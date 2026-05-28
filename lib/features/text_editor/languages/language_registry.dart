
/// @file language_registry.dart
/// @brief Registre modulaire des langages de programmation.
///
/// Chaque langage est une [LanguageDefinition] contenant le mode highlight,
/// la commande d'execution et les infos d'affichage.
/// Pour ajouter un langage : LanguageRegistry.instance.register(...)

import 'package:flutter/material.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart';

/// @class LanguageDefinition
/// @brief Decrit un langage supporte par l'editeur de code.
class LanguageDefinition {
  final String id;
  final String label;
  final List<String> extensions;

  /// Mode de coloration syntaxique (objet Mode de re_highlight).
  final Mode highlightMode;

  final IconData icon;
  final Color    color;

  /// Commande d'execution (null = pas d'execution directe).
  final String?       runCommand;
  final List<String>  runArgs;

  const LanguageDefinition({
    required this.id,
    required this.label,
    required this.extensions,
    required this.highlightMode,
    required this.icon,
    required this.color,
    this.runCommand,
    this.runArgs = const [],
  });

  bool get isRunnable => runCommand != null;
}

/// @class LanguageRegistry
/// @brief Registre central des langages de programmation (Singleton).
class LanguageRegistry {
  LanguageRegistry._();
  static final LanguageRegistry instance = LanguageRegistry._();

  final Map<String, LanguageDefinition> _byId        = {};
  final Map<String, LanguageDefinition> _byExtension = {};
  bool _initialized = false;

  /// @brief Enregistre un langage.
  void register(LanguageDefinition def) {
    _byId[def.id] = def;
    for (final ext in def.extensions) {
      _byExtension[ext.toLowerCase()] = def;
    }
  }

  LanguageDefinition? forExtension(String ext) => _byExtension[ext.toLowerCase()];
  LanguageDefinition? byId(String id)          => _byId[id];
  List<LanguageDefinition> get all             => _byId.values.toList();

  /// @brief Initialise avec les langages par defaut (appele une seule fois).
  void initDefaults() {
    if (_initialized) return;
    _initialized = true;

    // Helper pour recuperer un mode en toute securite
    Mode resumeMode(String key) =>
        builtinLanguages[key] ?? builtinLanguages['plaintext'] ?? Mode();

    register(LanguageDefinition(
      id: 'python', label: 'Python', extensions: ['py'],
      highlightMode: resumeMode('python'),
      icon: Icons.code_rounded, color: const Color(0xFF3776AB),
      runCommand: 'python3',
    ));
    register(LanguageDefinition(
      id: 'dart', label: 'Dart', extensions: ['dart'],
      highlightMode: resumeMode('dart'),
      icon: Icons.code_rounded, color: const Color(0xFF00B4AB),
    ));
    register(LanguageDefinition(
      id: 'javascript', label: 'JavaScript', extensions: ['js', 'jsx'],
      highlightMode: resumeMode('javascript'),
      icon: Icons.code_rounded, color: const Color(0xFFF7DF1E),
      runCommand: 'node',
    ));
    register(LanguageDefinition(
      id: 'typescript', label: 'TypeScript', extensions: ['ts', 'tsx'],
      highlightMode: resumeMode('typescript'),
      icon: Icons.code_rounded, color: const Color(0xFF3178C6),
    ));
    register(LanguageDefinition(
      id: 'html', label: 'HTML', extensions: ['html', 'htm'],
      highlightMode: resumeMode('html'),
      icon: Icons.language_rounded, color: const Color(0xFFE34F26),
    ));
    register(LanguageDefinition(
      id: 'css', label: 'CSS', extensions: ['css', 'scss', 'sass'],
      highlightMode: resumeMode('css'),
      icon: Icons.style_rounded, color: const Color(0xFF1572B6),
    ));
    register(LanguageDefinition(
      id: 'json', label: 'JSON', extensions: ['json'],
      highlightMode: resumeMode('json'),
      icon: Icons.data_object_rounded, color: const Color(0xFF929292),
    ));
    register(LanguageDefinition(
      id: 'yaml', label: 'YAML', extensions: ['yaml', 'yml'],
      highlightMode: resumeMode('yaml'),
      icon: Icons.data_object_rounded, color: const Color(0xFFCB171E),
    ));
    register(LanguageDefinition(
      id: 'xml', label: 'XML', extensions: ['xml'],
      highlightMode: resumeMode('xml'),
      icon: Icons.code_rounded, color: const Color(0xFFFF6600),
    ));
    register(LanguageDefinition(
      id: 'java', label: 'Java', extensions: ['java'],
      highlightMode: resumeMode('java'),
      icon: Icons.code_rounded, color: const Color(0xFFED8B00),
    ));
    register(LanguageDefinition(
      id: 'kotlin', label: 'Kotlin', extensions: ['kt'],
      highlightMode: resumeMode('kotlin'),
      icon: Icons.code_rounded, color: const Color(0xFF7F52FF),
    ));
    register(LanguageDefinition(
      id: 'cpp', label: 'C/C++', extensions: ['c', 'cpp', 'h', 'hpp', 'inl'],
      highlightMode: resumeMode('cpp'),
      icon: Icons.code_rounded, color: const Color(0xFF00599C),
    ));
    register(LanguageDefinition(
      id: 'csharp', label: 'C#', extensions: ['cs'],
      highlightMode: resumeMode('csharp'),
      icon: Icons.code_rounded, color: const Color(0xFF68217A),
    ));
    register(LanguageDefinition(
      id: 'go', label: 'Go', extensions: ['go'],
      highlightMode: resumeMode('go'),
      icon: Icons.code_rounded, color: const Color(0xFF00ADD8),
    ));
    register(LanguageDefinition(
      id: 'rust', label: 'Rust', extensions: ['rs'],
      highlightMode: resumeMode('rust'),
      icon: Icons.code_rounded, color: const Color(0xFFDEA584),
    ));
    register(LanguageDefinition(
      id: 'shell', label: 'Shell', extensions: ['sh', 'bash', 'zsh'],
      highlightMode: resumeMode('bash'),
      icon: Icons.terminal_rounded, color: const Color(0xFF4EAA25),
      runCommand: 'bash',
    ));
    register(LanguageDefinition(
      id: 'sql', label: 'SQL', extensions: ['sql'],
      highlightMode: resumeMode('sql'),
      icon: Icons.storage_rounded, color: const Color(0xFF336791),
    ));
    register(LanguageDefinition(
      id: 'markdown', label: 'Markdown', extensions: ['md', 'markdown'],
      highlightMode: resumeMode('markdown'),
      icon: Icons.article_rounded, color: const Color(0xFF519ABA),
    ));
    register(LanguageDefinition(
      id: 'text', label: 'Texte brut', extensions: ['txt', 'log'],
      highlightMode: resumeMode('plaintext'),
      icon: Icons.text_snippet_rounded, color: const Color(0xFF78909C),
    ));
  }
}
