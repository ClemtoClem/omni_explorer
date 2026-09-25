import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/features/archive/models/archive_tree.dart';

RawArchiveEntry f(String name, [int size = 1]) =>
    RawArchiveEntry(name: name, isDirectory: false, size: size);
RawArchiveEntry d(String name) =>
    RawArchiveEntry(name: name, isDirectory: true);

List<String> names(Iterable<ArchiveNode> nodes) =>
    nodes.map((n) => n.isDirectory ? '${n.name}/' : n.name).toList();

void main() {
  test('dossiers implicites : le contenu reste accessible', () {
    // Archive sans aucune entrée « dossier ».
    final t = ArchiveTree.fromEntries([f('a/b/c.txt'), f('a/d.txt')]);

    expect(names(t.children('')), ['a/']);
    expect(names(t.children('a')), ['b/', 'd.txt']);
    expect(names(t.children('a/b')), ['c.txt']);
    expect(t['a']!.implicit, isTrue);
  });

  test('chaque fichier reste sous son dossier, dossiers d\'abord', () {
    final t = ArchiveTree.fromEntries([
      f('zeta.txt'),
      f('src/main.dart'),
      f('Alpha.txt'),
      d('lib/'),
      f('lib/x.dart'),
    ]);
    expect(names(t.children('')), ['lib/', 'src/', 'Alpha.txt', 'zeta.txt']);
    expect(names(t.children('src')), ['main.dart']);
  });

  test('chemins normalisés : ./, /, \\, //, / final', () {
    final t = ArchiveTree.fromEntries([
      f('./a/x.txt'),
      f('/a/y.txt'),
      f(r'a\z.txt'),
      f('a//w.txt'),
      d('a/'),
    ]);
    expect(names(t.children('')), ['a/']);
    expect(names(t.children('a')), ['w.txt', 'x.txt', 'y.txt', 'z.txt']);
    expect(t['a']!.implicit, isFalse); // entrée explicite conservée
  });

  test('entrée « dossier » en double ou après son contenu', () {
    final t = ArchiveTree.fromEntries([f('a/x.txt'), d('a/'), d('a/')]);
    expect(names(t.children('')), ['a/']);
    expect(names(t.children('a')), ['x.txt']);
  });

  test('recherche, descendants, dossiers, totaux', () {
    final t = ArchiveTree.fromEntries(
        [f('a/Rapport.txt', 10), f('a/b/rapport-2.txt', 5), f('c.bin', 1)]);
    expect(t.search('RAPPORT').map((n) => n.path),
        ['a/Rapport.txt', 'a/b/rapport-2.txt']);
    expect(t.descendants('a').map((n) => n.path).toSet(),
        {'a/Rapport.txt', 'a/b', 'a/b/rapport-2.txt'});
    expect(t.directories, ['a', 'a/b']);
    expect(t.fileCount, 3);
    expect(t.totalSize, 16);
  });

  test('les segments « .. » restent visibles', () {
    final t = ArchiveTree.fromEntries([f('../evil.txt')]);
    expect(names(t.children('')), ['../']);
  });
}
