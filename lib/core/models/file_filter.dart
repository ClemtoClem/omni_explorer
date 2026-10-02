/// @file file_filter.dart
/// @brief Filtre de recherche de l'explorateur, enregistrable dans un
/// raccourci : nom, catégories, extensions, sous-dossiers et tri.

import 'package:path/path.dart' as p;

import '../../app/constants/app_constants.dart';
import 'file_item.dart';

class FileFilter {
  /// Texte cherché dans le nom (sans tenir compte de la casse).
  final String query;

  /// Catégories acceptées (vide : toutes).
  final Set<FileCategory> categories;

  /// Extensions acceptées, en minuscules et sans point (vide : toutes).
  final Set<String> extensions;

  /// Chercher aussi dans les sous-dossiers.
  final bool recursive;

  /// Tri imposé (`null` : tri des préférences de l'explorateur).
  final SortMode? sortMode;
  final bool sortAscending;

  const FileFilter({
    this.query = '',
    this.categories = const {},
    this.extensions = const {},
    this.recursive = false,
    this.sortMode,
    this.sortAscending = true,
  });

  static const none = FileFilter();

  /// Aucun critère de sélection (le tri seul ne filtre rien).
  bool get selectsNothing =>
      query.trim().isEmpty && categories.isEmpty && extensions.isEmpty;

  /// Rien de configuré du tout.
  bool get isEmpty => selectsNothing && !recursive && sortMode == null;

  /// Vrai si [item] correspond aux critères. Un dossier n'est retenu par
  /// des catégories ou des extensions que si la catégorie « Dossiers » est
  /// demandée.
  bool accepts(FileItem item) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty && !item.name.toLowerCase().contains(q)) return false;
    if (categories.isNotEmpty && !categories.contains(item.category)) {
      return false;
    }
    if (extensions.isNotEmpty) {
      if (item.isDirectory) return false;
      if (!extensions.contains(extensionOf(item.path))) return false;
    }
    return true;
  }

  static String extensionOf(String path) =>
      p.extension(path).toLowerCase().replaceFirst('.', '');

  /// « pdf, .DOCX  odt » → {pdf, docx, odt}.
  static Set<String> parseExtensions(String text) => {
        for (final part in text.split(RegExp(r'[\s,;]+')))
          if (part.replaceFirst('.', '').trim().isNotEmpty)
            part.replaceFirst('.', '').trim().toLowerCase(),
      };

  FileFilter copyWith({
    String? query,
    Set<FileCategory>? categories,
    Set<String>? extensions,
    bool? recursive,
    SortMode? sortMode,
    bool clearSort = false,
    bool? sortAscending,
  }) =>
      FileFilter(
        query: query ?? this.query,
        categories: categories ?? this.categories,
        extensions: extensions ?? this.extensions,
        recursive: recursive ?? this.recursive,
        sortMode: clearSort ? null : sortMode ?? this.sortMode,
        sortAscending: sortAscending ?? this.sortAscending,
      );

  /// Résumé court pour l'interface (« Images, PDF · .pdf · sous-dossiers »).
  String describe() => [
        if (query.trim().isNotEmpty) '« ${query.trim()} »',
        if (categories.isNotEmpty)
          categories.map((c) => categoryLabels[c] ?? c.name).join(', '),
        if (extensions.isNotEmpty) extensions.map((e) => '.$e').join(' '),
        if (recursive) 'sous-dossiers',
        if (sortMode != null)
          'tri ${sortLabels[sortMode]!.toLowerCase()} '
              '${sortAscending ? '↑' : '↓'}',
      ].join(' · ');

  /// Libellés des catégories proposées dans les filtres.
  static const categoryLabels = <FileCategory, String>{
    FileCategory.folder: 'Dossiers',
    FileCategory.audio: 'Audio',
    FileCategory.video: 'Vidéo',
    FileCategory.image: 'Images',
    FileCategory.pdf: 'PDF',
    FileCategory.markdown: 'Markdown',
    FileCategory.code: 'Code',
    FileCategory.text: 'Texte',
    FileCategory.archive: 'Archives',
  };

  static const sortLabels = <SortMode, String>{
    SortMode.name: 'Nom',
    SortMode.date: 'Date',
    SortMode.size: 'Taille',
    SortMode.type: 'Type',
  };

  Map<String, dynamic> toMap() => {
        if (query.isNotEmpty) 'query': query,
        if (categories.isNotEmpty)
          'categories': [for (final c in categories) c.name],
        if (extensions.isNotEmpty) 'extensions': extensions.toList(),
        if (recursive) 'recursive': true,
        if (sortMode != null) 'sort': sortMode!.name,
        if (sortMode != null) 'asc': sortAscending,
      };

  /// Lecture tolérante : une valeur inconnue (catégorie, tri) est ignorée.
  factory FileFilter.fromMap(Map<String, dynamic>? map) {
    if (map == null) return none;
    T? byName<T extends Enum>(List<T> values, Object? name) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    return FileFilter(
      query: map['query'] as String? ?? '',
      categories: {
        for (final c in (map['categories'] as List?) ?? const [])
          if (byName(FileCategory.values, c) case final cat?) cat,
      },
      extensions: {
        for (final e in (map['extensions'] as List?) ?? const [])
          if (e is String && e.isNotEmpty) e.toLowerCase(),
      },
      recursive: map['recursive'] == true,
      sortMode: byName(SortMode.values, map['sort']),
      sortAscending: map['asc'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FileFilter &&
      other.query == query &&
      other.recursive == recursive &&
      other.sortMode == sortMode &&
      other.sortAscending == sortAscending &&
      other.categories.length == categories.length &&
      other.categories.containsAll(categories) &&
      other.extensions.length == extensions.length &&
      other.extensions.containsAll(extensions);

  @override
  int get hashCode => Object.hash(query, recursive, sortMode, sortAscending,
      Object.hashAllUnordered(categories), Object.hashAllUnordered(extensions));
}
