import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import 'package:omni_explorer/features/password_vault/models/vault_entry.dart';
import 'package:omni_explorer/features/password_vault/models/vault_errors.dart';
import 'package:omni_explorer/features/password_vault/providers/vault_session.dart';
import 'package:omni_explorer/features/password_vault/services/secure_clipboard.dart';
import 'package:omni_explorer/features/password_vault/services/vault_crypto.dart';
import 'package:omni_explorer/features/password_vault/services/vault_merge.dart';
import 'package:omni_explorer/features/password_vault/services/vault_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SodiumSumo sodium;
  late Directory sandbox;

  setUpAll(() async => sodium = await SodiumSumoInit.init());
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('vault_export_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() => sandbox.delete(recursive: true));

  VaultRepository repo(String name) => VaultRepository(
      VaultCrypto(sodium,
          opsLimit: sodium.crypto.pwhash.opsLimitMin,
          memLimit: sodium.crypto.pwhash.memLimitMin),
      p.join(sandbox.path, name));

  final now = DateTime.utc(2026);
  VaultEntry entry(String id, String title, {String password = 'pw'}) =>
      VaultEntry(
          id: id,
          title: title,
          fields: {'password': password},
          createdAt: now,
          updatedAt: now);

  Future<UnlockedVault> vaultWith(
      VaultRepository r, String pw, List<VaultEntry> entries) async {
    final v = await r.create(pw);
    await r.save(v, VaultContent(entries));
    return v;
  }

  group('paquet d\'export', () {
    test('exige le mot de passe maître', () async {
      final r = repo('a');
      final v = await vaultWith(r, 'mot de passe A', [entry('1', 'Banque')]);
      await expectLater(r.exportPackage(v, 'mauvais mot de passe'),
          throwsA(isA<WrongPasswordException>()));
      v.dispose();
    });

    test('aller-retour, signature d\'export, aucune donnée en clair', () async {
      final r = repo('a');
      final v = await vaultWith(
          r, 'mot de passe A', [entry('1', 'Banque', password: 'S3cr3t')]);
      final bytes = await r.exportPackage(v, 'mot de passe A');
      v.dispose();

      expect(VaultCrypto.hasMagic(bytes, VaultCrypto.exportMagic), isTrue);
      expect(latin1.decode(bytes).contains('S3cr3t'), isFalse);
      expect(latin1.decode(bytes).contains('Banque'), isFalse);
      final content = await r.readExportPackage(bytes, 'mot de passe A');
      expect(content.entries.single.password, 'S3cr3t');
    });

    test('s\'importe dans un autre coffre, avec le mot de passe d\'origine',
        () async {
      final a = repo('a');
      final va = await vaultWith(a, 'mot de passe A', [entry('1', 'Banque')]);
      final bytes = await a.exportPackage(va, 'mot de passe A');
      va.dispose();

      final b = repo('b');
      final vb = await b.create('mot de passe B');
      await expectLater(b.readExportPackage(bytes, 'mot de passe B'),
          throwsA(isA<WrongPasswordException>()));
      final content = await b.readExportPackage(bytes, 'mot de passe A');
      expect(content.entries.single.title, 'Banque');
      vb.dispose();
    });

    test(
        'après un changement de mot de passe : nouvel export, nouveau mot '
        'de passe ; l\'ancien export garde l\'ancien', () async {
      final r = repo('a');
      final v = await vaultWith(r, 'ancien mot de passe', [entry('1', 'X')]);
      final oldExport = await r.exportPackage(v, 'ancien mot de passe');
      await r.changePassword(v, 'ancien mot de passe', 'nouveau mot de passe');
      final newExport = await r.exportPackage(v, 'nouveau mot de passe');
      v.dispose();

      await r.readExportPackage(oldExport, 'ancien mot de passe');
      await r.readExportPackage(newExport, 'nouveau mot de passe');
      await expectLater(r.readExportPackage(newExport, 'ancien mot de passe'),
          throwsA(isA<WrongPasswordException>()));
    });

    test('le fichier du coffre n\'est pas un export', () async {
      final r = repo('a');
      (await vaultWith(r, 'mot de passe A', [])).dispose();
      final vaultFile =
          File(p.join(sandbox.path, 'a', VaultRepository.fileName))
              .readAsBytesSync();
      await expectLater(r.readExportPackage(vaultFile, 'mot de passe A'),
          throwsA(isA<NotAnExportException>()));
      await expectLater(
          r.readExportPackage(
              Uint8List.fromList(utf8.encode('bonjour')), 'mot de passe A'),
          throwsA(isA<NotAnExportException>()));
    });

    test('export modifié : détecté', () async {
      final r = repo('a');
      final v = await vaultWith(r, 'mot de passe A', [entry('1', 'X')]);
      final bytes = await r.exportPackage(v, 'mot de passe A');
      v.dispose();
      bytes[bytes.length - 2] ^= 0x01;
      await expectLater(r.readExportPackage(bytes, 'mot de passe A'),
          throwsA(isA<VaultCorruptedException>()));
    });

    test('fichier trop volumineux refusé avant lecture', () async {
      final big = Uint8List(VaultRepository.maxExportBytes + 1);
      await expectLater(repo('a').readExportPackage(big, 'x'),
          throwsA(isA<ExportTooLargeException>()));
    });
  });

  group('session', () {
    VaultSession session(String name) => VaultSession(
          repositoryFactory: () async => repo(name),
          clipboard: SecureClipboard(useNative: false),
        );

    test('prévisualiser ne modifie rien ; appliquer enregistre', () async {
      final source = session('src');
      await source.ensureInitialized();
      await source.create('mot de passe A');
      await source.addEntry(title: 'Banque', fields: {'password': 'x'});
      await source.addEntry(title: 'Mail', fields: {'password': 'y'});
      final bytes = await source.exportPackage('mot de passe A');
      source.dispose();

      final target = session('dst');
      await target.ensureInitialized();
      await target.create('mot de passe B');
      await target.addEntry(title: 'Mail', fields: {'password': 'autre'});

      final plan = await target.previewImport(bytes, 'mot de passe A');
      expect(plan.added.single.title, 'Banque');
      expect(plan.conflicts.single.existing.title, 'Mail');
      expect(target.entries.length, 1); // rien d'appliqué

      await target.applyImport(plan, ImportConflictChoice.keepBoth);
      target.lock();
      await target.unlock('mot de passe B');
      expect(target.entries.map((e) => e.title).toSet(),
          {'Mail', 'Banque', 'Mail${VaultMerge.keptBothSuffix}'});
      target.dispose();
    });
  });
}
