/// @file editor_open_policy.dart
/// @brief Choix de la représentation d'un fichier à l'ouverture dans
/// l'éditeur, selon sa taille et son contenu, pour ne jamais charger en
/// mémoire un fichier que l'éditeur ne peut pas gérer.
///
/// - Contenu binaire (octet nul, UTF-8 invalide au début) → hexadécimal.
/// - Au-delà de [EditorLimits.textMaxBytes], ou avec une ligne de plus de
///   [EditorLimits.maxLineBytes] → pas d'ouverture en texte : l'utilisateur
///   choisit l'aperçu hexadécimal (lecture partielle) ou annule.
/// - Au-delà de [EditorLimits.highlightMaxBytes] → texte brut, sans
///   coloration syntaxique.
///
/// Mesures (PC, tests de widget) : 8 Mio en lignes de 80 caractères
/// s'ouvrent en 1 à 3 s ; une seule ligne de 256 Kio prend 3 à 4 s et une
/// ligne de 2 Mio plus de 3 min, aussi bien dans le champ texte que dans
/// l'éditeur de code. C'est la longueur de ligne, plus que la taille, qui
/// fige l'affichage (fichiers minifiés, JSON sur une ligne).

import 'dart:convert';
import 'dart:io';

import '../models/editor_view_mode.dart';

class EditorLimits {
  EditorLimits._();

  /// Au-delà, la coloration syntaxique est désactivée (texte brut).
  static const int highlightMaxBytes = 2 * 1024 * 1024;

  /// Au-delà, le fichier n'est pas chargé comme texte : champ de saisie et
  /// éditeur de code deviennent inutilisables, et la mémoire explose.
  static const int textMaxBytes = 10 * 1024 * 1024;

  /// Au-delà, une seule ligne rend l'affichage texte inutilisable.
  static const int maxLineBytes = 32 * 1024;

  /// Octets lus au début du fichier pour détecter un contenu binaire.
  static const int sniffBytes = 8 * 1024;

  /// Analyse des symboles d'un projet (autocomplétion) : fichiers ignorés
  /// au-delà de cette taille, et nombre maximal de fichiers lus.
  static const int symbolScanMaxFileBytes = 512 * 1024;
  static const int symbolScanMaxFiles = 2000;
}

/// Taille et nature d'un fichier, lues sans le charger.
class FileProbe {
  final int size;

  /// Vrai si le début du fichier contient un octet nul ou de l'UTF-8
  /// invalide (images, exécutables, archives, documents Office…).
  final bool looksBinary;

  /// Vrai si une ligne dépasse [EditorLimits.maxLineBytes].
  final bool hasLongLines;

  const FileProbe({
    required this.size,
    required this.looksBinary,
    this.hasLongLines = false,
  });

  /// Lit la taille et au plus [EditorLimits.sniffBytes] octets, puis, pour
  /// un fichier texte chargeable, parcourt le fichier par blocs pour y
  /// chercher une ligne trop longue (arrêt dès qu'elle est trouvée).
  static Future<FileProbe> of(String path) async {
    final raf = await File(path).open();
    try {
      final size = await raf.length();
      final head = await raf.read(EditorLimits.sniffBytes);
      final binary = looksBinaryBytes(head, truncated: size > head.length);
      var longLines = false;
      if (!binary && size <= EditorLimits.textMaxBytes) {
        await raf.setPosition(0);
        var current = 0; // longueur de la ligne en cours, d'un bloc à l'autre
        while (current >= 0) {
          final chunk = await raf.read(64 * 1024);
          if (chunk.isEmpty) break;
          current = _scanLines(chunk, current);
        }
        longLines = current < 0;
      }
      return FileProbe(
          size: size, looksBinary: binary, hasLongLines: longLines);
    } finally {
      await raf.close();
    }
  }

  /// Parcourt [chunk] en poursuivant une ligne déjà longue de [current]
  /// octets. Retourne la longueur de la ligne en cours à la fin du bloc, ou
  /// -1 dès qu'une ligne dépasse [EditorLimits.maxLineBytes].
  static int _scanLines(List<int> chunk, int current) {
    for (final b in chunk) {
      if (b == 0x0A) {
        current = 0;
      } else if (++current > EditorLimits.maxLineBytes) {
        return -1;
      }
    }
    return current;
  }

