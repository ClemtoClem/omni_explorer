/// @file custom_keyboard.dart
/// @brief Clavier AZERTY personnalisé complet.
///
/// Fonctionnalités :
/// - Long press sur une lettre → popup d'accents (overlay positionné au-dessus)
/// - 4 modes : ABC (AZERTY), 123 (numérique/symboles), SYM (ponctuation /
///   tableaux / flèches / unicode), 😊 (émojis par catégorie)
/// - Barre de suggestions par complétion dans le texte courant
/// - Barre de caractères de programmation (scrollable)
/// - Rangée de contrôle : Shift / CTRL / ALT / espace / TAB / ↵ / ESC / DEL / ⌫
/// - Rangée directionnelle dédiée : ← ↑ ↓ → | PgU PgD (ne déborde plus)
/// - Rangée de sélection de mode tout en bas : ABC | 123 | SYM | 😊

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layouts de touches
// ─────────────────────────────────────────────────────────────────────────────

const _rowsLower = [
  ['a','z','e','r','t','y','u','i','o','p'],
  ['q','s','d','f','g','h','j','k','l','m'],
  ['w','x','c','v','b','n',',','.'],
];
const _rowsUpper = [
  ['A','Z','E','R','T','Y','U','I','O','P'],
  ['Q','S','D','F','G','H','J','K','L','M'],
  ['W','X','C','V','B','N','?','!'],
];
const _rowsNumbers = [
  ['1','2','3','4','5','6','7','8','9','0'],
  ['!','@','#',r'$','%','^','&','*','(',')'],
  ['-','_','=','+','[',']','{','}','|','\\'],
];

// Barre de programmation rapide (scrollable)
const _progChars = [
  '`','~','!','@','#',r'$','%','^','&','*',
  '(',')','[',']','{','}','<','>','"',"'",
  '|','\\',';',':','/','.','?','-','_','+','=',
];

// ─────────────────────────────────────────────────────────────────────────────
// Accents (long press)
// ─────────────────────────────────────────────────────────────────────────────

/// Variantes accentuées accessibles par un appui long sur chaque lettre.
const Map<String, List<String>> _accentMap = {
  'a': ['à','â','ä','æ','å','ã','á'],
  'A': ['À','Â','Ä','Æ','Å','Ã','Á'],
  'e': ['é','è','ê','ë','ē','ě'],
  'E': ['É','È','Ê','Ë','Ē','Ě'],
  'i': ['î','ï','í','ì','ī'],
  'I': ['Î','Ï','Í','Ì','Ī'],
  'o': ['ô','ö','œ','ø','õ','ó','ò'],
  'O': ['Ô','Ö','Œ','Ø','Õ','Ó','Ò'],
  'u': ['ù','û','ü','ú','ū'],
  'U': ['Ù','Û','Ü','Ú','Ū'],
  'c': ['ç','ć','č'],
  'C': ['Ç','Ć','Č'],
  'n': ['ñ','ń','ň'],
  'N': ['Ñ','Ń','Ň'],
  'y': ['ÿ','ý'],
  'Y': ['Ÿ','Ý'],
  's': ['ś','š','ß'],
  'S': ['Ś','Š'],
  'z': ['ź','ž','ż'],
  'Z': ['Ź','Ž','Ż'],
  'r': ['ř'],
  'R': ['Ř'],
  'l': ['ł'],
  'L': ['Ł'],
  'd': ['ð'],
  'D': ['Ð'],
  't': ['þ'],
  'T': ['Þ'],
};

// ─────────────────────────────────────────────────────────────────────────────
// Clavier Symboles / Ponctuation / Unicod
// ─────────────────────────────────────────────────────────────────────────────

const _symCatIcons = ['…', '±', '┼', '→', '★'];
const _symCatLabels = ['Ponct.', 'Maths', 'Tableaux', 'Flèches', 'Divers'];

