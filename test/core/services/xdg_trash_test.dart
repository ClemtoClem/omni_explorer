/// Corbeille du système (Linux, spécification freedesktop) : format des
/// .trashinfo, mise à la corbeille, éléments ajoutés par d'autres logiciels,
/// restauration, suppression, corbeille d'un autre disque.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/core/services/file_operations_service.dart';
import 'package:omni_explorer/core/services/trash_service.dart';
import 'package:omni_explorer/core/services/xdg_trash.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late String home, disk, homeTrash;
  late XdgTrash xdg;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('xdg_trash_test_');
    home = p.join(sandbox.path, 'home');
    disk = p.join(sandbox.path, 'media', 'CLE'); // « autre disque »
    homeTrash = p.join(home, '.local', 'share', 'Trash');
    await Directory(home).create(recursive: true);
    await Directory(disk).create(recursive: true);
    xdg = XdgTrash(
      homeTrash: homeTrash,
      uid: 1000,
      mountPoints: () => ['/', disk],
    );
  });
  tearDown(() => sandbox.delete(recursive: true));

  File write(String path, [String text = 'x']) {
    File(path).parent.createSync(recursive: true);
    return File(path)..writeAsStringSync(text);
  }

  group('.trashinfo', () {
    test('format de la spécification, chemin encodé', () {
      final text = XdgTrash.formatTrashInfo(
          '/home/moi/Mes documents/été.txt', DateTime(2026, 10, 3, 9, 5, 7));
      expect(
          text,
          '[Trash Info]\n'
          'Path=/home/moi/Mes%20documents/%C3%A9t%C3%A9.txt\n'
          'DeletionDate=2026-10-03T09:05:07\n');
      final back = XdgTrash.parseTrashInfo(text)!;
      expect(back.path, '/home/moi/Mes documents/été.txt');
      expect(back.deletedAt, DateTime(2026, 10, 3, 9, 5, 7));
    });

    test('section ou chemin absents : invalide', () {
      expect(XdgTrash.parseTrashInfo('Path=/a'), isNull);
      expect(XdgTrash.parseTrashInfo('[Trash Info]\nDeletionDate=2026-01-01'),
          isNull);
    });
  });

  group('corbeille personnelle', () {
    test('mettre à la corbeille : contenu dans files/, origine dans info/',
        () async {
      final f = write(p.join(home, 'Documents', 'note.txt'));
      final item = await xdg.trash(f.path);

      expect(f.existsSync(), isFalse);
      expect(item.trashedPath, p.join(homeTrash, 'files', 'note.txt'));
      final info = File(p.join(homeTrash, 'info', 'note.txt.trashinfo'));
      expect(XdgTrash.parseTrashInfo(info.readAsStringSync())!.path, f.path);
      expect(xdg.list().single.originalPath, f.path);
    });

    test('même nom deux fois : nom libre numéroté', () async {
      await xdg.trash(write(p.join(home, 'a', 'r.txt')).path);
      final second = await xdg.trash(write(p.join(home, 'b', 'r.txt')).path);
      expect(p.basename(second.trashedPath), 'r.1.txt');
      expect(
          xdg.list().map((i) => i.originalPath),
          unorderedEquals([
            p.join(home, 'a', 'r.txt'),
            p.join(home, 'b', 'r.txt'),
          ]));
    });

    test('éléments mis à la corbeille par un autre logiciel visibles', () {
      write(p.join(homeTrash, 'files', 'Photo vacances.jpg'));
      write(
          p.join(homeTrash, 'info', 'Photo vacances.jpg.trashinfo'),
          '[Trash Info]\nPath=/home/moi/Images/Photo%20vacances.jpg\n'
          'DeletionDate=2026-09-01T12:00:00\n');
      // Contenu sans description : orphelin. Description sans contenu :
      // ignorée.
      write(p.join(homeTrash, 'files', 'mystere.bin'));
      write(p.join(homeTrash, 'info', 'fantome.txt.trashinfo'),
          '[Trash Info]\nPath=/x/fantome.txt\n');

      final items = xdg.list();
      expect(items.map((i) => i.name),
          unorderedEquals(['Photo vacances.jpg', 'mystere.bin']));
      final photo = items.firstWhere((i) => !i.isOrphan);
      expect(photo.originalPath, '/home/moi/Images/Photo vacances.jpg');
      expect(photo.deletedAt, DateTime(2026, 9, 1, 12));
      expect(items.firstWhere((i) => i.isOrphan).name, 'mystere.bin');
    });

    test('restaurer, puis conflit avec un fichier revenu entre-temps',
        () async {
      final path = p.join(home, 'Documents', 'r.txt');
      final item = await xdg.trash(write(path, 'ancien').path);
      write(path, 'nouveau');

      final restoredTo = await xdg.restore(item,
          onConflict: (_, __) async => ConflictAction.keepBoth);
      expect(restoredTo, p.join(home, 'Documents', 'r.1.txt'));
      expect(File(restoredTo!).readAsStringSync(), 'ancien');
      expect(File(path).readAsStringSync(), 'nouveau');
      expect(xdg.list(), isEmpty);
      expect(Directory(p.join(homeTrash, 'info')).listSync(), isEmpty);
    });

    test('supprimer définitivement efface contenu et description', () async {
      final d = Directory(p.join(home, 'dossier'))..createSync();
      write(p.join(d.path, 'sous', 'f.txt'));
      final item = await xdg.trash(d.path);
      expect(item.isDirectory, isTrue);

      await xdg.delete(item);
      expect(Directory(p.join(homeTrash, 'files')).listSync(), isEmpty);
      expect(Directory(p.join(homeTrash, 'info')).listSync(), isEmpty);
    });

    test('refuse la corbeille elle-même et ce qu\'elle contient', () async {
      final item = await xdg.trash(write(p.join(home, 'a.txt')).path);
      await expectLater(
          xdg.trash(item.trashedPath), throwsA(isA<FileOpException>()));
      await expectLater(xdg.trash(home), throwsA(isA<FileOpException>()));
    });
  });

  group('autre disque', () {
    test('corbeille du disque (.Trash-uid), chemin relatif au disque',
        () async {
      final f = write(p.join(disk, 'Films', 'clip.mp4'));
      final item = await xdg.trash(f.path);

      final diskTrash = p.join(disk, '.Trash-1000');
      expect(item.trashedPath, p.join(diskTrash, 'files', 'clip.mp4'));
      final info = File(p.join(diskTrash, 'info', 'clip.mp4.trashinfo'));
      expect(XdgTrash.parseTrashInfo(info.readAsStringSync())!.path,
          'Films/clip.mp4');
      // Rien dans la corbeille personnelle, mais l'élément est listé avec
      // son chemin complet.
      expect(Directory(p.join(homeTrash, 'files')).existsSync(), isFalse);
      expect(xdg.list().single.originalPath, f.path);

      await xdg.restore(xdg.list().single);
      expect(f.existsSync(), isTrue);
    });
  });

  group('TrashService avec la corbeille du système', () {
    late TrashService service;

    setUp(() async {
      service = TrashService();
      await service.init(systemTrash: xdg);
    });

    test('mettre à la corbeille, restaurer, vider', () async {
      expect(service.usesSystemTrash, isTrue);
      final a = write(p.join(home, 'a.txt'));
      final b = write(p.join(disk, 'b.txt'));
      await service.moveAllToTrash([a.path, b.path]);
      expect(service.items, hasLength(2));

      final itemA = service.items.firstWhere((i) => i.originalPath == a.path);
      await service.restore(itemA);
      expect(a.existsSync(), isTrue);
      expect(service.items.single.originalPath, b.path);

      final report = await service.emptyTrash();
      expect(report.hasFailures, isFalse);
      expect(service.items, isEmpty);
      expect(
          Directory(p.join(disk, '.Trash-1000', 'files')).listSync(), isEmpty);
    });

    test('un ajout par un autre logiciel apparaît sans relancer', () async {
      write(p.join(homeTrash, 'files', 'externe.txt'));
      write(p.join(homeTrash, 'info', 'externe.txt.trashinfo'),
          '[Trash Info]\nPath=/tmp/externe.txt\nDeletionDate=2026-10-03T10:00:00\n');
      for (var i = 0; i < 100 && service.items.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(service.items.single.originalPath, '/tmp/externe.txt');
    });

    tearDown(() async {
      // Retour à une corbeille d'application (arrête la surveillance).
      await service.init(directory: p.join(sandbox.path, 'app_trash'));
    });
  });
}
