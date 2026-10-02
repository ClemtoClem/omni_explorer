/// Parcours complet du coffre-fort dans l'interface.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:omni_explorer/features/password_vault/models/vault_entry.dart';

import 'package:omni_explorer/features/password_vault/providers/vault_session.dart';
import 'package:omni_explorer/features/password_vault/screens/password_vault_home_screen.dart';
import 'package:omni_explorer/features/password_vault/services/secure_clipboard.dart';
import 'package:omni_explorer/features/password_vault/services/vault_crypto.dart';
import 'package:omni_explorer/features/password_vault/services/vault_repository.dart';
import 'package:omni_explorer/features/password_vault/services/vault_sort.dart';

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

  /// Attend l'enregistrement ([saved]), puis la fermeture réelle du
  /// formulaire : tant que son animation de sortie n'est pas finie, ses
  /// champs (dont les secrets) sont encore à l'écran. settleIo n'avance pas
  /// l'horloge, d'où pumpAndSettle pour l'animation.
  Future<void> waitFormClosed(
      WidgetTester tester, bool Function() saved) async {
    await settleIo(tester, until: saved);
    final form = find.byKey(const Key('entry-title'));
    for (var i = 0; i < 20 && form.evaluate().isNotEmpty; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(form, findsNothing);
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
    await tester.tap(find.text('Site web'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-title')), 'Banque');
    await tester.enterText(find.byKey(const Key('field-username')), 'clement');
    await tester.enterText(find.byKey(const Key('field-password')), 'S3cr3t!');
    await tester.tap(find.byTooltip('Enregistrer'));
    // Attendre la fermeture réelle de l'écran d'édition, pas seulement
    // l'enregistrement : sinon son champ (qui contient le mot de passe) est
    // encore à l'écran.
    await waitFormClosed(tester, () => session.entries.isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Banque'), findsOneWidget);
    expect(find.text('Site web · clement'), findsOneWidget);
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
      await session.addEntry(title: 'Banque', fields: {'username': 'moi'});
      await session
          .addEntry(title: 'Courriel', fields: {'url': 'mail.example'});
    });
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'mail');
    await tester.pumpAndSettle();

    expect(find.text('Courriel'), findsOneWidget);
    expect(find.text('Banque'), findsNothing);
    session.lock();
    await tester.pumpAndSettle();
  });

  /// Défile la liste du formulaire jusqu'à [finder] (champs construits à la
  /// demande).
  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(finder, 150,
          scrollable: find.byType(Scrollable).first);

  testWidgets('ajouter une fiche bancaire avec tous ses champs',
      (tester) async {
    await pumpVault(tester);
    await tester.runAsync(() => session.create('mot de passe maître'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ajouter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banque'));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle entrée · Banque'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('entry-title')), 'Courant');
    const values = {
      'bankName': 'Banque X',
      'cardHolder': 'C. Dupont',
      'cardNumber': '4970123456789012',
      'cardExpiry': '09/29',
      'cardCvv': '123',
      'cardPin': '0000',
      'iban': 'FR7630006000011234567890189',
      'bic': 'AGRIFRPP',
      'rib': '30006 00001 12345678901 89',
      'onlineLogin': '12345678',
      'onlinePassword': '987654',
    };
    for (final e in values.entries) {
      final field = find.byKey(Key('field-${e.key}'));
      await scrollTo(tester, field);
      await tester.enterText(field, e.value);
    }
    // Les numéros sensibles sont masqués à la saisie.
    expect(find.text('4970123456789012'), findsNothing);

    await tester.tap(find.byTooltip('Enregistrer'));
    await waitFormClosed(tester, () => session.entries.isNotEmpty);
    await tester.pumpAndSettle();

    final saved = session.entries.single;
    expect(saved.category, VaultCategory.bank);
    expect(saved.fields, values);
    expect(find.text('Courant'), findsOneWidget);
    expect(find.text('Banque · Banque X'), findsOneWidget);
    session.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('trier par tag (croissant, décroissant) et par catégorie',
      (tester) async {
    await pumpVault(tester);
    await tester.runAsync(() async {
      await session.create('mot de passe maître');
      await session.addEntry(title: 'Compte', category: VaultCategory.bank);
      await session.addEntry(title: 'Agenda', category: VaultCategory.message);
      await session.addEntry(title: 'Zoo', category: VaultCategory.website);
      await session.addEntry(title: 'Courriel', category: VaultCategory.email);
    });
    await tester.pumpAndSettle();

    List<String> order() => [
          for (final t in ['Agenda', 'Compte', 'Courriel', 'Zoo'])
            if (find.text(t).evaluate().isNotEmpty) t
        ]..sort((a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy));

    expect(order(), ['Agenda', 'Compte', 'Courriel', 'Zoo']);

    Future<void> sortBy(String label) async {
      await tester.tap(find.byTooltip('Trier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await sortBy('Tag (Z → A)');
    expect(session.sortMode, VaultSortMode.tagDescending);
    expect(order(), ['Zoo', 'Courriel', 'Compte', 'Agenda']);

    await sortBy('Catégorie');
    // Banque, Message secret, Messagerie, Site web : en-têtes par catégorie.
    expect(order(), ['Compte', 'Agenda', 'Courriel', 'Zoo']);
    for (final h in ['BANQUE', 'MESSAGE SECRET', 'MESSAGERIE', 'SITE WEB']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }

    await sortBy('Tag (A → Z)');
    expect(find.text('SITE WEB'), findsNothing);
    expect(order(), ['Agenda', 'Compte', 'Courriel', 'Zoo']);
    session.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('changer de catégorie garde les valeurs des champs communs',
      (tester) async {
    await pumpVault(tester);
    await tester.runAsync(() async {
      await session.create('mot de passe maître');
      await session.addEntry(
          title: 'Box',
          fields: {'username': 'admin', 'password': 'p4ss', 'notes': 'n'});
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Box'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réseau Wi-Fi').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('field-ssid')), findsOneWidget);
    expect(find.byKey(const Key('field-username')), findsNothing);
    await tester.enterText(find.byKey(const Key('field-ssid')), 'maison');

    await tester.tap(find.byTooltip('Enregistrer'));
    await waitFormClosed(
        tester, () => session.entries.single.category == VaultCategory.wifi);
    // Les clés de la nouvelle catégorie seulement : l'identifiant d'un site
    // web n'a pas de sens pour un réseau Wi-Fi.
    expect(session.entries.single.fields,
        {'ssid': 'maison', 'password': 'p4ss', 'notes': 'n'});
    session.lock();
    await tester.pumpAndSettle();
  });

  test('le tri choisi est retrouvé à la session suivante', () async {
    SharedPreferences.setMockInitialValues({});
    await session.ensureInitialized();
    session.setSortMode(VaultSortMode.category);
    await Future<void>.delayed(Duration.zero);

    final next = VaultSession(
      repositoryFactory: () async => VaultRepository(
          VaultCrypto(sodium,
              opsLimit: sodium.crypto.pwhash.opsLimitMin,
              memLimit: sodium.crypto.pwhash.memLimitMin,
              useIsolate: false),
          p.join(sandbox.path, 'vault')),
      clipboard: SecureClipboard(useNative: false),
    );
    await next.ensureInitialized();
    await Future<void>.delayed(Duration.zero);
    expect(next.sortMode, VaultSortMode.category);
    next.dispose();
  });
}
