/// @file subtitle_parser.dart
/// @brief Parseur SRT / WebVTT minimal pour la recherche dans les sous-titres.

import 'dart:io';
import 'package:path/path.dart' as p;
import '../widgets/subtitle_search_dialog.dart' show SubtitleEntry;

class SubtitleParser {
  /// Cherche un fichier .srt / .vtt à côté de [videoPath] (même basename).
  static String? findExternalSubtitleFor(String videoPath) {
    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    for (final ext in const ['.srt', '.vtt']) {
      final candidate = p.join(dir, '$base$ext');
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Parse un fichier SRT ou VTT en lignes [SubtitleEntry].
  static Future<List<SubtitleEntry>> parseFile(String path) async {
    final content = await File(path).readAsString();
    final ext = p.extension(path).toLowerCase();
    if (ext == '.vtt') return _parseVtt(content);
    return _parseSrt(content);
  }

  static final _timeRe = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})');

  static List<SubtitleEntry> _parseSrt(String content) {
    final entries = <SubtitleEntry>[];
    final blocks = content.split(RegExp(r'\r?\n\r?\n'));
    for (final block in blocks) {
      final lines = block.split(RegExp(r'\r?\n'));
      Duration? start, end;
      final textLines = <String>[];
      for (final line in lines) {
        final m = _timeRe.firstMatch(line);
        if (m != null) {
          start = _parseTime(m, 1);
          end = _parseTime(m, 5);
        } else if (start != null && line.trim().isNotEmpty &&
            int.tryParse(line.trim()) == null) {
          textLines.add(line.trim());
        }
      }
      if (start != null && end != null && textLines.isNotEmpty) {
        entries.add(SubtitleEntry(
          start: start,
          end: end,
          text: textLines.join(' '),
        ));
      }
    }
    return entries;
  }

  static List<SubtitleEntry> _parseVtt(String content) {
    // WebVTT utilise le même format de chronologie que SRT, à virgule ou
    // point près ; le _parseSrt ci-dessus l'accepte déjà.
    return _parseSrt(content);
  }

  static Duration _parseTime(RegExpMatch m, int base) => Duration(
        hours: int.parse(m.group(base)!),
        minutes: int.parse(m.group(base + 1)!),
        seconds: int.parse(m.group(base + 2)!),
        milliseconds: int.parse(m.group(base + 3)!),
      );
}
