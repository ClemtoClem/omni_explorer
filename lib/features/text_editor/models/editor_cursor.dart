/// @file editor_cursor.dart
/// @brief Position du curseur (ligne, colonne) affichée par la barre d'état,
/// et conversions avec un décalage dans le texte.

class EditorCursor {
  /// Ligne, à partir de 1.
  final int line;

  /// Colonne, à partir de 1, en unités UTF-16 (comme les contrôleurs).
  final int column;

  const EditorCursor({
    required this.line,
    required this.column,
  })  : assert(line >= 1, 'line doit être >= 1'),
        assert(column >= 1, 'column doit être >= 1');

  /// Position au tout début du document (première ligne, avant le premier
  /// caractère).
  static const EditorCursor start = EditorCursor(line: 1, column: 1);

  /// Position du décalage [offset] (0-indexé) dans [text]. Un décalage
  /// invalide (-1 : pas de sélection) donne le début du document.
  factory EditorCursor.fromOffset(String text, int offset) {
    if (offset <= 0) return start;
    if (offset > text.length) offset = text.length;
    var line = 1, lineStart = 0;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    return EditorCursor(line: line, column: offset - lineStart + 1);
  }

  /// Décalage du début de la ligne [line] (1-indexée) dans [text], ou -1
  /// si le texte a moins de lignes.
  static int offsetOfLine(String text, int line) {
    if (line < 1) return -1;
    if (line == 1) return 0;
    var current = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A && ++current == line) return i + 1;
    }
    return -1;
  }

  /// Nombre de lignes de [text] (un texte vide en a une).
  static int lineCountOf(String text) {
    var n = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) n++;
    }
    return n;
  }

  @override
  bool operator ==(Object other) =>
      other is EditorCursor && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => 'Ln $line, Col $column';
}
