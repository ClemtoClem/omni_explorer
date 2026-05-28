# OmniExplorer — Application Android Flutter

Application Android tout-en-un combinant :

## Fonctionnalites

### Explorateur de fichiers
- Navigation complete dans le stockage interne et externe (SD)
- Barre de chemin interactive et editable (style Ubuntu)
  - Bouton remonter (↑), undo (←), redo (→)
  - Chaque segment est un bouton cliquable
  - Double-clic pour editer le chemin manuellement
- Raccourcis vers : Telechargements, Images, Videos, Musique, Documents, Captures
- Filtres par nom et par categorie de fichier
- Tri par nom, date, taille, type
- Vue liste et vue grille
- Icones adaptees au type de fichier
- Affichage de la date de modification et de la taille
- Selection multiple avec actions groupees (copier, deplacer, corbeille, supprimer)
- Gestion de la corbeille (avec restauration et vidage)
- Creation de raccourcis
- Affichage/masquage des fichiers caches

### Lecteur Audio/Video
- Formats audio : MP3, FLAC, WAV, OGG, AAC, M4A, OPUS, WMA, AIFF
- Formats video : MP4, MKV, AVI, MOV, WMV, FLV, WebM, M4V, 3GP
- Spectrometre anime pour les fichiers audio
- Lecture en arriere-plan avec notification
- Gestion des playlists (creation, persistence)
- Controles : play/pause, suivant/precedent, shuffle, repeter
- Barre de progression interactive

### Visionneur d'images
- Formats : JPG, PNG, GIF (anime), WebP (anime), SVG, BMP, HEIC, AVIF
- Zoom pinch-to-zoom (0.5x a 8x)
- Navigation par swipe entre les images du repertoire
- Miniatures en bas pour navigation rapide
- Mode diaporama avec duree configurable (2s, 3s, 5s, 10s)

### Editeur de code
- Coloration syntaxique pour 15+ langages (Python, Dart, JS, TS, HTML, CSS, JSON, YAML, Java, Kotlin, C/C++, C#, Go, Rust, Shell, SQL, Markdown...)
- Architecture modulaire : ajout de nouveaux langages via LanguageRegistry
- Systeme d'onglets multiples
- Mode projet (arbre de fichiers lateral)
- Terminal integre pour l'execution de scripts
- Runner pour Python, Node.js, Bash
- Recherche et remplacement
- Raccourcis clavier

### Visionneur Markdown
- Rendu HTML complet avec flutter_markdown
- Basculement source/rendu
- Liens cliquables

### Visionneur PDF
- Zoom pinch-to-zoom
- Navigation par pages
- Barre de pagination avec slider
- Dialogue "aller a la page"

### Clavier personnalise AZERTY
- Layout AZERTY complet
- Barre superieure : tous les caracteres de programmation
- Touches speciales : Ctrl, Alt, AltGr, Tab, Echap, Suppr, Backspace
- Touches de navigation : fleches, PageUp, PageDown
- Shift / Caps Lock / mode chiffres
- Masquable depuis l'editeur

## Architecture

```sh
lib/
├── core/
│   ├── constants/          # Constantes et enums globaux
│   ├── models/             # Modeles de donnees (FileItem, TrashItem, ShortcutItem)
│   ├── services/           # Services singleton (Settings, Trash)
│   ├── theme/              # AppTheme, AppColors
│   └── utils/              # FileUtils
├── features/
│   ├── file_explorer/      # Explorateur de fichiers
│   ├── media_player/       # Lecteur audio/video
│   ├── image_viewer/       # Visionneur d'images
│   ├── code_editor/        # Editeur de code
│   │   ├── languages/      # LanguageRegistry (modulaire)
│   │   └── widgets/        # TerminalPanel, ProjectTree
│   ├── markdown_viewer/    # Visionneur Markdown
│   └── pdf_viewer/         # Visionneur PDF
├── home/                   # Shell de navigation
└── widgets/
    └── custom_keyboard/    # Clavier AZERTY personnalise
```

## Ajouter un nouveau langage

```dart
LanguageRegistry.instance.register(LanguageDefinition(
  id:          'ruby',
  label:       'Ruby',
  extensions:  ['rb'],
  highlightMode: builtinLanguages['ruby']!,
  icon:        Icons.code_rounded,
  color:       Color(0xFFCC342D),
  runCommand:  'ruby',
));
```

## Configuration Android requise
- Android 8.0+ (API 26+)
- Permissions : READ_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE (< Android 10),
  READ_MEDIA_IMAGES/VIDEO/AUDIO (Android 13+), MANAGE_EXTERNAL_STORAGE

## Dependances principales
- `provider` — State management
- `just_audio` + `just_audio_background` — Lecteur audio
- `video_player` + `chewie` — Lecteur video
- `extended_image` — Visionneur d'images
- `pdfx` — Visionneur PDF
- `flutter_markdown` — Rendu Markdown
- `re_editor` + `re_highlight` — Editeur de code
- `permission_handler` — Gestion des permissions Android
- `path_provider` — Acces aux chemins systeme
- `sqflite` — Base de donnees locale
- `google_fonts` — Jost + Inter + JetBrains Mono
