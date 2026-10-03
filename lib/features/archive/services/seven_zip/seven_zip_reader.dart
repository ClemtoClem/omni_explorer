/// @file seven_zip_reader.dart
/// @brief Lecture des archives 7z en Dart pur (sans `7z` installé), d'après
/// la description du format de 7-Zip (`7zFormat.txt`).
///
/// Méthodes prises en charge : Copy, LZMA, LZMA2, Deflate, BZip2, filtres
/// BCJ x86 et Delta, chiffrement 7zAES (y compris l'en-tête chiffré). Les
/// autres (PPMd, BCJ2, filtres ARM…) lèvent [SevenZipUnsupportedException] :
/// l'appelant peut alors se rabattre sur l'outil `7z` s'il est installé.
///
/// L'archive est lue en mémoire, comme les autres formats de l'application.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;

import 'seven_zip_aes.dart';
import 'seven_zip_format.dart';

/// Méthode de compression non gérée par le lecteur intégré.
class SevenZipUnsupportedException implements Exception {
  final String method;
  const SevenZipUnsupportedException(this.method);
  @override
  String toString() => 'Méthode 7z non prise en charge : $method';
}

/// Mot de passe absent ou incorrect.
class SevenZipPasswordException implements Exception {
  final bool missing;
  const SevenZipPasswordException({required this.missing});
  @override
  String toString() => missing
      ? 'Cette archive est protégée par un mot de passe.'
      : 'Mot de passe incorrect.';
}

/// Entrée d'une archive 7z.
class SevenZipEntry {
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  /// Attributs Windows ; les 16 bits de poids fort portent le mode Unix
  /// quand le bit 0x8000 est présent (archives créées sous Linux).
  final int? attributes;
  final int? crc;

  /// Position du contenu : dossier (bloc compressé) et décalage dans sa
  /// sortie. -1 pour une entrée sans contenu.
  final int folder;
  final int offset;

  const SevenZipEntry({
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modified,
    this.attributes,
    this.crc,
    this.folder = -1,
    this.offset = 0,
  });

  /// Mode Unix (permissions et type), si l'archive le fournit.
  int? get unixMode {
    final a = attributes;
    if (a == null || a & 0x8000 == 0) return null;
    return (a >> 16) & 0xFFFF;
  }

  bool get isSymbolicLink => (unixMode ?? 0) & 0xF000 == 0xA000;
  bool get isAnti => false;
}

class _Coder {
  final Uint8List id;
  final int numIn;
  final int numOut;
  final Uint8List props;
  const _Coder(this.id, this.numIn, this.numOut, this.props);
}

class _Folder {
  final List<_Coder> coders;
  final List<(int, int)> bindPairs; // (inIndex, outIndex)
  final List<int> packedStreams; // indices des flux d'entrée non liés
  List<int> unpackSizes = const [];
  int? crc;

  _Folder(this.coders, this.bindPairs, this.packedStreams);

  int get numOutTotal => coders.fold(0, (n, c) => n + c.numOut);

  /// Flux de sortie principal : celui qu'aucune liaison ne consomme.
  int get mainOut {
    for (var i = 0; i < numOutTotal; i++) {
      if (!bindPairs.any((b) => b.$2 == i)) return i;
    }
    throw const FormatException('7z : dossier sans sortie');
  }

  int get unpackSize => unpackSizes[mainOut];
}

class _StreamsInfo {
  int packPos = 0;
  List<int> packSizes = const [];
  List<_Folder> folders = const [];

  /// Par dossier : nombre de fichiers, tailles et CRC de chacun.
  List<int> numUnpackStreams = const [];
  List<int> subSizes = const [];
  List<int?> subCrcs = const [];
}

class SevenZipArchive {
  final Uint8List _data;
  final String? _password;
  final List<SevenZipEntry> entries;
  final _StreamsInfo _streams;
  final Map<int, Uint8List> _folderCache = {};
  Uint8List? _keyCache;
  SevenZipAesParams? _keyParams;

  /// Vrai si l'en-tête (les noms de fichiers) est chiffré.
  bool headerEncrypted = false;

  SevenZipArchive._(this._data, this._password, this.entries, this._streams);

