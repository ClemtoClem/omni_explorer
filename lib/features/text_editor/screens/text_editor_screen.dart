/// @file text_editor_screen.dart
/// @brief Éditeur de texte et de code avec coloration syntaxique, gestion de projet et runner.
///
/// Fonctionnalités :
/// - Coloration syntaxique pour de nombreux langages via flutter_highlight
/// - Ouverture d'un répertoire comme projet (arborescence latérale)
/// - Runner Python (via shell) et serveur web local (via webview_flutter)
/// - Architecture modulaire : ajouter un langage = une entrée dans [LanguageRegistry]
/// - Onglets multiples
/// - Numéros de ligne, recherche/remplacement

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import '../../file_explorer/explorer_picker.dart';
import '../../../core/services/settings_service.dart';
import '../widgets/ssh_terminal_panel.dart';

// ---------------------------------------------------------------------------
// Registre des langages (modulaire)
// ---------------------------------------------------------------------------

/// @class LanguageDefinition
/// @brief Définit un langage supporté par l'éditeur.
class LanguageDefinition {
  /// Identifiant utilisé par flutter_highlight.
  final String highlightLanguage;

  /// Extensions de fichiers associées (sans le point).
  final List<String> extensions;

  /// Nom affiché dans l'UI.
  final String displayName;

  /// Commande de base pour exécuter un fichier (null = non exécutable).
  final RunnerConfig? runner;

  const LanguageDefinition({
    required this.highlightLanguage,
    required this.extensions,
    required this.displayName,
    this.runner,
  });
}

/// @class RunnerConfig
/// @brief Configuration du runner pour un langage donné.
class RunnerConfig {
  /// Commande (ex. 'python3', 'node').
  final String command;

  /// Type de sortie attendue.
  final RunnerType type;

  const RunnerConfig({required this.command, required this.type});
}

/// @enum RunnerType
/// @brief Type d'exécution du runner.
enum RunnerType { terminal, webServer }

/// @class LanguageRegistry
/// @brief Registre central de tous les langages supportés.
/// Pour ajouter un langage, ajouter une entrée dans [_languages].
class LanguageRegistry {
  static const List<LanguageDefinition> _languages = [
    LanguageDefinition(
      highlightLanguage: 'python',
      extensions: ['py'],
      displayName: 'Python',
      runner: RunnerConfig(command: 'python3', type: RunnerType.terminal),
    ),
    LanguageDefinition(
      highlightLanguage: 'javascript',
      extensions: ['js', 'mjs'],
      displayName: 'JavaScript',
      runner: RunnerConfig(command: 'node', type: RunnerType.terminal),
    ),
    LanguageDefinition(
      highlightLanguage: 'dart',
      extensions: ['dart'],
      displayName: 'Dart',
    ),
    LanguageDefinition(
      highlightLanguage: 'html',
      extensions: ['html', 'htm'],
      displayName: 'HTML',
      runner: RunnerConfig(command: '', type: RunnerType.webServer),
    ),
    LanguageDefinition(
      highlightLanguage: 'css',
      extensions: ['css'],
      displayName: 'CSS',
    ),
    LanguageDefinition(
      highlightLanguage: 'json',
      extensions: ['json'],
      displayName: 'JSON',
    ),
    LanguageDefinition(
      highlightLanguage: 'xml',
      extensions: ['xml', 'svg'],
      displayName: 'XML',
    ),
    LanguageDefinition(
      highlightLanguage: 'yaml',
      extensions: ['yaml', 'yml'],
      displayName: 'YAML',
    ),
    LanguageDefinition(
      highlightLanguage: 'bash',
      extensions: ['sh', 'bash'],
      displayName: 'Shell',
      runner: RunnerConfig(command: 'bash', type: RunnerType.terminal),
    ),
    LanguageDefinition(
      highlightLanguage: 'cpp',
      extensions: ['cpp', 'cc', 'cxx', 'c', 'h', 'hpp'],
      displayName: 'C/C++',
    ),
    LanguageDefinition(
      highlightLanguage: 'java',
      extensions: ['java'],
      displayName: 'Java',
    ),
    LanguageDefinition(
      highlightLanguage: 'kotlin',
      extensions: ['kt', 'kts'],
      displayName: 'Kotlin',
    ),
    LanguageDefinition(
      highlightLanguage: 'swift',
      extensions: ['swift'],
      displayName: 'Swift',
    ),
    LanguageDefinition(
      highlightLanguage: 'go',
      extensions: ['go'],
      displayName: 'Go',
    ),
    LanguageDefinition(
      highlightLanguage: 'rust',
      extensions: ['rs'],
      displayName: 'Rust',
    ),
    LanguageDefinition(
      highlightLanguage: 'sql',
      extensions: ['sql'],
      displayName: 'SQL',
    ),
    LanguageDefinition(
      highlightLanguage: 'markdown',
      extensions: ['md', 'markdown'],
      displayName: 'Markdown',
    ),
    LanguageDefinition(
      highlightLanguage: 'plaintext',
      extensions: ['txt', 'log', 'ini', 'cfg', 'conf'],
      displayName: 'Texte',
    ),
  ];

