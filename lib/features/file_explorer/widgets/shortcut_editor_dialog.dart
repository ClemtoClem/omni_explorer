/// @file shortcut_editor_dialog.dart
/// @brief Catalogue d'icônes / couleurs des raccourcis de répertoire et
/// dialogue de création / modification d'un raccourci.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/file_filter.dart';
import '../../../core/models/file_item.dart';
import '../explorer_picker.dart';

// ── Catalogue ────────────────────────────────────────────────────────────────

/// Icônes proposées pour un raccourci. La clé est enregistrée dans
/// [ShortcutItem.iconName] : ne pas renommer une clé existante.
const Map<String, IconData> kShortcutIcons = {
  'folder': Icons.folder_rounded,
  'folder_special': Icons.folder_special_rounded,
  'bookmark': Icons.bookmark_rounded,
  'star': Icons.star_rounded,
  'favorite': Icons.favorite_rounded,
  'home': Icons.home_rounded,
  'image': Icons.image_rounded,
  'camera': Icons.photo_camera_rounded,
  'video': Icons.videocam_rounded,
  'movie': Icons.movie_rounded,
  'music': Icons.music_note_rounded,
  'mic': Icons.mic_rounded,
  'document': Icons.description_rounded,
  'book': Icons.menu_book_rounded,
  'pdf': Icons.picture_as_pdf_rounded,
  'download': Icons.download_rounded,
  'archive': Icons.inventory_2_rounded,
  'code': Icons.code_rounded,
  'terminal': Icons.terminal_rounded,
  'apps': Icons.apps_rounded,
  'games': Icons.sports_esports_rounded,
  'work': Icons.work_rounded,
  'school': Icons.school_rounded,
  'cloud': Icons.cloud_rounded,
  'backup': Icons.backup_rounded,
  'sd_card': Icons.sd_card_rounded,
  'usb': Icons.usb_rounded,
  'storage': Icons.storage_rounded,
  'lock': Icons.lock_rounded,
  'share': Icons.share_rounded,
  'chat': Icons.chat_rounded,
  'travel': Icons.flight_rounded,
};

/// Couleurs proposées pour la tuile d'un raccourci.
const List<Color> kShortcutColors = [
  AppColors.colorFolder,
  AppColors.colorArchive,
  AppColors.colorPdf,
  AppColors.colorVideo,
  AppColors.colorAudio,
  AppColors.colorDoc,
  AppColors.info,
  AppColors.colorImage,
  AppColors.colorCode,
  AppColors.colorText,
];

const String _defaultIcon = 'folder';

IconData shortcutIconOf(ShortcutItem s) =>
    kShortcutIcons[s.iconName] ?? kShortcutIcons[_defaultIcon]!;

Color shortcutColorOf(ShortcutItem s) =>
    s.colorValue != null ? Color(s.colorValue!) : AppColors.colorFolder;

// ── Dialogue ─────────────────────────────────────────────────────────────────

/// Valeurs saisies dans [showShortcutEditor].
typedef ShortcutDraft = ({
  String name,
  String path,
  String iconName,
  int colorValue,
  FileFilter filter,
});

/// Ouvre l'éditeur de raccourci : création si [initial] est `null`,
/// modification sinon. Le répertoire se choisit dans l'explorateur de
/// l'application. Renvoie `null` si l'utilisateur annule.
Future<ShortcutDraft?> showShortcutEditor(
  BuildContext context, {
  ShortcutItem? initial,
  String? initialPath,
}) {
  return showDialog<ShortcutDraft>(
    context: context,
    builder: (_) => _ShortcutEditor(initial: initial, initialPath: initialPath),
  );
}

class _ShortcutEditor extends StatefulWidget {
  final ShortcutItem? initial;
  final String? initialPath;
  const _ShortcutEditor({this.initial, this.initialPath});

  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late String? _path = widget.initial?.path;
  late String _icon = kShortcutIcons.containsKey(widget.initial?.iconName)
      ? widget.initial!.iconName!
      : _defaultIcon;
  late Color _color = widget.initial != null
      ? shortcutColorOf(widget.initial!)
      : kShortcutColors.first;
  String? _nameError;
  String? _pathError;

