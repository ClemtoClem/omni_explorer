/// @file path_bar.dart
/// @brief Barre de chemin interactive et éditable, style Ubuntu.
///
/// Affiche le chemin courant sous forme de boutons cliquables.
/// Peut être basculée en mode édition pour saisir un chemin manuellement.
/// Contient les boutons Remonter (↑), Undo (←) et Redo (→).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_theme.dart';

/// @class PathBar
/// @brief Widget de barre de chemin interactive.
class PathBar extends StatefulWidget {
  final String currentPath;

  /// Chemin minimum affiché (les segments au-dessus sont masqués).
  final String rootPath;
  final void Function(String) onNavigate;
  final void Function(int) onSegmentTap;
  final VoidCallback? onUp;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  const PathBar({
    super.key,
    required this.currentPath,
    this.rootPath = '/',
    required this.onNavigate,
    required this.onSegmentTap,
    this.onUp,
    this.onUndo,
    this.onRedo,
  });

  @override
  State<PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<PathBar> {
  bool _editMode = false;
  late TextEditingController _ctrl;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentPath);
  }

  @override
  void didUpdateWidget(PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editMode && oldWidget.currentPath != widget.currentPath) {
      _ctrl.text = widget.currentPath;
      // Scroll automatique vers la fin
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Construction ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      height: 44,
      color: bgColor,
      child: Row(
        children: [
          // ── Bouton Remonter ────────────────────────────────────────────
          _NavBtn(
            icon: Icons.arrow_upward_rounded,
            tooltip: 'Répertoire parent',
            enabled: widget.onUp != null,
            onTap: widget.onUp,
          ),
          // ── Bouton Undo ────────────────────────────────────────────────
          _NavBtn(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Précédent',
            enabled: widget.onUndo != null,
            onTap: widget.onUndo,
          ),
          // ── Bouton Redo ────────────────────────────────────────────────
          _NavBtn(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Suivant',
            enabled: widget.onRedo != null,
            onTap: widget.onRedo,
          ),
          // ── Divider ────────────────────────────────────────────────────
          Container(width: 1, height: 28, color: border),
          // ── Chemin (mode affichage ou édition) ─────────────────────────
          Expanded(
            child: _editMode
                ? _buildEditMode(context)
                : _buildDisplayMode(context),
          ),
          // ── Bouton bascule mode édition ────────────────────────────────
          Tooltip(
            message: _editMode ? 'Valider le chemin' : 'Éditer le chemin',
            child: InkWell(
              onTap: _toggleEditMode,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  _editMode ? Icons.check_rounded : Icons.edit_rounded,
                  size: 18,
                  color: _editMode ? AppColors.accent : theme.iconTheme.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode affichage ────────────────────────────────────────────────────────

  Widget _buildDisplayMode(BuildContext context) {
    final theme = Theme.of(context);
    final allSegs =
        widget.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final rootSegs =
        widget.rootPath.split('/').where((s) => s.isNotEmpty).toList();
    // Miroir de provider.pathSegments : commence au dernier segment de rootPath.
    final offset = (rootSegs.length - 1).clamp(0, allSegs.length);
    final segs = allSegs.sublist(offset);

    return GestureDetector(
      onDoubleTap: () => setState(() => _editMode = true),
      child: ListView(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          if (segs.isEmpty)
            _PathSegment(
              label: rootSegs.isNotEmpty ? rootSegs.last : '/',
              onTap: () => widget.onNavigate(widget.rootPath),
              isLast: true,
            )
          else
            for (int i = 0; i < segs.length; i++) ...[
              if (i > 0)
                Icon(Icons.chevron_right_rounded,
                    size: 16,
                    color: theme.iconTheme.color?.withValues(alpha: 0.4)),
              _PathSegment(
                label: segs[i],
                onTap: () => widget.onSegmentTap(i),
                isLast: i == segs.length - 1,
              ),
            ],
        ],
      ),
    );
  }

  // ── Mode édition ──────────────────────────────────────────────────────────

  Widget _buildEditMode(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        style: GoogleFonts.jetBrainsMono(fontSize: 12),
        onSubmitted: _commitEdit,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  void _toggleEditMode() {
    if (_editMode) {
      _commitEdit(_ctrl.text);
    } else {
      setState(() {
        _editMode = true;
        _ctrl.text = widget.currentPath;
        _ctrl.selection =
            TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      });
    }
  }

  void _commitEdit(String value) {
    setState(() => _editMode = false);
    final path = value.trim();
    if (path.isNotEmpty) widget.onNavigate(path);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class _PathSegment
/// @brief Bouton représentant un segment du chemin.
class _PathSegment extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLast;

  const _PathSegment({
    required this.label,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: isLast
            ? BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Text(
          label,
          style: GoogleFonts.jost(
            fontSize: 12,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
            color:
                isLast ? AppColors.accent : theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class _NavBtn
/// @brief Bouton de navigation de la barre de chemin.
class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onTap;

  const _NavBtn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 38,
          height: 44,
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? Theme.of(context).iconTheme.color
                : Theme.of(context).iconTheme.color?.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
