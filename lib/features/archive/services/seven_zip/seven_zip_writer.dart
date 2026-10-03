/// @file seven_zip_writer.dart
/// @brief Écriture d'archives 7z en Dart pur : un bloc « solide » compressé
/// en LZMA, chiffré en AES-256 si un mot de passe est donné (avec, en
/// option, l'en-tête — donc les noms de fichiers — comme `7z -mhe=on`).
///
/// Les archives produites s'ouvrent avec 7-Zip, p7zip, Ark, File Roller…
/// Les modes Unix sont conservés comme le fait p7zip (attribut 0x8000).

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;

import 'lzma_encoder.dart';
import 'seven_zip_aes.dart';
import 'seven_zip_format.dart';

/// Flux compressé (et éventuellement chiffré) avec la description de son
/// dossier.
class _PackedFolder {
  final Uint8List packed;
  final Uint8List folder; // description du dossier (codeurs, liaisons)
  final List<int> unpackSizes;

  const _PackedFolder(this.packed, this.folder, this.unpackSizes);
}

abstract final class SevenZipWriter {
  /// Archive 7z contenant les fichiers de [archive], dans cet ordre. Les
  /// noms de dossiers peuvent finir par « / ».
  static Uint8List encode(
    arc.Archive archive, {
    String? password,
    bool encryptHeader = false,
  }) {
    final files = archive.files;
    final names = <String>[];
    final emptyStream = <bool>[];
    final emptyFile = <bool>[];
    final mtimes = <int?>[];
    final attributes = <int>[];
    final contents = <Uint8List>[];

    for (final f in files) {
      var name = f.name;
      while (name.endsWith('/')) {
        name = name.substring(0, name.length - 1);
      }
      if (name.isEmpty) continue;
      names.add(name);
      mtimes.add(f.lastModTime > 0
          ? SevenZip.toFileTime(
              DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000))
          : null);
      final perms = f.mode & 0x1FF;
      if (!f.isFile) {
        emptyStream.add(true);
        emptyFile.add(false);
        attributes.add(_attr(0x10, 0x4000 | (perms == 0 ? 0x1ED : perms)));
        continue;
      }
      final Uint8List data;
      final int type;
      if (f.isSymbolicLink) {
        data = Uint8List.fromList(utf8.encode(f.symbolicLink!));
        type = 0xA000 | 0x1FF;
      } else {
        final raw = f.readBytes() ?? Uint8List(0);
        data = raw;
        type = 0x8000 | (perms == 0 ? 0x1A4 : perms);
      }
      attributes.add(_attr(0x20, type));
      if (data.isEmpty) {
        emptyStream.add(true);
        emptyFile.add(true);
      } else {
        emptyStream.add(false);
        emptyFile.add(false);
        contents.add(data);
      }
    }

    final pw = (password == null || password.isEmpty) ? null : password;
    final out = BytesBuilder(copy: false);

    // ── Données ──
    _PackedFolder? main;
    if (contents.isNotEmpty) {
      final total = contents.fold<int>(0, (n, c) => n + c.length);
      final solid = Uint8List(total);
      var at = 0;
      for (final c in contents) {
        solid.setAll(at, c);
        at += c.length;
      }
      main = _pack(solid, pw);
      out.add(main.packed);
    }

    // ── En-tête ──
    final h = SevenZipByteWriter()..byte(SevenZipId.header);
    if (main != null) {
      h.byte(SevenZipId.mainStreamsInfo);
      _writeStreamsInfo(h, 0, main, contents);
    }
    if (names.isNotEmpty) {
      h.byte(SevenZipId.filesInfo);
      _writeFilesInfo(h, names, emptyStream, emptyFile, mtimes, attributes);
    }
    h.byte(SevenZipId.end);
    var header = h.toBytes();

    // En-tête chiffré : compressé, chiffré, rangé après les données, et
    // décrit par un petit en-tête « codé ».
    if (pw != null && encryptHeader) {
      final packedHeader = _pack(header, pw);
      final headerPos = out.length;
      out.add(packedHeader.packed);
      final e = SevenZipByteWriter()..byte(SevenZipId.encodedHeader);
      _writeStreamsInfo(e, headerPos, packedHeader, null,
          folderCrc: arc.getCrc32(header));
      header = e.toBytes();
    }

