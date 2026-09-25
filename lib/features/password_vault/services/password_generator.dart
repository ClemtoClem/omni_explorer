/// @file password_generator.dart
/// @brief Générateur de mots de passe aléatoires.
///
/// Source d'aléa : [Random.secure] (générateur cryptographique du système).
/// `nextInt` tire uniformément, sans le biais d'un modulo.

import 'dart:math';

class PasswordGeneratorOptions {
  final int length;
  final bool lowercase;
  final bool uppercase;
  final bool digits;
  final bool symbols;

  /// Retire les caractères faciles à confondre (0/O, 1/l/I…).
  final bool avoidAmbiguous;

  const PasswordGeneratorOptions({
    this.length = 20,
    this.lowercase = true,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
    this.avoidAmbiguous = false,
  });

  static const int minLength = 8;
  static const int maxLength = 128;

  PasswordGeneratorOptions copyWith({
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
    bool? avoidAmbiguous,
  }) =>
      PasswordGeneratorOptions(
        length: length ?? this.length,
        lowercase: lowercase ?? this.lowercase,
        uppercase: uppercase ?? this.uppercase,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
        avoidAmbiguous: avoidAmbiguous ?? this.avoidAmbiguous,
      );
}

class PasswordGenerator {
  final Random _random;

  PasswordGenerator([Random? random]) : _random = random ?? Random.secure();

  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _digits = '0123456789';
  static const String _symbols = r'!#$%&()*+,-./:;<=>?@[]^_{|}~';
  static const String _ambiguous = 'O0oIl1|';

  /// Familles de caractères retenues par [options].
  static List<String> charsets(PasswordGeneratorOptions options) {
    String strip(String s) => options.avoidAmbiguous
        ? s.split('').where((c) => !_ambiguous.contains(c)).join()
        : s;
    return [
      if (options.lowercase) strip(_lower),
      if (options.uppercase) strip(_upper),
      if (options.digits) strip(_digits),
      if (options.symbols) strip(_symbols),
    ];
  }

  /// Entropie (en bits) d'un mot de passe généré avec [options].
  static double entropyBits(PasswordGeneratorOptions options) {
    final pool = charsets(options).fold<int>(0, (n, s) => n + s.length);
    if (pool == 0) return 0;
    return options.length * log(pool) / ln2;
  }

  /// Génère un mot de passe. Au moins un caractère de chaque famille
  /// sélectionnée est présent.
  String generate(PasswordGeneratorOptions options) {
    final sets = charsets(options);
    if (sets.isEmpty) {
      throw ArgumentError('Choisissez au moins un type de caractères.');
    }
    if (options.length < PasswordGeneratorOptions.minLength ||
        options.length > PasswordGeneratorOptions.maxLength ||
        options.length < sets.length) {
      throw ArgumentError('Longueur invalide : ${options.length}.');
    }
    final all = sets.join();
    final chars = <String>[
      for (final s in sets) s[_random.nextInt(s.length)],
      for (var i = sets.length; i < options.length; i++)
        all[_random.nextInt(all.length)],
    ];
    // Mélange de Fisher-Yates : les caractères imposés ne sont pas en tête.
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
    return chars.join();
  }
}
