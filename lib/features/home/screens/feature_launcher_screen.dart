/// @file feature_launcher_screen.dart
/// @brief Menu principal macro-app : grille de cartes pour accéder à chaque
/// fonctionnalité, restauration de l'état au lancement, badge « actif » sur
/// les fonctionnalités qui ont de l'état en mémoire (lecture en cours,
/// onglets ouverts…).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/services/app_state_service.dart';
import '../../../core/services/permissions_service.dart';
import '../../file_explorer/screens/file_explorer_screen.dart';
import '../../media_player/providers/media_player_provider.dart';
import '../../media_player/screens/media_player_screen.dart';
import '../../password_vault/screens/password_vault_home_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../text_editor/screens/unified_editor_screen.dart';
import '../../video_editor/screens/video_editor_home_screen.dart';
import '../widgets/feature_card.dart';
import 'recent_files_screen.dart';

class FeatureLauncherScreen extends StatefulWidget {
  const FeatureLauncherScreen({super.key});

  @override
  State<FeatureLauncherScreen> createState() => _FeatureLauncherScreenState();
}

class _FeatureLauncherScreenState extends State<FeatureLauncherScreen>
    with WidgetsBindingObserver {
  bool _restoredOnce = false;
  UnifiedEditorProvider? _editor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Persiste la liste d'onglets ouverts à chaque changement.
      _editor = context.read<UnifiedEditorProvider>();
      _editor!.addListener(_persistEditorTabs);

      // Demande les permissions tant qu'un accès critique manque.
      // Vérifié à chaque lancement (et pas seulement au premier) : si
      // l'utilisateur a refusé ou n'a pas accordé tous les droits, on
      // redemande systématiquement.
      if (await PermissionsService.hasMissingCriticalPermissions() &&
          mounted) {
        await _showPermissionsIntro();
        if (!mounted) return;
        await PermissionsService.requestAll();
        await PermissionsService.markFirstLaunchDone();
      }

      if (mounted) _maybeRestore();
    });
  }

  Future<void> _showPermissionsIntro() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Autorisations nécessaires'),
        content: const Text(
          'OmniExplorer va vous demander plusieurs autorisations :\n\n'
          '• Stockage / Médias : pour parcourir et lire vos fichiers\n'
          '• Notifications : pour les contrôles de lecture audio\n'
          '• Tous les fichiers (Settings → spécial) : pour explorer hors '
          'des dossiers Médias\n\n'
          'Vous pourrez modifier ces choix à tout moment dans les Paramètres.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editor?.removeListener(_persistEditorTabs);
    super.dispose();
  }

  /// Sauvegarde défensive de l'état lorsque l'app passe en arrière-plan
  /// (Android : `paused` quand l'utilisateur quitte sans tuer le process).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted) {
      _persistEditorTabs();
    }
  }

  void _persistEditorTabs() {
    if (_editor == null || !mounted) return;
    final paths = _editor!.tabs.map((t) => t.path).toList();
    context.read<AppStateService>().setEditorTabs(paths);
  }

  /// Au premier build après le démarrage, rouvre la dernière fonctionnalité
  /// utilisée si l'option est activée.
  Future<void> _maybeRestore() async {
    if (_restoredOnce || !mounted) return;
    _restoredOnce = true;
    final state = context.read<AppStateService>();
    if (!state.restoreOnLaunch) return;
    final last = state.lastFeature;
    if (last == null || last == AppFeature.settings) return;
    // Empile la dernière feature au-dessus du launcher.
    _open(last);
  }

  void _open(AppFeature f) {
    final state = context.read<AppStateService>();
    state.setLastFeature(f);
    Widget? screen;
    switch (f) {
      case AppFeature.fileExplorer:
        screen = const FileExplorerScreen();
        break;
      case AppFeature.images:
        // Inclut les dossiers pour pouvoir naviguer + filtre images.
        screen = const FileExplorerScreen(
          initialCategories: {FileCategory.folder, FileCategory.image},
        );
        break;
      case AppFeature.pdfViewer:
        screen = const FileExplorerScreen(
          initialCategories: {FileCategory.folder, FileCategory.pdf},
        );
        break;
      case AppFeature.mediaPlayer:
        final hasMedia = context.read<MediaPlayerProvider>().hasMedia;
        screen = hasMedia
            ? const MediaPlayerScreen()
            : const FileExplorerScreen(
                initialCategories: {
                  FileCategory.folder,
                  FileCategory.audio,
                  FileCategory.video,
                },
              );
        break;
      case AppFeature.textEditor:
        // Si aucun onglet n'est en mémoire, rouvre la dernière liste persistée.
        final editorProv = context.read<UnifiedEditorProvider>();
        final saved = state.editorTabs;
        final paths = editorProv.tabs.isEmpty ? saved : const <String>[];
        screen = UnifiedEditorScreen(filePaths: paths);
        break;
      case AppFeature.videoEditor:
        screen = const VideoEditorHomeScreen();
        break;
      case AppFeature.passwordVault:
        screen = const PasswordVaultHomeScreen();
        break;
      case AppFeature.settings:
        screen = const SettingsScreen();
        break;
      case AppFeature.recents:
        screen = const RecentFilesScreen();
        break;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
  }

  // ── Construction ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = context.watch<MediaPlayerProvider>();
    final editor = context.watch<UnifiedEditorProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, c) {
            final crossAxis = c.maxWidth >= 1100
                ? 4
                : c.maxWidth >= 720
                    ? 3
                    : 2;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 120,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    title: Text('OmniExplorer',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.history_rounded),
                      tooltip: 'Récents',
                      onPressed: () => _open(AppFeature.recents),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      tooltip: 'Paramètres',
                      onPressed: () => _open(AppFeature.settings),
                    ),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxis,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.05,
                    ),
                    delegate: SliverChildListDelegate.fixed(_tiles(media, editor)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _tiles(MediaPlayerProvider media, UnifiedEditorProvider editor) {
    return [
      FeatureCard(
        icon: Icons.folder_rounded,
        color: AppColors.colorFolder,
        title: 'Explorateur',
        subtitle: 'Parcourir vos fichiers et dossiers',
        onTap: () => _open(AppFeature.fileExplorer),
      ),
      FeatureCard(
        icon: Icons.image_rounded,
        color: AppColors.colorImage,
        title: 'Images',
        subtitle: 'Photos, illustrations, GIF',
        onTap: () => _open(AppFeature.images),
      ),
      FeatureCard(
        icon: Icons.play_circle_rounded,
        color: AppColors.colorAudio,
        title: 'Lecteur multimédia',
        subtitle: media.hasMedia
            ? 'En cours : ${media.currentPath?.split("/").last ?? "média"}'
            : 'Musique et vidéos',
        badge: media.hasMedia
            ? (media.isPlaying ? '▶︎' : '⏸')
            : null,
        onTap: () => _open(AppFeature.mediaPlayer),
      ),
      FeatureCard(
        icon: Icons.picture_as_pdf_rounded,
        color: AppColors.colorPdf,
        title: 'PDF',
        subtitle: 'Lecteur de documents',
        onTap: () => _open(AppFeature.pdfViewer),
      ),
      FeatureCard(
        icon: Icons.code_rounded,
        color: AppColors.colorCode,
        title: 'Éditeur',
        subtitle: editor.tabs.isNotEmpty
            ? '${editor.tabs.length} onglet${editor.tabs.length > 1 ? "s" : ""}'
            : 'Texte, code, markdown, hex',
        badge: editor.tabs.isNotEmpty ? '${editor.tabs.length}' : null,
        onTap: () => _open(AppFeature.textEditor),
      ),
      FeatureCard(
        icon: Icons.movie_filter_rounded,
        color: AppColors.colorVideo,
        title: 'Éditeur multimédia',
        subtitle: 'Vidéo, audio, image · filmer & enregistrer',
        onTap: () => _open(AppFeature.videoEditor),
      ),
      FeatureCard(
        icon: Icons.shield_rounded,
        color: AppColors.warning,
        title: 'Coffre-fort',
        subtitle: 'Mots de passe chiffrés',
        badge: 'à venir',
        onTap: () => _open(AppFeature.passwordVault),
      ),
      FeatureCard(
        icon: Icons.settings_rounded,
        color: AppColors.colorText,
        title: 'Paramètres',
        subtitle: 'Thème, polices, comptes',
        onTap: () => _open(AppFeature.settings),
      ),
    ];
  }
}
