import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import 'package:omni_explorer/features/password_vault/models/vault_errors.dart';
import 'package:omni_explorer/features/password_vault/providers/vault_session.dart';
import 'package:omni_explorer/features/password_vault/services/secure_clipboard.dart';
import 'package:omni_explorer/features/password_vault/services/vault_crypto.dart';
import 'package:omni_explorer/features/password_vault/services/vault_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SodiumSumo sodium;
  late Directory sandbox;
  String? clipboard;
  const pw = 'mot de passe maître';

  setUpAll(() async => sodium = await SodiumSumoInit.init());

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('vault_session_test_');
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      } else if (call.method == 'Clipboard.getData') {
        return clipboard == null ? null : {'text': clipboard};
      }
      return null;
    });
  });

  tearDown(() => sandbox.delete(recursive: true));

  VaultSession session({
    Duration inactivity = const Duration(minutes: 5),
    Duration background = const Duration(seconds: 60),
  }) =>
      VaultSession(
        repositoryFactory: () async => VaultRepository(
            VaultCrypto(sodium,
                opsLimit: sodium.crypto.pwhash.opsLimitMin,
                memLimit: sodium.crypto.pwhash.memLimitMin),
            p.join(sandbox.path, 'vault')),
        clipboard: SecureClipboard(useNative: false),
        inactivityTimeout: inactivity,
        backgroundTimeout: background,
      );

  test('cycle complet : création, entrées, verrouillage, réouverture',
      () async {
    final s = session();
    await s.ensureInitialized();
    expect(s.status, VaultStatus.absent);

    await s.create(pw);
    expect(s.status, VaultStatus.unlocked);
    final e = await s.addEntry(
        title: 'Banque', fields: {'username': 'moi', 'password': 'x1'});
    await s.addEntry(title: 'Mail');
    await s.updateEntry(e.copyWith(fields: {...e.fields, 'password': 'x2'}));
    await s.deleteEntry(s.entries.singleWhere((x) => x.title == 'Mail').id);

    s.lock();
    expect(s.status, VaultStatus.locked);
    expect(s.entries, isEmpty); // rien ne reste accessible

    await expectLater(
        s.unlock('mauvais'), throwsA(isA<WrongPasswordException>()));
    await s.unlock(pw);
    expect(s.entries.single.password, 'x2');
    s.dispose();
  });

  test('verrouillage après inactivité', () async {
    final s = session(inactivity: const Duration(milliseconds: 100));
    await s.ensureInitialized();
    await s.create(pw);

    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(s.status, VaultStatus.locked);
    s.dispose();
  });

  test('une interaction repousse le verrouillage', () async {
    final s = session(inactivity: const Duration(milliseconds: 200));
    await s.ensureInitialized();
    await s.create(pw);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      s.touch();
    }
    expect(s.status, VaultStatus.unlocked);
    s.dispose();
  });

  test('arrière-plan : verrouillage après le délai, sauf retour avant',
      () async {
    final s = session(background: const Duration(milliseconds: 150));
    await s.ensureInitialized();
    await s.create(pw);

    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(s.status, VaultStatus.unlocked);

    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(s.status, VaultStatus.locked);
    s.dispose();
  });

  test('le verrouillage vide le presse-papiers', () async {
    final s = session();
    await s.ensureInitialized();
    await s.create(pw);
    await s.clipboard.copy('secret');
    expect(clipboard, 'secret');

    s.lock();
    await Future<void>.delayed(Duration.zero);

    expect(clipboard, '');
    s.dispose();
  });

  test('échec de sauvegarde : les entrées restent inchangées', () async {
    final s = session();
    await s.ensureInitialized();
    await s.create(pw);
    await s.addEntry(title: 'A');
    final dir = p.join(sandbox.path, 'vault');
    await Process.run('chmod', ['-R', 'a-w', dir]);

    await expectLater(
        s.addEntry(title: 'B'), throwsA(isA<FileSystemException>()));

    await Process.run('chmod', ['-R', 'u+w', dir]);
    expect(s.entries.map((e) => e.title), ['A']);
    expect(s.busy, isFalse);
    s.dispose();
  },
      skip: Platform.isWindows
          ? 'chmod indisponible'
          : (Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
              ? 'root ignore les permissions'
              : null));
}
