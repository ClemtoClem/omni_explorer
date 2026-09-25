/// @file file_naming.dart
/// @brief Noms libres pour les doublons, communs aux fichiers du disque et
/// aux entrées d'archive.
///
/// - Conflit (extraction, déplacement, copie vers un autre dossier) : un
///   point et un numéro avant l'extension — `rapport.1.txt`,
///   `rapport.2.txt`…
/// - Duplication dans le même dossier : `rapport.copy.1.txt`,
///   `rapport.copy.2.txt`… Dupliquer une copie reprend la numérotation de
///   l'original (`rapport.copy.1.txt` → `rapport.copy.2.txt`).
///
/// Les doubles extensions d'archive sont respectées (`site.1.tar.gz`) ; un
/// dossier ou un fichier caché sans extension reçoit le suffixe à la fin
/// (`photos.1`, `.bashrc.1`).

class FileNaming {
  FileNaming._();

  /// Extensions composées, traitées comme un tout.
  static const List<String> compoundExtensions = [
    '.tar.gz',
    '.tar.bz2',
    '.tar.xz',
    '.tar.zst',
    '.tar.lz',
    '.tar.lzma',
  ];

  static final RegExp _copySuffix = RegExp(r'^(.*)\.copy\.\d+$');

  /// Sépare [name] en base et extension (extension vide pour un dossier).
  static (String base, String ext) split(String name,
      {required bool isDirectory}) {
    if (isDirectory) return (name, '');
    final lower = name.toLowerCase();
    for (final ext in compoundExtensions) {
      if (lower.endsWith(ext) && name.length > ext.length) {
        final cut = name.length - ext.length;
        return (name.substring(0, cut), name.substring(cut));
      }
    }
    final dot = name.lastIndexOf('.');
    // « .bashrc » : le point initial ne marque pas une extension.
    if (dot <= 0 || dot == name.length - 1) return (name, '');
    return (name.substring(0, dot), name.substring(dot));
  }

  /// Premier nom libre pour résoudre un conflit : `nom.1.ext`, `nom.2.ext`…
  static String numbered(String name, bool Function(String candidate) taken,
      {required bool isDirectory}) {
    final (base, ext) = split(name, isDirectory: isDirectory);
    for (var i = 1;; i++) {
      final candidate = '$base.$i$ext';
      if (!taken(candidate)) return candidate;
    }
  }

  /// Premier nom libre pour une duplication : `nom.copy.1.ext`…
  static String copy(String name, bool Function(String candidate) taken,
      {required bool isDirectory}) {
    var (base, ext) = split(name, isDirectory: isDirectory);
    final already = _copySuffix.firstMatch(base);
    if (already != null) base = already.group(1)!;
    for (var i = 1;; i++) {
      final candidate = '$base.copy.$i$ext';
      if (!taken(candidate)) return candidate;
    }
  }
}
