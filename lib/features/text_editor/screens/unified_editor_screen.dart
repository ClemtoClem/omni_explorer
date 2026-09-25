/// @file unified_editor_screen.dart
/// @brief Éditeur unifié : code, markdown, texte, texte enrichi et hexadécimal, similaire à VS Code.
///
/// Modes d'affichage par onglet :
///   code      – CodeEditor (re_editor) + coloration syntaxique + autocomplétion
///   markdown  – Source éditable OU aperçu rendu (flutter_markdown)
///   text      – Texte brut (lecture seule : SelectableText, édition : TextField)
///   richText  – Texte enrichi (gras/italique/souligné/couleur via barre d'outils)
///   hex       – Grille offset / hex / ASCII avec édition octet par octet
///
/// Comportement :
///   - Fichier ouvert en lecture seule par défaut
///   - Double-tap sur l'onglet → passe en mode édition
///   - Mode Workspace : arborescence latérale + .workspace.json à la racine
///   - Barre d'autocomplétion : mots-clés du langage + symboles du fichier courant
///     + symboles du workspace

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart' as re_dark;
import 'package:re_highlight/styles/atom-one-light.dart' as re_light;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/atomic_write.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/system_ui.dart';
import '../../../core/widgets/custom_keyboard.dart';
import '../languages/language_registry.dart';
import '../widgets/terminal_panel.dart';
import '../completions/language_completions.dart';
import '../models/editor_view_mode.dart';
import '../models/workspace_settings.dart';
import '../services/editor_intelligence.dart';
import '../services/editor_open_policy.dart';
import '../services/hex_file_io.dart';
import '../services/workspace_service.dart';
import 'workspace_settings_screen.dart';

export '../models/editor_view_mode.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────


const int _hexBytesPerRow = 8;

// ─── Formatage texte enrichi ──────────────────────────────────────────────────

enum _RichFmt { bold, italic, underline, strikethrough }

class _FmtSpan {
  int start;
  int end;
  final Set<_RichFmt> formats;
  final Color? textColor;

  _FmtSpan(this.start, this.end, this.formats, [this.textColor]);

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'formats': formats.map((f) => f.index).toList(),
        if (textColor != null) 'color': textColor!.toARGB32(),
      };

  factory _FmtSpan.fromJson(Map<String, dynamic> j) => _FmtSpan(
        j['start'] as int,
        j['end'] as int,
        (j['formats'] as List?)
                ?.map((i) => _RichFmt.values[i as int])
                .toSet() ??
            {},
        j['color'] != null ? Color(j['color'] as int) : null,
      );
}

class _RichTextController extends TextEditingController {
  final List<_FmtSpan> spans = [];

  _RichTextController({super.text});

  void toggleFormat(_RichFmt fmt, int start, int end) {
    if (start >= end) return;
    final hasAll = spans.any(
        (s) => s.start <= start && s.end >= end && s.formats.contains(fmt));
    if (hasAll) {
      spans.removeWhere((s) => s.start >= start && s.end <= end);
    } else {
      _merge(_FmtSpan(start, end, {fmt}));
    }
    notifyListeners();
  }

  void setTextColor(Color? color, int start, int end) {
    if (start >= end) return;
    _merge(_FmtSpan(start, end, {}, color));
    notifyListeners();
  }

  void clearRange(int start, int end) {
    spans.removeWhere((s) => s.start >= start && s.end <= end);
    notifyListeners();
  }

  void _merge(_FmtSpan s) {
    spans.removeWhere((e) => e.start >= s.start && e.end <= s.end);
    spans.add(s);
  }

  String get formattingJson =>
      jsonEncode(spans.map((s) => s.toJson()).toList());

  void loadFromJson(String json) {
    spans.clear();
    try {
      final list = jsonDecode(json) as List;
      spans.addAll(list.map((e) => _FmtSpan.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final src = text;
    if (src.isEmpty || spans.isEmpty) return TextSpan(text: src, style: style);
    final base = style ?? const TextStyle();
    final cs = List<TextStyle>.filled(src.length, base);
    for (final sp in spans) {
      final s = sp.start.clamp(0, src.length);
      final e = sp.end.clamp(0, src.length);
      for (int i = s; i < e; i++) {
        cs[i] = cs[i].copyWith(
          fontWeight:
              sp.formats.contains(_RichFmt.bold) ? FontWeight.bold : null,
          fontStyle:
              sp.formats.contains(_RichFmt.italic) ? FontStyle.italic : null,
          decoration: _deco(sp.formats),
          color: sp.textColor,
        );
      }
    }
    final result = <InlineSpan>[];
    int i = 0;
    while (i < src.length) {
      int j = i + 1;
      while (j < src.length && cs[j] == cs[i]) { j++; }
      result.add(TextSpan(text: src.substring(i, j), style: cs[i]));
      i = j;
    }
    return TextSpan(children: result, style: base);
  }

  TextDecoration? _deco(Set<_RichFmt> f) {
    final parts = <TextDecoration>[];
    if (f.contains(_RichFmt.underline)) parts.add(TextDecoration.underline);
    if (f.contains(_RichFmt.strikethrough)) parts.add(TextDecoration.lineThrough);
    return parts.isEmpty ? null : TextDecoration.combine(parts);
  }
}

// ─── Adaptateur CodeEditor ↔ CustomKeyboard ───────────────────────────────────

class _CodeCtrlAdapter {
  CodeLineEditingController codeCtrl;
  _CodeCtrlAdapter(this.codeCtrl);

  TextEditingValue get value {
    final text = codeCtrl.text;
    final sel = codeCtrl.selection;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: _toFlat(text, sel.baseIndex, sel.baseOffset),
        extentOffset: _toFlat(text, sel.extentIndex, sel.extentOffset),
      ),
    );
  }

  set value(TextEditingValue val) {
    codeCtrl.text = val.text;
    final base = _toLC(val.text, val.selection.baseOffset);
    final ext = _toLC(val.text, val.selection.extentOffset);
    codeCtrl.selection = CodeLineSelection(
      baseIndex: base.$1,
      baseOffset: base.$2,
      extentIndex: ext.$1,
      extentOffset: ext.$2,
    );
  }

  int _toFlat(String t, int line, int col) {
    final lines = t.split('\n');
    int off = 0;
    for (int i = 0; i < line && i < lines.length; i++) {
      off += lines[i].length + 1;
    }
    return off + col;
  }

  (int, int) _toLC(String t, int flat) {
    if (flat <= 0) return (0, 0);
    final lines = t.split('\n');
    int cur = 0;
    for (int i = 0; i < lines.length; i++) {
      if (cur + lines[i].length >= flat) return (i, flat - cur);
      cur += lines[i].length + 1;
    }
    return (lines.length - 1, lines.last.length);
  }
}

// ─── Modèle d'onglet ──────────────────────────────────────────────────────────

class _UTab {
  final String path;
  String content;
  bool isDirty = false;
  bool isReadOnly;
  EditorViewMode viewMode;
  LanguageDefinition? lang;

  CodeLineEditingController? codeCtrl;
  TextEditingController? textCtrl;
  _RichTextController? richCtrl;
  EditorIntelligence? intel;

  bool showMdPreview;

  // État hexadécimal
  Uint8List? bytes;
  int hexSelectedOffset;
  bool hexModified;
  /// Taille du fichier sur le disque au chargement des octets.
  int hexFileLength;
  TextEditingController? hexInputCtrl;
  FocusNode? hexInputFocus;
  ScrollController? hexScrollCtrl;

