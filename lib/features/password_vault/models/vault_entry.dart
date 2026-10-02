/// @file vault_entry.dart
/// @brief Entrée du coffre-fort et contenu déchiffré (schéma versionné).
///
/// Schéma 1 : identifiants seulement (titre, identifiant, mot de passe,
/// adresse, notes). Schéma 2 : catégories ([VaultCategory]) et champs par
/// catégorie ; les entrées du schéma 1 deviennent des « Site web ».

import 'vault_category.dart';
import 'vault_errors.dart';

export 'vault_category.dart';

/// Une information enregistrée dans le coffre : un tag (son nom), une
/// catégorie et les valeurs des champs de cette catégorie.
class VaultEntry {
  final String id;

  /// Tag de l'entrée (nom affiché, clé de tri). Enregistré sous `title`.
  final String title;

  /// Clé de la catégorie, gardée telle quelle même si cette version ne la
  /// connaît pas (coffre écrit par une version plus récente).
  final String categoryKey;

  /// Valeurs par clé de champ ([VaultField.key]). Les clés inconnues de la
  /// catégorie sont conservées à l'enregistrement.
  final Map<String, String> fields;

  final DateTime createdAt;
  final DateTime updatedAt;

  VaultEntry({
    required this.id,
    required this.title,
    VaultCategory category = VaultCategory.website,
    String? categoryKey,
    Map<String, String> fields = const {},
    required this.createdAt,
    required this.updatedAt,
  })  : categoryKey = categoryKey ?? category.key,
        fields = Map.unmodifiable({
          for (final e in fields.entries)
            if (e.value.isNotEmpty) e.key: e.value,
        });

  /// Catégorie affichée (« Site web » pour une catégorie inconnue).
  VaultCategory get category =>
      VaultCategory.byKey(categoryKey) ?? VaultCategory.website;

  /// Valeur du champ [key] (vide si absent).
  String operator [](String key) => fields[key] ?? '';

  String get username => this['username'];
  String get password => this['password'];
  String get url => this['url'];
  String get notes => this['notes'];

  /// Texte affiché sous le tag dans la liste (champ résumé de la catégorie).
  String get summary {
    final key = category.summary;
    return key == null ? '' : this[key];
  }

  /// Valeur secrète principale (copiable depuis la liste).
  String get primarySecret {
    final key = category.secret;
    return key == null ? '' : this[key];
  }

  VaultEntry copyWith({
    String? title,
    VaultCategory? category,
    Map<String, String>? fields,
    DateTime? updatedAt,
  }) =>
      VaultEntry(
        id: id,
        title: title ?? this.title,
        categoryKey: category?.key ?? categoryKey,
        fields: fields ?? this.fields,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Même contenu (tag, catégorie, champs), dates et identifiant exclus.
  bool sameContent(VaultEntry other) =>
      title == other.title &&
      categoryKey == other.categoryKey &&
      fields.length == other.fields.length &&
      fields.entries.every((e) => other.fields[e.key] == e.value);

  /// Vrai si [query] apparaît dans le tag, le nom de la catégorie ou un
  /// champ lisible (jamais dans un champ secret ni dans les notes).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    if (category.label.toLowerCase().contains(q)) return true;
    for (final f in category.fields) {
      if (f.isSecret || f.key == 'notes') continue;
      if (this[f.key].toLowerCase().contains(q)) return true;
    }
    return false;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'category': categoryKey,
        'fields': fields,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, Object?> json) {
    String str(String key) {
      final v = json[key];
      if (v is String) return v;
      throw VaultCorruptedException('entrée : champ « $key » invalide');
    }

    DateTime date(String key) {
      final parsed = DateTime.tryParse(str(key));
      if (parsed == null) {
        throw VaultCorruptedException('entrée : date « $key » invalide');
      }
      return parsed;
    }

    final raw = json['fields'];
    if (raw is! Map) {
      throw const VaultCorruptedException('entrée : champs invalides');
    }
    final fields = <String, String>{};
    for (final e in raw.entries) {
      if (e.key is! String || e.value is! String) {
        throw const VaultCorruptedException('entrée : champ invalide');
      }
      fields[e.key as String] = e.value as String;
    }

    return VaultEntry(
      id: str('id'),
      title: str('title'),
      categoryKey: str('category'),
      fields: fields,
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
  static const int currentSchema = 2;

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
      _migrations = {1: _fromSchema1};

  /// Schéma 1 → 2 : chaque identifiant devient une entrée « Site web ».
  static Map<String, Object?> _fromSchema1(Map<String, Object?> json) {
    final list = json['entries'];
    if (list is! List) return json; // signalé ensuite comme corrompu
    return {
      ...json,
      'schema': 2,
      'entries': [
        for (final e in list)
          if (e is Map<String, Object?>)
            {
              for (final k in const ['id', 'title', 'createdAt', 'updatedAt'])
                k: e[k],
              'category': VaultCategory.website.key,
              'fields': {
                for (final k in const ['username', 'password', 'url', 'notes'])
                  if (e[k] != null) k: e[k],
              },
            }
          else
            e,
      ],
    };
  }

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
