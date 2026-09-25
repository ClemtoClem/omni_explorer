import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/features/text_editor/services/ssh_known_hosts.dart';
import 'package:omni_explorer/features/text_editor/widgets/ssh_host_key_dialog.dart';

Uint8List fp(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + seed) % 256));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SshKnownHosts> hosts([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    return SshKnownHosts(await SharedPreferences.getInstance());
  }

  group('SshKnownHosts', () {
    test('empreinte au format OpenSSH (SHA256:, base64 sans « = »)', () {
      final printed = SshKnownHosts.formatFingerprint(fp(1));
      expect(printed, startsWith('SHA256:'));
      expect(printed, isNot(contains('=')));
      expect(printed.length, 'SHA256:'.length + 43); // 32 octets en base64
    });

    test('inconnu, puis accepté, puis reconnu', () async {
      final h = await hosts();
      expect(h.check('vm', 22, 'ssh-ed25519', fp(1)), HostKeyStatus.unknown);

      await h.trust('vm', 22, 'ssh-ed25519', fp(1));

      expect(h.check('vm', 22, 'ssh-ed25519', fp(1)), HostKeyStatus.trusted);
    });

    test('empreinte ou type différent : clé changée', () async {
      final h = await hosts();
      await h.trust('vm', 22, 'ssh-ed25519', fp(1));

      expect(h.check('vm', 22, 'ssh-ed25519', fp(2)), HostKeyStatus.changed);
      expect(h.check('vm', 22, 'ssh-rsa', fp(1)), HostKeyStatus.changed);
    });

    test('une clé par hôte et par port ; casse de l\'hôte ignorée', () async {
      final h = await hosts();
      await h.trust('VM.local', 22, 'ssh-ed25519', fp(1));

      expect(
          h.check('vm.local', 22, 'ssh-ed25519', fp(1)), HostKeyStatus.trusted);
      expect(h.check('vm.local', 2222, 'ssh-ed25519', fp(1)),
          HostKeyStatus.unknown);
    });

    test('oublier une clé', () async {
      final h = await hosts();
      await h.trust('vm', 22, 'ssh-ed25519', fp(1));
      await h.forget('vm', 22);
      expect(h.check('vm', 22, 'ssh-ed25519', fp(2)), HostKeyStatus.unknown);
    });

    test('données illisibles : aucune clé n\'est reconnue à tort', () async {
      for (final raw in ['{pas du json', '[1, 2]', '{"vm:22": 3}']) {
        final h = await hosts({AppConstants.prefSshKnownHosts: raw});
        expect(h.check('vm', 22, 'ssh-ed25519', fp(1)), HostKeyStatus.unknown,
            reason: raw);
      }
    });
  });

  group('verifyHostKey', () {
    late SshKnownHosts h;
    Future<bool>? result;

    Future<void> start(WidgetTester tester, Uint8List key) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => result = verifyHostKey(ctx, h,
                host: 'vm', port: 22, type: 'ssh-ed25519', fingerprint: key),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    setUp(() async => h = await hosts());

    testWidgets('premier contact accepté : clé mémorisée', (tester) async {
      await start(tester, fp(1));
      expect(find.text('Serveur inconnu'), findsOneWidget);
      expect(find.textContaining(SshKnownHosts.formatFingerprint(fp(1))),
          findsOneWidget);

      await tester.tap(find.text('Faire confiance'));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      expect(h.check('vm', 22, 'ssh-ed25519', fp(1)), HostKeyStatus.trusted);
    });

    testWidgets('premier contact refusé : rien n\'est mémorisé',
        (tester) async {
      await start(tester, fp(1));
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(h.check('vm', 22, 'ssh-ed25519', fp(1)), HostKeyStatus.unknown);
    });

    testWidgets('clé connue : aucune question', (tester) async {
      await h.trust('vm', 22, 'ssh-ed25519', fp(1));
      await start(tester, fp(1));

      expect(find.byType(AlertDialog), findsNothing);
      expect(await result, isTrue);
    });

    testWidgets('clé changée : refus, avec avertissement', (tester) async {
      await h.trust('vm', 22, 'ssh-ed25519', fp(1));
      await start(tester, fp(2));

      expect(find.text('Clé du serveur modifiée'), findsOneWidget);
      // Aucun bouton ne permet d'accepter la nouvelle clé ici.
      expect(find.text('Faire confiance'), findsNothing);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(h.check('vm', 22, 'ssh-ed25519', fp(2)), HostKeyStatus.changed);
    });
  });
}
