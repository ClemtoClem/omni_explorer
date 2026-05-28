/// @file terminal_keys_bar.dart
/// @brief Rangée de touches spéciales pour le terminal (inspiré de Xed-Editor).
///
/// Fournit les touches absentes du clavier logiciel mais indispensables en
/// ligne de commande : Échap, Tab, flèches, Début/Fin, Page préc./suiv., les
/// raccourcis Ctrl courants (^C, ^D, ^Z, ^L) et quelques symboles fréquents.
/// Tout passe par l'API d'entrée du [Terminal] xterm (donc via onOutput → SSH).

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../../../app/theme/app_theme.dart';

class TerminalKeysBar extends StatelessWidget {
  final Terminal terminal;
  const TerminalKeysBar({super.key, required this.terminal});

  List<_VKey> get _keys => [
        _VKey('ESC', (t) => t.keyInput(TerminalKey.escape)),
        _VKey('TAB', (t) => t.keyInput(TerminalKey.tab)),
        _VKey('^C', (t) => t.charInput(0x63, ctrl: true)),
        _VKey('^D', (t) => t.charInput(0x64, ctrl: true)),
        _VKey('^Z', (t) => t.charInput(0x7a, ctrl: true)),
        _VKey('^L', (t) => t.charInput(0x6c, ctrl: true)),
        _VKey('←', (t) => t.keyInput(TerminalKey.arrowLeft)),
        _VKey('↑', (t) => t.keyInput(TerminalKey.arrowUp)),
        _VKey('↓', (t) => t.keyInput(TerminalKey.arrowDown)),
        _VKey('→', (t) => t.keyInput(TerminalKey.arrowRight)),
        _VKey('⇤', (t) => t.keyInput(TerminalKey.home)),
        _VKey('⇥', (t) => t.keyInput(TerminalKey.end)),
        _VKey('Pg↑', (t) => t.keyInput(TerminalKey.pageUp)),
        _VKey('Pg↓', (t) => t.keyInput(TerminalKey.pageDown)),
        _VKey('-', (t) => t.textInput('-')),
        _VKey('/', (t) => t.textInput('/')),
        _VKey('|', (t) => t.textInput('|')),
        _VKey('~', (t) => t.textInput('~')),
        _VKey('*', (t) => t.textInput('*')),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: AppColors.darkSurface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: _keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final key = _keys[i];
          return _KeyButton(label: key.label, onTap: () => key.action(terminal));
        },
      ),
    );
  }
}

class _VKey {
  final String label;
  final void Function(Terminal t) action;
  const _VKey(this.label, this.action);
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _KeyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1E2E),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 38),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFCDD6F4),
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