  /// Lit l'en-tête de [data] (le contenu n'est décompressé qu'à la demande).
  static SevenZipArchive open(Uint8List data, {String? password}) {
    if (data.length < 32 || !SevenZip.hasSignature(data)) {
      throw const FormatException('Ce n\'est pas une archive 7z');
    }
    final head = ByteData.sublistView(data, 0, 32);
    final startCrc = head.getUint32(8, Endian.little);
    if (arc.getCrc32(Uint8List.sublistView(data, 12, 32)) != startCrc) {
      throw const FormatException('7z : en-tête de départ corrompu');
    }
    final nextOffset = head.getUint64(12, Endian.little);
    final nextSize = head.getUint64(20, Endian.little);
    final nextCrc = head.getUint32(28, Endian.little);
    final archive = SevenZipArchive._(data, password, [], _StreamsInfo());
    if (nextSize == 0) return archive; // archive vide
    final start = 32 + nextOffset;
    if (start + nextSize > data.length) {
      throw const FormatException('7z : archive tronquée');
    }
    var header = Uint8List.sublistView(data, start, start + nextSize);
    if (arc.getCrc32(header) != nextCrc) {
      throw const FormatException('7z : en-tête corrompu');
    }
    // En-tête compressé (et éventuellement chiffré) : le décoder d'abord.
    while (header.isNotEmpty && header[0] == SevenZipId.encodedHeader) {
      final r = SevenZipByteReader(header)..readByte();
      final info = _readStreamsInfo(r);
      if (info.folders.isEmpty) {
        throw const FormatException('7z : en-tête codé vide');
      }
      final f = info.folders[0];
      if (f.coders.any((c) => SevenZip.methodOf(c.id) == SevenZipMethod.aes)) {
        archive.headerEncrypted = true;
      }
      final decoded = archive._decodeFolder(info, 0);
      if (f.crc != null && arc.getCrc32(decoded) != f.crc) {
        throw password == null
            ? const FormatException('7z : en-tête codé corrompu')
            : const SevenZipPasswordException(missing: false);
      }
      header = decoded;
    }
    final r = SevenZipByteReader(header);
    if (r.readByte() != SevenZipId.header) {
      throw const FormatException('7z : en-tête inattendu');
    }
    return archive._parseHeader(r)
      ..headerEncrypted = archive.headerEncrypted
      .._keyCache = archive._keyCache
      .._keyParams = archive._keyParams;
  }

  SevenZipArchive _parseHeader(SevenZipByteReader r) {
    var id = r.readByte();
    if (id == SevenZipId.archiveProperties) {
      while (true) {
        final t = r.readNumber();
        if (t == 0) break;
        r.skip(r.readNumber());
      }
      id = r.readByte();
    }
    if (id == SevenZipId.additionalStreamsInfo) {
      _readStreamsInfo(r); // non utilisé par 7-Zip lui-même
      id = r.readByte();
    }
    var streams = _StreamsInfo();
    if (id == SevenZipId.mainStreamsInfo) {
      streams = _readStreamsInfo(r);
      id = r.readByte();
    }
    final list = <SevenZipEntry>[];
    if (id == SevenZipId.filesInfo) {
      list.addAll(_readFiles(r, streams));
      id = r.readByte();
    }
    if (id != SevenZipId.end) {
      throw const FormatException('7z : fin d\'en-tête attendue');
    }
    return SevenZipArchive._(_data, _password, list, streams);
  }

  // ── Informations de flux ────────────────────────────────────────────────

  static _StreamsInfo _readStreamsInfo(SevenZipByteReader r) {
    final info = _StreamsInfo();
    while (true) {
      final id = r.readByte();
      switch (id) {
        case SevenZipId.end:
          return info;
        case SevenZipId.packInfo:
          info.packPos = r.readNumber();
          final n = r.readNumber();
          info.packSizes = List.filled(n, 0);
          while (true) {
            final t = r.readByte();
            if (t == SevenZipId.end) break;
            if (t == SevenZipId.size) {
              for (var i = 0; i < n; i++) {
                info.packSizes[i] = r.readNumber();
              }
            } else if (t == SevenZipId.crc) {
              r.readDigests(n);
            } else {
              throw FormatException('7z : propriété $t inattendue');
            }
          }
        case SevenZipId.unpackInfo:
          _readUnpackInfo(r, info);
        case SevenZipId.subStreamsInfo:
          _readSubStreams(r, info);
        default:
          throw FormatException('7z : propriété $id inattendue');
      }
    }
  }

