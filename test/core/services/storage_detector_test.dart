/// Détection des supports de stockage : analyse de /proc/mounts (Linux) et
/// des volumes renvoyés par Android.

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/core/services/file_service.dart';
import 'package:omni_explorer/core/services/storage_detector.dart';

void main() {
  group('Linux (/proc/mounts)', () {
    const mounts = '''
sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
udev /dev devtmpfs rw,nosuid,relatime 0 0
tmpfs /run tmpfs rw,nosuid,nodev,noexec,relatime 0 0
/dev/nvme0n1p2 / ext4 rw,relatime 0 0
/dev/loop3 /snap/flutter/145 squashfs ro,nodev,relatime 0 0
/dev/nvme0n1p1 /boot/efi vfat rw,relatime 0 0
/dev/nvme0n1p3 /home ext4 rw,relatime 0 0
/dev/sda1 /mnt/data ext4 rw,relatime 0 0
/dev/sda1 /srv/bind ext4 rw,relatime 0 0
/dev/sdb1 /media/clement/MA\\040CLE vfat rw,nosuid,nodev 0 0
/dev/mmcblk0p1 /media/clement/PHOTOS exfat rw,nosuid,nodev 0 0
/dev/sr0 /media/clement/DVD iso9660 ro,nosuid,nodev 0 0
nas:/volume1 /mnt/nas nfs4 rw,relatime 0 0
tmpfs /run/user/1000 tmpfs rw,nosuid,nodev 0 0
gvfsd-fuse /run/user/1000/gvfs fuse.gvfsd-fuse rw,nosuid,nodev 0 0
overlay /var/lib/docker/overlay2/x/merged overlay rw 0 0
''';

    final storages = StorageDetector.parseLinuxMounts(
      mounts,
      home: '/home/clement',
      deviceKind: (dev) => switch (dev) {
        '/dev/sdb1' => StorageKind.usb,
        '/dev/mmcblk0p1' => StorageKind.sdCard,
        _ => StorageKind.disk,
      },
    );

    test('dossier personnel, système, puis les autres par chemin', () {
      expect(storages.map((s) => s.path), [
        '/home/clement',
        '/',
        '/media/clement/DVD',
        '/media/clement/MA CLE', // \\040 décodé
        '/media/clement/PHOTOS',
        '/mnt/data',
        '/mnt/nas',
      ]);
    });

    test('nature et libellé de chaque support', () {
      final byPath = {for (final s in storages) s.path: s};
      expect(byPath['/home/clement']!.kind, StorageKind.home);
      expect(byPath['/']!.label, 'Système');
      expect(byPath['/media/clement/MA CLE']!.kind, StorageKind.usb);
      expect(byPath['/media/clement/MA CLE']!.label, 'MA CLE');
      expect(byPath['/media/clement/PHOTOS']!.kind, StorageKind.sdCard);
      expect(byPath['/media/clement/DVD']!.kind, StorageKind.optical);
      expect(byPath['/media/clement/DVD']!.readOnly, isTrue);
      expect(byPath['/mnt/nas']!.kind, StorageKind.network);
      expect(byPath['/mnt/data']!.kind, StorageKind.disk);
      expect(byPath['/mnt/data']!.isExternal, isFalse);
      expect(byPath['/media/clement/MA CLE']!.isExternal, isTrue);
    });

    test('écarte snaps, /boot, pseudo-systèmes, /home, montages en double', () {
      final paths = storages.map((s) => s.path).toSet();
      for (final hidden in [
        '/snap/flutter/145',
        '/boot/efi',
        '/home', // contient le dossier personnel
        '/srv/bind', // même périphérique que /mnt/data
        '/run/user/1000/gvfs',
        '/proc',
      ]) {
        expect(paths.contains(hidden), isFalse, reason: hidden);
      }
    });

    test('points de montage inaccessibles ignorés', () {
      final r = StorageDetector.parseLinuxMounts(mounts,
          home: '/home/clement', exists: (p) => p != '/mnt/nas');
      expect(r.any((s) => s.path == '/mnt/nas'), isFalse);
    });
  });

  group('Android', () {
    test('volumes du système : interne d\'abord, SD et USB reconnus', () {
      final r = StorageDetector.parseAndroidVolumes([
        {
          'path': '/storage/1234-ABCD',
          'label': 'Carte SD SanDisk',
          'primary': false,
          'removable': true,
        },
        {
          'path': '/storage/emulated/0',
          'label': 'Espace de stockage interne partagé',
          'primary': true,
          'removable': false,
        },
        {
          'path': '/storage/9F3E-1111',
          'label': 'Clé USB Kingston',
          'primary': false,
          'removable': true,
          'readOnly': true,
        },
        {'path': '', 'label': 'invalide'},
      ]);
      expect(r.map((s) => (s.path, s.kind)), [
        ('/storage/emulated/0', StorageKind.internal),
        ('/storage/1234-ABCD', StorageKind.sdCard),
        ('/storage/9F3E-1111', StorageKind.usb),
      ]);
      expect(r.last.readOnly, isTrue);
      expect(r[1].label, 'Carte SD SanDisk');
    });

    test('nom manquant : libellé par défaut', () {
      final r = StorageDetector.parseAndroidVolumes([
        {'path': '/storage/AAAA-0000', 'primary': false, 'removable': true},
      ]);
      expect(r.single.label, 'Carte SD');
    });

    test('racine d\'un volume depuis un dossier d\'application', () {
      expect(
          StorageDetector.androidVolumeRoot(
              '/storage/1234-ABCD/Android/data/com.example/files'),
          '/storage/1234-ABCD');
      expect(StorageDetector.androidVolumeRoot('/storage/emulated/0'),
          '/storage/emulated/0');
    });
  });
}
