/// @file line_operations.dart
/// @brief Opérations sur les lignes de la sélection : dupliquer, déplacer,
/// supprimer, commenter. Fonctions pures sur (texte, sélection), communes aux
/// modes code, texte et texte enrichi.
///
/// Les lignes concernées sont celles que touche la sélection ; une sélection
/// qui finit au tout début d'une ligne n'inclut pas cette ligne (comme dans
/// VS Code après une sélection de lignes entières).

/// Résultat d'une opération : nouveau texte et nouvelle sélection.
class LineEdit {
  final String text;
  final int selectionStart;
  final int selectionEnd;

  const LineEdit(this.text, this.selectionStart, this.selectionEnd);

  @override
  bool operator ==(Object other) =>
      other is LineEdit &&
      other.text == text &&
      other.selectionStart == selectionStart &&
      other.selectionEnd == selectionEnd;

  @override
  int get hashCode => Object.hash(text, selectionStart, selectionEnd);

  @override
  String toString() => 'LineEdit(${text.replaceAll('\n', r'\n')}, '
      '$selectionStart, $selectionEnd)';
}

/// Syntaxe de commentaire de ligne d'un langage.
class LineComment {
  final String prefix;

  /// Fin de commentaire pour les langages sans commentaire de ligne
  /// (HTML : `<!-- … -->`, CSS : `/* … */`).
  final String suffix;

  const LineComment(this.prefix, [this.suffix = '']);

  /// Syntaxe pour un identifiant de [LanguageRegistry], ou `null` (texte
  /// brut : rien à commenter).
  static LineComment? forLanguage(String? id) => switch (id) {
        'python' || 'yaml' || 'shell' => const LineComment('#'),
        'sql' => const LineComment('--'),
        'html' || 'xml' || 'markdown' => const LineComment('<!--', '-->'),
        'css' => const LineComment('/*', '*/'),
        'dart' ||
        'javascript' ||
        'typescript' ||
        'java' ||
        'kotlin' ||
        'cpp' ||
        'csharp' ||
        'go' ||
        'rust' ||
        'json' =>
          const LineComment('//'),
        _ => null,
      };
}

abstract final class LineOperations {
  /// Bloc de lignes [start, end[ (fin de ligne finale exclue) touché par la
  /// sélection.
  static (int, int) _block(String text, int selStart, int selEnd) {
    var a = selStart.clamp(0, text.length), b = selEnd.clamp(0, text.length);
    if (a > b) (a, b) = (b, a);
    // Sélection non vide finissant en début de ligne : ligne exclue.
    if (b > a && b > 0 && text.codeUnitAt(b - 1) == 0x0A) b--;
    final start = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
    var end = text.indexOf('\n', b);
    if (end < 0) end = text.length;
    return (start, end);
  }

  static (int, int) _ordered(int a, int b) => a <= b ? (a, b) : (b, a);

  /// Duplique les lignes de la sélection en dessous ; la sélection passe sur
  /// la copie.
  static LineEdit duplicate(String text, int selStart, int selEnd) {
    final (start, end) = _block(text, selStart, selEnd);
    final block = text.substring(start, end);
    final shift = block.length + 1;
    final (a, b) = _ordered(selStart, selEnd);
    return LineEdit(
      '${text.substring(0, end)}\n$block${text.substring(end)}',
      a + shift,
      b + shift,
    );
  }

  /// Échange les lignes de la sélection avec la ligne au-dessus ([up]) ou
  /// en dessous. Sans voisine, le texte est inchangé.
  static LineEdit move(String text, int selStart, int selEnd,
      {required bool up}) {
    final (start, end) = _block(text, selStart, selEnd);
    final (a, b) = _ordered(selStart, selEnd);
    final block = text.substring(start, end);
    if (up) {
      if (start == 0) return LineEdit(text, a, b);
      final prevStart = start == 1 ? 0 : text.lastIndexOf('\n', start - 2) + 1;
      final prev = text.substring(prevStart, start - 1);
      final shift = prev.length + 1;
      return LineEdit(
        '${text.substring(0, prevStart)}$block\n$prev${text.substring(end)}',
        a - shift,
        b - shift,
      );
    }
    if (end >= text.length) return LineEdit(text, a, b);
    var nextEnd = text.indexOf('\n', end + 1);
    if (nextEnd < 0) nextEnd = text.length;
    final next = text.substring(end + 1, nextEnd);
    final shift = next.length + 1;
    return LineEdit(
      '${text.substring(0, start)}$next\n$block${text.substring(nextEnd)}',
      a + shift,
      b + shift,
    );
  }

