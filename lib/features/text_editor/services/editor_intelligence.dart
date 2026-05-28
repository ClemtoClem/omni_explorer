/// @file editor_intelligence.dart
/// @brief Saisie intelligente pour le CodeEditor (inspiré de Xed-Editor).
///
/// Branché sur un [CodeLineEditingController], ce service réagit aux
/// modifications du texte (post-traitement, donc compatible clavier logiciel /
/// IME comme physique) pour :
///   - continuer automatiquement les listes Markdown (puces, numéros, cases,
///     citations) à l'appui sur Entrée, et supprimer une puce vide ;
///   - fermer automatiquement les paires (), [], {}, "", '', `` ;
///   - fermer automatiquement les balises HTML/XML <tag> → </tag>.

import 'package:re_editor/re_editor.dart';

class EditorIntelligence {
  final CodeLineEditingController controller;
  final bool bulletContinuation;
  final bool autoCloseBracket;
  final bool autoCloseTag;

  EditorIntelligence(
    this.controller, {
    this.bulletContinuation = false,
    this.autoCloseBracket = true,
    this.autoCloseTag = false,
  }) {
    _prev = controller.value;
    controller.addListener(_onChanged);
  }

  void dispose() => controller.removeListener(_onChanged);

  // ── Paires auto-fermantes ───────────────────────────────────────────────────
  static const Map<String, String> _pairs = {
    '(': ')', '[': ']', '{': '}', '"': '"', "'": "'", '`': '`',
  };

  // Éléments HTML sans balise fermante.
  static const Set<String> _voidTags = {
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
    'link', 'meta', 'param', 'source', 'track', 'wbr',
  };

  // ── Patterns Markdown ───────────────────────────────────────────────────────
  static final RegExp _emptyItem =
      RegExp(r'^\s*([-+*]|\d+[.)])(\s+\[[ xX]\])?\s*$');
  static final RegExp _ulItem =
      RegExp(r'^(\s*)([-+*])(\s+)(\[[ xX]\]\s+)?\S');
  static final RegExp _olItem =
      RegExp(r'^(\s*)(\d+)([.)])(\s+)(\[[ xX]\]\s+)?\S');
  static final RegExp _checkedBox = RegExp(r'\[[xX]\]');
  static final RegExp _tag = RegExp(r'<([a-zA-Z][\w:-]*)([^<>]*)>$');
  static final RegExp _word = RegExp(r'[A-Za-z0-9_]');

  CodeLineEditingValue? _prev;
  bool _busy = false;

  // ── Boucle de détection ─────────────────────────────────────────────────────

  void _onChanged() {
    if (_busy) return;
    final prev = _prev;
    final cur = controller.value;
    _prev = cur;
    if (prev == null || !cur.selection.isCollapsed) return;

    final lineDelta = cur.codeLines.length - prev.codeLines.length;
    if (lineDelta == 1) {
      if (bulletContinuation) _handleNewLine(cur);
    } else if (lineDelta == 0 && cur.selection.isSameLine) {
      _handleInsert(prev, cur);
    }
  }

  /// Exécute une modification du contrôleur sans ré-entrer dans le détecteur.
  void _apply(void Function() op) {
    _busy = true;
    try {
      op();
    } finally {
      _prev = controller.value;
      _busy = false;
    }
  }

  // ── Continuation de liste ───────────────────────────────────────────────────

  void _handleNewLine(CodeLineEditingValue cur) {
    final idx = cur.selection.extentIndex;
    if (idx <= 0 || idx >= cur.codeLines.length) return;
    final completed = cur.codeLines[idx - 1].text;

    // Puce / citation vide → on la supprime et on fusionne les deux lignes.
    if (_emptyItem.hasMatch(completed) || completed.trimRight() == '>') {
      _apply(() {
        controller.replaceSelection(
          '',
          CodeLineSelection(
            baseIndex: idx - 1,
            baseOffset: 0,
            extentIndex: idx,
            extentOffset: cur.codeLines[idx].length,
          ),
        );
      });
      return;
    }

    final marker = _nextMarker(completed);
    if (marker != null) {
      _apply(() => controller.replaceSelection(marker));
    }
  }

  /// Marqueur à insérer pour continuer la liste (l'indentation est déjà
  /// reportée par l'éditeur, on n'ajoute donc que le marqueur).
  String? _nextMarker(String line) {
    final ol = _olItem.firstMatch(line);
    if (ol != null) {
      final num = int.tryParse(ol.group(2)!) ?? 0;
      final cb = ol.group(5) ?? '';
      return '${num + 1}${ol.group(3)}${ol.group(4)}'
          '${cb.replaceAll(_checkedBox, '[ ]')}';
    }
    final ul = _ulItem.firstMatch(line);
    if (ul != null) {
      final cb = ul.group(4) ?? '';
      return '${ul.group(2)}${ul.group(3)}'
          '${cb.replaceAll(_checkedBox, '[ ]')}';
    }
    if (line.trimLeft().startsWith('>') && line.trim() != '>') {
      return '> ';
    }
    return null;
  }

  // ── Auto-fermeture ──────────────────────────────────────────────────────────

  void _handleInsert(CodeLineEditingValue prev, CodeLineEditingValue cur) {
    final sel = cur.selection;
    final idx = sel.extentIndex;
    final off = sel.extentOffset;
    if (off <= 0) return;
    if (prev.selection.extentIndex != idx) return;
    if (off != prev.selection.extentOffset + 1) return;

    final line = cur.codeLines[idx].text;
    if (off > line.length) return;
    final ch = line[off - 1];

    if (autoCloseTag && ch == '>') {
      _closeTag(idx, off, line);
      return;
    }
    if (autoCloseBracket && _pairs.containsKey(ch)) {
      _closeBracket(idx, off, line, ch);
    }
  }

  void _closeBracket(int idx, int off, String line, String open) {
    final close = _pairs[open]!;
    final after = off < line.length ? line[off] : '';
    // Ne pas fermer juste avant un mot (ex. taper « ( » devant « foo »).
    if (after.isNotEmpty && _word.hasMatch(after)) return;

    if (open == close) {
      // Guillemets : éviter les apostrophes de mots (don't) et le doublon.
      final before = off >= 2 ? line[off - 2] : '';
      if (before.isNotEmpty && _word.hasMatch(before)) return;
      if (after == close) return;
    }
    _insertClosing(idx, off, close);
  }

  void _closeTag(int idx, int off, String line) {
    final m = _tag.firstMatch(line.substring(0, off));
    if (m == null) return;
    final attrs = m.group(2) ?? '';
    if (attrs.trimRight().endsWith('/')) return; // auto-fermante <br/>
    final tag = m.group(1)!;
    if (_voidTags.contains(tag.toLowerCase())) return;
    _insertClosing(idx, off, '</$tag>');
  }

  /// Insère [closing] après le curseur puis replace le curseur entre les deux.
  void _insertClosing(int idx, int off, String closing) {
    _apply(() {
      controller.replaceSelection(closing);
      controller.value = controller.value.copyWith(
        selection: CodeLineSelection.collapsed(index: idx, offset: off),
      );
    });
  }
}
