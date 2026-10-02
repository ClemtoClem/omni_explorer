import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import 'package:omni_explorer/features/password_vault/models/vault_entry.dart';
import 'package:omni_explorer/features/password_vault/models/vault_errors.dart';
import 'package:omni_explorer/features/password_vault/services/vault_crypto.dart';
import 'package:omni_explorer/features/password_vault/services/vault_repository.dart';

void main() {
  late SodiumSumo sodium;
  late Directory sandbox;
  late VaultRepository repo;
  const pw = 'mot de passe maître';

  final noChmod = Platform.isWindows
      ? 'chmod indisponible'
      : (Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'root ignore les permissions'
          : null);

  setUpAll(() async => sodium = await SodiumSumoInit.init());

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('vault_repo_test_');
    repo = VaultRepository(
        VaultCrypto(sodium,
            opsLimit: sodium.crypto.pwhash.opsLimitMin,
            memLimit: sodium.crypto.pwhash.memLimitMin),
        p.join(sandbox.path, 'vault'));
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+rwx', sandbox.path]);
    await sandbox.delete(recursive: true);
  });

  File mainFile() =>
      File(p.join(sandbox.path, 'vault', VaultRepository.fileName));
  File backupFile() =>
      File(p.join(sandbox.path, 'vault', '${VaultRepository.fileName}.bak'));

  VaultContent withTitles(List<String> titles) {
    final now = DateTime.utc(2026);
    return VaultContent([
      for (final t in titles)
        VaultEntry(
            id: t,
            title: t,
            fields: {'password': 'pw-$t'},
            createdAt: now,
            updatedAt: now),
    ]);
  }

  List<String> titles(UnlockedVault v) =>
      v.content.entries.map((e) => e.title).toList();

  test('création puis ouverture', () async {
    final created = await repo.create(pw);
    expect(repo.exists, isTrue);
    created.dispose();

    final opened = await repo.unlock(pw);
    expect(opened.content.entries, isEmpty);
    opened.dispose();
  });

  test('mot de passe trop court refusé, rien n\'est créé', () async {
    await expectLater(
        repo.create('court'), throwsA(isA<WeakPasswordException>()));
    expect(repo.exists, isFalse);
  });

  test('ne recrée jamais par-dessus un coffre existant', () async {
    (await repo.create(pw)).dispose();
    final before = mainFile().readAsBytesSync();
    await expectLater(
        repo.create('autre mot de passe'), throwsA(isA<VaultException>()));
    expect(mainFile().readAsBytesSync(), before);
  });

  test('mauvais mot de passe', () async {
    (await repo.create(pw)).dispose();
    await expectLater(repo.unlock('pas le bon mot de passe'),
        throwsA(isA<WrongPasswordException>()));
  });

  test('sauvegarde : persistée, et version précédente dans .bak', () async {
    final v = await repo.create(pw);
    await repo.save(v, withTitles(['A']));
    await repo.save(v, withTitles(['A', 'B']));
    v.dispose();

    final main = await repo.unlock(pw);
    expect(titles(main), ['A', 'B']);
    main.dispose();
    final previous = await repo.unlock(pw, fromBackup: true);
    expect(titles(previous), ['A']);
    previous.dispose();
  });

  test('échec d\'écriture : fichier et contenu en mémoire intacts', () async {
    final v = await repo.create(pw);
    await repo.save(v, withTitles(['A']));
    final before = mainFile().readAsBytesSync();
    // Fichiers ET dossier en lecture seule : ni écriture atomique, ni repli
    // sur l'écriture directe.
    await Process.run('chmod', ['444', mainFile().path, backupFile().path]);
    await Process.run('chmod', ['555', p.dirname(mainFile().path)]);

    await expectLater(repo.save(v, withTitles(['A', 'B'])),
        throwsA(isA<FileSystemException>()));

    await Process.run('chmod', ['755', p.dirname(mainFile().path)]);
    await Process.run('chmod', ['644', mainFile().path, backupFile().path]);
    expect(titles(v), ['A']);
    expect(mainFile().readAsBytesSync(), before);
    v.dispose();
  }, skip: noChmod);

  test('fichier principal endommagé : la version précédente le remplace',
      () async {
    final v = await repo.create(pw);
    await repo.save(v, withTitles(['A']));
    await repo.save(v, withTitles(['A', 'B']));
    v.dispose();
    final bytes = mainFile().readAsBytesSync();
    bytes[bytes.length - 3] ^= 0xFF;
    mainFile().writeAsBytesSync(bytes);

    await expectLater(repo.unlock(pw), throwsA(isA<VaultCorruptedException>()));

    final fromBackup = await repo.unlock(pw, fromBackup: true);
    await repo.restoreFromBackup(fromBackup);
    fromBackup.dispose();
    final repaired = await repo.unlock(pw);
    expect(titles(repaired), ['A']);
    repaired.dispose();
  });

  test('changement de mot de passe maître', () async {
    final v = await repo.create(pw);
    await repo.save(v, withTitles(['A']));
    final saltBefore = repo.crypto.parse(mainFile().readAsBytesSync()).kdf.salt;

    await expectLater(repo.changePassword(v, 'pas le bon', 'nouveau mdp 123'),
        throwsA(isA<WrongPasswordException>()));
    await expectLater(repo.changePassword(v, pw, 'court'),
        throwsA(isA<WeakPasswordException>()));

    await repo.changePassword(v, pw, 'nouveau mdp 123');
    // Le coffre ouvert reste utilisable avec les nouvelles clés.
    await repo.save(v, withTitles(['A', 'B']));
    v.dispose();

    final after = repo.crypto.parse(mainFile().readAsBytesSync());
    expect(after.kdf.salt, isNot(equals(saltBefore)));
    await expectLater(repo.unlock(pw), throwsA(isA<WrongPasswordException>()));
    final reopened = await repo.unlock('nouveau mdp 123');
    expect(titles(reopened), ['A', 'B']);
    reopened.dispose();
  });

  test('coffre verrouillé : plus aucune écriture possible', () async {
    final v = await repo.create(pw);
    v.dispose();
    await expectLater(repo.save(v, withTitles(['A'])), throwsStateError);
  });

  test('verrouiller efface le contenu déchiffré du coffre ouvert', () async {
    final v = await repo.create(pw);
    await repo.save(v, withTitles(['A']));
    expect(v.content.entries, isNotEmpty);

    v.dispose();

    expect(v.isDisposed, isTrue);
    expect(v.content.entries, isEmpty);
  });

  test('suppression du coffre et de sa sauvegarde', () async {
    final v = await repo.create(pw);
    await repo.save(v, withTitles(['A']));
    v.dispose();
    expect(backupFile().existsSync(), isTrue);

    await repo.deleteVault();

    expect(mainFile().existsSync(), isFalse);
    expect(backupFile().existsSync(), isFalse);
  });

  test('Linux : dossier du coffre réservé à l\'utilisateur (700)', () async {
    (await repo.create(pw)).dispose();
    final mode = Directory(p.join(sandbox.path, 'vault')).statSync().mode;
    expect((mode & 0x1FF).toRadixString(8), '700');
  }, skip: Platform.isLinux ? null : 'Linux uniquement');
}
