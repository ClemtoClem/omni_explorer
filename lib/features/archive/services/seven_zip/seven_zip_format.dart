/// @file seven_zip_format.dart
/// @brief Constantes du format 7z (identifiants de propriétés, de méthodes)
/// et lecture / écriture de ses types binaires (nombres variables, champs de
/// bits, dates FILETIME).

import 'dart:typed_data';

/// Identifiants des propriétés de l'en-tête (`7zFormat.txt`).
abstract final class SevenZipId {
  static const end = 0x00;
  static const header = 0x01;
  static const archiveProperties = 0x02;
  static const additionalStreamsInfo = 0x03;
  static const mainStreamsInfo = 0x04;
  static const filesInfo = 0x05;
  static const packInfo = 0x06;
  static const unpackInfo = 0x07;
  static const subStreamsInfo = 0x08;
  static const size = 0x09;
  static const crc = 0x0A;
  static const folder = 0x0B;
  static const codersUnpackSize = 0x0C;
  static const numUnpackStream = 0x0D;
  static const emptyStream = 0x0E;
  static const emptyFile = 0x0F;
  static const anti = 0x10;
  static const name = 0x11;
  static const cTime = 0x12;
  static const aTime = 0x13;
  static const mTime = 0x14;
  static const winAttributes = 0x15;
  static const encodedHeader = 0x17;
  static const dummy = 0x19;
}

/// Méthodes gérées par le lecteur intégré.
enum SevenZipMethod { copy, lzma, lzma2, deflate, bzip2, bcjX86, delta, aes }

abstract final class SevenZip {
  static const signature = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C];

  static const idCopy = [0x00];
  static const idLzma = [0x03, 0x01, 0x01];
  static const idAes = [0x06, 0xF1, 0x07, 0x01];

  static bool hasSignature(List<int> data) {
    if (data.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (data[i] != signature[i]) return false;
    }
    return true;
  }

  static String _hex(List<int> id) =>
      id.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static SevenZipMethod? methodOf(List<int> id) => switch (_hex(id)) {
        '00' => SevenZipMethod.copy,
        '030101' => SevenZipMethod.lzma,
        '21' => SevenZipMethod.lzma2,
        '040108' => SevenZipMethod.deflate,
        '040202' => SevenZipMethod.bzip2,
        '03030103' || '04' => SevenZipMethod.bcjX86,
        '03' => SevenZipMethod.delta,
        '06f10701' => SevenZipMethod.aes,
        _ => null,
      };

  /// Nom lisible d'une méthode (y compris celles non gérées).
  static String methodName(List<int> id) => switch (_hex(id)) {
        '030401' => 'PPMd',
        '0303011b' => 'BCJ2',
        '040109' => 'Deflate64',
        '03030501' || '03030701' || '07' || '08' => 'filtre ARM',
        '0a' => 'filtre ARM64',
        '0b' => 'filtre RISC-V',
        '03030205' || '05' => 'filtre PowerPC',
        '03030401' || '06' => 'filtre IA-64',
        '03030805' || '09' => 'filtre SPARC',
        '04f71101' => 'Zstandard',
        final hex => methodOf(id)?.name ?? 'méthode 0x$hex',
      };

  /// FILETIME (centaines de nanosecondes depuis 1601) → date.
  static DateTime? fromFileTime(int ft) {
    const epochDiff = 116444736000000000; // 1601 → 1970
    if (ft <= 0) return null;
    return DateTime.fromMicrosecondsSinceEpoch((ft - epochDiff) ~/ 10,
        isUtc: true);
  }

  static int toFileTime(DateTime d) =>
      d.toUtc().microsecondsSinceEpoch * 10 + 116444736000000000;
}

/// Lecture séquentielle de l'en-tête.
class SevenZipByteReader {
  final Uint8List _b;
  int _pos = 0;

  SevenZipByteReader(this._b);

  void _need(int n) {
    if (_pos + n > _b.length) {
      throw const FormatException('7z : en-tête tronqué');
    }
  }

  int readByte() {
    _need(1);
    return _b[_pos++];
  }

  Uint8List readBytes(int n) {
    _need(n);
    final out = Uint8List.sublistView(_b, _pos, _pos + n);
    _pos += n;
    return out;
  }

  void skip(int n) {
    _need(n);
    _pos += n;
  }

  Uint8List get remaining => Uint8List.sublistView(_b, _pos);

  int readUint32() {
    _need(4);
    final v = ByteData.sublistView(_b, _pos, _pos + 4).getUint32(0, Endian.little);
    _pos += 4;
    return v;
  }

  int readUint64() {
    _need(8);
    final v = ByteData.sublistView(_b, _pos, _pos + 8).getUint64(0, Endian.little);
    _pos += 8;
    return v;
  }