const _symGroups = [
  [
    '.', ',', ';', ':', '!', '?', '…', '¡', '¿',
    '«', '»', '"', '"', '\'', '\'', '‹', '›',
    '—', '–', '‐', '·', '•', '°', '/', '\\', '|', '¦',
    '(', ')', '[', ']', '{', '}', '<', '>',
    '"', "'", '`', '~', '@', '#', r'$', '%', '^', '&', '*',
  ],
  [
    '+', '-', '×', '÷', '=', '≠', '≈', '≡', '≢',
    '<', '>', '≤', '≥', '≪', '≫', '±', '∓',
    '%', '‰', '°', '√', '∛', '∑', '∏', '∫', '∂', '∞',
    '∈', '∉', '⊂', '⊃', '⊆', '⊇', '∩', '∪', '∅',
    'π', 'φ', 'θ', 'λ', 'μ', 'σ', 'τ', 'ω', 'Δ', 'Σ', 'Π',
    '¹', '²', '³', '⁴', '⁰', '½', '¼', '¾',
  ],
  [
    '─','━','│','┃',
    '┌','┐','└','┘',
    '├','┤','┬','┴','┼',
    '╔','╗','╚','╝',
    '╠','╣','╦','╩','╬',
    '═','║',
    '▀','▄','█','▌','▐','░','▒','▓',
    '■','□','▪','▫','●','○','◆','◇',
    '△','▽','▲','▼',
  ],
  [
    '←','→','↑','↓',
    '↔','↕','↖','↗','↘','↙',
    '⇐','⇒','⇑','⇓','⇔','⇕',
    '⇖','⇗','⇘','⇙',
    '➔','➜','➡','⬅','⬆','⬇',
    '↩','↪','↺','↻',
    '⟵','⟶','⟷',
    '↦','↤','↥','↧',
    '⊲','⊳','⊴','⊵',
  ],
  [
    '★','☆','♠','♣','♥','♦',
    '✓','✗','✔','✘','✦','✧','✩','✪',
    '©','®','™','℗','℃','℉','℮',
    '§','¶','†','‡','※','‼','⁉','‽',
    '€',r'$','£','¥','¢','¤',
    '♩','♪','♫','♬','♭','♮','♯',
    '☀','☁','☂','☃','☄','⚡','❄','🔥',
    '⚠','⚡','ℹ','🔒','🔓','🔗',
  ],
];

// ─────────────────────────────────────────────────────────────────────────────
// Émojis
// ─────────────────────────────────────────────────────────────────────────────

const _emojiCatIcons = ['😊','🐶','🍕','💻','❤️'];
const _emojiGroups = [
  ['😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🙂','😉','😌','😍',
   '🥰','😘','😋','😛','😜','🤪','😎','🤩','🥳','😏','😒','😔','🥺','😢',
   '😭','😤','😠','😡','🤬','😱','😨','😰','🤗','🤔','😶','😐','😑','😬',
   '🙄','😯','😲','🥱','😴','🤢','🤮','😷','🤒','🤕','🤑','😈','💀','💩'],
  ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸',
   '🐵','🐔','🐧','🐦','🦆','🦅','🦉','🐺','🐴','🦄','🐝','🦋','🌱','🌲',
   '🌳','🌴','🌵','🍀','🌺','🌻','🌹','🌷','🌸','⭐','🌟','✨','🌙','☀️','🌈'],
  ['🍎','🍊','🍋','🍇','🍓','🍒','🍑','🥭','🍍','🥝','🍅','🥑','🌽','🥕',
   '🍕','🍔','🍟','🌮','🍣','🍱','🍜','🍝','🍛','🥗','🍦','🍧','🎂','🍰',
   '🍫','🍬','🍭','☕','🍵','🍺','🍻','🥂','🍷','🍸','🍹','🧃','🥤','🧋'],
  ['📱','💻','⌨️','🖥️','📷','📸','📹','🎥','📺','📻','💡','🔦','🔧','🔨',
   '🔩','🔗','🧲','📚','📖','✏️','📝','📊','📈','📉','📌','📍','✂️','🔐',
   '🔒','🔓','🔑','🎵','🎶','🎤','🎧','🎸','🎹','🥁','🎷','🎻','🎮','🕹️'],
  ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','💔','💕','💞','💓','💗','💖',
   '💘','💝','✅','❌','⭕','🛑','⛔','🚫','💯','💢','❗','❕','❓','❔',
   '‼️','⁉️','🔱','⚜️','♻️','⚠️','💬','💭','🔥','💥','👍','👎','👏',
   '🙌','🤝','🙏','💪','👋','🫶','☮️'],
];

// ─────────────────────────────────────────────────────────────────────────────
// Mode clavier
// ─────────────────────────────────────────────────────────────────────────────

enum _KbdMode { alpha, numeric, symbol, emoji }

// ─────────────────────────────────────────────────────────────────────────────
// Widget principal
// ─────────────────────────────────────────────────────────────────────────────

