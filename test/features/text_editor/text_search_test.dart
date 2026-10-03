/// Recherche / remplacement, opérations sur les lignes, palette de
/// commandes et recherche dans le projet (logique, sans interface).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/text_editor/services/line_operations.dart';
import 'package:omni_explorer/features/text_editor/services/project_search.dart';
import 'package:omni_explorer/features/text_editor/services/text_search.dart';
import 'package:omni_explorer/features/text_editor/widgets/command_palette.dart';

void main() {
  group('TextSearch', () {
    List<int> starts(String text, TextSearchQuery q) =>
        TextSearch.findAll(text, q).map((m) => m.start).toList();

    test('casse ignorée par défaut, respectée sur demande', () {
      const text = 'Foo foo FOO';
      expect(starts(text, const TextSearchQuery('foo')), [0, 4, 8]);
      expect(
          starts(text, const TextSearchQuery('foo', caseSensitive: true)), [4]);
    });

    test('mot entier, y compris autour de lettres accentuées', () {
      const text = 'été étés bété été_x été';
      expect(starts(text, const TextSearchQuery('été', wholeWord: true)),
          [0, 20]);
    });

    test('caractères spéciaux littéraux hors mode expression', () {
      const text = 'a-b /x/ #1 (y) a.b axb c++ ';
      for (final pat in ['a-b', '/x/', '#1', '(y)', 'a.b', 'c++', ' ']) {
        expect(TextSearch.findAll(text, TextSearchQuery(pat)), isNotEmpty,
            reason: pat);
        expect(
            TextSearch.findAll(
                text, TextSearchQuery(pat, wholeWord: pat.trim().isNotEmpty)),
            isA<List<TextMatch>>(),
            reason: '$pat (mot entier)');
      }
      expect(starts(text, const TextSearchQuery('a.b')), [15]);
    });

    test('expression régulière, et motif invalide signalé', () {
      expect(starts('x1 y22 z', const TextSearchQuery(r'\d+', regex: true)),
          [1, 4]);
      const bad = TextSearchQuery('(', regex: true);
      expect(bad.error, isNotNull);
      expect(TextSearch.findAll('(', bad), isEmpty);
    });

    test('correspondances vides ignorées', () {
      expect(TextSearch.findAll('a\nb', const TextSearchQuery('^', regex: true)),
          isEmpty);
    });

    test('remplacement avec groupes', () {
      const q = TextSearchQuery(r'(\w+)@(?<dom>\w+)', regex: true);
      final (out, n) =
          TextSearch.replaceAll('ana@x, bob@y', q, r'${dom}:$1 $$');
      expect(out, r'x:ana $, y:bob $');
      expect(n, 2);
    });

    test('remplacement littéral : « \$1 » reste tel quel', () {
      final (out, n) = TextSearch.replaceAll(
          'a.a', const TextSearchQuery('.'), r'$1');
      expect(out, r'a$1a');
      expect(n, 1);
    });

    test('occurrence à partir d\'un décalage, avec retour au début', () {
      const ms = [TextMatch(2, 3), TextMatch(8, 9)];
      expect(TextSearch.indexAtOrAfter(ms, 0), 0);
      expect(TextSearch.indexAtOrAfter(ms, 3), 1);
      expect(TextSearch.indexAtOrAfter(ms, 9), 0);
      expect(TextSearch.indexAtOrAfter(const [], 0), -1);
    });
  });

  group('LineOperations', () {
    const text = 'un\ndeux\ntrois';

    test('dupliquer : la sélection passe sur la copie', () {
      expect(LineOperations.duplicate(text, 4, 4),
          const LineEdit('un\ndeux\ndeux\ntrois', 9, 9));
      // Dernière ligne, sans fin de ligne finale.
      expect(LineOperations.duplicate(text, 13, 13),
          const LineEdit('un\ndeux\ntrois\ntrois', 19, 19));
    });

    test('déplacer vers le haut et le bas, bornes comprises', () {
      expect(LineOperations.move(text, 4, 4, up: true),
          const LineEdit('deux\nun\ntrois', 1, 1));
      expect(LineOperations.move(text, 4, 4, up: false),
          const LineEdit('un\ntrois\ndeux', 10, 10));
      expect(LineOperations.move(text, 0, 0, up: true).text, text);
      expect(LineOperations.move(text, 10, 10, up: false).text, text);
    });

    test('une sélection qui finit en début de ligne exclut cette ligne', () {
      // « un\n » sélectionné entièrement : seule la ligne 1 bouge.
      expect(LineOperations.move(text, 0, 3, up: false),
          const LineEdit('deux\nun\ntrois', 5, 8));
    });

    test('supprimer', () {
      expect(LineOperations.delete(text, 4, 4),
          const LineEdit('un\ntrois', 3, 3));
      expect(LineOperations.delete(text, 10, 10),
          const LineEdit('un\ndeux', 3, 3));
      expect(LineOperations.delete('seule', 2, 2), const LineEdit('', 0, 0));
    });

    test('commenter puis décommenter : retour au texte d\'origine', () {
      const code = '  a();\n\n    b();\n  c();';
      const slash = LineComment('//');
      final on = LineOperations.toggleComment(code, 0, code.length, slash);
      expect(on.text, '  // a();\n\n  //   b();\n  // c();');
      final off = LineOperations.toggleComment(
          on.text, on.selectionStart, on.selectionEnd, slash);
      expect(off.text, code);
    });

    test('commentaire de ligne : le curseur suit le texte', () {
      // Curseur après « x » sur « x = 1 ».
      final on =
          LineOperations.toggleComment('x = 1', 1, 1, const LineComment('#'));
      expect(on, const LineEdit('# x = 1', 3, 3));
      final off = LineOperations.toggleComment(
          on.text, 3, 3, const LineComment('#'));
      expect(off, const LineEdit('x = 1', 1, 1));
    });

    test('commentaire avec fin (HTML)', () {
      const html = LineComment('<!--', '-->');
      final on = LineOperations.toggleComment('<p>a</p>', 0, 0, html);
      expect(on.text, '<!-- <p>a</p> -->');
      expect(LineOperations.toggleComment(on.text, 0, 0, html).text,
          '<p>a</p>');
    });

    test('syntaxe par langage', () {
      expect(LineComment.forLanguage('python')!.prefix, '#');
      expect(LineComment.forLanguage('dart')!.prefix, '//');
      expect(LineComment.forLanguage('sql')!.prefix, '--');
      expect(LineComment.forLanguage('text'), isNull);
      expect(LineComment.forLanguage(null), isNull);
    });
  });

  group('palette', () {
    test('saisie approximative et classement', () {
      expect(paletteScore('Aller à la ligne', 'all'), isNotNull);
      expect(paletteScore('Aller à la ligne', 'alg'), isNotNull);
      expect(paletteScore('Aller à la ligne', 'xyz'), isNull);
      // La requête contiguë l'emporte sur des lettres éparses.
      expect(paletteScore('Sauvegarder', 'sauv')!,
          greaterThan(paletteScore('Supprimer les lignes au-dessus', 'sauv') ?? -1));
    });
  });

  group('ProjectSearch', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('project_search_test_');
      File(p.join(root.path, 'lib', 'a.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {\n  print("TODO un");\n}\n');
      File(p.join(root.path, 'notes.txt'))
          .writeAsBytesSync(latin1.encode('café TODO deux\n'));
      File(p.join(root.path, 'image.bin'))
          .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0x54, 0x4F]);
      File(p.join(root.path, 'build', 'gen.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// TODO exclu');
      File(p.join(root.path, '.git', 'HEAD'))
        ..createSync(recursive: true)
        ..writeAsStringSync('TODO caché');
    });
    tearDown(() => root.delete(recursive: true));

    test('liste les fichiers hors exclus et cachés', () async {
      final files = await ProjectSearch.listFiles(root.path, exclude: ['build']);
      expect(files.map((f) => p.relative(f, from: root.path)),
          ['image.bin', p.join('lib', 'a.dart'), 'notes.txt']);
    });

    test('occurrences : ligne, colonne, extrait ; binaires sautés', () async {
      ProjectSearchSummary? summary;
      final hits = await ProjectSearch.search(
        root.path,
        const TextSearchQuery('todo'),
        exclude: ['build'],
        onDone: (s) => summary = s,
      ).toList();

      final byFile = {
        for (final h in hits) p.relative(h.path, from: root.path): h
      };
      expect(byFile.keys.toSet(), {p.join('lib', 'a.dart'), 'notes.txt'});
      final dart = byFile[p.join('lib', 'a.dart')]!;
      expect((dart.line, dart.column), (2, 10));
      expect(dart.preview.substring(dart.previewStart, dart.previewEnd),
          'TODO');
      expect(byFile['notes.txt']!.preview, 'café TODO deux'); // Latin-1
      expect(summary!.hits, 2);
      expect(summary!.truncated, isFalse);
    });
  });
}
