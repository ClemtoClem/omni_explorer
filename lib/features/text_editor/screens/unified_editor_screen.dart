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
///   - Barre d'état, recherche / remplacement (casse, mot entier, expression),
///     palette de commandes (Ctrl+Maj+P), opérations sur les lignes,
///     recherche dans le projet, nouveau fichier / enregistrer sous
///
/// Modèle et état : `models/editor_tab.dart`,
/// `providers/unified_editor_provider.dart`.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
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
import '../../file_explorer/explorer_picker.dart';
import '../../file_explorer/screens/file_explorer_screen.dart';
import '../languages/language_registry.dart';
import '../widgets/terminal_panel.dart';
import '../completions/language_completions.dart';
import '../models/editor_cursor.dart';
import '../models/editor_tab.dart';
import '../models/project_node.dart';
import '../models/rich_text_controller.dart';
import '../models/editor_view_mode.dart';
import '../services/editor_drafts.dart';
import '../services/editor_encoding.dart';
import '../services/code_ctrl_adapter.dart';
import '../services/editor_open_policy.dart';
import '../services/hex_file_io.dart';
import '../services/line_operations.dart';
import '../services/project_search.dart';
import '../services/text_search.dart';
import '../providers/unified_editor_provider.dart';
import '../services/workspace_service.dart';
import '../widgets/command_palette.dart';
import '../widgets/editor_search_bar.dart';
import '../widgets/editor_status_bar.dart';
import '../widgets/editor_tab_bar.dart';
import '../widgets/go_to_line_dialog.dart';
import 'project_search_screen.dart';
import 'workspace_settings_screen.dart';

export '../models/editor_view_mode.dart';
export '../providers/unified_editor_provider.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────

