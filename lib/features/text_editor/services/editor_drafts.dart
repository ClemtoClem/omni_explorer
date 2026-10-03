/// @file editor_drafts.dart
/// @brief Brouillons des onglets non sauvegardés, écrits quand l'application
/// passe en arrière-plan : si le système la tue, les modifications sont
/// proposées à la réouverture du fichier.
///
/// Le fichier de l'utilisateur n'est jamais modifié : le brouillon vit dans
/// le dossier de support de l'application (un fichier JSON par chemin), et
/// disparaît à la sauvegarde ou quand l'utilisateur abandonne ses
/// modifications.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/atomic_write.dart';
import 'editor_encoding.dart';

class EditorDraft {
  final String path;
  final String content;
  final EditorEncoding encoding;

  /// Date de modification et taille du fichier au moment de son ouverture :
  /// si elles ont changé, le fichier a été modifié ailleurs depuis.
  final DateTime? baseModified;
  final int? baseSize;

  final DateTime savedAt;

  const EditorDraft({
    required this.path,
    required this.content,
    required this.encoding,
    required this.savedAt,
    this.baseModified,
    this.baseSize,
  });

  Map<String, dynamic> toJson() => {
        'v': 1,
        'path': path,
        'content': content,
        'encoding': encoding.name,
        'savedAt': savedAt.millisecondsSinceEpoch,
        if (baseModified != null)
          'baseModified': baseModified!.millisecondsSinceEpoch,
        if (baseSize != null) 'baseSize': baseSize,
      };

  static EditorDraft? fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1 || j['path'] is! String || j['content'] is! String) {
      return null;
    }
    DateTime? ms(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return EditorDraft(
      path: j['path'] as String,
      content: j['content'] as String,
      encoding: EditorEncoding.values.asNameMap()[j['encoding']] ??
          EditorEncoding.utf8,
      savedAt: ms(j['savedAt']) ?? DateTime.now(),
      baseModified: ms(j['baseModified']),
      baseSize: j['baseSize'] as int?,
    );
  }
}

abstract final class EditorDrafts {
  /// Dossier des brouillons. Remplaçable en test (pas de path_provider).
  static Future<Directory> Function() directory = () async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'editor_drafts'));

  /// Nom de fichier stable pour [path] : empreinte FNV-1a 64 bits (un
  /// chemin complet dépasserait la longueur maximale d'un nom de fichier).
  /// Le chemin est aussi stocké dans le brouillon, et vérifié à la lecture.
  static String _fileName(String path) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(path)) {
      h ^= b;
      h *= 0x100000001b3; // débordement sur 64 bits, voulu
    }
    return '${h.toUnsigned(64).toRadixString(16).padLeft(16, '0')}.json';
  }

  static Future<File> _file(String path) async =>
      File(p.join((await directory()).path, _fileName(path)));

  static Future<void> save(EditorDraft draft) async {
    final f = await _file(draft.path);
    await f.parent.create(recursive: true);
    await AtomicWrite.string(f.path, jsonEncode(draft.toJson()));
  }

  /// Brouillon de [path], ou `null` (aucun, illisible, ou d'un autre chemin
  /// de même empreinte).
  static Future<EditorDraft?> load(String path) async {
    try {
      final f = await _file(path);
      if (!await f.exists()) return null;
      final draft = EditorDraft.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      return draft?.path == path ? draft : null;
    } catch (_) {
      return null; // brouillon corrompu : on ne bloque pas l'ouverture
    }
  }

  static Future<void> delete(String path) async {
    try {
      final f = await _file(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Au pire, le brouillon sera proposé (et refusé) à la réouverture.
    }
  }
}
