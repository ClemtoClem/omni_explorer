/// @file permissions_service.dart
/// @brief Centralise la demande de toutes les permissions de l'application
/// au premier lancement (et fournit un point d'entrée pour les redemander
/// depuis les Paramètres).
/// 
/// @code ```dart
/// void _handlePermissions(BuildContext context) async {
///   final result = await PermissionsService.requestAll();
///
///   if (result.allGranted) {
///     // Top ! On passe à la suite.
///     await PermissionsService.markFirstLaunchDone();
///     Navigator.of(context).pushReplacementNamed('/home');
///   } else if (result.hasPermanentlyDenied) {
///     // L'utilisateur a coché "Ne plus demander". On doit lui expliquer pourquoi c'est requis
///     // et lui proposer d'ouvrir les paramètres.
///     _showSettingsDialog(context);
///   } else {
///     // Refus simple, on peut afficher un message d'explication standard.
///     ScaffoldMessenger.of(context).showSnackBar(
///       const SnackBar(content: Text('Certaines permissions sont nécessaires pour lister vos fichiers.')),
///     );
///   }
/// }
///
/// void _showSettingsDialog(BuildContext context) {
///   showDialog(
///     context: context,
///     builder: (ctx) => AlertDialog(
///       title: const Text('Permissions requises'),
///       document: const Text('Vous avez désactivé des permissions cruciales. Veuillez les réactiver dans les paramètres système.'),
///       actions: [
///         TextButton(
///           onChanged: () => Navigator.pop(ctx),
///           child: const Text('Annuler'),
///         ),
///         ElevatedButton(
///           onPressed: () {
///             Navigator.pop(ctx);
///             PermissionsService.openAppSettingsPage();
///           },
///           child: const Text('Ouvrir les Paramètres'),
///         ),
///       ],
///     ),
///   );
/// }
/// ```

import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionsResult {
  final Map<Permission, PermissionStatus> statuses;
  const PermissionsResult(this.statuses);

  /// Renvoie vrai si TOUTES les permissions demandées sont accordées ou limitées.
  bool get allGranted =>
      statuses.values.every((s) => s.isGranted || s.isLimited);

  /// Liste les permissions qui ont été refusées.
  Iterable<Permission> get denied =>
      statuses.entries.where((e) => !e.value.isGranted && !e.value.isLimited).map((e) => e.key);

  /// Indique si au moins une permission a été définitivement refusée par l'utilisateur
  /// (nécessite un saut manuel dans les paramètres de l'application).
  bool get hasPermanentlyDenied =>
      statuses.values.any((s) => s.isPermanentlyDenied);
}

class PermissionsService {
  static const _kFirstLaunchKey = 'permissions.first_launch_done';

  /// Renvoie l'ensemble des permissions runtime utiles à l'application sur la
  /// plateforme courante.
  static List<Permission> _runtimePermissions() {
    if (kIsWeb || !Platform.isAndroid) return const [];
    
    // Note : Idéalement, utilisez le package `device_info_plus` pour filtrer finement par SDK Android.
    // À défaut, on liste les permissions ; permission_handler gère l'incompatibilité API gracieusement.
    return const [
      // ── Stockage et médias ──
      Permission.storage,
      Permission.photos,
      Permission.videos,
      Permission.audio,
      Permission.accessMediaLocation,
      
      // ── Bluetooth (IMPORTANT) ──
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      
      // ── Notifications ──
      Permission.notification
    ];
  }

  /// Permissions à statut « spécial » (saut dans Paramètres système).
  static List<Permission> _specialPermissions() {
    if (kIsWeb || !Platform.isAndroid) return const [];
    return const [
      Permission.manageExternalStorage, // Gestion globale des fichiers (Android 11+)
    ];
  }

  /// Ouvre les paramètres de modification système (pour WRITE_SETTINGS)
  static Future<void> openSystemWriteSettingsPage() async {
    if (!Platform.isAndroid) return;
    
    const platform = MethodChannel('com.example.omni_explorer/settings');
    try {
      await platform.invokeMethod('openWriteSettings');
    } catch (e) {
      debugPrint('[Permissions] Impossible d\'ouvrir WRITE_SETTINGS : $e');
    }
  }

