/// @file storage_detector.dart
/// @brief Détection des supports de stockage internes et externes.
///
/// - **Android** : volumes montés d'après `StorageManager` (canal natif de
///   `MainActivity`) : stockage interne, cartes SD, clés et disques USB,
///   avec le nom donné par le système. Repli (Android < 7 ou canal absent) :
///   `path_provider` et parcours de `/storage`.
/// - **Linux** : dossier personnel, système de fichiers racine, puis chaque
///   système de fichiers réel de `/proc/mounts` (partitions, disques, cartes
///   SD, clés USB, disques optiques, partages réseau). Les montages
///   techniques (snaps, /boot, pseudo-systèmes) sont écartés.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_service.dart';

abstract final class StorageDetector {
  static const _channel = MethodChannel('com.example.omni_explorer/storage');

  /// Espaces de stockage de l'appareil, le principal en premier.
  static Future<List<StorageInfo>> detect() async {
    try {
      if (Platform.isAndroid) return await _android();
      if (Platform.isLinux) return _linux();
    } catch (e) {
      debugPrint('[Storage] détection impossible : $e');
    }
    return const [];
  }

  // ── Android ──────────────────────────────────────────────────────────────

  static Future<List<StorageInfo>> _android() async {
    final result = <StorageInfo>[];
    try {
      final volumes = await _channel.invokeListMethod<Map>('getVolumes');
      if (volumes != null) result.addAll(parseAndroidVolumes(volumes));
    } on MissingPluginException {
      // Canal absent (tests) : repli ci-dessous.
    } on PlatformException catch (e) {
      debugPrint('[Storage] volumes Android : $e');
    }

    if (result.isEmpty) {
      // Repli : un dossier d'application par volume (…/Android/data/…).
      try {
        final dirs = await getExternalStorageDirectories() ?? const [];
        for (final (i, d) in dirs.indexed) {
          final root = androidVolumeRoot(d.path);
          if (result.any((s) => s.path == root)) continue;
          result.add(StorageInfo(
            path: root,
            label: i == 0 ? 'Stockage interne' : 'Carte SD',
            isExternal: i > 0,
            isAvailable: Directory(root).existsSync(),
          ));
        }
      } catch (e) {
        debugPrint('[Storage] path_provider : $e');
      }
    }

    // Volumes que le système ne liste pas (certaines clés USB OTG) mais
    // visibles sous /storage avec l'accès à tous les fichiers.
    for (final dir in _listDirs('/storage')) {
      final name = p.basename(dir);
      if (name == 'emulated' || name == 'self') continue;
      if (result.any((s) => s.path == dir)) continue;
      result.add(StorageInfo(
        path: dir,
        label: 'Support externe ($name)',
        isExternal: true,
        isAvailable: true,
        kind: StorageKind.usb,
      ));
    }
    return result;
  }

  /// Convertit la réponse du canal natif (voir `MainActivity.storageVolumes`).
  @visibleForTesting
  static List<StorageInfo> parseAndroidVolumes(List<Map> volumes) {
    final result = <StorageInfo>[];
    for (final v in volumes) {
      final path = v['path'];
      if (path is! String || path.isEmpty) continue;
      final primary = v['primary'] == true;
      final removable = v['removable'] == true;
      final label = (v['label'] as String?)?.trim() ?? '';
      final lower = label.toLowerCase();
      final kind = primary || !removable
          ? StorageKind.internal
          : lower.contains('usb')
              ? StorageKind.usb
              : StorageKind.sdCard;
      result.add(StorageInfo(
        path: path,
        label: label.isNotEmpty
            ? label
            : switch (kind) {
                StorageKind.internal => 'Stockage interne',
                StorageKind.usb => 'Clé USB',
                _ => 'Carte SD',
              },
        isExternal: !primary,
        isAvailable: true,
        kind: kind,
        readOnly: v['readOnly'] == true,
      ));
    }
    // Le stockage principal en premier.
    result.sort((a, b) => (a.kind == StorageKind.internal ? 0 : 1)
        .compareTo(b.kind == StorageKind.internal ? 0 : 1));
    return result;
  }

  /// `/storage/XXXX-XXXX/Android/data/app/files` → `/storage/XXXX-XXXX`.
  @visibleForTesting
  static String androidVolumeRoot(String appDir) {
    final parts = appDir.split('/');
    final i = parts.indexOf('Android');
    return i > 0 ? parts.sublist(0, i).join('/') : appDir;
  }

  // ── Linux ────────────────────────────────────────────────────────────────

  static List<StorageInfo> _linux() {
    String mounts = '';
    try {
      mounts = File('/proc/self/mounts').readAsStringSync();
    } catch (_) {
      try {
        mounts = File('/proc/mounts').readAsStringSync();
      } catch (_) {}
    }
    return parseLinuxMounts(
      mounts,
      home: Platform.environment['HOME'],
      deviceKind: _linuxDeviceKind,
      exists: (path) => Directory(path).existsSync(),
    );
  }