class CustomKeyboard extends StatefulWidget {
  final FocusNode focusNode;
  final dynamic controller; 

  const CustomKeyboard({
    super.key,
    required this.focusNode,
    this.controller,
  });

  @override
  State<CustomKeyboard> createState() => _CustomKeyboardState();
}

class _CustomKeyboardState extends State<CustomKeyboard> {
  bool     _shift   = false;
  bool     _caps    = false;
  _KbdMode _mode    = _KbdMode.alpha;
  bool     _ctrl    = false;
  bool     _alt     = false;
  bool     _visible = true;
  int      _symCat  = 0;
  int      _emojiCat= 0;
  List<String> _suggestions = [];

  OverlayEntry? _accentOverlay;
  Timer? _repeatTimer;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    FocusManager.instance.addListener(_onGlobalFocusChange);
  }

  @override
  void didUpdateWidget(CustomKeyboard old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _removeAccentOverlay();
    _stopKeyRepeat();
    widget.focusNode.removeListener(_onFocusChange);
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus && _visible) _hideSysKeyboard();
  }

  void _onGlobalFocusChange() {
    if (!_visible || !mounted) return;
    FocusNode? node = FocusManager.instance.primaryFocus;
    while (node != null) {
      if (node == widget.focusNode) { _hideSysKeyboard(); return; }
      node = node.parent;
    }
  }

  void _hideSysKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
    });
  }

  // Gère la répétition des touches au maintien (Backspace / Nav)
  void _startKeyRepeat(LogicalKeyboardKey key) {
    _sendKey(key);
    _stopKeyRepeat();
    _repeatTimer = Timer(const Duration(milliseconds: 400), () {
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 45), (timer) {
        _sendKey(key);
      });
    });
  }

  void _stopKeyRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _showAccentPopup(BuildContext keyContext, String baseChar, List<String> accents) {
    _removeAccentOverlay();
    HapticFeedback.mediumImpact();

    final box = keyContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;

    _accentOverlay = OverlayEntry(
      builder: (_) => _AccentPopup(
        anchorLeft: pos.dx,
        anchorTop: pos.dy,
        anchorWidth: size.width,
        accents: accents,
        onSelect: (c) {
          _removeAccentOverlay();
          _insert(c);
        },
        onDismiss: _removeAccentOverlay,
      ),
    );
    Overlay.of(context).insert(_accentOverlay!);
  }

  void _removeAccentOverlay() {
    _accentOverlay?.remove();
    _accentOverlay = null;
  }

  EditableTextState? get _editState =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>();

  TextEditingValue get _currentValue {
    if (widget.controller != null) {
      try { return widget.controller.value as TextEditingValue; } catch (_) {}
    }
    return _editState?.textEditingValue ?? const TextEditingValue();
  }

  void _updateTextValue(TextEditingValue newValue) {
    if (widget.controller != null) {
      try {
        widget.controller.value = newValue;
      } catch (_) {
        try {
          widget.controller.text = newValue.text;
        } catch (_) {
          _editState?.userUpdateTextEditingValue(newValue, SelectionChangedCause.keyboard);
        }
      }
    } else {
      _editState?.userUpdateTextEditingValue(newValue, SelectionChangedCause.keyboard);
    }
  }

  void _insert(String char) {
    HapticFeedback.lightImpact();
    final cur = _currentValue;
    final sel = cur.selection;
    if (sel.isValid) {
      final newText = cur.text.replaceRange(
        sel.start.clamp(0, cur.text.length),
        sel.end.clamp(0, cur.text.length),
        char,
      );
      _updateTextValue(
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: sel.start + char.length),
        ),
      );
    }
    setState(() {
      if (_shift && !_caps) _shift = false;
    });
    _updateSuggestions();
  }

  void _sendKey(LogicalKeyboardKey key) {
    HapticFeedback.lightImpact();
    final val = _currentValue;
    final sel = val.selection;
    if (!sel.isValid) return;

    var text = val.text;
    var newSel = sel;

    if (key == LogicalKeyboardKey.backspace) {
      if (sel.isCollapsed && sel.start > 0) {
        text   = text.substring(0, sel.start - 1) + text.substring(sel.start);
        newSel = TextSelection.collapsed(offset: sel.start - 1);
      } else if (!sel.isCollapsed) {
        text   = text.replaceRange(sel.start, sel.end, '');
        newSel = TextSelection.collapsed(offset: sel.start);
      }
    } else if (key == LogicalKeyboardKey.delete) {
      if (sel.isCollapsed && sel.start < text.length) {
        text   = text.substring(0, sel.start) + text.substring(sel.start + 1);
        newSel = TextSelection.collapsed(offset: sel.start);
      }
    } else if (key == LogicalKeyboardKey.enter) {
      _insert('\n'); return;
    } else if (key == LogicalKeyboardKey.tab) {
      _insert('\t'); return;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      final p = (sel.baseOffset - 1).clamp(0, text.length);
      newSel = TextSelection.collapsed(offset: p);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final p = (sel.baseOffset + 1).clamp(0, text.length);
      newSel = TextSelection.collapsed(offset: p);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      final before = text.substring(0, sel.baseOffset);
      final col    = before.length - (before.lastIndexOf('\n') + 1);
      final prev   = before.lastIndexOf('\n');
      if (prev >= 0) {
        final lineBefore = text.substring(0, prev);
        final prevNl     = lineBefore.lastIndexOf('\n');
        final newOff     = (prevNl + 1 + col).clamp(prevNl + 1, prev);
        newSel = TextSelection.collapsed(offset: newOff);
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final before  = text.substring(0, sel.baseOffset);
      final col     = before.length - (before.lastIndexOf('\n') + 1);
      final nextNl  = text.indexOf('\n', sel.baseOffset);
      if (nextNl >= 0) {
        final nextNl2 = text.indexOf('\n', nextNl + 1);
        final lineEnd = nextNl2 < 0 ? text.length : nextNl2;
        final newOff  = (nextNl + 1 + col).clamp(nextNl + 1, lineEnd);
        newSel = TextSelection.collapsed(offset: newOff);
      }
    } else if (key == LogicalKeyboardKey.pageUp) {
      newSel = const TextSelection.collapsed(offset: 0);
    } else if (key == LogicalKeyboardKey.pageDown) {
      newSel = TextSelection.collapsed(offset: text.length);
    }

    _updateTextValue(TextEditingValue(text: text, selection: newSel));
    _updateSuggestions();
  }

  void _updateSuggestions() {
    final conn = _editState;
    if (conn == null) { if (_suggestions.isNotEmpty) setState(() => _suggestions = []); return; }
    final val    = conn.textEditingValue;
    final cursor = val.selection.baseOffset;
    if (cursor <= 0) { if (_suggestions.isNotEmpty) setState(() => _suggestions = []); return; }

    final before = val.text.substring(0, cursor);
    final match  = RegExp(r'\w+$').firstMatch(before);
    if (match == null || match.group(0)!.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    final word  = match.group(0)!;
    final seen  = <String>{word};
    final list  = <String>[];
    for (final m in RegExp(r'\w+').allMatches(val.text)) {
      final w = m.group(0)!;
      if (w.length > word.length && w.startsWith(word) && seen.add(w)) {
        list.add(w);
        if (list.length == 6) break;
      }
    }
    setState(() => _suggestions = list);
  }

  void _applySuggestion(String word) {
    HapticFeedback.lightImpact();
    final conn = _editState; if (conn == null) return;
    final val    = conn.textEditingValue;
    final cursor = val.selection.baseOffset; if (cursor <= 0) return;
    final before = val.text.substring(0, cursor);
    final match  = RegExp(r'\w+$').firstMatch(before); if (match == null) return;
    final start  = cursor - match.group(0)!.length;
    conn.userUpdateTextEditingValue(
      TextEditingValue(
        text:      val.text.substring(0, start) + word + val.text.substring(cursor),
        selection: TextSelection.collapsed(offset: start + word.length),
      ),
      SelectionChangedCause.keyboard,
    );
    setState(() => _suggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FloatingActionButton(
            heroTag: 'kbd_show',
            onPressed: () {
              HapticFeedback.mediumImpact();
              setState(() => _visible = true);
            },
            child: const Icon(Icons.keyboard_rounded),
          ),
        ),
      );
    }

    final theme     = Theme.of(context);
    final isDark    = theme.brightness == Brightness.dark;
    final bg        = isDark ? AppColors.darkSurface  : AppColors.lightSurface2;
    final keyBg     = isDark ? AppColors.darkSurface2 : AppColors.lightSurface;
    final border    = isDark ? AppColors.darkBorder   : AppColors.lightBorder;
    final textColor = isDark ? AppColors.darkText     : AppColors.lightText;

    return Container(
      color: bg,
      padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom), // Respecte la zone d'encoche du bas (iOS/Android)
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSuggestionBar(keyBg, border, textColor),
            Divider(height: 1, color: border),

            if (_mode == _KbdMode.emoji)
              _buildEmojiKeyboard(keyBg, border, textColor)
            else if (_mode == _KbdMode.symbol)
              _buildSymbolKeyboard(keyBg, border, textColor)
            else ...[
              _buildProgBar(keyBg, border, textColor),
              Divider(height: 1, color: border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: _buildLetterRows(keyBg, border, textColor),
              ),
            ],

            Divider(height: 1, color: border),
            _buildControlRow(keyBg, border, textColor),
            _buildNavRow(keyBg, border, textColor),
            _buildModeRow(keyBg, border, textColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionBar(Color keyBg, Color border, Color textColor) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: _suggestions.isEmpty
                ? Center(
                    child: Text('Suggestions…',
                        style: TextStyle(
                            fontSize: 12,
                            color: textColor.withAlpha(80),
                            fontStyle: FontStyle.italic)))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    itemCount: _suggestions.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _applySuggestion(_suggestions[i]),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: keyBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border),
                        ),
                        child: Center(
                          child: Text(_suggestions[i],
                              style: GoogleFonts.jost(
                                  fontSize: 13,
                                  color: textColor,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ),
                  ),
          ),
          Container(width: 1, height: 24, color: border, margin: const EdgeInsets.symmetric(horizontal: 4)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 48,
              child: _K(
                icon: Icons.keyboard_hide_rounded,
                bg: keyBg, border: border, tc: textColor,
                onTap: () => setState(() => _visible = false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgBar(Color keyBg, Color border, Color textColor) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: _progChars.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _insert(_progChars[i]),
          child: Container(
            width: 36,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: keyBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border),
            ),
            child: Center(
              child: Text(_progChars[i],
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLetterRows(Color keyBg, Color border, Color textColor) {
    final rows = _mode == _KbdMode.numeric
        ? _rowsNumbers
        : (_shift || _caps ? _rowsUpper : _rowsLower);

    return Column(
      children: rows.map((row) {
        final missingKeys = 10 - row.length; 
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (missingKeys > 0) Spacer(flex: missingKeys),
              ...row.map((c) {
                final accents = _accentMap[c] ?? [];
                return Expanded(
                  flex: 2,
                  child: _LetterKey(
                    label:    c,
                    bg:       keyBg,
                    border:   border,
                    tc:       textColor,
                    accents:  accents,
                    onTap:    () => _insert(c),
                    onLongPress: accents.isEmpty
                        ? null
                        : (ctx) => _showAccentPopup(ctx, c, accents),
                  ),
                );
              }),
              if (missingKeys > 0) Spacer(flex: missingKeys),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildControlRow(Color keyBg, Color border, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_mode == _KbdMode.alpha)
            Expanded(
              flex: 4,
              child: _Mod(
                icon: _caps ? CupertinoIcons.capslock_fill : CupertinoIcons.capslock,
                active: _shift || _caps,
                bg: keyBg, border: border, tc: textColor,
                onTap: () => setState(() {
                  if (_shift) { _caps = !_caps; _shift = false; }
                  else        { _shift = true; }
                }),
              ),
            ),
          Expanded(flex: 3, child: _Mod(label: 'CTRL', active: _ctrl, bg: keyBg, border: border, tc: textColor, onTap: () => setState(() => _ctrl = !_ctrl))),
          Expanded(flex: 3, child: _Mod(label: 'ALT', active: _alt, bg: keyBg, border: border, tc: textColor, onTap: () => setState(() => _alt = !_alt))),
          Expanded(flex: 9, child: _K(icon: Icons.space_bar_rounded, bg: keyBg, border: border, tc: textColor, onTap: () => _insert(' '))),
          Expanded(flex: 3, child: _K(icon: Icons.keyboard_tab, bg: keyBg, border: border, tc: textColor, onTap: () => _sendKey(LogicalKeyboardKey.tab))),
          Expanded(flex: 4, child: _K(icon: Icons.keyboard_return, bg: keyBg, border: border, tc: textColor, onTap: () => _sendKey(LogicalKeyboardKey.enter))),
          Expanded(flex: 3, child: _K(label: 'DEL', bg: keyBg, border: border, tc: textColor, 
            onTap: () => _sendKey(LogicalKeyboardKey.delete),
            onLongPressStart: () => _startKeyRepeat(LogicalKeyboardKey.delete),
            onLongPressEnd: _stopKeyRepeat,
          )),
          Expanded(flex: 4, child: _K(icon: Icons.backspace, bg: keyBg, border: border, tc: textColor, 
            onTap: () => _sendKey(LogicalKeyboardKey.backspace),
            onLongPressStart: () => _startKeyRepeat(LogicalKeyboardKey.backspace),
            onLongPressEnd: _stopKeyRepeat,
          )),
        ],
      ),
    );
  }

  Widget _buildNavRow(Color keyBg, Color border, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        children: [
          _NavBtn(icon: Icons.keyboard_arrow_left, bg: keyBg, border: border, tc: textColor, 
            onTap: () => _sendKey(LogicalKeyboardKey.arrowLeft),
            onLongPressStart: () => _startKeyRepeat(LogicalKeyboardKey.arrowLeft),
            onLongPressEnd: _stopKeyRepeat),
          _NavBtn(icon: Icons.keyboard_arrow_up, bg: keyBg, border: border, tc: textColor, 
            onTap: () => _sendKey(LogicalKeyboardKey.arrowUp),
            onLongPressStart: () => _startKeyRepeat(LogicalKeyboardKey.arrowUp),
            onLongPressEnd: _stopKeyRepeat),
          _NavBtn(icon: Icons.keyboard_arrow_down, bg: keyBg, border: border, tc: textColor, 
            onTap: () => _sendKey(LogicalKeyboardKey.arrowDown),
            onLongPressStart: () => _startKeyRepeat(LogicalKeyboardKey.arrowDown),
            onLongPressEnd: _stopKeyRepeat),
          _NavBtn(icon: Icons.keyboard_arrow_right, bg: keyBg, border: border, tc: textColor, 
            onTap: () => _sendKey(LogicalKeyboardKey.arrowRight),
            onLongPressStart: () => _startKeyRepeat(LogicalKeyboardKey.arrowRight),
            onLongPressEnd: _stopKeyRepeat),
          Container(width: 1, height: 24, color: border, margin: const EdgeInsets.symmetric(horizontal: 6)),
          _NavBtn(icon: Icons.keyboard_double_arrow_up, bg: keyBg, border: border, tc: textColor, onTap: () => _sendKey(LogicalKeyboardKey.pageUp)),
          _NavBtn(icon: Icons.keyboard_double_arrow_down, bg: keyBg, border: border, tc: textColor, onTap: () => _sendKey(LogicalKeyboardKey.pageDown)),
        ],
      ),
    );
  }

  Widget _buildModeRow(Color keyBg, Color border, Color textColor) {
    return Container(
      color: AppColors.accent.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          _ModeBtn(label: 'ABC', active: _mode == _KbdMode.alpha, bg: keyBg, border: border, tc: textColor, onTap: () => setState(() { _mode = _KbdMode.alpha; })),
          _ModeBtn(label: '123', active: _mode == _KbdMode.numeric, bg: keyBg, border: border, tc: textColor, onTap: () => setState(() { _mode = _KbdMode.numeric; })),
          _ModeBtn(label: 'SYM', active: _mode == _KbdMode.symbol, bg: keyBg, border: border, tc: textColor, onTap: () => setState(() { _mode = _KbdMode.symbol; })),
          _ModeBtn(label: '😊', active: _mode == _KbdMode.emoji, bg: keyBg, border: border, tc: textColor, onTap: () => setState(() { _mode = _KbdMode.emoji; })),
        ],
      ),
    );
  }

  Widget _buildSymbolKeyboard(Color keyBg, Color border, Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: List.generate(_symCatIcons.length, (i) {
              final active = i == _symCat;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _symCat = i);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 2.5)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_symCatIcons[i], style: TextStyle(fontSize: active ? 16 : 14)),
                        if (active) Text(_symCatLabels[i], style: TextStyle(fontSize: 9, color: AppColors.accent, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(
          height: 190,
          child: GridView.builder(
            padding: const EdgeInsets.all(6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:  8,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.1,
            ),
            itemCount: _symGroups[_symCat].length,
            itemBuilder: (_, i) {
              final ch = _symGroups[_symCat][i];
              return _SymbolEmojiKey(label: ch, textColor: textColor, keyBg: keyBg, border: border, onTap: () => _insert(ch));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiKeyboard(Color keyBg, Color border, Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: List.generate(_emojiCatIcons.length, (i) {
              final active = i == _emojiCat;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _emojiCat = i);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 2.5)),
                    ),
                    child: Center(child: Text(_emojiCatIcons[i], style: TextStyle(fontSize: active ? 22 : 18))),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(
          height: 190,
          child: GridView.builder(
            padding: const EdgeInsets.all(6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   8,
              mainAxisSpacing:  4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.1,
            ),
            itemCount: _emojiGroups[_emojiCat].length,
            itemBuilder: (_, i) {
              final emoji = _emojiGroups[_emojiCat][i];
              return _SymbolEmojiKey(label: emoji, textColor: textColor, keyBg: keyBg, border: border, isEmoji: true, onTap: () => _insert(emoji));
            },
          ),
        ),
      ],
    );
  }
}