  // ── Filtres de recherche appliqués à l'ouverture ──────────────────────────
  late final FileFilter _initialFilter =
      widget.initial?.filter ?? FileFilter.none;
  late final TextEditingController _query =
      TextEditingController(text: _initialFilter.query);
  late final TextEditingController _extensions = TextEditingController(
      text: _initialFilter.extensions.map((e) => '.$e').join(' '));
  late final Set<FileCategory> _categories = {..._initialFilter.categories};
  late bool _recursive = _initialFilter.recursive;
  late SortMode? _sortMode = _initialFilter.sortMode;
  late bool _sortAsc = _initialFilter.sortAscending;

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    _extensions.dispose();
    super.dispose();
  }

  FileFilter get _filter => FileFilter(
        query: _query.text.trim(),
        categories: {..._categories},
        extensions: FileFilter.parseExtensions(_extensions.text),
        recursive: _recursive,
        sortMode: _sortMode,
        sortAscending: _sortAsc,
      );

  Future<void> _choosePath() async {
    final path = await ExplorerPicker.pickDirectory(
      context,
      title: 'Répertoire du raccourci',
      initialPath: _path ?? widget.initialPath,
    );
    if (path == null || !mounted) return;
    setState(() {
      _path = path;
      _pathError = null;
      // Nom par défaut : celui du dossier, tant que l'utilisateur n'a rien saisi.
      if (_name.text.trim().isEmpty) _name.text = p.basename(path);
    });
  }

  void _submit() {
    final name = _name.text.trim();
    final path = _path;
    setState(() {
      _nameError = name.isEmpty ? 'Donnez un nom au raccourci' : null;
      _pathError = path == null
          ? 'Choisissez un répertoire'
          : !Directory(path).existsSync()
              ? 'Ce répertoire n\'existe plus'
              : null;
    });
    if (_nameError != null || _pathError != null) return;
    Navigator.pop<ShortcutDraft>(context, (
      name: name,
      path: path!,
      iconName: _icon,
      colorValue: _color.toARGB32(),
      filter: _filter,
    ));
  }

  /// Filtres appliqués quand le raccourci ouvre l'explorateur : retrouver
  /// directement les fichiers voulus (ex. les PDF de Téléchargements, du
  /// plus récent au plus ancien, sous-dossiers compris).
  Widget _filterSection(ThemeData theme) {
    return Theme(
      // Pas de séparateurs autour de la section repliable.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('shortcut-filters'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: !_initialFilter.isEmpty,
        title: Text('Filtres de recherche', style: theme.textTheme.labelLarge),
        subtitle: Text(
          _filter.isEmpty
              ? 'Aucun : tout le contenu du répertoire'
              : _filter.describe(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('filter-query'),
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Nom contient',
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Text('Types de fichiers', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in FileFilter.categoryLabels.entries)
                FilterChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 12)),
                  selected: _categories.contains(e.key),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => setState(() =>
                      on ? _categories.add(e.key) : _categories.remove(e.key)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('filter-extensions'),
            controller: _extensions,
            decoration: const InputDecoration(
              labelText: 'Extensions',
              hintText: 'ex. pdf docx odt',
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            key: const ValueKey('filter-recursive'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Chercher aussi dans les sous-dossiers'),
            value: _recursive,
            onChanged: (v) => setState(() => _recursive = v),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SortMode?>(
                  key: const ValueKey('filter-sort'),
                  initialValue: _sortMode,
                  isDense: true,
                  decoration:
                      const InputDecoration(labelText: 'Tri', isDense: true),
                  items: [
                    const DropdownMenuItem(
                        value: null,
                        child: Text('Préférence de l\'explorateur')),
                    for (final e in FileFilter.sortLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (m) => setState(() => _sortMode = m),
                ),
              ),
              if (_sortMode != null)
                IconButton(
                  tooltip: _sortAsc ? 'Croissant' : 'Décroissant',
                  icon: Icon(_sortAsc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded),
                  onPressed: () => setState(() => _sortAsc = !_sortAsc),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.initial == null
          ? 'Nouveau raccourci'
          : 'Modifier le raccourci'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _Preview(icon: _icon, color: _color, name: _name)),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nom',
                  errorText: _nameError,
                ),
                onChanged: (_) => setState(() => _nameError = null),
              ),
              const SizedBox(height: 12),
              Text('Répertoire', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                key: const ValueKey('shortcut-path'),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _path ?? 'Choisir dans l\'explorateur…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: _choosePath,
              ),
              if (_pathError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 12),
                  child: Text(_pathError!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 16),
              Text('Icône', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in kShortcutIcons.entries)
                    _Choice(
                      selected: e.key == _icon,
                      color: _color,
                      onTap: () => setState(() => _icon = e.key),
                      child: Icon(e.value,
                          size: 20, color: e.key == _icon ? _color : null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Couleur', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kShortcutColors)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.toARGB32() == _color.toARGB32()
                                ? theme.colorScheme.onSurface
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _filterSection(theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  const _Choice({
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Aperçu de la tuile telle qu'elle apparaîtra sur la page Stockage.
class _Preview extends StatelessWidget {
  final String icon;
  final Color color;
  final TextEditingController name;

  const _Preview({required this.icon, required this.color, required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(kShortcutIcons[icon], color: color, size: 26),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: name,
          builder: (context, v, _) => Text(
            v.text.trim().isEmpty ? 'Raccourci' : v.text.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