  /// Nombre à longueur variable : les bits de poids fort à 1 du premier
  /// octet donnent le nombre d'octets supplémentaires (petit-boutiste).
  int readNumber() {
    final first = readByte();
    var mask = 0x80;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      if (first & mask == 0) {
        final high = first & (mask - 1);
        return value | (high << (8 * i));
      }
      value |= readByte() << (8 * i);
      mask >>= 1;
    }
    return value;
  }

  /// Champ de [n] bits, bit de poids fort en premier.
  List<bool> readBits(int n) {
    final out = List.filled(n, false);
    var byte = 0, mask = 0;
    for (var i = 0; i < n; i++) {
      if (mask == 0) {
        byte = readByte();
        mask = 0x80;
      }
      out[i] = byte & mask != 0;
      mask >>= 1;
    }
    return out;
  }

  /// « Tous définis » (un octet) ou champ de bits.
  List<bool> readOptionalBits(int n) =>
      readByte() != 0 ? List.filled(n, true) : readBits(n);

  /// CRC optionnels de [n] éléments.
  List<int?> readDigests(int n) {
    final defined = readOptionalBits(n);
    return [for (final d in defined) d ? readUint32() : null];
  }
}

/// Écriture de l'en-tête.
class SevenZipByteWriter {
  final BytesBuilder _b = BytesBuilder();

  int get length => _b.length;
  Uint8List toBytes() => _b.toBytes();

  void byte(int v) => _b.addByte(v & 0xFF);
  void bytes(List<int> v) => _b.add(v);

  void uint32(int v) =>
      _b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());

  void uint64(int v) =>
      _b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());

  /// Nombre à longueur variable (voir [SevenZipByteReader.readNumber]).
  void number(int value) {
    var first = 0, mask = 0x80, extra = 0;
    for (; extra < 8; extra++) {
      if (value < (1 << (7 * (extra + 1)))) {
        first |= value >> (8 * extra);
        break;
      }
      first |= mask;
      mask >>= 1;
    }
    byte(first);
    var v = value;
    for (var i = 0; i < extra; i++) {
      byte(v);
      v >>= 8;
    }
  }

  void bits(List<bool> v) {
    var cur = 0, mask = 0x80;
    for (final b in v) {
      if (b) cur |= mask;
      mask >>= 1;
      if (mask == 0) {
        byte(cur);
        cur = 0;
        mask = 0x80;
      }
    }
    if (mask != 0x80) byte(cur);
  }

  /// « Tous définis » ou champ de bits.
  void optionalBits(List<bool> v) {
    if (v.every((b) => b)) {
      byte(1);
    } else {
      byte(0);
      bits(v);
    }
  }
}

/// Filtre BCJ x86 en décodage (adresses relatives des CALL/JMP rétablies),
/// d'après `Bra86.c` du LZMA SDK (domaine public). En place.
void sevenZipBcjX86Decode(Uint8List data) {
  const maskToAllowed = [true, true, true, false, true, false, false, false];
  const maskToBitNumber = [0, 1, 2, 2, 3, 3, 3, 3];
  bool msByte(int b) => b == 0 || b == 0xFF;

  final size = data.length;
  if (size < 5) return;
  const ip = 5;
  var bufferPos = 0;
  var prevPosT = -1;
  var prevMask = 0;
  while (true) {
    var p = bufferPos;
    final limit = size - 4;
    while (p < limit && data[p] & 0xFE != 0xE8) {
      p++;
    }
    bufferPos = p;
    if (p >= limit) break;
    prevPosT = bufferPos - prevPosT;
    if (prevPosT > 3) {
      prevMask = 0;
    } else {
      prevMask = (prevMask << (prevPosT - 1)) & 7;
      if (prevMask != 0) {
        final b = data[p + 4 - maskToBitNumber[prevMask]];
        if (!maskToAllowed[prevMask] || msByte(b)) {
          prevPosT = bufferPos;
          prevMask = ((prevMask << 1) & 7) | 1;
          bufferPos++;
          continue;
        }
      }
    }
    prevPosT = bufferPos;
    if (msByte(data[p + 4])) {
      var src = (data[p + 4] << 24) |
          (data[p + 3] << 16) |
          (data[p + 2] << 8) |
          data[p + 1];
      int dest;
      while (true) {
        dest = (src - (ip + bufferPos)) & 0xFFFFFFFF;
        if (prevMask == 0) break;
        final index = maskToBitNumber[prevMask] * 8;
        final b = (dest >> (24 - index)) & 0xFF;
        if (!msByte(b)) break;
        src = dest ^ ((1 << (32 - index)) - 1);
      }
      data[p + 4] = (~(((dest >> 24) & 1) - 1)) & 0xFF;
      data[p + 3] = (dest >> 16) & 0xFF;
      data[p + 2] = (dest >> 8) & 0xFF;
      data[p + 1] = dest & 0xFF;
      bufferPos += 5;
    } else {
      prevMask = ((prevMask << 1) & 7) | 1;
      bufferPos++;
    }
  }
}
