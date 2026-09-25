import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/core/services/file_operations_service.dart';
import 'package:omni_explorer/core/services/trash_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late String trashDir;
  late String docs;
  late TrashService trash;

  final noLinks = Platform.isWindows ? 'liens symboliques non garantis' : null;
  final noChmod = Platform.isWindows
      ? 'chmod indisponible'
      : (Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'root ignore les permissions'
          : null);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('trash_test_');
    trashDir = p.join(sandbox.path, '.omni_trash');
    docs = p.join(sandbox.path, 'docs');
    await Directory(docs).create();
    trash = TrashService();
    await trash.init(directory: trashDir);
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+rwx', sandbox.path]);
    await sandbox.delete(recursive: true);
  });

  File write(String path, String text) {
    File(path).parent.createSync(recursive: true);
    return File(path)..writeAsStringSync(text);
  }

  File metaFile() => File(p.join(trashDir, AppConstants.trashMetaFile));

  group('mise à la corbeille', () {
    test('déplace le fichier et l\'indexe', () async {
      final f = write(p.join(docs, 'note.txt'), 'x');

      final item = await trash.moveToTrash(f.path);

      expect(f.existsSync(), isFalse);
      expect(File(item.trashedPath).readAsStringSync(), 'x');
      expect(trash.items.single.originalPath, f.path);
      final meta = jsonDecode(metaFile().readAsStringSync()) as List;
      expect(meta.single['originalPath'], f.path);
    });

    test('élément absent : erreur claire', () async {
      await expectLater(trash.moveToTrash(p.join(docs, 'absent')),
          throwsA(isA<FileOpException>()));
      expect(trash.items, isEmpty);
    });

    test('refuse un dossier qui contient la corbeille', () async {
      await expectLater(
          trash.moveToTrash(sandbox.path), throwsA(isA<FileOpException>()));
      expect(Directory(trashDir).existsSync(), isTrue);
      expect(trash.items, isEmpty);
    });

    test('refuse un élément déjà dans la corbeille', () async {
      final item =
          await trash.moveToTrash(write(p.join(docs, 'a.txt'), 'x').path);
      await expectLater(
          trash.moveToTrash(item.trashedPath), throwsA(isA<FileOpException>()));
      expect(trash.items.length, 1);
    });

    test('permission refusée : rien n\'est copié ni indexé', () async {
      final f = write(p.join(docs, 'locked', 'f.txt'), 'x');
      await Process.run('chmod', ['555', p.dirname(f.path)]);

      await expectLater(
          trash.moveToTrash(f.path), throwsA(isA<FileOpException>()));

      expect(f.readAsStringSync(), 'x');
      expect(trash.items, isEmpty);
      expect(
          Directory(trashDir)
              .listSync()
              .where((e) => !p.basename(e.path).startsWith('.')),
          isEmpty);
    }, skip: noChmod);

    test('un lien est mis à la corbeille sans toucher à sa cible', () async {
      final target = write(p.join(sandbox.path, 'target.txt'), 'cible');
      final link = Link(p.join(docs, 'link'))..createSync(target.path);

      final item = await trash.moveToTrash(link.path);

      expect(FileSystemEntity.isLinkSync(item.trashedPath), isTrue);
      expect(target.readAsStringSync(), 'cible');
      await trash.restore(item);
      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    }, skip: noLinks);
  });

  group('restauration', () {
    test('restaure un fichier à sa place', () async {
      final f = write(p.join(docs, 'note.txt'), 'x');
      final item = await trash.moveToTrash(f.path);

      final to = await trash.restore(item);

      expect(to, f.path);
      expect(f.readAsStringSync(), 'x');
      expect(trash.items, isEmpty);
    });

    test('restaure un dossier et recrée son dossier parent', () async {
      write(p.join(docs, 'projet', 'src', 'main.dart'), 'code');
      final item = await trash.moveToTrash(p.join(docs, 'projet'));
      await Directory(docs).delete(recursive: true);

      await trash.restore(item);

      expect(
          File(p.join(docs, 'projet', 'src', 'main.dart')).readAsStringSync(),
          'code');
    });

    test('n\'écrase jamais un fichier recréé entre-temps', () async {
      final f = write(p.join(docs, 'note.txt'), 'ancien');
      final item = await trash.moveToTrash(f.path);
      write(f.path, 'nouveau');

      final to = await trash.restore(item);

      expect(f.readAsStringSync(), 'nouveau');
      expect(to, isNot(f.path));
      expect(File(to!).readAsStringSync(), 'ancien');
      expect(trash.items, isEmpty);
    });

    test('conflit « ignorer » : l\'élément reste dans la corbeille', () async {
      final f = write(p.join(docs, 'note.txt'), 'ancien');
      final item = await trash.moveToTrash(f.path);
      write(f.path, 'nouveau');

      final to = await trash.restore(item,
          onConflict: (_, __) async => ConflictAction.skip);

      expect(to, isNull);
      expect(trash.items.single, item);
      expect(f.readAsStringSync(), 'nouveau');
    });

    test('conflit « remplacer »', () async {
      final f = write(p.join(docs, 'note.txt'), 'ancien');
      final item = await trash.moveToTrash(f.path);
      write(f.path, 'nouveau');

      await trash.restore(item,
          onConflict: (_, __) async => ConflictAction.replace);

      expect(f.readAsStringSync(), 'ancien');
      expect(trash.items, isEmpty);
    });

    test('échec : l\'élément reste dans la corbeille', () async {
      final f = write(p.join(docs, 'ro', 'note.txt'), 'x');
      final item = await trash.moveToTrash(f.path);
      await Process.run('chmod', ['555', p.join(docs, 'ro')]);

      await expectLater(trash.restore(item), throwsA(isA<FileOpException>()));

      expect(trash.items.single, item);
      expect(File(item.trashedPath).existsSync(), isTrue);
    }, skip: noChmod);
  });

  group('suppression', () {
    test('supprime définitivement un élément', () async {
      final item =
          await trash.moveToTrash(write(p.join(docs, 'a.txt'), 'x').path);
      await trash.deletePermanently(item);
      expect(File(item.trashedPath).existsSync(), isFalse);
      expect(trash.items, isEmpty);
    });

    test('échec de suppression : l\'élément reste listé', () async {
      final item =
          await trash.moveToTrash(write(p.join(docs, 'a.txt'), 'x').path);
      await Process.run('chmod', ['555', trashDir]);

      await expectLater(
          trash.deletePermanently(item), throwsA(isA<FileOpException>()));
      expect(trash.items.single, item);
    }, skip: noChmod);

    test('vider : bilan de chaque élément', () async {
      await trash.moveToTrash(write(p.join(docs, 'a.txt'), 'x').path);
      await trash.moveToTrash(write(p.join(docs, 'b.txt'), 'y').path);

      final report = await trash.emptyTrash();

      expect(report.succeeded.length, 2);
      expect(report.hasFailures, isFalse);
      expect(trash.items, isEmpty);
    });
  });

  group('index et réconciliation', () {
    test('l\'index survit à un redémarrage', () async {
      final f = write(p.join(docs, 'note.txt'), 'x');
      await trash.moveToTrash(f.path);

      await trash.init(directory: trashDir);

      expect(trash.items.single.originalPath, f.path);
    });

    test('entrée sans fichier (application tuée) : retirée', () async {
      metaFile().writeAsStringSync(jsonEncode([
        {
          'trashedPath': p.join(trashDir, 'fantome.txt'),
          'originalPath': p.join(docs, 'fantome.txt'),
          'deletedAt': DateTime.now().toIso8601String(),
          'isDirectory': 0,
          'size': 1,
        }
      ]));

      await trash.init(directory: trashDir);

      expect(trash.items, isEmpty);
    });

    test('fichier hors index : listé comme orphelin, supprimable', () async {
      write(p.join(trashDir, 'perdu.txt'), 'x');

      await trash.init(directory: trashDir);

      final orphan = trash.items.single;
      expect(orphan.isOrphan, isTrue);
      await expectLater(trash.restore(orphan), throwsA(isA<FileOpException>()));
      await trash.deletePermanently(orphan);
      expect(trash.items, isEmpty);
    });

    test('index corrompu : mis de côté, contenu toujours listé', () async {
      final f = write(p.join(docs, 'note.txt'), 'x');
      final item = await trash.moveToTrash(f.path);
      metaFile().writeAsStringSync('{ pas du json');

      await trash.init(directory: trashDir);

      expect(trash.items.single.trashedPath, item.trashedPath);
      expect(trash.items.single.isOrphan, isTrue);
      final aside = Directory(trashDir)
          .listSync()
          .where((e) => p.basename(e.path).contains('.corrupt-'));
      expect(aside.length, 1);
      expect(File(aside.single.path).readAsStringSync(), '{ pas du json');
    });

    test('l\'index est écrit de façon atomique (aucun temporaire laissé)',
        () async {
      await trash.moveToTrash(write(p.join(docs, 'a.txt'), 'x').path);
      final leftovers = Directory(trashDir)
          .listSync()
          .where((e) => p.basename(e.path).contains('.tmp-'));
      expect(leftovers, isEmpty);
    });
  });
}
