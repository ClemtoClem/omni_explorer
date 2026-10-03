/// @file file_explorer_screen.dart
/// @brief Écran principal de l'explorateur de fichiers.
///
/// Affiche le contenu d'un répertoire avec navigation interactive,
/// barre de chemin éditable, filtres, tri, et sélection multiple.
/// L'ouverture des fichiers est déléguée à [FileOpener].

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:omni_explorer/core/services/permissions_service.dart';
import 'package:omni_explorer/core/utils/system_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../../core/utils/responsive.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/file_filter.dart';
import '../../../core/models/file_item.dart';
import '../../../core/services/app_state_service.dart';
import '../../../core/services/file_operations_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../core/utils/file_opener.dart';
import '../../archive/screens/archive_screen.dart';
import '../explorer_picker.dart';
import '../providers/file_explorer_provider.dart';
import '../widgets/file_list_item.dart';
import '../widgets/file_grid_item.dart';
import '../widgets/path_bar.dart';
import '../../../core/widgets/file_op_dialogs.dart';
import '../widgets/filter_bar.dart';

/// @class FileExplorerScreen
/// @brief Écran principal de l'explorateur de fichiers.
class FileExplorerScreen extends StatefulWidget {
  /// Catégories pré-appliquées au filtre (utilisé par le launcher pour ouvrir
  /// « Images » avec {folder, image}, « Lecteur multimédia » avec
  /// {folder, audio, video}, « PDF » avec {folder, pdf}). Vide = pas de
  /// filtre, tout est affiché.
  final Set<FileCategory> initialCategories;

  /// Chemin à ouvrir directement au démarrage (prioritaire sur la
  /// restauration de la dernière session).
  final String? initialPath;

  /// Mode sélecteur : l'explorateur sert à choisir des fichiers, un dossier
  /// ou un emplacement d'enregistrement, et renvoie la liste des chemins
  /// choisis via `Navigator.pop`. Ouvert par [ExplorerPicker].
  final ExplorerPickRequest? pick;

  /// Filtre appliqué à l'ouverture (raccourci de la page Stockage) :
  /// nom, catégories, extensions, sous-dossiers, tri.
  final FileFilter? initialFilter;

  const FileExplorerScreen({
    super.key,
    this.initialCategories = const {},
    this.initialPath,
    this.pick,
    this.initialFilter,
  });

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen>
    with WidgetsBindingObserver {
  late FileExplorerProvider _provider;
  late AppStateService _appState;
  bool _showFilter = false;

  /// Nom du fichier à écrire (mode sélecteur « enregistrer »).
  late final TextEditingController _saveName =
      TextEditingController(text: widget.pick?.fileName ?? '');
  String? _saveError;

  /// Collage en cours : bouton du pied de page désactivé.
  bool _pasting = false;

  ExplorerPickRequest? get _pick => widget.pick;

  @override
  void initState() {
    super.initState();
    SystemUI.hideBottomBar();
    WidgetsBinding.instance.addObserver(this);
    _provider = FileExplorerProvider(context.read<SettingsService>());
    _appState = context.read<AppStateService>();
    final pick = _pick;
    if (pick != null) {
      _provider.setFileFilter(pick.accepts);
    } else {
      // Un sélecteur ne déplace pas la dernière position de l'explorateur.
      _provider.addListener(_persistPath);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _provider.init();
      } catch (e) {
        debugPrint('[FileExplorer] init failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Erreur d'initialisation : $e"),
              backgroundColor: AppColors.error));
        }
        return;
      }
      if (!mounted) return;

      // Priorité 1 : chemin demandé (raccourci de StorageScreen).
      // Priorité 2 : dernier chemin visité.
      final target = widget.initialPath ?? _appState.lastExplorerPath;
      try {
        if (target != null &&
            target.isNotEmpty &&
            target != _provider.currentPath &&
            Directory(target).existsSync()) {
          await _provider.navigateTo(target, addToHistory: false);
        }
      } catch (e) {
        debugPrint('[FileExplorer] restore path failed: $e');
      }

