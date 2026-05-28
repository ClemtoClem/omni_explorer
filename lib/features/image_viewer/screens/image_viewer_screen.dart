/// @file image_viewer_screen.dart
/// @brief Visionneur d'images personnalisé : zoom, rotation, navigation, diaporama.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/utils/system_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/services/settings_service.dart';

// ─── Écran principal ──────────────────────────────────────────────────────────

class ImageViewerScreen extends StatefulWidget {
  final String imagePath;
  final List<String> allImages;

  const ImageViewerScreen({
    super.key,
    required this.imagePath,
    required this.allImages,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {

  // ── Navigation ────────────────────────────────────────────────────────────
  late PageController _pageCtrl;
  late int _currentIdx;

  // ── Visibilité UI ─────────────────────────────────────────────────────────
  bool _showUI = true;
  late AnimationController _uiAnim;
  late Animation<double> _uiFade;

  // ── Diaporama ─────────────────────────────────────────────────────────────
  bool _slideshow = false;
  int _slideshowSec = 3;
  Timer? _slideshowTimer;

  // ── Transformations de la page courante ───────────────────────────────────
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _rotationAngle = 0.0;

  // Valeurs en début de geste (référence cumulative)
  double _gScale = 1.0;
  Offset _gOffset = Offset.zero;
  Offset _gFocal = Offset.zero;
  double _gRotation = 0.0;

  // ── Overlays temporaires (1 s) ────────────────────────────────────────────
  bool _showZoomLabel = false;
  bool _showRotLabel = false;
  Timer? _zoomTimer;
  Timer? _rotTimer;

  // ─────────────────────────────────────────────────────────────────────────

  List<String> get _images =>
      widget.allImages.isEmpty ? [widget.imagePath] : widget.allImages;

  String get _currentPath => _images[_currentIdx];

  bool get _isZoomed => _scale > 1.05;

  @override
  void initState() {
    super.initState();
    SystemUI.hideBottomBar();
    for (final path in _images) {
      context.read<SettingsService>().addRecentFile(path);
    }
    _currentIdx = _images.indexOf(widget.imagePath);
    if (_currentIdx < 0) _currentIdx = 0;
    _pageCtrl = PageController(initialPage: _currentIdx);

    _uiAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _uiFade = CurvedAnimation(parent: _uiAnim, curve: Curves.easeInOut);
  }

  @override
  void dispose() {

    _slideshowTimer?.cancel();
    _zoomTimer?.cancel();
    _rotTimer?.cancel();
    _pageCtrl.dispose();
    _uiAnim.dispose();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  void _toggleUI() {
    setState(() => _showUI = !_showUI);
    _showUI ? _uiAnim.forward() : _uiAnim.reverse();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _nextImage() {
    if (_images.length <= 1) return;
    _pageCtrl.animateToPage(
      (_currentIdx + 1) % _images.length,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _prevImage() {
    if (_images.length <= 1) return;
    _pageCtrl.animateToPage(
      (_currentIdx - 1 + _images.length) % _images.length,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int idx) {
    setState(() {
      _currentIdx = idx;
      _scale = 1.0;
      _offset = Offset.zero;
      _rotationAngle = 0.0;
      _showZoomLabel = false;
      _showRotLabel = false;
    });
  }

  // ── Diaporama ─────────────────────────────────────────────────────────────

  void _startSlideshow() {
    setState(() => _slideshow = true);
    _slideshowTimer?.cancel();
    _slideshowTimer = Timer.periodic(
      Duration(seconds: _slideshowSec),
      (_) => _nextImage(),
    );
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    setState(() => _slideshow = false);
  }

  // ── Double tap (zoom 150 % / reset 100 %) ─────────────────────────────────

  void _onDoubleTap() {
    if (_isZoomed) {
      setState(() {
        _scale = 1.0;
        _offset = Offset.zero;
        _showUI = true;
      });
      _uiAnim.forward();
    } else {
      setState(() => _scale = 1.5);
      if (_slideshow) _stopSlideshow();
    }
    _flashZoom();
  }

  // ── Gestes scale / pan / rotation ─────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _gScale    = _scale;
    _gOffset   = _offset;
    _gFocal    = d.localFocalPoint;
    _gRotation = _rotationAngle;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final newScale  = (_gScale * d.scale).clamp(0.5, 3.0);
    final newOffset = _gOffset + (d.localFocalPoint - _gFocal);

    final scaleChanged = (newScale - _scale).abs() > 0.01;
    final rotChanged   = d.pointerCount >= 2 && d.rotation.abs() > 0.005;

    setState(() {
      _scale  = newScale;
      _offset = newOffset;
      if (rotChanged) {
        _rotationAngle = _gRotation + d.rotation;
      }
    });

    if (scaleChanged) _flashZoom();
    if (rotChanged)   _flashRot();
  }

  // ── Boutons rotation ──────────────────────────────────────────────────────

  void _rotateCW()  => _applyRotation( math.pi / 2);
  void _rotateCCW() => _applyRotation(-math.pi / 2);

  void _applyRotation(double delta) {
    setState(() => _rotationAngle += delta);
    _flashRot();
  }

  // ── Overlays 1 s ─────────────────────────────────────────────────────────

  void _flashZoom() {
    setState(() => _showZoomLabel = true);
    _zoomTimer?.cancel();
    _zoomTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showZoomLabel = false);
    });
  }

  void _flashRot() {
    setState(() => _showRotLabel = true);
    _rotTimer?.cancel();
    _rotTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showRotLabel = false);
    });
  }

  String get _zoomText => '${(_scale * 100).round()}%';

  String get _rotText {
    double deg = (_rotationAngle * 180 / math.pi) % 360;
    if (deg < 0) deg += 360;
    return '${deg.round()}°';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(
        children: [
          // ── PageView ────────────────────────────────────────────────────────
          PageView.builder(
            controller: _pageCtrl,
            // Désactive le swipe lorsque l'image est zoomée (pan à la place).
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            itemCount: _images.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) => _buildPage(i),
          ),

          // ── Barre supérieure ────────────────────────────────────────────────
          FadeTransition(
            opacity: _uiFade,
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildTopBar(safeTop),
            ),
          ),

          // ── Barre inférieure (miniatures) ───────────────────────────────────
          FadeTransition(
            opacity: _uiFade,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomBar(),
            ),
          ),

          // ── Flèches gauche / droite ─────────────────────────────────────────
          if (_showUI && _images.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _NavArrow(
                icon: Icons.chevron_left_rounded,
                onTap: _prevImage,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _NavArrow(
                icon: Icons.chevron_right_rounded,
                onTap: _nextImage,
              ),
            ),
          ],

          // ── Overlay zoom / rotation ─────────────────────────────────────────
          if (_showZoomLabel || _showRotLabel)
            Positioned(
              bottom: 96,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showZoomLabel)
                    _OverlayChip(
                        icon: Icons.zoom_in_rounded, text: _zoomText),
                  if (_showRotLabel)
                    _OverlayChip(
                        icon: Icons.rotate_right_rounded, text: _rotText),
                ],
              ),
            ),

          // ── Indicateur diaporama ────────────────────────────────────────────
          if (_slideshow)
            Positioned(
              top: safeTop + 60,
              right: 16,
              child: const _SlideshowDot(),
            ),
        ],
      ),
    );
  }

  // ── Page image ────────────────────────────────────────────────────────────

  Widget _buildPage(int idx) {
    final path   = _images[idx];
    final isCurr = idx == _currentIdx;
    final ext    = FileUtils.extOf(path);

    Widget img;
    if (ext == 'svg') {
      img = Center(
        child: SvgPicture.file(File(path), fit: BoxFit.contain),
      );
    } else {
      img = Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  color: Colors.white38, size: 64),
              SizedBox(height: 8),
              Text('Image non disponible',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Seule la page courante porte les gestes et les transformations.
    if (!isCurr) return img;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleUI,
      onDoubleTap: _onDoubleTap,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
          ..rotateZ(_rotationAngle)
          ..scaleByDouble(_scale, _scale, 1, 1),
        child: img,
      ),
    );
  }

  // ── Barre supérieure ──────────────────────────────────────────────────────

  Widget _buildTopBar(double safeTop) {
    final name  = p.basename(_currentPath);
    final count = _images.length;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xDD000000), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: safeTop + 4,
        left: 4,
        right: 8,
        bottom: 24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Retour
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Retour',
          ),
          // Nom + compteur
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: GoogleFonts.jost(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  count > 1 ? 'Photo ${_currentIdx + 1} / $count' : 'Photo',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          // Rotation gauche
          _IconBtn(
            icon: Icons.rotate_left_rounded,
            onTap: _rotateCCW,
            tooltip: 'Rotation gauche',
          ),
          // Rotation droite
          _IconBtn(
            icon: Icons.rotate_right_rounded,
            onTap: _rotateCW,
            tooltip: 'Rotation droite',
          ),
          // Diaporama
          _IconBtn(
            icon: _slideshow
                ? Icons.stop_rounded
                : Icons.slideshow_rounded,
            color: _slideshow ? AppColors.accent : Colors.white,
            onTap: _slideshow ? _stopSlideshow : _showSlideshowSheet,
            tooltip: _slideshow ? 'Arrêter' : 'Diaporama',
          ),
          // Partager
          _IconBtn(
            icon: Icons.share_rounded,
            onTap: () => Share.shareXFiles([XFile(_currentPath)]),
            tooltip: 'Partager',
          ),
        ],
      ),
    );
  }

  // ── Barre inférieure (miniatures) ─────────────────────────────────────────

  Widget _buildBottomBar() {
    final images = _images;
    if (images.length <= 1) return const SizedBox.shrink();
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xDD000000), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(bottom: safeBottom + 8, top: 16),
      child: SizedBox(
        height: 64,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: images.length,
          itemBuilder: (_, i) {
            final sel = i == _currentIdx;
            return GestureDetector(
              onTap: () => _pageCtrl.animateToPage(
                i,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: sel ? 60 : 50,
                height: sel ? 60 : 50,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(images[i]),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      size: 20,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Feuille diaporama ─────────────────────────────────────────────────────

  void _showSlideshowSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Diaporama',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Intervalle'),
                  Text(
                    '$_slideshowSec sec',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _slideshowSec.toDouble(),
                min: 1,
                max: 60,
                divisions: 59,
                label: '$_slideshowSec s',
                onChanged: (v) {
                  setState(() => _slideshowSec = v.round());
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Démarrer'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _startSlideshow();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Flèche navigation ────────────────────────────────────────────────────────

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 88,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white70, size: 28),
      ),
    );
  }
}

// ─── Bouton icône top-bar ─────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color color;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 22),
      onPressed: onTap,
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

// ─── Chip overlay (zoom % / angle rotation) ───────────────────────────────────

class _OverlayChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _OverlayChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Indicateur diaporama animé ───────────────────────────────────────────────

class _SlideshowDot extends StatefulWidget {
  const _SlideshowDot();

  @override
  State<_SlideshowDot> createState() => _SlideshowDotState();
}

class _SlideshowDotState extends State<_SlideshowDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.slideshow_rounded, color: Colors.white, size: 14),
            SizedBox(width: 5),
            Text('Diaporama',
                style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
