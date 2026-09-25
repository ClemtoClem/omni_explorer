import 'dart:io';

import 'package:archive/archive.dart' as arc;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/core/services/file_operations_service.dart';
import 'package:omni_explorer/features/archive/models/archive_entry.dart';
import 'package:omni_explorer/features/archive/models/archive_tree.dart';
import 'package:omni_explorer/features/archive/services/archive_document.dart';

void main() {
  late Directory sandbox;
  setUp(() async =>
      sandbox = await Directory.systemTemp.createTemp('archive_doc_test_'));
  tearDown(() => sandbox.delete(recursive: true));

  String disk(String rel, String text) {
    final f = File(p.join(sandbox.path, 'disk', rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    return f.path;
  }

  List<String> names(ArchiveTree t, String dir) => t
      .children(dir)
      .map((n) => n.isDirectory ? '${n.name}/' : n.name)
      .toList();

  /// Archive de départ : README.md, src/main.dart, src/util.dart.
  String makeArchive(String fileName) {
    final a = arc.Archive()
      ..addFile(arc.ArchiveFile.string('README.md', 'lisez-moi'))
      ..addFile(arc.ArchiveFile.string('src/main.dart', 'main'))
      ..addFile(arc.ArchiveFile.string('src/util.dart', 'util'));
    final tar = arc.TarEncoder().encodeBytes(a);
    final bytes = switch (p.extension(fileName)) {
      '.zip' => arc.ZipEncoder().encodeBytes(a),
      '.tar' => tar,
      '.gz' => const arc.GZipEncoder().encodeBytes(tar),
      _ => arc.BZip2Encoder().encodeBytes(tar),
    };
    final path = p.join(sandbox.path, fileName);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  Future<ArchiveDocument> reopen(ArchiveDocument doc) async {
    await doc.save();
    return ArchiveDocument.open(doc.path, password: doc.password);
  }

  for (final fileName in [
    'projet.zip',
    'projet.tar',
    'projet.tar.gz',
    'projet.tar.bz2'
  ]) {
    group(fileName, () {
      test('ajouter, créer, renommer, déplacer, dupliquer, supprimer',
          () async {
        var doc = await ArchiveDocument.open(makeArchive(fileName));
        expect(doc.canEdit, isTrue);

        disk('notes.txt', 'notes');
        disk('assets/logo.svg', '<svg/>');
        await doc.addFromDisk([
          p.join(sandbox.path, 'disk', 'notes.txt'),
          p.join(sandbox.path, 'disk', 'assets'),
        ], '');
        doc.createFolder('', 'docs');
        doc.rename('README.md', 'LISEZMOI.md');
        doc.rename('src', 'lib');
        await doc.move(['notes.txt'], 'docs');
        doc.duplicate(['lib/main.dart']);
        doc.delete(['lib/util.dart']);

        doc = await reopen(doc);
        final t = doc.tree;
        expect(names(t, ''), ['assets/', 'docs/', 'lib/', 'LISEZMOI.md']);
        expect(names(t, 'lib'), ['main.copy.1.dart', 'main.dart']);
        expect(names(t, 'docs'), ['notes.txt']);
        expect(
            String.fromCharCodes(doc.readFile('lib/main.copy.1.dart')), 'main');
        expect(String.fromCharCodes(doc.readFile('assets/logo.svg')), '<svg/>');
        expect(String.fromCharCodes(doc.readFile('LISEZMOI.md')), 'lisez-moi');
      });

      test(
          'mise à jour depuis un dossier : ajoute et remplace, ne supprime rien',
          () async {
        final project = p.join(sandbox.path, 'disk', 'projet');
        disk('projet/src/main.dart', 'main');
        disk('projet/src/util.dart', 'util v2'); // modifié
        disk('projet/src/nouveau.dart', 'nouveau'); // ajouté
        disk('projet/build/sortie.bin', 'binaire'); // exclu
        var doc = await ArchiveDocument.open(makeArchive(fileName));

        final report = doc.syncFromDirectory(project, exclude: {'build'});

        expect(report.added, 1);
        expect(report.updated, 1);
        expect(report.unchanged, 1);
        expect(report.skipped, 1);
        doc = await reopen(doc);
        expect(String.fromCharCodes(doc.readFile('src/util.dart')), 'util v2');
        expect(
            String.fromCharCodes(doc.readFile('src/nouveau.dart')), 'nouveau');
        expect(doc.exists('README.md'), isTrue); // absent du dossier : conservé
        expect(doc.exists('build'), isFalse);

        // Deuxième passage : plus rien à faire.
        final again = doc.syncFromDirectory(project, exclude: {'build'});
        expect(again.added + again.updated, 0);
      });
    });
  }

  group('conflits dans l\'archive', () {
    Future<ArchiveDocument> withConflict() async {
      final doc = await ArchiveDocument.open(makeArchive('c.zip'));
      doc.createFolder('', 'dest');
      disk('main.dart', 'autre');
      await doc
          .addFromDisk([p.join(sandbox.path, 'disk', 'main.dart')], 'dest');
      return doc;
    }

    test('déplacer : renommer (par défaut), remplacer, ignorer', () async {
      var doc = await withConflict();
      await doc.move(['src/main.dart'], 'dest');
      expect(names(doc.tree, 'dest'), ['main.1.dart', 'main.dart']);

      doc = await withConflict();
      await doc.move(['src/main.dart'], 'dest',
          onConflict: (_, __) async => ConflictAction.replace);
      expect(String.fromCharCodes(doc.readFile('dest/main.dart')), 'main');
      expect(doc.exists('src/main.dart'), isFalse);

      doc = await withConflict();
      final r = await doc.move(['src/main.dart'], 'dest',
          onConflict: (_, __) async => ConflictAction.skip);
      expect(r.skipped, 1);
      expect(doc.exists('src/main.dart'), isTrue);
    });

    test('ajouter depuis le disque : conflit résolu', () async {
      final doc = await ArchiveDocument.open(makeArchive('c.zip'));
      disk('README.md', 'nouveau');
      final r = await doc.addFromDisk(
          [p.join(sandbox.path, 'disk', 'README.md')], '',
          onConflict: (_, __) async => ConflictAction.replace);
      expect(r.replaced, 1);
      expect(String.fromCharCodes(doc.readFile('README.md')), 'nouveau');
    });

    test('dossier dans lui-même refusé ; noms invalides refusés', () async {
      final doc = await ArchiveDocument.open(makeArchive('c.zip'));
      doc.createFolder('src', 'sub');
      final r = await doc.move(['src'], 'src/sub');
      expect(r.failures.length, 1);
      expect(() => doc.rename('README.md', 'a/b'),
          throwsA(isA<ArchiveOpException>()));
      expect(() => doc.rename('README.md', 'src'),
          throwsA(isA<ArchiveOpException>()));
      expect(() => doc.createFolder('', 'src'),
          throwsA(isA<ArchiveOpException>()));
    });

    test('les liens symboliques du disque ne sont pas ajoutés', () async {
      final doc = await ArchiveDocument.open(makeArchive('c.zip'));
      final link = p.join(sandbox.path, 'lien');
      Link(link).createSync('/etc/passwd');
      final r = await doc.addFromDisk([link], '');
      expect(r.skipped, 1);
      expect(doc.exists('lien'), isFalse);
    }, skip: Platform.isWindows);
  });

  test('ZIP chiffré en AES : mot de passe exigé', () async {
    var doc = await ArchiveDocument.open(makeArchive('secret.zip'));
    doc.setPassword('mot de passe');
    await doc.save();

    // Sans mot de passe, le contenu n'est pas lisible.
    await expectLater(() async {
      final d = await ArchiveDocument.open(doc.path);
      d.readFile('README.md');
    }(), throwsA(anything));

    doc = await ArchiveDocument.open(doc.path, password: 'mot de passe');
    expect(String.fromCharCodes(doc.readFile('README.md')), 'lisez-moi');
  });

  test('formats en lecture seule : modification refusée', () async {
    final a = arc.Archive()..addFile(arc.ArchiveFile.string('a.txt', 'x'));
    final txz = p.join(sandbox.path, 'r.tar.xz');
    File(txz).writeAsBytesSync(
        arc.XZEncoder().encodeBytes(arc.TarEncoder().encodeBytes(a)));
    final gz = p.join(sandbox.path, 'note.txt.gz');
    File(gz)
        .writeAsBytesSync(const arc.GZipEncoder().encodeBytes('abc'.codeUnits));

    final xz = await ArchiveDocument.open(txz);
    expect(xz.canEdit, isFalse);
    expect(names(xz.tree, ''), ['a.txt']); // mais lisible
    expect(() => xz.createFolder('', 'x'), throwsA(isA<ArchiveOpException>()));

    final single = await ArchiveDocument.open(gz);
    expect(single.canEdit, isFalse);
    expect(String.fromCharCodes(single.readFile('note.txt')), 'abc');
  });
}