  static void _readUnpackInfo(SevenZipByteReader r, _StreamsInfo info) {
    if (r.readByte() != SevenZipId.folder) {
      throw const FormatException('7z : dossiers attendus');
    }
    final n = r.readNumber();
    if (r.readByte() != 0) {
      throw const SevenZipUnsupportedException('dossiers externes');
    }
    info.folders = [for (var i = 0; i < n; i++) _readFolder(r)];
    if (r.readByte() != SevenZipId.codersUnpackSize) {
      throw const FormatException('7z : tailles attendues');
    }
    for (final f in info.folders) {
      f.unpackSizes = [for (var i = 0; i < f.numOutTotal; i++) r.readNumber()];
    }
    while (true) {
      final t = r.readByte();
      if (t == SevenZipId.end) break;
      if (t == SevenZipId.crc) {
        final crcs = r.readDigests(n);
        for (var i = 0; i < n; i++) {
          info.folders[i].crc = crcs[i];
        }
      } else {
        throw FormatException('7z : propriété $t inattendue');
      }
    }
  }

  static _Folder _readFolder(SevenZipByteReader r) {
    final numCoders = r.readNumber();
    final coders = <_Coder>[];
    var numInTotal = 0, numOutTotal = 0;
    for (var i = 0; i < numCoders; i++) {
      final flags = r.readByte();
      if (flags & 0x80 != 0) {
        throw const SevenZipUnsupportedException('méthodes alternatives');
      }
      final id = r.readBytes(flags & 0x0F);
      var numIn = 1, numOut = 1;
      if (flags & 0x10 != 0) {
        numIn = r.readNumber();
        numOut = r.readNumber();
      }
      final props =
          flags & 0x20 != 0 ? r.readBytes(r.readNumber()) : Uint8List(0);
      coders.add(_Coder(id, numIn, numOut, props));
      numInTotal += numIn;
      numOutTotal += numOut;
    }
    final bindPairs = [
      for (var i = 0; i < numOutTotal - 1; i++) (r.readNumber(), r.readNumber())
    ];
    final numPacked = numInTotal - bindPairs.length;
    final List<int> packed;
    if (numPacked == 1) {
      packed = [
        for (var i = 0; i < numInTotal; i++)
          if (!bindPairs.any((b) => b.$1 == i)) i
      ].take(1).toList();
    } else {
      packed = [for (var i = 0; i < numPacked; i++) r.readNumber()];
    }
    return _Folder(coders, bindPairs, packed);
  }

  static void _readSubStreams(SevenZipByteReader r, _StreamsInfo info) {
    final folders = info.folders;
    info.numUnpackStreams = List.filled(folders.length, 1);
    var t = r.readByte();
    if (t == SevenZipId.numUnpackStream) {
      for (var i = 0; i < folders.length; i++) {
        info.numUnpackStreams[i] = r.readNumber();
      }
      t = r.readByte();
    }
    final sizes = <int>[];
    final hasSizes = t == SevenZipId.size;
    for (var i = 0; i < folders.length; i++) {
      final count = info.numUnpackStreams[i];
      if (count == 0) continue;
      var sum = 0;
      for (var j = 0; j < count - 1; j++) {
        final s = hasSizes ? r.readNumber() : 0;
        sizes.add(s);
        sum += s;
      }
      sizes.add(folders[i].unpackSize - sum);
    }
    if (hasSizes) t = r.readByte();
    info.subSizes = sizes;

    // CRC : connus d'avance pour un dossier à un seul fichier et CRC.
    final crcs = <int?>[];
    var unknown = 0;
    for (var i = 0; i < folders.length; i++) {
      final count = info.numUnpackStreams[i];
      if (!(count == 1 && folders[i].crc != null)) unknown += count;
    }
    List<int?> read = List.filled(unknown, null);
    while (t != SevenZipId.end) {
      if (t == SevenZipId.crc) {
        read = r.readDigests(unknown);
      } else {
        r.skip(r.readNumber());
      }
      t = r.readByte();
    }
    var k = 0;
    for (var i = 0; i < folders.length; i++) {
      final count = info.numUnpackStreams[i];
      if (count == 1 && folders[i].crc != null) {
        crcs.add(folders[i].crc);
      } else {
        for (var j = 0; j < count; j++) {
          crcs.add(read[k++]);
        }
      }
    }
    info.subCrcs = crcs;
  }

  // ── Fichiers ────────────────────────────────────────────────────────────