// ── WIDGETS ATOMIQUES AVEC ETAT DE PRESSION (FEEDBACK VISUEL RAPIDE) ──────────

class _K extends StatefulWidget {
  final String?   label;
  final IconData? icon;
  final Color     bg, border, tc;
  final VoidCallback onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  
  const _K({
    this.label, this.icon,
    required this.bg, required this.border, required this.tc,
    required this.onTap, this.onLongPressStart, this.onLongPressEnd,
  });

  @override
  State<_K> createState() => _KState();
}

class _KState extends State<_K> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) { setState(() => _isPressed = true); widget.onLongPressStart?.call(); },
    onTapUp: (_) { setState(() => _isPressed = false); widget.onLongPressEnd?.call(); widget.onTap(); },
    onTapCancel: () { setState(() => _isPressed = false); widget.onLongPressEnd?.call(); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 30),
      height: 48, // Hauteur ergonomique standardisée (MD standard target)
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: _isPressed ? widget.tc.withValues(alpha: 0.15) : widget.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.border),
        boxShadow: _isPressed ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), offset: const Offset(0, 1), blurRadius: 1)],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: widget.icon != null
                ? Icon(widget.icon, size: 22, color: widget.tc)
                : Text(widget.label ?? '',
                    style: GoogleFonts.jost(fontSize: 14, color: widget.tc, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    ),
  );
}

