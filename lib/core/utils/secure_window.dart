/// @file secure_window.dart
/// @brief Protection de l'écran pour les contenus sensibles (Android) :
/// captures et enregistrements bloqués, vignette masquée dans les
/// applications récentes (`FLAG_SECURE`).
///
/// Compteur de références : l'écran reste protégé tant qu'au moins un écran
/// sensible est affiché. Sans effet hors Android (Linux n'a pas d'équivalent).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecureWindow {
  SecureWindow._();

  static const MethodChannel _channel =
      MethodChannel('com.example.omni_explorer/security');

  static int _holders = 0;

  /// Nombre d'écrans sensibles affichés (tests).
  @visibleForTesting
  static int get holders => _holders;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// À appeler à l'affichage d'un écran sensible.
  static Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _set(true);
  }

  /// À appeler quand l'écran sensible disparaît.
  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _set(false);
  }

  static Future<void> _set(bool enabled) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('setSecure', {'enabled': enabled});
    } on PlatformException catch (e) {
      debugPrint('[SecureWindow] ${e.code}');
    } on MissingPluginException {
      debugPrint('[SecureWindow] canal natif absent');
    }
  }
}
