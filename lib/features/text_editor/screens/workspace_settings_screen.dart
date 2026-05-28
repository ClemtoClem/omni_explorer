/// @file workspace_settings_screen.dart
/// @brief Écran de paramètres du workspace, inspiré de VS Code Settings.
///
/// Organise les paramètres en catégories (Éditeur, Fichiers, Affichage,
/// Langages, JSON brut) avec un champ de recherche en haut.
/// Les modifications sont enregistrées via le callback [onSave] et
/// persistées dans le fichier .workspace.json à la racine du projet.

library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/workspace_settings.dart';

// ─── Entrée point ─────────────────────────────────────────────────────────────

class WorkspaceSettingsScreen extends StatefulWidget {
  final String projectPath;
  final WorkspaceSettings settings;
  final Future<void> Function(WorkspaceSettings) onSave;

  const WorkspaceSettingsScreen({
    super.key,
    required this.projectPath,
    required this.settings,
    required this.onSave,
  });

  @override
  State<WorkspaceSettingsScreen> createState() =>
      _WorkspaceSettingsScreenState();
}

class _WorkspaceSettingsScreenState extends State<WorkspaceSettingsScreen>
    with SingleTickerProviderStateMixin {

  late WorkspaceSettings _settings;
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _saving = false;
  bool _dirty = false;

  // Pour le mode JSON brut
  late TextEditingController _jsonCtrl;
  String? _jsonError;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _tabCtrl = TabController(length: 5, vsync: this);
    _jsonCtrl = TextEditingController(text: _settings.toJsonString());
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 4) {
        // Passer en mode JSON brut : synchroniser
        _jsonCtrl.text = _settings.toJsonString();
        _jsonError = null;
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _update(WorkspaceSettings s) {
    setState(() {
      _settings = s;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_tabCtrl.index == 4) {
      // Valider et appliquer le JSON brut
      try {
        final json = jsonDecode(_jsonCtrl.text) as Map<String, dynamic>;
        _settings = WorkspaceSettings.fromJson(json);
        setState(() => _jsonError = null);
      } catch (e) {
        setState(() => _jsonError = 'JSON invalide : $e');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(_settings);
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres du workspace sauvegardés'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paramètres du Workspace', style: TextStyle(fontSize: 14)),
            Text(
              p.basename(widget.projectPath),
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Éditeur'),
            Tab(text: 'Fichiers'),
            Tab(text: 'Affichage'),
            Tab(text: 'Langages'),
            Tab(text: 'JSON'),
          ],
        ),
        actions: [
          if (_dirty)
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded, size: 16),
              label: const Text('Sauvegarder'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche globale
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher un paramètre…',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                isDense: true,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildEditorTab(theme),
                _buildFilesTab(theme),
                _buildDisplayTab(theme),
                _buildLanguagesTab(theme),
                _buildJsonTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab Éditeur ───────────────────────────────────────────────────────────

  Widget _buildEditorTab(ThemeData theme) {
    final items = <_SettingItem>[
      _SettingItem(
        key: 'fontSize',
        label: 'Taille de la police',
        description: 'Taille en pixels de la police dans l\'éditeur.',
        widget: _buildSliderInt(
          value: _settings.fontSize,
          min: 8,
          max: 32,
          onChanged: (v) => _update(_settings.copyWith(fontSize: v)),
          display: '${_settings.fontSize} px',
        ),
      ),
      _SettingItem(
        key: 'fontFamily',
        label: 'Police',
        description: 'Famille de polices utilisée dans l\'éditeur.',
        widget: _FontFamilyPicker(
          value: _settings.fontFamily,
          onChanged: (v) => _update(_settings.copyWith(fontFamily: v)),
        ),
      ),
      _SettingItem(
        key: 'wordWrap',
        label: 'Retour à la ligne automatique',
        description:
            'Retour à la ligne quand le texte dépasse la largeur de l\'éditeur.',
        widget: Switch(
          value: _settings.wordWrap,
          onChanged: (v) => _update(_settings.copyWith(wordWrap: v)),
        ),
      ),
      _SettingItem(
        key: 'showLineNumbers',
        label: 'Numéros de ligne',
        description: 'Affiche les numéros de ligne dans l\'éditeur de code.',
        widget: Switch(
          value: _settings.showLineNumbers,
          onChanged: (v) => _update(_settings.copyWith(showLineNumbers: v)),
        ),
      ),
      _SettingItem(
        key: 'tabSize',
        label: 'Taille de tabulation',
        description: 'Nombre d\'espaces par niveau d\'indentation.',
        widget: _buildDropdown<int>(
          value: _settings.tabSize,
          items: const [2, 4, 8],
          label: (v) => v.toString(),
          onChanged: (v) => _update(_settings.copyWith(tabSize: v)),
        ),
      ),
      _SettingItem(
        key: 'insertSpaces',
        label: 'Insérer des espaces',
        description:
            'Utilise des espaces plutôt que des tabulations pour l\'indentation.',
        widget: Switch(
          value: _settings.insertSpaces,
          onChanged: (v) => _update(_settings.copyWith(insertSpaces: v)),
        ),
      ),
      _SettingItem(
        key: 'formatOnSave',
        label: 'Formater à la sauvegarde',
        description: 'Formate automatiquement le code à chaque sauvegarde.',
        widget: Switch(
          value: _settings.formatOnSave,
          onChanged: (v) => _update(_settings.copyWith(formatOnSave: v)),
        ),
      ),
      _SettingItem(
        key: 'autoSave',
        label: 'Sauvegarde automatique',
        description: 'Enregistre les fichiers automatiquement lors des modifications.',
        widget: Switch(
          value: _settings.autoSave,
          onChanged: (v) => _update(_settings.copyWith(autoSave: v)),
        ),
      ),
    ];
    return _buildSettingsList(items);
  }

  // ── Tab Fichiers ──────────────────────────────────────────────────────────

  Widget _buildFilesTab(ThemeData theme) {
    return _ExcludePatternsEditor(
      patterns: _settings.excludePatterns,
      searchQuery: _searchQuery,
      onChanged: (patterns) =>
          _update(_settings.copyWith(excludePatterns: patterns)),
    );
  }

  // ── Tab Affichage ─────────────────────────────────────────────────────────

  Widget _buildDisplayTab(ThemeData theme) {
    final items = <_SettingItem>[
      _SettingItem(
        key: 'themeMode',
        label: 'Thème de l\'éditeur',
        description:
            'Thème visuel pour ce workspace. « system » utilise le thème global de l\'application.',
        widget: _buildDropdown<String>(
          value: _settings.themeMode,
          items: const ['system', 'dark', 'light'],
          label: (v) => switch (v) {
            'dark' => 'Sombre',
            'light' => 'Clair',
            _ => 'Système (global)',
          },
          onChanged: (v) => _update(_settings.copyWith(themeMode: v)),
        ),
      ),
      _SettingItem(
        key: 'useCustomKeyboard',
        label: 'Clavier personnalisé (Android)',
        description:
            'Utilise le clavier AZERTY personnalisé sur Android. Remplace le paramètre global.',
        widget: _buildDropdown<String>(
          value: _settings.useCustomKeyboard == null
              ? 'global'
              : (_settings.useCustomKeyboard! ? 'yes' : 'no'),
          items: const ['global', 'yes', 'no'],
          label: (v) => switch (v) {
            'yes' => 'Activé',
            'no' => 'Désactivé',
            _ => 'Hériter du paramètre global',
          },
          onChanged: (v) => _update(_settings.copyWith(
            useCustomKeyboard: v == 'global' ? null : v == 'yes',
          )),
        ),
      ),
    ];
    return _buildSettingsList(items);
  }

  // ── Tab Langages ──────────────────────────────────────────────────────────

  Widget _buildLanguagesTab(ThemeData theme) {
    return _LanguageAssociationsEditor(
      associations: _settings.languageAssociations,
      searchQuery: _searchQuery,
      onChanged: (assoc) =>
          _update(_settings.copyWith(languageAssociations: assoc)),
    );
  }

  // ── Tab JSON brut ─────────────────────────────────────────────────────────

  Widget _buildJsonTab(ThemeData theme) {
    return Column(
      children: [
        if (_jsonError != null)
          Container(
            width: double.infinity,
            color: Colors.red.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 16, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_jsonError!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 12))),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Édition directe du fichier .workspace.json',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  try {
                    final json =
                        jsonDecode(_jsonCtrl.text) as Map<String, dynamic>;
                    _settings = WorkspaceSettings.fromJson(json);
                    setState(() {
                      _jsonError = null;
                      _dirty = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('JSON validé et appliqué'),
                          duration: Duration(seconds: 1)),
                    );
                  } catch (e) {
                    setState(() => _jsonError = 'JSON invalide : $e');
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 14),
                label: const Text('Valider', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TextField(
            controller: _jsonCtrl,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(12),
            ),
            onChanged: (_) => setState(() {
              _dirty = true;
              _jsonError = null;
            }),
          ),
        ),
      ],
    );
  }

  // ── Helpers de construction ───────────────────────────────────────────────

  Widget _buildSettingsList(List<_SettingItem> items) {
    final filtered = _searchQuery.isEmpty
        ? items
        : items
            .where((i) =>
                i.label.toLowerCase().contains(_searchQuery) ||
                i.description.toLowerCase().contains(_searchQuery))
            .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'Aucun paramètre trouvé pour « $_searchQuery »',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (_, i) => _buildSettingRow(filtered[i]),
    );
  }

  Widget _buildSettingRow(_SettingItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13)),
                const SizedBox(height: 2),
                Text(item.description,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          item.widget,
        ],
      ),
    );
  }

  Widget _buildSliderInt({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    required String display,
  }) {
    return SizedBox(
      width: 160,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          Text(display,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: items
          .map((v) => DropdownMenuItem(value: v, child: Text(label(v))))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ─── Widgets internes ─────────────────────────────────────────────────────────

class _SettingItem {
  final String key;
  final String label;
  final String description;
  final Widget widget;
  const _SettingItem({
    required this.key,
    required this.label,
    required this.description,
    required this.widget,
  });
}

class _FontFamilyPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  static const _fonts = [
    'JetBrainsMono',
    'monospace',
    'Roboto Mono',
    'Source Code Pro',
    'Fira Code',
    'Courier New',
  ];

  const _FontFamilyPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final current = _fonts.contains(value) ? value : _fonts[0];
    return DropdownButton<String>(
      value: current,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: _fonts
          .map((f) => DropdownMenuItem(
              value: f,
              child: Text(f, style: TextStyle(fontFamily: f, fontSize: 13))))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _ExcludePatternsEditor extends StatefulWidget {
  final List<String> patterns;
  final String searchQuery;
  final ValueChanged<List<String>> onChanged;

  const _ExcludePatternsEditor({
    required this.patterns,
    required this.searchQuery,
    required this.onChanged,
  });

  @override
  State<_ExcludePatternsEditor> createState() => _ExcludePatternsEditorState();
}

class _ExcludePatternsEditorState extends State<_ExcludePatternsEditor> {
  final _addCtrl = TextEditingController();
  late List<String> _patterns;

  @override
  void initState() {
    super.initState();
    _patterns = List<String>.from(widget.patterns);
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final v = _addCtrl.text.trim();
    if (v.isEmpty || _patterns.contains(v)) return;
    setState(() => _patterns.add(v));
    _addCtrl.clear();
    widget.onChanged(_patterns);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.searchQuery.isEmpty
        ? _patterns
        : _patterns
            .where((p) => p.toLowerCase().contains(widget.searchQuery))
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Patterns d\'exclusion',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              const Text(
                'Fichiers et dossiers à masquer dans l\'arborescence du projet.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Ajouter un pattern (ex: *.tmp)',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _add,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10)),
                    child: const Text('Ajouter'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Aucun pattern'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final pattern = filtered[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.block_rounded,
                          size: 16, color: Colors.orange),
                      title: Text(pattern,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 16),
                        onPressed: () {
                          setState(() => _patterns.remove(pattern));
                          widget.onChanged(_patterns);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LanguageAssociationsEditor extends StatefulWidget {
  final Map<String, String> associations;
  final String searchQuery;
  final ValueChanged<Map<String, String>> onChanged;

  const _LanguageAssociationsEditor({
    required this.associations,
    required this.searchQuery,
    required this.onChanged,
  });

  @override
  State<_LanguageAssociationsEditor> createState() =>
      _LanguageAssociationsEditorState();
}

class _LanguageAssociationsEditorState
    extends State<_LanguageAssociationsEditor> {
  final _extCtrl = TextEditingController();
  final _langCtrl = TextEditingController();
  late Map<String, String> _assoc;

  @override
  void initState() {
    super.initState();
    _assoc = Map<String, String>.from(widget.associations);
  }

  @override
  void dispose() {
    _extCtrl.dispose();
    _langCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final ext = _extCtrl.text.trim().replaceAll('.', '').toLowerCase();
    final lang = _langCtrl.text.trim().toLowerCase();
    if (ext.isEmpty || lang.isEmpty) return;
    setState(() => _assoc[ext] = lang);
    _extCtrl.clear();
    _langCtrl.clear();
    widget.onChanged(_assoc);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _assoc.entries
        .where((e) =>
            widget.searchQuery.isEmpty ||
            e.key.contains(widget.searchQuery) ||
            e.value.contains(widget.searchQuery))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Associations de langages',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              const Text(
                'Associe une extension de fichier à un langage spécifique. '
                'Ex : twig → html, vue → javascript',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _extCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Extension (ex: twig)',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('→', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _langCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Langage (ex: html)',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _add,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10)),
                    child: const Text('Ajouter'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    widget.searchQuery.isNotEmpty
                        ? 'Aucune association trouvée'
                        : 'Aucune association définie\n'
                            'Les extensions non reconnues utiliseront\n'
                            'la détection automatique.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 48,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('.${e.key}',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      title: Text('→  ${e.value}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 16),
                        onPressed: () {
                          setState(() => _assoc.remove(e.key));
                          widget.onChanged(_assoc);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
