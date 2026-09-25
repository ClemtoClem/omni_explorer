/// @file app_constants.dart
/// @brief Constantes globales de l'application OmniExplorer.

/// @class AppConstants
/// @brief Constantes globales de l'application.
class AppConstants {
  AppConstants._();

  static const String appName    = 'OmniExplorer';
  static const String appVersion = '1.0.0';

  // ── Préférences ───────────────────────────────────────────────────────────
  static const String prefThemeMode    = 'theme_mode';
  static const String prefViewMode     = 'view_mode';
  static const String prefSortBy       = 'sort_by';
  static const String prefSortAsc      = 'sort_asc';
  static const String prefShowHidden   = 'show_hidden';
  static const String prefShortcuts    = 'shortcuts';
  static const String prefBookmarks    = 'bookmarks';
  static const String prefRecentFiles  = 'recent_files';
  static const String prefPlaylistsKey = 'playlists';

  // ── Thème ─────────────────────────────────────────────────────────────────
  static const String prefThemePreset  = 'theme_preset';
  static const String prefCustomAccent = 'custom_accent_color';

  // ── Clavier ───────────────────────────────────────────────────────────────
  static const String prefUseCustomKeyboard = 'use_custom_keyboard';

  // ── Polices ───────────────────────────────────────────────────────────────
  static const String prefUiFontFamily       = 'ui_font_family';
  static const String prefUiFontScale        = 'ui_font_scale';
  static const String prefCodeFontFamily     = 'code_font_family';
  static const String prefCodeFontSize       = 'code_font_size';
  static const String prefMarkdownFontFamily = 'md_font_family';
  static const String prefMarkdownFontSize   = 'md_font_size';
  static const String prefTextFontFamily     = 'text_font_family';
  static const String prefTextFontSize       = 'text_font_size';
  static const String prefRichFontFamily     = 'rich_font_family';
  static const String prefRichFontSize       = 'rich_font_size';
  static const String prefHexFontFamily      = 'hex_font_family';
  static const String prefHexFontSize        = 'hex_font_size';

  // ── SSH / Debian VM ──────────────────────────────────────────────────────
  static const String prefSshHost         = 'ssh_host';
  static const String prefSshPort         = 'ssh_port';
  static const String prefSshUsername     = 'ssh_username';
  static const String prefSshPassword     = 'ssh_password';
  static const String prefSshSharedPath   = 'ssh_shared_path';
  /// Empreintes des clés d'hôte SSH acceptées (confiance à la 1re connexion).
  static const String prefSshKnownHosts   = 'ssh_known_hosts';

  // ── Corbeille ─────────────────────────────────────────────────────────────
  static const String trashFolderName  = '.omni_trash';
  static const String trashMetaFile    = '.trash_meta.json';

  // ── Limites ───────────────────────────────────────────────────────────────
  static const int maxRecentFiles      = 20;
  static const int maxUndoHistory      = 50;
  static const int slideshowDefaultMs  = 3000;

  // ── Extensions par catégorie ──────────────────────────────────────────────

  static const Set<String> audioExtensions = {
    'mp3', 'flac', 'wav', 'ogg', 'aac', 'm4a', 'opus', 'wma', 'aiff', 'midi'
  };

  static const Set<String> videoExtensions = {
    'mp4', 'mpeg', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', '3gp', 'ts',
  };

  static const Set<String> imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'ico',
    'tiff', 'tif', 'heic', 'heif', 'avif',
  };

  static const Set<String> pdfExtensions  = {'pdf'};

  static const Set<String> markdownExtensions = {'md', 'markdown'};

  static const Set<String> archiveExtensions = {
    'zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar',
    'tgz', 'tbz2', 'txz', 'tar.gz', 'tar.bz2', 'tar.xz',
    'jar', 'war', 'ear', 'apk', 'ipa',
    'deb', 'rpm', 'cab', 'iso',
  };

  /// Extensions reconnues par l'éditeur de code avec coloration syntaxique.
  static const Set<String> codeExtensions = {
    'dart', 'py', 'js', 'ts', 'jsx', 'tsx', 'html', 'htm', 'css', 'scss',
    'sass', 'json', 'yaml', 'yml', 'xml', 'java', 'kt', 'c', 'cpp', 'h', 'inl',
    'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'swift', 'sh', 'bash', 'zsh',
    'fish', 'sql', 'lua', 'r', 'toml', 'ini', 'cfg', 'conf', 'dockerfile',
    'makefile', 'cmake',
  };

  static const Set<String> textExtensions = {
    'txt', 'log', 'csv', 'tsv', 'nfo', 'srt', 'vtt',
  };

  static const Set<String> binaryExtensions = {
    'bin', 'dat', 'raw', 'exe', 'dll', 'so', 'dylib', 'elf',
    'o', 'obj', 'a', 'lib',
    'db', 'sqlite', 'sqlite3',
    'iso', 'img', 'dex', 'class',
    'pak', 'rom', 'fw', 'hex',
  };
}

/// @enum FileCategory
/// @brief Catégories de fichiers reconnues par l'application.
enum FileCategory {
  folder,
  audio,
  video,
  image,
  pdf,
  markdown,
  code,
  text,
  archive,
  binary,
  unknown,
}

/// @enum SortMode
/// @brief Modes de tri pour l'explorateur de fichiers.
enum SortMode {
  name,
  date,
  size,
  type,
}

/// @enum ViewMode
/// @brief Modes d'affichage pour l'explorateur de fichiers.
enum ViewMode {
  list,
  grid,
}
