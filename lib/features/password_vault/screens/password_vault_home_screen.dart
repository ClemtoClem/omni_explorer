/// @file password_vault_home_screen.dart
/// @brief Placeholder du coffre-fort de mots de passe.
///
/// L'implémentation complète (mot de passe maître + dérivation Argon2, base
/// chiffrée, déverrouillage biométrique via local_auth, FLAG_SECURE / blocage
/// captures) viendra dans une passe dédiée.

import 'package:flutter/material.dart';

class PasswordVaultHomeScreen extends StatelessWidget {
  const PasswordVaultHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coffre-fort')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Coffre-fort sécurisé',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Mots de passe chiffrés localement (Argon2 + AES-GCM), '
                'déverrouillage biométrique, blocage des captures d\'écran. '
                'Cette fonctionnalité est en cours de développement '
                '(passe suivante).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
