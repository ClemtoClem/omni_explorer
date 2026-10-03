/// @file editor_encoding.dart
/// @brief Détection et conversion d'encodage pour l'éditeur de code.
///
/// Sans BOM, l'encodage est déduit du début du fichier :
/// 1. un BOM (UTF-8, UTF-16 LE/BE) tranche immédiatement ;
/// 2. des octets nuls presque tous de la même parité → UTF-16 sans BOM
///    (testé avant l'UTF-8 : de l'ASCII en UTF-16 est de l'UTF-8 valide,
///    octets nuls compris) ;
/// 3. de l'UTF-8 valide → UTF-8 ;
/// 4. sinon Windows-1252 (Latin-1, plus les caractères typographiques de la
///    plage 0x80-0x9F).
///
/// La détection ne lit qu'un préfixe ([EditorLimits.sniffBytes]) ; le
/// décodage s'applique au contenu complet, après les limites de taille
/// d'`EditorOpenPolicy`.

import 'dart:convert';
import 'dart:typed_data';

enum EditorEncoding {
  utf8('UTF-8'),
  utf8Bom('UTF-8 BOM'),

  /// UTF-16 petit-boutiste. Écrit toujours avec BOM.
  utf16Le('UTF-16 LE'),

  /// UTF-16 gros-boutiste. Écrit toujours avec BOM.
  utf16Be('UTF-16 BE'),

  /// Windows-1252, sur-ensemble de l'ISO-8859-1 (Latin-1).
  windows1252('Windows-1252');

  const EditorEncoding(this.label);
  final String label;

  /// Vrai si l'encodage est désigné par un BOM ou par sa structure (UTF-16) :
  /// le contenu est alors du texte, même avec des octets nuls.
  bool get isUnicodeMarked =>
      this == utf8Bom || this == utf16Le || this == utf16Be;
}

class EditorEncodingException implements Exception {
  final String message;
  const EditorEncodingException(this.message);
  @override
  String toString() => message;
}

abstract final class EditorEncodingDetector {
  /// Détecte l'encodage du préfixe [head]. Avec [truncated], jusqu'à
  /// 3 octets finaux peuvent être un caractère UTF-8 coupé par la lecture
  /// partielle.
  static EditorEncoding detect(List<int> head, {bool truncated = false}) {
    if (head.isEmpty) return EditorEncoding.utf8;

    // 1. BOM.
    if (head.length >= 3 &&
        head[0] == 0xEF &&
        head[1] == 0xBB &&
        head[2] == 0xBF) {
      return EditorEncoding.utf8Bom;
    }
    if (head.length >= 2) {
      if (head[0] == 0xFF && head[1] == 0xFE) return EditorEncoding.utf16Le;
      if (head[0] == 0xFE && head[1] == 0xFF) return EditorEncoding.utf16Be;
    }

    // 2. UTF-16 sans BOM. Texte latin en UTF-16 LE : « h\0i\0 » — les
    //    octets nuls sont aux positions impaires ; en BE, aux paires.
    final utf16 = _utf16WithoutBom(head);
    if (utf16 != null) return utf16;

    // 3. UTF-8.
    if (isValidUtf8(head, truncated: truncated)) return EditorEncoding.utf8;

    // 4. Repli 8 bits.
    return EditorEncoding.windows1252;
  }

  static EditorEncoding? _utf16WithoutBom(List<int> head) {
    final end = (head.length < 1024 ? head.length : 1024) & ~1;
    if (end < 8) return null;
    var nulEven = 0, nulOdd = 0;
    for (var i = 0; i < end; i++) {
      if (head[i] != 0) continue;
      if (i.isEven) {
        nulEven++;
      } else {
        nulOdd++;
      }
    }
    final pairs = end ~/ 2;
    // Au moins un quart de caractères ASCII, et l'autre parité quasi vide
    // (un caractère comme U+4E00 donne un nul « à contre-parité »).
    final EditorEncoding candidate;
    if (nulOdd * 4 >= pairs && nulEven * 20 <= nulOdd) {
      candidate = EditorEncoding.utf16Le;
    } else if (nulEven * 4 >= pairs && nulOdd * 20 <= nulEven) {
      candidate = EditorEncoding.utf16Be;
    } else {
      return null;
    }
    // Des entiers 16 bits (échantillons audio, tables) ont la même allure :
    // un texte, lui, n'a presque pas de caractères de contrôle.
    final le = candidate == EditorEncoding.utf16Le;
    var controls = 0;
    for (var i = 0; i < end; i += 2) {
      final u =
          le ? head[i] | (head[i + 1] << 8) : (head[i] << 8) | head[i + 1];
      if (u < 0x20 && u != 0x09 && u != 0x0A && u != 0x0D && u != 0x0C) {
        controls++;
      }
    }
    return controls * 100 > pairs ? null : candidate;
  }

  /// Vrai si [bytes] est de l'UTF-8 valide (octets nuls compris).
  static bool isValidUtf8(List<int> bytes, {bool truncated = false}) {
    final maxCut = truncated ? 3 : 0;
    for (var cut = 0; cut <= maxCut && cut <= bytes.length; cut++) {
      try {
        utf8.decode(bytes.sublist(0, bytes.length - cut));
        return true;
      } on FormatException {
        // Essai suivant : un caractère multi-octets a peut-être été coupé.
      }
    }
    return false;
  }

