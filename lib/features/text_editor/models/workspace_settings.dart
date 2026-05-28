import 'dart:convert';

/// Paramètres de configuration d'un workspace (projet ouvert).
/// Stockés dans .workspace.json à la racine du projet.
class WorkspaceSettings {
  /// 'dark' | 'light' | 'system' — 'system' = utilise le thème global de l'app
  final String themeMode;

  /// Remplace le paramètre global useCustomKeyboard si non null
  final bool? useCustomKeyboard;

  final int fontSize;
  final String fontFamily;
  final bool wordWrap;
  final bool showLineNumbers;

  /// Sauvegarde automatique à chaque changement de fichier
  final bool autoSave;

  /// Formater le code à la sauvegarde (placeholder, à implémenter par langage)
  final bool formatOnSave;

  final int tabSize;
  final bool insertSpaces;

  /// Associations extension → id de langage, ex: {'twig': 'html'}
  final Map<String, String> languageAssociations;

  /// Patterns à exclure de l'arborescence projet
  final List<String> excludePatterns;

  /// Paramètres personnalisés libres (extension future)
  final Map<String, dynamic> extra;

  const WorkspaceSettings({
    this.themeMode = 'system',
    this.useCustomKeyboard,
    this.fontSize = 13,
    this.fontFamily = 'JetBrainsMono',
    this.wordWrap = true,
    this.showLineNumbers = true,
    this.autoSave = false,
    this.formatOnSave = false,
    this.tabSize = 2,
    this.insertSpaces = true,
    this.languageAssociations = const {},
    this.excludePatterns = const [
      '.git',
      '.dart_tool',
      'node_modules',
      '__pycache__',
      'build',
      '.gradle',
      '.idea',
    ],
    this.extra = const {},
  });

  factory WorkspaceSettings.fromJson(Map<String, dynamic> json) {
    return WorkspaceSettings(
      themeMode: json['themeMode'] as String? ?? 'system',
      useCustomKeyboard: json['useCustomKeyboard'] as bool?,
      fontSize: json['fontSize'] as int? ?? 13,
      fontFamily: json['fontFamily'] as String? ?? 'JetBrainsMono',
      wordWrap: json['wordWrap'] as bool? ?? true,
      showLineNumbers: json['showLineNumbers'] as bool? ?? true,
      autoSave: json['autoSave'] as bool? ?? false,
      formatOnSave: json['formatOnSave'] as bool? ?? false,
      tabSize: json['tabSize'] as int? ?? 2,
      insertSpaces: json['insertSpaces'] as bool? ?? true,
      languageAssociations:
          Map<String, String>.from(json['languageAssociations'] as Map? ?? {}),
      excludePatterns: (json['excludePatterns'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['.git', '.dart_tool', 'node_modules', '__pycache__', 'build'],
      extra: Map<String, dynamic>.from(json['extra'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'themeMode': themeMode,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'wordWrap': wordWrap,
      'showLineNumbers': showLineNumbers,
      'autoSave': autoSave,
      'formatOnSave': formatOnSave,
      'tabSize': tabSize,
      'insertSpaces': insertSpaces,
      'languageAssociations': languageAssociations,
      'excludePatterns': excludePatterns,
    };
    if (useCustomKeyboard != null) {
      m['useCustomKeyboard'] = useCustomKeyboard;
    }
    if (extra.isNotEmpty) m['extra'] = extra;
    return m;
  }

  WorkspaceSettings copyWith({
    String? themeMode,
    Object? useCustomKeyboard = _absent,
    int? fontSize,
    String? fontFamily,
    bool? wordWrap,
    bool? showLineNumbers,
    bool? autoSave,
    bool? formatOnSave,
    int? tabSize,
    bool? insertSpaces,
    Map<String, String>? languageAssociations,
    List<String>? excludePatterns,
    Map<String, dynamic>? extra,
  }) {
    return WorkspaceSettings(
      themeMode: themeMode ?? this.themeMode,
      useCustomKeyboard: identical(useCustomKeyboard, _absent)
          ? this.useCustomKeyboard
          : useCustomKeyboard as bool?,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      wordWrap: wordWrap ?? this.wordWrap,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      autoSave: autoSave ?? this.autoSave,
      formatOnSave: formatOnSave ?? this.formatOnSave,
      tabSize: tabSize ?? this.tabSize,
      insertSpaces: insertSpaces ?? this.insertSpaces,
      languageAssociations:
          languageAssociations ?? this.languageAssociations,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      extra: extra ?? this.extra,
    );
  }

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  static const _absent = Object();
}
