/// @file video_export_service.dart
/// @brief Export vidéo en arrière-plan : service de premier plan (garde le
/// process vivant si l'app passe en arrière-plan), notification de progression
/// puis notification de fin. L'encodage FFmpeg tourne déjà sur un thread natif
/// (hors isolate Dart) donc l'UI ne gèle pas ; le service de premier plan évite
/// que l'OS ne tue l'app pendant un export long.

import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;

class VideoExportService {
  static final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static const int _doneNotifId = 4242;

  /// À appeler une fois au démarrage (depuis main.dart).
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'video_export',
        channelName: 'Export vidéo',
        channelDescription: 'Progression de l\'export vidéo',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );

    await _notif.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
  }

  /// Annule un éventuel export en cours et arrête le service.
  static Future<void> cancel() async {
    final sessions = await FFmpegKit.listSessions();
    if (sessions.isNotEmpty) await FFmpegKit.cancel();
    await _stopService();
  }

  static Future<void> _stopService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Lance l'export en arrière-plan.
  ///
  /// [command] est la commande FFmpeg déjà assemblée (régulée thermiquement) ;
  /// [outputPath] le fichier de sortie ; [totalDurationMs] sert au calcul de la
  /// progression.
  static Future<void> export({
    required String command,
    required String outputPath,
    required int totalDurationMs,
    void Function(double progress)? onProgress,
    required void Function(File file) onCompleted,
    void Function(Object error)? onError,
  }) async {
    await init();

    // Démarre le service de premier plan (notification persistante).
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Export vidéo',
        notificationText: 'Préparation…',
      );
    } catch (e) {
      // Pas bloquant : sans service, l'export marche tant que l'app reste ouverte.
      debugPrint('[Export] foreground service indisponible : $e');
    }

    await FFmpegKit.executeAsync(
      command,
      (session) async {
        final code = await session.getReturnCode();
        await _stopService();
        if (ReturnCode.isSuccess(code)) {
          await _showDone(success: true, fileName: p.basename(outputPath));
          onCompleted(File(outputPath));
        } else {
          final logs = await session.getOutput();
          debugPrint('[Export] FFmpeg échec ($code) : $logs');
          await _showDone(success: false, fileName: p.basename(outputPath));
          onError?.call('Échec de l\'export (code $code)');
        }
      },
      null,
      (Statistics stats) {
        if (totalDurationMs <= 0) return;
        final progress = (stats.getTime() / totalDurationMs).clamp(0.0, 1.0);
        onProgress?.call(progress);
        final pct = (progress * 100).round();
        FlutterForegroundTask.updateService(
          notificationTitle: 'Export vidéo',
          notificationText: 'En cours… $pct %',
        );
      },
    );
  }

  static Future<void> _showDone(
      {required bool success, required String fileName}) async {
    const android = AndroidNotificationDetails(
      'video_export_done',
      'Export terminé',
      channelDescription: 'Notification de fin d\'export vidéo',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _notif.show(
      _doneNotifId,
      success ? '✅ Export terminé' : '❌ Export échoué',
      success ? fileName : 'Une erreur est survenue pendant l\'export.',
      const NotificationDetails(android: android, iOS: DarwinNotificationDetails()),
    );
  }
}