  /// Vrai si un préfixe décodé en Windows-1252 ressemble à un fichier
  /// binaire plutôt qu'à du texte : octet nul, ou plus de 1 % de caractères
  /// de contrôle (hors tabulation, fins de ligne, saut de page, échappement)
  /// et d'octets non définis en Windows-1252.
  static bool looksBinary8Bit(List<int> head) {
    if (head.isEmpty) return false;
    var suspicious = 0;
    for (final b in head) {
      if (b == 0) return true;
      final control = b < 0x20 &&
          b != 0x09 && // tabulation
          b != 0x0A &&
          b != 0x0D &&
          b != 0x0C && // saut de page
          b != 0x1B; // échappement (codes couleur des journaux)
      final undefined =
          b == 0x81 || b == 0x8D || b == 0x8F || b == 0x90 || b == 0x9D;
      if (control || undefined || b == 0x7F) suspicious++;
    }
    return suspicious * 100 > head.length;
  }
}

abstract final class EditorEncodingCodec {
  static String decode(List<int> bytes, EditorEncoding encoding) {
    switch (encoding) {
      case EditorEncoding.utf8:
      case EditorEncoding.utf8Bom:
        return _decodeUtf8(bytes);
      case EditorEncoding.utf16Le:
        return _decodeUtf16(bytes, littleEndian: true);
      case EditorEncoding.utf16Be:
        return _decodeUtf16(bytes, littleEndian: false);
      case EditorEncoding.windows1252:
        return _decode1252(bytes);
    }
  }

  /// Encode [text]. Lève [EditorEncodingException] si un caractère n'est
  /// pas représentable (Windows-1252).
  static Uint8List encode(String text, EditorEncoding encoding) {
    switch (encoding) {
      case EditorEncoding.utf8:
        return utf8.encode(text);
      case EditorEncoding.utf8Bom:
        return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
      case EditorEncoding.utf16Le:
        return _encodeUtf16(text, littleEndian: true);
      case EditorEncoding.utf16Be:
        return _encodeUtf16(text, littleEndian: false);
      case EditorEncoding.windows1252:
        return _encode1252(text);
    }
  }

  /// UTF-8, BOM retiré s'il est présent (qu'il soit attendu ou non : il
  /// n'a pas sa place dans le texte édité).
  static String _decodeUtf8(List<int> bytes) {
    final hasBom = bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    try {
      return utf8.decode(hasBom ? bytes.sublist(3) : bytes);
    } on FormatException catch (e) {
      throw EditorEncodingException('UTF-8 invalide : ${e.message}');
    }
  }

  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    var start = 0;
    if (bytes.length >= 2) {
      final bom = littleEndian
          ? bytes[0] == 0xFF && bytes[1] == 0xFE
          : bytes[0] == 0xFE && bytes[1] == 0xFF;
      if (bom) start = 2;
    }
    if ((bytes.length - start).isOdd) {
      throw const EditorEncodingException('UTF-16 : nombre d\'octets impair.');
    }
    final units = Uint16List((bytes.length - start) ~/ 2);
    for (var i = 0; i < units.length; i++) {
      final a = bytes[start + 2 * i], b = bytes[start + 2 * i + 1];
      units[i] = littleEndian ? a | (b << 8) : (a << 8) | b;
    }
    // Les paires de substitution sont conservées telles quelles : une
    // String Dart est elle-même en UTF-16.
    return String.fromCharCodes(units);
  }

  static Uint8List _encodeUtf16(String text, {required bool littleEndian}) {
    final units = text.codeUnits;
    final out = Uint8List(2 + units.length * 2);
    out[0] = littleEndian ? 0xFF : 0xFE;
    out[1] = littleEndian ? 0xFE : 0xFF;
    for (var i = 0; i < units.length; i++) {
      final u = units[i], lo = u & 0xFF, hi = u >> 8;
      out[2 + 2 * i] = littleEndian ? lo : hi;
      out[3 + 2 * i] = littleEndian ? hi : lo;
    }
    return out;
  }

  /// Plage 0x80-0x9F de Windows-1252 (indéfinie en ISO-8859-1). Les cinq
  /// positions non attribuées (0x81, 0x8D, 0x8F, 0x90, 0x9D) donnent le
  /// caractère de contrôle C1 de même valeur, pour un aller-retour exact.
  static const List<int> _cp1252 = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
  ];

  static String _decode1252(List<int> bytes) {
    final units = Uint16List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      units[i] = b < 0x80 || b >= 0xA0 ? b : _cp1252[b - 0x80];
    }
    return String.fromCharCodes(units);
  }

  static Uint8List _encode1252(String text) {
    final buf = Uint8List(text.length); // au plus un octet par unité UTF-16
    var n = 0;
    for (final cp in text.runes) {
      if (cp < 0x80 || (cp >= 0xA0 && cp <= 0xFF)) {
        buf[n++] = cp;
        continue;
      }
      final i = _cp1252.indexOf(cp);
      if (i < 0) {
        throw EditorEncodingException(
            'Le caractère U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')} '
            'n\'existe pas en Windows-1252.');
      }
      buf[n++] = 0x80 + i;
    }
    return buf.sublist(0, n);
  }
}