  /// Retrouve la définition pour une extension donnée.
  static LanguageDefinition? forExtension(String ext) {
    final lower = ext.toLowerCase();
    try {
      return _languages.firstWhere(
        (l) => l.extensions.contains(lower),
      );
    } catch (_) {
      return null;
    }
  }

  /// Retourne toutes les définitions.
  static List<LanguageDefinition> get all => _languages;
}

// ---------------------------------------------------------------------------
// Modèle d'onglet
// ---------------------------------------------------------------------------

/// @class EditorTab
/// @brief Représente un onglet de fichier ouvert dans l'éditeur.
class EditorTab {
  /// Chemin absolu du fichier.
  final String path;

  /// Nom affiché dans l'onglet.
  String get name => p.basename(path);

  /// Contenu courant (mutable).
  String content;

  /// Marqueur de modification non sauvegardée.
  bool isDirty;

  /// Langue détectée.
  LanguageDefinition? language;

  /// Contrôleur de texte associé.
  TextEditingController controller;

  EditorTab({
    required this.path,
    required this.content,
    this.isDirty = false,
    this.language,
  }) : controller = TextEditingController(text: content);

  void dispose() => controller.dispose();
}

// ---------------------------------------------------------------------------
// Provider de l'éditeur
// ---------------------------------------------------------------------------

/// @class TextEditorProvider
/// @brief Gère l'état de l'éditeur : onglets, projet, runner.
class TextEditorProvider extends ChangeNotifier {
  /// Liste des onglets ouverts.
  final List<EditorTab> tabs = [];

  /// Index de l'onglet actif.
  int _activeIndex = 0;
  int get activeIndex => _activeIndex;
  EditorTab? get activeTab => tabs.isEmpty ? null : tabs[_activeIndex];

  /// Répertoire projet ouvert.
  String? _projectPath;
  String? get projectPath => _projectPath;

  /// Arborescence du projet.
  List<_ProjectNode> _projectTree = [];
  // ignore: library_private_types_in_public_api
  List<_ProjectNode> get projectTree => _projectTree;

  /// Sortie du runner.
  String _runnerOutput = '';
  String get runnerOutput => _runnerOutput;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Panneau runner visible.
  bool _showRunner = false;
  bool get showRunner => _showRunner;

  /// Panneau projet visible.
  bool _showProject = false;
  bool get showProject => _showProject;

  /// Terminal SSH Debian VM visible.
  bool _showSshTerminal = false;
  bool get showSshTerminal => _showSshTerminal;

  /// Thème sombre actif.
  bool _isDark = true;
  bool get isDark => _isDark;
  void toggleTheme() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void toggleProject() {
    _showProject = !_showProject;
    notifyListeners();
  }

  void toggleRunner() {
    _showRunner = !_showRunner;
    notifyListeners();
  }

  void toggleSshTerminal() {
    _showSshTerminal = !_showSshTerminal;
    notifyListeners();
  }