class _LetterKey extends StatefulWidget {
  final String     label;
  final Color      bg, border, tc;
  final List<String> accents;
  final VoidCallback onTap;
  final void Function(BuildContext)? onLongPress;

  const _LetterKey({
    required this.label,
    required this.bg, required this.border, required this.tc,
    required this.accents,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_LetterKey> createState() => _LetterKeyState();
}

class _LetterKeyState extends State<_LetterKey> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext ctx) => GestureDetector(
    onTapDown: (_) => setState(() => _isPressed = true),
    onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); },
    onTapCancel: () => setState(() => _isPressed = false),
    onLongPress: widget.onLongPress != null ? () {
      setState(() => _isPressed = false);
      widget.onLongPress!(ctx);
    } : null,
    child: Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: _isPressed ? widget.tc.withValues(alpha: 0.15) : widget.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.border),
        boxShadow: _isPressed ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), offset: const Offset(0, 1), blurRadius: 1)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            widget.label,
            style: GoogleFonts.jost(fontSize: 18, color: widget.tc, fontWeight: FontWeight.w500),
          ),
          if (widget.accents.isNotEmpty)
            Positioned(
              top: 4, right: 4,
              child: Container(
                width: 4, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Mod extends StatefulWidget {
  final String?   label;
  final IconData? icon;
  final bool   active;
  final Color  bg, border, tc;
  final VoidCallback onTap;

  const _Mod({
    this.label, this.icon,
    required this.active,
    required this.bg, required this.border, required this.tc,
    required this.onTap,
  });

  @override
  State<_Mod> createState() => _ModState();
}

class _ModState extends State<_Mod> {
  bool _isPressed = false;

  @override
  Widget build(_) => GestureDetector(
    onTapDown: (_) => setState(() => _isPressed = true),
    onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); HapticFeedback.lightImpact(); },
    onTapCancel: () => setState(() => _isPressed = false),
    child: Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: widget.active 
            ? AppColors.accent.withValues(alpha: 0.25) 
            : (_isPressed ? widget.tc.withValues(alpha: 0.15) : widget.bg),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.active ? AppColors.accent : widget.border,
          width: widget.active ? 1.5 : 1,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: widget.icon != null
                ? Icon(widget.icon, size: 20, color: widget.active ? AppColors.accent : widget.tc)
                : Text(widget.label ?? '',
                  style: GoogleFonts.jost(
                      fontSize: 12,
                      color: widget.active ? AppColors.accent : widget.tc,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
          ),
        ),
      ),
    ),
  );
}

