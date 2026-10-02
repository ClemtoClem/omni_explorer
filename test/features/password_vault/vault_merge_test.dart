import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/features/password_vault/models/vault_entry.dart';
import 'package:omni_explorer/features/password_vault/services/vault_merge.dart';

void main() {
  final t0 = DateTime.utc(2026);
  final now = DateTime.utc(2026, 9, 25);
  var counter = 0;
  String newId() => 'new-${counter++}';

  VaultEntry e(String id, String title,
          {String user = '', String pw = 'pw', String url = ''}) =>
      VaultEntry(
          id: id,
          title: title,
          fields: {'username': user, 'password': pw, 'url': url},
          createdAt: t0,
          updatedAt: t0);

  final existing = [
    e('1', 'Banque', user: 'moi', pw: 'a'),
    e('2', 'Mail', user: 'moi@x', pw: 'b', url: 'mail.example'),
  ];

  test('classe nouveaux, identiques et conflits', () {
    final plan = VaultMerge.plan(existing, [
      e('1', 'Banque', user: 'moi', pw: 'a'), // même id, identique
      e('zz', 'MAIL',
          user: 'moi@x',
          pw: 'b',
          url:
              'Mail.Example'), // même compte, mdp identique mais titre différent
      e('2', 'Mail',
          user: 'moi@x',
          pw: 'changé',
          url: 'mail.example'), // conflit (même id)
      e('9', 'Forum', user: 'pseudo'), // nouveau
      e('9', 'Forum', user: 'pseudo'), // doublon dans l'export
    ]);

    expect(plan.added.map((x) => x.title), ['Forum']);
    expect(plan.identical.map((x) => x.id), ['1']);
    expect(plan.conflicts.map((c) => c.existing.id), ['2', '2']);
  });

  test('même compte (titre, identifiant, adresse) sans même identifiant', () {
    final plan = VaultMerge.plan(
        existing, [e('autre-id', 'Banque', user: 'moi', pw: 'nouveau')]);
    expect(plan.conflicts.single.existing.id, '1');
  });

  group('application', () {
    final plan = VaultMerge.plan(existing, [
      e('2', 'Mail', user: 'moi@x', pw: 'changé', url: 'mail.example'),
      e('9', 'Forum', user: 'pseudo'),
    ]);

    test('garder les deux', () {
      final r = VaultMerge.apply(existing, plan, ImportConflictChoice.keepBoth,
          newId: newId, now: now);
      expect(r.length, 4);
      expect(r.firstWhere((x) => x.id == '2').password, 'b');
      final copy =
          r.firstWhere((x) => x.title == 'Mail${VaultMerge.keptBothSuffix}');
      expect(copy.password, 'changé');
      expect(copy.id, isNot('2'));
    });

    test('remplacer : l\'entrée existante garde son identifiant', () {
      final r = VaultMerge.apply(existing, plan, ImportConflictChoice.replace,
          newId: newId, now: now);
      expect(r.length, 3);
      final mail = r.firstWhere((x) => x.id == '2');
      expect(mail.password, 'changé');
      expect(mail.updatedAt, now);
    });

    test(
        'remplacer depuis un autre coffre (autre identifiant) : '
        'l\'identifiant existant est conservé, sans doublon', () {
      final fromOther = VaultMerge.plan(existing,
          [e('autre-coffre-42', 'Banque', user: 'moi', pw: 'nouveau')]);
      final r = VaultMerge.apply(
          existing, fromOther, ImportConflictChoice.replace,
          newId: newId, now: now);
      expect(r.length, existing.length);
      expect(r.firstWhere((x) => x.title == 'Banque').id, '1');
      expect(r.firstWhere((x) => x.title == 'Banque').password, 'nouveau');
    });

    test('ignorer', () {
      final r = VaultMerge.apply(existing, plan, ImportConflictChoice.skip,
          newId: newId, now: now);
      expect(r.length, 3);
      expect(r.firstWhere((x) => x.id == '2').password, 'b');
    });

    test('identifiants toujours uniques', () {
      for (final choice in ImportConflictChoice.values) {
        final r =
            VaultMerge.apply(existing, plan, choice, newId: newId, now: now);
        expect(r.map((x) => x.id).toSet().length, r.length, reason: '$choice');
      }
    });
  });
}
