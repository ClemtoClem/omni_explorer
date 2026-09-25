/// @file atomic_write.dart
/// @brief Écriture atomique : le fichier contient soit l'ancien contenu, soit
/// le nouveau, jamais un mélange tronqué — même si l'application est tuée ou
/// si le stockage se remplit en cours d'écriture.
///
/// Principe : écrire dans un fichier temporaire du même dossier, forcer son
/// écriture sur le disque, puis le renommer par-dessus la cible (`rename` est
/// atomique au sein d'un même système de fichiers).
///
/// Préservé : les permissions de l'original (ex. script exécutable) et les
/// liens symboliques (on écrit dans la cible du lien, le lien reste un lien).
/// Non préservé : le propriétaire, et les autres liens physiques (« hard
/// links ») vers l'ancien contenu, qui gardent l'ancienne version.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class AtomicWrite {
  AtomicWrite._();

  /// Écrit [bytes] dans [path] de façon atomique.
  ///
  /// Si le dossier n'autorise pas la création du fichier temporaire alors que
  /// le fichier lui-même est modifiable (cas rare), l'écriture se fait
  /// directement dans le fichier, comme avant : sauvegarder reste possible,
  /// sans la garantie d'atomicité.
  static Future<void> bytes(String path, List<int> bytes) async {
    final target = resolveTarget(path);
    final original = File(target);
    final exists = await original.exists();
    final tmp = File(p.join(p.dirname(target),
        '.${p.basename(target)}.tmp-${DateTime.now().microsecondsSinceEpoch}'));

    try {
      await tmp.create(exclusive: true);
    } on FileSystemException {
      if (!exists) rethrow;
      await original.writeAsBytes(bytes, flush: true);
      return;
    }

    try {
      if (exists && !Platform.isWindows && _mode(original) != _mode(tmp)) {
        // Le temporaire hérite des permissions par défaut : on le recrée par
        // copie de l'original, qui conserve ses permissions.
        await tmp.delete();
        await original.copy(tmp.path);
      }
      // FileMode.write tronque le temporaire avant d'écrire.
      await tmp.writeAsBytes(bytes, mode: FileMode.write, flush: true);
      await tmp.rename(target);
    } catch (_) {
      // L'original est intact ; seul le temporaire est à retirer.
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// Écrit [text] (UTF-8) dans [path] de façon atomique.
  static Future<void> string(String path, String text) =>
      bytes(path, utf8.encode(text));

  /// Chemin réellement écrit : la cible finale si [path] est un lien
  /// symbolique (sinon `rename` remplacerait le lien par un fichier).
  static String resolveTarget(String path) {
    var current = path;
    // Chaîne de liens, bornée pour ne pas boucler sur un cycle.
    for (var i = 0; i < 40; i++) {
      if (FileSystemEntity.typeSync(current, followLinks: false) !=
          FileSystemEntityType.link) {
        return current;
      }
      final target = Link(current).targetSync();
      current = p.normalize(
          p.isAbsolute(target) ? target : p.join(p.dirname(current), target));
    }
    throw FileSystemException('Trop de liens symboliques', path);
  }

  static int _mode(File f) => f.statSync().mode & 0xFFF; // 0o7777
}