  _UTab({
    required this.path,
    required this.content,
    this.isReadOnly = true,
    required this.viewMode,
    this.lang,
  })  : showMdPreview = viewMode == EditorViewMode.markdown,
        hexSelectedOffset = -1,
        hexModified = false,
        hexFileLength = 0 {
    _init();
  }

  String get name => p.basename(path);

  /// Vrai si seul le début du fichier est chargé en hexadécimal : l'onglet
  /// doit alors rester en lecture seule.
  bool get hexTruncated => bytes != null && bytes!.length < hexFileLength;

  void _init() {
    switch (viewMode) {
      case EditorViewMode.code:
      case EditorViewMode.markdown:
        codeCtrl = CodeLineEditingController.fromText(content);
        final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
        final isMarkdown = viewMode == EditorViewMode.markdown;
        intel = EditorIntelligence(
          codeCtrl!,
          bulletContinuation: isMarkdown,
          autoCloseBracket: true,
          autoCloseTag: isMarkdown ||
              const {'html', 'htm', 'xml', 'svg', 'vue', 'xhtml', 'jsx', 'tsx'}
                  .contains(ext),
        );
        break;
      case EditorViewMode.text:
        textCtrl = TextEditingController(text: content);
        break;
      case EditorViewMode.richText:
        richCtrl = _RichTextController(text: content);
        break;
      case EditorViewMode.hex:
        hexInputCtrl = TextEditingController();
        hexInputFocus = FocusNode();
        hexScrollCtrl = ScrollController();
        break;
    }
  }

  void switchMode(EditorViewMode newMode) {
    if (newMode == viewMode) return;
    _dispose();
    viewMode = newMode;
    _init();
  }

  void _dispose() {
    intel?.dispose();
    intel = null;
    codeCtrl?.dispose();
    codeCtrl = null;
    textCtrl?.dispose();
    textCtrl = null;
    richCtrl?.dispose();
    richCtrl = null;
    hexInputCtrl?.dispose();
    hexInputCtrl = null;
    hexInputFocus?.dispose();
    hexInputFocus = null;
    hexScrollCtrl?.dispose();
    hexScrollCtrl = null;
  }

  void dispose() => _dispose();
}

// ─── Nœud arborescence projet ─────────────────────────────────────────────────

class _ProjNode {
  final String path;
  final String name;
  final bool isDir;
  final int depth;
  bool expanded = false;
  List<_ProjNode> children = const [];

  _ProjNode({
    required this.path,
    required this.name,
    required this.isDir,
    required this.depth,
  });
}

// ─── Provider état persistant ─────────────────────────────────────────────────

/// Conserve les onglets ouverts entre les navigations vers l'explorateur.
// ignore: library_private_types_in_public_api
class UnifiedEditorProvider extends ChangeNotifier {
  // ignore: library_private_types_in_public_api
  final List<_UTab> tabs = [];
  int activeTabIndex = 0;
  bool isWorkspace = false;
  String workspacePath = '';
  WorkspaceSettings ws = const WorkspaceSettings();
  // ignore: library_private_types_in_public_api
  List<_ProjNode> tree = [];
  bool showTree = true;

  // ignore: library_private_types_in_public_api
  _UTab? get activeTab =>
      tabs.isEmpty || activeTabIndex >= tabs.length ? null : tabs[activeTabIndex];

  int indexOfPath(String path) => tabs.indexWhere((t) => t.path == path);

  // ignore: library_private_types_in_public_api
  void addTab(_UTab tab) {
    tabs.add(tab);
    activeTabIndex = tabs.length - 1;
    notifyListeners();
  }

  void removeTab(int index) {
    tabs[index].dispose();
    tabs.removeAt(index);
    if (activeTabIndex >= tabs.length && activeTabIndex > 0) {
      activeTabIndex = tabs.length - 1;
    }
    notifyListeners();
  }

  void setActiveTabIndex(int index) {
    if (index >= 0 && index < tabs.length) {
      activeTabIndex = index;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final t in tabs) { t.dispose(); }
    super.dispose();
  }
}

// ─── Écran principal ──────────────────────────────────────────────────────────

class UnifiedEditorScreen extends StatefulWidget {
  final List<String> filePaths;
  final String? workspacePath;
  final bool forceHex;

  const UnifiedEditorScreen({
    super.key,
    required this.filePaths,
    this.workspacePath,
    this.forceHex = false,
  });

