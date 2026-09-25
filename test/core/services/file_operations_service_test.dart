import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/core/services/file_operations_service.dart';

void main() {
  const ops = FileOperationsService();
  late Directory sandbox;
  late String a; // dossier source
  late String b; // dossier destination

  final noLinks = Platform.isWindows ? 'liens symboliques non garantis' : null;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('file_ops_test_');
    a = p.join(sandbox.path, 'a');
    b = p.join(sandbox.path, 'b');
    await Directory(a).create();
    await Directory(b).create();
  });

  tearDown(() => sandbox.delete(recursive: true));

  File write(String path, String text) => File(path)..writeAsStringSync(text);
  String read(String path) => File(path).readAsStringSync();
  List<String> names(String dir) =>
      Directory(dir).listSync().map((e) => p.basename(e.path)).toList()..sort();

  group('FileNameValidator', () {
    for (final bad in ['', '   ', '.', '..', 'a/b', '../x', 'a\u0000b']) {
      test('refuse « $bad »', () {
        expect(FileNameValidator.validate(bad), isNotNull);
      });
    }
    test('refuse un nom de plus de 255 octets', () {
      expect(FileNameValidator.validate('é' * 128), isNotNull); // 256 octets
      expect(FileNameValidator.validate('é' * 127), isNull);
    });
    for (final ok in ['notes.txt', '.bashrc', 'Été 2024', 'a b (1).tar.gz']) {
      test('accepte « $ok »', () {
        expect(FileNameValidator.validate(ok), isNull);
      });
    }
  });

  group('création', () {
    test('crée un dossier et un fichier', () async {
      await ops.createDirectory(a, 'dir');
      await ops.createFile(a, 'f.txt');
      expect(Directory(p.join(a, 'dir')).existsSync(), isTrue);
      expect(File(p.join(a, 'f.txt')).existsSync(), isTrue);
    });

    test('refuse un nom déjà pris sans toucher à l\'existant', () async {
      write(p.join(a, 'f.txt'), 'garder');
      await expectLater(
          ops.createFile(a, 'f.txt'), throwsA(isA<FileOpException>()));
      await expectLater(
          ops.createDirectory(a, 'f.txt'), throwsA(isA<FileOpException>()));
      expect(read(p.join(a, 'f.txt')), 'garder');
    });

    test('refuse un nom qui sortirait du dossier', () async {
      await expectLater(
          ops.createFile(a, '../evil.txt'), throwsA(isA<FileOpException>()));
      await expectLater(
          ops.createDirectory(a, 'x/y'), throwsA(isA<FileOpException>()));
      expect(File(p.join(sandbox.path, 'evil.txt')).existsSync(), isFalse);
    });
  });

  group('renommage', () {
    test('renomme un fichier', () async {
      write(p.join(a, 'old.txt'), 'x');
      final dest = await ops.rename(p.join(a, 'old.txt'), 'new.txt');
      expect(dest, p.join(a, 'new.txt'));
      expect(names(a), ['new.txt']);
    });

    test('n\'écrase jamais un élément existant', () async {
      write(p.join(a, 'one.txt'), 'un');
      write(p.join(a, 'two.txt'), 'deux');

      await expectLater(ops.rename(p.join(a, 'one.txt'), 'two.txt'),
          throwsA(isA<FileOpException>()));
      expect(read(p.join(a, 'one.txt')), 'un');
      expect(read(p.join(a, 'two.txt')), 'deux');
    });

    test('n\'écrase pas un dossier existant', () async {
      await Directory(p.join(a, 'd1')).create();
      await Directory(p.join(a, 'd2'))
          .create(); // vide : rename(2) l'écraserait
      await expectLater(
          ops.rename(p.join(a, 'd1'), 'd2'), throwsA(isA<FileOpException>()));
      expect(names(a), ['d1', 'd2']);
    });

    test('refuse un nom qui déplacerait le fichier ailleurs', () async {
      write(p.join(a, 'f.txt'), 'x');
      await expectLater(ops.rename(p.join(a, 'f.txt'), '../f.txt'),
          throwsA(isA<FileOpException>()));
      expect(names(a), ['f.txt']);
    });

    test('accepte un changement de casse seule', () async {
      write(p.join(a, 'readme.md'), 'x');
      await ops.rename(p.join(a, 'readme.md'), 'README.md');
      expect(names(a), ['README.md']);
      expect(read(p.join(a, 'README.md')), 'x');
    });

    test('lien dont le nom ne diffère que par la casse : refusé', () async {
      write(p.join(a, 'notes'), 'cible');
      await Link(p.join(a, 'Notes.lnk')).create(p.join(a, 'notes'));
      await Link(p.join(a, 'NOTES')).create(p.join(a, 'notes'));

      await expectLater(ops.rename(p.join(a, 'NOTES'), 'notes'),
          throwsA(isA<FileOpException>()));
      expect(read(p.join(a, 'notes')), 'cible');
    }, skip: noLinks);

    test('élément disparu : erreur claire', () async {
      await expectLater(ops.rename(p.join(a, 'absent'), 'x'),
          throwsA(isA<FileOpException>()));
    });
  });

  group('copie / déplacement', () {
    test('copie un dossier et son contenu', () async {
      await Directory(p.join(a, 'd', 'sub')).create(recursive: true);
      write(p.join(a, 'd', 'sub', 'f.txt'), 'x');

      final r = await ops.transfer([p.join(a, 'd')], b, move: false);

      expect(r.succeeded, [p.join(a, 'd')]);
      expect(read(p.join(b, 'd', 'sub', 'f.txt')), 'x');
      expect(read(p.join(a, 'd', 'sub', 'f.txt')), 'x');
    });

    test('déplace un fichier', () async {
      write(p.join(a, 'f.txt'), 'x');
      final r = await ops.transfer([p.join(a, 'f.txt')], b, move: true);
      expect(r.succeeded.length, 1);
      expect(names(a), isEmpty);
      expect(read(p.join(b, 'f.txt')), 'x');
    });

    test('conflit sans résolveur : les deux sont gardés', () async {
      write(p.join(a, 'f.txt'), 'nouveau');
      write(p.join(b, 'f.txt'), 'ancien');

      await ops.transfer([p.join(a, 'f.txt')], b, move: false);

      expect(read(p.join(b, 'f.txt')), 'ancien');
      expect(read(p.join(b, 'f.1.txt')), 'nouveau');
    });

    test('conflit « ignorer »', () async {
      write(p.join(a, 'f.txt'), 'nouveau');
      write(p.join(b, 'f.txt'), 'ancien');

      final r = await ops.transfer([p.join(a, 'f.txt')], b,
          move: true, onConflict: (_, __) async => ConflictAction.skip);

      expect(r.skipped, [p.join(a, 'f.txt')]);
      expect(read(p.join(b, 'f.txt')), 'ancien');
      expect(read(p.join(a, 'f.txt')), 'nouveau'); // source intacte
    });

    test('conflit « remplacer » (fichier)', () async {
      write(p.join(a, 'f.txt'), 'nouveau');
      write(p.join(b, 'f.txt'), 'ancien');

      final r = await ops.transfer([p.join(a, 'f.txt')], b,
          move: true, onConflict: (_, __) async => ConflictAction.replace);

      expect(r.succeeded.length, 1);
      expect(read(p.join(b, 'f.txt')), 'nouveau');
      expect(names(a), isEmpty);
      expect(names(b), ['f.txt']); // aucun fichier temporaire restant
    });

    test('conflit « remplacer » un dossier', () async {
      await Directory(p.join(a, 'd')).create();
      await Directory(p.join(b, 'd')).create();
      write(p.join(a, 'd', 'new.txt'), 'n');
      write(p.join(b, 'd', 'old.txt'), 'o');

      await ops.transfer([p.join(a, 'd')], b,
          move: false, onConflict: (_, __) async => ConflictAction.replace);

      expect(names(p.join(b, 'd')), ['new.txt']);
      expect(names(b), ['d']);
    });

    test('copier dans le même dossier crée une copie, sans demander', () async {
      write(p.join(a, 'f.txt'), 'x');
      var asked = false;

      await ops.transfer([p.join(a, 'f.txt')], a, move: false,
          onConflict: (_, __) async {
        asked = true;
        return ConflictAction.replace;
      });

      expect(asked, isFalse);
      expect(names(a), ['f.copy.1.txt', 'f.txt']);
    });

    test('déplacer dans son propre dossier ne fait rien', () async {
      write(p.join(a, 'f.txt'), 'x');
      final r = await ops.transfer([p.join(a, 'f.txt')], a, move: true);
      expect(r.skipped.length, 1);
      expect(names(a), ['f.txt']);
    });

    test('refuse de copier un dossier dans lui-même', () async {
      await Directory(p.join(a, 'd', 'inner')).create(recursive: true);

      final r = await ops
          .transfer([p.join(a, 'd')], p.join(a, 'd', 'inner'), move: false);

      expect(r.failures.length, 1);
      expect(names(p.join(a, 'd', 'inner')), isEmpty);
    });

    test('refuse aussi quand la destination est atteinte par un lien',
        () async {
      await Directory(p.join(a, 'd', 'inner')).create(recursive: true);
      await Link(p.join(b, 'shortcut')).create(p.join(a, 'd', 'inner'));

      final r = await ops
          .transfer([p.join(a, 'd')], p.join(b, 'shortcut'), move: false);

      expect(r.failures.length, 1);
      expect(names(p.join(a, 'd', 'inner')), isEmpty);
    }, skip: noLinks);

    test('copie les liens comme des liens, sans suivre leur cible', () async {
      final outside = p.join(sandbox.path, 'outside');
      await Directory(outside).create();
      write(p.join(outside, 'big.bin'), 'cible');
      await Directory(p.join(a, 'd')).create();
      await Link(p.join(a, 'd', 'link')).create(outside);
      await Link(p.join(a, 'd', 'loop')).create(p.join(a, 'd')); // boucle

      final r = await ops.transfer([p.join(a, 'd')], b, move: false);

      expect(r.hasFailures, isFalse);
      final copied = p.join(b, 'd', 'link');
      expect(FileSystemEntity.isLinkSync(copied), isTrue);
      expect(Link(copied).targetSync(), outside);
      expect(FileSystemEntity.isLinkSync(p.join(b, 'd', 'loop')), isTrue);
    }, skip: noLinks);

    test('une copie ratée ne laisse rien derrière elle', () async {
      await Directory(p.join(a, 'd')).create();
      write(p.join(a, 'd', 'ok.txt'), 'ok');
      final locked = write(p.join(a, 'd', 'z_locked.txt'), 'secret');
      await Process.run('chmod', ['000', locked.path]);

      // Copie (sur un même stockage, un déplacement est un simple rename et
      // n'emprunte pas ce chemin).
      final r = await ops.transfer([p.join(a, 'd')], b, move: false);

      await Process.run('chmod', ['644', locked.path]);
      expect(r.failures.length, 1);
      expect(names(b), isEmpty); // pas de copie partielle
      expect(read(p.join(a, 'd', 'ok.txt')), 'ok'); // source intacte
    },
        skip: Platform.isWindows
            ? 'chmod indisponible'
            : (Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
                ? 'root ignore les permissions'
                : null));

    test('permission refusée : échec direct, rien n\'est copié', () async {
      await Directory(p.join(a, 'ro')).create();
      write(p.join(a, 'ro', 'f.txt'), 'x');
      await Process.run('chmod', ['555', p.join(a, 'ro')]);

      final r = await ops.transfer([p.join(a, 'ro', 'f.txt')], b, move: true);

      await Process.run('chmod', ['755', p.join(a, 'ro')]);
      expect(r.failures.single.reason, 'permission refusée');
      expect(names(b), isEmpty); // pas de repli « copie »
      expect(read(p.join(a, 'ro', 'f.txt')), 'x');
    },
        skip: Platform.isWindows
            ? 'chmod indisponible'
            : (Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
                ? 'root ignore les permissions'
                : null));

    test('déplacement vers un autre stockage : copie puis suppression',
        () async {
      final other =
          Directory('/dev/shm').createTempSync('file_ops_cross_device_');
      try {
        await Directory(p.join(a, 'd')).create();
        write(p.join(a, 'd', 'f.txt'), 'x');

        final r = await ops.transfer([p.join(a, 'd')], other.path, move: true);

        expect(r.succeeded.length, 1);
        expect(read(p.join(other.path, 'd', 'f.txt')), 'x');
        expect(Directory(p.join(a, 'd')).existsSync(), isFalse);
      } finally {
        other.deleteSync(recursive: true);
      }
    },
        skip: !Directory('/dev/shm').existsSync() ||
                FileStat.statSync('/dev/shm').type ==
                    FileSystemEntityType.notFound ||
                _sameDevice('/dev/shm', Directory.systemTemp.path)
            ? 'pas de second système de fichiers disponible'
            : null);

    test('rapporte chaque échec et continue', () async {
      write(p.join(a, 'ok.txt'), 'x');
      final r = await ops.transfer(
          [p.join(a, 'absent.txt'), p.join(a, 'ok.txt')], b,
          move: false);
      expect(r.failures.single.path, p.join(a, 'absent.txt'));
      expect(r.succeeded, [p.join(a, 'ok.txt')]);
    });
  });

  group('suppression définitive', () {
    test('supprime fichiers et dossiers', () async {
      write(p.join(a, 'f.txt'), 'x');
      await Directory(p.join(a, 'd', 'e')).create(recursive: true);

      final r =
          await ops.deletePermanently([p.join(a, 'f.txt'), p.join(a, 'd')]);

      expect(r.succeeded.length, 2);
      expect(names(a), isEmpty);
    });

    test('supprime un lien sans toucher à sa cible', () async {
      final target = p.join(sandbox.path, 'target');
      await Directory(target).create();
      write(p.join(target, 'keep.txt'), 'x');
      await Link(p.join(a, 'link')).create(target);

      await ops.deletePermanently([p.join(a, 'link')]);

      expect(names(a), isEmpty);
      expect(read(p.join(target, 'keep.txt')), 'x');
    }, skip: noLinks);
  });

  group('uniqueDestination', () {
    test('conflit : point et numéro avant l\'extension', () {
      write(p.join(a, 'f.txt'), '');
      write(p.join(a, 'f.1.txt'), '');
      expect(FileOperationsService.uniqueDestination(a, 'f.txt'),
          p.join(a, 'f.2.txt'));
    });

    test('fichiers cachés et dossiers', () async {
      write(p.join(a, '.bashrc'), '');
      await Directory(p.join(a, 'photos.2023')).create();
      expect(FileOperationsService.uniqueDestination(a, '.bashrc'),
          p.join(a, '.bashrc.1'));
      expect(
          FileOperationsService.uniqueDestination(a, 'photos.2023',
              keepExtension: false),
          p.join(a, 'photos.2023.1'));
    });
  });

  group('dupliquer', () {
    test('fichier : .copy.N, numéro suivant à chaque duplication', () async {
      write(p.join(a, 'rapport.txt'), 'r');

      await ops.duplicate([p.join(a, 'rapport.txt')]);
      await ops.duplicate([p.join(a, 'rapport.txt')]);
      // Dupliquer une copie reprend la numérotation de l'original.
      await ops.duplicate([p.join(a, 'rapport.copy.1.txt')]);

      expect(names(a), [
        'rapport.copy.1.txt',
        'rapport.copy.2.txt',
        'rapport.copy.3.txt',
        'rapport.txt',
      ]);
      expect(read(p.join(a, 'rapport.copy.3.txt')), 'r');
    });

    test('dossier avec son contenu, et archive à double extension', () async {
      await Directory(p.join(a, 'projet')).create();
      write(p.join(a, 'projet', 'main.dart'), 'code');
      write(p.join(a, 'site.tar.gz'), 'x');

      final r =
          await ops.duplicate([p.join(a, 'projet'), p.join(a, 'site.tar.gz')]);

      expect(r.succeeded.length, 2);
      expect(read(p.join(a, 'projet.copy.1', 'main.dart')), 'code');
      expect(File(p.join(a, 'site.copy.1.tar.gz')).existsSync(), isTrue);
    });

    test('élément disparu : rapporté', () async {
      final r = await ops.duplicate([p.join(a, 'absent')]);
      expect(r.failures.length, 1);
    });
  });
}

/// Vrai si [a] et [b] sont sur le même système de fichiers (Linux, via stat).
bool _sameDevice(String a, String b) {
  final r = Process.runSync('stat', ['-c', '%d', a, b]);
  if (r.exitCode != 0) return true;
  final ids = r.stdout.toString().trim().split('\n');
  return ids.length != 2 || ids[0] == ids[1];
}