  /// Ouvre un fichier dans un nouvel onglet (ou active l'existant).
  Future<void> openFile(String path) async {
    final existing = tabs.indexWhere((t) => t.path == path);
    if (existing != -1) {
      _activeIndex = existing;
      notifyListeners();
      return;
    }
    try {
      final content = await File(path).readAsString();
      final ext = p.extension(path).replaceFirst('.', '');
      final lang = LanguageRegistry.forExtension(ext);
      final tab = EditorTab(path: path, content: content, language: lang);
      tab.controller.addListener(() {
        if (tab.content != tab.controller.text) {
          tab.content = tab.controller.text;
          tab.isDirty = true;
          notifyListeners();
        }
      });
      tabs.add(tab);
      _activeIndex = tabs.length - 1;
      notifyListeners();
    } catch (e) {
      _runnerOutput = 'Erreur ouverture : $e';
      notifyListeners();
    }
  }

  /// Sauvegarde l'onglet actif.
  Future<void> saveActive() async {
    final tab = activeTab;
    if (tab == null) return;
    try {
      await File(tab.path).writeAsString(tab.controller.text);
      tab.isDirty = false;
      notifyListeners();
    } catch (e) {
      _runnerOutput = 'Erreur sauvegarde : $e';
      notifyListeners();
    }
  }

  /// Ferme un onglet.
  void closeTab(int index) {
    tabs[index].dispose();
    tabs.removeAt(index);
    if (_activeIndex >= tabs.length && _activeIndex > 0) {
      _activeIndex = tabs.length - 1;
    }
    notifyListeners();
  }

  /// Active un onglet.
  void setActiveTab(int index) {
    _activeIndex = index;
    notifyListeners();
  }

  /// Ouvre un répertoire comme projet.
  Future<void> openProject(String dirPath) async {
    _projectPath = dirPath;
    _showProject = true;
    _projectTree = await _buildTree(dirPath, 0);
    notifyListeners();
  }

  Future<List<_ProjectNode>> _buildTree(String dirPath, int depth) async {
    if (depth > 5) return [];
    final dir = Directory(dirPath);
    final nodes = <_ProjectNode>[];
    try {
      final entities = await dir.list().toList()
        ..sort((a, b) {
          final aDir = a is Directory ? 0 : 1;
          final bDir = b is Directory ? 0 : 1;
          if (aDir != bDir) return aDir - bDir;
          return p.basename(a.path).compareTo(p.basename(b.path));
        });
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          nodes.add(_ProjectNode(
            path: e.path,
            name: name,
            isDirectory: true,
            depth: depth,
          ));
        } else {
          nodes.add(_ProjectNode(
            path: e.path,
            name: name,
            isDirectory: false,
            depth: depth,
          ));
        }
      }
    } catch (_) {}
    return nodes;
  }

  /// Développe/réduit un nœud du projet.
  Future<void> toggleNode(int index) async {
    final node = _projectTree[index];
    if (!node.isDirectory) return;
    if (node.isExpanded) {
      // Réduire : supprimer les enfants
      node.isExpanded = false;
      _projectTree.removeWhere((n) =>
          n.depth > node.depth && _projectTree.indexOf(n) > index);
      // Rebuild proprement
      final newTree = <_ProjectNode>[];
      for (final n in _projectTree) {
        newTree.add(n);
      }
      _projectTree = newTree;
    } else {
      node.isExpanded = true;
      final children = await _buildTree(node.path, node.depth + 1);
      _projectTree.insertAll(index + 1, children);
    }
    notifyListeners();
  }

  /// Lance l'exécution du fichier actif.
  Future<void> runActive() async {
    final tab = activeTab;
    if (tab == null || tab.language?.runner == null) return;
    await saveActive();

    _showRunner = true;
    _isRunning = true;
    _runnerOutput = '▶ Exécution de ${tab.name}...\n';
    notifyListeners();

    final runner = tab.language!.runner!;

    if (runner.type == RunnerType.webServer) {
      _runnerOutput += '🌐 Serveur web non disponible sur Android.\n';
      _isRunning = false;
      notifyListeners();
      return;
    }

    try {
      final result = await Process.run(
        runner.command,
        [tab.path],
        workingDirectory: p.dirname(tab.path),
      ).timeout(const Duration(seconds: 30));
      _runnerOutput += result.stdout.toString();
      if (result.stderr.toString().isNotEmpty) {
        _runnerOutput += '\n⚠ Erreurs :\n${result.stderr}';
      }
      _runnerOutput += '\n✓ Terminé (code ${result.exitCode})';
    } catch (e) {
      _runnerOutput += '✗ Erreur : $e';
    }
    _isRunning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t.dispose();
    }
    super.dispose();
  }
}

