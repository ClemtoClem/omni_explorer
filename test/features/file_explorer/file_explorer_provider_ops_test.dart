import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/core/services/file_operations_service.dart';
import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/features/file_explorer/providers/file_explorer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late String a, b;
  late FileExplorerProvider prov;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Pas de trousseau système en test : stockage sécurisé simulé.
    FlutterSecureStorage.setMockInitialValues({});
    sandbox = await Directory.systemTemp.createTemp('explorer_ops_test_');
    a = p.join(sandbox.path, 'a');
    b = p.join(sandbox.path, 'b');
    await Directory(a).create();
    await Directory(b).create();
    final settings = SettingsService();
    await settings.init();
    prov = FileExplorerProvider(settings);
    await prov.navigateTo(b);
  });

  tearDown(() async {
    prov.dispose();
    await sandbox.delete(recursive: true);
  });

  test('couper-coller : seuls les échecs restent dans le presse-papiers',
      () async {
    File(p.join(a, 'ok.txt')).writeAsStringSync('x');
    final missing = p.join(a, 'absent.txt');
    prov.cutToClipboard([p.join(a, 'ok.txt'), missing]);

    final report = await prov.pasteClipboard();

    expect(report.succeeded, [p.join(a, 'ok.txt')]);
    expect(report.failures.single.path, missing);
    expect(prov.clipboardCount, 1);
    expect(prov.clipboardIsCut, isTrue);
    expect(File(p.join(b, 'ok.txt')).existsSync(), isTrue);
  });

  test('copier-coller : le presse-papiers est conservé', () async {
    File(p.join(a, 'f.txt')).writeAsStringSync('x');
    prov.copyToClipboard([p.join(a, 'f.txt')]);

    await prov.pasteClipboard();
    await prov.pasteClipboard(); // deuxième collage : garder les deux

    expect(prov.clipboardCount, 1);
    expect(File(p.join(b, 'f.txt')).existsSync(), isTrue);
    expect(File(p.join(b, 'f.1.txt')).existsSync(), isTrue);
  });

  test('collage possible ou non dans le dossier courant', () async {
    File(p.join(a, 'f.txt')).writeAsStringSync('x');
    await Directory(p.join(b, 'sous')).create();

    expect(prov.pasteBlockReason, isNull); // presse-papiers vide

    prov.copyToClipboard([p.join(a, 'f.txt')]);
    expect(prov.pasteBlockReason, isNull);

    // Déplacer vers le dossier d'origine : rien à faire.
    await prov.navigateTo(a);
    prov.cutToClipboard([p.join(a, 'f.txt')]);
    expect(prov.pasteBlockReason, 'Déjà dans ce dossier');
    // Copier dans le même dossier reste possible (copie à côté).
    prov.copyToClipboard([p.join(a, 'f.txt')]);
    expect(prov.pasteBlockReason, isNull);

    // Un dossier dans lui-même ou dans un de ses sous-dossiers.
    prov.copyToClipboard([b]);
    await prov.navigateTo(b);
    expect(prov.pasteBlockReason, contains('lui-même'));
    await prov.navigateTo(p.join(b, 'sous'));
    expect(prov.pasteBlockReason, contains('lui-même'));
    expect(prov.clipboard, [b]);
  });

  test('renommer vers un nom existant est refusé', () async {
    File(p.join(b, 'one.txt')).writeAsStringSync('un');
    File(p.join(b, 'two.txt')).writeAsStringSync('deux');

    await expectLater(prov.rename(p.join(b, 'one.txt'), 'two.txt'),
        throwsA(isA<FileOpException>()));
    expect(File(p.join(b, 'two.txt')).readAsStringSync(), 'deux');
  });

  test('créer un dossier existant est signalé', () async {
    await Directory(p.join(b, 'd')).create();
    await expectLater(
        prov.createDirectory('d'), throwsA(isA<FileOpException>()));
  });
}