  static List<SevenZipEntry> _readFiles(
      SevenZipByteReader r, _StreamsInfo streams) {
    final numFiles = r.readNumber();
    var emptyStream = List.filled(numFiles, false);
    var emptyFile = <bool>[];
    var anti = <bool>[];
    final names = List.filled(numFiles, '');
    final mtimes = List<DateTime?>.filled(numFiles, null);
    final attrs = List<int?>.filled(numFiles, null);

    while (true) {
      final type = r.readNumber();
      if (type == SevenZipId.end) break;
      final size = r.readNumber();
      final sub = SevenZipByteReader(r.readBytes(size));
      switch (type) {
        case SevenZipId.emptyStream:
          emptyStream = sub.readBits(numFiles);
        case SevenZipId.emptyFile:
          emptyFile = sub.readBits(emptyStream.where((e) => e).length);
        case SevenZipId.anti:
          anti = sub.readBits(emptyStream.where((e) => e).length);
        case SevenZipId.name:
          if (sub.readByte() != 0) {
            throw const SevenZipUnsupportedException('noms externes');
          }
          final raw = sub.remaining;
          var start = 0, idx = 0;
          for (var i = 0; i + 1 < raw.length && idx < numFiles; i += 2) {
            if (raw[i] == 0 && raw[i + 1] == 0) {
              names[idx++] = _utf16(raw, start, i);
              start = i + 2;
            }
          }
        case SevenZipId.mTime:
          final defined = sub.readOptionalBits(numFiles);
          if (sub.readByte() != 0) break; // données externes : ignorées
          for (var i = 0; i < numFiles; i++) {
            if (defined[i]) mtimes[i] = SevenZip.fromFileTime(sub.readUint64());
          }
        case SevenZipId.winAttributes:
          final defined = sub.readOptionalBits(numFiles);
          if (sub.readByte() != 0) break;
          for (var i = 0; i < numFiles; i++) {
            if (defined[i]) attrs[i] = sub.readUint32();
          }
        default:
          break; // dates de création / d'accès, rembourrage… ignorés
      }
    }

    final entries = <SevenZipEntry>[];
    var emptyIndex = 0, folder = 0, inFolder = 0, sub = 0, offset = 0;
    for (var i = 0; i < numFiles; i++) {
      final name = names[i].replaceAll('\\', '/');
      if (emptyStream[i]) {
        final isAnti = emptyIndex < anti.length && anti[emptyIndex];
        final isFile = emptyIndex < emptyFile.length && emptyFile[emptyIndex];
        emptyIndex++;
        if (isAnti) continue; // marqueur de suppression (mises à jour)
        entries.add(SevenZipEntry(
            name: name,
            isDirectory: !isFile,
            size: 0,
            modified: mtimes[i],
            attributes: attrs[i]));
        continue;
      }
      while (folder < streams.folders.length &&
          inFolder >= streams.numUnpackStreams[folder]) {
        folder++;
        inFolder = 0;
        offset = 0;
      }
      if (folder >= streams.folders.length) {
        throw const FormatException('7z : plus de fichiers que de flux');
      }
      final size = streams.subSizes[sub];
      entries.add(SevenZipEntry(
        name: name,
        isDirectory: (attrs[i] ?? 0) & 0x10 != 0,
        size: size,
        modified: mtimes[i],
        attributes: attrs[i],
        crc: streams.subCrcs.length > sub ? streams.subCrcs[sub] : null,
        folder: folder,
        offset: offset,
      ));
      offset += size;
      inFolder++;
      sub++;
    }
    return entries;
  }

  static String _utf16(Uint8List b, int start, int end) {
    final units = Uint16List((end - start) ~/ 2);
    for (var i = 0; i < units.length; i++) {
      units[i] = b[start + 2 * i] | (b[start + 2 * i + 1] << 8);
    }
    return String.fromCharCodes(units);
  }

  // ── Contenu ─────────────────────────────────────────────────────────────

  /// Contenu de [entry], CRC vérifié.
  Uint8List read(SevenZipEntry entry) {
    if (entry.folder < 0) return Uint8List(0);
    final out =
        _folderCache[entry.folder] ??= _decodeFolder(_streams, entry.folder);
    if (entry.offset + entry.size > out.length) {
      throw const FormatException('7z : contenu tronqué');
    }
    final data =
        Uint8List.sublistView(out, entry.offset, entry.offset + entry.size);
    if (entry.crc != null && arc.getCrc32(data) != entry.crc) {
      throw _password != null || _usesAes(entry.folder)
          ? SevenZipPasswordException(missing: _password == null)
          : FormatException('7z : « ${entry.name} » est corrompu (CRC)');
    }
    return data;
  }

