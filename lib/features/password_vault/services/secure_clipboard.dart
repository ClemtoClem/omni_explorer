/// @file secure_clipboard.dart
/// @brief Copie de secrets dans le presse-papiers, effacée automatiquement.
///
/// - Android : copie marquée « sensible » (Android 13+ ne l'affiche pas en
///   aperçu), effacement natif. Une application en arrière-plan ne pouvant
///   plus lire le presse-papiers (Android 10+), l'effacement a lieu aussi
///   quand la vérification est impossible.
/// - Autres plateformes : presse-papiers Flutter, effacé seulement s'il
///   contient encore la valeur copiée.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecureClipboard {
  /// Délai avant effacement.
  final Duration clearAfter;
  final bool _useNative;

  SecureClipboard({
    this.clearAfter = const Duration(seconds: 30),
    @visibleForTesting bool? useNative,
  }) : _useNative = useNative ?? (!kIsWeb && Platform.isAndroid);

  static const MethodChannel _channel =
      MethodChannel('com.example.omni_explorer/security');

  Timer? _timer;
  String? _copied;

  /// Vrai si une copie attend d'être effacée.
  bool get hasPendingClear => _timer?.isActive ?? false;

  /// Copie [text] et programme son effacement.
  Future<void> copy(String text) async {
    if (_useNative) {
      await _channel.invokeMethod('copySensitive', {'text': text});
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
    _copied = text;
    _timer?.cancel();
    _timer = Timer(clearAfter, () => unawaited(clearNow()));
  }

  /// Efface immédiatement la copie en attente (verrouillage du coffre…).
  Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    final expected = _copied;
    _copied = null;
    if (expected == null) return;
    try {
      if (_useNative) {
        await _channel.invokeMethod('clearVaultClip');
      } else {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == expected) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      }
    } on PlatformException catch (e) {
      debugPrint('[SecureClipboard] effacement impossible : ${e.code}');
    } on MissingPluginException {
      debugPrint('[SecureClipboard] canal natif absent');
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
