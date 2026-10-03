/// @file seven_zip_aes.dart
/// @brief Chiffrement des archives 7z (codec « 7zAES ») : AES-256-CBC, clé
/// dérivée du mot de passe par SHA-256 itéré (2^19 tours par défaut).

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Paramètres du codec AES d'un dossier 7z.
class SevenZipAesParams {
  /// Nombre de tours de dérivation : 2^[cyclesPower] (63 : pas de hachage,
  /// clé = sel + mot de passe).
  final int cyclesPower;
  final Uint8List salt;
  final Uint8List iv;

  const SevenZipAesParams(this.cyclesPower, this.salt, this.iv);

  /// Valeurs écrites par 7-Zip : 2^19 tours, sans sel, IV aléatoire de
  /// 16 octets.
  factory SevenZipAesParams.random({int cyclesPower = 19}) {
    final rnd = Random.secure();
    return SevenZipAesParams(cyclesPower, Uint8List(0),
        Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256))));
  }

  /// Lecture des propriétés du codec.
  factory SevenZipAesParams.parse(Uint8List props) {
    if (props.isEmpty) throw const FormatException('Propriétés AES vides');
    final b0 = props[0];
    final cycles = b0 & 0x3F;
    if (b0 & 0xC0 == 0) {
      return SevenZipAesParams(cycles, Uint8List(0), Uint8List(0));
    }
    if (props.length < 2) throw const FormatException('Propriétés AES');
    final b1 = props[1];
    final saltSize = ((b0 >> 7) & 1) + (b1 >> 4);
    final ivSize = ((b0 >> 6) & 1) + (b1 & 0x0F);
    if (props.length != 2 + saltSize + ivSize) {
      throw const FormatException('Propriétés AES : taille incohérente');
    }
    return SevenZipAesParams(
      cycles,
      Uint8List.sublistView(props, 2, 2 + saltSize),
      Uint8List.sublistView(props, 2 + saltSize),
    );
  }

  /// Propriétés du codec telles que 7-Zip les écrit.
  Uint8List toBytes() {
    final s = salt.length, v = iv.length;
    if (s == 0 && v == 0) return Uint8List.fromList([cyclesPower]);
    final b0 = cyclesPower | (s > 0 ? 0x80 : 0) | (v > 0 ? 0x40 : 0);
    final b1 = ((s > 0 ? s - 1 : 0) << 4) | (v > 0 ? v - 1 : 0);
    return Uint8List.fromList([b0, b1, ...salt, ...iv]);
  }
}

abstract final class SevenZipAes {
  /// Clé AES-256 dérivée de [password] (UTF-16LE, comme 7-Zip).
  static Uint8List deriveKey(String password, SevenZipAesParams params) {
    final pw = Uint8List(password.length * 2);
    for (var i = 0; i < password.length; i++) {
      final u = password.codeUnitAt(i);
      pw[2 * i] = u & 0xFF;
      pw[2 * i + 1] = u >> 8;
    }
    if (params.cyclesPower == 0x3F) {
      final key = Uint8List(32);
      final src = [...params.salt, ...pw];
      key.setRange(0, min(32, src.length), src);
      return key;
    }
    // Tour i : sel ‖ mot de passe ‖ i (8 octets petit-boutiste). Un seul
    // tampon réutilisé : seul le compteur change d'un tour à l'autre.
    final block = Uint8List(params.salt.length + pw.length + 8)
      ..setAll(0, params.salt)
      ..setAll(params.salt.length, pw);
    final counterAt = params.salt.length + pw.length;
    final digest = SHA256Digest();
    final rounds = 1 << params.cyclesPower;
    for (var i = 0; i < rounds; i++) {
      var c = i;
      for (var j = 0; j < 8; j++) {
        block[counterAt + j] = c & 0xFF;
        c >>= 8;
      }
      digest.update(block, 0, block.length);
    }
    final key = Uint8List(32);
    digest.doFinal(key, 0);
    return key;
  }

  static CBCBlockCipher _cipher(Uint8List key, Uint8List iv, bool encrypt) {
    final ivFull = Uint8List(16)..setRange(0, min(16, iv.length), iv);
    return CBCBlockCipher(AESEngine())
      ..init(encrypt, ParametersWithIV(KeyParameter(key), ivFull));
  }

  /// Déchiffre [data] (longueur multiple de 16 ; un reste éventuel est
  /// ignoré, comme dans 7-Zip).
  static Uint8List decrypt(Uint8List data, Uint8List key, Uint8List iv) {
    final cipher = _cipher(key, iv, false);
    final out = Uint8List(data.length - data.length % 16);
    for (var off = 0; off < out.length; off += 16) {
      cipher.processBlock(data, off, out, off);
    }
    return out;
  }

  /// Chiffre [data], complété par des zéros jusqu'à un multiple de 16 (le
  /// codec suivant connaît la taille exacte).
  static Uint8List encrypt(Uint8List data, Uint8List key, Uint8List iv) {
    final padded = Uint8List((data.length + 15) & ~15)..setAll(0, data);
    final cipher = _cipher(key, iv, true);
    final out = Uint8List(padded.length);
    for (var off = 0; off < out.length; off += 16) {
      cipher.processBlock(padded, off, out, off);
    }
    return out;
  }
}