  /// Vrai si un contenu ou l'en-tête est chiffré.
  bool get isEncrypted =>
      headerEncrypted ||
      [for (var i = 0; i < _streams.folders.length; i++) i].any(_usesAes);

  bool _usesAes(int folder) => _streams.folders[folder].coders
      .any((c) => SevenZip.methodOf(c.id) == SevenZipMethod.aes);

  /// Décode le dossier [index] de [info] (sortie principale entière).
  Uint8List _decodeFolder(_StreamsInfo info, int index) {
    final folder = info.folders[index];
    var packOffset = 32 + info.packPos;
    var packIndex = 0;
    for (var i = 0; i < index; i++) {
      for (var j = 0; j < info.folders[i].packedStreams.length; j++) {
        packOffset += info.packSizes[packIndex++];
      }
    }
    // Flux compressés du dossier, indexés par numéro de flux d'entrée.
    final packed = <int, Uint8List>{};
    for (final inIndex in folder.packedStreams) {
      final size = info.packSizes[packIndex++];
      if (packOffset + size > _data.length) {
        throw const FormatException('7z : archive tronquée');
      }
      packed[inIndex] =
          Uint8List.sublistView(_data, packOffset, packOffset + size);
      packOffset += size;
    }

    // Premier flux d'entrée / de sortie de chaque codeur.
    final inStart = <int>[], outStart = <int>[];
    var ins = 0, outs = 0;
    for (final c in folder.coders) {
      inStart.add(ins);
      outStart.add(outs);
      ins += c.numIn;
      outs += c.numOut;
    }

    Uint8List decodeOut(int outIndex) {
      var coderIndex = 0;
      while (coderIndex + 1 < folder.coders.length &&
          outStart[coderIndex + 1] <= outIndex) {
        coderIndex++;
      }
      final coder = folder.coders[coderIndex];
      if (coder.numIn != 1 || coder.numOut != 1) {
        throw SevenZipUnsupportedException(SevenZip.methodName(coder.id));
      }
      final inIndex = inStart[coderIndex];
      final bound = folder.bindPairs.where((b) => b.$1 == inIndex);
      final input =
          bound.isEmpty ? packed[inIndex]! : decodeOut(bound.first.$2);
      return _runCoder(coder, input, folder.unpackSizes[outIndex]);
    }

    final out = decodeOut(folder.mainOut);
    if (out.length != folder.unpackSize) {
      throw const FormatException('7z : taille décompressée incorrecte');
    }
    return out;
  }

  Uint8List _runCoder(_Coder coder, Uint8List input, int outSize) {
    final method = SevenZip.methodOf(coder.id);
    try {
      switch (method) {
        case SevenZipMethod.copy:
          return input.length == outSize
              ? input
              : Uint8List.sublistView(input, 0, outSize);
        case SevenZipMethod.lzma:
          return _lzma(coder.props, input, outSize);
        case SevenZipMethod.lzma2:
          return _lzma2(input, outSize);
        case SevenZipMethod.deflate:
          final out = arc.Inflate(input).getBytes();
          return _exact(out, outSize);
        case SevenZipMethod.bzip2:
          return _exact(arc.BZip2Decoder().decodeBytes(input), outSize);
        case SevenZipMethod.bcjX86:
          final out = Uint8List.fromList(input);
          sevenZipBcjX86Decode(out);
          return _exact(out, outSize);
        case SevenZipMethod.delta:
          return _delta(coder.props, input, outSize);
        case SevenZipMethod.aes:
          return _aes(coder.props, input, outSize);
        case null:
          throw SevenZipUnsupportedException(SevenZip.methodName(coder.id));
      }
    } on SevenZipUnsupportedException {
      rethrow;
    } on SevenZipPasswordException {
      rethrow;
    } catch (e) {
      // Données chiffrées avec un mauvais mot de passe : le décodage échoue.
      if (_password != null) {
        throw const SevenZipPasswordException(missing: false);
      }
      throw FormatException('7z : données corrompues (${method?.name}) : $e');
    }
  }

  static Uint8List _exact(List<int> out, int size) {
    if (out.length < size) {
      throw const FormatException('7z : sortie trop courte');
    }
    final bytes = out is Uint8List ? out : Uint8List.fromList(out);
    return bytes.length == size ? bytes : Uint8List.sublistView(bytes, 0, size);
  }

