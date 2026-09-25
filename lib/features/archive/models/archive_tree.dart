/// @file archive_tree.dart
/// @brief Arborescence d'une archive, reconstruite à partir de la liste plate
/// de ses entrées.
///
/// Corrige ce qui faussait l'affichage :
/// - chemins hétérogènes : `\`, `./`, `//`, `/` initial, `/` final des
///   dossiers ;
/// - dossiers implicites : beaucoup d'archives ne listent que `a/b/c.txt`,
///   sans entrée pour `a/` ni `a/b/` ; ils sont recréés ;
/// - ordre : le contenu d'un dossier est listé à part (dossiers d'abord),
///   au lieu d'un tri global qui éloignait les fichiers de leur dossier.
///
/// Les segments `..` sont gardés tels quels (visibles), l'extraction les
/// refusant de toute façon (P0.1).

/// Nœud de l'arborescence.
class ArchiveNode {
  /// Chemin normalisé : segments séparés par `/`, sans `/` initial ni final.
  final String path;
  final bool isDirectory;
  final int size;
  final int compressedSize;
  final DateTime? modified;

  /// Vrai si le dossier n'a pas d'entrée propre dans l'archive.
  final bool implicit;

  const ArchiveNode({
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.compressedSize = 0,
    this.modified,
    this.implicit = false,
  });

  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  String get parent {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }
}

/// Entrée brute telle que lue dans l'archive.
class RawArchiveEntry {
  final String name;
  final bool isDirectory;
  final int size;
  final int compressedSize;
  final DateTime? modified;

  const RawArchiveEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.compressedSize = 0,
    this.modified,
  });
}

class ArchiveTree {
  final Map<String, ArchiveNode> _nodes;
  final Map<String, List<ArchiveNode>> _children;

  ArchiveTree._(this._nodes, this._children);

  /// Normalise un nom d'entrée (voir la documentation du fichier). Retourne
  /// une chaîne vide pour la racine.
  static String normalize(String name) => name
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .join('/');

  factory ArchiveTree.fromEntries(Iterable<RawArchiveEntry> entries) {
    final nodes = <String, ArchiveNode>{};

    void ensureDirs(String path) {
      var parent = path;
      while (true) {
        final i = parent.lastIndexOf('/');
        if (i < 0) break;
        parent = parent.substring(0, i);
        if (nodes.containsKey(parent)) {
          // Un fichier homonyme d'un dossier : le dossier l'emporte pour que
          // le contenu reste accessible.
          if (nodes[parent]!.isDirectory) break;
        }
        nodes[parent] =
            ArchiveNode(path: parent, isDirectory: true, implicit: true);
      }
    }

    for (final e in entries) {
      final path = normalize(e.name);
      if (path.isEmpty) continue;
      final existing = nodes[path];
      // Un dossier déjà connu (implicite ou explicite) n'est pas écrasé par
      // un doublon ; une entrée explicite remplace un dossier implicite.
      if (existing != null && existing.isDirectory && !existing.implicit) {
        continue;
      }
      if (existing != null && existing.isDirectory && !e.isDirectory) {
        continue; // un fichier ne masque pas un dossier qui a du contenu
      }
      nodes[path] = ArchiveNode(
        path: path,
        isDirectory: e.isDirectory,
        size: e.isDirectory ? 0 : e.size,
        compressedSize: e.compressedSize,
        modified: e.modified,
      );
      ensureDirs(path);
    }

    final children = <String, List<ArchiveNode>>{};
    for (final n in nodes.values) {
      children.putIfAbsent(n.parent, () => []).add(n);
    }
    for (final list in children.values) {
      list.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return ArchiveTree._(nodes, children);
  }

  /// Nœud de [path], ou `null`.
  ArchiveNode? operator [](String path) => _nodes[normalize(path)];

  /// Contenu direct du dossier [dir] (`''` : racine), dossiers d'abord.
  List<ArchiveNode> children(String dir) =>
      List.unmodifiable(_children[normalize(dir)] ?? const []);

  bool isDirectory(String path) {
    final p = normalize(path);
    return p.isEmpty || (_nodes[p]?.isDirectory ?? false);
  }

  /// Tous les nœuds sous [dir] (récursif), [dir] exclu.
  Iterable<ArchiveNode> descendants(String dir) {
    final prefix = normalize(dir);
    return _nodes.values
        .where((n) => prefix.isEmpty ? true : n.path.startsWith('$prefix/'));
  }

  /// Tous les dossiers (pour choisir une destination), racine exclue.
  List<String> get directories =>
      (_nodes.values.where((n) => n.isDirectory).map((n) => n.path).toList()
        ..sort());

  int get fileCount => _nodes.values.where((n) => !n.isDirectory).length;
  int get totalSize => _nodes.values.fold(0, (s, n) => s + n.size);

  /// Recherche (insensible à la casse) dans les noms, sur toute l'archive.
  List<ArchiveNode> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _nodes.values.where((n) => n.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
}
