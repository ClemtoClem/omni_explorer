/// @file project_search.dart
/// @brief Recherche dans les fichiers d'un projet : liste des fichiers
/// (ouverture rapide) et occurrences ligne par ligne.
///
/// Bornée pour rester utilisable sur téléphone : dossiers exclus du projet
/// et dossiers cachés ignorés, fichiers binaires ou trop gros sautés,
/// nombre de fichiers et de résultats plafonné. Les fichiers sont lus dans
/// leur encodage détecté (UTF-8, UTF-16, Windows-1252).

import 'dart:io';

import 'package:path/path.dart' as p;

import 'editor_encoding.dart';
import 'editor_open_policy.dart';
import 'text_search.dart';

/// Occurrence dans un fichier du projet.
class ProjectSearchHit {
  final String path;

  /// Ligne et colonne, à partir de 1.
  final int line;
  final int column;

  /// Ligne entière (tronquée si très longue) et position de l'occurrence
  /// dans [preview].
  final String preview;
  final int previewStart;
  final int previewEnd;

  const ProjectSearchHit({
    required this.path,
    required this.line,
    required this.column,
    required this.preview,
    required this.previewStart,
    required this.previewEnd,
  });
}

/// Fin de recherche : pourquoi elle s'est arrêtée.
class ProjectSearchSummary {
  final int filesScanned;
  final int hits;

  /// Vrai si un plafond (fichiers ou résultats) a interrompu la recherche.
  final bool truncated;

  const ProjectSearchSummary(this.filesScanned, this.hits, this.truncated);
}

abstract final class ProjectSearch {
  static const int maxFiles = 5000;
  static const int maxHits = 2000;
  static const int maxFileBytes = 2 * 1024 * 1024;
  static const int _previewMax = 160;

  /// Fichiers du projet [root], chemins triés, hors [exclude] (noms de
  /// dossiers ou de fichiers) et éléments cachés. Au plus [maxFiles].
  static Future<List<String>> listFiles(String root,
      {List<String> exclude = const []}) async {
    final out = <String>[];
    await for (final f in _walk(root, exclude)) {
      out.add(f.path);
      if (out.length >= maxFiles) break;
    }
    out.sort();
    return out;
  }

  static Stream<File> _walk(String root, List<String> exclude) async* {
    final pending = <Directory>[Directory(root)];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      final List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        continue; // dossier illisible
      }
      entries.sort((a, b) => b.path.compareTo(a.path));
      for (final e in entries) {
        final name = p.basename(e.path);
        if (name.startsWith('.') || exclude.contains(name)) continue;
        if (e is Directory) {
          pending.add(e);
        } else if (e is File) {
          yield e;
        }
      }
    }
  }

  /// Occurrences de [query] dans les fichiers de [root]. Le flux se termine
  /// par un [ProjectSearchSummary] passé à [onDone].
  static Stream<ProjectSearchHit> search(
    String root,
    TextSearchQuery query, {
    List<String> exclude = const [],
    void Function(ProjectSearchSummary)? onDone,
  }) async* {
    if (query.isEmpty || query.error != null) {
      onDone?.call(const ProjectSearchSummary(0, 0, false));
      return;
    }
    var files = 0, hits = 0;
    var truncated = false;
    await for (final file in _walk(root, exclude)) {
      if (files >= maxFiles) {
        truncated = true;
        break;
      }
      files++;
      final text = await _readText(file);
      if (text == null) continue;
      for (final hit in _hitsIn(file.path, text, query)) {
        yield hit;
        if (++hits >= maxHits) {
          truncated = true;
          break;
        }
      }
      if (truncated) break;
    }
    onDone?.call(ProjectSearchSummary(files, hits, truncated));
  }

  /// Texte du fichier, ou `null` s'il est trop gros, binaire ou illisible.
  static Future<String?> _readText(File file) async {
    try {
      if (await file.length() > maxFileBytes) return null;
      final bytes = await file.readAsBytes();
      final head = bytes.length > EditorLimits.sniffBytes
          ? bytes.sublist(0, EditorLimits.sniffBytes)
          : bytes;
      final truncated = bytes.length > head.length;
      final enc = EditorEncodingDetector.detect(head, truncated: truncated);
      if (FileProbe.isBinary(head, enc, truncated: truncated)) return null;
      try {
        return EditorEncodingCodec.decode(bytes, enc);
      } on EditorEncodingException {
        return EditorEncodingCodec.decode(bytes, EditorEncoding.windows1252);
      }
    } on FileSystemException {
      return null;
    }
  }

  static Iterable<ProjectSearchHit> _hitsIn(
      String path, String text, TextSearchQuery query) sync* {
    final matches = TextSearch.findAll(text, query, limit: maxHits);
    if (matches.isEmpty) return;
    var line = 1, lineStart = 0, scanned = 0;
    for (final m in matches) {
      // Avance le compteur de lignes jusqu'à l'occurrence.
      for (; scanned < m.start; scanned++) {
        if (text.codeUnitAt(scanned) == 0x0A) {
          line++;
          lineStart = scanned + 1;
        }
      }
      var lineEnd = text.indexOf('\n', m.start);
      if (lineEnd < 0) lineEnd = text.length;
      final col = m.start - lineStart;
      // Extrait centré sur l'occurrence pour les lignes très longues.
      var from = lineStart, to = lineEnd;
      if (to - from > _previewMax) {
        from = (m.start - 40).clamp(lineStart, lineEnd);
        to = (from + _previewMax).clamp(from, lineEnd);
      }
      final raw = text.substring(from, to);
      final preview = raw.trimRight().replaceAll('\r', '');
      final start = (m.start - from).clamp(0, preview.length);
      final end = (m.end - from).clamp(start, preview.length);
      yield ProjectSearchHit(
        path: path,
        line: line,
        column: col + 1,
        preview: preview,
        previewStart: start,
        previewEnd: end,
      );
    }
  }
}
