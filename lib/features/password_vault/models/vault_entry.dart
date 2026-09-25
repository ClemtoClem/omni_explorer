/// @file vault_entry.dart
/// @brief Entrée du coffre-fort et contenu déchiffré (schéma versionné).

import 'vault_errors.dart';

/// Un identifiant enregistré dans le coffre.
class VaultEntry {
  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VaultEntry({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  VaultEntry copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    DateTime? updatedAt,
  }) =>
      VaultEntry(
        id: id,
        title: title ?? this.title,
        username: username ?? this.username,
        password: password ?? this.password,
        url: url ?? this.url,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Vrai si [query] apparaît dans le titre, l'identifiant ou l'adresse
  /// (jamais dans le mot de passe ni les notes).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        username.toLowerCase().contains(q) ||
        url.toLowerCase().contains(q);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, Object?> json) {
    String str(String key, {bool required = false}) {
      final v = json[key];
      if (v is String) return v;
      if (v == null && !required) return '';
      throw VaultCorruptedException('entrée : champ « $key » invalide');
    }

    DateTime date(String key) {
      final parsed = DateTime.tryParse(str(key, required: true));
      if (parsed == null) {
        throw VaultCorruptedException('entrée : date « $key » invalide');
      }
      return parsed;
    }

    return VaultEntry(
      id: str('id', required: true),
      title: str('title', required: true),
      username: str('username'),
      password: str('password'),
      url: str('url'),
      notes: str('notes'),
      createdAt: date('createdAt'),
      updatedAt: date('updatedAt'),
    );
  }
}

/// Contenu déchiffré du coffre.
///
/// Le champ `schema` versionne la structure de ce contenu, indépendamment du
/// format du fichier : une évolution (nouveau champ, catégories…) ajoute une
/// étape à [_migrations] au lieu de rendre les anciens coffres illisibles.
class VaultContent {
  /// Version du schéma produite par cette version de l'application.
  static const int currentSchema = 1;

  final List<VaultEntry> entries;

  const VaultContent(this.entries);

  static const empty = VaultContent([]);

  Map<String, Object?> toJson() => {
        'schema': currentSchema,
        'entries': [for (final e in entries) e.toJson()],
      };

  /// Migrations successives : la clé est le schéma de départ, la fonction
  /// produit le JSON du schéma suivant.
  static final Map<int, Map<String, Object?> Function(Map<String, Object?>)>
      _migrations = {};

  factory VaultContent.fromJson(Object? decoded) {
    if (decoded is! Map<String, Object?>) {
      throw const VaultCorruptedException('contenu : objet attendu');
    }
    var json = decoded;
    var schema = json['schema'];
    if (schema is! int || schema < 1) {
      throw const VaultCorruptedException('contenu : schéma invalide');
    }
    if (schema > currentSchema) {
      throw const VaultTooNewException();
    }
    while (schema != currentSchema) {
      final migrate = _migrations[schema];
      if (migrate == null) {
        throw VaultCorruptedException('contenu : pas de migration du schéma '
            '$schema');
      }
      json = migrate(json);
      schema = (schema as int) + 1;
    }
    final list = json['entries'];
    if (list is! List) {
      throw const VaultCorruptedException('contenu : liste d\'entrées absente');
    }
    return VaultContent([
      for (final e in list)
        if (e is Map<String, Object?>)
          VaultEntry.fromJson(e)
        else
          throw const VaultCorruptedException('contenu : entrée invalide'),
    ]);
  }
}
