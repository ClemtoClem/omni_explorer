import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/core/utils/file_naming.dart';

void main() {
  bool none(String _) => false;

  group('split', () {
    for (final (name, isDir, base, ext) in [
      ('rapport.txt', false, 'rapport', '.txt'),
      ('site.tar.gz', false, 'site', '.tar.gz'),
      ('SITE.TAR.XZ', false, 'SITE', '.TAR.XZ'),
      ('.bashrc', false, '.bashrc', ''),
      ('.config.json', false, '.config', '.json'),
      ('Makefile', false, 'Makefile', ''),
      ('fin.', false, 'fin.', ''),
      ('photos.2023', true, 'photos.2023', ''),
    ]) {
      test('« $name »', () {
        expect(FileNaming.split(name, isDirectory: isDir), (base, ext));
      });
    }
  });

  test('conflit : premier numéro libre', () {
    final taken = {'a.1.txt', 'a.2.txt'};
    expect(FileNaming.numbered('a.txt', taken.contains, isDirectory: false),
        'a.3.txt');
    expect(
        FileNaming.numbered('dossier', none, isDirectory: true), 'dossier.1');
    expect(FileNaming.numbered('site.tar.gz', none, isDirectory: false),
        'site.1.tar.gz');
  });

  test('duplication : .copy.N, et reprise depuis une copie', () {
    expect(FileNaming.copy('a.txt', none, isDirectory: false), 'a.copy.1.txt');
    final taken = {'a.copy.1.txt'};
    expect(FileNaming.copy('a.copy.1.txt', taken.contains, isDirectory: false),
        'a.copy.2.txt');
    expect(FileNaming.copy('src', none, isDirectory: true), 'src.copy.1');
  });

  test('un numéro de conflit n\'est pas pris pour une copie', () {
    expect(FileNaming.copy('version.2.txt', none, isDirectory: false),
        'version.2.copy.1.txt');
  });
}