  @override
  State<UnifiedEditorScreen> createState() => _UnifiedEditorState();
}

class _UnifiedEditorState extends State<UnifiedEditorScreen>
    with TickerProviderStateMixin {

  // ── État persistant (survit aux navigations) ──────────────────────────────

  late UnifiedEditorProvider _p;

  // ── Terminal ──────────────────────────────────────────────────────────────

  bool _showTerminal = false;
  final List<String> _termLines = [];
  Process? _runProcess;

  // ── Recherche ─────────────────────────────────────────────────────────────

  bool _showSearch = false;
  final _searchCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();

  // ── Autocomplétion ────────────────────────────────────────────────────────

  List<String> _completions = [];
  List<String> _wsSymbols = [];

  // ── Clavier custom ────────────────────────────────────────────────────────

  final FocusNode _editorFocus = FocusNode();
  _CodeCtrlAdapter? _kbAdapter;

  // ── Couleur texte enrichi (dernière sélection) ────────────────────────────

  Color _richColor = Colors.red;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemUI.hideBottomBar();
    LanguageRegistry.instance.initDefaults();
    _p = context.read<UnifiedEditorProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<SettingsService>();
      // Applique les polices globales si aucun workspace n'a déjà configuré les siennes.
      if (!_p.isWorkspace) {
        _p.ws = _p.ws.copyWith(
          fontFamily: _fontFamilyKey(s.codeFontFamily),
          fontSize: s.codeFontSize,
        );
      }

      if (widget.workspacePath != null) {
        await _openWorkspace(widget.workspacePath!);
      }
      for (final path in widget.filePaths) {
        if (FileSystemEntity.isDirectorySync(path)) {
          await _openWorkspace(path);
        } else {
          await _openFile(path);
        }
      }
    });
  }

  @override
  void dispose() {
    // Les onglets sont conservés dans UnifiedEditorProvider — pas de dispose ici.
    _searchCtrl.dispose();
    _replaceCtrl.dispose();
    _editorFocus.dispose();
    _runProcess?.kill();
    super.dispose();
  }

  // ── Workspace ─────────────────────────────────────────────────────────────

  Future<void> _openWorkspace(String dir) async {
    final settings = await WorkspaceService.load(dir);
    final tree = await _buildTree(dir, 0, settings.excludePatterns);
    if (!mounted) return;
    setState(() {
      _p.isWorkspace = true;
      _p.workspacePath = dir;
      _p.ws = settings;
      _p.tree = tree;
      _p.showTree = true;
    });
    _scanWorkspaceSymbols(dir);
  }

  /// Collecte les symboles des fichiers de code du projet (autocomplétion).
  /// Bornée : fichiers volumineux ignorés, nombre de fichiers limité.
  Future<void> _scanWorkspaceSymbols(String dir) async {
    final symbols = <String>{};
    var scanned = 0;
    try {
      await for (final e
          in Directory(dir).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final ext = FileUtils.extOf(e.path);
        final lang = LanguageRegistry.instance.forExtension(ext);
        if (lang == null) continue;
        if (scanned >= EditorLimits.symbolScanMaxFiles) break;
        try {
          if (await e.length() > EditorLimits.symbolScanMaxFileBytes) continue;
          scanned++;
          final content = await e.readAsString();
          symbols.addAll(LanguageCompletions.extractSymbols(content, lang.id));
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _wsSymbols = symbols.toList());
  }

  // ── Gestion des fichiers ──────────────────────────────────────────────────

  Future<void> _openFile(String path) async {
    final idx = _p.tabs.indexWhere((t) => t.path == path);
    if (idx >= 0) {
      setState(() {
        _p.activeTabIndex = idx;
        _syncKb();
      });
      return;
    }

    final ext = FileUtils.extOf(path);
    final lang = LanguageRegistry.instance.forExtension(ext);

    // Taille et nature du fichier AVANT de le lire : un fichier trop gros
    // ou binaire ne doit jamais être chargé en entier comme texte.
    final FileProbe probe;
    try {
      probe = await FileProbe.of(path);
    } on FileSystemException catch (e) {
      _showErr('Lecture impossible : ${e.message}');
      return;
    }
    final decision = EditorOpenPolicy.decide(probe, _detectMode(ext),
        forceHex: widget.forceHex);
    if (decision.block != null &&
        !await _confirmHexPreview(path, probe, decision.block!)) {
      return;
    }
    final mode = decision.mode;
    if (decision.notice != null) _snack(decision.notice!);

    _UTab tab;
    if (mode == EditorViewMode.hex) {
      tab = _UTab(
          path: path, content: '', isReadOnly: true, viewMode: mode, lang: lang);
      if (!await _loadHexBytes(tab, path)) {
        tab.dispose();
        return;
      }
    } else {
      String content = '';
      try {
        content = await File(path).readAsString();
      } catch (e) {
        _showErr('Lecture impossible : $e');
        return;
      }
      tab = _UTab(
          path: path,
          content: content,
          isReadOnly: true,
          viewMode: mode,
          lang: lang);
      if (mode == EditorViewMode.richText) await _loadRichFmt(tab);
      _attachListeners(tab);
    }

    if (!mounted) return;
    setState(() {
      _p.tabs.add(tab);
      _p.activeTabIndex = _p.tabs.length - 1;
      _syncKb();
    });
    if (mounted) {
      context.read<SettingsService>().addRecentFile(path);
    }
  }

  /// Fichier non affichable en texte : propose l'aperçu hexadécimal.
  Future<bool> _confirmHexPreview(
      String path, FileProbe probe, TextBlock block) async {
    if (!mounted) return false;
    final why = switch (block) {
      TextBlock.tooLarge =>
        '« ${p.basename(path)} » fait ${FileUtils.formatSize(probe.size)} : '
            'trop pour l\'éditeur de texte (limite : '
            '${FileUtils.formatSize(EditorLimits.textMaxBytes)}).',
      TextBlock.longLines =>
        '« ${p.basename(path)} » contient une ligne de plus de '
            '${EditorLimits.maxLineBytes ~/ 1024} Kio (fichier minifié ?) : '
            'l\'afficher en texte figerait l\'application.',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Fichier volumineux'),
        content: Text(
            '$why\n\n'
            'L\'ouvrir en hexadécimal ? Au-delà de '
            '${FileUtils.formatSize(HexFileIO.maxLoadedBytes)}, seul le début '
            'est affiché, en lecture seule.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Hexadécimal')),
        ],
      ),
    );
    return ok == true;
  }

  EditorViewMode _detectMode(String ext) {
    switch (ext.toLowerCase()) {
      case 'md':
      case 'markdown':
        return EditorViewMode.markdown;
      case 'doc':
      case 'docx':
      case 'rtf':
      case 'odt':
        return EditorViewMode.richText;
      case 'txt':
      case 'log':
      case 'ini':
      case 'cfg':
      case 'conf':
      case 'env':
        return EditorViewMode.text;
      default:
        final lang = LanguageRegistry.instance.forExtension(ext);
        if (lang != null && lang.id != 'plaintext' && lang.id != 'markdown') {
          return EditorViewMode.code;
        }
        return EditorViewMode.text;
    }
  }

  /// Charge (ou recharge depuis le disque) les octets de [tab].
  /// Retourne `false` si la lecture a échoué (erreur déjà affichée).
  Future<bool> _loadHexBytes(_UTab tab, String path) async {
    try {
      final loaded = await HexFileIO.load(path);
      tab.bytes = loaded.bytes;
      tab.hexFileLength = loaded.fileLength;
      tab.hexSelectedOffset = -1;
      tab.hexModified = false;
      if (loaded.isTruncated) tab.isReadOnly = true;
      return true;
    } catch (e) {
      _showErr('Lecture hex impossible : $e');
      return false;
    }
  }

  Future<void> _loadRichFmt(_UTab tab) async {
    final fmtFile = File('${tab.path}.fmt');
    if (fmtFile.existsSync()) {
      try {
        tab.richCtrl?.loadFromJson(await fmtFile.readAsString());
      } catch (_) {}
    }
  }

  void _attachListeners(_UTab tab) {
    tab.codeCtrl?.addListener(() => _updateCompletions(tab));
    tab.textCtrl?.addListener(() => _updateCompletionsTxt(tab));
    tab.richCtrl?.addListener(() => _updateCompletionsTxt(tab));
  }

  // ── Sauvegarde ────────────────────────────────────────────────────────────

  Future<void> _save([int? idx]) async {
    final tab = idx != null
        ? (_p.tabs.length > idx ? _p.tabs[idx] : null)
        : _p.activeTab;
    if (tab == null) return;

    if (tab.viewMode == EditorViewMode.hex) {
      if (tab.bytes == null || !tab.hexModified) return;
      try {
        await HexFileIO.save(tab.path, tab.bytes!,
            loadedFileLength: tab.hexFileLength);
        if (mounted) {
          setState(() {
            tab.hexModified = false;
            tab.isDirty = false;
          });
        }
        _snack('Fichier sauvegardé');
      } on HexSaveRefused catch (e) {
        _showErr(e.message);
      } catch (e) {
        _showErr('Sauvegarde hex impossible : $e');
      }
      return;
    }

    final newContent = switch (tab.viewMode) {
      EditorViewMode.code || EditorViewMode.markdown =>
        tab.codeCtrl?.text ?? tab.content,
      EditorViewMode.text => tab.textCtrl?.text ?? tab.content,
      EditorViewMode.richText => tab.richCtrl?.text ?? tab.content,
      _ => tab.content,
    };

    try {
      // Écriture atomique : une interruption (application tuée, stockage
      // plein) laisse l'ancien contenu intact au lieu d'un fichier tronqué.
      await AtomicWrite.string(tab.path, newContent);
      tab.content = newContent;
      if (tab.viewMode == EditorViewMode.richText && tab.richCtrl != null) {
        await AtomicWrite.string(
            '${tab.path}.fmt', tab.richCtrl!.formattingJson);
      }
      if (mounted) setState(() => tab.isDirty = false);
      _snack('Fichier sauvegardé');
    } catch (e) {
      _showErr('Sauvegarde impossible : $e');
    }
  }

  // ── Fermeture d'onglet ────────────────────────────────────────────────────

  Future<void> _closeTab(int idx) async {
    final tab = _p.tabs[idx];
    if (tab.isDirty || tab.hexModified) {
      final res = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Modifications non sauvegardées'),
          content: Text('Sauvegarder « ${tab.name} » ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: const Text('Abandonner')),
            TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: const Text('Sauvegarder')),
          ],
        ),
      );
      if (res == 'cancel') return;
      if (res == 'save') await _save(idx);
    }
    if (!mounted) return;
    setState(() {
      _p.tabs[idx].dispose();
      _p.tabs.removeAt(idx);
      if (_p.activeTabIndex >= _p.tabs.length && _p.activeTabIndex > 0) {
        _p.activeTabIndex = _p.tabs.length - 1;
      }
      _syncKb();
    });
  }

  void _enableEdit(int idx) {
    final tab = _p.tabs[idx];
    if (tab.viewMode == EditorViewMode.hex && tab.hexTruncated) {
      _snack('Fichier trop volumineux : seul le début est affiché, '
          'en lecture seule.');
      return;
    }
    if (tab.isReadOnly) setState(() => tab.isReadOnly = false);
  }

  /// Change la représentation de l'onglet actif.
  ///
  /// Entre modes texte (code, markdown, texte, enrichi), le texte en cours est
  /// transmis tel quel. Vers ou depuis l'hexadécimal, le contenu est RELU
  /// depuis le disque : texte et octets ne sont pas synchronisés en mémoire,
  /// et réutiliser l'un pour l'autre afficherait un document vide ou périmé
  /// qui, une fois sauvegardé, écraserait le fichier. Les modifications non
  /// sauvegardées doivent donc l'être avant ce changement.
  Future<void> _switchViewMode(EditorViewMode mode) async {
    final tab = _p.activeTab;
    if (tab == null || tab.viewMode == mode) return;
    final fromHex = tab.viewMode == EditorViewMode.hex;
    final toHex = mode == EditorViewMode.hex;

    // Nature du fichier sur le disque : les limites de l'ouverture valent
    // aussi ici. Entre modes texte, le disque n'est pas nécessaire (fichier
    // supprimé ailleurs) : on se rabat sur le texte en mémoire.
    FileProbe probe;
    try {
      probe = await FileProbe.of(tab.path);
    } on FileSystemException catch (e) {
      if (fromHex || toHex) {
        _showErr('Lecture impossible : ${e.message}');
        return;
      }
      probe = FileProbe.ofText(tab.content);
    }
    if (!mounted) return;
    final refused = EditorOpenPolicy.refuseSwitch(probe, mode);
    if (refused != null) {
      _showErr(refused);
      return;
    }

    if (!fromHex && !toHex) {
      final cur = switch (tab.viewMode) {
        EditorViewMode.code || EditorViewMode.markdown =>
          tab.codeCtrl?.text ?? tab.content,
        EditorViewMode.text => tab.textCtrl?.text ?? tab.content,
        EditorViewMode.richText => tab.richCtrl?.text ?? tab.content,
        _ => tab.content,
      };
      setState(() {
        tab.content = cur;
        tab.switchMode(mode);
        _attachListeners(tab);
        _syncKb();
      });
      return;
    }

    if (tab.isDirty || tab.hexModified) {
      _showErr('Sauvegardez d\'abord vos modifications : le passage '
          '${toHex ? 'en ' : 'depuis l\''}hexadécimal relit le fichier sur '
          'le disque.');
      return;
    }

    if (toHex) {
      if (!await _loadHexBytes(tab, tab.path) || !mounted) return;
      setState(() {
        tab.content = '';
        tab.switchMode(mode);
        _syncKb();
      });
      return;
    }

    // Depuis l'hexadécimal vers un mode texte : relire le texte.
    // Lecture et décodage séparés : readAsString signale un décodage raté
    // par une FileSystemException, indiscernable d'une erreur d'accès.
    final List<int> raw;
    try {
      raw = await File(tab.path).readAsBytes();
    } on FileSystemException catch (e) {
      _showErr('Lecture impossible : ${e.message}');
      return;
    }
    final String text;
    try {
      text = utf8.decode(raw);
    } on FormatException {
      _showErr('Ce fichier n\'est pas du texte UTF-8 : il reste affiché en '
          'hexadécimal.');
      return;
    }
    if (!mounted) return;
    setState(() {
      tab.content = text;
      tab.bytes = null; // libère le tampon binaire
      tab.hexFileLength = 0;
      tab.switchMode(mode);
      _attachListeners(tab);
      _syncKb();
    });
  }

  // ── Polices ───────────────────────────────────────────────────────────────

  /// Retourne la clé fontFamily enregistrée par Google Fonts pour [displayName].
  /// Ex: 'JetBrains Mono' → 'JetBrainsMono', 'Roboto Mono' → 'RobotoMono'.
  String _fontFamilyKey(String displayName) {
    try {
      return GoogleFonts.getFont(displayName).fontFamily ?? displayName;
    } catch (_) {
      return displayName.replaceAll(' ', '');
    }
  }

  /// Construit un [TextStyle] à partir d'un nom Google Fonts.
  TextStyle _googleFontStyle(String family, {
    required double size,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
  }) {
    try {
      return GoogleFonts.getFont(family,
          fontSize: size, color: color, fontWeight: weight, height: height);
    } catch (_) {
      return TextStyle(fontSize: size, color: color, fontWeight: weight, height: height);
    }
  }

  void _syncKb() {
    final tab = _p.activeTab;
    if (tab?.codeCtrl != null) {
      _kbAdapter = _CodeCtrlAdapter(tab!.codeCtrl!);
    } else {
      _kbAdapter = null;
    }
  }

  // ── Autocomplétion ────────────────────────────────────────────────────────

  void _updateCompletions(_UTab tab) {
    final ctrl = tab.codeCtrl;
    if (ctrl == null) return;
    final flat = _codeFlat(ctrl);
    final word = _wordAt(ctrl.text, flat);
    _refreshSuggestions(word, tab);
  }

  void _updateCompletionsTxt(_UTab tab) {
    final ctrl = tab.textCtrl ?? tab.richCtrl;
    if (ctrl == null) return;
    final word = _wordAt(ctrl.text, ctrl.selection.baseOffset);
    _refreshSuggestions(word, tab);
  }

  void _refreshSuggestions(String word, _UTab tab) {
    final sug = LanguageCompletions.getSuggestions(
      prefix: word,
      languageId: tab.lang?.id ?? 'plaintext',
      currentFileContent: tab.content,
      workspaceSymbols: _wsSymbols,
    );
    if (mounted && sug != _completions) setState(() => _completions = sug);
  }

  int _codeFlat(CodeLineEditingController c) {
    final t = c.text;
    final s = c.selection;
    int off = 0;
    final lines = t.split('\n');
    for (int i = 0; i < s.baseIndex && i < lines.length; i++) {
      off += lines[i].length + 1;
    }
    return off + s.baseOffset;
  }

  String _wordAt(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return '';
    int start = cursor;
    while (start > 0 && RegExp(r'[\w$]').hasMatch(text[start - 1])) {
      start--;
    }
    return text.substring(start, cursor);
  }

  void _insertCompletion(String comp) {
    final tab = _p.activeTab;
    if (tab == null) return;
    if (tab.codeCtrl != null) {
      final c = tab.codeCtrl!;
      final flat = _codeFlat(c);
      final word = _wordAt(c.text, flat);
      final suffix = comp.substring(word.length);
      final newText = c.text.substring(0, flat) + suffix + c.text.substring(flat);
      final lc = _toLC(newText, flat + suffix.length);
      c.text = newText;
      c.selection = CodeLineSelection.collapsed(index: lc.$1, offset: lc.$2);
    } else {
      final ctrl = tab.textCtrl ?? tab.richCtrl;
      if (ctrl == null) return;
      final cursor = ctrl.selection.baseOffset;
      final word = _wordAt(ctrl.text, cursor);
      final suffix = comp.substring(word.length);
      final newText =
          ctrl.text.substring(0, cursor) + suffix + ctrl.text.substring(cursor);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor + suffix.length),
      );
    }
    setState(() => _completions = []);
  }

  (int, int) _toLC(String t, int flat) {
    final lines = t.split('\n');
    int cur = 0;
    for (int i = 0; i < lines.length; i++) {
      if (cur + lines[i].length >= flat) return (i, flat - cur);
      cur += lines[i].length + 1;
    }
    return (lines.length - 1, lines.last.length);
  }

  // ── Exécution ─────────────────────────────────────────────────────────────

  Future<void> _run() async {
    final tab = _p.activeTab;
    if (tab?.lang?.isRunnable != true) return;
    if (tab!.isDirty) await _save();
    setState(() {
      _showTerminal = true;
      _termLines
        ..clear()
        ..add('> ${tab.lang!.runCommand} ${tab.name}')
        ..add('');
    });
    try {
      _runProcess = await Process.start(
        tab.lang!.runCommand!,
        [...tab.lang!.runArgs, tab.path],
        workingDirectory: _p.isWorkspace ? _p.workspacePath : p.dirname(tab.path),
      );
      _runProcess!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((d) {
        if (mounted) setState(() => _termLines.addAll(d.split('\n')));
      });
      _runProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((d) {
        if (mounted) setState(() => _termLines.addAll(d.split('\n')));
      });
      _runProcess!.exitCode.then((code) {
        if (mounted) setState(() => _termLines.add('\n> Terminé (code $code)'));
      });
    } catch (e) {
      setState(() => _termLines.add('Erreur : $e'));
    }
  }

  void _stopProcess() {
    _runProcess?.kill();
    _runProcess = null;
    setState(() => _termLines.add('\n> Processus arrêté'));
  }

  // ── Arborescence ──────────────────────────────────────────────────────────

  Future<List<_ProjNode>> _buildTree(
      String dir, int depth, List<String> excl) async {
    if (depth > 8) return [];
    final nodes = <_ProjNode>[];
    try {
      final entities = Directory(dir).listSync()
        ..sort((a, b) {
          final ad = a is Directory ? 0 : 1;
          final bd = b is Directory ? 0 : 1;
          if (ad != bd) return ad - bd;
          return p.basename(a.path).compareTo(p.basename(b.path));
        });
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.') || excl.any((x) => name == x)) continue;
        nodes.add(_ProjNode(
          path: e.path,
          name: name,
          isDir: e is Directory,
          depth: depth,
        ));
      }
    } catch (_) {}
    return nodes;
  }

  Future<void> _toggleNode(_ProjNode node) async {
    if (!node.isDir) return;
    if (node.expanded) {
      setState(() => node.expanded = false);
    } else {
      final children =
          await _buildTree(node.path, node.depth + 1, _p.ws.excludePatterns);
      setState(() {
        node.expanded = true;
        node.children = children;
      });
    }
  }

  // ── Hex ───────────────────────────────────────────────────────────────────

  void _hexSelect(_UTab tab, int offset) {
    if (tab.bytes == null || offset >= tab.bytes!.length) return;
    setState(() => tab.hexSelectedOffset = offset);
    final hex =
        tab.bytes![offset].toRadixString(16).padLeft(2, '0').toUpperCase();
    tab.hexInputCtrl?.text = hex;
    tab.hexInputCtrl?.selection =
        TextSelection(baseOffset: 0, extentOffset: hex.length);
    tab.hexInputFocus?.requestFocus();
    _hexScroll(tab, offset);
  }

  void _hexApply(_UTab tab) {
    final text = tab.hexInputCtrl?.text.trim() ?? '';
    if (text.length != 2) return;
    final val = int.tryParse(text, radix: 16);
    if (val == null || tab.bytes == null || tab.hexSelectedOffset < 0) return;
    setState(() {
      tab.bytes![tab.hexSelectedOffset] = val;
      tab.hexModified = true;
      tab.isDirty = true;
    });
  }

  void _hexNav(_UTab tab, int delta) {
    if (tab.bytes == null) return;
    final next = tab.hexSelectedOffset + delta;
    if (next < 0 || next >= tab.bytes!.length) return;
    _hexSelect(tab, next);
  }

  void _hexScroll(_UTab tab, int offset) {
    final sc = tab.hexScrollCtrl;
    if (sc == null || !sc.hasClients) return;
    final row = offset ~/ _hexBytesPerRow;
    const rowH = 28.0;
    final target = row * rowH;
    final viewH = sc.position.viewportDimension;
    final cur = sc.offset;
    if (target < cur || target + rowH > cur + viewH) {
      sc.animateTo(
        (target - viewH / 2 + rowH / 2).clamp(0, sc.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Recherche / Remplacement ──────────────────────────────────────────────

  void _replaceNext() {
    final tab = _p.activeTab;
    if (tab == null) return;
    final q = _searchCtrl.text;
    final r = _replaceCtrl.text;
    if (q.isEmpty) return;
    if (tab.codeCtrl != null) {
      final c = tab.codeCtrl!;
      final newText = c.text.replaceFirst(q, r);
      if (newText != c.text) {
        c.text = newText;
        setState(() => tab.isDirty = true);
      }
    } else {
      final ctrl = tab.textCtrl ?? tab.richCtrl;
      if (ctrl == null) return;
      final newText = ctrl.text.replaceFirst(q, r);
      if (newText != ctrl.text) {
        ctrl.text = newText;
        setState(() => tab.isDirty = true);
      }
    }
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    context.watch<UnifiedEditorProvider>(); // rebuild quand les onglets changent
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settings = context.watch<SettingsService>();
    final useKb = _p.activeTab?.viewMode != EditorViewMode.hex &&
        !kIsWeb &&
        Platform.isAndroid &&
        (_p.ws.useCustomKeyboard ?? settings.useCustomKeyboard);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme),
      body: Column(
        children: [
          if (_p.tabs.isNotEmpty) _buildTabBar(theme),
          Expanded(
            child: Row(
              children: [
                if (_p.isWorkspace && _p.showTree) _buildProjectPanel(theme),
                Expanded(
                  child: Column(
                    children: [
                      if (_showSearch) _buildSearchBar(theme),
                      Expanded(child: _buildEditorContent(theme, isDark)),
                      if (_completions.isNotEmpty) _buildCompletionBar(theme),
                      if (_showTerminal)
                        TerminalPanel(
                          output: _termLines,
                          onClear: () => setState(() => _termLines.clear()),
                          onClose: () => setState(() => _showTerminal = false),
                          onStop: _runProcess != null ? _stopProcess : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (useKb && _kbAdapter != null)
            CustomKeyboard(
              focusNode: _editorFocus,
              controller: _kbAdapter,
            ),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(ThemeData theme) {
    final tab = _p.activeTab;
    return AppBar(
      leading: _p.isWorkspace
          ? IconButton(
              icon: Icon(_p.showTree
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined),
              iconSize: 20,
              onPressed: () => setState(() => _p.showTree = !_p.showTree),
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tab != null) ...[
            Flexible(
              child: Text(
                tab.name + (tab.isDirty || tab.hexModified ? ' •' : ''),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 6),
            _ModeBadge(tab: tab),
            if (!tab.isReadOnly)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('EDIT',
                    style: TextStyle(
                        fontSize: 9,
                        color: AppColors.success,
                        fontWeight: FontWeight.w700)),
              ),
          ] else
            Text(
              _p.isWorkspace ? p.basename(_p.workspacePath) : 'Éditeur',
              style: theme.textTheme.titleMedium,
            ),
        ],
      ),
      actions: [
        if (tab != null)
          PopupMenuButton<EditorViewMode>(
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            tooltip: 'Mode d\'interprétation',
            onSelected: _switchViewMode,
            itemBuilder: (_) => [
              _modeItem(EditorViewMode.code, Icons.code_rounded, 'Code', tab),
              _modeItem(EditorViewMode.markdown, Icons.article_rounded,
                  'Markdown', tab),
              _modeItem(
                  EditorViewMode.text, Icons.text_snippet_outlined, 'Texte', tab),
              _modeItem(EditorViewMode.richText, Icons.format_color_text_rounded,
                  'Texte enrichi', tab),
              _modeItem(
                  EditorViewMode.hex, Icons.memory_rounded, 'Hexadécimal', tab),
            ],
          ),
        if (tab?.viewMode == EditorViewMode.markdown)
          IconButton(
            icon: Icon(tab!.showMdPreview
                ? Icons.code_rounded
                : Icons.preview_rounded),
            tooltip: tab.showMdPreview ? 'Source' : 'Aperçu',
            onPressed: () =>
                setState(() => tab.showMdPreview = !tab.showMdPreview),
          ),
        IconButton(
          icon: const Icon(Icons.search_rounded, size: 20),
          onPressed: () => setState(() => _showSearch = !_showSearch),
        ),
        IconButton(
          icon: const Icon(Icons.save_rounded, size: 20),
          tooltip: 'Sauvegarder',
          onPressed: (tab?.isDirty == true || tab?.hexModified == true)
              ? _save
              : null,
        ),
        if (tab?.lang?.isRunnable == true)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded),
            color: AppColors.success,
            tooltip: 'Exécuter',
            onPressed: _run,
          ),
        IconButton(
          icon: const Icon(Icons.terminal_rounded, size: 20),
          tooltip: 'Terminal',
          onPressed: () => setState(() => _showTerminal = !_showTerminal),
        ),
        if (_p.isWorkspace)
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'Paramètres du workspace',
            onPressed: _openWsSettings,
          ),
      ],
    );
  }

  PopupMenuItem<EditorViewMode> _modeItem(
      EditorViewMode mode, IconData icon, String label, _UTab tab) {
    return PopupMenuItem(
      value: mode,
      child: Row(children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Text(label),
        if (tab.viewMode == mode) ...[
          const Spacer(),
          Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
        ],
      ]),
    );
  }

  // ── Onglets ───────────────────────────────────────────────────────────────

  Widget _buildTabBar(ThemeData theme) {
    return Container(
      height: 36,
      color: theme.colorScheme.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _p.tabs.length,
        itemBuilder: (_, i) {
          final tab = _p.tabs[i];
          final isActive = i == _p.activeTabIndex;
          return GestureDetector(
            onTap: () {
              if (_p.activeTabIndex == i) return;
              setState(() {
                _p.activeTabIndex = i;
                _syncKb();
              });
            },
            onDoubleTap: () => _enableEdit(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.scaffoldBackgroundColor
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.isDirty || tab.hexModified)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle),
                    ),
                  if (tab.isReadOnly)
                    const Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.lock_outline_rounded, size: 10),
                    ),
                  Text(
                    tab.name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isActive
                          ? null
                          : theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _closeTab(i),
                    child: const Icon(Icons.close_rounded, size: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Panneau projet ────────────────────────────────────────────────────────

  Widget _buildProjectPanel(ThemeData theme) {
    return Container(
      width: 220,
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded,
                    size: 14, color: AppColors.colorFolder),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.basename(_p.workspacePath).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: _buildTreeNodes(_p.tree, theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTreeNodes(List<_ProjNode> nodes, ThemeData theme) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      widgets.add(_buildTreeNode(node, theme));
      if (node.expanded) {
        widgets.addAll(_buildTreeNodes(node.children, theme));
      }
    }
    return widgets;
  }

  Widget _buildTreeNode(_ProjNode node, ThemeData theme) {
    final isActive = _p.activeTab?.path == node.path;
    return InkWell(
      onTap: () async {
        if (node.isDir) {
          await _toggleNode(node);
        } else {
          await _openFile(node.path);
        }
      },
      child: Container(
        color: isActive ? AppColors.accent.withValues(alpha: 0.1) : null,
        padding: EdgeInsets.only(
            left: 10.0 + node.depth * 12, top: 3, bottom: 3, right: 8),
        child: Row(
          children: [
            Icon(
              node.isDir
                  ? (node.expanded
                      ? Icons.folder_open_rounded
                      : Icons.folder_rounded)
                  : _fileIcon(node.name),
              size: 14,
              color: node.isDir
                  ? AppColors.colorFolder
                  : _fileColor(node.name),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                node.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isActive ? AppColors.accent : null,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = FileUtils.extOf(name);
    switch (ext) {
      case 'md':
      case 'markdown':
        return Icons.article_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
        return Icons.image_outlined;
      case 'xml':
      case 'json':
      case 'yaml':
      case 'yml':
        return Icons.data_object_rounded;
      default:
        final lang = LanguageRegistry.instance.forExtension(ext);
        return lang != null ? Icons.code_rounded : Icons.insert_drive_file_outlined;
    }
  }

  Color _fileColor(String name) {
    final lang = LanguageRegistry.instance.forExtension(FileUtils.extOf(name));
    return lang?.color ?? AppColors.colorText;
  }

  // ── Zone éditeur principale ───────────────────────────────────────────────

  Widget _buildEditorContent(ThemeData theme, bool isDark) {
    final tab = _p.activeTab;
    if (tab == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 64,
                color: theme.iconTheme.color?.withValues(alpha: 0.1)),
            const SizedBox(height: 12),
            Text(
              _p.isWorkspace
                  ? 'Sélectionnez un fichier dans le projet'
                  : 'Ouvrez un fichier pour commencer',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.textTheme.bodySmall?.color),
            ),
            if (_p.isWorkspace) ...[
              const SizedBox(height: 8),
              Text(
                'Double-tap sur un onglet pour activer l\'édition',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }
    return switch (tab.viewMode) {
      EditorViewMode.code => _buildCodeView(tab, theme, isDark),
      EditorViewMode.markdown => _buildMarkdownView(tab, theme, isDark),
      EditorViewMode.text => _buildTextView(tab, theme),
      EditorViewMode.richText => _buildRichView(tab, theme),
      EditorViewMode.hex => _buildHexView(tab, theme),
    };
  }

  // ── Mode Code ─────────────────────────────────────────────────────────────

  Widget _buildCodeView(_UTab tab, ThemeData theme, bool isDark) {
    final lang = tab.lang;
    final codeTheme = CodeHighlightTheme(
      languages: {
        if (lang != null)
          lang.id: CodeHighlightThemeMode(mode: lang.highlightMode),
      },
      theme: isDark ? re_dark.atomOneDarkTheme : re_light.atomOneLightTheme,
    );
    return CodeEditor(
      controller: tab.codeCtrl ?? CodeLineEditingController(),
      focusNode: _editorFocus,
      readOnly: tab.isReadOnly,
      onChanged: (_) {
        if (!tab.isDirty) setState(() => tab.isDirty = true);
      },
      style: CodeEditorStyle(
        fontSize: _p.ws.fontSize.toDouble(),
        fontFamily: _p.ws.fontFamily,
        backgroundColor: theme.scaffoldBackgroundColor,
        textColor: theme.textTheme.bodyLarge?.color ?? Colors.white,
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent.withValues(alpha: 0.3),
        codeTheme: codeTheme,
      ),
      wordWrap: _p.ws.wordWrap,
      shortcutsActivatorsBuilder: const DefaultCodeShortcutsActivatorsBuilder(),
    );
  }

  // ── Mode Markdown ─────────────────────────────────────────────────────────

  Widget _buildMarkdownView(_UTab tab, ThemeData theme, bool isDark) {
    if (tab.showMdPreview || tab.isReadOnly) {
      return Markdown(
        data: tab.codeCtrl?.text ?? tab.content,
        selectable: true,
        styleSheet: _mdStyleSheet(theme, isDark),
        onTapLink: (_, href, __) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        padding: const EdgeInsets.all(16),
      );
    }
    return _buildCodeView(tab, theme, isDark);
  }

  MarkdownStyleSheet _mdStyleSheet(ThemeData t, bool isDark) {
    final txt = isDark ? Colors.white.withAlpha(222) : Colors.black.withAlpha(222);
    final codeColor = isDark ? const Color(0xFF89B4FA) : const Color(0xFF1565C0);
    final codeBg = isDark ? const Color(0xFF313244) : const Color(0xFFEEEEEE);
    final s = context.read<SettingsService>();
    final mdBase = _googleFontStyle(s.markdownFontFamily,
        size: s.markdownFontSize.toDouble(), color: txt, height: 1.6);
    return MarkdownStyleSheet(
      h1: mdBase.copyWith(fontSize: s.markdownFontSize * 1.8, fontWeight: FontWeight.bold, height: 1.4),
      h2: mdBase.copyWith(fontSize: s.markdownFontSize * 1.45, fontWeight: FontWeight.bold, height: 1.4),
      h3: mdBase.copyWith(fontSize: s.markdownFontSize * 1.2, fontWeight: FontWeight.bold, height: 1.4),
      p: mdBase,
      code: TextStyle(fontFamily: 'monospace', fontSize: s.markdownFontSize * 0.87, color: codeColor, backgroundColor: codeBg),
      codeblockDecoration:
          BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(8)),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(4),
        border: const Border(left: BorderSide(color: Color(0xFF89B4FA), width: 4)),
      ),
      blockquote: TextStyle(
          color: isDark ? Colors.white60 : Colors.black54,
          fontStyle: FontStyle.italic),
      listBullet: TextStyle(color: t.colorScheme.primary),
      tableHead: TextStyle(fontWeight: FontWeight.bold, color: txt),
      tableBody: TextStyle(color: txt),
      tableBorder: TableBorder.all(color: isDark ? Colors.white24 : Colors.black12),
    );
  }

  // ── Mode Texte ────────────────────────────────────────────────────────────

  Widget _buildTextView(_UTab tab, ThemeData theme) {
    final s = context.read<SettingsService>();
    final style = _googleFontStyle(
      s.textFontFamily,
      size: s.textFontSize.toDouble(),
      color: theme.textTheme.bodyLarge?.color,
    );
    if (tab.isReadOnly) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(tab.content, style: style),
      );
    }
    return TextField(
      controller: tab.textCtrl,
      focusNode: _editorFocus,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: style,
      decoration: const InputDecoration(
          border: InputBorder.none, contentPadding: EdgeInsets.all(12)),
      onChanged: (_) {
        if (!tab.isDirty) setState(() => tab.isDirty = true);
      },
    );
  }

  // ── Mode Texte enrichi ────────────────────────────────────────────────────

  Widget _buildRichView(_UTab tab, ThemeData theme) {
    final s = context.read<SettingsService>();
    final richStyle = _googleFontStyle(
      s.richFontFamily,
      size: s.richFontSize.toDouble(),
      color: theme.textTheme.bodyLarge?.color,
    );
    return Column(
      children: [
        if (!tab.isReadOnly) _buildRichToolbar(tab, theme),
        Expanded(
          child: tab.isReadOnly
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText.rich(
                    tab.richCtrl?.buildTextSpan(
                          context: context,
                          withComposing: false,
                        ) ??
                        TextSpan(
                            text: tab.content,
                            style: richStyle),
                  ),
                )
              : TextField(
                  controller: tab.richCtrl,
                  focusNode: _editorFocus,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: richStyle,
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12)),
                  onChanged: (_) {
                    if (!tab.isDirty) setState(() => tab.isDirty = true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRichToolbar(_UTab tab, ThemeData theme) {
    return Container(
      height: 44,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _FmtBtn(
              icon: Icons.format_bold,
              tip: 'Gras',
              onTap: () => _applyFmt(tab, _RichFmt.bold)),
          _FmtBtn(
              icon: Icons.format_italic,
              tip: 'Italique',
              onTap: () => _applyFmt(tab, _RichFmt.italic)),
          _FmtBtn(
              icon: Icons.format_underlined,
              tip: 'Souligné',
              onTap: () => _applyFmt(tab, _RichFmt.underline)),
          _FmtBtn(
              icon: Icons.format_strikethrough,
              tip: 'Barré',
              onTap: () => _applyFmt(tab, _RichFmt.strikethrough)),
          const VerticalDivider(width: 16),
          Tooltip(
            message: 'Couleur du texte',
            child: InkWell(
              onTap: () => _pickColor(tab),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.format_color_text_rounded, size: 16),
                    Container(height: 3, width: 16, color: _richColor),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 16),
          _FmtBtn(
              icon: Icons.format_clear,
              tip: 'Effacer le formatage',
              onTap: () => _clearFmt(tab)),
        ],
      ),
    );
  }

  void _applyFmt(_UTab tab, _RichFmt fmt) {
    final ctrl = tab.richCtrl;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    ctrl.toggleFormat(fmt, sel.start, sel.end);
    setState(() => tab.isDirty = true);
  }

  void _clearFmt(_UTab tab) {
    final ctrl = tab.richCtrl;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    ctrl.clearRange(sel.start, sel.end);
    setState(() => tab.isDirty = true);
  }

  Future<void> _pickColor(_UTab tab) async {
    const colors = [
      Colors.red, Colors.orange, Colors.yellow, Colors.green,
      Colors.blue, Colors.purple, Colors.pink, Colors.teal,
      Colors.white, Colors.black,
    ];
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Couleur du texte'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors
                  .map((c) => InkWell(
                        onTap: () => Navigator.pop(context, c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => _richColor = picked);
    final ctrl = tab.richCtrl;
    if (ctrl != null) {
      final sel = ctrl.selection;
      if (sel.isValid && !sel.isCollapsed) {
        ctrl.setTextColor(picked, sel.start, sel.end);
        setState(() => tab.isDirty = true);
      }
    }
  }

  // ── Mode Hexadécimal ──────────────────────────────────────────────────────

  Widget _buildHexView(_UTab tab, ThemeData theme) {
    if (tab.bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tab.bytes!.isEmpty) return const Center(child: Text('Fichier vide'));

    final rowCount = (tab.bytes!.length / _hexBytesPerRow).ceil();

    return Stack(
      children: [
        Column(
          children: [
            if (tab.hexTruncated) _buildHexTruncatedBanner(tab, theme),
            _buildHexHeader(theme),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: tab.hexScrollCtrl,
                padding: tab.hexSelectedOffset >= 0
                    ? const EdgeInsets.only(bottom: 140)
                    : EdgeInsets.zero,
                itemCount: rowCount,
                itemExtent: 28,
                itemBuilder: (_, row) => _buildHexRow(tab, row, theme),
              ),
            ),
          ],
        ),
        if (tab.hexSelectedOffset >= 0)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildHexEditBar(tab, theme),
          ),
      ],
    );
  }

  /// Bandeau affiché quand seul le début d'un gros fichier est chargé.
  Widget _buildHexTruncatedBanner(_UTab tab, ThemeData theme) {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Aperçu des ${FileUtils.formatSize(tab.bytes!.length)} premiers '
              'sur ${FileUtils.formatSize(tab.hexFileLength)} : '
              'lecture seule pour ne pas tronquer le fichier.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHexHeader(ThemeData theme) {
    final s = context.read<SettingsService>();
    final style = _googleFontStyle(s.hexFontFamily,
        size: (s.hexFontSize * 0.82).clamp(8, 14),
        color: theme.textTheme.bodySmall?.color,
        weight: FontWeight.w600);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 68, child: Text('OFFSET', style: style)),
          Expanded(
            child: Row(
              children: List.generate(
                  _hexBytesPerRow,
                  (i) => SizedBox(
                        width: 26,
                        child: Text(i.toRadixString(16).toUpperCase(),
                            style: style, textAlign: TextAlign.center),
                      )),
            ),
          ),
          const SizedBox(width: 8),
          Text('ASCII', style: style),
        ],
      ),
    );
  }

  Widget _buildHexRow(_UTab tab, int row, ThemeData theme) {
    final bytes = tab.bytes!;
    final start = row * _hexBytesPerRow;
    final end = math.min(start + _hexBytesPerRow, bytes.length);
    final rowBytes = bytes.sublist(start, end);
    final s = context.read<SettingsService>();
    final hexSz = s.hexFontSize.toDouble();
    final offsetStyle = _googleFontStyle(s.hexFontFamily,
        size: hexSz * 0.92, color: theme.textTheme.bodySmall?.color);
    final hexStyle = _googleFontStyle(s.hexFontFamily, size: hexSz);
    final asciiStyle = _googleFontStyle(s.hexFontFamily,
        size: hexSz * 0.92, color: theme.textTheme.bodySmall?.color);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: row.isOdd ? theme.colorScheme.surface.withValues(alpha: 0.4) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              start.toRadixString(16).padLeft(8, '0').toUpperCase(),
              style: offsetStyle,
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(_hexBytesPerRow, (i) {
                final offset = start + i;
                if (i >= rowBytes.length) return const SizedBox(width: 26);
                final byte = rowBytes[i];
                final isSel = offset == tab.hexSelectedOffset;
                return GestureDetector(
                  onTap: () => _hexSelect(tab, offset),
                  child: Container(
                    width: 26,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: isSel
                        ? BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(4))
                        : null,
                    child: Text(
                      byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
                      style: hexStyle.copyWith(
                        color: isSel ? Colors.white : _hexColor(byte, theme),
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: rowBytes.map((b) {
              final c = (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '·';
              return Text(c, style: asciiStyle);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _hexColor(int byte, ThemeData theme) {
    final base = theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;
    if (byte == 0x00) return base.withValues(alpha: 0.25);
    if (byte == 0xFF) return AppColors.warning.withValues(alpha: 0.8);
    if (byte < 0x20 || byte == 0x7F) return AppColors.info.withValues(alpha: 0.8);
    return base;
  }

  Widget _buildHexEditBar(_UTab tab, ThemeData theme) {
    final bytes = tab.bytes!;
    final offset = tab.hexSelectedOffset;
    if (offset < 0 || offset >= bytes.length) return const SizedBox.shrink();
    final byte = bytes[offset];
    final dec = byte.toString().padLeft(3, ' ');
    final char = (byte >= 0x20 && byte < 0x7F) ? String.fromCharCode(byte) : '·';
    final hs = context.read<SettingsService>();
    final mono = _googleFontStyle(hs.hexFontFamily, size: hs.hexFontSize.toDouble());

    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Offset: 0x${offset.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                style: mono.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(width: 16),
              Text('Dec: $dec', style: mono),
              const SizedBox(width: 16),
              Text("Char: '$char'", style: mono),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => tab.hexSelectedOffset = -1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: offset > 0 ? () => _hexNav(tab, -1) : null,
              ),
              Expanded(
                child: TextField(
                  controller: tab.hexInputCtrl,
                  focusNode: tab.hexInputFocus,
                  enabled: !tab.isReadOnly,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(2),
                    _UpperCaseFmt(),
                  ],
                  textAlign: TextAlign.center,
                  style: mono.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'FF',
                    hintStyle: mono.copyWith(
                      fontSize: 18,
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.4),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.length == 2) {
                      _hexApply(tab);
                      if (offset + 1 < bytes.length) _hexNav(tab, 1);
                    }
                  },
                  onSubmitted: (_) => _hexApply(tab),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: tab.isReadOnly
                    ? null
                    : () {
                        if (tab.hexInputCtrl?.text.length == 2) {
                          _hexApply(tab);
                        }
                      },
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10)),
                child: const Text('Appliquer'),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: offset < bytes.length - 1
                    ? () => _hexNav(tab, 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Barre de recherche ────────────────────────────────────────────────────

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Rechercher…',
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _replaceCtrl,
              decoration: const InputDecoration(
                hintText: 'Remplacer…',
                isDense: true,
                prefixIcon: Icon(Icons.find_replace_rounded, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _replaceNext,
            child: const Text('Remplacer', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            onPressed: () => setState(() => _showSearch = false),
          ),
        ],
      ),
    );
  }

  // ── Barre de suggestions ──────────────────────────────────────────────────

  Widget _buildCompletionBar(ThemeData theme) {
    return Container(
      height: 36,
      color: theme.colorScheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: _completions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final comp = _completions[i];
          return GestureDetector(
            onTap: () => _insertCompletion(comp),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Text(comp,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.accent)),
            ),
          );
        },
      ),
    );
  }

  // ── Paramètres workspace ──────────────────────────────────────────────────

  void _openWsSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkspaceSettingsScreen(
          projectPath: _p.workspacePath,
          settings: _p.ws,
          onSave: (updated) async {
            await WorkspaceService.save(_p.workspacePath, updated);
            setState(() => _p.ws = updated);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Widgets auxiliaires
// ═══════════════════════════════════════════════════════════════════════════════

class _ModeBadge extends StatelessWidget {
  final _UTab tab;
  const _ModeBadge({required this.tab});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (tab.viewMode) {
      EditorViewMode.code =>
        (tab.lang?.label ?? 'Code', tab.lang?.color ?? AppColors.colorCode),
      EditorViewMode.markdown => ('MD', const Color(0xFF4078C8)),
      EditorViewMode.text => ('TXT', AppColors.colorText),
      EditorViewMode.richText => ('DOC', const Color(0xFF2B579A)),
      EditorViewMode.hex => ('HEX', AppColors.colorUnknown),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _FmtBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _FmtBtn({required this.icon, required this.tip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 16)),
      ),
    );
  }
}

class _UpperCaseFmt extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue old, TextEditingValue value) =>
      value.copyWith(text: value.text.toUpperCase());
}
