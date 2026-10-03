/// @file lzma_encoder.dart
/// @brief Encodeur LZMA (flux brut, sans en-tête ni marqueur de fin), pour
/// les archives 7z écrites par l'application.
///
/// Le paquet `archive` sait décoder LZMA mais pas l'encoder. Cet encodeur
/// suit le format de référence (LZMA SDK, domaine public) en mode « rapide » :
/// recherche de correspondances par chaînes de hachage sur 3 octets,
/// analyse gloutonne avec évaluation paresseuse de la position suivante, et
/// réutilisation des quatre dernières distances (« rep »). Le taux de
/// compression se situe entre `7z -mx=1` et `-mx=3`, en Dart pur (aucune bibliothèque
/// native), donc identique sous Android et Linux.

import 'dart:typed_data';

/// Paramètres d'un flux LZMA (les 5 octets de propriétés du codec 7z).
class LzmaProperties {
  /// Bits de contexte littéral (lc), de position littérale (lp) et de
  /// position (pb) : valeurs par défaut de 7-Zip.
  final int lc;
  final int lp;
  final int pb;
  final int dictionarySize;

  const LzmaProperties({
    this.lc = 3,
    this.lp = 0,
    this.pb = 2,
    required this.dictionarySize,
  });

  /// Octet de propriétés suivi de la taille du dictionnaire (petit-boutiste).
  Uint8List toBytes() {
    final out = Uint8List(5);
    out[0] = (pb * 5 + lp) * 9 + lc;
    out.buffer.asByteData().setUint32(1, dictionarySize, Endian.little);
    return out;
  }

  /// Dictionnaire adapté à [dataLength] : puissance de deux, entre 64 Kio et
  /// [max] (borne la mémoire de l'encodeur : 4 octets par position).
  static int dictionaryFor(int dataLength, {int max = 1 << 23}) {
    var size = 1 << 16;
    while (size < dataLength && size < max) {
      size <<= 1;
    }
    return size;
  }
}

/// Codeur d'intervalle (« range coder ») de LZMA.
class _RangeEncoder {
  int _low = 0; // jusqu'à 33 bits
  int _range = 0xFFFFFFFF;
  int _cache = 0;
  int _cacheSize = 1;
  Uint8List _out;
  int _pos = 0;

  _RangeEncoder(int capacity) : _out = Uint8List(capacity < 64 ? 64 : capacity);

  void _write(int b) {
    if (_pos == _out.length) {
      final grown = Uint8List(_out.length * 2);
      grown.setRange(0, _pos, _out);
      _out = grown;
    }
    _out[_pos++] = b;
  }

  void _shiftLow() {
    if (_low < 0xFF000000 || _low > 0xFFFFFFFF) {
      final carry = _low >> 32;
      var temp = _cache;
      do {
        _write((temp + carry) & 0xFF);
        temp = 0xFF;
      } while (--_cacheSize != 0);
      _cache = (_low >> 24) & 0xFF;
    }
    _cacheSize++;
    _low = (_low & 0x00FFFFFF) << 8;
  }

  @pragma('vm:prefer-inline')
  void bit(Uint16List probs, int index, int bit) {
    final p = probs[index];
    final bound = (_range >> 11) * p;
    if (bit == 0) {
      _range = bound;
      probs[index] = p + ((2048 - p) >> 5);
    } else {
      _low += bound;
      _range -= bound;
      probs[index] = p - (p >> 5);
    }
    while (_range < 0x01000000) {
      _range = (_range << 8) & 0xFFFFFFFF;
      _shiftLow();
    }
  }

  void directBits(int value, int count) {
    for (var i = count - 1; i >= 0; i--) {
      _range >>= 1;
      if ((value >> i) & 1 == 1) _low += _range;
      while (_range < 0x01000000) {
        _range = (_range << 8) & 0xFFFFFFFF;
        _shiftLow();
      }
    }
  }

  void bitTree(Uint16List probs, int base, int numBits, int value) {
    var m = 1;
    for (var i = numBits - 1; i >= 0; i--) {
      final b = (value >> i) & 1;
      bit(probs, base + m, b);
      m = (m << 1) | b;
    }
  }

  void reverseBitTree(Uint16List probs, int base, int numBits, int value) {
    var m = 1;
    for (var i = 0; i < numBits; i++) {
      final b = value & 1;
      bit(probs, base + m, b);
      m = (m << 1) | b;
      value >>= 1;
    }
  }

  Uint8List finish() {
    for (var i = 0; i < 5; i++) {
      _shiftLow();
    }
    return Uint8List.sublistView(_out, 0, _pos);
  }
}

/// Modèle des longueurs (correspondances ou répétitions).
class _LengthEncoder {
  final Uint16List choice = _probs(2);
  final Uint16List low = _probs(16 << 3);
  final Uint16List mid = _probs(16 << 3);
  final Uint16List high = _probs(256);

