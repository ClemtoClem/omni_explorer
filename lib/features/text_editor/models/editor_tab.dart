/// @file editor_tab.dart
/// @brief Onglet de l'éditeur unifié : fichier, mode d'affichage, contrôleurs
/// du mode courant, encodage et état hexadécimal.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../languages/language_registry.dart';
import '../services/editor_encoding.dart';
import '../services/editor_intelligence.dart';
import 'editor_view_mode.dart';
import 'rich_text_controller.dart';

class EditorTab {
  final String path;
  String content;
  bool isDirty = false;
  bool isReadOnly;
  EditorViewMode viewMode;
  LanguageDefinition? lang;

  /// Encodage de lecture et d'écriture du fichier (modes texte).
  EditorEncoding encoding = EditorEncoding.utf8;

  /// Date et taille du fichier quand il a été lu ou écrit : un brouillon
  /// les compare pour savoir si le fichier a changé ailleurs depuis.
  DateTime? diskModified;
  int? diskSize;

  CodeLineEditingController? codeCtrl;
  TextEditingController? textCtrl;
  RichTextController? richCtrl;
  EditorIntelligence? intel;

  bool showMdPreview;

  // État hexadécimal
  Uint8List? bytes;
  int hexSelectedOffset;
  bool hexModified;

  /// Taille du fichier sur le disque au chargement des octets.
  int hexFileLength;
  TextEditingController? hexInputCtrl;
  FocusNode? hexInputFocus;
  ScrollController? hexScrollCtrl;

  EditorTab({
    required this.path,
    required this.content,
    this.isReadOnly = true,
    required this.viewMode,
    this.lang,
  })  : showMdPreview = viewMode == EditorViewMode.markdown,
        hexSelectedOffset = -1,
        hexModified = false,
        hexFileLength = 0 {
    _init();
  }

  String get name => p.basename(path);

  /// Vrai si seul le début du fichier est chargé en hexadécimal : l'onglet
  /// doit alors rester en lecture seule.
  bool get hexTruncated => bytes != null && bytes!.length < hexFileLength;

  void _init() {
    switch (viewMode) {
      case EditorViewMode.code:
      case EditorViewMode.markdown:
        codeCtrl = CodeLineEditingController.fromText(content);
        final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
        final isMarkdown = viewMode == EditorViewMode.markdown;
        intel = EditorIntelligence(
          codeCtrl!,
          bulletContinuation: isMarkdown,
          autoCloseBracket: true,
          autoCloseTag: isMarkdown ||
              const {'html', 'htm', 'xml', 'svg', 'vue', 'xhtml', 'jsx', 'tsx'}
                  .contains(ext),
        );
        break;
      case EditorViewMode.text:
        textCtrl = TextEditingController(text: content);
        break;
      case EditorViewMode.richText:
        richCtrl = RichTextController(text: content);
        break;
      case EditorViewMode.hex:
        hexInputCtrl = TextEditingController();
        hexInputFocus = FocusNode();
        hexScrollCtrl = ScrollController();
        break;
    }
  }

  void switchMode(EditorViewMode newMode) {
    if (newMode == viewMode) return;
    _dispose();
    viewMode = newMode;
    _init();
  }

  /// Remplace le texte en recréant les contrôleurs du mode courant (relecture
  /// avec un autre encodage) : l'historique d'annulation repart de zéro.
  void reload(String text) {
    _dispose();
    content = text;
    _init();
  }

  /// Texte en cours d'édition (le contenu chargé si le mode n'a pas de
  /// contrôleur).
  String get currentText => switch (viewMode) {
        EditorViewMode.code ||
        EditorViewMode.markdown =>
          codeCtrl?.text ?? content,
        EditorViewMode.text => textCtrl?.text ?? content,
        EditorViewMode.richText => richCtrl?.text ?? content,
        EditorViewMode.hex => content,
      };

  void _dispose() {
    intel?.dispose();
    intel = null;
    codeCtrl?.dispose();
    codeCtrl = null;
    textCtrl?.dispose();
    textCtrl = null;
    richCtrl?.dispose();
    richCtrl = null;
    hexInputCtrl?.dispose();
    hexInputCtrl = null;
    hexInputFocus?.dispose();
    hexInputFocus = null;
    hexScrollCtrl?.dispose();
    hexScrollCtrl = null;
  }

  void dispose() => _dispose();
}
