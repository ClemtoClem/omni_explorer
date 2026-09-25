/// @file ssh_known_hosts.dart
/// @brief Clés d'hôte SSH connues (équivalent de `~/.ssh/known_hosts`).
///
/// Principe « confiance à la première connexion » (TOFU) : l'empreinte d'un
/// serveur inconnu est montrée à l'utilisateur, qui l'accepte ou non ; elle
/// est ensuite exigée à chaque connexion. Une empreinte différente signale
/// une possible interception (attaque de l'homme du milieu) : la connexion
/// est refusée.
///
/// Les empreintes sont publiques : les préférences suffisent à les stocker.

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/constants/app_constants.dart';

enum HostKeyStatus {
  /// Empreinte déjà acceptée pour ce serveur.
  trusted,

  /// Premier contact : demander à l'utilisateur.
  unknown,

  /// Empreinte différente de celle acceptée : refuser.
  changed,
}

class SshKnownHosts {
  final SharedPreferences _prefs;
  SshKnownHosts(this._prefs);

  /// Empreinte au format d'OpenSSH : `SHA256:` + base64 sans remplissage.
  static String formatFingerprint(Uint8List sha256) =>
      'SHA256:${base64.encode(sha256).replaceAll('=', '')}';

  static String _hostId(String host, int port) =>
      '${host.trim().toLowerCase()}:$port';

  Map<String, String> _load() {
    final raw = _prefs.getString(AppConstants.prefSshKnownHosts);
    if (raw == null) return {};
    // Illisible : aucune clé n'est considérée comme connue (on redemandera),
    // ce qui ne fait jamais accepter une clé à tort.
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return {};
    }
    if (decoded is! Map) return {};
    return {
      for (final e in decoded.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  }

  /// Statut de la clé [type] d'empreinte [fingerprint] pour [host]:[port].
  HostKeyStatus check(
      String host, int port, String type, Uint8List fingerprint) {
    final known = _load()[_hostId(host, port)];
    if (known == null) return HostKeyStatus.unknown;
    return known == '$type ${formatFingerprint(fingerprint)}'
        ? HostKeyStatus.trusted
        : HostKeyStatus.changed;
  }

  /// Empreinte acceptée pour [host]:[port], au format « type SHA256:… ».
  String? knownKey(String host, int port) => _load()[_hostId(host, port)];

  /// Accepte (ou remplace) la clé de [host]:[port].
  Future<void> trust(
      String host, int port, String type, Uint8List fingerprint) async {
    final all = _load()
      ..[_hostId(host, port)] = '$type ${formatFingerprint(fingerprint)}';
    await _prefs.setString(AppConstants.prefSshKnownHosts, jsonEncode(all));
  }

  /// Oublie la clé de [host]:[port] (serveur réinstallé, par exemple).
  Future<void> forget(String host, int port) async {
    final all = _load()..remove(_hostId(host, port));
    await _prefs.setString(AppConstants.prefSshKnownHosts, jsonEncode(all));
  }
}
