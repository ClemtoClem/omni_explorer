import 'dart:io';

import 'package:archive/archive.dart' as arc;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/archive/models/archive_entry.dart';
import 'package:omni_explorer/features/archive/services/archive_service.dart';

void main() {
  late Directory sandbox;
  setUp(() async =>
      sandbox = await Directory.systemTemp.createTemp('archive_format_test_'));
  tearDown(() => sandbox.delete(recursive: true));

  String write(String name, List<int> bytes) {
    final path = p.join(sandbox.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  List<int> zipBytes() => arc.ZipEncoder().encodeBytes(
      arc.Archive()..addFile(arc.ArchiveFile.string('word/document.xml', 'x')));
  List<int> tarBytes() => arc.TarEncoder().encodeBytes(
      arc.Archive()..addFile(arc.ArchiveFile.string('a.txt', 'x')));

  test('formats dérivés de ZIP reconnus par leur signature', () {
    expect(ArchiveService.detectType(write('rapport.docx', zipBytes())),
        ArchiveType.zip);
    expect(ArchiveService.detectType(write('livre.epub', zipBytes())),
        ArchiveType.zip);
    expect(ArchiveService.detectType(write('app.apk', zipBytes())),
        ArchiveType.jar);
    // Mal nommé : c'est le contenu qui compte.
    expect(ArchiveService.detectType(write('photo.jpg', zipBytes())),
        ArchiveType.zip);
  });

  test('TAR sans extension, TAR compressés', () {
    expect(ArchiveService.detectType(write('sauvegarde', tarBytes())),
        ArchiveType.tar);
    final gz = const arc.GZipEncoder().encodeBytes(tarBytes());
    expect(ArchiveService.detectType(write('s.tar.gz', gz)), ArchiveType.tarGz);
    expect(ArchiveService.detectType(write('s.tgz', gz)), ArchiveType.tarGz);
    expect(ArchiveService.detectType(write('notes.gz', gz)), ArchiveType.gz);
    final bz = arc.BZip2Encoder().encodeBytes(tarBytes());
    expect(
        ArchiveService.detectType(write('s.tar.bz2', bz)), ArchiveType.tarBz2);
  });

  test('signatures 7z et RAR', () {
    expect(
        ArchiveService.detectType(
            write('x.bin', [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 4])),
        ArchiveType.sevenZip);
    expect(
        ArchiveService.detectType(
            write('y.dat', [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])),
        ArchiveType.rar);
  });

  test('fichier absent ou sans signature connue : l\'extension', () {
    expect(ArchiveService.detectType(p.join(sandbox.path, 'absent.zip')),
        ArchiveType.zip);
    expect(ArchiveService.detectType(write('texte.txt', 'bonjour'.codeUnits)),
        ArchiveType.unknown);
  });
}
