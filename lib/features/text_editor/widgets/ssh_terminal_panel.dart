// @file ssh_terminal_panel.dart
// @brief Terminal SSH interactif connecté à la VM Debian (Android AVF).
//
// Utilise dartssh2 pour la connexion et xterm pour le rendu du terminal.
// Se connecte automatiquement à localhost:2222 (port par défaut de la VM Debian AVF).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/app_theme.dart';
import 'terminal_keys_bar.dart';

// ── Thème terminal (Catppuccin Mocha) ─────────────────────────────────────────

const _kTermTheme = TerminalTheme(
  cursor:                    Color(0xFF89B4FA),
  selection:                 Color(0x6089B4FA),
  foreground:                Color(0xFFCDD6F4),
  background:                Color(0xFF0D1117),
  black:                     Color(0xFF1E1E2E),
  red:                       Color(0xFFF38BA8),
  green:                     Color(0xFFA6E3A1),
  yellow:                    Color(0xFFF9E2AF),
  blue:                      Color(0xFF89B4FA),
  magenta:                   Color(0xFFCBA6F7),
  cyan:                      Color(0xFF89DCEB),
  white:                     Color(0xFFBAC2DE),
  brightBlack:               Color(0xFF585B70),
  brightRed:                 Color(0xFFF38BA8),
  brightGreen:               Color(0xFFA6E3A1),
  brightYellow:              Color(0xFFF9E2AF),
  brightBlue:                Color(0xFF89B4FA),
  brightMagenta:             Color(0xFFCBA6F7),
  brightCyan:                Color(0xFF89DCEB),
  brightWhite:               Color(0xFFA6ADC8),
  searchHitBackground:        Color(0x80F9E2AF),
  searchHitBackgroundCurrent: Color(0xC0F9E2AF),
  searchHitForeground:        Color(0xFF1E1E2E),
);

// ── États de connexion ────────────────────────────────────────────────────────

enum _ConnState { idle, connecting, connected, error }

// ─────────────────────────────────────────────────────────────────────────────

/// Terminal SSH interactif connecté à la VM Debian via localhost.
class SshTerminalPanel extends StatefulWidget {
  final String       host;
  final int          port;
  final String       username;
  final String       password;
  /// Répertoire partagé Android↔Debian (ex: /mnt/shared).
  final String       initialDir;
  final VoidCallback onClose;

  const SshTerminalPanel({
    super.key,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.initialDir,
    required this.onClose,
  });

  @override
  State<SshTerminalPanel> createState() => _SshTerminalPanelState();
}

class _SshTerminalPanelState extends State<SshTerminalPanel> {
  final _terminal = Terminal(maxLines: 10000);
  SSHClient? _client;
  SSHSession? _shell;
  _ConnState  _state    = _ConnState.idle;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _shell?.close();
    _client?.close();
    super.dispose();
  }

  // ── Connexion SSH ─────────────────────────────────────────────────────────

  Future<void> _connect() async {
    if (!mounted) return;
    setState(() => _state = _ConnState.connecting);
    _terminal.write('\r\n\x1b[33mConnexion à ${widget.host}:${widget.port}...\x1b[0m\r\n');

    try {
      final socket = await SSHSocket.connect(
        widget.host, widget.port,
        timeout: const Duration(seconds: 8),
      );

      _client = SSHClient(
        socket,
        username: widget.username,
        onPasswordRequest: () => widget.password,
      );

      _shell = await _client!.shell(
        pty: const SSHPtyConfig(
          type: 'xterm-256color',
          width:  80,
          height: 24,
        ),
      );

      // stdout/stderr → terminal
      _stdoutSub = _shell!.stdout.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      _stderrSub = _shell!.stderr.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Saisie terminal → stdin SSH
      _terminal.onOutput = (data) {
        _shell?.stdin.add(utf8.encode(data));
      };

      // Resize PTY lors du redimensionnement du widget
      _terminal.onResize = (w, h, pw, ph) {
        _shell?.resizeTerminal(w, h, pw, ph);
      };

      // Naviguer vers le dossier partagé au démarrage
      if (widget.initialDir.isNotEmpty) {
        _shell!.stdin.add(utf8.encode('cd "${widget.initialDir}"\n'));
      }

      if (mounted) setState(() => _state = _ConnState.connected);

      // Fin de session
      _shell!.done.then((_) {
        if (mounted) {
          _terminal.write('\r\n\x1b[33m[Session terminée]\x1b[0m\r\n');
          setState(() => _state = _ConnState.idle);
        }
      });
    } catch (e) {
      _handleError(e);
    }
  }

  void _handleError(Object e) {
    String msg;
    if (e.toString().contains('Connection refused') ||
        e.toString().contains('ECONNREFUSED')) {
      msg = 'Connexion refusée.\n'
          'Vérifiez que la VM Debian est démarrée\n'
          'et que le serveur SSH est actif (port ${widget.port}).';
    } else if (e.toString().contains('timeout') ||
               e.toString().contains('timed out')) {
      msg = 'Délai de connexion dépassé.\n'
          'La VM Debian ne répond pas sur localhost:${widget.port}.';
    } else if (e.toString().toLowerCase().contains('auth')) {
      msg = 'Authentification échouée.\n'
          'Vérifiez le nom d\'utilisateur et le mot de passe.';
    } else {
      msg = e.toString();
    }
    _terminal.write('\r\n\x1b[31m❌ $msg\x1b[0m\r\n');
    _terminal.write('\r\n\x1b[90mAppuyez sur ↺ pour reconnecter.\x1b[0m\r\n');
    if (mounted) setState(() => _state = _ConnState.error);
  }

  Future<void> _reconnect() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _shell?.close();
    _client?.close();
    _shell  = null;
    _client = null;
    _terminal.write('\r\n');
    await _connect();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _state == _ConnState.connecting
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : TerminalView(
                    _terminal,
                    autofocus: true,
                    theme: _kTermTheme,
                    textStyle: const TerminalStyle(fontSize: 12),
                  ),
          ),
          if (_state == _ConnState.connected)
            TerminalKeysBar(terminal: _terminal),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      color: AppColors.darkSurface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded, size: 14, color: Color(0xFF89B4FA)),
          const SizedBox(width: 6),
          const Text(
            'DEBIAN VM',
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Color(0xFF89B4FA)),
          ),
          const SizedBox(width: 8),
          _StatusDot(state: _state),
          const Spacer(),
          _TermBtn(
            icon: Icons.refresh_rounded,
            tooltip: 'Reconnecter',
            onTap: _state != _ConnState.connecting ? _reconnect : null,
          ),
          _TermBtn(icon: Icons.close_rounded, tooltip: 'Fermer', onTap: widget.onClose),
        ],
      ),
    );
  }
}

// ── Widgets internes ──────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final _ConnState state;
  const _StatusDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _ConnState.connected  => Colors.green,
      _ConnState.connecting => Colors.orange,
      _ConnState.error      => AppColors.error,
      _ConnState.idle       => Colors.grey,
    };
    return Container(
      width: 7, height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TermBtn extends StatelessWidget {
  final IconData     icon;
  final String       tooltip;
  final VoidCallback? onTap;

  const _TermBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(
            icon, size: 14,
            color: onTap != null ? AppColors.darkSubtext : AppColors.darkSubtext.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