  /// Nature d'un texte déjà en mémoire (fichier supprimé du disque). Les
  /// longueurs sont comptées en caractères, approximation des octets.
  factory FileProbe.ofText(String text) {
    var longest = 0, current = 0;
    for (final unit in text.codeUnits) {
      if (unit == 0x0A) {
        current = 0;
      } else if (++current > longest) {
        longest = current;
      }
    }
    return FileProbe(
        size: text.length,
        looksBinary: false,
        hasLongLines: longest > EditorLimits.maxLineBytes);
  }

  /// Vrai si [head] n'est pas du texte UTF-8. Avec [truncated], jusqu'à
  /// 3 octets finaux peuvent être un caractère coupé par la lecture partielle.
  static bool looksBinaryBytes(List<int> head, {bool truncated = false}) {
    if (head.contains(0)) return true;
    final maxCut = truncated ? 3 : 0;
    for (var cut = 0; cut <= maxCut && cut <= head.length; cut++) {
      try {
        utf8.decode(head.sublist(0, head.length - cut));
        return false;
      } on FormatException {
        // Essai suivant : un caractère multi-octets a peut-être été coupé.
      }
    }
    return true;
  }
}

/// Pourquoi un fichier n'est pas ouvert comme texte.
enum TextBlock {
  /// Plus de [EditorLimits.textMaxBytes].
  tooLarge,

  /// Une ligne de plus de [EditorLimits.maxLineBytes].
  longLines,
}

/// Décision d'ouverture.
class OpenDecision {
  /// Représentation à utiliser.
  final EditorViewMode mode;

  /// Message à montrer à l'utilisateur (mode différent de celui attendu).
  final String? notice;

  /// Raison pour laquelle le texte est exclu : demander avant d'ouvrir en
  /// hexadécimal. `null` si l'ouverture se fait directement.
  final TextBlock? block;

  bool get needsHexConfirmation => block != null;

  const OpenDecision(this.mode, {this.notice, this.block});
}

class EditorOpenPolicy {
  EditorOpenPolicy._();

  /// Représentation à utiliser pour un fichier de nature [probe], dont
  /// l'extension suggère [detected].
  static OpenDecision decide(FileProbe probe, EditorViewMode detected,
      {bool forceHex = false}) {
    if (forceHex || detected == EditorViewMode.hex) {
      return const OpenDecision(EditorViewMode.hex);
    }
    if (probe.looksBinary) {
      return const OpenDecision(EditorViewMode.hex,
          notice: 'Contenu binaire : fichier affiché en hexadécimal.');
    }
    if (probe.size > EditorLimits.textMaxBytes) {
      return const OpenDecision(EditorViewMode.hex, block: TextBlock.tooLarge);
    }
    if (probe.hasLongLines) {
      return const OpenDecision(EditorViewMode.hex, block: TextBlock.longLines);
    }
    final highlighted =
        detected == EditorViewMode.code || detected == EditorViewMode.markdown;
    if (highlighted && probe.size > EditorLimits.highlightMaxBytes) {
      return const OpenDecision(EditorViewMode.text,
          notice: 'Fichier volumineux : ouvert en texte brut, sans '
              'coloration syntaxique.');
    }
    return OpenDecision(detected);
  }

  /// Raison de refuser de passer le fichier [probe] en [mode], ou `null` si
  /// c'est possible.
  static String? refuseSwitch(FileProbe probe, EditorViewMode mode) {
    final size = probe.size;
    if (mode != EditorViewMode.hex && probe.hasLongLines) {
      return 'Ce fichier contient une ligne de plus de '
          '${EditorLimits.maxLineBytes ~/ 1024} Kio : l\'affichage en texte '
          'figerait l\'application.';
    }
    switch (mode) {
      case EditorViewMode.hex:
        return null; // lecture partielle au-delà de 32 Mio
      case EditorViewMode.code:
      case EditorViewMode.markdown:
        if (size > EditorLimits.highlightMaxBytes) {
          return 'Fichier trop volumineux pour la coloration syntaxique '
              '(au-delà de ${EditorLimits.highlightMaxBytes ~/ (1024 * 1024)} '
              'Mo) : restez en texte brut.';
        }
        return null;
      case EditorViewMode.text:
      case EditorViewMode.richText:
        if (size > EditorLimits.textMaxBytes) {
          return 'Fichier trop volumineux pour l\'affichage en texte '
              '(au-delà de ${EditorLimits.textMaxBytes ~/ (1024 * 1024)} Mo).';
        }
        return null;
    }
  }
}
