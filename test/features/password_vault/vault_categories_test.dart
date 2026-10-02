/// Catégories du coffre : migration du schéma 1, sérialisation, recherche,
/// tri par tag ou par catégorie, fusion à l'import.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/features/password_vault/models/vault_entry.dart';
import 'package:omni_explorer/features/password_vault/models/vault_errors.dart';
import 'package:omni_explorer/features/password_vault/services/vault_merge.dart';
import 'package:omni_explorer/features/password_vault/services/vault_sort.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  VaultEntry entry(String id, String tag, VaultCategory c,
          [Map<String, String> fields = const {}]) =>
      VaultEntry(
          id: id,
          title: tag,
          category: c,
          fields: fields,
          createdAt: t0,
          updatedAt: t0);

  /// Aller-retour par le JSON, comme à l'enregistrement du coffre.
  VaultContent roundTrip(VaultContent c) =>
      VaultContent.fromJson(jsonDecode(jsonEncode(c.toJson())));

  group('schéma', () {
    test('un coffre du schéma 1 devient des entrées « Site web »', () {
      final v1 = {
        'schema': 1,
        'entries': [
          {
            'id': 'a',
            'title': 'Forum',
            'username': 'moi',
            'password': 'pw',
            'url': 'https://forum.example',
            'notes': '',
            'createdAt': t0.toIso8601String(),
            'updatedAt': t0.toIso8601String(),
          },
        ],
      };
      final e = VaultContent.fromJson(v1).entries.single;
      expect(e.category, VaultCategory.website);
      expect((e.title, e.username, e.password, e.url),
          ('Forum', 'moi', 'pw', 'https://forum.example'));
      expect(e.fields.containsKey('notes'), isFalse); // vide : non gardé
      expect(VaultContent([e]).toJson()['schema'], 2);
    });

    test('une fiche bancaire complète est conservée à l\'identique', () {
      final bank = entry('b', 'Compte courant', VaultCategory.bank, {
        'bankName': 'Banque X',
        'cardHolder': 'C. Dupont',
        'cardNumber': '4970 1234 5678 9012',
        'cardExpiry': '09/29',
        'cardCvv': '123',
        'cardPin': '0000',
        'iban': 'FR76 3000 6000 0112 3456 7890 189',
        'bic': 'AGRIFRPP',
        'rib': '30006 00001 12345678901 89',
        'onlineLogin': '12345678',
        'onlinePassword': '987654',
      });
      final back = roundTrip(VaultContent([bank])).entries.single;
      expect(back.category, VaultCategory.bank);
      expect(back.sameContent(bank), isTrue);
      expect(back['iban'], 'FR76 3000 6000 0112 3456 7890 189');
    });

    test('une catégorie inconnue (version plus récente) est gardée', () {
      final future = VaultEntry(
          id: 'f',
          title: 'Voiture',
          categoryKey: 'vehicle',
          fields: {'plate': 'AB-123-CD'},
          createdAt: t0,
          updatedAt: t0);
      final back = roundTrip(VaultContent([future])).entries.single;
      expect(back.categoryKey, 'vehicle');
      expect(back.category, VaultCategory.website); // affichage seulement
      expect(back['plate'], 'AB-123-CD');
    });

    test('des champs mal formés sont signalés comme corruption', () {
      final bad = {
        'schema': 2,
        'entries': [
          {
            'id': 'x',
            'title': 'X',
            'category': 'bank',
            'fields': {'iban': 42},
            'createdAt': t0.toIso8601String(),
            'updatedAt': t0.toIso8601String(),
          },
        ],
      };
      expect(() => VaultContent.fromJson(bad),
          throwsA(isA<VaultCorruptedException>()));
    });

    test('chaque catégorie a des clés de champs uniques et un tag', () {
      final keys = VaultCategory.values.map((c) => c.key).toSet();
      expect(keys, hasLength(VaultCategory.values.length));
      for (final c in VaultCategory.values) {
        final fieldKeys = c.fields.map((f) => f.key).toList();
        expect(fieldKeys.toSet(), hasLength(fieldKeys.length), reason: c.key);
        if (c.summary != null) expect(c.field(c.summary!), isNotNull);
        if (c.secret != null) expect(c.field(c.secret!)!.isSecret, isTrue);
      }
    });
  });

  group('recherche', () {
    test('tag, catégorie et champs lisibles ; jamais les secrets', () {
      final bank = entry('b', 'Perso', VaultCategory.bank,
          {'bankName': 'Banque X', 'cardNumber': '4970123456789012'});
      expect(bank.matches('perso'), isTrue);
      expect(bank.matches('banque x'), isTrue);
      expect(bank.matches('BANQUE'), isTrue); // libellé de la catégorie
      expect(bank.matches('4970'), isFalse);

      final msg = entry('m', 'Coffre', VaultCategory.message,
          {'message': 'le code est sous le pot de fleurs'});
      expect(msg.matches('fleurs'), isFalse);
    });
  });

  group('tri', () {
    final entries = [
      entry('1', 'banque', VaultCategory.bank),
      entry('2', 'Écran', VaultCategory.website),
      entry('3', 'Zoo', VaultCategory.website),
      entry('4', 'agenda', VaultCategory.message),
      entry('5', 'Box', VaultCategory.wifi),
    ];
    List<String> tags(VaultSortMode m) =>
        sortVaultEntries(entries, m).map((e) => e.title).toList();

    test('par tag, croissant, sans casse ni accents', () {
      expect(tags(VaultSortMode.tagAscending),
          ['agenda', 'banque', 'Box', 'Écran', 'Zoo']);
    });

    test('par tag, décroissant', () {
      expect(tags(VaultSortMode.tagDescending),
          ['Zoo', 'Écran', 'Box', 'banque', 'agenda']);
    });

    test('par catégorie (A → Z), puis par tag', () {
      final sorted = sortVaultEntries(entries, VaultSortMode.category);
      expect(sorted.map((e) => '${e.category.label}/${e.title}'), [
        'Banque/banque',
        'Message secret/agenda',
        'Réseau Wi-Fi/Box',
        'Site web/Écran',
        'Site web/Zoo',
      ]);
    });

    test('la liste d\'origine n\'est pas modifiée', () {
      sortVaultEntries(entries, VaultSortMode.tagDescending);
      expect(entries.first.title, 'banque');
    });

    test('mode inconnu dans les préférences : tri par tag croissant', () {
      expect(VaultSortMode.byKey('???'), VaultSortMode.tagAscending);
      expect(VaultSortMode.byKey(null), VaultSortMode.tagAscending);
      expect(VaultSortMode.byKey('category'), VaultSortMode.category);
    });
  });

  group('fusion à l\'import', () {
    test('même tag dans deux catégories : pas de correspondance', () {
      final existing = [
        entry('1', 'Orange', VaultCategory.email, {'address': 'a@o.fr'})
      ];
      final incoming = [
        entry('2', 'Orange', VaultCategory.phone, {'phoneNumber': '06'})
      ];
      final plan = VaultMerge.plan(existing, incoming);
      expect(plan.added, hasLength(1));
      expect(plan.conflicts, isEmpty);
    });

    test('un champ propre à la catégorie modifié : conflit, puis remplacé', () {
      final existing = [
        entry('1', 'Box', VaultCategory.wifi,
            {'ssid': 'maison', 'password': 'ancien'})
      ];
      final incoming = [
        entry('9', 'Box', VaultCategory.wifi,
            {'ssid': 'maison', 'password': 'nouveau', 'security': 'WPA3'})
      ];
      final plan = VaultMerge.plan(existing, incoming);
      expect(plan.conflicts, hasLength(1));

      final merged = VaultMerge.apply(
          existing, plan, ImportConflictChoice.replace,
          newId: () => 'n', now: t0);
      final box = merged.single;
      expect((box.id, box['password'], box['security'], box.category),
          ('1', 'nouveau', 'WPA3', VaultCategory.wifi));
    });

    test('contenu identique : doublon ignoré', () {
      final a = entry('1', 'Note', VaultCategory.message, {'message': 'x'});
      final plan = VaultMerge.plan([a], [a]);
      expect(plan.identical, hasLength(1));
    });
  });
}
