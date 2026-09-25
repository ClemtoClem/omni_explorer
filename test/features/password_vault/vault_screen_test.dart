/// Parcours complet du coffre-fort dans l'interface.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:omni_explorer/features/password_vault/providers/vault_session.dart';
import 'package:omni_explorer/features/password_vault/screens/password_vault_home_screen.dart';
import 'package:omni_explorer/features/password_vault/services/secure_clipboard.dart';
import 'package:omni_explorer/features/password_vault/services/vault_crypto.dart';
import 'package:omni_explorer/features/password_vault/services/vault_repository.dart';

import '../../helpers/editor_harness.dart' show settleIo;

void main() {
  late SodiumSumo sodium;
  late Directory sandbox;
  late VaultSession session;

  setUpAll(() async => sodium = await SodiumSumoInit.init());

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('vault_screen_test_');
    session = VaultSession(
      repositoryFactory: () async => VaultRepository(
          VaultCrypto(sodium,
              opsLimit: sodium.crypto.pwhash.opsLimitMin,
              memLimit: sodium.crypto.pwhash.memLimitMin,
              // Pas d'isolate depuis l'horloge fictive des tests de widget.
              useIsolate: false),
          p.join(sandbox.path, 'vault')),
      clipboard: SecureClipboard(useNative: false),
    );
  });

  tearDown(() async {
    session.dispose();
    await sandbox.delete(recursive: true);
  });

  Future<void> pumpVault(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: session,
      child: const MaterialApp(home: PasswordVaultHomeScreen()),
    ));
    await settleIo(tester, until: () => session.status != VaultStatus.loading);
  }

  testWidgets('créer, ajouter, verrouiller, rouvrir', (tester) async {
    await pumpVault(tester);
    expect(find.text('Créer le coffre-fort'), findsOneWidget);

    // Mots de passe différents : refusé.
    await tester.enterText(
        find.byKey(const Key('create-password')), 'mot de passe maître');
    await tester.enterText(
        find.byKey(const Key('create-confirm')), 'autre chose 123');
    await tester.tap(find.text('Créer'));
    await tester.pump();
    expect(find.text('Les deux mots de passe diffèrent.'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('create-confirm')), 'mot de passe maître');
    await tester.tap(find.text('Créer'));
    await settleIo(tester, until: () => session.status == VaultStatus.unlocked);
    expect(find.textContaining('Aucune entrée'), findsOneWidget);

    // Ajout d'une entrée.
    await tester.tap(find.byTooltip('Ajouter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-title')), 'Banque');
    await tester.enterText(find.byKey(const Key('entry-username')), 'clement');
    await tester.enterText(find.byKey(const Key('entry-password')), 'S3cr3t!');
    await tester.tap(find.byTooltip('Enregistrer'));
    await settleIo(tester, until: () => session.entries.isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Banque'), findsOneWidget);
    expect(find.text('clement'), findsOneWidget);
    expect(find.text('S3cr3t!'), findsNothing); // jamais affiché dans la liste

    // Verrouillage : plus rien de visible.
    await tester.tap(find.byTooltip('Verrouiller'));
    await tester.pumpAndSettle();
    expect(find.text('Coffre verrouillé'), findsOneWidget);
    expect(find.text('Banque'), findsNothing);

    // Mauvais mot de passe, puis le bon.
    await tester.enterText(
        find.byKey(const Key('unlock-password')), 'erreur de saisie');
    await tester.tap(find.text('Déverrouiller'));
    await settleIo(tester,
        until: () =>
            find.text('Mot de passe incorrect.').evaluate().isNotEmpty);
    expect(find.text('Mot de passe incorrect.'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('unlock-password')), 'mot de passe maître');
    await tester.tap(find.text('Déverrouiller'));
    await settleIo(tester, until: () => session.status == VaultStatus.unlocked);
    await tester.pumpAndSettle();
    expect(find.text('Banque'), findsOneWidget);

    // Verrouiller annule le minuteur d'inactivité (vérifié en fin de test).
    session.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('recherche', (tester) async {
    await pumpVault(tester);
    await tester.runAsync(() async {
      await session.create('mot de passe maître');
      await session.addEntry(title: 'Banque', username: 'moi');
      await session.addEntry(title: 'Courriel', url: 'mail.example');
    });
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'mail');
    await tester.pumpAndSettle();

    expect(find.text('Courriel'), findsOneWidget);
    expect(find.text('Banque'), findsNothing);
    session.lock();
    await tester.pumpAndSettle();
  });
}
