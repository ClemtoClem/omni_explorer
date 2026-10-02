/// @file vault_merge.dart
/// @brief Fusion des entrées d'un export dans le coffre ouvert.
///
/// Une entrée importée « correspond » à une entrée existante si elle a le
/// même identifiant interne (export de ce même coffre), ou la même
/// catégorie, le même tag et le même champ résumé de la catégorie
/// (identifiant, adresse e-mail, banque… : même information saisie sur un
/// autre appareil).
/// - aucune correspondance : entrée ajoutée ;
/// - correspondance au contenu identique : ignorée (doublon) ;
/// - correspondance au contenu différent : conflit, résolu selon le choix de
///   l'utilisateur ([ImportConflictChoice]).

import '../models/vault_entry.dart';

enum ImportConflictChoice {
  /// Ajouter l'entrée importée à côté de l'existante (titre suffixé).
  keepBoth,

  /// Remplacer le contenu de l'existante par l'importée.
  replace,

  /// Garder l'existante, ignorer l'importée.
  skip,
}

/// Conflit entre une entrée existante et une entrée importée.
class ImportConflict {
  final VaultEntry existing;
  final VaultEntry incoming;
  const ImportConflict(this.existing, this.incoming);
}

/// Résultat de l'analyse d'un import, avant application.
class ImportPlan {
  final List<VaultEntry> added;
  final List<VaultEntry> identical;
  final List<ImportConflict> conflicts;

  const ImportPlan({
    required this.added,
    required this.identical,
    required this.conflicts,
  });

  int get total => added.length + identical.length + conflicts.length;
}

class VaultMerge {
  VaultMerge._();

  /// Suffixe du titre d'une entrée importée gardée à côté d'une existante.
  static const String keptBothSuffix = ' (importé)';

  static String _key(VaultEntry e) => [
        e.categoryKey,
        e.title.trim().toLowerCase(),
        e.summary.trim().toLowerCase(),
        // Les sites web se distinguent aussi par leur adresse.
        e.url.trim().toLowerCase(),
      ].join('\u0000');

  /// Classe les entrées importées [incoming] par rapport à [existing].
  static ImportPlan plan(List<VaultEntry> existing, List<VaultEntry> incoming) {
    final byId = {for (final e in existing) e.id: e};
    final byKey = {for (final e in existing) _key(e): e};
    final added = <VaultEntry>[];
    final identical = <VaultEntry>[];
    final conflicts = <ImportConflict>[];
    final seen = <String>{};

    for (final e in incoming) {
      // Doublon à l'intérieur même de l'export : une seule fois.
      if (!seen.add(e.id)) continue;
      final match = byId[e.id] ?? byKey[_key(e)];
      if (match == null) {
        added.add(e);
      } else if (match.sameContent(e)) {
        identical.add(e);
      } else {
        conflicts.add(ImportConflict(match, e));
      }
    }
    return ImportPlan(added: added, identical: identical, conflicts: conflicts);
  }

  /// Applique [plan] à [existing] selon [choice]. [newId] fournit un
  /// identifiant pour les entrées gardées en double.
  static List<VaultEntry> apply(
    List<VaultEntry> existing,
    ImportPlan plan,
    ImportConflictChoice choice, {
    required String Function() newId,
    required DateTime now,
  }) {
    final result = [...existing];
    final usedIds = {for (final e in existing) e.id};

    VaultEntry withFreshIdIfTaken(VaultEntry e) {
      if (!usedIds.contains(e.id)) return e;
      return VaultEntry(
        id: newId(),
        title: e.title,
        categoryKey: e.categoryKey,
        fields: e.fields,
        createdAt: e.createdAt,
        updatedAt: now,
      );
    }

    for (final e in plan.added) {
      final entry = withFreshIdIfTaken(e);
      usedIds.add(entry.id);
      result.add(entry);
    }

    for (final c in plan.conflicts) {
      switch (choice) {
        case ImportConflictChoice.skip:
          break;
        case ImportConflictChoice.replace:
          final i = result.indexWhere((e) => e.id == c.existing.id);
          result[i] = VaultEntry(
            id: c.existing.id,
            title: c.incoming.title,
            categoryKey: c.incoming.categoryKey,
            fields: c.incoming.fields,
            createdAt: c.existing.createdAt,
            updatedAt: now,
          );
        case ImportConflictChoice.keepBoth:
          final copy = VaultEntry(
            id: newId(),
            title: '${c.incoming.title}$keptBothSuffix',
            categoryKey: c.incoming.categoryKey,
            fields: c.incoming.fields,
            createdAt: c.incoming.createdAt,
            updatedAt: now,
          );
          usedIds.add(copy.id);
          result.add(copy);
      }
    }
    return result;
  }
}