  /// [len] : longueur moins 2 (0 à 271).
  void encode(_RangeEncoder rc, int len, int posState) {
    if (len < 8) {
      rc.bit(choice, 0, 0);
      rc.bitTree(low, posState << 3, 3, len);
    } else if (len < 16) {
      rc.bit(choice, 0, 1);
      rc.bit(choice, 1, 0);
      rc.bitTree(mid, posState << 3, 3, len - 8);
    } else {
      rc.bit(choice, 0, 1);
      rc.bit(choice, 1, 1);
      rc.bitTree(high, 0, 8, len - 16);
    }
  }
}

Uint16List _probs(int n) => Uint16List(n)..fillRange(0, n, 1024);

abstract final class LzmaEncoder {
  static const int _matchMin = 2;
  static const int _matchMax = 273;
  static const int _endPosModelIndex = 14;
  static const int _numFullDistances = 128;

  /// Encode [data] en flux LZMA brut (sans marqueur de fin : le décodeur doit
  /// connaître la taille, ce que fournit l'archive 7z). [niceLength] et
  /// [depth] règlent le compromis vitesse / taux.
  static Uint8List encode(Uint8List data, LzmaProperties props,
      {int niceLength = 64, int depth = 32}) {
    final n = data.length;
    final rc = _RangeEncoder(n ~/ 2 + 1024);
    final lc = props.lc, lp = props.lp, pb = props.pb;
    final posMask = (1 << pb) - 1, lpMask = (1 << lp) - 1;

    final isMatch = _probs(12 << 4);
    final isRep = _probs(12);
    final isRepG0 = _probs(12);
    final isRepG1 = _probs(12);
    final isRepG2 = _probs(12);
    final isRep0Long = _probs(12 << 4);
    final literal = _probs(0x300 << (lc + lp));
    final posSlot = _probs(4 << 6);
    final posSpecial = _probs(1 + _numFullDistances - _endPosModelIndex);
    final align = _probs(16);
    final lenEnc = _LengthEncoder();
    final repLenEnc = _LengthEncoder();

    // Recherche par chaînes de hachage (3 octets).
    final dictSize = props.dictionarySize;
    final chainLen = dictSize < n ? dictSize : _pow2AtLeast(n + 1);
    final chainMask = chainLen - 1;
    const hashBits = 16;
    final head = Int32List(1 << hashBits)..fillRange(0, 1 << hashBits, -1);
    final chain = Int32List(chainLen);
    var inserted = 0; // positions déjà insérées : [0, inserted[

    int hashAt(int i) =>
        (((data[i] | (data[i + 1] << 8) | (data[i + 2] << 16)) * 0x9E3779B1) &
            0xFFFFFFFF) >>
        (32 - hashBits);

    void insertUpTo(int end) {
      // Insère les positions [inserted, end[ qui ont 3 octets devant elles.
      final last = end < n - 2 ? end : n - 2;
      while (inserted < last) {
        final h = hashAt(inserted);
        chain[inserted & chainMask] = head[h];
        head[h] = inserted;
        inserted++;
      }
      if (inserted < end) inserted = end;
    }

    // Meilleure correspondance à [pos] (avant insertion de pos) : longueur et
    // distance - 1 dans [_mLen] / [_mDist].
    var mLen = 0, mDist = 0;
    void findMatch(int pos) {
      mLen = 0;
      mDist = 0;
      final avail = n - pos;
      if (avail < 3) return;
      final maxLen = avail < _matchMax ? avail : _matchMax;
      var cur = head[hashAt(pos)];
      var left = depth;
      while (cur >= 0 && left-- > 0) {
        final delta = pos - cur;
        if (delta <= 0 || delta >= dictSize || delta >= chainLen) break;
        if (data[cur + mLen] == data[pos + mLen] && data[cur] == data[pos]) {
          var len = 0;
          while (len < maxLen && data[cur + len] == data[pos + len]) {
            len++;
          }
          if (len > mLen) {
            mLen = len;
            mDist = delta - 1;
            if (len >= niceLength || len == maxLen) break;
          }
        }
        final next = chain[cur & chainMask];
        if (next >= cur) break;
        cur = next;
      }
      // Longueur 3 très lointaine : un littéral coûte moins cher.
      if (mLen == 3 && mDist >= 0x4000) mLen = 0;
    }

    var state = 0;
    final reps = Int32List(4);
    var pos = 0;

    void encodeLiteral() {
      final posState = pos & posMask;
      rc.bit(isMatch, (state << 4) + posState, 0);
      final prev = pos > 0 ? data[pos - 1] : 0;
      final base = 0x300 * (((pos & lpMask) << lc) + (prev >> (8 - lc)));
      var symbol = data[pos] | 0x100;
      if (state < 7) {
        do {
          rc.bit(literal, base + (symbol >> 8), (symbol >> 7) & 1);
          symbol <<= 1;
        } while (symbol < 0x10000);
      } else {
        var matchByte = data[pos - reps[0] - 1];
        var offs = 0x100;
        do {
          matchByte <<= 1;
          rc.bit(literal, base + offs + (matchByte & offs) + (symbol >> 8),
              (symbol >> 7) & 1);
          symbol <<= 1;
          offs &= ~(matchByte ^ symbol);
        } while (symbol < 0x10000);
      }
      state = state < 4
          ? 0
          : state < 10
              ? state - 3
              : state - 6;
      pos++;
    }

    void encodeMatch(int dist, int len) {
      final posState = pos & posMask;
      rc.bit(isMatch, (state << 4) + posState, 1);
      rc.bit(isRep, state, 0);
      lenEnc.encode(rc, len - _matchMin, posState);
      final lenState = len - 2 < 3 ? len - 2 : 3;
      final slot = _posSlotOf(dist);
      rc.bitTree(posSlot, lenState << 6, 6, slot);
      if (slot >= 4) {
        final footerBits = (slot >> 1) - 1;
        final base = (2 | (slot & 1)) << footerBits;
        final reduced = dist - base;
        if (slot < _endPosModelIndex) {
          rc.reverseBitTree(posSpecial, base - slot - 1, footerBits, reduced);
        } else {
          rc.directBits(reduced >> 4, footerBits - 4);
          rc.reverseBitTree(align, 0, 4, reduced & 15);
        }
      }
      reps[3] = reps[2];
      reps[2] = reps[1];
      reps[1] = reps[0];
      reps[0] = dist;
      state = state < 7 ? 7 : 10;
      pos += len;
    }

    void encodeRep(int index, int len) {
      final posState = pos & posMask;
      rc.bit(isMatch, (state << 4) + posState, 1);
      rc.bit(isRep, state, 1);
      if (index == 0) {
        rc.bit(isRepG0, state, 0);
        rc.bit(isRep0Long, (state << 4) + posState, 1);
      } else {
        rc.bit(isRepG0, state, 1);
        final dist = reps[index];
        if (index == 1) {
          rc.bit(isRepG1, state, 0);
        } else {
          rc.bit(isRepG1, state, 1);
          rc.bit(isRepG2, state, index - 2);
          if (index == 3) reps[3] = reps[2];
          reps[2] = reps[1];
        }
        reps[1] = reps[0];
        reps[0] = dist;
      }
      repLenEnc.encode(rc, len - _matchMin, posState);
      state = state < 7 ? 8 : 11;
      pos += len;
    }

    int repLength(int p, int rep, int maxLen) {
      final src = p - rep - 1;
      if (src < 0) return 0;
      var len = 0;
      while (len < maxLen && data[src + len] == data[p + len]) {
        len++;
      }
      return len;
    }

    // Correspondance trouvée d'avance à la position suivante (évaluation
    // paresseuse) : réutilisée au tour suivant.
    var aheadValid = false;
    var aheadLen = 0, aheadDist = 0;

    while (pos < n) {
      final avail = n - pos;
      final maxLen = avail < _matchMax ? avail : _matchMax;
      if (avail < 2) {
        insertUpTo(pos + 1);
        encodeLiteral();
        aheadValid = false;
        continue;
      }

      // Répétitions des quatre dernières distances.
      var repLen = 0, repIndex = 0;
      for (var i = 0; i < 4; i++) {
        final len = repLength(pos, reps[i], maxLen);
        if (len > repLen) {
          repLen = len;
          repIndex = i;
        }
      }
      if (repLen >= niceLength) {
        insertUpTo(pos + repLen);
        encodeRep(repIndex, repLen);
        aheadValid = false;
        continue;
      }

      int mainLen, mainDist;
      if (aheadValid) {
        mainLen = aheadLen;
        mainDist = aheadDist;
      } else {
        insertUpTo(pos);
        findMatch(pos);
        mainLen = mLen;
        mainDist = mDist;
      }
      aheadValid = false;
      insertUpTo(pos + 1);

      if (mainLen >= niceLength) {
        insertUpTo(pos + mainLen);
        encodeMatch(mainDist, mainLen);
        continue;
      }

      if (repLen >= 2 &&
          (repLen + 1 >= mainLen ||
              (repLen + 2 >= mainLen && mainDist >= (1 << 9)) ||
              (repLen + 3 >= mainLen && mainDist >= (1 << 15)))) {
        insertUpTo(pos + repLen);
        encodeRep(repIndex, repLen);
        continue;
      }

      if (mainLen < 3) {
        encodeLiteral();
        continue;
      }

      // Évaluation paresseuse : une meilleure correspondance commence-t-elle
      // à la position suivante ?
      findMatch(pos + 1);
      if (mLen >= 3 &&
          (mLen > mainLen + 1 ||
              (mLen == mainLen + 1 && mDist < mainDist * 128) ||
              (mLen >= mainLen && mDist < mainDist))) {
        aheadValid = true;
        aheadLen = mLen;
        aheadDist = mDist;
        encodeLiteral();
        continue;
      }
      insertUpTo(pos + mainLen);
      encodeMatch(mainDist, mainLen);
    }
    return rc.finish();
  }

  static int _posSlotOf(int dist) {
    if (dist < 4) return dist;
    final n = dist.bitLength - 1;
    return (n << 1) | ((dist >> (n - 1)) & 1);
  }

  static int _pow2AtLeast(int v) {
    var p = 1;
    while (p < v) {
      p <<= 1;
    }
    return p;
  }
}
