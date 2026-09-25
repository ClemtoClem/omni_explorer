/// @file hex_file_io.dart
/// @brief Lecture / écriture des fichiers ouverts dans l'éditeur hexadécimal.
///
/// Les gros fichiers ne sont chargés que partiellement ([maxLoadedBytes]).
/// Invariant de sécurité : on n'écrit JAMAIS un tampon dont la taille diffère
/// de celle du fichier d'origine — un tampon partiel réécrit tel quel
/// tronquerait le fichier (perte de données).

import 'dart:io';
import 'dart:typed_data';

/// Contenu chargé pour l'éditeur hexadécimal.
class HexLoadResult {
  /// Octets chargés (au plus [HexFileIO.maxLoadedBytes]).
  final Uint8List bytes;

  /// Taille réelle du fichier au moment du chargement.
  final int fileLength;

  const HexLoadResult(this.bytes, this.fileLength);

  /// Vrai si seul le début du fichier a été chargé.
  bool get isTruncated => bytes.length < fileLength;
}

/// Levée quand une sauvegarde hexadécimale corromprait le fichier.
class HexSaveRefused implements Exception {
  /// Explication destinée à l'utilisateur.
  final String message;

  const HexSaveRefused(this.message);

  @override
  String toString() => message;
}

class HexFileIO {
  HexFileIO._();

  /// Taille maximale chargée en mémoire (32 Mio).
  static const int maxLoadedBytes = 32 * 1024 * 1024;

  /// Charge au plus [maxBytes] octets depuis le début de [path], sans lire
  /// le reste du fichier (un fichier de plusieurs Go ne sature pas la RAM).
  static Future<HexLoadResult> load(
    String path, {
    int maxBytes = maxLoadedBytes,
  }) async {
    final raf = await File(path).open();
    try {
      final length = await raf.length();
      final toRead = length < maxBytes ? length : maxBytes;
      final bytes = await raf.read(toRead);
      return HexLoadResult(bytes, length);
    } finally {
      await raf.close();
    }
  }

  /// Écrit [bytes] dans [path], dont la taille au chargement était
  /// [loadedFileLength].
  ///
  /// Refuse ([HexSaveRefused]) si le tampon est partiel, ou si le fichier a
  /// changé de taille sur le disque depuis son chargement (modifié par une
  /// autre application : l'écraser ferait perdre ces changements).
  static Future<void> save(
    String path,
    Uint8List bytes, {
    required int loadedFileLength,
  }) async {
    if (bytes.length != loadedFileLength) {
      throw const HexSaveRefused(
          'Sauvegarde refusée : seul le début de ce fichier est chargé. '
          'L\'enregistrer tronquerait le fichier.');
    }
    final current = await File(path).length();
    if (current != loadedFileLength) {
      throw const HexSaveRefused(
          'Sauvegarde refusée : le fichier a été modifié sur le disque depuis '
          'son ouverture. Rouvrez-le avant de le modifier.');
    }
    await File(path).writeAsBytes(bytes, flush: true);
  }
}
