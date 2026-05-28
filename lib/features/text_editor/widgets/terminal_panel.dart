
/// @file terminal_panel.dart
/// @brief Panneau terminal integre dans l'editeur de code.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_theme.dart';

/// @class TerminalPanel
/// @brief Widget terminal affichant la sortie d'un processus.
class TerminalPanel extends StatefulWidget {
  final List<String> output;
  final VoidCallback  onClear;
  final VoidCallback  onClose;
  final VoidCallback? onStop;

  const TerminalPanel({
    super.key,
    required this.output,
    required this.onClear,
    required this.onClose,
    this.onStop,
  });

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(TerminalPanel old) {
    super.didUpdateWidget(old);
    if (old.output.length != widget.output.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        border: Border(
          top: BorderSide(color: AppColors.darkBorder),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 32,
            color: AppColors.darkSurface,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 14, color: AppColors.darkSubtext),
                const SizedBox(width: 6),
                Text('TERMINAL', style: TextStyle(
                  fontSize: 10, letterSpacing: 1.2,
                  color: AppColors.darkSubtext,
                )),
                const Spacer(),
                if (widget.onStop != null)
                  _TermBtn(
                    icon: Icons.stop_rounded,
                    color: AppColors.error,
                    tooltip: 'Arreter',
                    onTap: widget.onStop!,
                  ),
                _TermBtn(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Effacer',
                  onTap: widget.onClear,
                ),
                _TermBtn(
                  icon: Icons.close_rounded,
                  tooltip: 'Fermer',
                  onTap: widget.onClose,
                ),
              ],
            ),
          ),
          // Sortie
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: widget.output.length,
              itemBuilder: (_, i) {
                final line = widget.output[i];
                // Colorisation simple des erreurs
                final isError = line.contains('\u001b[31m') || line.toLowerCase().contains('error');
                final clean = line.replaceAll(RegExp(r'\u001b\[[0-9;]*m'), '');
                return Text(
                  clean,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: isError ? AppColors.error : const Color(0xFFB0C4DE),
                    height: 1.5,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TermBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _TermBtn({required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext ctx) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(icon, size: 14, color: color ?? AppColors.darkSubtext),
        ),
      ),
    );
  }
}
