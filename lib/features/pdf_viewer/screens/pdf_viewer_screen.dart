/// @file pdf_viewer_screen.dart
/// @brief Visionneur de fichiers PDF avec navigation par pages, zoom et partage.
///
/// Fonctionnalités :
/// - Rendu PDF natif via pdfx
/// - Navigation page précédente / suivante
/// - Saisie directe du numéro de page
/// - Zoom pinch-to-zoom
/// - Barre d'outils escamotable
/// - Partage du fichier
/// - Support multi-fichiers avec onglets

import 'package:flutter/material.dart';
import 'package:omni_explorer/app/theme/app_theme.dart';
import 'package:omni_explorer/core/utils/system_ui.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart'; // pour Share et XFile
import 'package:provider/provider.dart';
import '../../../core/services/settings_service.dart';

/// @class PdfViewerScreen
/// @brief Écran de visualisation d'un ou plusieurs fichiers PDF.
class PdfViewerScreen extends StatefulWidget {
  /// Chemins absolus des fichiers PDF à ouvrir.
  final List<String> filePaths;

  const PdfViewerScreen({super.key, required this.filePaths});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with TickerProviderStateMixin {
  late TabController? _tabController;

  @override
  void initState() {
    super.initState();
    SystemUI.hideBottomBar();
    for (final path in widget.filePaths) {
      context.read<SettingsService>().addRecentFile(path);
    }
    if (widget.filePaths.length > 1) {
      _tabController = TabController(
        length: widget.filePaths.length,
        vsync: this,
      );
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filePaths.length == 1) {
      return _PdfView(filePath: widget.filePaths[0]);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(p.basename(widget.filePaths[_tabController?.index ?? 0])),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: widget.filePaths
              .map((path) => Tab(text: p.basename(path)))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: widget.filePaths
            .map((path) => _PdfView(filePath: path))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget de contenu PDF
// ---------------------------------------------------------------------------

class _PdfView extends StatefulWidget {
  final String filePath;
  const _PdfView({required this.filePath});

  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView> {
  late PdfControllerPinch _pdfController;
  int _totalPages = 0;
  int _currentPage = 1;
  bool _barsVisible = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    try {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.filePath),
      );
    } catch (e) {
      setState(() {
        _error = 'Impossible d\'ouvrir le PDF :\n$e';
      });
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  void _share() {
    Share.shareXFiles([XFile(widget.filePath)]);
  }

  void _goToPageDialog(BuildContext context) {
    final controller = TextEditingController(text: _currentPage.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aller à la page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '1 – $_totalPages',
          ),
          onSubmitted: (v) {
            final page = int.tryParse(v);
            if (page != null && page >= 1 && page <= _totalPages) {
              _pdfController.jumpToPage(page);
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(controller.text);
              if (page != null && page >= 1 && page <= _totalPages) {
                _pdfController.jumpToPage(page);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Aller'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final foregroundColor = isDark
        ? AppColors.darkSurface2
        : AppColors.lightSurface2;
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        title: Text(p.basename(widget.filePath)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _share,
            tooltip: 'Partager',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error == null)
            GestureDetector(
              onTap: () => setState(() => _barsVisible = !_barsVisible),
              child: PdfViewPinch(
                controller: _pdfController,
                onDocumentLoaded: (doc) {
                  setState(() {
                    _totalPages = doc.pagesCount;
                  });
                },
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                },
                onDocumentError: (e) {
                  setState(() {
                    _error = 'Erreur chargement PDF : $e';
                  });
                },
                builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                  options: const DefaultBuilderOptions(),
                  documentLoaderBuilder: (_) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  pageLoaderBuilder: (_) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorBuilder: (_, e) => Center(
                    child: Text(
                      'Erreur page : $e',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
                // Background decoration depend on theme
                backgroundDecoration: BoxDecoration(
                  color: backgroundColor.withAlpha(250)
                ),
              ),
            )
          else
            _ErrorView(message: _error!),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _barsVisible ? 0 : -80,
            left: 0,
            right: 0,
            child: _BottomBar(
              currentPage: _currentPage,
              totalPages: _totalPages,
              controller: _pdfController,
              onGoToPage: () => _goToPageDialog(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets internes
// ---------------------------------------------------------------------------

/// @class _BottomBar
/// @brief Barre de navigation bas du viewer PDF.
class _BottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final PdfControllerPinch controller;
  final VoidCallback onGoToPage;

  const _BottomBar({
    required this.currentPage,
    required this.totalPages,
    required this.controller,
    required this.onGoToPage,
  });

  @override
  Widget build(BuildContext context) {
    final canPrev = currentPage > 1;
    final canNext = currentPage < totalPages;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;

    return Container(
      color: backgroundColor.withAlpha(250),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        top: 8,
        left: 16,
        right: 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Précédent
          IconButton(
            icon: Icon(Icons.chevron_left, color: theme.iconTheme.color?.withValues(alpha:0.4)),
            onPressed: canPrev
                ? () => controller.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                    )
                : null,
            tooltip: 'Page précédente',
          ),

          // Indicateur de page (cliquable)
          GestureDetector(
            onTap: totalPages > 0 ? onGoToPage : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                totalPages > 0
                    ? '$currentPage / $totalPages'
                    : '…',
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Suivant
          IconButton(
            icon: Icon(Icons.chevron_right, color: theme.iconTheme.color?.withValues(alpha:0.4)),
            onPressed: canNext
                ? () => controller.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                    )
                : null,
            tooltip: 'Page suivante',
          ),
        ],
      ),
    );
  }
}

/// @class _ErrorView
/// @brief Vue d'erreur du viewer PDF.
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf,
                size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              message,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Retour'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