const int _hexBytesPerRow = 8;

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── État persistant (survit aux navigations) ──────────────────────────────

  late UnifiedEditorProvider _p;

  // ── Terminal ──────────────────────────────────────────────────────────────

  bool _showTerminal = false;
  final List<String> _termLines = [];
  Process? _runProcess;

  // ── Recherche ─────────────────────────────────────────────────────────────

  bool _showSearch = false;
  final _searchBarKey = GlobalKey<EditorSearchBarState>();
  TextSearchQuery _searchQuery = const TextSearchQuery('');
  bool _searchReplace = false;

  /// Occurrences dans l'onglet actif, recalculées quand la requête ou le
  /// texte change (même minuterie que la barre d'état).
  List<TextMatch> _matches = const [];
  int _matchIndex = -1;

  // ── Autocomplétion ────────────────────────────────────────────────────────

  List<String> _completions = [];
  List<String> _wsSymbols = [];
  Timer? _completionDebounce;

  // ── Barre d'état ──────────────────────────────────────────────────────────

  /// Position et taille du document actif. Notifier dédié : déplacer le
  /// curseur ne reconstruit que la barre d'état, pas tout l'écran.
  final _stats = ValueNotifier<_DocStats>(_DocStats.empty);
  Timer? _statsTimer;

  /// Contrôleur pour lequel [_stats] a été calculé : un changement d'onglet
  /// ou de mode impose un recalcul.
  Object? _statsSource;

  // ── Clavier custom ────────────────────────────────────────────────────────

  final FocusNode _editorFocus = FocusNode();
  CodeCtrlAdapter? _kbAdapter;

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Les onglets sont conservés dans UnifiedEditorProvider — pas de dispose ici.
    _editorFocus.dispose();
    _runProcess?.kill();
    _completionDebounce?.cancel();
    _statsTimer?.cancel();
    _stats.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `hidden` précède `paused` sur toutes les plateformes ; `inactive` est
    // ignoré (volet de notifications, dialogue système : l'application
    // reste visible).
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistDrafts();
    }
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

  /// Écrit un brouillon de chaque onglet texte modifié. Le fichier lui-même
  /// n'est pas touché : sauvegarder reste une décision de l'utilisateur.
  Future<void> _persistDrafts() async {
    for (final tab in List.of(_p.tabs)) {
      if (!tab.isDirty || tab.viewMode == EditorViewMode.hex) continue;
      try {
        await EditorDrafts.save(EditorDraft(
          path: tab.path,
          content: tab.currentText,
          encoding: tab.encoding,
          savedAt: DateTime.now(),
          baseModified: tab.diskModified,
          baseSize: tab.diskSize,
        ));
      } catch (_) {
        // Au mieux : l'application part en arrière-plan, pas de message.
      }
    }
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

    EditorTab tab;
    if (mode == EditorViewMode.hex) {
      tab = EditorTab(
          path: path,
          content: '',
          isReadOnly: true,
          viewMode: mode,
          lang: lang);
      if (!await _loadHexBytes(tab, path)) {
        tab.dispose();
        return;
      }
    } else {
      final List<int> raw;
      final FileStat stat;
      try {
        raw = await File(path).readAsBytes();
        stat = await File(path).stat();
      } on FileSystemException catch (e) {
        _showErr('Lecture impossible : ${e.message}');
        return;
      }
      final decoded = _decodeText(raw, probe.encoding);
      if (decoded == null) return;
      var (content, encoding) = decoded;

      // Brouillon laissé par une session interrompue (application tuée en
      // arrière-plan) : proposer de le reprendre.
      var restored = false;
      final draft = await EditorDrafts.load(path);
      if (draft != null && draft.content != content) {
        final changedOnDisk =
            draft.baseModified != stat.modified || draft.baseSize != stat.size;
        restored = await _confirmRestoreDraft(path, changedOnDisk);
        if (restored) {
          content = draft.content;
          encoding = draft.encoding;
        }
      }
      if (draft != null && !restored) await EditorDrafts.delete(path);

      tab = EditorTab(
          path: path,
          content: content,
          isReadOnly: !restored,
          viewMode: mode,
          lang: lang)
        ..encoding = encoding
        ..diskModified = stat.modified
        ..diskSize = stat.size
        ..isDirty = restored;
      if (mode == EditorViewMode.richText) await _loadRichFmt(tab);
      _attachListeners(tab);
    }

    if (!mounted) return;
    setState(() {
      _p.tabs.add(tab);
      _p.activeTabIndex = _p.tabs.length - 1;
      _syncKb();
    });
    _p.tabsChanged();
    _restoreCursor(tab);
    if (mounted) {
      context.read<SettingsService>().addRecentFile(path);
    }
  }

  /// Replace le curseur où il était quand le fichier a été fermé (pendant
  /// la session).
  void _restoreCursor(EditorTab tab) {
    final cursor = _p.cursors[tab.path];
    if (cursor == null || cursor == EditorCursor.start) return;
    _moveCursorTo(tab, cursor.line, cursor.column);
  }

  /// Place le curseur de [tab] en [line]:[column] (1-indexées, bornées au
  /// document) et fait défiler jusqu'à lui.
  void _moveCursorTo(EditorTab tab, int line, int column, {int length = 0}) {
    final code = tab.codeCtrl;
    final ctrl = tab.textCtrl ?? tab.richCtrl;
    final text = code?.text ?? ctrl?.text;
    if (text == null) return;
    var start = EditorCursor.offsetOfLine(text, line);
    if (start < 0) start = text.length;
    var lineEnd = text.indexOf('\n', start);
    if (lineEnd < 0) lineEnd = text.length;
    final offset = (start + column - 1).clamp(start, lineEnd);
    _selectRange(tab, offset, (offset + length).clamp(offset, text.length));
  }

  /// Sélectionne [start, end[ dans l'onglet [tab] et fait défiler jusqu'à
  /// la sélection.
  void _selectRange(EditorTab tab, int start, int end, {bool focus = false}) {
    final code = tab.codeCtrl;
    if (code != null) {
      final text = code.text;
      final a = _toLC(text, start), b = _toLC(text, end);
      code.selection = CodeLineSelection(
        baseIndex: a.$1,
        baseOffset: a.$2,
        extentIndex: b.$1,
        extentOffset: b.$2,
      );
      // Éditeur pas encore construit (onglet qui vient de s'ouvrir) : le
      // défilement attend la prochaine frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (tab.codeCtrl == code) code.makeCursorVisible();
      });
    } else {
      final ctrl = tab.textCtrl ?? tab.richCtrl;
      if (ctrl == null) return;
      ctrl.selection = TextSelection(baseOffset: start, extentOffset: end);
    }
    // Un champ texte ne fait défiler jusqu'à la sélection qu'avec le focus.
    if (focus) _editorFocus.requestFocus();
  }

  /// Décode [raw] avec l'encodage détecté sur le début du fichier. Si de
  /// l'UTF-8 invalide apparaît plus loin que la partie analysée, le fichier
  /// est relu en Windows-1252, qui accepte tous les octets. Retourne `null`
  /// si le décodage est impossible (message déjà affiché).
  (String, EditorEncoding)? _decodeText(List<int> raw, EditorEncoding enc) {
    try {
      return (EditorEncodingCodec.decode(raw, enc), enc);
    } on EditorEncodingException catch (e) {
      if (enc != EditorEncoding.utf8) {
        _showErr('Lecture impossible : $e');
        return null;
      }
      _snack('UTF-8 invalide plus loin dans le fichier : ouvert en '
          '${EditorEncoding.windows1252.label}.');
      return (
        EditorEncodingCodec.decode(raw, EditorEncoding.windows1252),
        EditorEncoding.windows1252,
      );
    }
  }

  Future<bool> _confirmRestoreDraft(String path, bool changedOnDisk) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: const Text('Modifications non sauvegardées'),
        content: Text(
            '« ${p.basename(path)} » a été modifié lors d\'une session '
            'précédente, sans être sauvegardé. Reprendre ces modifications ?'
            '${changedOnDisk ? '\n\nAttention : le fichier a changé sur le '
                'disque depuis.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Abandonner')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Reprendre')),
        ],
      ),
    );
    return ok == true;
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
        content: Text('$why\n\n'
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
  Future<bool> _loadHexBytes(EditorTab tab, String path) async {
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

  Future<void> _loadRichFmt(EditorTab tab) async {
    final fmtFile = File('${tab.path}.fmt');
    if (fmtFile.existsSync()) {
      try {
        tab.richCtrl?.loadFromJson(await fmtFile.readAsString());
      } catch (_) {}
    }
  }

  void _attachListeners(EditorTab tab) {
    tab.codeCtrl?.addListener(() {
      _updateCompletions(tab);
      _scheduleStats(tab);
    });
    tab.textCtrl?.addListener(() {
      _updateCompletionsTxt(tab);
      _scheduleStats(tab);
    });
    tab.richCtrl?.addListener(() {
      _updateCompletionsTxt(tab);
      _scheduleStats(tab);
    });
  }

  // ── Barre d'état ──────────────────────────────────────────────────────────

  /// Recalcule la position et la taille du document actif au prochain tour
  /// de boucle : les contrôleurs notifient aussi pendant la construction des
  /// widgets (même raison que pour l'autocomplétion), et plusieurs
  /// notifications d'une même frappe n'entraînent qu'un calcul.
  void _scheduleStats([EditorTab? from]) {
    if (from != null && from != _p.activeTab) return;
    _statsTimer?.cancel();
    _statsTimer = Timer(Duration.zero, () {
      if (!mounted) return;
      _stats.value = _computeStats(_p.activeTab);
      if (_showSearch) _refreshMatches();
    });
  }

  _DocStats _computeStats(EditorTab? tab) {
    if (tab == null) return _DocStats.empty;
    final code = tab.codeCtrl;
    if (code != null) {
      final sel = code.selection;
      // Longueur sans construire le texte complet : caractères des lignes
      // (repliées comprises) et fins de ligne.
      var chars = 0;
      for (final segment in code.codeLines.segments) {
        for (final line in segment) {
          chars += line.charCount;
        }
      }
      return _DocStats(
        EditorCursor(line: sel.extentIndex + 1, column: sel.extentOffset + 1),
        code.lineCount,
        chars + code.lineCount - 1,
      );
    }
    final ctrl = tab.textCtrl ?? tab.richCtrl;
    final text = ctrl?.text ?? tab.content;
    return _DocStats(
      EditorCursor.fromOffset(text, ctrl?.selection.extentOffset ?? 0),
      EditorCursor.lineCountOf(text),
      text.length,
    );
  }

  Future<void> _showGoToLine() async {
    final tab = _p.activeTab;
    if (tab == null || tab.viewMode == EditorViewMode.hex) return;
    final stats = _computeStats(tab);
    final line = await showGoToLineDialog(
      context,
      lineCount: stats.lineCount,
      currentLine: stats.cursor.line,
    );
    if (line == null || !mounted || !_p.tabs.contains(tab)) return;
    _moveCursorTo(tab, line, 1);
    _editorFocus.requestFocus();
  }

  /// Change l'encodage de l'onglet actif : relire le fichier avec un autre
  /// encodage (onglet sans modification), ou enregistrer le texte avec un
  /// autre encodage à la prochaine sauvegarde.
  Future<void> _showEncodingPicker() async {
    final tab = _p.activeTab;
    if (tab == null || tab.viewMode == EditorViewMode.hex) return;
    final canReopen = !tab.isDirty;
    final choice = await showModalBottomSheet<(bool, EditorEncoding)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sCtx) {
        Widget section(String title, bool reopen) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child:
                      Text(title, style: Theme.of(sCtx).textTheme.titleSmall),
                ),
                for (final e in EditorEncoding.values)
                  ListTile(
                    dense: true,
                    title: Text(e.label),
                    trailing: e == tab.encoding
                        ? Icon(Icons.check_rounded, color: AppColors.accent)
                        : null,
                    onTap: () => Navigator.pop(sCtx, (reopen, e)),
                  ),
              ],
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canReopen) section('Rouvrir avec l\'encodage', true),
                section('Enregistrer avec l\'encodage', false),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted || !_p.tabs.contains(tab)) return;
    final (reopen, encoding) = choice;
    if (!reopen) {
      if (encoding == tab.encoding) return;
      setState(() {
        tab.encoding = encoding;
        tab.isDirty = true; // les octets du fichier vont changer
      });
      _snack('Sera enregistré en ${encoding.label}');
      return;
    }
    final List<int> raw;
    try {
      raw = await File(tab.path).readAsBytes();
    } on FileSystemException catch (e) {
      _showErr('Lecture impossible : ${e.message}');
      return;
    }
    final String text;
    try {
      text = EditorEncodingCodec.decode(raw, encoding);
    } on EditorEncodingException catch (e) {
      _showErr('Ce fichier n\'est pas en ${encoding.label} : $e');
      return;
    }
    if (!mounted || !_p.tabs.contains(tab)) return;
    setState(() {
      tab.encoding = encoding;
      tab.reload(text);
      _attachListeners(tab);
      _syncKb();
    });
    if (tab.viewMode == EditorViewMode.richText) await _loadRichFmt(tab);
  }

  /// Choisit le langage de l'onglet actif (coloration, autocomplétion,
  /// exécution), indépendamment de l'extension.
  Future<void> _showLanguagePicker() async {
    final tab = _p.activeTab;
    if (tab == null || tab.viewMode == EditorViewMode.hex) return;
    final langs = LanguageRegistry.instance.all
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    // Sentinelle « texte brut » : null signifie « fermé sans choisir ».
    const plain = '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Texte brut'),
              trailing: tab.lang == null
                  ? Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.pop(sCtx, plain),
            ),
            for (final l in langs)
              ListTile(
                leading: Icon(l.icon, color: l.color),
                title: Text(l.label),
                trailing: tab.lang?.id == l.id
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(sCtx, l.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted || !_p.tabs.contains(tab)) return;
    final lang =
        picked == plain ? null : langs.firstWhere((l) => l.id == picked);
    setState(() => tab.lang = lang);
    _scheduleStats();
    // Un langage choisi en texte brut : passer en code pour la coloration
    // (les limites de taille d'EditorOpenPolicy s'appliquent).
    if (lang != null &&
        lang.id != 'plaintext' &&
        tab.viewMode == EditorViewMode.text) {
      await _switchViewMode(lang.id == 'markdown'
          ? EditorViewMode.markdown
          : EditorViewMode.code);
    }
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

    final newContent = tab.currentText;
    final Uint8List encoded;
    try {
      encoded = EditorEncodingCodec.encode(newContent, tab.encoding);
    } on EditorEncodingException catch (e) {
      _showErr('$e Choisissez un autre encodage (barre d\'état) pour '
          'sauvegarder.');
      return;
    }

    try {
      // Écriture atomique : une interruption (application tuée, stockage
      // plein) laisse l'ancien contenu intact au lieu d'un fichier tronqué.
      await AtomicWrite.bytes(tab.path, encoded);
      tab.content = newContent;
      try {
        final stat = await File(tab.path).stat();
        tab.diskModified = stat.modified;
        tab.diskSize = stat.size;
      } on FileSystemException {
        // Sans effet sur la sauvegarde elle-même.
      }
      await EditorDrafts.delete(tab.path);
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

  Future<void> _closeTab(int idx) => _closeTabs([_p.tabs[idx]]);

  /// Ferme [toClose] dans l'ordre, en demandant pour chaque onglet modifié
  /// s'il faut le sauvegarder. « Annuler » interrompt la série : les onglets
  /// restants ne sont pas fermés.
  Future<void> _closeTabs(Iterable<EditorTab> toClose) async {
    for (final tab in List.of(toClose)) {
      if (!mounted || !_p.tabs.contains(tab)) continue;
      if (tab.isDirty || tab.hexModified) {
        setState(() => _p.activeTabIndex = _p.tabs.indexOf(tab));
        if (!await _confirmClose(tab) || !mounted) return;
      } else {
        await EditorDrafts.delete(tab.path);
        if (!mounted) return;
      }
      _removeTab(tab);
    }
  }

  /// Demande quoi faire des modifications de [tab]. Retourne `false` si
  /// l'utilisateur annule, ou si la sauvegarde demandée a échoué.
  Future<bool> _confirmClose(EditorTab tab) async {
    final res = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Modifications non sauvegardées'),
        content: Text('Sauvegarder « ${tab.name} » ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, 'discard'),
              child: const Text('Abandonner')),
          TextButton(
              onPressed: () => Navigator.pop(dCtx, 'cancel'),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, 'save'),
              child: const Text('Sauvegarder')),
        ],
      ),
    );
    switch (res) {
      case 'save':
        final idx = _p.tabs.indexOf(tab);
        if (idx < 0) return false;
        await _save(idx);
        return !tab.isDirty && !tab.hexModified;
      case 'discard':
        await EditorDrafts.delete(tab.path);
        return true;
      default:
        return false;
    }
  }

  /// Retire [tab] sans confirmation, en gardant si possible l'onglet actif.
  void _removeTab(EditorTab tab) {
    final idx = _p.tabs.indexOf(tab);
    if (idx < 0) return;
    final active = _p.activeTab;
    setState(() {
      _p.closedPaths
        ..remove(tab.path)
        ..add(tab.path);
      if (_p.closedPaths.length > 20) _p.closedPaths.removeAt(0);
      _p.cursors[tab.path] = _computeStats(tab).cursor;
      tab.dispose();
      _p.tabs.removeAt(idx);
      final keep = active == null ? -1 : _p.tabs.indexOf(active);
      if (keep >= 0) {
        _p.activeTabIndex = keep;
      } else if (_p.activeTabIndex >= _p.tabs.length) {
        _p.activeTabIndex = math.max(0, _p.tabs.length - 1);
      }
      _syncKb();
    });
    _p.tabsChanged();
  }

  Future<void> _handleTabAction(int index, TabAction action) async {
    if (index >= _p.tabs.length) return;
    final target = _p.tabs[index];
    final tabs = List.of(_p.tabs);
    switch (action) {
      case TabAction.close:
        await _closeTabs([target]);
      case TabAction.closeOthers:
        await _closeTabs(tabs.where((t) => t != target));
      case TabAction.closeToRight:
        await _closeTabs(tabs.sublist(index + 1));
      case TabAction.closeToLeft:
        await _closeTabs(tabs.sublist(0, index));
      case TabAction.closeAllUnmodified:
        await _closeTabs(tabs.where((t) => !t.isDirty && !t.hexModified));
      case TabAction.closeAll:
        await _closeTabs(tabs);
      case TabAction.reopenClosed:
        await _reopenClosed();
    }
  }

  Future<void> _reopenClosed() async {
    while (_p.closedPaths.isNotEmpty) {
      final path = _p.closedPaths.removeLast();
      if (await File(path).exists()) {
        await _openFile(path);
        return;
      }
    }
    _snack('Aucun onglet fermé à rouvrir');
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
      final cur = tab.currentText;
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
    final head = raw.length > EditorLimits.sniffBytes
        ? raw.sublist(0, EditorLimits.sniffBytes)
        : raw;
    final truncated = raw.length > head.length;
    final detected = EditorEncodingDetector.detect(head, truncated: truncated);
    if (FileProbe.isBinary(head, detected, truncated: truncated)) {
      _showErr('Ce fichier n\'est pas du texte : il reste affiché en '
          'hexadécimal.');
      return;
    }
    final decoded = _decodeText(raw, detected);
    if (decoded == null || !mounted) return;
    final (text, encoding) = decoded;
    setState(() {
      tab.content = text;
      tab.encoding = encoding;
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
  TextStyle _googleFontStyle(
    String family, {
    required double size,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
  }) {
    try {
      return GoogleFonts.getFont(family,
          fontSize: size, color: color, fontWeight: weight, height: height);
    } catch (_) {
      return TextStyle(
          fontSize: size, color: color, fontWeight: weight, height: height);
    }
  }

  void _syncKb() {
    final tab = _p.activeTab;
    if (tab?.codeCtrl != null) {
      _kbAdapter = CodeCtrlAdapter(tab!.codeCtrl!);
    } else {
      _kbAdapter = null;
    }
  }

  // ── Autocomplétion ────────────────────────────────────────────────────────

  void _updateCompletions(EditorTab tab) {
    final ctrl = tab.codeCtrl;
    if (ctrl == null) return;
    final flat = _codeFlat(ctrl);
    final word = _wordAt(ctrl.text, flat);
    _refreshSuggestions(word, tab);
  }

  void _updateCompletionsTxt(EditorTab tab) {
    final ctrl = tab.textCtrl ?? tab.richCtrl;
    if (ctrl == null) return;
    final word = _wordAt(ctrl.text, ctrl.selection.baseOffset);
    _refreshSuggestions(word, tab);
  }

  void _refreshSuggestions(String word, EditorTab tab) {
    final sug = LanguageCompletions.getSuggestions(
      prefix: word,
      languageId: tab.lang?.id ?? 'plaintext',
      currentFileContent: tab.content,
      workspaceSymbols: _wsSymbols,
    );

    // Le listener du contrôleur peut être appelé pendant la construction du
    // widget (CodeEditor.initState notifie le contrôleur). setState pendant
    // build lève une exception ; on repousse l'application de l'état au
    // prochain tour de la boucle d'événements.
    _completionDebounce?.cancel();
    if (!mounted) return;
    if (listEquals(sug, _completions)) return;
    _completionDebounce = Timer(Duration.zero, () {
      if (!mounted) return;
      setState(() => _completions = sug);
    });
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
      final newText =
          c.text.substring(0, flat) + suffix + c.text.substring(flat);
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
        workingDirectory:
            _p.isWorkspace ? _p.workspacePath : p.dirname(tab.path),
      );
      _runProcess!.stdout.transform(const SystemEncoding().decoder).listen((d) {
        if (mounted) setState(() => _termLines.addAll(d.split('\n')));
      });
      _runProcess!.stderr.transform(const SystemEncoding().decoder).listen((d) {
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

  Future<List<ProjectNode>> _buildTree(
      String dir, int depth, List<String> excl) async {
    if (depth > 8) return [];
    final nodes = <ProjectNode>[];
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
        nodes.add(ProjectNode(
          path: e.path,
          name: name,
          isDir: e is Directory,
          depth: depth,
        ));
      }
    } catch (_) {}
    return nodes;
  }

  Future<void> _toggleNode(ProjectNode node) async {
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

  void _hexSelect(EditorTab tab, int offset) {
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

  void _hexApply(EditorTab tab) {
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

  void _hexNav(EditorTab tab, int delta) {
    if (tab.bytes == null) return;
    final next = tab.hexSelectedOffset + delta;
    if (next < 0 || next >= tab.bytes!.length) return;
    _hexSelect(tab, next);
  }

  void _hexScroll(EditorTab tab, int offset) {
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

  // ── Recherche ─────────────────────────────────────────────────────────────

  /// Sélection de l'onglet en décalages dans le texte (début ≤ fin).
  (int, int) _selectionOf(EditorTab tab) {
    final code = tab.codeCtrl;
    final TextSelection sel;
    if (code != null) {
      sel = CodeCtrlAdapter(code).value.selection;
    } else {
      sel = (tab.textCtrl ?? tab.richCtrl)?.selection ??
          const TextSelection.collapsed(offset: 0);
    }
    if (!sel.isValid) return (0, 0);
    return (sel.start, sel.end);
  }

  /// Remplace tout le texte de l'onglet et place la sélection ; l'onglet
  /// devient « modifié ».
  void _replaceText(EditorTab tab, String text, int selStart, int selEnd) {
    final value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: selStart, extentOffset: selEnd),
    );
    final code = tab.codeCtrl;
    if (code != null) {
      CodeCtrlAdapter(code).value = value;
      code.makeCursorVisible();
    } else {
      (tab.textCtrl ?? tab.richCtrl)?.value = value;
    }
    setState(() => tab.isDirty = true);
  }

  void _openSearch({bool replace = false}) {
    final tab = _p.activeTab;
    if (tab == null || tab.viewMode == EditorViewMode.hex) return;
    // Texte sélectionné sur une ligne : motif proposé.
    final (a, b) = _selectionOf(tab);
    final selected =
        b > a && b - a <= 200 ? tab.currentText.substring(a, b) : '';
    final seed = selected.contains('\n') ? '' : selected;
    if (_showSearch) {
      _searchBarKey.currentState?.focus(pattern: seed, replace: replace);
      return;
    }
    setState(() {
      _showSearch = true;
      _searchReplace = replace;
      if (seed.isNotEmpty) _searchQuery = _searchQuery.copyWith(pattern: seed);
    });
    _refreshMatches(select: true);
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _matches = const [];
      _matchIndex = -1;
    });
    _editorFocus.requestFocus();
  }

  void _onSearchQuery(TextSearchQuery q) {
    _searchQuery = q;
    _refreshMatches(select: true);
  }

  /// Recalcule les occurrences dans l'onglet actif. Avec [select], la
  /// première occurrence à partir du curseur est sélectionnée.
  void _refreshMatches({bool select = false}) {
    final tab = _p.activeTab;
    if (!_showSearch || tab == null || tab.viewMode == EditorViewMode.hex) {
      return;
    }
    final matches = TextSearch.findAll(tab.currentText, _searchQuery);
    // Occurrence courante : celle qui contient le curseur (l'éditeur de
    // code réduit la sélection à sa fin quand il perd le focus), sinon la
    // suivante.
    final (a, _) = _selectionOf(tab);
    var index = matches.indexWhere((m) => m.start <= a && a <= m.end);
    if (index < 0) index = TextSearch.indexAtOrAfter(matches, a);
    setState(() {
      _matches = matches;
      _matchIndex = index;
    });
    if (select && index >= 0) {
      _selectRange(tab, matches[index].start, matches[index].end);
    }
  }

  /// Va à l'occurrence suivante ([delta] = 1) ou précédente (-1).
  void _gotoMatch(int delta) {
    final tab = _p.activeTab;
    if (tab == null) return;
    final matches = TextSearch.findAll(tab.currentText, _searchQuery);
    if (matches.isEmpty) {
      setState(() {
        _matches = const [];
        _matchIndex = -1;
      });
      return;
    }
    final (a, b) = _selectionOf(tab);
    final onMatch = matches.indexWhere((m) => m.start == a && m.end == b);
    int index;
    if (onMatch >= 0) {
      index = (onMatch + delta) % matches.length;
    } else if (delta > 0) {
      index = TextSearch.indexAtOrAfter(matches, b);
    } else {
      index = matches.lastIndexWhere((m) => m.end < a);
      if (index < 0) index = matches.length - 1;
    }
    setState(() {
      _matches = matches;
      _matchIndex = index;
    });
    _selectRange(tab, matches[index].start, matches[index].end,
        focus: tab.codeCtrl == null);
  }

  /// Remplace l'occurrence sélectionnée puis passe à la suivante ; sans
  /// occurrence sélectionnée, va d'abord à la suivante.
  void _replaceCurrent(String replace) {
    final tab = _p.activeTab;
    if (tab == null || tab.isReadOnly) return;
    final text = tab.currentText;
    final matches = TextSearch.findAll(text, _searchQuery);
    final (a, b) = _selectionOf(tab);
    final i = matches.indexWhere((m) => m.start == a && m.end == b);
    if (i < 0) {
      _gotoMatch(1);
      return;
    }
    final m = matches[i];
    final by = TextSearch.replacementFor(text, m, _searchQuery, replace);
    final newText = text.replaceRange(m.start, m.end, by);
    final after = m.start + by.length;
    _replaceText(tab, newText, after, after);
    _gotoMatch(1);
  }

  void _replaceAll(String replace) {
    final tab = _p.activeTab;
    if (tab == null || tab.isReadOnly) return;
    final (newText, count) =
        TextSearch.replaceAll(tab.currentText, _searchQuery, replace);
    if (count == 0) return;
    final (a, _) = _selectionOf(tab);
    final caret = a.clamp(0, newText.length);
    _replaceText(tab, newText, caret, caret);
    _refreshMatches();
    _snack('$count remplacement${count > 1 ? 's' : ''}');
  }

  // ── Opérations sur les lignes ─────────────────────────────────────────────

  bool get _canEditLines {
    final tab = _p.activeTab;
    return tab != null &&
        !tab.isReadOnly &&
        tab.viewMode != EditorViewMode.hex &&
        !(tab.viewMode == EditorViewMode.markdown && tab.showMdPreview);
  }

  void _lineOp(LineEdit Function(String text, int start, int end) op) {
    final tab = _p.activeTab;
    if (tab == null || !_canEditLines) return;
    final text = tab.currentText;
    final (a, b) = _selectionOf(tab);
    final edit = op(text, a, b);
    if (edit.text == text) return;
    _replaceText(tab, edit.text, edit.selectionStart, edit.selectionEnd);
  }

  LineComment? get _commentSyntax {
    final tab = _p.activeTab;
    if (tab == null) return null;
    if (tab.viewMode == EditorViewMode.markdown) {
      return LineComment.forLanguage('markdown');
    }
    return LineComment.forLanguage(tab.lang?.id);
  }

  void _toggleComment() {
    final syntax = _commentSyntax;
    if (syntax == null) {
      _snack('Pas de commentaire de ligne pour ce langage');
      return;
    }
    _lineOp((t, a, b) => LineOperations.toggleComment(t, a, b, syntax));
  }

  void _duplicateLines() => _lineOp(LineOperations.duplicate);
  void _deleteLines() => _lineOp(LineOperations.delete);
  void _moveLines(bool up) =>
      _lineOp((t, a, b) => LineOperations.move(t, a, b, up: up));

  // ── Fichiers : nouveau, ouvrir, enregistrer sous, révéler ─────────────────

  /// Dossier proposé par les sélecteurs : projet, sinon dossier du fichier
  /// actif.
  String? get _pickerStart {
    if (_p.isWorkspace) return _p.workspacePath;
    final tab = _p.activeTab;
    return tab == null ? null : p.dirname(tab.path);
  }

  Future<void> _newFile() async {
    final path = await ExplorerPicker.saveFile(
      context,
      title: 'Nouveau fichier',
      fileName: 'sans_titre.txt',
      initialPath: _pickerStart,
    );
    if (path == null || !mounted) return;
    try {
      final f = File(path);
      // Un fichier existant (remplacement confirmé dans l'explorateur) est
      // ouvert tel quel : « Nouveau » ne doit pas effacer son contenu.
      if (!await f.exists()) await f.create(recursive: true);
    } on FileSystemException catch (e) {
      _showErr('Création impossible : ${e.message}');
      return;
    }
    await _openFile(path);
    final i = _p.indexOfPath(path);
    if (i >= 0) _enableEdit(i);
    if (_p.isWorkspace) await _refreshTree();
  }

  Future<void> _openFiles() async {
    final paths = await ExplorerPicker.pickFiles(context,
        title: 'Ouvrir dans l\'éditeur', initialPath: _pickerStart);
    for (final path in paths) {
      if (!mounted) return;
      await _openFile(path);
    }
  }

  /// Écrit le texte de l'onglet actif dans un autre fichier, qui le remplace
  /// dans l'onglet. Le fichier d'origine n'est pas modifié.
  Future<void> _saveAs() async {
    final tab = _p.activeTab;
    if (tab == null || tab.viewMode == EditorViewMode.hex) return;
    final target = await ExplorerPicker.saveFile(
      context,
      fileName: tab.name,
      initialPath: p.dirname(tab.path),
    );
    if (target == null || !mounted || !_p.tabs.contains(tab)) return;
    if (target == tab.path) {
      await _save(_p.tabs.indexOf(tab));
      return;
    }
    final text = tab.currentText;
    try {
      final bytes = EditorEncodingCodec.encode(text, tab.encoding);
      await AtomicWrite.bytes(target, bytes);
      if (tab.viewMode == EditorViewMode.richText && tab.richCtrl != null) {
        await AtomicWrite.string('$target.fmt', tab.richCtrl!.formattingJson);
      }
    } on EditorEncodingException catch (e) {
      _showErr('$e Choisissez un autre encodage (barre d\'état).');
      return;
    } catch (e) {
      _showErr('Enregistrement impossible : $e');
      return;
    }
    if (!mounted) return;
    // L'onglet d'origine laisse la place au nouveau fichier, au même rang.
    final index = _p.tabs.indexOf(tab);
    final existing = _p.indexOfPath(target);
    if (existing >= 0) _removeTab(_p.tabs[existing]);
    await EditorDrafts.delete(tab.path);
    final cursor = _computeStats(tab).cursor;
    _removeTab(tab);
    _p.closedPaths.remove(tab.path);
    await _openFile(target);
    final opened = _p.indexOfPath(target);
    if (opened < 0 || !mounted) return;
    final moved = _p.tabs.removeAt(opened);
    final at = index.clamp(0, _p.tabs.length);
    setState(() {
      _p.tabs.insert(at, moved);
      _p.activeTabIndex = at;
      moved.isReadOnly = false;
      _syncKb();
    });
    _moveCursorTo(moved, cursor.line, cursor.column);
    _p.tabsChanged();
    if (_p.isWorkspace) await _refreshTree();
    _snack('Enregistré sous ${p.basename(target)}');
  }

  void _revealInExplorer() {
    final tab = _p.activeTab;
    if (tab == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileExplorerScreen(initialPath: p.dirname(tab.path)),
      ),
    );
  }

  Future<void> _refreshTree() async {
    final tree = await _buildTree(_p.workspacePath, 0, _p.ws.excludePatterns);
    if (mounted) setState(() => _p.tree = tree);
  }

  // ── Projet : ouverture rapide, recherche ──────────────────────────────────

  Future<void> _quickOpen() async {
    if (!_p.isWorkspace) {
      await _openFiles();
      return;
    }
    final root = _p.workspacePath;
    final files =
        await ProjectSearch.listFiles(root, exclude: _p.ws.excludePatterns);
    if (!mounted) return;
    await showCommandPalette(
      context,
      hint: 'Ouvrir un fichier du projet…',
      items: [
        for (final f in files)
          PaletteItem(
            label: p.basename(f),
            detail: p.dirname(p.relative(f, from: root)) == '.'
                ? null
                : p.dirname(p.relative(f, from: root)),
            icon: _fileIcon(p.basename(f)),
            run: () => _openFile(f),
          ),
      ],
    );
  }

  Future<void> _searchProject() async {
    if (!_p.isWorkspace) return;
    final hit = await Navigator.push<ProjectSearchHit>(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectSearchScreen(
          root: _p.workspacePath,
          exclude: _p.ws.excludePatterns,
          initialQuery: _searchQuery,
        ),
      ),
    );
    if (hit == null || !mounted) return;
    await _openFile(hit.path);
    final tab = _p.activeTab;
    if (tab == null || tab.path != hit.path) return;
    _moveCursorTo(tab, hit.line, hit.column,
        length: hit.previewEnd - hit.previewStart);
  }

  // ── Palette de commandes ──────────────────────────────────────────────────

  List<PaletteItem> _commands() {
    final tab = _p.activeTab;
    final text = tab != null && tab.viewMode != EditorViewMode.hex;
    final dirty = tab != null && (tab.isDirty || tab.hexModified);
    final lines = _canEditLines;
    return [
      PaletteItem(
          label: 'Nouveau fichier…',
          icon: Icons.note_add_outlined,
          shortcut: 'Ctrl+N',
          run: _newFile),
      PaletteItem(
          label: 'Ouvrir un fichier…',
          icon: Icons.folder_open_outlined,
          shortcut: _p.isWorkspace ? 'Ctrl+P' : 'Ctrl+O',
          run: _p.isWorkspace ? _quickOpen : _openFiles),
      PaletteItem(
          label: 'Sauvegarder',
          icon: Icons.save_rounded,
          shortcut: 'Ctrl+S',
          enabled: dirty,
          run: _save),
      PaletteItem(
          label: 'Enregistrer sous…',
          icon: Icons.save_as_outlined,
          shortcut: 'Ctrl+Maj+S',
          enabled: text,
          run: _saveAs),
      PaletteItem(
          label: 'Révéler dans l\'explorateur',
          icon: Icons.folder_outlined,
          enabled: tab != null,
          run: _revealInExplorer),
      PaletteItem(
          label: 'Fermer l\'onglet',
          icon: Icons.close_rounded,
          shortcut: 'Ctrl+W',
          enabled: tab != null,
          run: _closeActiveTab),
      PaletteItem(
          label: 'Rouvrir le dernier onglet fermé',
          icon: Icons.restore_rounded,
          shortcut: 'Ctrl+Maj+T',
          enabled: _p.closedPaths.isNotEmpty,
          run: _reopenClosed),
      PaletteItem(
          label: 'Rechercher',
          icon: Icons.search_rounded,
          shortcut: 'Ctrl+F',
          enabled: text,
          run: _openSearch),
      PaletteItem(
          label: 'Remplacer',
          icon: Icons.find_replace_rounded,
          shortcut: 'Ctrl+H',
          enabled: text && !tab.isReadOnly,
          run: () => _openSearch(replace: true)),
      if (_p.isWorkspace)
        PaletteItem(
            label: 'Rechercher dans le projet…',
            icon: Icons.manage_search_rounded,
            shortcut: 'Ctrl+Maj+F',
            run: _searchProject),
      PaletteItem(
          label: 'Aller à la ligne…',
          icon: Icons.low_priority_rounded,
          shortcut: 'Ctrl+G',
          enabled: text,
          run: _showGoToLine),
      PaletteItem(
          label: 'Commenter / décommenter les lignes',
          icon: Icons.comment_outlined,
          shortcut: 'Ctrl+/',
          enabled: lines && _commentSyntax != null,
          run: _toggleComment),
      PaletteItem(
          label: 'Dupliquer les lignes',
          icon: Icons.copy_all_outlined,
          shortcut: 'Ctrl+Maj+D',
          enabled: lines,
          run: _duplicateLines),
      PaletteItem(
          label: 'Monter les lignes',
          icon: Icons.arrow_upward_rounded,
          shortcut: 'Alt+↑',
          enabled: lines,
          run: () => _moveLines(true)),
      PaletteItem(
          label: 'Descendre les lignes',
          icon: Icons.arrow_downward_rounded,
          shortcut: 'Alt+↓',
          enabled: lines,
          run: () => _moveLines(false)),
      PaletteItem(
          label: 'Supprimer les lignes',
          icon: Icons.backspace_outlined,
          shortcut: 'Ctrl+Maj+K',
          enabled: lines,
          run: _deleteLines),
      PaletteItem(
          label: 'Passer en édition',
          icon: Icons.edit_outlined,
          enabled: tab != null && tab.isReadOnly,
          run: () => _enableEdit(_p.activeTabIndex)),
      PaletteItem(
          label: 'Changer le langage…',
          icon: Icons.code_rounded,
          enabled: text,
          run: _showLanguagePicker),
      PaletteItem(
          label: 'Changer l\'encodage…',
          icon: Icons.translate_rounded,
          enabled: text,
          run: _showEncodingPicker),
      for (final (mode, label, icon) in const [
        (EditorViewMode.code, 'Code', Icons.code_rounded),
        (EditorViewMode.markdown, 'Markdown', Icons.article_rounded),
        (EditorViewMode.text, 'Texte', Icons.text_snippet_outlined),
        (
          EditorViewMode.richText,
          'Texte enrichi',
          Icons.format_color_text_rounded
        ),
        (EditorViewMode.hex, 'Hexadécimal', Icons.memory_rounded),
      ])
        PaletteItem(
            label: 'Afficher en : $label',
            icon: icon,
            enabled: tab != null && tab.viewMode != mode,
            run: () => _switchViewMode(mode)),
      if (tab?.lang?.isRunnable == true)
        PaletteItem(
            label: 'Exécuter le fichier',
            icon: Icons.play_arrow_rounded,
            run: _run),
      PaletteItem(
          label: _showTerminal ? 'Masquer le terminal' : 'Afficher le terminal',
          icon: Icons.terminal_rounded,
          run: () => setState(() => _showTerminal = !_showTerminal)),
      if (_p.isWorkspace)
        PaletteItem(
            label: 'Paramètres du projet',
            icon: Icons.tune_rounded,
            run: _openWsSettings),
    ];
  }

  Future<void> _showPalette() =>
      showCommandPalette(context, items: _commands());

  void _closeActiveTab() {
    if (_p.activeTab != null) _closeTab(_p.activeTabIndex);
  }

  void _cycleTab(int delta) {
    if (_p.tabs.length < 2) return;
    setState(() {
      _p.activeTabIndex = (_p.activeTabIndex + delta) % _p.tabs.length;
      _syncKb();
    });
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
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
    context
        .watch<UnifiedEditorProvider>(); // rebuild quand les onglets changent
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settings = context.watch<SettingsService>();
    final useKb = _p.activeTab?.viewMode != EditorViewMode.hex &&
        !kIsWeb &&
        Platform.isAndroid &&
        (_p.ws.useCustomKeyboard ?? settings.useCustomKeyboard);

    // Police de code des Paramètres appliquée à chaud (hors projet, dont
    // les réglages priment).
    if (!_p.isWorkspace) {
      final family = _fontFamilyKey(settings.codeFontFamily);
      if (_p.ws.fontFamily != family ||
          _p.ws.fontSize != settings.codeFontSize) {
        _p.ws =
            _p.ws.copyWith(fontFamily: family, fontSize: settings.codeFontSize);
      }
    }

    final tab = _p.activeTab;
    final statsSource = tab?.codeCtrl ?? tab?.textCtrl ?? tab?.richCtrl ?? tab;
    if (!identical(statsSource, _statsSource)) {
      // Autre onglet ou autre mode : recalcul hors de la construction.
      _statsSource = statsSource;
      _scheduleStats();
    }

    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Scaffold(
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
                        if (_showSearch && tab != null)
                          EditorSearchBar(
                            key: _searchBarKey,
                            initialQuery: _searchQuery,
                            initialReplace: _searchReplace,
                            canReplace: !tab.isReadOnly,
                            matchIndex: _matchIndex,
                            matchCount: _matches.length,
                            onQueryChanged: _onSearchQuery,
                            onNext: () => _gotoMatch(1),
                            onPrevious: () => _gotoMatch(-1),
                            onReplace: _replaceCurrent,
                            onReplaceAll: _replaceAll,
                            onClose: _closeSearch,
                          ),
                        Expanded(child: _buildEditorContent(theme, isDark)),
                        if (_completions.isNotEmpty) _buildCompletionBar(theme),
                        if (_showTerminal)
                          TerminalPanel(
                            output: _termLines,
                            onClear: () => setState(() => _termLines.clear()),
                            onClose: () =>
                                setState(() => _showTerminal = false),
                            onStop: _runProcess != null ? _stopProcess : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (tab != null && tab.viewMode != EditorViewMode.hex)
              _buildStatusBar(tab),
            if (useKb && _kbAdapter != null)
              CustomKeyboard(
                focusNode: _editorFocus,
                controller: _kbAdapter,
              ),
          ],
        ),
      ),
    );
  }

  /// Raccourcis clavier de l'écran. En mode code, l'éditeur traite d'abord
  /// les siens (voir `shortcutOverrideActions` de [_buildCodeView]).
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    SingleActivator ctrl(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, control: true, shift: shift);
    return {
      ctrl(LogicalKeyboardKey.keyS): _save,
      ctrl(LogicalKeyboardKey.keyS, shift: true): _saveAs,
      ctrl(LogicalKeyboardKey.keyN): _newFile,
      ctrl(LogicalKeyboardKey.keyO): _openFiles,
      ctrl(LogicalKeyboardKey.keyP): _quickOpen,
      ctrl(LogicalKeyboardKey.keyP, shift: true): _showPalette,
      const SingleActivator(LogicalKeyboardKey.f1): _showPalette,
      ctrl(LogicalKeyboardKey.keyW): _closeActiveTab,
      ctrl(LogicalKeyboardKey.keyT, shift: true): _reopenClosed,
      ctrl(LogicalKeyboardKey.tab): () => _cycleTab(1),
      ctrl(LogicalKeyboardKey.tab, shift: true): () => _cycleTab(-1),
      ctrl(LogicalKeyboardKey.keyF): _openSearch,
      ctrl(LogicalKeyboardKey.keyH): () => _openSearch(replace: true),
      ctrl(LogicalKeyboardKey.keyF, shift: true): _searchProject,
      const SingleActivator(LogicalKeyboardKey.f3): () => _gotoMatch(1),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
          _gotoMatch(-1),
      ctrl(LogicalKeyboardKey.keyG): _showGoToLine,
      ctrl(LogicalKeyboardKey.slash): _toggleComment,
      ctrl(LogicalKeyboardKey.keyD, shift: true): _duplicateLines,
      ctrl(LogicalKeyboardKey.keyK, shift: true): _deleteLines,
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
          _moveLines(true),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
          _moveLines(false),
    };
  }

  Widget _buildStatusBar(EditorTab tab) {
    return ValueListenableBuilder<_DocStats>(
      valueListenable: _stats,
      builder: (_, stats, __) => EditorStatusBar(
        cursor: stats.cursor,
        lineCount: stats.lineCount,
        charCount: stats.charCount,
        encoding: tab.encoding,
        language: tab.lang,
        mode: tab.viewMode,
        dirty: tab.isDirty,
        onGoToLineTap: _showGoToLine,
        onEncodingTap: _showEncodingPicker,
        onLanguageTap: _showLanguagePicker,
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              _modeItem(EditorViewMode.text, Icons.text_snippet_outlined,
                  'Texte', tab),
              _modeItem(EditorViewMode.richText,
                  Icons.format_color_text_rounded, 'Texte enrichi', tab),
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
        if (tab != null && tab.viewMode != EditorViewMode.hex)
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 20),
            tooltip: 'Rechercher (Ctrl+F)',
            onPressed: _showSearch ? _closeSearch : _openSearch,
          ),
        IconButton(
          icon: const Icon(Icons.save_rounded, size: 20),
          tooltip: 'Sauvegarder',
          onPressed:
              (tab?.isDirty == true || tab?.hexModified == true) ? _save : null,
        ),
        if (tab?.lang?.isRunnable == true)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded),
            color: AppColors.success,
            tooltip: 'Exécuter',
            onPressed: _run,
          ),
        _buildMoreMenu(tab),
      ],
    );
  }

  /// Menu ⋮ : fichiers, lignes, outils. Les mêmes actions sont dans la
  /// palette de commandes.
  Widget _buildMoreMenu(EditorTab? tab) {
    final text = tab != null && tab.viewMode != EditorViewMode.hex;
    final lines = _canEditLines;
    PopupMenuEntry<VoidCallback> item(
            IconData icon, String label, VoidCallback action,
            {bool enabled = true}) =>
        PopupMenuItem<VoidCallback>(
          value: action,
          enabled: enabled,
          height: 40,
          child: Row(children: [
            Icon(icon, size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ]),
        );
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Plus d\'actions',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        item(Icons.bolt_rounded, 'Palette de commandes', _showPalette),
        const PopupMenuDivider(),
        item(Icons.note_add_outlined, 'Nouveau fichier…', _newFile),
        item(Icons.folder_open_outlined, 'Ouvrir…',
            _p.isWorkspace ? _quickOpen : _openFiles),
        item(Icons.save_as_outlined, 'Enregistrer sous…', _saveAs,
            enabled: text),
        item(Icons.folder_outlined, 'Révéler dans l\'explorateur',
            _revealInExplorer,
            enabled: tab != null),
        if (_p.isWorkspace)
          item(Icons.manage_search_rounded, 'Rechercher dans le projet…',
              _searchProject),
        if (lines) ...[
          const PopupMenuDivider(),
          item(Icons.comment_outlined, 'Commenter les lignes', _toggleComment,
              enabled: _commentSyntax != null),
          item(
              Icons.copy_all_outlined, 'Dupliquer les lignes', _duplicateLines),
          item(Icons.arrow_upward_rounded, 'Monter les lignes',
              () => _moveLines(true)),
          item(Icons.arrow_downward_rounded, 'Descendre les lignes',
              () => _moveLines(false)),
          item(Icons.backspace_outlined, 'Supprimer les lignes', _deleteLines),
        ],
        const PopupMenuDivider(),
        item(Icons.low_priority_rounded, 'Aller à la ligne…', _showGoToLine,
            enabled: text),
        item(
            Icons.terminal_rounded,
            _showTerminal ? 'Masquer le terminal' : 'Terminal',
            () => setState(() => _showTerminal = !_showTerminal)),
        if (_p.isWorkspace)
          item(Icons.tune_rounded, 'Paramètres du projet', _openWsSettings),
      ],
    );
  }

  PopupMenuItem<EditorViewMode> _modeItem(
      EditorViewMode mode, IconData icon, String label, EditorTab tab) {
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
    return EditorTabBar(
      tabs: [
        for (final t in _p.tabs)
          EditorTabInfo(
            path: t.path,
            name: t.name,
            isDirty: t.isDirty || t.hexModified,
            isReadOnly: t.isReadOnly,
          ),
      ],
      activeIndex: _p.activeTabIndex,
      onSelect: (i) => setState(() {
        _p.activeTabIndex = i;
        _syncKb();
      }),
      onDoubleTap: _enableEdit,
      onClose: _closeTab,
      onAction: _handleTabAction,
      canReopenClosed: _p.closedPaths.isNotEmpty,
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

  List<Widget> _buildTreeNodes(List<ProjectNode> nodes, ThemeData theme) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      widgets.add(_buildTreeNode(node, theme));
      if (node.expanded) {
        widgets.addAll(_buildTreeNodes(node.children, theme));
      }
    }
    return widgets;
  }

  Widget _buildTreeNode(ProjectNode node, ThemeData theme) {
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
              color: node.isDir ? AppColors.colorFolder : _fileColor(node.name),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                node.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isActive ? AppColors.accent : null,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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
        return lang != null
            ? Icons.code_rounded
            : Icons.insert_drive_file_outlined;
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
                size: 64, color: theme.iconTheme.color?.withValues(alpha: 0.1)),
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

  Widget _buildCodeView(EditorTab tab, ThemeData theme, bool isDark) {
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
      indicatorBuilder: _p.ws.showLineNumbers
          ? (context, editingController, chunkController, notifier) =>
              DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                textStyle: TextStyle(
                  fontSize: _p.ws.fontSize * 0.85,
                  color: theme.disabledColor,
                ),
                focusedTextStyle: TextStyle(
                  fontSize: _p.ws.fontSize * 0.85,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              )
          : null,
      shortcutsActivatorsBuilder: const DefaultCodeShortcutsActivatorsBuilder(),
      // Raccourcis de l'éditeur de code redirigés vers ceux de l'écran :
      // même comportement dans tous les modes.
      shortcutOverrideActions: {
        CodeShortcutSaveIntent:
            CallbackAction<CodeShortcutSaveIntent>(onInvoke: (_) => _save()),
        CodeShortcutFindIntent: CallbackAction<CodeShortcutFindIntent>(
            onInvoke: (_) => _openSearch()),
        CodeShortcutReplaceIntent: CallbackAction<CodeShortcutReplaceIntent>(
            onInvoke: (_) => _openSearch(replace: true)),
        CodeShortcutCommentIntent: CallbackAction<CodeShortcutCommentIntent>(
            onInvoke: (_) => _toggleComment()),
      },
    );
  }

  // ── Mode Markdown ─────────────────────────────────────────────────────────

  Widget _buildMarkdownView(EditorTab tab, ThemeData theme, bool isDark) {
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
    final txt =
        isDark ? Colors.white.withAlpha(222) : Colors.black.withAlpha(222);
    final codeColor =
        isDark ? const Color(0xFF89B4FA) : const Color(0xFF1565C0);
    final codeBg = isDark ? const Color(0xFF313244) : const Color(0xFFEEEEEE);
    final s = context.read<SettingsService>();
    final mdBase = _googleFontStyle(s.markdownFontFamily,
        size: s.markdownFontSize.toDouble(), color: txt, height: 1.6);
    return MarkdownStyleSheet(
      h1: mdBase.copyWith(
          fontSize: s.markdownFontSize * 1.8,
          fontWeight: FontWeight.bold,
          height: 1.4),
      h2: mdBase.copyWith(
          fontSize: s.markdownFontSize * 1.45,
          fontWeight: FontWeight.bold,
          height: 1.4),
      h3: mdBase.copyWith(
          fontSize: s.markdownFontSize * 1.2,
          fontWeight: FontWeight.bold,
          height: 1.4),
      p: mdBase,
      code: TextStyle(
          fontFamily: 'monospace',
          fontSize: s.markdownFontSize * 0.87,
          color: codeColor,
          backgroundColor: codeBg),
      codeblockDecoration:
          BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(8)),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(4),
        border:
            const Border(left: BorderSide(color: Color(0xFF89B4FA), width: 4)),
      ),
      blockquote: TextStyle(
          color: isDark ? Colors.white60 : Colors.black54,
          fontStyle: FontStyle.italic),
      listBullet: TextStyle(color: t.colorScheme.primary),
      tableHead: TextStyle(fontWeight: FontWeight.bold, color: txt),
      tableBody: TextStyle(color: txt),
      tableBorder:
          TableBorder.all(color: isDark ? Colors.white24 : Colors.black12),
    );
  }

  // ── Mode Texte ────────────────────────────────────────────────────────────

  Widget _buildTextView(EditorTab tab, ThemeData theme) {
    final s = context.read<SettingsService>();
    final style = _googleFontStyle(
      s.textFontFamily,
      size: s.textFontSize.toDouble(),
      color: theme.textTheme.bodyLarge?.color,
    );
    // Lecture seule : champ non modifiable plutôt que SelectableText, pour
    // que recherche et « Aller à la ligne » puissent sélectionner.
    return TextField(
      controller: tab.textCtrl,
      focusNode: _editorFocus,
      readOnly: tab.isReadOnly,
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

  Widget _buildRichView(EditorTab tab, ThemeData theme) {
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
                        TextSpan(text: tab.content, style: richStyle),
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

  Widget _buildRichToolbar(EditorTab tab, ThemeData theme) {
    return Container(
      height: 44,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _FmtBtn(
              icon: Icons.format_bold,
              tip: 'Gras',
              onTap: () => _applyFmt(tab, RichFmt.bold)),
          _FmtBtn(
              icon: Icons.format_italic,
              tip: 'Italique',
              onTap: () => _applyFmt(tab, RichFmt.italic)),
          _FmtBtn(
              icon: Icons.format_underlined,
              tip: 'Souligné',
              onTap: () => _applyFmt(tab, RichFmt.underline)),
          _FmtBtn(
              icon: Icons.format_strikethrough,
              tip: 'Barré',
              onTap: () => _applyFmt(tab, RichFmt.strikethrough)),
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

  void _applyFmt(EditorTab tab, RichFmt fmt) {
    final ctrl = tab.richCtrl;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    ctrl.toggleFormat(fmt, sel.start, sel.end);
    setState(() => tab.isDirty = true);
  }

  void _clearFmt(EditorTab tab) {
    final ctrl = tab.richCtrl;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    ctrl.clearRange(sel.start, sel.end);
    setState(() => tab.isDirty = true);
  }

  Future<void> _pickColor(EditorTab tab) async {
    const colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.white,
      Colors.black,
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

  Widget _buildHexView(EditorTab tab, ThemeData theme) {
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
  Widget _buildHexTruncatedBanner(EditorTab tab, ThemeData theme) {
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

  Widget _buildHexRow(EditorTab tab, int row, ThemeData theme) {
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
      color:
          row.isOdd ? theme.colorScheme.surface.withValues(alpha: 0.4) : null,
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
    final base =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;
    if (byte == 0x00) return base.withValues(alpha: 0.25);
    if (byte == 0xFF) return AppColors.warning.withValues(alpha: 0.8);
    if (byte < 0x20 || byte == 0x7F) {
      return AppColors.info.withValues(alpha: 0.8);
    }
    return base;
  }

  Widget _buildHexEditBar(EditorTab tab, ThemeData theme) {
    final bytes = tab.bytes!;
    final offset = tab.hexSelectedOffset;
    if (offset < 0 || offset >= bytes.length) return const SizedBox.shrink();
    final byte = bytes[offset];
    final dec = byte.toString().padLeft(3, ' ');
    final char =
        (byte >= 0x20 && byte < 0x7F) ? String.fromCharCode(byte) : '·';
    final hs = context.read<SettingsService>();
    final mono =
        _googleFontStyle(hs.hexFontFamily, size: hs.hexFontSize.toDouble());

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
                onPressed:
                    offset < bytes.length - 1 ? () => _hexNav(tab, 1) : null,
              ),
            ],
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
                border:
                    Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
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
  final EditorTab tab;
  const _ModeBadge({required this.tab});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (tab.viewMode) {
      EditorViewMode.code => (
          tab.lang?.label ?? 'Code',
          tab.lang?.color ?? AppColors.colorCode
        ),
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
        child: Padding(
            padding: const EdgeInsets.all(7), child: Icon(icon, size: 16)),
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

/// Position et taille du document actif, affichées par la barre d'état.
class _DocStats {
  final EditorCursor cursor;
  final int lineCount;
  final int charCount;

  const _DocStats(this.cursor, this.lineCount, this.charCount);

  static const empty = _DocStats(EditorCursor.start, 1, 0);

  @override
  bool operator ==(Object other) =>
      other is _DocStats &&
      other.cursor == cursor &&
      other.lineCount == lineCount &&
      other.charCount == charCount;

  @override
  int get hashCode => Object.hash(cursor, lineCount, charCount);
}
