/// @file vault_crypto.dart
/// @brief Format et chiffrement du fichier du coffre-fort (libsodium).
///
/// ## Clés
/// - **KEK** (clé de chiffrement de clé) : dérivée du mot de passe maître par
///   Argon2id (`crypto_pwhash`), avec un sel aléatoire. Elle ne sert qu'à
///   chiffrer la DEK.
/// - **DEK** (clé de données) : 32 octets aléatoires, qui chiffrent le
///   contenu. Changer de mot de passe maître régénère sel, KEK et DEK.
///
/// ## Fichier (format 1)
/// ```
/// | "OMNIVLT1" (8 o) | longueur de l'en-tête (uint32 BE) | en-tête JSON | contenu chiffré |
/// ```
/// L'en-tête (UTF-8) contient les paramètres Argon2id, le sel, la DEK chiffrée
/// et le nonce du contenu, en base64. Le contenu est chiffré en
/// XChaCha20-Poly1305 avec la DEK et un nonce aléatoire (24 o) renouvelé à
/// chaque sauvegarde ; **tout ce qui précède** (magic, longueur, en-tête) est
/// authentifié comme données associées : la moindre modification de l'en-tête
/// ou du contenu est détectée.
///
/// Un numéro de format plus récent que [VaultCrypto.formatVersion] est refusé
/// ([VaultTooNewException]) au lieu d'être mal interprété.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';

import '../models/vault_entry.dart';
import '../models/vault_errors.dart';

/// Paramètres d'Argon2id, conservés dans l'en-tête pour pouvoir les faire
/// évoluer sans rendre les anciens coffres illisibles.
class KdfParams {
  final int opsLimit;
  final int memLimit;
  final Uint8List salt;

  const KdfParams({
    required this.opsLimit,
    required this.memLimit,
    required this.salt,
  });

  /// Réglage par défaut : 3 passes et 128 Mio (≈ 0,2 s sur PC, 1 à 2 s sur
  /// téléphone). 256 Mio risqueraient d'échouer sur les appareils modestes.
  static const int defaultOpsLimit = 3;
  static const int defaultMemLimit = 128 * 1024 * 1024;

  Map<String, Object?> toJson() => {
        'alg': 'argon2id13',
        'ops': opsLimit,
        'mem': memLimit,
        'salt': base64.encode(salt),
      };
}

/// Contenu d'un fichier de coffre dont la structure a été validée.
class VaultFile {
  final KdfParams kdf;
  final Uint8List wrapNonce;
  final Uint8List wrappedKey;
  final Uint8List payloadNonce;

  /// Magic + longueur + en-tête : données associées du contenu.
  final Uint8List authenticatedHeader;
  final Uint8List payload;

  const VaultFile({
    required this.kdf,
    required this.wrapNonce,
    required this.wrappedKey,
    required this.payloadNonce,
    required this.authenticatedHeader,
    required this.payload,
  });
}

class VaultCrypto {
  final SodiumSumo sodium;

  /// Réglages d'Argon2id pour les nouveaux coffres (réduits dans les tests).
  final int opsLimit;
  final int memLimit;

  /// Dérivation de clé dans un isolate (toujours en production). Les tests
  /// de widget la désactivent : un isolate lancé depuis leur horloge fictive
  /// ne rend jamais la main. Le chemin par isolate reste couvert par les
  /// tests unitaires.
  final bool useIsolate;

  VaultCrypto(
    this.sodium, {
    this.opsLimit = KdfParams.defaultOpsLimit,
    this.memLimit = KdfParams.defaultMemLimit,
    @visibleForTesting this.useIsolate = true,
  });

  static const int formatVersion = 1;

  /// Signature du fichier du coffre.
  static final Uint8List magic = Uint8List.fromList(utf8.encode('OMNIVLT1'));

  /// Signature d'un export (même format, même chiffrement) : un export ne
  /// peut pas être pris pour le coffre, ni l'inverse.
  static final Uint8List exportMagic =
      Uint8List.fromList(utf8.encode('OMNIEXP1'));

  /// Vrai si [bytes] commence par la signature [expected].
  static bool hasMagic(Uint8List bytes, Uint8List expected) {
    if (bytes.length < expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (bytes[i] != expected[i]) return false;
    }
    return true;
  }

  static const String _cipher = 'xchacha20poly1305-ietf';