    final body = out.toBytes();
    final start = ByteData(20)
      ..setUint64(0, body.length, Endian.little)
      ..setUint64(8, header.length, Endian.little)
      ..setUint32(16, arc.getCrc32(header), Endian.little);
    final startBytes = start.buffer.asUint8List();
    return (BytesBuilder(copy: false)
          ..add(SevenZip.signature)
          ..add([0, 4])
          ..add((ByteData(4)
                ..setUint32(0, arc.getCrc32(startBytes), Endian.little))
              .buffer
              .asUint8List())
          ..add(startBytes)
          ..add(body)
          ..add(header))
        .toBytes();
  }

  /// Attributs : Windows (bas) et mode Unix (haut, marqué par 0x8000).
  static int _attr(int windows, int unixMode) =>
      windows | 0x8000 | (unixMode << 16);

  /// Compresse [data] en LZMA, puis la chiffre si [password].
  static _PackedFolder _pack(Uint8List data, String? password) {
    final props = LzmaProperties(
        dictionarySize: LzmaProperties.dictionaryFor(data.length));
    final lzma = LzmaEncoder.encode(data, props);
    final f = SevenZipByteWriter();
    if (password == null) {
      f.number(1);
      _coder(f, SevenZip.idLzma, props.toBytes());
      return _PackedFolder(lzma, f.toBytes(), [data.length]);
    }
    final aes = SevenZipAesParams.random();
    final encrypted =
        SevenZipAes.encrypt(lzma, SevenZipAes.deriveKey(password, aes), aes.iv);
    // Codeur 0 : LZMA (sortie principale) ; codeur 1 : AES. L'entrée du LZMA
    // (flux d'entrée 0) est la sortie de l'AES (flux de sortie 1).
    f.number(2);
    _coder(f, SevenZip.idLzma, props.toBytes());
    _coder(f, SevenZip.idAes, aes.toBytes());
    f
      ..number(0)
      ..number(1);
    return _PackedFolder(encrypted, f.toBytes(), [data.length, lzma.length]);
  }

  static void _coder(SevenZipByteWriter w, List<int> id, Uint8List props) {
    w.byte(id.length | 0x20); // codeur simple, avec propriétés
    w.bytes(id);
    w.number(props.length);
    w.bytes(props);
  }

  /// [contents] : fichiers du dossier (tailles et CRC), ou `null` pour un
  /// en-tête codé (un seul flux, CRC dans [folderCrc]).
  static void _writeStreamsInfo(SevenZipByteWriter w, int packPos,
      _PackedFolder folder, List<Uint8List>? contents,
      {int? folderCrc}) {
    w
      ..byte(SevenZipId.packInfo)
      ..number(packPos)
      ..number(1)
      ..byte(SevenZipId.size)
      ..number(folder.packed.length)
      ..byte(SevenZipId.end);

    w
      ..byte(SevenZipId.unpackInfo)
      ..byte(SevenZipId.folder)
      ..number(1)
      ..byte(0) // pas de données externes
      ..bytes(folder.folder)
      ..byte(SevenZipId.codersUnpackSize);
    for (final s in folder.unpackSizes) {
      w.number(s);
    }
    if (folderCrc != null) {
      w
        ..byte(SevenZipId.crc)
        ..byte(1)
        ..uint32(folderCrc);
    }
    w.byte(SevenZipId.end);

    if (contents != null) {
      w
        ..byte(SevenZipId.subStreamsInfo)
        ..byte(SevenZipId.numUnpackStream)
        ..number(contents.length);
      if (contents.length > 1) {
        w.byte(SevenZipId.size);
        for (var i = 0; i < contents.length - 1; i++) {
          w.number(contents[i].length);
        }
      }
      w
        ..byte(SevenZipId.crc)
        ..byte(1);
      for (final c in contents) {
        w.uint32(arc.getCrc32(c));
      }
      w.byte(SevenZipId.end);
    }
    w.byte(SevenZipId.end);
  }

  static void _writeFilesInfo(
    SevenZipByteWriter w,
    List<String> names,
    List<bool> emptyStream,
    List<bool> emptyFile,
    List<int?> mtimes,
    List<int> attributes,
  ) {
    void property(int id, void Function(SevenZipByteWriter) body) {
      final sub = SevenZipByteWriter();
      body(sub);
      w
        ..byte(id)
        ..number(sub.length)
        ..bytes(sub.toBytes());
    }

    w.number(names.length);
    if (emptyStream.contains(true)) {
      property(SevenZipId.emptyStream, (s) => s.bits(emptyStream));
      final files = [
        for (var i = 0; i < names.length; i++)
          if (emptyStream[i]) emptyFile[i]
      ];
      if (files.contains(true)) {
        property(SevenZipId.emptyFile, (s) => s.bits(files));
      }
    }
    property(SevenZipId.name, (s) {
      s.byte(0);
      for (final n in names) {
        for (final u in n.codeUnits) {
          s
            ..byte(u)
            ..byte(u >> 8);
        }
        s
          ..byte(0)
          ..byte(0);
      }
    });
    if (mtimes.any((t) => t != null)) {
      property(SevenZipId.mTime, (s) {
        s
          ..optionalBits([for (final t in mtimes) t != null])
          ..byte(0);
        for (final t in mtimes) {
          if (t != null) s.uint64(t);
        }
      });
    }
    property(SevenZipId.winAttributes, (s) {
      s
        ..byte(1) // tous définis
        ..byte(0);
      for (final a in attributes) {
        s.uint32(a);
      }
    });
    w.byte(SevenZipId.end);
  }
}
