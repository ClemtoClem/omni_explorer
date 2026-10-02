/// Raccourcis de répertoire : défauts proposés une fois, ajout, modification,
/// ordre, retrait, persistance de l'icône et de la couleur.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/core/models/file_item.dart';
import 'package:omni_explorer/core/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<SettingsService> fresh() async {
    final s = SettingsService();
    await s.init();
    return s;
  }

  const defaults = [
    ShortcutItem(id: '', name: 'Images', path: '/s/DCIM', iconName: 'image'),
    ShortcutItem(id: '', name: 'Tout', path: '/s', iconName: 'folder_special'),
  ];

  test('les défauts sont ajoutés une seule fois, devant les favoris existants',
      () async {
    final s = await fresh();
    await s.addShortcut('Projets', '/s/Projets');
    await s.addShortcut('Photos', '/s/DCIM'); // même chemin qu'un défaut

    await s.seedDefaultShortcuts(defaults);
    expect(s.shortcuts.map((e) => e.name), ['Tout', 'Projets', 'Photos']);
    expect(s.shortcuts.map((e) => e.id).toSet(), hasLength(3));

    // Un défaut retiré ne revient pas.
    await s.removeShortcut(s.shortcuts.first.id);
    await s.seedDefaultShortcuts(defaults);
    expect(s.needsDefaultShortcuts, isFalse);
    expect(s.shortcuts.map((e) => e.name), ['Projets', 'Photos']);
  });

  test('ajout refusé pour un chemin déjà présent', () async {
    final s = await fresh();
    expect(await s.addShortcut('A', '/a'), isTrue);
    expect(await s.addShortcut('B', '/a'), isFalse);
    expect(s.shortcuts, hasLength(1));
  });

  test('modification : nom, chemin, icône et couleur sont persistés', () async {
    final s = await fresh();
    await s.addShortcut('A', '/a');
    await s.addShortcut('B', '/b');
    final a = s.shortcuts.first;

    expect(
        await s.updateShortcut(
            a.copyWith(path: '/b')), // chemin d'un autre raccourci
        isFalse);
    expect(
        await s.updateShortcut(a.copyWith(
            name: 'Musique', path: '/m', iconName: 'music', colorValue: 42)),
        isTrue);

    final reloaded = await fresh();
    final m = reloaded.shortcuts.first;
    expect((m.id, m.name, m.path, m.iconName, m.colorValue),
        (a.id, 'Musique', '/m', 'music', 42));
  });

  test('déplacement dans la liste, bornes comprises', () async {
    final s = await fresh();
    for (final n in ['a', 'b', 'c']) {
      await s.addShortcut(n, '/$n');
    }
    String order() => s.shortcuts.map((e) => e.name).join();

    await s.moveShortcut(s.shortcuts[2].id, -1);
    expect(order(), 'acb');
    await s.moveShortcut(s.shortcuts[0].id, -1); // déjà en tête
    expect(order(), 'acb');
    await s.moveShortcut(s.shortcuts[0].id, 5);
    expect(order(), 'cba');
  });

  test('les anciens favoris sans couleur se relisent', () async {
    SharedPreferences.setMockInitialValues({
      'shortcuts': '[{"id":"x","name":"Old","path":"/o","icon":null}]',
    });
    final s = await fresh();
    expect(s.shortcuts.single.colorValue, isNull);
    expect(s.shortcuts.single.name, 'Old');
  });
}
