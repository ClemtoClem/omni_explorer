import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/core/services/settings_service.dart';

/// Stockage sécurisé en panne : chaque appel échoue.
class _BrokenStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<dynamic>.error(PlatformException(code: 'unavailable'));
}

/// Stockage sécurisé muet : aucun appel ne se termine.
class _HangingStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<dynamic>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = SettingsService.sshPasswordSecretKey;
  final defaultStorage = SettingsService.secureStorage;
  final defaultTimeout = SettingsService.secureStorageTimeout;

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() {
    SettingsService.secureStorage = defaultStorage;
    SettingsService.secureStorageTimeout = defaultTimeout;
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('migre le mot de passe en clair puis l\'efface des préférences',
      () async {
    SharedPreferences.setMockInitialValues(
        {AppConstants.prefSshPassword: 'secret'});

    final s = SettingsService();
    await s.init();

    expect(s.sshPassword, 'secret');
    expect((await prefs()).containsKey(AppConstants.prefSshPassword), isFalse);
    expect(await const FlutterSecureStorage().read(key: key), 'secret');
  });

  test('ancien mot de passe vide : clé en clair simplement retirée', () async {
    SharedPreferences.setMockInitialValues({AppConstants.prefSshPassword: ''});

    final s = SettingsService();
    await s.init();

    expect(s.sshPassword, '');
    expect((await prefs()).containsKey(AppConstants.prefSshPassword), isFalse);
    expect(await const FlutterSecureStorage().read(key: key), isNull);
  });

  test('lit le mot de passe déjà présent dans le stockage sécurisé', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({key: 'déjà là'});

    final s = SettingsService();
    await s.init();

    expect(s.sshPassword, 'déjà là');
  });

  test('setSshPassword écrit dans le stockage sécurisé, jamais en clair',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService();
    await s.init();

    await s.setSshPassword('nouveau');
    expect(await const FlutterSecureStorage().read(key: key), 'nouveau');
    final p = await prefs();
    expect(p.getKeys().map(p.get), isNot(contains('nouveau')));

    await s.setSshPassword('');
    expect(await const FlutterSecureStorage().read(key: key), isNull);
  });

  test('stockage en panne : l\'ancienne valeur est conservée, pas perdue',
      () async {
    SharedPreferences.setMockInitialValues(
        {AppConstants.prefSshPassword: 'secret'});
    SettingsService.secureStorage = _BrokenStorage();

    final s = SettingsService();
    await s.init();

    expect(s.sshPassword, 'secret');
    // Pas encore migrée : elle reste là pour une nouvelle tentative.
    expect((await prefs()).getString(AppConstants.prefSshPassword), 'secret');
    await expectLater(s.setSshPassword('x'), throwsA(isA<PlatformException>()));
  });

  test('stockage muet : le démarrage n\'est pas bloqué', () async {
    SharedPreferences.setMockInitialValues(
        {AppConstants.prefSshPassword: 'secret'});
    SettingsService.secureStorage = _HangingStorage();
    SettingsService.secureStorageTimeout = const Duration(milliseconds: 50);

    final s = SettingsService();
    await s.init().timeout(const Duration(seconds: 5));

    expect(s.sshPassword, 'secret');
    expect((await prefs()).getString(AppConstants.prefSshPassword), 'secret');
  });
}
