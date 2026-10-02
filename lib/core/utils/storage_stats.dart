/// @file storage_stats.dart
/// @brief Récupération de l'espace occupé / libre d'un point de montage.
///
/// Utilise `df -k` (toybox sur Android, coreutils sur Linux) : pas de
/// dépendance native supplémentaire, fonctionne sans root.

import 'dart:io';

class StorageStats {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;

  const StorageStats({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
  });

  static const StorageStats empty =
      StorageStats(totalBytes: 0, usedBytes: 0, freeBytes: 0);

  bool get hasData => totalBytes > 0;

  double get usedRatio =>
      totalBytes == 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);
}

/// Statistiques de stockage de [path] (0 partout si indisponible).
Future<StorageStats> getStorageStats(String path) async {
  try {
    final result = await Process.run('df', ['-k', path]);
    if (result.exitCode != 0) return StorageStats.empty;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return StorageStats.empty;
    // Filesystem  1K-blocks  Used  Available  Use%  Mounted on
    final parts = lines[1].split(RegExp(r'\s+'));
    if (parts.length < 4) return StorageStats.empty;
    final totalKb = int.tryParse(parts[1]) ?? 0;
    final usedKb = int.tryParse(parts[2]) ?? 0;
    final freeKb = int.tryParse(parts[3]) ?? 0;
    return StorageStats(
      totalBytes: totalKb * 1024,
      usedBytes: usedKb * 1024,
      freeBytes: freeKb * 1024,
    );
  } catch (_) {
    return StorageStats.empty;
  }
}