import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/workspace_settings.dart';

/// Gère le fichier .workspace.json d'un projet.
class WorkspaceService {
  static const _filename = '.workspace.json';

  WorkspaceService._();

  static File _file(String projectPath) =>
      File(p.join(projectPath, _filename));

  /// Charge les paramètres du workspace. Retourne les defaults si le fichier
  /// n'existe pas.
  static Future<WorkspaceSettings> load(String projectPath) async {
    final file = _file(projectPath);
    if (!file.existsSync()) return const WorkspaceSettings();
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return WorkspaceSettings.fromJson(json);
    } catch (_) {
      return const WorkspaceSettings();
    }
  }

  /// Sauvegarde les paramètres dans .workspace.json.
  static Future<void> save(
      String projectPath, WorkspaceSettings settings) async {
    await _file(projectPath).writeAsString(settings.toJsonString());
  }

  /// Vérifie si un fichier .workspace.json existe.
  static bool exists(String projectPath) =>
      _file(projectPath).existsSync();
}
