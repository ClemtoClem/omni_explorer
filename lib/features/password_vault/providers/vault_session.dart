/// @file vault_session.dart
/// @brief État du coffre-fort pour l'interface : absent, verrouillé ou
/// ouvert ; opérations sur les entrées ; verrouillage automatique.
///
/// Verrouillage automatique :
/// - après [inactivityTimeout] sans interaction ([touch]) ;
/// - [backgroundTimeout] après le passage de l'application en arrière-plan
///   (le temps d'aller coller un mot de passe dans une autre application) ;
/// - immédiatement si l'application se termine.
/// Verrouiller efface les clés de la mémoire et vide le presse-papiers.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import '../models/vault_entry.dart';
import '../models/vault_errors.dart';
import '../services/secure_clipboard.dart';
import '../services/vault_crypto.dart';
import '../services/vault_repository.dart';

enum VaultStatus {
  /// Initialisation (chargement de libsodium, recherche du coffre).
  loading,

  /// Aucun coffre : proposer d'en créer un.
  absent,

  locked,
  unlocked,

  /// Le coffre ne peut pas être utilisé sur cet appareil ([initError]).
  unavailable,
}

class VaultSession extends ChangeNotifier with WidgetsBindingObserver {
  final Future<VaultRepository> Function() _repositoryFactory;
  final SecureClipboard clipboard;
  final Duration inactivityTimeout;
  final Duration backgroundTimeout;

  VaultSession({
    Future<VaultRepository> Function()? repositoryFactory,
    SecureClipboard? clipboard,
    this.inactivityTimeout = const Duration(minutes: 5),
    this.backgroundTimeout = const Duration(seconds: 60),
  })  : _repositoryFactory = repositoryFactory ?? defaultRepository,
        clipboard = clipboard ?? SecureClipboard() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Coffre de l'application : libsodium et dossier privé.
  static Future<VaultRepository> defaultRepository() async {
    final sodium = await SodiumSumoInit.init();
    final support = await getApplicationSupportDirectory();
    return VaultRepository(VaultCrypto(sodium), p.join(support.path, 'vault'));
  }

  VaultStatus _status = VaultStatus.loading;
  VaultStatus get status => _status;

  /// Raison de [VaultStatus.unavailable].
  String? initError;

  /// Vrai pendant une opération longue (dérivation de clé, sauvegarde).
  bool busy = false;

  VaultRepository? _repo;
  UnlockedVault? _vault;
  Timer? _inactivityTimer;
  Timer? _backgroundTimer;
  Future<void>? _initializing;
  final _uuid = const Uuid();

  List<VaultEntry> get entries =>
      List.unmodifiable(_vault?.content.entries ?? const []);

  bool get hasBackup => _repo?.hasBackup ?? false;

  // ── Cycle de vie ────────────────────────────────────────────────────────

  /// Charge libsodium et détecte le coffre (une seule fois).
  Future<void> ensureInitialized() => _initializing ??= _init();

  Future<void> _init() async {
    try {
      _repo = await _repositoryFactory();
      _status = _repo!.exists ? VaultStatus.locked : VaultStatus.absent;
    } catch (e) {
      debugPrint('[Vault] initialisation impossible : ${e.runtimeType}');
      initError = 'La bibliothèque de chiffrement n\'a pas pu être chargée.';
      _status = VaultStatus.unavailable;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundTimer?.cancel();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_vault != null && !(_backgroundTimer?.isActive ?? false)) {
          _backgroundTimer = Timer(backgroundTimeout, lock);
        }
      case AppLifecycleState.detached:
        lock();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lock();
    clipboard.dispose();
    super.dispose();
  }

  // ── Ouverture / fermeture ───────────────────────────────────────────────

  Future<void> create(String password) =>
      _run(() async => _opened(await _repo!.create(password)));

  /// Ouvre le coffre. Avec [fromBackup], ouvre la version précédente et la
  /// réinstalle comme fichier principal (fichier principal endommagé).
  Future<void> unlock(String password, {bool fromBackup = false}) =>
      _run(() async {
        final vault = await _repo!.unlock(password, fromBackup: fromBackup);
        if (fromBackup) {
          try {
            await _repo!.restoreFromBackup(vault);
          } catch (_) {
            vault.dispose();
            rethrow;
          }
        }
        _opened(vault);
      });

  void _opened(UnlockedVault vault) {
    _vault?.dispose();
    _vault = vault;
    _status = VaultStatus.unlocked;
    touch();
  }

  /// Verrouille : clés effacées de la mémoire, presse-papiers vidé.
  void lock() {
    _inactivityTimer?.cancel();
    _backgroundTimer?.cancel();
    final wasOpen = _vault != null;
    _vault?.dispose();
    _vault = null;
    unawaited(clipboard.clearNow());
    if (wasOpen) {
      _status = VaultStatus.locked;
      notifyListeners();
    }
  }

  /// Signale une interaction : repousse le verrouillage pour inactivité.
  void touch() {
    if (_vault == null) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityTimeout, lock);
  }

  // ── Entrées ─────────────────────────────────────────────────────────────

  /// Ajoute une entrée et l'enregistre.
  Future<VaultEntry> addEntry({
    required String title,
    String username = '',
    String password = '',
    String url = '',
    String notes = '',
  }) async {
    final now = DateTime.now().toUtc();
    final entry = VaultEntry(
      id: _uuid.v4(),
      title: title,
      username: username,
      password: password,
      url: url,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await _saveEntries([...entries, entry]);
    return entry;
  }

  /// Remplace l'entrée de même identifiant et l'enregistre.
  Future<void> updateEntry(VaultEntry entry) async {
    final list = [...entries];
    final i = list.indexWhere((e) => e.id == entry.id);
    if (i < 0) throw StateError('Entrée introuvable.');
    list[i] = entry.copyWith(updatedAt: DateTime.now().toUtc());
    await _saveEntries(list);
  }

  Future<void> deleteEntry(String id) =>
      _saveEntries(entries.where((e) => e.id != id).toList());

  /// Enregistre ; en cas d'échec, le contenu en mémoire reste l'ancien.
  Future<void> _saveEntries(List<VaultEntry> list) => _run(() async {
        final vault = _requireOpen();
        await _repo!.save(vault, VaultContent(list));
        touch();
      });

  // ── Mot de passe maître / suppression ───────────────────────────────────

  Future<void> changePassword(String current, String next) => _run(() async {
        await _repo!.changePassword(_requireOpen(), current, next);
        touch();
      });

  /// Supprime définitivement le coffre (et sa sauvegarde).
  Future<void> deleteVault() => _run(() async {
        lock();
        await _repo!.deleteVault();
        _status = VaultStatus.absent;
      });

  // ── Interne ─────────────────────────────────────────────────────────────

  UnlockedVault _requireOpen() {
    final vault = _vault;
    if (vault == null) throw StateError('Coffre verrouillé.');
    return vault;
  }

  /// Exécute [body] en signalant l'occupation ; les erreurs du coffre
  /// ([VaultException]) sont propagées telles quelles pour l'interface.
  Future<void> _run(Future<void> Function() body) async {
    busy = true;
    notifyListeners();
    try {
      await body();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
