/// @file vault_sort.dart
/// @brief Tri des entrées du coffre : par tag (croissant / décroissant) ou
/// par catégorie.

import '../models/vault_entry.dart';

enum VaultSortMode {
  /// Tags de A à Z.
  tagAscending('tag_asc', 'Tag (A → Z)'),

  /// Tags de Z à A.
  tagDescending('tag_desc', 'Tag (Z → A)'),

  /// Regroupées par catégorie (catégories de A à Z), tags de A à Z dans
  /// chaque catégorie.
  category('category', 'Catégorie');

  /// Clé enregistrée dans les préférences.
  final String key;
  final String label;
  const VaultSortMode(this.key, this.label);

  static VaultSortMode byKey(String? key) => values.firstWhere(
        (m) => m.key == key,
        orElse: () => VaultSortMode.tagAscending,
      );
}

/// Clé de comparaison : sans casse ni accents (« Éducation » se range avec
/// les « e »), espaces de bord ignorés.
String vaultSortKey(String text) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final lower = text.trim().toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

int _byTag(VaultEntry a, VaultEntry b) {
  final c = vaultSortKey(a.title).compareTo(vaultSortKey(b.title));
  // Ordre stable et déterministe entre tags égaux.
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Renvoie [entries] triées selon [mode] (la liste d'origine n'est pas
/// modifiée).
List<VaultEntry> sortVaultEntries(
    Iterable<VaultEntry> entries, VaultSortMode mode) {
  final list = [...entries];
  switch (mode) {
    case VaultSortMode.tagAscending:
      list.sort(_byTag);
    case VaultSortMode.tagDescending:
      list.sort((a, b) => _byTag(b, a));
    case VaultSortMode.category:
      list.sort((a, b) {
        final c = vaultSortKey(a.category.label)
            .compareTo(vaultSortKey(b.category.label));
        return c != 0 ? c : _byTag(a, b);
      });
  }
  return list;
}
