import 'dart:io';

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
    expect(File(p.join(b, 'f (copie).txt')).existsSync(), isTrue);
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