  static Uint8List _lzma(Uint8List props, Uint8List input, int outSize) {
    if (props.length < 5) throw const FormatException('LZMA : propriétés');
    var d = props[0];
    final lc = d % 9;
    d ~/= 9;
    final lp = d % 5, pb = d ~/ 5;
    final dec = arc.LzmaDecoder()
      ..reset(
          literalContextBits: lc,
          literalPositionBits: lp,
          positionBits: pb,
          resetDictionary: true);
    return dec.decode(arc.InputMemoryStream(input), outSize);
  }

  /// LZMA2 : suite de blocs, chacun compressé (LZMA) ou brut.
  static Uint8List _lzma2(Uint8List input, int outSize) {
    final out = Uint8List(outSize);
    var written = 0, pos = 0;
    final dec = arc.LzmaDecoder();
    var needProps = true;
    while (pos < input.length) {
      final control = input[pos++];
      if (control == 0) break;
      if (control & 0x80 == 0) {
        if (control > 2) throw const FormatException('LZMA2 : bloc inconnu');
        final size = ((input[pos] << 8) | input[pos + 1]) + 1;
        pos += 2;
        final chunk = dec.decodeUncompressed(
            arc.InputMemoryStream(
                Uint8List.sublistView(input, pos, pos + size)),
            size);
        out.setRange(written, written + size, chunk);
        written += size;
        pos += size;
        continue;
      }
      final unpacked =
          (((control & 0x1F) << 16) | (input[pos] << 8) | input[pos + 1]) + 1;
      final packedSize = ((input[pos + 2] << 8) | input[pos + 3]) + 1;
      pos += 4;
      final reset = (control >> 5) & 3;
      if (reset >= 2) {
        var d = input[pos++];
        final lc = d % 9;
        d ~/= 9;
        dec.reset(
            literalContextBits: lc,
            literalPositionBits: d % 5,
            positionBits: d ~/ 5,
            resetDictionary: reset == 3);
        needProps = false;
      } else if (needProps) {
        throw const FormatException('LZMA2 : propriétés manquantes');
      } else if (reset == 1) {
        dec.reset();
      }
      final chunk = dec.decode(
          arc.InputMemoryStream(
              Uint8List.sublistView(input, pos, pos + packedSize)),
          unpacked);
      out.setRange(written, written + unpacked, chunk);
      written += unpacked;
      pos += packedSize;
      // Garde le dictionnaire borné (les blocs suivants s'y réfèrent).
      dec.trimDictionary(1 << 26);
    }
    if (written != outSize) throw const FormatException('LZMA2 : taille');
    return out;
  }

  static Uint8List _delta(Uint8List props, Uint8List input, int outSize) {
    final dist = (props.isEmpty ? 0 : props[0]) + 1;
    final out = Uint8List.fromList(Uint8List.sublistView(input, 0, outSize));
    for (var i = dist; i < out.length; i++) {
      out[i] = (out[i] + out[i - dist]) & 0xFF;
    }
    return out;
  }

  Uint8List _aes(Uint8List props, Uint8List input, int outSize) {
    final password = _password;
    if (password == null) throw const SevenZipPasswordException(missing: true);
    final params = SevenZipAesParams.parse(props);
    final same = _keyParams != null &&
        _keyParams!.cyclesPower == params.cyclesPower &&
        _listEq(_keyParams!.salt, params.salt);
    final key = same ? _keyCache! : SevenZipAes.deriveKey(password, params);
    _keyCache = key;
    _keyParams = params;
    final out = SevenZipAes.decrypt(input, key, params.iv);
    return _exact(out, outSize);
  }

  static bool _listEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── Conversion ──────────────────────────────────────────────────────────

  /// Archive du paquet `archive` (contenus décompressés, CRC vérifiés) :
  /// réutilise l'extraction, l'édition et l'écriture communes.
  arc.Archive toArchive({bool Function(SevenZipEntry entry)? where}) {
    final out = arc.Archive();
    for (final e in entries) {
      if (where != null && !where(e)) continue;
      final arc.ArchiveFile file;
      if (e.isDirectory) {
        file = arc.ArchiveFile.directory('${e.name}/');
      } else if (e.isSymbolicLink) {
        file = arc.ArchiveFile.symlink(e.name, utf8.decode(read(e)));
      } else {
        file = arc.ArchiveFile.bytes(e.name, read(e));
      }
      if (e.modified != null) {
        file.lastModTime = e.modified!.millisecondsSinceEpoch ~/ 1000;
      }
      final mode = e.unixMode;
      if (mode != null && mode & 0x1FF != 0) file.mode = mode & 0x1FF;
      out.addFile(file);
    }
    return out;
  }
}
