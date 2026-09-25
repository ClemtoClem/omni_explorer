/// @file vault_repository.dart
/// @brief Fichier du coffre-fort : création, ouverture, sauvegarde,
/// changement de mot de passe, sauvegarde de secours.
///
/// - Emplacement : dossier privé de l'application (inaccessible aux autres
///   applications sur Android ; exclu de la sauvegarde Android depuis P0.7).
/// - Chaque sauvegarde copie d'abord la version actuelle dans `.bak`, puis
///   écrit la nouvelle de façon atomique : une interruption laisse toujours
///   un fichier complet, et un fichier endommagé peut être remplacé par la
///   version précédente.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart';

import '../../../core/utils/atomic_write.dart';
import '../models/vault_entry.dart';
import '../models/vault_errors.dart';
import 'vault_crypto.dart';

/// Coffre ouvert : clés en mémoire native (effacées par [dispose]) et
/// contenu déchiffré.
class UnlockedVault {
  SecureKey _kek;
  SecureKey _dek;
  KdfParams _kdf;
  VaultContent content;

  UnlockedVault._(this._kek, this._dek, this._kdf, this.content);

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Efface les clés de la mémoire et oublie le contenu.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _kek.dispose();
    _dek.dispose();
    content = VaultContent.empty;
  }
}

class VaultRepository {
  final VaultCrypto crypto;
  final String directory;

  VaultRepository(this.crypto, this.directory);

  static const String fileName = 'vault.omnivault';

  File get _file => File(p.join(directory, fileName));
  File get _backup => File(p.join(directory, '$fileName.bak'));

  bool get exists => _file.existsSync();
  bool get hasBackup => _backup.existsSync();

  SodiumSumo get _sodium => crypto.sodium;

  /// Règles du mot de passe maître ; `null` s'il est acceptable.
  static String? validatePassword(String password) {
    if (password.length < VaultCrypto.minPasswordLength) {
      return 'Au moins ${VaultCrypto.minPasswordLength} caractères '
          '(12 ou plus recommandés).';
    }
    if (password.trim().isEmpty) return 'Le mot de passe est vide.';
    return null;
  }

  // ── Création / ouverture ────────────────────────────────────────────────

  /// Crée un coffre vide protégé par [password]. Refuse d'écraser un coffre
  /// existant.
  Future<UnlockedVault> create(String password) async {
    final invalid = validatePassword(password);
    if (invalid != null) throw WeakPasswordException(invalid);
    if (exists) {
      throw const VaultCorruptedException('un coffre existe déjà');
    }
    await _ensureDirectory();
    final kdf = crypto.newKdfParams();
    final kek = await crypto.deriveKey(password, kdf);
    final vault =
        UnlockedVault._(kek, crypto.newDataKey(), kdf, VaultContent.empty);
    try {
      await _write(vault, VaultContent.empty, backupFirst: false);
    } catch (_) {
      vault.dispose();
      rethrow;
    }
    return vault;
  }

  /// Ouvre le coffre avec [password]. Avec [fromBackup], ouvre la version
  /// précédente (`.bak`) : utile si le fichier principal est endommagé.
  Future<UnlockedVault> unlock(String password,
      {bool fromBackup = false}) async {
    final source = fromBackup ? _backup : _file;
    final Uint8List bytes;
    try {
      bytes = await source.readAsBytes();
    } on FileSystemException {
      throw const VaultCorruptedException('fichier illisible');
    }
    final file = crypto.parse(bytes);
    final kek = await crypto.deriveKey(password, file.kdf);
    SecureKey? dek;
    try {
      dek = crypto.unwrapDataKey(file, kek);
      final content = crypto.openContent(file, dek);
      return UnlockedVault._(kek, dek, file.kdf, content);
    } catch (_) {
      kek.dispose();
      dek?.dispose();
      rethrow;
    }
  }

  // ── Sauvegarde ──────────────────────────────────────────────────────────

  /// Enregistre [content] dans le coffre ouvert [vault]. En cas d'échec
  /// (stockage plein…), le fichier précédent reste intact et [vault.content]
  /// n'est pas modifié.
  Future<void> save(UnlockedVault vault, VaultContent content) async {
    _checkOpen(vault);
    await _write(vault, content, backupFirst: true);
    vault.content = content;
  }

  /// Remplace le fichier principal par le contenu du coffre ouvert depuis la
  /// sauvegarde (après un [unlock] avec `fromBackup`).
  Future<void> restoreFromBackup(UnlockedVault vault) async {
    _checkOpen(vault);
    // Pas de copie du fichier principal endommagé par-dessus la sauvegarde.
    await _write(vault, vault.content, backupFirst: false);
  }

  /// Change le mot de passe maître. Sel, KEK **et** DEK sont renouvelés : un
  /// ancien fichier et l'ancien mot de passe ne permettent pas de lire les
  /// versions suivantes.
  Future<void> changePassword(
      UnlockedVault vault, String current, String next) async {
    _checkOpen(vault);
    final invalid = validatePassword(next);
    if (invalid != null) throw WeakPasswordException(invalid);

    // Vérifie le mot de passe actuel avec les paramètres du coffre ouvert.
    final check = await crypto.deriveKey(current, vault._kdf);
    try {
      final same = check.runUnlockedSync(
          (a) => vault._kek.runUnlockedSync((b) => _sodium.memcmp(a, b)));
      if (!same) throw const WrongPasswordException();
    } finally {
      check.dispose();
    }

    final kdf = crypto.newKdfParams();
    final kek = await crypto.deriveKey(next, kdf);
    final dek = crypto.newDataKey();
    final candidate = UnlockedVault._(kek, dek, kdf, vault.content);
    try {
      await _write(candidate, vault.content, backupFirst: true);
    } catch (_) {
      candidate.dispose();
      rethrow;
    }
    // Le coffre ouvert adopte les nouvelles clés ; les anciennes sont effacées.
    vault._kek.dispose();
    vault._dek.dispose();
    vault
      .._kek = kek
      .._dek = dek
      .._kdf = kdf;
  }

  /// Supprime définitivement le coffre et sa sauvegarde.
  Future<void> deleteVault() async {
    for (final f in [_file, _backup]) {
      if (f.existsSync()) await f.delete();
    }
  }

  // ── Interne ─────────────────────────────────────────────────────────────

  Future<void> _write(UnlockedVault vault, VaultContent content,
      {required bool backupFirst}) async {
    final bytes = crypto.seal(
        content: content, dek: vault._dek, kek: vault._kek, kdf: vault._kdf);
    if (backupFirst && _file.existsSync()) {
      await AtomicWrite.bytes(_backup.path, await _file.readAsBytes());
    }
    await AtomicWrite.bytes(_file.path, bytes);
  }

  Future<void> _ensureDirectory() async {
    final dir = Directory(directory);
    if (dir.existsSync()) return;
    await dir.create(recursive: true);
    if (!kIsWeb && Platform.isLinux) {
      // Dossier réservé à l'utilisateur (Android isole déjà les données).
      // Appel synchrone : exécuté une seule fois, à la création.
      final r = Process.runSync('chmod', ['700', directory]);
      if (r.exitCode != 0) debugPrint('[Vault] chmod 700 impossible');
    }
  }

  void _checkOpen(UnlockedVault vault) {
    if (vault.isDisposed) {
      throw StateError('Coffre verrouillé : opération impossible.');
    }
  }
}