class _NavBtn extends StatefulWidget {
  final IconData icon;
  final Color  bg, border, tc;
  final VoidCallback onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  const _NavBtn({
    required this.icon,
    required this.bg, required this.border, required this.tc,
    required this.onTap, this.onLongPressStart, this.onLongPressEnd,
  });

  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  bool _isPressed = false;

  @override
  Widget build(_) => Expanded(
    child: GestureDetector(
      onTapDown: (_) { setState(() => _isPressed = true); widget.onLongPressStart?.call(); },
      onTapUp: (_) { setState(() => _isPressed = false); widget.onLongPressEnd?.call(); widget.onTap(); },
      onTapCancel: () { setState(() => _isPressed = false); widget.onLongPressEnd?.call(); },
      child: Container(
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: _isPressed ? widget.tc.withValues(alpha: 0.15) : widget.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: widget.border),
          boxShadow: _isPressed ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), offset: const Offset(0, 1), blurRadius: 1)],
        ),
        child: Center(
          child: Icon(widget.icon, size: 24, color: widget.tc),
        ),
      ),
    ),
  );
}

class _ModeBtn extends StatefulWidget {
  final String label;
  final bool   active;
  final Color  bg, border, tc;
  final VoidCallback onTap;

  const _ModeBtn({
    required this.label, required this.active,
    required this.bg, required this.border, required this.tc,
    required this.onTap,
  });