  /// Systèmes de fichiers de données (les pseudo-systèmes — proc, tmpfs,
  /// squashfs des snaps, overlay… — sont ignorés).
  static const _diskTypes = {
    'ext2', 'ext3', 'ext4', 'btrfs', 'xfs', 'f2fs', 'jfs', 'reiserfs',
    'nilfs2', 'bcachefs', 'zfs', 'vfat', 'msdos', 'exfat', 'ntfs', 'ntfs3',
    'fuseblk', 'hfs', 'hfsplus', 'apfs', //
  };
  static const _opticalTypes = {'iso9660', 'udf'};
  static const _networkTypes = {
    'nfs', 'nfs4', 'cifs', 'smb3', 'smbfs', 'fuse.sshfs', 'fuse.rclone',
    '9p', 'davfs', 'fuse.davfs2', //
  };

  /// Préfixes de montages techniques à ne pas proposer.
  static const _hiddenPrefixes = [
    '/boot',
    '/efi',
    '/snap',
    '/var/snap',
    '/var/lib/snapd',
    '/var/lib/docker',
    '/proc',
    '/sys',
    '/dev',
    '/run/user',
    '/run/snapd',
    '/recovery',
  ];

  /// Analyse le contenu de `/proc/mounts`.
  ///
  /// [deviceKind] précise la nature d'un périphérique bloc (`/dev/sdb1` :
  /// USB, carte SD ou disque) ; [exists] filtre les points de montage
  /// inaccessibles.
  @visibleForTesting
  static List<StorageInfo> parseLinuxMounts(
    String mounts, {
    String? home,
    StorageKind Function(String device)? deviceKind,
    bool Function(String path)? exists,
  }) {
    exists ??= (_) => true;
    final result = <StorageInfo>[];
    if (home != null && home.isNotEmpty && exists(home)) {
      result.add(StorageInfo(
        path: home,
        label: 'Dossier personnel',
        isExternal: false,
        isAvailable: true,
        kind: StorageKind.home,
      ));
    }

    final seenDevices = <String>{};
    final others = <StorageInfo>[];
    for (final line in const LineSplitter().convert(mounts)) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 4) continue;
      final device = _unescape(cols[0]);
      final mountPoint = _unescape(cols[1]);
      final type = cols[2];
      final options = cols[3].split(',');

      final network = _networkTypes.contains(type);
      final optical = _opticalTypes.contains(type);
      if (!network && !optical && !_diskTypes.contains(type)) continue;
      if (device.startsWith('/dev/loop')) continue;
      if (mountPoint != '/' &&
          _hiddenPrefixes.any(
              (pre) => mountPoint == pre || mountPoint.startsWith('$pre/'))) {
        continue;
      }
      // Partition qui contient le dossier personnel (/home) : déjà couverte
      // par « Dossier personnel ».
      if (home != null &&
          mountPoint != '/' &&
          (home == mountPoint || home.startsWith('$mountPoint/'))) {
        continue;
      }
      // Sous-volumes btrfs, montages liés : un seul point par périphérique.
      if (!network && !seenDevices.add(device)) continue;
      if (!exists(mountPoint)) continue;

      final kind = mountPoint == '/'
          ? StorageKind.system
          : network
              ? StorageKind.network
              : optical
                  ? StorageKind.optical
                  : (deviceKind?.call(device) ?? StorageKind.disk);
      final removable = kind == StorageKind.usb ||
          kind == StorageKind.sdCard ||
          kind == StorageKind.optical ||
          mountPoint.startsWith('/media/') ||
          mountPoint.startsWith('/run/media/');
      final info = StorageInfo(
        path: mountPoint,
        label: mountPoint == '/'
            ? 'Système'
            : p.basename(mountPoint).isEmpty
                ? mountPoint
                : p.basename(mountPoint),
        isExternal: removable || network,
        isAvailable: true,
        kind: kind,
        readOnly: options.contains('ro'),
      );
      if (kind == StorageKind.system) {
        result.add(info);
      } else {
        others.add(info);
      }
    }
    others.sort((a, b) => a.path.compareTo(b.path));
    return [...result, ...others];
  }

  /// `/proc/mounts` code les espaces et caractères spéciaux en octal
  /// (`\040` pour une espace).
  static String _unescape(String s) => s.replaceAllMapped(
      RegExp(r'\\([0-7]{3})'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)));

  /// Nature d'un périphérique d'après sysfs : le lien
  /// `/sys/class/block/<nom>` passe par `…/usb…/` pour un support USB ;
  /// `mmcblk` désigne un lecteur de cartes SD.
  static StorageKind _linuxDeviceKind(String device) {
    if (!device.startsWith('/dev/')) return StorageKind.disk;
    var name = p.basename(device);
    try {
      // /dev/mapper/… (LUKS, LVM) : on suit le lien vers dm-N.
      name = p.basename(File(device).resolveSymbolicLinksSync());
    } catch (_) {}
    if (name.startsWith('mmcblk')) return StorageKind.sdCard;
    if (name.startsWith('sr')) return StorageKind.optical;
    try {
      final sys = Link('/sys/class/block/$name').resolveSymbolicLinksSync();
      if (sys.contains('/usb')) return StorageKind.usb;
      if (sys.contains('/mmc')) return StorageKind.sdCard;
    } catch (_) {}
    return StorageKind.disk;
  }

  static List<String> _listDirs(String path) {
    try {
      return Directory(path)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((d) => d.path)
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }
}
