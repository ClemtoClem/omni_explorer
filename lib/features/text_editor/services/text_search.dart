/// @file text_search.dart
/// @brief Recherche et remplacement dans un texte : respect de la casse, mot
/// entier, expression régulière. Commun à la barre de recherche de l'éditeur
/// et à la recherche dans le projet.

/// Options d'une recherche.
class TextSearchQuery {
  final String pattern;
  final bool caseSensitive;
  final bool wholeWord;
  final bool regex;

  const TextSearchQuery(
    this.pattern, {
    this.caseSensitive = false,
    this.wholeWord = false,
    this.regex = false,
  });

  TextSearchQuery copyWith({
    String? pattern,
    bool? caseSensitive,
    bool? wholeWord,
    bool? regex,
  }) =>
      TextSearchQuery(
        pattern ?? this.pattern,
        caseSensitive: caseSensitive ?? this.caseSensitive,
        wholeWord: wholeWord ?? this.wholeWord,
        regex: regex ?? this.regex,
      );

  bool get isEmpty => pattern.isEmpty;

  /// Expression compilée. Lève [FormatException] si [regex] est vrai et que
  /// le motif est invalide.
  RegExp toRegExp() {
    var source = regex ? pattern : RegExp.escape(pattern);
    // Mot entier : bornes « non-mot » plutôt que \b, qui ne connaît que
    // l'ASCII (« é » n'y est pas une lettre).
    if (wholeWord) {
      source = r'(?<![\p{L}\p{N}_])(?:' + source + r')(?![\p{L}\p{N}_])';
    }
    return RegExp(source,
        caseSensitive: caseSensitive, multiLine: true, unicode: true);
  }

  /// Message d'erreur si le motif est une expression invalide, sinon `null`.
  String? get error {
    if (isEmpty) return null;
    try {
      toRegExp();
      return null;
    } on FormatException catch (e) {
      return 'Expression invalide : ${e.message}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TextSearchQuery &&
      other.pattern == pattern &&
      other.caseSensitive == caseSensitive &&
      other.wholeWord == wholeWord &&
      other.regex == regex;

  @override
  int get hashCode => Object.hash(pattern, caseSensitive, wholeWord, regex);
}

/// Occurrence : décalages [start, end[ dans le texte.
class TextMatch {
  final int start;
  final int end;
  const TextMatch(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is TextMatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextMatch($start, $end)';
}

abstract final class TextSearch {
  /// Au-delà, la recherche s'arrête : le compteur affiche « 10000+ ».
  static const int maxMatches = 10000;

  /// Occurrences de [query] dans [text], dans l'ordre. Les correspondances
  /// vides (ex. `^` en expression) sont ignorées. Liste vide pour un motif
  /// vide ou invalide.
  static List<TextMatch> findAll(String text, TextSearchQuery query,
      {int limit = maxMatches}) {
    if (query.isEmpty) return const [];
    final RegExp re;
    try {
      re = query.toRegExp();
    } on FormatException {
      return const [];
    }
    final out = <TextMatch>[];
    for (final m in re.allMatches(text)) {
      if (m.end == m.start) continue;
      out.add(TextMatch(m.start, m.end));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Indice de la première occurrence qui commence à [offset] ou après (en
  /// revenant au début), ou -1 s'il n'y en a pas.
  static int indexAtOrAfter(List<TextMatch> matches, int offset) {
    if (matches.isEmpty) return -1;
    for (var i = 0; i < matches.length; i++) {
      if (matches[i].start >= offset) return i;
    }
    return 0;
  }

  /// Texte de remplacement de [match]. En mode expression, `$1`, `${nom}` et
  /// `$0` reprennent les groupes ; `$$` donne un « $ ».
  static String replacementFor(
      String text, TextMatch match, TextSearchQuery query, String replace) {
    if (!query.regex) return replace;
    final m = query.toRegExp().matchAsPrefix(text, match.start);
    if (m == null) return replace;
    return replace.replaceAllMapped(RegExp(r'\$(\$|\d+|\{(\w+)\})'), (g) {
      if (g[1] == r'$') return r'$';
      final named = g[2];
      if (named != null) {
        try {
          return (m as RegExpMatch).namedGroup(named) ?? '';
        } on ArgumentError {
          return g[0]!;
        }
      }
      final index = int.parse(g[1]!);
      return index <= m.groupCount ? (m.group(index) ?? '') : g[0]!;
    });
  }

  /// Remplace toutes les occurrences. Retourne le nouveau texte et le
  /// nombre de remplacements.
  static (String, int) replaceAll(
      String text, TextSearchQuery query, String replace) {
    final matches = findAll(text, query, limit: 1 << 30);
    if (matches.isEmpty) return (text, 0);
    final out = StringBuffer();
    var last = 0;
    for (final m in matches) {
      out
        ..write(text.substring(last, m.start))
        ..write(replacementFor(text, m, query, replace));
      last = m.end;
    }
    out.write(text.substring(last));
    return (out.toString(), matches.length);
  }
}