/// @class _ProjectNode
/// @brief Nœud dans l'arborescence du projet.
class _ProjectNode {
  final String path;
  final String name;
  final bool isDirectory;
  final int depth;
  bool isExpanded = false;

  _ProjectNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.depth,
  });
}

// ---------------------------------------------------------------------------
// Écran principal
// ---------------------------------------------------------------------------

/// @class TextEditorScreen
/// @brief Écran de l'éditeur de texte/code.
class TextEditorScreen extends StatefulWidget {
  /// Chemin du fichier à ouvrir au démarrage (optionnel).
  final String? initialFilePath;

  /// Chemin du répertoire projet à ouvrir (optionnel).
  final String? initialProjectPath;

  const TextEditorScreen({
    super.key,
    this.initialFilePath,
    this.initialProjectPath,
  });

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late TextEditorProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = TextEditorProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.initialProjectPath != null) {
        await _provider.openProject(widget.initialProjectPath!);
      }
      if (widget.initialFilePath != null) {
        await _provider.openFile(widget.initialFilePath!);
      }
    });
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<TextEditorProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            backgroundColor: provider.isDark
                ? const Color(0xFF1E1E2E)
                : const Color(0xFFF5F5F5),
            appBar: _buildAppBar(context, provider),
            body: Row(
              children: [
                // Panneau projet
                if (provider.showProject)
                  _ProjectPanel(provider: provider),

                // Zone principale
                Expanded(
                  child: Column(
                    children: [
                      // Barre d'onglets
                      if (provider.tabs.isNotEmpty)
                        _TabBar(provider: provider),

                      // Éditeur
                      Expanded(
                        child: provider.tabs.isEmpty
                            ? _EmptyEditor(provider: provider)
                            : _EditorArea(provider: provider),
                      ),

                      // Panneau runner
                      if (provider.showRunner)
                        _RunnerPanel(provider: provider),

                      // Terminal SSH Debian VM
                      if (provider.showSshTerminal) Builder(
                        builder: (ctx) {
                          final s = ctx.read<SettingsService>();
                          return SshTerminalPanel(
                            key: const ValueKey('debian_terminal'),
                            host:       s.sshHost,
                            port:       s.sshPort,
                            username:   s.sshUsername,
                            password:   s.sshPassword,
                            initialDir: s.sshSharedPath,
                            onClose:    provider.toggleSshTerminal,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, TextEditorProvider provider) {
    return AppBar(
      backgroundColor:
          provider.isDark ? const Color(0xFF181825) : const Color(0xFFE0E0E0),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Retour',
      ),
      title: Text(
        provider.activeTab?.name ?? 'Éditeur',
        style: const TextStyle(fontSize: 14),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        // Ouvrir projet
        IconButton(
          icon: const Icon(Icons.folder_open_outlined),
          tooltip: 'Ouvrir répertoire projet',
          onPressed: () => _openProjectDialog(context, provider),
        ),
        // Panneau projet
        IconButton(
          icon: Icon(
            Icons.account_tree_outlined,
            color: provider.showProject
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          tooltip: 'Arborescence projet',
          onPressed: provider.toggleProject,
        ),
        // Sauvegarder
        IconButton(
          icon: const Icon(Icons.save_outlined),
          tooltip: 'Sauvegarder (Ctrl+S)',
          onPressed:
              provider.activeTab != null ? provider.saveActive : null,
        ),
        // Runner
        if (provider.activeTab?.language?.runner != null)
          IconButton(
            icon: provider.isRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded, color: Colors.green),
            tooltip: 'Exécuter',
            onPressed: provider.isRunning ? null : provider.runActive,
          ),
        // Terminal Debian VM
        IconButton(
          icon: Icon(
            Icons.terminal_rounded,
            color: provider.showSshTerminal
                ? const Color(0xFF89B4FA)
                : null,
          ),
          tooltip: 'Terminal Debian VM',
          onPressed: provider.toggleSshTerminal,
        ),
        // Thème
        IconButton(
          icon: Icon(
              provider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          tooltip: 'Basculer thème',
          onPressed: provider.toggleTheme,
        ),
      ],
    );
  }

  Future<void> _openProjectDialog(
      BuildContext context, TextEditorProvider provider) async {
    final path = await ExplorerPicker.pickDirectory(context,
        title: 'Répertoire du projet', initialPath: provider.projectPath);
    if (path != null) await provider.openProject(path);
  }
}

// ---------------------------------------------------------------------------
// Widgets internes
// ---------------------------------------------------------------------------

/// @class _TabBar
/// @brief Barre d'onglets des fichiers ouverts.
class _TabBar extends StatelessWidget {
  final TextEditorProvider provider;
  const _TabBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isDark = provider.isDark;
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: provider.tabs.length,
        itemBuilder: (ctx, i) {
          final tab = provider.tabs[i];
          final isActive = i == provider.activeIndex;
          return GestureDetector(
            onTap: () => provider.setActiveTab(i),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 200, minWidth: 80),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? (isDark
                        ? const Color(0xFF313244)
                        : const Color(0xFFFFFFFF))
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive
                        ? const Color(0xFF89B4FA)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.isDirty)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      tab.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive
                            ? (isDark ? Colors.white : Colors.black87)
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => provider.closeTab(i),
                    borderRadius: BorderRadius.circular(4),
                    child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// @class _EditorArea
/// @brief Zone principale d'édition avec numéros de ligne et coloration syntaxique.
class _EditorArea extends StatefulWidget {
  final TextEditorProvider provider;
  const _EditorArea({required this.provider});

  @override
  State<_EditorArea> createState() => _EditorAreaState();
}

class _EditorAreaState extends State<_EditorArea> {
  final ScrollController _scrollController = ScrollController();
  bool _highlightMode = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final tab = provider.activeTab;
    if (tab == null) return const SizedBox.shrink();

    final isDark = provider.isDark;
    final bgColor =
        isDark ? const Color(0xFF1E1E2E) : const Color(0xFFFFFFFF);
    final textColor = isDark ? Colors.white70 : Colors.black87;

    return Stack(
      children: [
        // Mode édition avec TextField
        if (!_highlightMode)
          _rawEditor(tab, bgColor, textColor, isDark)
        else
          _highlightedEditor(tab, isDark),

        // Bouton bascule highlight/raw
        Positioned(
          bottom: 8,
          right: 8,
          child: Tooltip(
            message: _highlightMode ? 'Mode édition' : 'Mode lecture',
            child: FloatingActionButton.small(
              heroTag: 'toggle_mode',
              backgroundColor: isDark
                  ? const Color(0xFF313244)
                  : const Color(0xFFE0E0E0),
              onPressed: () => setState(() => _highlightMode = !_highlightMode),
              child: Icon(
                _highlightMode ? Icons.edit_note : Icons.code,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Éditeur brut avec TextField.
  Widget _rawEditor(EditorTab tab, Color bgColor, Color textColor, bool isDark) {
    return Container(
      color: bgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numéros de ligne
          _LineNumbers(
            controller: tab.controller,
            isDark: isDark,
          ),
          // TextField
          Expanded(
            child: TextField(
              controller: tab.controller,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
                color: textColor,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: (_) {},
            ),
          ),
        ],
      ),
    );
  }

  /// Éditeur avec coloration syntaxique (lecture seule).
  Widget _highlightedEditor(EditorTab tab, bool isDark) {
    final lang = tab.language?.highlightLanguage ?? 'plaintext';
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    return SingleChildScrollView(
      controller: _scrollController,
      child: HighlightView(
        tab.content,
        language: lang,
        theme: theme,
        padding: const EdgeInsets.all(12),
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

/// @class _LineNumbers
/// @brief Affiche les numéros de ligne synchronisés avec le TextField.
class _LineNumbers extends StatefulWidget {
  final TextEditingController controller;
  final bool isDark;
  const _LineNumbers({required this.controller, required this.isDark});

  @override
  State<_LineNumbers> createState() => _LineNumbersState();
}

class _LineNumbersState extends State<_LineNumbers> {
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    _update();
  }

  void _update() {
    final lines = '\n'.allMatches(widget.controller.text).length + 1;
    if (lines != _lineCount) setState(() => _lineCount = lines);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isDark ? Colors.white24 : Colors.black26;
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: widget.isDark ? const Color(0xFF181825) : const Color(0xFFF0F0F0),
      child: Column(
        children: List.generate(
          _lineCount,
          (i) => SizedBox(
            height: 19.5,
            child: Text(
              '${i + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// @class _RunnerPanel
/// @brief Panneau de sortie du runner (terminal simulé).
class _RunnerPanel extends StatelessWidget {
  final TextEditorProvider provider;
  const _RunnerPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: const Color(0xFF11111B),
      child: Column(
        children: [
          // Barre titre
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0xFF1E1E2E),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                const Text(
                  'Terminal',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (provider.isRunning)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: provider.toggleRunner,
                  child: const Icon(Icons.close, size: 14, color: Colors.white38),
                ),
              ],
            ),
          ),
          // Sortie
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Text(
                provider.runnerOutput,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFCDD6F4),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// @class _ProjectPanel
/// @brief Arborescence du projet (panneau latéral gauche).
class _ProjectPanel extends StatelessWidget {
  final TextEditorProvider provider;
  const _ProjectPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isDark = provider.isDark;
    return Container(
      width: 220,
      color: isDark ? const Color(0xFF181825) : const Color(0xFFE8E8E8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 14, color: Color(0xFF89B4FA)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.basename(provider.projectPath ?? ''),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : Colors.black54,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Arborescence
          Expanded(
            child: ListView.builder(
              itemCount: provider.projectTree.length,
              itemBuilder: (ctx, i) {
                final node = provider.projectTree[i];
                return InkWell(
                  onTap: () async {
                    if (node.isDirectory) {
                      await provider.toggleNode(i);
                    } else {
                      await provider.openFile(node.path);
                    }
                  },
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 12.0 + node.depth * 14,
                      top: 4,
                      bottom: 4,
                      right: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          node.isDirectory
                              ? (node.isExpanded
                                  ? Icons.folder_open
                                  : Icons.folder)
                              : _fileIcon(node.name),
                          size: 14,
                          color: node.isDirectory
                              ? const Color(0xFF89B4FA)
                              : const Color(0xFFA6E3A1),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            node.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    switch (ext) {
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'java':
      case 'kt':
        return Icons.code;
      case 'json':
      case 'yaml':
      case 'yml':
        return Icons.data_object;
      case 'html':
      case 'css':
        return Icons.language;
      case 'md':
        return Icons.article_outlined;
      case 'png':
      case 'jpg':
      case 'gif':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

/// @class _EmptyEditor
/// @brief Écran vide affiché quand aucun fichier n'est ouvert.
class _EmptyEditor extends StatelessWidget {
  final TextEditorProvider provider;
  const _EmptyEditor({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isDark = provider.isDark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.code,
            size: 64,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun fichier ouvert',
            style: TextStyle(
              color: isDark ? Colors.white24 : Colors.black26,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ouvrez un répertoire projet ou un fichier depuis l\'explorateur',
            style: TextStyle(
              color: isDark ? Colors.white12 : Colors.black12,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