  /// Taille maximale d'en-tête acceptée (protection contre un fichier forgé).
  static const int _maxHeaderBytes = 64 * 1024;

  /// Données associées de la DEK chiffrée : lient la clé à son usage.
  static final Uint8List _wrapAad =
      Uint8List.fromList(utf8.encode('omni-vault:dek:v1'));

  Aead get _aead => sodium.crypto.aeadXChaCha20Poly1305IETF;

  /// Longueur minimale d'un mot de passe maître.
  static const int minPasswordLength = 8;

  // ── Clés ────────────────────────────────────────────────────────────────

  KdfParams newKdfParams() => KdfParams(
        opsLimit: opsLimit,
        memLimit: memLimit,
        salt: sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes),
      );

  /// Nouvelle clé de données aléatoire.
  SecureKey newDataKey() => _aead.keygen();

  /// Dérive la KEK de [password] (Argon2id) dans un isolate : le calcul, long
  /// et gourmand en mémoire, ne bloque pas l'interface.
  Future<SecureKey> deriveKey(String password, KdfParams kdf) async {
    final keyBytes = _aead.keyBytes;
    final salt = kdf.salt;
    final ops = kdf.opsLimit;
    final mem = kdf.memLimit;
    final pw = utf8.encode(password);
    SecureKey derive(List<SecureKey> _, List<KeyPair> __) {
      final pwBytes = Int8List.fromList(pw);
      try {
        return sodium.crypto.pwhash.callRaw(
          outLen: keyBytes,
          password: pwBytes,
          salt: salt,
          opsLimit: ops,
          memLimit: mem,
          alg: CryptoPwhashAlgorithm.argon2id13,
        );
      } finally {
        pwBytes.fillRange(0, pwBytes.length, 0);
      }
    }

    try {
      return useIsolate
          ? await sodium.runIsolated(derive)
          : derive(const [], const []);
    } on SodiumException {
      throw const VaultKeyDerivationException();
    } finally {
      pw.fillRange(0, pw.length, 0);
    }
  }

  // ── Scellement ──────────────────────────────────────────────────────────

  /// Produit les octets du fichier : [content] chiffré avec [dek], et [dek]
  /// chiffrée avec [kek] (dérivée avec [kdf]). [signature] distingue le
  /// coffre ([magic]) d'un export ([exportMagic]).
  Uint8List seal({
    required VaultContent content,
    required SecureKey dek,
    required SecureKey kek,
    required KdfParams kdf,
    Uint8List? signature,
  }) {
    final head = signature ?? magic;
    final wrapNonce = sodium.randombytes.buf(_aead.nonceBytes);
    final dekBytes = dek.extractBytes();
    final Uint8List wrappedKey;
    try {
      wrappedKey = _aead.encrypt(
          message: dekBytes,
          nonce: wrapNonce,
          key: kek,
          additionalData: _wrapAad);
    } finally {
      dekBytes.fillRange(0, dekBytes.length, 0);
    }

    final payloadNonce = sodium.randombytes.buf(_aead.nonceBytes);
    final header = utf8.encode(jsonEncode({
      'format': formatVersion,
      'kdf': kdf.toJson(),
      'wrap': {
        'alg': _cipher,
        'nonce': base64.encode(wrapNonce),
        'key': base64.encode(wrappedKey),
      },
      'payload': {'alg': _cipher, 'nonce': base64.encode(payloadNonce)},
    }));

    final prefix = BytesBuilder(copy: false)
      ..add(head)
      ..add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List())
      ..add(header);
    final aad = prefix.toBytes();

    final plain = utf8.encode(jsonEncode(content.toJson()));
    try {
      final cipher = _aead.encrypt(
          message: plain, nonce: payloadNonce, key: dek, additionalData: aad);
      return (BytesBuilder(copy: false)
            ..add(aad)
            ..add(cipher))
          .toBytes();
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  // ── Ouverture ───────────────────────────────────────────────────────────

  /// Valide la structure de [bytes] sans rien déchiffrer. [signature] :
  /// [magic] (coffre, par défaut) ou [exportMagic].
  VaultFile parse(Uint8List bytes, {Uint8List? signature}) {
    final head = signature ?? magic;
    final headerStart = head.length + 4;
    if (bytes.length < headerStart) {
      throw const VaultCorruptedException('fichier trop court');
    }
    if (!hasMagic(bytes, head)) {
      throw const VaultCorruptedException('signature absente');
    }
    final headerLen =
        ByteData.sublistView(bytes, head.length, headerStart).getUint32(0);
    if (headerLen == 0 ||
        headerLen > _maxHeaderBytes ||
        headerStart + headerLen > bytes.length) {
      throw const VaultCorruptedException('longueur d\'en-tête invalide');
    }
    final headerEnd = headerStart + headerLen;

    final Object? header;
    try {
      header = jsonDecode(utf8.decode(bytes.sublist(headerStart, headerEnd)));
    } on FormatException {
      throw const VaultCorruptedException('en-tête illisible');
    }
    if (header is! Map<String, Object?>) {
      throw const VaultCorruptedException('en-tête invalide');
    }
    final format = header['format'];
    if (format is! int || format < 1) {
      throw const VaultCorruptedException('version de format invalide');
    }
    if (format > formatVersion) throw const VaultTooNewException();

    final kdf = _map(header, 'kdf');
    final wrap = _map(header, 'wrap');
    final payload = _map(header, 'payload');
    if (kdf['alg'] != 'argon2id13' ||
        wrap['alg'] != _cipher ||
        payload['alg'] != _cipher) {
      throw const VaultCorruptedException('algorithme inconnu');
    }
    final ops = kdf['ops'];
    final mem = kdf['mem'];
    final pw = sodium.crypto.pwhash;
    if (ops is! int ||
        mem is! int ||
        ops < pw.opsLimitMin ||
        ops > pw.opsLimitMax ||
        mem < pw.memLimitMin ||
        mem > pw.memLimitMax) {
      throw const VaultCorruptedException('paramètres Argon2id invalides');
    }

    return VaultFile(
      kdf: KdfParams(
          opsLimit: ops,
          memLimit: mem,
          salt: _bytes(kdf, 'salt', length: pw.saltBytes)),
      wrapNonce: _bytes(wrap, 'nonce', length: _aead.nonceBytes),
      wrappedKey: _bytes(wrap, 'key', length: _aead.keyBytes + _aead.aBytes),
      payloadNonce: _bytes(payload, 'nonce', length: _aead.nonceBytes),
      authenticatedHeader: Uint8List.sublistView(bytes, 0, headerEnd),
      payload: Uint8List.sublistView(bytes, headerEnd),
    );
  }

  /// Déchiffre la DEK avec [kek]. Échec : mauvais mot de passe.
  SecureKey unwrapDataKey(VaultFile file, SecureKey kek) {
    final Uint8List dekBytes;
    try {
      dekBytes = _aead.decrypt(
          cipherText: file.wrappedKey,
          nonce: file.wrapNonce,
          key: kek,
          additionalData: _wrapAad);
    } on SodiumException {
      throw const WrongPasswordException();
    }
    try {
      return sodium.secureCopy(dekBytes);
    } finally {
      dekBytes.fillRange(0, dekBytes.length, 0);
    }
  }

  /// Déchiffre le contenu avec [dek]. Échec : fichier modifié ou endommagé
  /// (la DEK, elle, a été authentifiée par [unwrapDataKey]).
  VaultContent openContent(VaultFile file, SecureKey dek) {
    final Uint8List plain;
    try {
      plain = _aead.decrypt(
          cipherText: file.payload,
          nonce: file.payloadNonce,
          key: dek,
          additionalData: file.authenticatedHeader);
    } on SodiumException {
      throw const VaultCorruptedException('contenu non authentifié');
    }
    try {
      return VaultContent.fromJson(jsonDecode(utf8.decode(plain)));
    } on FormatException {
      throw const VaultCorruptedException('contenu illisible');
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  // ── Utilitaires ─────────────────────────────────────────────────────────

  static Map<String, Object?> _map(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is Map<String, Object?>) return v;
    throw VaultCorruptedException('en-tête : « $key » absent');
  }

  static Uint8List _bytes(Map<String, Object?> json, String key,
      {required int length}) {
    final v = json[key];
    if (v is! String) {
      throw VaultCorruptedException('en-tête : « $key » absent');
    }
    final Uint8List decoded;
    try {
      decoded = base64.decode(v);
    } on FormatException {
      throw VaultCorruptedException('en-tête : « $key » illisible');
    }
    if (decoded.length != length) {
      throw VaultCorruptedException('en-tête : « $key » de taille invalide');
    }
    return decoded;
  }
}
