import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/features/password_vault/services/password_generator.dart';

void main() {
  final gen = PasswordGenerator();

  test('longueur demandée et au moins un caractère de chaque famille', () {
    const options = PasswordGeneratorOptions(length: 12);
    for (var i = 0; i < 200; i++) {
      final pw = gen.generate(options);
      expect(pw.length, 12);
      expect(pw, matches(RegExp('[a-z]')));
      expect(pw, matches(RegExp('[A-Z]')));
      expect(pw, matches(RegExp('[0-9]')));
      expect(pw, matches(RegExp(r'[^a-zA-Z0-9]')));
    }
  });

  test('seulement les familles choisies', () {
    const options =
        PasswordGeneratorOptions(length: 30, uppercase: false, symbols: false);
    for (var i = 0; i < 100; i++) {
      expect(gen.generate(options), matches(RegExp(r'^[a-z0-9]{30}$')));
    }
  });

  test('caractères ambigus exclus', () {
    const options = PasswordGeneratorOptions(length: 64, avoidAmbiguous: true);
    for (var i = 0; i < 100; i++) {
      expect(gen.generate(options), isNot(matches(RegExp('[O0oIl1|]'))));
    }
  });

  test('aucune répétition sur 1000 tirages', () {
    const options = PasswordGeneratorOptions(length: 16);
    final seen = {for (var i = 0; i < 1000; i++) gen.generate(options)};
    expect(seen.length, 1000);
  });

  test('options invalides refusées', () {
    expect(
        () => gen.generate(const PasswordGeneratorOptions(
            lowercase: false, uppercase: false, digits: false, symbols: false)),
        throwsArgumentError);
    expect(() => gen.generate(const PasswordGeneratorOptions(length: 4)),
        throwsArgumentError);
  });

  test('entropie', () {
    // 20 caractères parmi 26 minuscules : 20 × log2(26) ≈ 94 bits.
    final bits = PasswordGenerator.entropyBits(const PasswordGeneratorOptions(
        uppercase: false, digits: false, symbols: false));
    expect(bits, closeTo(94.0, 0.1));
  });
}
