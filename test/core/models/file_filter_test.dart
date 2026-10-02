/// Filtre de recherche des raccourcis et de l'explorateur.

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/core/models/file_filter.dart';
import 'package:omni_explorer/core/models/file_item.dart';

void main() {
  FileItem item(String name, {bool dir = false, FileCategory? cat}) => FileItem(
        path: '/x/$name',
        name: name,
        isDirectory: dir,
        size: 0,
        modified: DateTime(2026),
        category: cat ?? (dir ? FileCategory.folder : FileCategory.binary),
        isHidden: name.startsWith('.'),
      );

  test('nom, catégories et extensions se cumulent', () {
    const f = FileFilter(
      query: 'rapport',
      categories: {FileCategory.pdf},
      extensions: {'pdf'},
    );
    expect(f.accepts(item('Rapport 2026.pdf', cat: FileCategory.pdf)), isTrue);
    expect(f.accepts(item('facture.pdf', cat: FileCategory.pdf)), isFalse);
    expect(f.accepts(item('rapport.docx', cat: FileCategory.text)), isFalse);
  });

  test('un dossier passe les catégories seulement si « Dossiers » est choisi',
      () {
    const images = FileFilter(categories: {FileCategory.image});
    const withFolders =
        FileFilter(categories: {FileCategory.image, FileCategory.folder});
    expect(images.accepts(item('Vacances', dir: true)), isFalse);
    expect(withFolders.accepts(item('Vacances', dir: true)), isTrue);
    // Les extensions ne visent que des fichiers.
    expect(
        const FileFilter(extensions: {'pdf'}).accepts(item('pdf', dir: true)),
        isFalse);
  });

  test('saisie des extensions tolérante', () {
    expect(FileFilter.parseExtensions(' .PDF, docx;odt  .md '),
        {'pdf', 'docx', 'odt', 'md'});
    expect(FileFilter.parseExtensions('  ,  '), isEmpty);
  });

  test('sérialisation aller-retour, valeurs inconnues ignorées', () {
    const f = FileFilter(
      query: 'x',
      categories: {FileCategory.image, FileCategory.video},
      extensions: {'jpg'},
      recursive: true,
      sortMode: SortMode.date,
      sortAscending: false,
    );
    expect(FileFilter.fromMap(f.toMap()), f);
    expect(FileFilter.none.toMap(), isEmpty);

    final odd = FileFilter.fromMap({
      'categories': ['image', 'hologramme'],
      'sort': 'couleur',
    });
    expect(odd.categories, {FileCategory.image});
    expect(odd.sortMode, isNull);
  });

  test('le raccourci garde son filtre (et les anciens se relisent)', () {
    const s = ShortcutItem(
      id: '1',
      name: 'PDF',
      path: '/d',
      filter: FileFilter(extensions: {'pdf'}, recursive: true),
    );
    final back = ShortcutItem.fromMap(s.toMap());
    expect(back.filter, s.filter);
    expect(ShortcutItem.fromMap({'id': '2', 'name': 'a', 'path': '/a'}).filter,
        FileFilter.none);
  });

  test('résumé lisible', () {
    const f = FileFilter(
      categories: {FileCategory.pdf},
      extensions: {'pdf'},
      recursive: true,
      sortMode: SortMode.date,
      sortAscending: false,
    );
    expect(f.describe(), 'PDF · .pdf · sous-dossiers · tri date ↓');
    expect(FileFilter.none.isEmpty, isTrue);
    expect(const FileFilter(sortMode: SortMode.size).selectsNothing, isTrue);
  });
}
