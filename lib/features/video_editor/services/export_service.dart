/// @file export_service.dart
/// @brief Lance les commandes FFmpeg pour exporter les rendus de l'éditeur
/// vidéo (adapté de l'exemple fourni à `ffmpeg_kit_flutter_new`).

import 'dart:developer';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:omni_explorer/features/video_editor/utils/ffmpeg_config.dart';

class ExportService {
  /// Annule toutes les sessions FFmpeg en cours.
  static Future<void> disposeAll() async {
    final executions = await FFmpegKit.listSessions();
    if (executions.isNotEmpty) await FFmpegKit.cancel();
  }

  /// Lance une commande issue de `getExecuteConfig()` du package video_editor.
  static Future<FFmpegSession> runFFmpegCommand(
    FFmpegVideoEditorExecute execute, {
    required void Function(File file) onCompleted,
    void Function(Object, StackTrace)? onError,
    void Function(Statistics)? onProgress,
  }) {
    log('FFmpeg start process with command = ${execute.command}');
    return FFmpegKit.executeAsync(
      execute.command,
      (session) async {
        final state =
            FFmpegKitConfig.sessionStateToString(await session.getState());
        final code = await session.getReturnCode();

        if (ReturnCode.isSuccess(code)) {
          onCompleted(File(execute.outputPath));
        } else {
          onError?.call(
            Exception(
                'FFmpeg process exited with state $state and return code $code.\n${await session.getOutput()}'),
            StackTrace.current,
          );
        }
      },
      null,
      onProgress,
    );
  }

  /// Commande FFmpeg brute (pour reverse / concat / cover custom).
  static Future<FFmpegSession> runRawCommand(
    String command, {
    required String outputPath,
    required void Function(File file) onCompleted,
    void Function(Object, StackTrace)? onError,
    void Function(Statistics)? onProgress,
  }) {
    log('FFmpeg raw command = $command');
    return FFmpegKit.executeAsync(
      command,
      (session) async {
        final state =
            FFmpegKitConfig.sessionStateToString(await session.getState());
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          onCompleted(File(outputPath));
        } else {
          onError?.call(
            Exception(
                'FFmpeg exited with state $state, code $code.\n${await session.getOutput()}'),
            StackTrace.current,
          );
        }
      },
      null,
      onProgress,
    );
  }

  /// Inverse une vidéo (audio + vidéo) en réencodage.
  static String reverseCommand(String input, String output) =>
      '-i ${_q(input)} -vf reverse -af areverse ${_q(output)}';

  /// Concatène une liste de vidéos via le démuxer concat (pas de réencodage si
  /// même codec/résolution ; sinon FFmpeg signale l'erreur).
  static String concatCommand(String listFilePath, String output) =>
      '-y -f concat -safe 0 -i ${_q(listFilePath)} -c copy ${_q(output)}';

  static String _q(String path) =>
      path.contains(' ') ? '"$path"' : path;
}
