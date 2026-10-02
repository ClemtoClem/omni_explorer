/// Explorateur : filtre du mode sélecteur et navigation entre stockages.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/features/file_explorer/explorer_picker.dart';
import 'package:omni_explorer/features/file_explorer/providers/file_explorer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late String internal, sd;
  late FileExplorerProvider prov;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    sandbox = await Directory.systemTemp.createTemp('explorer_picker_test_');
    internal = p.join(sandbox.path, 'internal');
    sd = p.join(sandbox.path, 'sd');
    await Directory(p.join(internal, 'Movies')).create(recursive: true);
    await Directory(p.join(sd, 'DCIM')).create(recursive: true);
    File(p.join(internal, 'clip.mp4')).writeAsStringSync('v');
    File(p.join(internal, 'song.mp3')).writeAsStringSync('a');
    File(p.join(internal, 'export.omnivault')).writeAsStringSync('x');
    final settings = SettingsService();
    await settings.init();
    prov = FileExplorerProvider(settings)..debugSetStorageRoots([internal, sd]);
    await prov.navigateTo(internal, addToHistory: false);
  });

  tearDown(() async {
    prov.dispose();
    await sandbox.delete(recursive: true);
  });

  List<String> names() => prov.entries.map((e) => e.name).toList();

  test('le filtre du sélecteur masque les fichiers refusés, pas les dossiers',
      () {
    const videos = ExplorerPickRequest(
      mode: ExplorerPickMode.files,
      title: 't',
      categories: {FileCategory.video},
    );
    prov.setFileFilter(videos.accepts);
    expect(names(), unorderedEquals(['Movies', 'clip.mp4']));

    prov.setFileFilter(null);
    expect(names(), hasLength(4));
  });

  test('filtre par extension, insensible à la casse', () async {
    File(p.join(internal, 'OLD.OMNIVAULT')).writeAsStringSync('x');
    await prov.refresh();
    const vault = ExplorerPickRequest(
      mode: ExplorerPickMode.save,
      title: 't',
      extensions: {'omnivault'},
    );
    prov.setFileFilter(vault.accepts);
    expect(names(),
        unorderedEquals(['Movies', 'export.omnivault', 'OLD.OMNIVAULT']));
  });

  test('le mode dossier ne montre aucun fichier', () {
    const dir =
        ExplorerPickRequest(mode: ExplorerPickMode.directory, title: 't');
    prov.setFileFilter(dir.accepts);
    expect(names(), ['Movies']);
  });

  test('naviguer vers une carte SD bascule la racine sur la carte', () async {
    await prov.navigateTo(p.join(sd, 'DCIM'));
    expect(prov.currentPath, p.join(sd, 'DCIM'));
    expect(prov.rootPath, sd);

    // Retour arrière : on revient sur le stockage interne.
    await prov.undo();
    expect(prov.currentPath, internal);
    expect(prov.rootPath, internal);
  });

  test('un chemin hors de tout stockage est ramené à la racine', () async {
    await prov.navigateTo(p.join(sandbox.path, 'ailleurs'));
    expect(prov.currentPath, internal);
  });
}
