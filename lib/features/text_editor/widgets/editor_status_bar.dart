/// @file editor_status_bar.dart
/// @brief Barre d'état de l'éditeur : ligne/colonne, encodage, langage,
/// état de modification, longueur du document.

import 'package:flutter/material.dart';

import '../models/editor_cursor.dart';
import '../models/editor_view_mode.dart';
import '../services/editor_encoding.dart';
import '../languages/language_registry.dart';

class EditorStatusBar extends StatelessWidget {
  final EditorCursor cursor;

  /// Nombre total de lignes du document.
  final int lineCount;

  /// Nombre de caractères.
  final int charCount;

  /// Encodage en cours.
  final EditorEncoding encoding;

  /// Langage détecté (peut être null en mode texte).
  final LanguageDefinition? language;

  /// Mode d'affichage en cours (code, markdown, texte, enrichi, hex).
  final EditorViewMode mode;

  /// Vrai si le document a des modifications non sauvegardées.
  final bool dirty;

  /// Actions : changer d'encodage, changer de langage, aller à la ligne.
  final VoidCallback? onEncodingTap;
  final VoidCallback? onLanguageTap;
  final VoidCallback? onGoToLineTap;

  const EditorStatusBar({
    super.key,
    required this.cursor,
    required this.lineCount,
    required this.charCount,
    required this.encoding,
    required this.language,
    required this.mode,
    required this.dirty,
    this.onEncodingTap,
    this.onLanguageTap,
    this.onGoToLineTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surface;
    final fg = theme.textTheme.bodySmall?.color ?? theme.iconTheme.color;
    final accent = theme.colorScheme.primary;

    return Material(
      color: bg,
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            // Ligne / colonne — cliquable (aller à la ligne).
            InkWell(
              onTap: onGoToLineTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(
                    'Ln ${cursor.line}, Col ${cursor.column}',
                    style: _mono(context, fg),
                  ),
                ),
              ),
            ),
            _sep(theme),
            // Langage / mode — cliquable.
            InkWell(
              onTap: onLanguageTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(
                    language?.label ?? _modeLabel(mode),
                    style: _mono(context, fg),
                  ),
                ),
              ),
            ),
            // Statistiques discrètes : cèdent la place sur écran étroit.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '$lineCount lignes · $charCount car.',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(context, fg),
                ),
              ),
            ),
            _sep(theme),
            // Encodage — cliquable.
            InkWell(
              onTap: onEncodingTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(encoding.label, style: _mono(context, fg)),
                ),
              ),
            ),
            // Indicateur « non sauvegardé ».
            if (dirty)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Icon(Icons.circle, size: 8, color: accent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sep(ThemeData theme) => Container(
        width: 1,
        height: 14,
        color: theme.dividerColor,
      );

  TextStyle _mono(BuildContext context, Color? color) => TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: color,
      );

  String _modeLabel(EditorViewMode mode) => switch (mode) {
        EditorViewMode.code => 'Code',
        EditorViewMode.markdown => 'Markdown',
        EditorViewMode.text => 'Texte',
        EditorViewMode.richText => 'Enrichi',
        EditorViewMode.hex => 'Hex',
      };
}
