/// Explorateur : filtres complets (raccourcis), recherche dans les
/// sous-dossiers, tri imposé.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/core/models/file_filter.dart';
import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/features/file_explorer/providers/file_explorer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late String root;
  late FileExplorerProvider prov;
  late SettingsService settings;

  void write(String rel, {DateTime? modified}) {
    final f = File(p.join(root, rel))..createSync(recursive: true);
    f.writeAsStringSync(rel);
    if (modified != null) f.setLastModifiedSync(modified);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    sandbox = await Directory.systemTemp.createTemp('explorer_search_test_');
    root = sandbox.path;
    write('a.pdf', modified: DateTime(2020));
    write('notes.txt');
    write('docs/b.pdf', modified: DateTime(2024));
    write('docs/2026/c.PDF', modified: DateTime(2026));
    write('docs/photo.jpg');
    write('.cache/hidden.pdf');
    settings = SettingsService();
    await settings.init();
    prov = FileExplorerProvider(settings)..debugSetStorageRoots([root]);
    await prov.navigateTo(root, addToHistory: false);
  });

  tearDown(() async {
    prov.dispose();
    await sandbox.delete(recursive: true);
  });

  Future<void> searchDone() async {
    for (var i = 0; i < 200 && prov.searching; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(prov.searching, isFalse);
  }

  List<String> shown() =>
      prov.entries.map((e) => p.relative(e.path, from: root)).toList();

  test('sans sous-dossiers : seul le dossier courant est filtré', () {
    prov.applyFilter(const FileFilter(extensions: {'pdf'}));
    expect(shown(), ['a.pdf']);
  });

  test('avec sous-dossiers : tous les PDF, fichiers cachés exclus', () async {
    prov.applyFilter(const FileFilter(extensions: {'pdf'}, recursive: true));
    expect(prov.showsSearchResults, isTrue);
    await searchDone();
    expect(
        shown(), unorderedEquals(['a.pdf', 'docs/b.pdf', 'docs/2026/c.PDF']));

    // Afficher les fichiers cachés relance la recherche.
    await settings.setShowHidden(true);
    await searchDone();
    expect(shown(), contains('.cache/hidden.pdf'));
    await settings.setShowHidden(false);
  });

  test('tri imposé par le filtre : plus récent d\'abord', () async {
    prov.applyFilter(const FileFilter(
      extensions: {'pdf'},
      recursive: true,
      sortMode: SortMode.date,
      sortAscending: false,
    ));
    await searchDone();
    expect(shown(), ['docs/2026/c.PDF', 'docs/b.pdf', 'a.pdf']);
    expect(prov.effectiveSortMode, SortMode.date);

    // Le menu de tri reprend la main : retour au tri des préférences.
    prov.clearSortOverride();
    expect(prov.effectiveSortMode, settings.sortMode);
  });

  test('critère retiré : retour au contenu du dossier', () async {
    prov.applyFilter(const FileFilter(query: 'photo', recursive: true));
    await searchDone();
    expect(shown(), ['docs/photo.jpg']);

    prov.clearFilter();
    expect(prov.showsSearchResults, isFalse);
    expect(shown(), unorderedEquals(['docs', 'a.pdf', 'notes.txt']));
  });

  test('un dossier illisible n\'arrête pas la recherche', () async {
    if (Platform.isWindows) return;
    write('locked/x.pdf');
    final locked = p.join(root, 'locked');
    await Process.run('chmod', ['000', locked]);
    try {
      prov.applyFilter(const FileFilter(extensions: {'pdf'}, recursive: true));
      await searchDone();
      expect(shown(), containsAll(['a.pdf', 'docs/b.pdf', 'docs/2026/c.PDF']));
    } finally {
      await Process.run('chmod', ['755', locked]);
    }
  });

  test('plafond de résultats signalé', () async {
    for (var i = 0; i < FileExplorerProvider.maxSearchResults + 5; i++) {
      write('many/f$i.log');
    }
    prov.applyFilter(const FileFilter(extensions: {'log'}, recursive: true));
    await searchDone();
    expect(prov.searchTruncated, isTrue);
    expect(prov.entries.length, FileExplorerProvider.maxSearchResults);
  });
}
