/// @file explorer_picker.dart
/// @brief Sélection de fichiers / dossiers via l'explorateur de l'application.
///
/// Point d'entrée unique des autres fonctionnalités (éditeur multimédia,
/// archives, coffre-fort, éditeur de texte) pour choisir un fichier, un
/// dossier ou un emplacement d'enregistrement : elles ouvrent toutes le même
/// [FileExplorerScreen] (navigation, tri, filtres, fichiers cachés, cartes
/// SD) au lieu d'un sélecteur système ou d'un navigateur fait main.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/constants/app_constants.dart';
import '../../core/models/file_item.dart';
import 'screens/file_explorer_screen.dart';

/// Ce que l'explorateur doit faire choisir.
enum ExplorerPickMode {
  /// Un ou plusieurs fichiers existants.
  files,

  /// Un dossier (les fichiers sont masqués).
  directory,

  /// Un chemin de fichier à écrire : dossier courant + nom saisi.
  save,
}

/// Paramètres d'une sélection dans l'explorateur.
class ExplorerPickRequest {
  final ExplorerPickMode mode;

  /// Titre affiché dans la barre de l'explorateur.
  final String title;

  /// Mode [ExplorerPickMode.files] : plusieurs fichiers à la fois.
  final bool allowMultiple;

  /// Catégories de fichiers proposées (vide : toutes).
  final Set<FileCategory> categories;

  /// Extensions proposées, en minuscules et sans point (vide : toutes).
  final Set<String> extensions;

  /// Mode [ExplorerPickMode.save] : nom de fichier proposé.
  final String? fileName;

  const ExplorerPickRequest({
    required this.mode,
    required this.title,
    this.allowMultiple = false,
    this.categories = const {},
    this.extensions = const {},
    this.fileName,
  });

  /// Vrai si le fichier [item] peut être choisi (les dossiers ne passent
  /// jamais par ce filtre : ils restent visibles pour naviguer).
  bool accepts(FileItem item) {
    if (mode == ExplorerPickMode.directory) return false;
    if (categories.isNotEmpty && !categories.contains(item.category)) {
      return false;
    }
    if (extensions.isNotEmpty) {
      final ext = p.extension(item.path).toLowerCase().replaceFirst('.', '');
      if (!extensions.contains(ext)) return false;
    }
    return true;
  }
}

/// Raccourcis pour ouvrir l'explorateur en mode sélecteur.
abstract final class ExplorerPicker {
  static Future<List<String>> _pick(
    BuildContext context,
    ExplorerPickRequest request, {
    String? initialPath,
  }) async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => FileExplorerScreen(
          pick: request,
          initialPath: initialPath,
        ),
      ),
    );
    return result ?? const [];
  }

  /// Choisit un fichier. `null` : sélection annulée.
  static Future<String?> pickFile(
    BuildContext context, {
    String title = 'Choisir un fichier',
    Set<FileCategory> categories = const {},
    Set<String> extensions = const {},
    String? initialPath,
  }) async {
    final paths = await _pick(
      context,
      ExplorerPickRequest(
        mode: ExplorerPickMode.files,
        title: title,
        categories: categories,
        extensions: extensions,
      ),
      initialPath: initialPath,
    );
    return paths.isEmpty ? null : paths.first;
  }

  /// Choisit plusieurs fichiers. Liste vide : sélection annulée.
  static Future<List<String>> pickFiles(
    BuildContext context, {
    String title = 'Choisir des fichiers',
    Set<FileCategory> categories = const {},
    Set<String> extensions = const {},
    String? initialPath,
  }) =>
      _pick(
        context,
        ExplorerPickRequest(
          mode: ExplorerPickMode.files,
          title: title,
          allowMultiple: true,
          categories: categories,
          extensions: extensions,
        ),
        initialPath: initialPath,
      );

  /// Choisit un dossier. `null` : sélection annulée.
  static Future<String?> pickDirectory(
    BuildContext context, {
    String title = 'Choisir un dossier',
    String? initialPath,
  }) async {
    final paths = await _pick(
      context,
      ExplorerPickRequest(mode: ExplorerPickMode.directory, title: title),
      initialPath: initialPath,
    );
    return paths.isEmpty ? null : paths.first;
  }

  /// Choisit l'emplacement d'un fichier à écrire (le remplacement d'un
  /// fichier existant est confirmé par l'utilisateur). `null` : annulé.
  static Future<String?> saveFile(
    BuildContext context, {
    String title = 'Enregistrer sous',
    String fileName = '',
    Set<String> extensions = const {},
    String? initialPath,
  }) async {
    final paths = await _pick(
      context,
      ExplorerPickRequest(
        mode: ExplorerPickMode.save,
        title: title,
        fileName: fileName,
        extensions: extensions,
      ),
      initialPath: initialPath,
    );
    return paths.isEmpty ? null : paths.first;
  }
}