  @override
  State<_ModeBtn> createState() => _ModeBtnState();
}

class _ModeBtnState extends State<_ModeBtn> {
  bool _isPressed = false;

  @override
  Widget build(_) => Expanded(
    child: GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); HapticFeedback.mediumImpact(); },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: widget.active
              ? AppColors.accent.withValues(alpha: 0.22)
              : (_isPressed ? widget.tc.withValues(alpha: 0.12) : widget.bg),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.active ? AppColors.accent : widget.border,
            width: widget.active ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(widget.label,
              style: GoogleFonts.jost(
                  fontSize: 14,
                  color: widget.active ? AppColors.accent : widget.tc,
                  fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    ),
  );
}

class _SymbolEmojiKey extends StatefulWidget {
  final String label;
  final Color textColor, keyBg, border;
  final bool isEmoji;
  final VoidCallback onTap;

  const _SymbolEmojiKey({
    required this.label,
    required this.textColor,
    required this.keyBg,
    required this.border,
    this.isEmoji = false,
    required this.onTap,
  });

  @override
  State<_SymbolEmojiKey> createState() => _SymbolEmojiKeyState();
}

class _SymbolEmojiKeyState extends State<_SymbolEmojiKey> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) { setState(() => _isPressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        decoration: BoxDecoration(
          color: _isPressed ? widget.textColor.withValues(alpha: 0.15) : widget.keyBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: widget.border),
        ),
        child: Center(
          child: Text(
            widget.label, 
            style: TextStyle(fontSize: widget.isEmoji ? 22 : 14, color: widget.textColor),
          ),
        ),
      ),
    );
  }
}

class _AccentPopup extends StatelessWidget {
  final double anchorLeft;
  final double anchorTop;
  final double anchorWidth;
  final List<String> accents;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  const _AccentPopup({
    required this.anchorLeft,
    required this.anchorTop,
    required this.anchorWidth,
    required this.accents,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const kW = 42.0; 
    const kH = 48.0;
    const kPad = 6.0;
    final popupW = accents.length * kW + kPad * 2;

    double left = anchorLeft + (anchorWidth - popupW) / 2;
    final screenW = MediaQuery.of(context).size.width;
    if (left + popupW > screenW - 6) left = screenW - popupW - 6;
    if (left < 6) left = 6;
    final top = anchorTop - kH - 12;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top:  top,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.surface,
            child: Container(
              padding: const EdgeInsets.all(kPad),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: accents.map((c) => GestureDetector(
                  onTap: () => onSelect(c),
                  child: Container(
                    width: kW,
                    height: kH - kPad * 2,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: AppColors.accent.withValues(alpha: 0.08),
                    ),
                    child: Center(
                      child: Text(c,
                          style: GoogleFonts.jost(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent)),
                    ),
                  ),
                )).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}