      if (!mounted) return;
      final filter = widget.initialFilter;
      if (filter != null && !filter.isEmpty) {
        _provider.applyFilter(filter);
        // Le tri seul ne demande pas d'afficher la barre de filtres.
        if (!filter.selectsNothing || filter.recursive) {
          setState(() => _showFilter = true);
        }
      } else if (widget.initialCategories.isNotEmpty) {
        _provider.setFilterCategories(widget.initialCategories);
        setState(() => _showFilter = true);
      }
    });
  }

  void _persistPath() {
    final p = _provider.currentPath;
    if (p.isNotEmpty) _appState.setLastExplorerPath(p);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _provider.removeListener(_persistPath);
    _provider.dispose();
    _saveName.dispose();
    super.dispose();
  }

  /// Détecte le retour depuis les Paramètres système après avoir accordé
  /// MANAGE_EXTERNAL_STORAGE et ré-initialise l'explorateur si nécessaire.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _provider.recheckAndInit();
    }
  }

  // ── Construction ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<FileExplorerProvider>(
        builder: (context, prov, _) => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: _buildAppBar(context, prov),
          body: Column(
            children: [
              PathBar(
                currentPath: prov.currentPath,
                rootPath: prov.rootPath,
                onNavigate: prov.navigateTo,
                onSegmentTap: prov.navigateToSegment,
                onUp: prov.isAtRoot ? null : prov.navigateUp,
                onUndo: prov.canUndo ? prov.undo : null,
                onRedo: prov.canRedo ? prov.redo : null,
              ),
              if (!kIsWeb &&
                  Platform.isAndroid &&
                  prov.needsFullStoragePermission)
                _buildPermissionBanner(),
              if (_showFilter)
                FilterBar(
                  query: prov.filterQuery,
                  selectedCategories: prov.filterCategories,
                  extensions: prov.filterExtensions,
                  recursive: prov.recursiveSearch,
                  searching: prov.searching,
                  truncated: prov.searchTruncated,
                  resultCount: prov.entries.length,
                  onQueryChanged: prov.setFilterQuery,
                  onCategoryToggled: prov.toggleFilterCategory,
                  onExtensionsChanged: prov.setFilterExtensions,
                  onRecursiveChanged: prov.setRecursiveSearch,
                  onClear: prov.clearFilter,
                ),
              const Divider(height: 1),
              Expanded(child: _buildBody(context, prov)),
            ],
          ),
          bottomNavigationBar: _pick != null
              ? _buildPickBar(context, prov, _pick!)
              : prov.selectMode
                  ? _buildSelectionBar(context, prov)
                  : prov.hasClipboard
                      ? _buildPasteBar(context, prov)
                      : null,
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(BuildContext context, FileExplorerProvider prov) {
    final settings = context.watch<SettingsService>();

    return AppBar(
      toolbarHeight: 100, // augmente la hauteur
      leading: IconButton(
        icon: Icon(
            _pick != null ? Icons.close_rounded : Icons.arrow_back_rounded),
        tooltip: _pick != null ? 'Annuler' : 'Retour',
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            prov.selectMode
                ? '${prov.selected.length} sélectionné(s)'
                : _pick?.title ?? 'Explorateur',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_showFilter
                      ? Icons.filter_list_off
                      : Icons.filter_list_rounded),
                  tooltip: 'Filtrer',
                  onPressed: () => setState(() => _showFilter = !_showFilter),
                ),
                IconButton(
                  icon: Icon(settings.viewMode == ViewMode.list
                      ? Icons.grid_view_rounded
                      : Icons.view_list_rounded),
                  tooltip: settings.viewMode == ViewMode.list
                      ? 'Vue grille'
                      : 'Vue liste',
                  onPressed: () => settings.setViewMode(
                    settings.viewMode == ViewMode.list
                        ? ViewMode.grid
                        : ViewMode.list,
                  ),
                ),
                _buildSortMenu(context, settings, prov),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: prov.refresh,
                  tooltip: 'Actualiser',
                ),
                IconButton(
                  icon: Icon(settings.showHidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  tooltip: settings.showHidden
                      ? 'Masquer les fichiers cachés'
                      : 'Afficher les fichiers cachés',
                  onPressed: () => settings.setShowHidden(!settings.showHidden),
                ),
                if (!prov.selectMode)
                  IconButton(
                      icon: const Icon(Icons.add_rounded),
                      tooltip: "Nouveau",
                      onPressed: () => _showNewItemDialog(context, prov)),
              ],
            ),
          ),
        ],
      ),
      actions: const [],
    );
  }

  Widget _buildSortMenu(BuildContext context, SettingsService settings,
      FileExplorerProvider prov) {
    const labels = FileFilter.sortLabels;
    // Tri imposé par un raccourci : affiché, puis remplacé par le choix de
    // l'utilisateur (qui devient la préférence).
    final current = prov.effectiveSortMode;
    final asc = prov.effectiveSortAsc;
    return PopupMenuButton<SortMode>(
      icon: const Icon(Icons.sort_rounded),
      tooltip: 'Trier par',
      onSelected: (mode) {
        prov.clearSortOverride();
        if (current == mode) {
          settings.setSortMode(mode);
          settings.setSortAsc(!asc);
        } else {
          settings.setSortMode(mode);
        }
      },
      itemBuilder: (_) => SortMode.values.map((m) {
        return PopupMenuItem<SortMode>(
          value: m,
          child: Row(
            children: [
              Icon(
                current == m
                    ? (asc ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.sort,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(labels[m]!),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Contenu principal ──────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, FileExplorerProvider prov) {
    if (prov.loading) return const Center(child: CircularProgressIndicator());
    if (prov.error != null) return _buildError(prov.error!);
    if (prov.entries.isEmpty) return _buildEmpty(prov);

    final settings = context.watch<SettingsService>();
    return settings.viewMode == ViewMode.grid
        ? _buildGrid(context, prov)
        : _buildList(context, prov);
  }

  Widget _buildList(BuildContext context, FileExplorerProvider prov) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: prov.entries.length,
      itemBuilder: (_, i) {
        final item = prov.entries[i];
        return FileListItem(
          item: item,
          isSelected: prov.selected.contains(item.path),
          selectMode: prov.selectMode,
          onTap: () => _onItemTap(context, item, prov),
          onLongPress: () => _onItemLongPress(item, prov),
          onSelect: () => prov.toggleSelect(item.path),
          showActions: _pick == null,
          // Résultat d'une recherche dans les sous-dossiers : où il se trouve.
          location: prov.showsSearchResults
              ? p.relative(p.dirname(item.path), from: prov.currentPath)
              : null,
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, FileExplorerProvider prov) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumnsFor(constraints.maxWidth),
          childAspectRatio: 0.85,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: prov.entries.length,
        itemBuilder: (_, i) {
          final item = prov.entries[i];
          return FileGridItem(
            item: item,
            isSelected: prov.selected.contains(item.path),
            selectMode: prov.selectMode,
            onTap: () => _onItemTap(context, item, prov),
            onLongPress: () => _onItemLongPress(item, prov),
            onSelect: () => prov.toggleSelect(item.path),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(FileExplorerProvider prov) {
    if (prov.searching) {
      return const Center(child: Text('Recherche dans les sous-dossiers…'));
    }
    final filtered = !prov.filter.selectsNothing;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(filtered ? Icons.search_off_rounded : Icons.folder_open_rounded,
              size: 64,
              color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            filtered
                ? 'Aucun élément ne correspond aux filtres'
                : 'Répertoire vide',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      Theme.of(context).iconTheme.color?.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 56, color: AppColors.error.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  // ── Bannière permission ────────────────────────────────────────────────────

  Widget _buildPermissionBanner() {
    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      backgroundColor: AppColors.warning.withValues(alpha: 0.12),
      content: const Text(
        'Sans « Accès à tous les fichiers », l\'explorateur n\'affiche que '
        'les dossiers et les images/vidéos/audio autorisés. '
        'Activez l\'autorisation pour voir tous les fichiers.',
        style: TextStyle(fontSize: 13),
      ),
      leading: const Icon(Icons.folder_off_outlined, color: AppColors.warning),
      actions: [
        TextButton(
          onPressed: () async {
            // Ouvre directement la page « Modifier les paramètres système »
            // (ou la page de l'app si la perm n'est pas applicable).
            final granted = await PermissionsService.hasManageExternalStorage();
            if (!granted) await PermissionsService.openAppSettingsPage();
          },
          child: const Text('Autoriser'),
        ),
      ],
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  void _showNewItemDialog(BuildContext ctx, FileExplorerProvider prov) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NewItemSheet(provider: prov),
    );
  }

  // ── Barre de sélection ─────────────────────────────────────────────────────

  Widget _buildSelectionBar(BuildContext ctx, FileExplorerProvider prov) {
    final trash = context.read<TrashService>();
    return SafeArea(
      child: Container(
        height: 64,
        color: Theme.of(ctx).colorScheme.surface,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: _selBtn(
                    Icons.close_rounded, 'Désélectionner', prov.clearSelection),
              ),
              SizedBox(
                width: 58,
                child:
                    _selBtn(Icons.select_all_rounded, 'Tout', prov.selectAll),
              ),
              SizedBox(
                width: 58,
                child: _selBtn(Icons.open_in_new_rounded, 'Ouvrir',
                    () => _openSelected(ctx, prov)),
              ),
              SizedBox(
                width: 58,
                child: _selBtn(Icons.copy_rounded, 'Copier',
                    () => _copySelected(ctx, prov)),
              ),
              SizedBox(
                width: 58,
                child: _selBtn(Icons.control_point_duplicate_rounded,
                    'Dupliquer', () => _duplicateSelected(prov)),
              ),
              SizedBox(
                width: 58,
                child: _selBtn(Icons.cut_rounded, 'Déplacer',
                    () => _moveSelected(ctx, prov)),
              ),
              SizedBox(
                width: 58,
                child: _selBtn(Icons.delete_outline_rounded, 'Corbeille',
                    () => _trashSelected(prov, trash)),
              ),
              SizedBox(
                width: 58,
                child: _selBtn(Icons.delete_forever_rounded, 'Supprimer',
                    () => _deleteSelected(ctx, prov)),
              ),
              SizedBox(
                width: 58,
                child: _selBtn(Icons.compress_rounded, 'Archiver',
                    () => _compressSelected(ctx, prov)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selBtn(IconData icon, String label, VoidCallback? onTap) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  // ── Gestion des taps ───────────────────────────────────────────────────────

  void _onItemTap(BuildContext ctx, FileItem item, FileExplorerProvider prov) {
    final pick = _pick;
    if (pick != null) {
      _onPickTap(item, prov, pick);
      return;
    }
    if (prov.selectMode) {
      prov.toggleSelect(item.path);
      return;
    }
    if (item.isDirectory) {
      prov.navigateTo(item.path);
    } else {
      _openFile(ctx, item);
    }
  }

  void _onItemLongPress(FileItem item, FileExplorerProvider prov) {
    final pick = _pick;
    if (pick != null) {
      if (!item.isDirectory && pick.allowMultiple) _togglePicked(item, prov);
      return;
    }
    prov.toggleSelectMode();
    prov.toggleSelect(item.path);
  }

  // ── Mode sélecteur ─────────────────────────────────────────────────────────

  void _onPickTap(
      FileItem item, FileExplorerProvider prov, ExplorerPickRequest pick) {
    if (item.isDirectory) {
      prov.navigateTo(item.path);
      return;
    }
    switch (pick.mode) {
      case ExplorerPickMode.files:
        if (pick.allowMultiple) {
          _togglePicked(item, prov);
        } else {
          Navigator.pop(context, [item.path]);
        }
      case ExplorerPickMode.save:
        // Reprendre le nom d'un fichier existant (pour le remplacer).
        setState(() {
          _saveName.text = item.name;
          _saveError = null;
        });
      case ExplorerPickMode.directory:
        break;
    }
  }

  void _togglePicked(FileItem item, FileExplorerProvider prov) {
    if (!prov.selectMode) prov.toggleSelectMode();
    prov.toggleSelect(item.path);
  }

  /// Pied de page du presse-papiers : rappelle ce qui attend d'être copié
  /// ou déplacé, et le valide dans le dossier courant.
  Widget _buildPasteBar(BuildContext ctx, FileExplorerProvider prov) {
    final theme = Theme.of(ctx);
    final cut = prov.clipboardIsCut;
    final count = prov.clipboardCount;
    final blocked = prov.pasteBlockReason;
    final what =
        count == 1 ? p.basename(prov.clipboard.first) : '$count éléments';
    final here = prov.currentPath.isEmpty
        ? ''
        : p.basename(prov.currentPath).isEmpty
            ? prov.currentPath
            : p.basename(prov.currentPath);
    return SafeArea(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                cut ? Icons.drive_file_move_outline : Icons.file_copy_outlined,
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cut ? 'Déplacer' : 'Copier'} $what',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      blocked ?? 'vers « $here »',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: blocked != null ? AppColors.error : null),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _pasting ? null : prov.clearClipboard,
                child: const Text('Annuler'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: blocked != null || _pasting
                    ? null
                    : () => _pasteHere(ctx, prov),
                icon: _pasting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(cut
                        ? Icons.content_paste_go_rounded
                        : Icons.content_paste_rounded),
                label: Text(cut ? 'Déplacer ici' : 'Copier ici'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickBar(
      BuildContext ctx, FileExplorerProvider prov, ExplorerPickRequest pick) {
    final Widget content;
    switch (pick.mode) {
      case ExplorerPickMode.files:
        if (!pick.allowMultiple) return const SizedBox.shrink();
        final count = prov.selected.length;
        content = Row(
          children: [
            Expanded(
              child: Text(
                count == 0
                    ? 'Touchez les fichiers à ajouter'
                    : '$count fichier(s) sélectionné(s)',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ),
            if (count > 0)
              TextButton(
                  onPressed: prov.clearSelection,
                  child: const Text('Désélectionner')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: count == 0
                  ? null
                  : () => Navigator.pop(ctx, prov.selected.toList()),
              child: const Text('Valider'),
            ),
          ],
        );
      case ExplorerPickMode.directory:
        content = Row(
          children: [
            const Icon(Icons.folder_rounded, color: AppColors.colorFolder),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                p.basename(prov.currentPath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: prov.currentPath.isEmpty || prov.error != null
                  ? null
                  : () => Navigator.pop(ctx, [prov.currentPath]),
              child: const Text('Choisir ce dossier'),
            ),
          ],
        );
      case ExplorerPickMode.save:
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _saveName,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Nom du fichier',
                  errorText: _saveError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) {
                  if (_saveError != null) setState(() => _saveError = null);
                },
                onSubmitted: (_) => _confirmSave(prov),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton(
                onPressed: prov.currentPath.isEmpty || prov.error != null
                    ? null
                    : () => _confirmSave(prov),
                child: const Text('Enregistrer'),
              ),
            ),
          ],
        );
    }
    return SafeArea(
      child: Material(
        color: Theme.of(ctx).colorScheme.surface,
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              16, 10, 16, 10 + MediaQuery.of(ctx).viewInsets.bottom),
          child: content,
        ),
      ),
    );
  }

  Future<void> _confirmSave(FileExplorerProvider prov) async {
    final name = _saveName.text.trim();
    final invalid = FileNameValidator.validate(name);
    if (invalid != null) {
      setState(() => _saveError = invalid);
      return;
    }
    final target = p.join(prov.currentPath, name);
    if (FileSystemEntity.typeSync(target) == FileSystemEntityType.directory) {
      setState(() => _saveError = 'Un dossier porte déjà ce nom');
      return;
    }
    if (File(target).existsSync()) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: const Text('Remplacer le fichier ?'),
          content: Text('« $name » existe déjà dans ce dossier.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Annuler')),
            TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Remplacer',
                  style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    if (mounted) Navigator.pop(context, [target]);
  }

  /// @brief Ouvre un fichier via [FileOpener] avec les listes contextuelles.
  void _openFile(BuildContext ctx, FileItem item) {
    // Toutes les images du dossier pour la navigation dans le visionneur
    final allImages = item.category == FileCategory.image
        ? _provider.entries
            .where((e) => e.category == FileCategory.image)
            .map((e) => e.path)
            .toList()
        : null;

    // Tous les médias du dossier pour la lecture en séquence
    final playlist = (item.category == FileCategory.audio ||
            item.category == FileCategory.video)
        ? _provider.entries
            .where((e) =>
                e.category == FileCategory.audio ||
                e.category == FileCategory.video)
            .map((e) => e.path)
            .toList()
        : null;

    FileOpener.open(ctx, item, allImages: allImages, playlist: playlist);
  }

  /// @brief Ouvre les fichiers sélectionnés via [FileOpener.openMany].
  void _openSelected(BuildContext ctx, FileExplorerProvider prov) {
    final items =
        _provider.entries.where((e) => prov.selected.contains(e.path)).toList();
    if (items.isEmpty) return;

    prov.clearSelection();
    FileOpener.openMany(ctx, items);
  }

  // ── Actions de sélection multiple ─────────────────────────────────────────

  Future<void> _trashSelected(
      FileExplorerProvider prov, TrashService trash) async {
    final report = await trash.moveAllToTrash(prov.selected.toList());
    prov.clearSelection();
    await prov.refresh();
    if (mounted) {
      showFileOpReport(context, report, verb: 'mis à la corbeille');
    }
  }

  Future<void> _deleteSelected(
      BuildContext ctx, FileExplorerProvider prov) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer définitivement'),
        content: Text(
            'Supprimer ${prov.selected.length} élément(s) définitivement ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final report = await prov.deletePermanently(prov.selected.toList());
    prov.clearSelection();
    if (mounted) showFileOpReport(context, report, verb: 'supprimé(s)');
  }

  Future<void> _duplicateSelected(FileExplorerProvider prov) async {
    final report = await prov.duplicate(prov.selected.toList());
    prov.clearSelection();
    if (mounted) showFileOpReport(context, report, verb: 'dupliqué(s)');
  }

  void _copySelected(BuildContext ctx, FileExplorerProvider prov) {
    final count = prov.selected.length;
    prov.copyToClipboard(prov.selected);
    prov.clearSelection();
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('$count élément(s) copié(s) — naviguez puis collez')));
  }

  void _moveSelected(BuildContext ctx, FileExplorerProvider prov) {
    final count = prov.selected.length;
    prov.cutToClipboard(prov.selected);
    prov.clearSelection();
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('$count élément(s) coupé(s) — naviguez puis collez')));
  }

  Future<void> _pasteHere(BuildContext ctx, FileExplorerProvider prov) async {
    if (_pasting) return;
    final wasCut = prov.clipboardIsCut;
    setState(() => _pasting = true);
    final FileOpReport report;
    try {
      report = await prov.pasteClipboard(
          onConflict: askingConflictResolver(context));
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
    // Copie réussie : le pied de page disparaît (un « couper » vide déjà le
    // presse-papiers des éléments déplacés).
    if (!wasCut && report.failures.isEmpty) prov.clearClipboard();
    if (!mounted) return;
    showFileOpReport(context, report, verb: wasCut ? 'déplacé(s)' : 'collé(s)');
  }

  Future<void> _compressSelected(
      BuildContext ctx, FileExplorerProvider prov) async {
    final paths = prov.selected.toList();
    if (paths.isEmpty) return;
    final created = await showCompressDialog(
      ctx,
      sourcePaths: paths,
      destDir: prov.currentPath,
    );
    if (created) {
      prov.clearSelection();
      prov.refresh();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feuille de création d'élément
// ─────────────────────────────────────────────────────────────────────────────

/// @class _NewItemSheet
/// @brief Bottom sheet pour créer un répertoire ou un fichier.
class _NewItemSheet extends StatefulWidget {
  final FileExplorerProvider provider;
  const _NewItemSheet({required this.provider});

  @override
  State<_NewItemSheet> createState() => _NewItemSheetState();
}

class _NewItemSheetState extends State<_NewItemSheet> {
  final _ctrl = TextEditingController();
  bool _isDir = true;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _create(BuildContext ctx) async {
    final name = _ctrl.text.trim();
    final invalid = FileNameValidator.validate(name);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    try {
      if (_isDir) {
        await widget.provider.createDirectory(name);
      } else {
        await widget.provider.createFile(name);
      }
      if (ctx.mounted) Navigator.pop(ctx);
    } on FileOpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nouveau', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Dossier'),
                selected: _isDir,
                onSelected: (_) => setState(() => _isDir = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Fichier'),
                selected: !_isDir,
                onSelected: (_) => setState(() => _isDir = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText:
                  _isDir ? 'Nom du dossier' : 'Nom du fichier (ex: script.py)',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _create(ctx),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _create(ctx),
                child: const Text('Créer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