  /// Supprime les lignes de la sélection ; le curseur se place au début de
  /// la ligne qui les suit (ou de la dernière ligne).
  static LineEdit delete(String text, int selStart, int selEnd) {
    final (start, end) = _block(text, selStart, selEnd);
    if (end < text.length) {
      final out = text.substring(0, start) + text.substring(end + 1);
      return LineEdit(out, start, start);
    }
    // Dernier bloc du texte : retirer aussi la fin de ligne qui le précède.
    final from = start == 0 ? 0 : start - 1;
    final out = text.substring(0, from);
    final caret = from == 0 ? 0 : out.lastIndexOf('\n') + 1;
    return LineEdit(out, caret, caret);
  }

  /// Commente les lignes de la sélection, ou les décommente si toutes les
  /// lignes non vides le sont déjà. Le préfixe s'aligne sur l'indentation la
  /// plus faible du bloc, suivi d'une espace.
  static LineEdit toggleComment(
      String text, int selStart, int selEnd, LineComment syntax) {
    final (start, end) = _block(text, selStart, selEnd);
    final lines = text.substring(start, end).split('\n');
    final prefix = syntax.prefix, suffix = syntax.suffix;

    bool isBlank(String l) => l.trim().isEmpty;
    int indentOf(String l) => l.length - l.trimLeft().length;
    bool commented(String l) {
      final t = l.trim();
      return t.startsWith(prefix) && (suffix.isEmpty || t.endsWith(suffix));
    }

    final content = lines.where((l) => !isBlank(l)).toList();
    if (content.isEmpty) {
      final (a, b) = _ordered(selStart, selEnd);
      return LineEdit(text, a, b);
    }
    final uncomment = content.every(commented);

    // Modifications (position dans le texte, longueur retirée, texte ajouté)
    // pour recalculer la sélection.
    final edits = <(int, int, String)>[];
    final out = <String>[];
    var lineStart = start;
    final minIndent = content.map(indentOf).reduce((x, y) => x < y ? x : y);
    for (final line in lines) {
      var result = line;
      if (!isBlank(line)) {
        if (uncomment) {
          final i = indentOf(line);
          var cut = prefix.length;
          if (line.length > i + cut && line[i + cut] == ' ') cut++;
          edits.add((lineStart + i, cut, ''));
          result = line.substring(0, i) + line.substring(i + cut);
          if (suffix.isNotEmpty) {
            final trimmedEnd = result.trimRight();
            var s = trimmedEnd.length - suffix.length;
            var len = suffix.length;
            if (s > 0 && trimmedEnd[s - 1] == ' ') {
              s--;
              len++;
            }
            // Position dans la ligne d'origine : décalée de ce qui a été
            // retiré au début.
            edits.add((lineStart + s + cut, len, ''));
            result = result.substring(0, s) + result.substring(s + len);
          }
        } else {
          edits.add((lineStart + minIndent, 0, '$prefix '));
          result =
              '${line.substring(0, minIndent)}$prefix ${line.substring(minIndent)}';
          if (suffix.isNotEmpty) {
            edits.add((lineStart + line.length, 0, ' $suffix'));
            result = '$result $suffix';
          }
        }
      }
      out.add(result);
      lineStart += line.length + 1;
    }

    int map(int offset) {
      var delta = 0;
      for (final (pos, removed, added) in edits) {
        if (offset >= pos + removed) {
          delta += added.length - removed;
        } else if (offset > pos) {
          delta += pos - offset; // dans la partie retirée : ramené à pos
        }
      }
      return offset + delta;
    }

    final (a, b) = _ordered(selStart, selEnd);
    return LineEdit(
      text.substring(0, start) + out.join('\n') + text.substring(end),
      map(a),
      map(b),
    );
  }
}
