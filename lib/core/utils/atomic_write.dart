/// @file atomic_write.dart
/// @brief Écriture atomique : le fichier contient soit l'ancien contenu, soit
/// le nouveau, jamais un mélange tronqué — même si l'application est tuée ou
/// si le stockage se remplit en cours d'écriture.
///
/// Principe : écrire dans un fichier temporaire du même dossier, forcer son
/// écriture sur le disque, puis le renommer par-dessus la cible (`rename` est
/// atomique au sein d'un même système de fichiers).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class AtomicWrite {
  AtomicWrite._();

  /// Écrit [bytes] dans [path] de façon atomique.
  static Future<void> bytes(String path, List<int> bytes) async {
    final target = File(path);
    final tmp = File(p.join(p.dirname(path),
        '.${p.basename(path)}.tmp-${DateTime.now().microsecondsSinceEpoch}'));
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      // L'original est intact ; seul le temporaire est à retirer.
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// Écrit [text] (UTF-8) dans [path] de façon atomique.
  static Future<void> string(String path, String text) =>
      bytes(path, utf8.encode(text));
}
