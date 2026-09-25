/// @file ssh_host_key_dialog.dart
/// @brief Vérification de la clé d'hôte SSH avec l'utilisateur (TOFU).

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../services/ssh_known_hosts.dart';

/// Décide si la connexion à [host]:[port] peut continuer avec la clé
/// [type] d'empreinte [fingerprint] :
/// - clé connue et identique : oui ;
/// - premier contact : l'utilisateur voit l'empreinte et décide ; acceptée,
///   elle est mémorisée ;
/// - clé différente de celle mémorisée : non, avec un avertissement.
Future<bool> verifyHostKey(
  BuildContext context,
  SshKnownHosts knownHosts, {
  required String host,
  required int port,
  required String type,
  required Uint8List fingerprint,
}) async {
  final printed = SshKnownHosts.formatFingerprint(fingerprint);
  switch (knownHosts.check(host, port, type, fingerprint)) {
    case HostKeyStatus.trusted:
      return true;

    case HostKeyStatus.unknown:
      if (!context.mounted) return false;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          title: const Text('Serveur inconnu'),
          content: SelectableText('Première connexion à $host:$port.\n\n'
              'Clé $type\n$printed\n\n'
              'Vérifiez que cette empreinte est bien celle du serveur (sur le '
              'serveur : ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub) avant de '
              'lui faire confiance.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Refuser')),
            FilledButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('Faire confiance')),
          ],
        ),
      );
      if (accepted != true) return false;
      await knownHosts.trust(host, port, type, fingerprint);
      return true;

    case HostKeyStatus.changed:
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dCtx) => AlertDialog(
            icon: const Icon(Icons.gpp_bad_rounded, color: AppColors.error),
            title: const Text('Clé du serveur modifiée'),
            content: SelectableText(
                'La clé de $host:$port ne correspond pas à celle acceptée '
                'précédemment. Il peut s\'agir d\'une interception de la '
                'connexion : elle est refusée.\n\n'
                'Attendue : ${knownHosts.knownKey(host, port)}\n'
                'Reçue : $type $printed\n\n'
                'Si le serveur a été réinstallé, oubliez l\'ancienne clé dans '
                'Paramètres → VM Debian — SSH.'),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Fermer')),
            ],
          ),
        );
      }
      return false;
  }
}