  /// Demande toutes les permissions (Runtime + Spéciales) en une seule passe.
  /// Encapsulé dans try/catch : si `permission_handler` n'est pas chargé
  /// nativement (APK non reconstruit après ajout du plugin → typique
  /// MissingPluginException), on logge et on continue plutôt que de bloquer
  /// l'app entière.
  static Future<PermissionsResult> requestAll() async {
    final result = <Permission, PermissionStatus>{};

    // 1. Demande groupée des permissions standards
    final runtime = _runtimePermissions();
    if (runtime.isNotEmpty) {
      developer.log('Demande des permissions runtime...', name: 'PermissionsService');
      try {
        result.addAll(await runtime.request());
      } on MissingPluginException catch (e) {
        debugPrint('[Permissions] plugin natif indisponible (runtime) : $e — '
            'reconstruire l\'APK avec `flutter clean && flutter run`.');
      } catch (e) {
        debugPrint('[Permissions] échec runtime : $e');
      }
    }

    // 2. Demande séquentielle des permissions spéciales (intent système).
    for (final perm in _specialPermissions()) {
      try {
        final status = await perm.status;
        if (!status.isGranted) {
          developer.log('Demande de la permission spéciale : $perm',
              name: 'PermissionsService');
          result[perm] = await perm.request();
        } else {
          result[perm] = status;
        }
      } on MissingPluginException catch (e) {
        debugPrint('[Permissions] plugin natif indisponible ($perm) : $e');
      } catch (e) {
        debugPrint('[Permissions] échec $perm : $e');
      }
    }

    return PermissionsResult(result);
  }

  /// Récupère l'état actuel de toutes les permissions sans afficher de boîte de dialogue.
  static Future<PermissionsResult> checkCurrentStatuses() async {
    final result = <Permission, PermissionStatus>{};
    final allPermissions = [..._runtimePermissions(), ..._specialPermissions()];

    try {
      final statuses = await Future.wait(allPermissions.map((p) => p.status));
      for (var i = 0; i < allPermissions.length; i++) {
        result[allPermissions[i]] = statuses[i];
      }
    } on MissingPluginException catch (e) {
      debugPrint('[Permissions] checkCurrentStatuses indisponible : $e');
    } catch (e) {
      debugPrint('[Permissions] checkCurrentStatuses erreur : $e');
    }
    return PermissionsResult(result);
  }

  /// Ouvre la page des paramètres de l'application. 
  /// Utile à appeler si `result.hasPermanentlyDenied` est vrai.
  static Future<bool> openAppSettingsPage() async {
    developer.log('Ouverture des paramètres de l\'application...', name: 'PermissionsService');
    return await openAppSettings();
  }

  /// Marque la passe initiale comme terminée.
  static Future<void> markFirstLaunchDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFirstLaunchKey, true);
  }

  /// Vérifie si le premier lancement a déjà eu lieu.
  static Future<bool> isFirstLaunchDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kFirstLaunchKey) ?? false;
  }

  /// Statut courant de MANAGE_EXTERNAL_STORAGE.
  static Future<bool> hasManageExternalStorage() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await Permission.manageExternalStorage.isGranted;
    } on MissingPluginException catch (e) {
      debugPrint('[Permissions] hasManageExternalStorage indisponible : $e');
      return false;
    } catch (e) {
      debugPrint('[Permissions] hasManageExternalStorage erreur : $e');
      return false;
    }
  }

  /// Indique si l'une des permissions critiques (médias + tous fichiers) est manquante.
  /// Renvoie `true` (= il manque quelque chose) en cas d'erreur pour redéclencher
  /// la demande au prochain lancement.
  static Future<bool> hasMissingCriticalPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final statuses = await Future.wait([
        Permission.photos.status,
        Permission.videos.status,
        Permission.audio.status,
        Permission.storage.status,
        Permission.manageExternalStorage.status,
      ]);

      final mediaOk = statuses.sublist(0, 4).any((s) => s.isGranted || s.isLimited);
      final fullOk = statuses[4].isGranted;

      return !(mediaOk && fullOk);
    } on MissingPluginException catch (e) {
      debugPrint('[Permissions] hasMissingCriticalPermissions indisponible : $e — '
          'reconstruire l\'APK avec `flutter clean && flutter run`.');
      return true;
    } catch (e) {
      debugPrint('[Permissions] hasMissingCriticalPermissions erreur : $e');
      return true;
    }
  }
}
