import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:omni_explorer/features/password_vault/models/vault_entry.dart';
import 'package:omni_explorer/features/password_vault/models/vault_errors.dart';
import 'package:omni_explorer/features/password_vault/services/vault_crypto.dart';

void main() {
  late SodiumSumo sodium;
  late VaultCrypto crypto;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
    // Paramètres minimaux : les tests portent sur le format, pas sur le coût.
    crypto = VaultCrypto(sodium,
        opsLimit: sodium.crypto.pwhash.opsLimitMin,
        memLimit: sodium.crypto.pwhash.memLimitMin);
  });

  final now = DateTime.utc(2026, 9, 25, 12);
  final content = VaultContent([
    VaultEntry(
        id: 'a1',
        title: 'Banque',
        fields: {
          'username': 'clement',
          'password': 'S3cr3t!é',
          'url': 'https://banque.example',
          'notes': 'code agence 42',
        },
        createdAt: now,
        updatedAt: now),
  ]);

  /// Scelle [content] avec [password] ; renvoie les octets du fichier.
  Future<Uint8List> sealWith(String password) async {
    final kdf = crypto.newKdfParams();
    final kek = await crypto.deriveKey(password, kdf);
    final dek = crypto.newDataKey();
    try {
      return crypto.seal(content: content, dek: dek, kek: kek, kdf: kdf);
    } finally {
      kek.dispose();
      dek.dispose();
    }
  }

  /// Ouvre [bytes] avec [password].
  Future<VaultContent> openWith(Uint8List bytes, String password) async {
    final file = crypto.parse(bytes);
    final kek = await crypto.deriveKey(password, file.kdf);
    try {
      final dek = crypto.unwrapDataKey(file, kek);
      try {
        return crypto.openContent(file, dek);
      } finally {
        dek.dispose();
      }
    } finally {
      kek.dispose();
    }
  }

  /// Réécrit l'en-tête JSON avec [edit] (même longueur non requise).
  Uint8List withHeader(
      Uint8List bytes, void Function(Map<String, dynamic>) edit) {
    final len = ByteData.sublistView(bytes, 8, 12).getUint32(0);
    final header = jsonDecode(utf8.decode(bytes.sublist(12, 12 + len)))
        as Map<String, dynamic>;
    edit(header);
    final newHeader = utf8.encode(jsonEncode(header));
    return (BytesBuilder()
          ..add(bytes.sublist(0, 8))
          ..add((ByteData(4)..setUint32(0, newHeader.length))
              .buffer
              .asUint8List())
          ..add(newHeader)
          ..add(bytes.sublist(12 + len)))
        .toBytes();
  }

  test('aller-retour : le contenu est retrouvé à l\'identique', () async {
    final bytes = await sealWith('mot de passe maître');
    final opened = await openWith(bytes, 'mot de passe maître');

    expect(jsonEncode(opened.toJson()), jsonEncode(content.toJson()));
  });

  test('aucune donnée en clair dans le fichier', () async {
    final bytes = await sealWith('mot de passe maître');
    final raw = latin1.decode(bytes);
    for (final secret in ['Banque', 'clement', 'S3cr3t', 'agence']) {
      expect(raw.contains(secret), isFalse, reason: secret);
    }
  });

  test('deux sauvegardes du même contenu diffèrent (sel et nonces neufs)',
      () async {
    final a = await sealWith('pw-12345678');
    final b = await sealWith('pw-12345678');
    expect(a, isNot(equals(b)));
  });

  test('les paramètres Argon2id sont inscrits dans l\'en-tête', () async {
    final file = crypto.parse(await sealWith('pw-12345678'));
    expect(file.kdf.opsLimit, sodium.crypto.pwhash.opsLimitMin);
    expect(file.kdf.memLimit, sodium.crypto.pwhash.memLimitMin);
    expect(file.kdf.salt.length, sodium.crypto.pwhash.saltBytes);
  });

  test('mauvais mot de passe', () async {
    final bytes = await sealWith('le bon mot de passe');
    await expectLater(
        openWith(bytes, 'le mauvais'), throwsA(isA<WrongPasswordException>()));
  });

  test('contenu chiffré modifié : détecté', () async {
    final bytes = await sealWith('pw-12345678');
    bytes[bytes.length - 5] ^= 0x01;
    await expectLater(openWith(bytes, 'pw-12345678'),
        throwsA(isA<VaultCorruptedException>()));
  });

  test('en-tête modifié (nonce du contenu) : détecté', () async {
    final bytes = await sealWith('pw-12345678');
    final forged = withHeader(bytes, (h) {
      final n = base64.decode(h['payload']['nonce'] as String);
      n[0] ^= 0x01;
      h['payload']['nonce'] = base64.encode(n);
    });
    await expectLater(openWith(forged, 'pw-12345678'),
        throwsA(isA<VaultCorruptedException>()));
  });

  test('en-tête modifié sans toucher aux clés : détecté (données associées)',
      () async {
    final bytes = await sealWith('pw-12345678');
    final forged = withHeader(bytes, (h) => h['ajout'] = 'x');
    await expectLater(openWith(forged, 'pw-12345678'),
        throwsA(isA<VaultCorruptedException>()));
  });

  test('format plus récent : refus explicite', () async {
    final forged =
        withHeader(await sealWith('pw-12345678'), (h) => h['format'] = 2);
    expect(() => crypto.parse(forged), throwsA(isA<VaultTooNewException>()));
  });

  test('fichiers malformés : erreur « endommagé », jamais de plantage',
      () async {
    final good = await sealWith('pw-12345678');
    final cases = <String, Uint8List>{
      'vide': Uint8List(0),
      'tronqué': good.sublist(0, 20),
      'mauvaise signature':
          Uint8List.fromList([...utf8.encode('PASVAULT'), ...good.sublist(8)]),
      'longueur énorme': Uint8List.fromList(
          [...good.sublist(0, 8), 0xFF, 0xFF, 0xFF, 0xFF, ...good.sublist(12)]),
      'algorithme inconnu': withHeader(good, (h) => h['kdf']['alg'] = 'md5'),
      'sel trop court': withHeader(good, (h) => h['kdf']['salt'] = 'AAAA'),
      'paramètres absurdes': withHeader(good, (h) => h['kdf']['ops'] = 0),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(() => crypto.parse(value), throwsA(isA<VaultCorruptedException>()),
          reason: key);
    }
  });

  test('schéma de contenu plus récent : refus explicite', () {
    expect(() => VaultContent.fromJson({'schema': 99, 'entries': []}),
        throwsA(isA<VaultTooNewException>()));
    expect(() => VaultContent.fromJson({'schema': 1}),
        throwsA(isA<VaultCorruptedException>()));
  });
}
