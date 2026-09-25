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

## Build et tests

### Prérequis
- Flutter stable (validé avec Flutter 3.47.5 / Dart 3.13.4).
- **JDK 17 ou 21** pour le build Android : AGP 8.11 et Kotlin 2.2 échouent sous
  JDK 25 (`IllegalArgumentException: 25`).

Le chemin du JDK dépend de la machine, il n'est donc **pas** versionné dans
`android/gradle.properties`. Deux façons de le définir :

```sh
# Option 1 : configuration Gradle de l'utilisateur (tous les projets)
echo "org.gradle.java.home=/usr/lib/jvm/java-21-openjdk-amd64" >> ~/.gradle/gradle.properties

# Option 2 : JDK utilisé par Flutter
flutter config --jdk-dir /usr/lib/jvm/java-21-openjdk-amd64
```

### Commandes

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test   # vérification du format
flutter analyze                                           # analyse statique
flutter test                                              # tests
flutter build apk --debug                                 # APK de debug
```

Avec Flutter installé via **snap**, `flutter` sort en code 255 sans aucun
message si sa sortie est redirigée vers un fichier (`flutter build … > log`).
Passer par un pipe : `flutter build apk --debug 2>&1 | tee build.log`.

## Journal des implémentations

Le diagnostic complet et le plan priorisé (P0 à P3) sont dans
[DIAGNOSTIC.md](DIAGNOSTIC.md). Chaque tâche est développée sur sa propre
branche et documentée ici.

### P0.0 : hygiène du dépôt et base de validation

Branche : `p0/repo-hygiene`

**Problèmes**
- Le travail en cours sur l'éditeur multimédia (30 fichiers modifiés, 7 non
  suivis) n'était pas commité : risque de perte.
- Des fichiers qui n'ont rien à faire dans Git étaient suivis : une ancienne
  copie des sources (`omni_explorer.zip`), les caches Gradle de l'exemple de
  `packages/re_editor`, son `local.properties` (chemin du SDK de la machine) et
  ses `GeneratedPluginRegistrant` générés.
- `android/gradle.properties` imposait `org.gradle.java.home` avec un chemin
  propre à une machine : le build échouait partout ailleurs (autre poste, CI).
- Le seul test était le modèle « Counter » de Flutter, qui échouait.
- Le build APK échouait à l'empaquetage : `fvp` et `ffmpeg-kit` embarquent
  chacun `libc++_shared.so` (« 2 files found with path
  lib/arm64-v8a/libc++_shared.so »). Le message de Flutter qui accuse
  Java 25 est trompeur : Gradle tournait bien sous JDK 21.

**Modifications**
- Travail en cours commité tel quel sur la branche `wip/media-editor`
  (commit `c103d19`), sans correction ; ses défauts connus sont listés dans
  `DIAGNOSTIC.md`.
- `.gitignore` : caches et sorties de build Android à tous les niveaux
  (`**/android/.gradle/`, `**/android/build/`, `**/android/.kotlin/`,
  `local.properties`, `GeneratedPluginRegistrant`), archives à la racine
  (`/*.zip`), et fichiers de secrets (`key.properties`, `*.jks`, `*.keystore`,
  `*.p12`, `.env`).
- Fichiers ci-dessus retirés de l'index Git. Ils restent sur le disque
  (`omni_explorer.zip` n'est pas supprimé).
- `org.gradle.java.home` retiré de `android/gradle.properties` et remplacé par
  un commentaire renvoyant à la section « Build et tests ».
- `android/app/build.gradle.kts` : règle `packaging.jniLibs.pickFirsts` pour
  ne garder qu'une copie de `libc++_shared.so`.
- `test/widget_test.dart` remplacé par `test/app_smoke_test.dart` : l'application
  est construite avec ses vrais providers (SharedPreferences simulées, polices
  sans accès réseau) et doit afficher l'écran d'accueil et ses cartes, sans
  exception.
- `DIAGNOSTIC.md` (audit du projet) ajouté au dépôt.

**Validation**
- `flutter test` : 1 test, réussi.
- `flutter analyze` : 0 erreur, 0 avertissement ; 13 remarques de style
  préexistantes dans `lib/` (inchangées).
- `dart format` : fichiers de test conformes.
- `flutter build apk --debug` : réussi (`app-debug.apk`, 399 Mo : toutes les
  architectures, FFmpeg complet et fvp embarqués ; la taille de l'APK de
  release sera à traiter avec l'audit des dépendances).

**Reste à faire (tâches suivantes)**
- `lib/` n'est pas encore formaté par `dart format` (85 fichiers sur 112
  seraient modifiés) ; ce sera fait
  avec la mise en place de la CI (P2), pour ne pas mélanger un reformatage
  massif avec des corrections.
- La lecture vidéo (`fvp`) et l'export FFmpeg doivent être vérifiés sur un
  appareil, puisqu'ils partagent désormais une seule runtime C++.
- `ffmpeg_kit_flutter_new` embarque la variante **full-gpl** de FFmpeg :
  distribuer l'APK impose alors la licence GPL à l'application. À trancher
  lors de l'audit des dépendances (P2) : accepter la GPL ou passer à une
  variante LGPL.
- Pas encore de hook ni de CI qui bloque un commit de secret : prévu en P2.

### P0.1 : protection contre les archives malveillantes (« Zip Slip »)

Branche : `p0/zip-slip`

**Problème (CRITIQUE)**
L'extraction écrivait chaque entrée à `p.join(destination, nomDeLEntrée)`
sans aucune vérification. Une archive piégée (téléchargée, reçue par
messagerie…) pouvait donc écrire n'importe où, puisque l'application dispose
de l'accès à tous les fichiers :
- `../../DCIM/photo.jpg` remonte au-dessus du dossier choisi ;
- `/storage/emulated/0/…` : avec un chemin absolu, `p.join` ignore
  complètement la destination ;
- un lien symbolique déjà présent dans la destination faisait écrire
  ailleurs.

Défaut connexe : l'écran d'archive affichait « Extrait dans … » même quand
l'extraction venait d'échouer.

**Modifications**
- Nouveau `lib/core/utils/safe_path.dart`, réutilisable (il servira aussi au
  serveur Go Live) :
  - `SafePath.resolveWithin(racine, entrée)` : validation lexicale. Sont
    refusés `..` (même `a/../b`), les chemins absolus, les lettres de lecteur
    (`C:`), les chemins UNC et le caractère nul ; `\` compte comme un
    séparateur.
  - `SafeExtractionRoot` : avant de créer le moindre dossier, résout le chemin
    réel du plus proche dossier existant et vérifie qu'il reste dans la
    racine réelle. Une destination qui est elle-même un lien (`/sdcard`)
    reste acceptée. Refuse d'écrire sur un emplacement occupé par un lien.
- `ArchiveService` (ZIP, JAR, TAR, TAR.GZ/BZ2/XZ, GZ/BZ2/XZ) :
  - **tout ou rien** : tous les noms sont validés avant d'écrire quoi que ce
    soit ; une seule entrée dangereuse fait refuser l'archive entière, avec un
    message qui la nomme ;
  - les liens symboliques contenus dans l'archive ne sont jamais recréés ;
    leur nombre est signalé à l'utilisateur ;
  - 7z et RAR : la liste des entrées est validée avant de lancer l'outil
    externe ;
  - `extractAll` et `extractEntry` renvoient un `ExtractResult` (fichiers
    écrits, liens ignorés) ;
  - `extractEntry` : l'entrée `doc` n'embarque plus aussi `docs/…` (la
    sélection se faisait sur le préfixe de caractères) ;
  - le décodage, qui était dupliqué, est regroupé dans `_decodeMulti`.
- Écran d'archive et menu de l'explorateur : le succès n'est annoncé que si
  l'extraction a réellement réussi.

**Validation**
- 32 nouveaux tests : `test/core/utils/safe_path_test.dart` et
  `test/features/archive/archive_service_test.dart`. Ils utilisent de vraies
  archives piégées (ZIP et TAR.GZ : `..`, `..\`, chemin absolu, lien
  symbolique dans l'archive), de vrais liens symboliques dans la destination,
  et vérifient que rien n'est écrit hors du dossier.
- Test de mutation : avec les refus de `..` et des chemins absolus
  désactivés, les tests ZIP échouent. Les tests TAR.GZ restent verts grâce à
  la seconde couche (vérification du chemin réel sur le disque) : les deux
  protections fonctionnent indépendamment.
- `flutter test` : 33 tests réussis. `flutter analyze` : 0 erreur,
  0 avertissement (12 remarques de style préexistantes).
- `flutter build apk --debug` : réussi.

**Limites et suite**
- 7z et RAR : les liens symboliques contenus dans ces archives ne sont pas
  visibles dans la liste ; on s'appuie alors sur les protections de
  7-Zip/unrar. Ces formats ne fonctionnent de toute façon que sur Linux et
  Windows (outil externe requis).
- Une vérification sur disque suivie d'une écriture laisse une fenêtre de
  concurrence théorique (un autre processus modifiant la destination pendant
  l'extraction) ; elle est acceptable pour une application mobile
  mono-utilisateur.
- Les fichiers déjà présents dans la destination étaient encore écrasés sans
  confirmation. Annoncé ici pour P0.3, cela a finalement été corrigé en P0.5
  (voir cette section).
- Les archives sont toujours chargées entièrement en mémoire : c'est le
  streaming, prévu en P2.

### P0.2 : l'éditeur hexadécimal ne peut plus tronquer ni vider un fichier

Branche : `p0/hex-truncation`

**Problèmes (CRITIQUE)**
- Au-delà de 32 Mo, seuls les 32 premiers Mo étaient chargés, mais la
  sauvegarde réécrivait le fichier avec ce tampon partiel. Modifier un octet
  d'une vidéo de 2 Go la réduisait à 32 Mo. Le fichier était de plus lu **en
  entier** avant d'être coupé, ce qui saturait la mémoire sur les très gros
  fichiers.
- Défaut découvert pendant la tâche : **changer de représentation** (menu
  « Mode d'interprétation ») pouvait détruire le fichier.
  - Hex → Texte/Code : un onglet ouvert en hex n'a pas de texte en mémoire.
    L'éditeur affichait donc un document vide ; taper quelque chose puis
    sauvegarder remplaçait tout le fichier par ce texte.
  - Texte → Hex : les octets n'étaient jamais chargés, la vue restait bloquée
    sur un indicateur de chargement.
- Après une sauvegarde hex, l'onglet restait marqué « modifié ».
- Une erreur de lecture à l'ouverture laissait un onglet bloqué en
  chargement.

**Modifications**
- Nouveau `lib/features/text_editor/services/hex_file_io.dart` :
  - `load` lit au plus 32 Mio depuis le début du fichier
    (`RandomAccessFile`), sans jamais charger le reste ;
  - `save` applique l'invariant **« ne jamais écrire un tampon d'une autre
    taille que le fichier d'origine »** ; il refuse aussi si le fichier a
    changé de taille sur le disque depuis son ouverture (modifié par une
    autre application).
- Éditeur (`unified_editor_screen.dart`) :
  - un fichier tronqué s'ouvre en **lecture seule**, avec un bandeau qui
    l'explique (« Aperçu des 32 Mo premiers sur 2 Go… ») ; demander l'édition
    est refusé avec un message ;
  - vers ou depuis l'hexadécimal, le contenu est **relu depuis le disque** ;
    le changement est refusé tant que des modifications ne sont pas
    sauvegardées ; un fichier qui n'est pas de l'UTF-8 valide reste en hex,
    avec un message clair ;
  - après une sauvegarde hex, l'onglet n'est plus marqué « modifié » ;
  - un onglet dont la lecture échoue n'est plus ouvert.

**Validation**
- `test/features/text_editor/hex_file_io_test.dart` (7 tests) : lecture
  partielle, limite de 32 Mio (fichier creux), sauvegarde refusée pour un
  tampon partiel (fichier laissé intact), refus si le fichier a changé sur
  le disque.
- `test/features/text_editor/unified_editor_hex_test.dart` (5 tests de widget
  sur l'éditeur réel) : hex → texte montre le vrai contenu, fichier binaire
  refusé, texte → hex charge les octets, changement refusé si non
  sauvegardé, gros fichier en lecture seule.
- Contrôle : avec l'ancien code de l'éditeur, les 5 tests de widget
  échouent ; ils reproduisent donc bien les défauts corrigés.
- `flutter test` : 45 tests réussis. `flutter analyze` : 0 erreur,
  0 avertissement (12 remarques de style préexistantes).
- `flutter build apk --debug` : réussi.

**Limites et suite**
- Les fichiers de plus de 32 Mo ne sont pas modifiables en hexadécimal :
  l'éditeur paginé (lecture par blocs, insertion, suppression, annuler et
  rétablir, recherche) est prévu en P2.
- La sauvegarde hex écrit encore directement dans le fichier : l'écriture
  atomique est prévue en P0.5.
- Le contrôle « fichier modifié ailleurs » ne compare que la taille : une
  modification externe de même taille n'est pas détectée.

### P0.3 : opérations sur les fichiers sans écrasement silencieux

Branche : `p0/file-ops`

**Problèmes**
- **Le renommage ne fonctionnait pas** : le bouton « Renommer » fermait
  simplement la boîte de dialogue. La fonction du provider, jamais appelée,
  aurait de plus écrasé sans avertissement un élément portant déjà le nouveau
  nom (`File.rename` remplace la cible sous Linux et Android), et acceptait
  `/` ou `..` dans le nom.
- **Coller** : en cas de conflit, un suffixe « (copie) » était ajouté
  d'office, sans laisser le choix. Les erreurs n'étaient que journalisées :
  l'utilisateur voyait « N élément(s) collé(s) » sans savoir ce qui avait
  échoué. Les liens symboliques étaient suivis (boucle infinie possible,
  copie du contenu de leur cible), et une copie ratée laissait un résultat
  partiel. Couper-coller dans le même dossier renommait l'élément en
  « x (copie) ».
- **Créer** un fichier ou un dossier : aucune vérification du nom (`../x`,
  `a/b`) ; un nom déjà pris n'affichait rien.
- **Supprimer définitivement la sélection** : au premier échec, une
  exception non gérée arrêtait l'opération, sans message.

**Modifications**
- Nouveau `lib/core/services/file_operations_service.dart`, en pur Dart et
  testable, utilisé par l'explorateur :
  - `FileNameValidator` : refuse un nom vide, `.`, `..`, `/`, le caractère
    nul, ou plus de 255 octets ;
  - `rename` : ne remplace jamais un autre élément ; le changement de casse
    seule (`a.txt` → `A.txt`) fonctionne, y compris sur les stockages
    insensibles à la casse ; un lien n'est jamais confondu avec sa cible ;
  - `transfer` (copier / déplacer) : en cas de conflit, un résolveur décide
    (ignorer, garder les deux, remplacer). Le remplacement passe par un nom
    temporaire et n'est jamais destructif : en cas d'échec, l'état d'origine
    est restauré. Un dossier ne peut pas être copié dans lui-même, même via
    un lien. Les liens sont copiés en tant que liens. Une copie ratée est
    retirée. Entre stockages différents, le déplacement se fait par copie
    puis suppression. Chaque élément produit un bilan (réussi, ignoré,
    échec avec sa raison) ;
  - `deletePermanently` : supprime un lien sans toucher à sa cible et
    rapporte chaque échec ;
  - les erreurs système sont traduites (permission refusée, stockage plein,
    lecture seule…).
- `FileExplorerProvider` passe par ce service. `pasteClipboard` renvoie le
  bilan ; après un « couper », seuls les éléments en échec restent dans le
  presse-papiers, pour pouvoir réessayer. `copyTo`, jamais appelé et non
  sécurisé, est supprimé.
- Interface (`file_op_dialogs.dart`) :
  - boîte de conflit : Ignorer / Garder les deux / Remplacer, avec
    « Appliquer aux éléments suivants » ;
  - boîte de renommage : l'erreur s'affiche sous le champ sans fermer la
    boîte, et le nom est présélectionné sans son extension ;
  - bilan après coller ou supprimer : message court, plus le détail des
    échecs sur demande (« Détails ») ;
  - la feuille « Nouveau » affiche l'erreur (nom invalide, élément existant).

**Validation**
- 48 nouveaux tests :
  - `test/core/services/file_operations_service_test.dart` (39 tests, sur
    de vrais dossiers temporaires) : noms refusés, aucun écrasement au
    renommage (fichier comme dossier vide), changement de casse, lien vs
    cible, conflits ignorer / garder / remplacer, copie dans le même dossier,
    dossier dans lui-même (y compris via un lien), liens et boucles de
    liens, copie ratée nettoyée (fichier rendu illisible), bilan d'erreurs,
    suppression d'un lien sans toucher sa cible ;
  - `test/features/file_explorer/file_op_dialogs_test.dart` (5 tests de
    widget) : dialogues de renommage et de conflit ;
  - `test/features/file_explorer/file_explorer_provider_ops_test.dart`
    (4 tests) : presse-papiers après un couper partiellement raté,
    renommage et création refusés.
- Test de mutation : en retirant les vérifications de conflit du service,
  9 tests échouent.
- `flutter test` : 93 tests réussis. `flutter analyze` : 0 erreur,
  0 avertissement (12 remarques de style préexistantes).
- `flutter build apk --debug` : réussi.

**Limites et suite**
- La mise à la corbeille (menu contextuel et sélection) n'attend pas la fin
  de l'opération et annonce un succès même en cas d'échec : c'est traité
  avec la corbeille en P0.4.
- Les longues copies n'affichent pas de progression et ne peuvent pas être
  annulées (P3).
- `core/services/file_service.dart`, l'ancien doublon, n'est plus utilisé
  que par du code mort (`text_editor_screen.dart`) ; il sera supprimé avec
  ce code mort en P2.
- Sur un stockage qui ne gère pas les liens symboliques (carte SD en
  exFAT), copier un lien échoue ; l'échec est rapporté dans le bilan.

### P0.4 : corbeille fiable

Branche : `p0/trash`

**Problèmes**
- **Restauration** : un dossier venant d'un autre stockage (carte SD) n'était
  pas restauré, mais disparaissait quand même de la liste. Il devenait
  orphelin et invisible. Restaurer écrasait sans avertissement un fichier
  recréé entre-temps au même emplacement.
- **Index des chemins d'origine** : écrit directement (non atomique), et
  ignoré en silence s'il était illisible. Si l'application était tuée pendant
  l'écriture, les chemins d'origine de *tous* les éléments étaient perdus :
  les fichiers restaient dans la corbeille, invisibles, sans possibilité de
  les restaurer ni de les supprimer.
- **Mettre à la corbeille un dossier qui la contient** (par exemple
  `Android/`, puisque la corbeille est dans `Android/data/…`) : le repli
  « copie » copiait le dossier dans son propre descendant, sans fin.
- **Repli « copie puis suppression »** : il se déclenchait pour n'importe
  quel échec de déplacement, y compris « permission refusée ». On obtenait
  une copie dans la corbeille, un original impossible à supprimer, puis un
  orphelin.
- **Interface** : mettre à la corbeille, restaurer, supprimer et vider
  n'attendaient pas la fin de l'opération et n'affichaient jamais d'erreur.
  Le succès était annoncé d'office. « Vider » dans la feuille de la corbeille
  supprimait tout sans confirmation.

**Modifications**
- `TrashService`, réécrit en gardant la même API :
  - l'index est écrit **avant** le déplacement et mis à jour **après** la
    restauration : une interruption ne fait jamais perdre un chemin
    d'origine ;
  - l'index est écrit de façon atomique (nouveau
    `lib/core/utils/atomic_write.dart`, réutilisé en P0.5) ; un index
    illisible est mis de côté (`.corrupt-…`), jamais écrasé ;
  - au chargement, l'index est **réconcilié** avec le contenu réel : les
    entrées dont le fichier a disparu sont retirées, et les fichiers absents
    de l'index sont listés comme « origine inconnue » (supprimables, non
    restaurables automatiquement) ;
  - `restore` ne remplace jamais un élément sans décision : même boîte de
    conflit que l'explorateur, et sans choix, les deux sont gardés. En cas
    d'échec, l'élément reste dans la corbeille. Le dossier parent est recréé
    si besoin ;
  - refus clair de mettre à la corbeille un élément absent, un élément déjà
    dans la corbeille, ou un dossier qui la contient ;
  - `moveAllToTrash` et `emptyTrash` renvoient un bilan par élément ; les
    liens sont déplacés et supprimés en tant que liens.
- `FileOperationsService` :
  - nouvelle méthode publique `relocate` (déplacement ou copie vers un chemin
    exact, avec conflits), utilisée par la corbeille ;
  - le repli « copie puis suppression » n'a lieu **que** lors d'un changement
    de stockage (`EXDEV`) ; toute autre erreur est remontée sans rien
    copier ;
  - si l'original ne peut pas être supprimé après une copie complète,
    `PartialMoveException` le signale et **la copie est conservée** :
    l'original a pu être partiellement supprimé, la copie est alors le seul
    exemplaire complet.
- Interface :
  - le menu contextuel, la sélection et les paramètres attendent la fin de
    l'opération et affichent le bilan ou l'erreur ;
  - dans la feuille de la corbeille, les échecs s'affichent dans une boîte
    de dialogue (un message éphémère resterait caché derrière la feuille) ;
    une restauration sous un autre nom est signalée ; « Vider » demande
    confirmation ;
  - chaque élément affiche son dossier d'origine.

**Validation**
- 22 nouveaux tests :
  - `test/core/services/trash_service_test.dart` (20 tests, sur de vrais
    dossiers) : restauration de fichiers et de dossiers, parent recréé,
    aucun écrasement, conflits ignorer et remplacer, échecs (permissions)
    qui laissent l'élément en place, liens, refus (corbeille dans le
    dossier, élément déjà à la corbeille), redémarrage, entrées fantômes,
    orphelins, index corrompu mis de côté, écriture atomique ;
  - 2 tests ajoutés au service : « permission refusée » ne copie rien, et
    un **vrai déplacement entre deux systèmes de fichiers** (le disque et le
    tmpfs `/dev/shm`). Ce test est ignoré automatiquement si aucun second
    système de fichiers n'est disponible.
- Tests de mutation : rétablir le repli « copie » pour toute erreur, faire
  remplacer systématiquement lors d'une restauration, ou désactiver la
  réconciliation des orphelins : chacun de ces sabotages fait échouer des
  tests.
- `flutter test` : 115 tests réussis. `flutter analyze` : 0 erreur,
  0 avertissement (12 remarques de style préexistantes).
- `flutter build apk --debug` : réussi.

**Limites et suite**
- La corbeille est dans le dossier privé de l'application sur le stockage
  interne (`Android/data/…`) :
  - **désinstaller l'application vide la corbeille** ;
  - mettre à la corbeille un élément d'une carte SD le copie sur le
    stockage interne (lent pour les gros dossiers).

  Une corbeille par stockage serait préférable ; à décider avec l'audit
  Android (P2).
- La taille affichée d'un dossier mis à la corbeille est 0 (le calcul
  récursif n'est pas fait).
- Les dialogues de la corbeille ne sont pas couverts par des tests de widget
  (la logique l'est par les tests du service).
- Les éléments orphelins ne peuvent pas être restaurés vers un dossier
  choisi.

### P0.5 : écritures atomiques et plus aucun écrasement silencieux

Branche : `p0/atomic-writes`

**Problèmes**
- **Éditeur** (texte, code, Markdown, texte enrichi et son fichier `.fmt`,
  hexadécimal) et **réglages d'espace de travail** : sauvegarde directe dans
  le fichier. Si l'application était tuée ou le stockage plein pendant
  l'écriture, le fichier restait **tronqué**.
- **Archives** :
  - changer ou retirer le mot de passe **supprimait l'archive d'origine
    avant** de mettre la nouvelle en place : une interruption faisait perdre
    l'archive. Le nom temporaire fixe `x.zip.tmp` écrasait en plus un
    éventuel fichier de ce nom ;
  - ajouter ou retirer des fichiers d'un ZIP réécrivait l'archive
    directement ;
  - si l'encodage échouait, rien n'était écrit, sans aucune erreur.
- **Extraction** : un fichier déjà présent dans la destination était
  **écrasé sans rien demander**, et 7z/RAR utilisaient `-y` (tout écraser).
  La section P0.1 annonçait cette correction pour P0.3, mais elle n'y avait
  pas été faite.
- **Création d'archive** : une archive du même nom était écrasée (ZIP,
  TAR.GZ). Avec 7z (et le ZIP chiffré, qui passe par 7z), `7z a` **ajoutait**
  les fichiers à l'archive existante, ce qui mélangeait deux contenus. Le
  nom saisi n'était pas validé.

**Modifications**
- `lib/core/utils/atomic_write.dart` (créé en P0.4) : écriture dans un
  temporaire du même dossier, vidage sur disque (`flush`), puis renommage
  atomique. Il préserve désormais :
  - les **permissions** : un script exécutable ou un fichier privé les
    garde. Vérifié : `File.copy` conserve les permissions, le temporaire
    n'est donc recréé par copie que lorsqu'elles diffèrent ;
  - les **liens symboliques** : on écrit dans la cible du lien (chaînes
    comprises), et le lien reste un lien ;
  - si le dossier interdit de créer le temporaire alors que le fichier est
    modifiable (cas rare), l'écriture se fait directement dans le fichier,
    comme avant, plutôt que d'empêcher la sauvegarde.
- Éditeur (texte, `.fmt`, hex) et réglages d'espace de travail : sauvegarde
  via `AtomicWrite`.
- `ArchiveService` :
  - extraction : en cas de conflit, la même boîte de dialogue que dans
    l'explorateur (Ignorer / Garder les deux / Remplacer) ; sans choix, les
    deux sont gardés ; un dossier n'est jamais remplacé par un fichier ;
    chaque fichier est écrit de façon atomique ; 7z utilise `-aou` et unrar
    `-or` (renommage automatique) ; le bilan (`ExtractResult.notes`) indique
    les fichiers renommés ou ignorés ;
  - création : refus d'écraser ou de compléter une archive existante ; le
    nom saisi est validé ; les archives produites par 7z sont écrites sous un
    nom temporaire puis renommées ;
  - modification ZIP et mot de passe : le nouveau fichier est produit à part,
    puis remplace l'original **d'un coup**, sans suppression préalable ;
  - un échec d'encodage lève une erreur.
- Les dialogues d'opérations sur les fichiers (conflit, renommage, bilan)
  sont déplacés de `features/file_explorer/widgets/` vers `lib/core/widgets/`
  : ils servent désormais à l'explorateur, aux paramètres et aux archives.

**Validation**
- 20 nouveaux tests :
  - `test/core/utils/atomic_write_test.dart` (9 tests) : création,
    remplacement, permissions 750 et 600, lien et chaîne de liens, cycle de
    liens, échec du renommage (cible intacte, aucun temporaire), dossier non
    modifiable ;
  - `test/features/text_editor/unified_editor_save_test.dart` (3 tests de
    widget sur l'éditeur réel) : sauvegarde sans temporaire, fichier ouvert
    via un lien qui reste un lien, permissions conservées ;
  - `test/features/archive/archive_service_test.dart` (8 tests ajoutés) :
    conflits à l'extraction (garder les deux par défaut, ignorer, remplacer,
    dossier jamais remplacé, `.gz`), refus d'écraser à la création,
    création / ajout / retrait ZIP sans temporaire restant.
- Tests de mutation : liens non résolus, permissions non conservées,
  remplacement par défaut à l'extraction, écrasement autorisé à la
  création : chacun de ces sabotages fait échouer des tests.
- Les attentes des tests de l'éditeur reposent désormais sur une condition
  (onglet ouvert, sauvegarde terminée) plutôt que sur une durée fixe. Un
  échec isolé était apparu une fois pendant les tests de mutation, sans que
  je puisse le reproduire ensuite ; la durée fixe, dépendante de la charge,
  en était la cause la plus probable.
- `flutter test` : 135 tests réussis (deux exécutions complètes).
  `flutter analyze` : 0 erreur, 0 avertissement (12 remarques de style
  préexistantes). `flutter build apk --debug` : réussi.

**Limites et suite**
- L'atomicité de la sauvegarde **dans l'éditeur** est vérifiée par les tests
  d'`AtomicWrite` et par relecture, mais pas de bout en bout : simuler un
  stockage plein ou un arrêt brutal en pleine écriture n'est pas faisable
  ici.
- 7z et RAR ne sont pas installés sur la machine de développement : les
  options `-aou` et `-or` et la création via 7z ne sont pas testées.
- Les autres liens physiques (« hard links ») vers un fichier gardent
  l'ancien contenu après une sauvegarde, et le propriétaire du fichier n'est
  pas conservé.
- **Défaut découvert, à traiter en P1.2 (éditeur de code)** : à chaque
  ouverture d'un onglet de code, `CodeEditor.initState` déclenche une
  notification du contrôleur, et l'écouteur d'autocomplétion appelle alors
  `setState` pendant la construction de l'écran. En debug, cela produit une
  erreur rouge (« setState() called during build ») ; en release, l'écran
  est reconstruit inutilement.

### P0.6 : ouverture des gros fichiers sans plantage ni blocage

Branche : `p0/open-size-limits`

**Problèmes**
- L'éditeur lisait tout fichier texte en entier (`readAsString`), **sans
  limite** : ouvrir un journal de 2 Go faisait planter l'application par
  manque de mémoire.
- Les fichiers de catégorie « binaire » (`.bin`, `.dat`…) partaient dans
  l'éditeur texte, où la lecture échouait sur de l'UTF-8 invalide avec un
  message technique. Les `.docx` et `.odt`, qui sont des archives ZIP,
  étaient traités comme du « texte enrichi ».
- L'analyse des symboles d'un projet (autocomplétion) lisait **tous** les
  fichiers de code, quelle que soit leur taille ou leur nombre.
- **Constat en cours de tâche, grâce à des mesures** : ce n'est pas tant la
  taille qui fige l'affichage que la **longueur de ligne**. Mesures sur PC
  (tests de widget ; un téléphone sera plusieurs fois plus lent) :

  | Contenu | Champ texte | Éditeur de code |
  |---|---|---|
  | 2 Mio en lignes de 80 caractères | 0,7 s | 0,3 s |
  | 8 Mio en lignes de 80 caractères | 1,1 s | 2,9 s |
  | une seule ligne de 64 Kio | 0,5 s | — |
  | une seule ligne de 256 Kio | 3,2 s | 3,9 s |
  | une seule ligne de 2 Mio | > 3 min | 6 min 35 s |

  Un JavaScript minifié ou un JSON d'une seule ligne figeait donc
  l'application, même de taille modeste. Un premier plan basé uniquement
  sur la taille laissait passer exactement ce cas.

**Modifications**
- Nouveau `lib/features/text_editor/services/editor_open_policy.dart` :
  - `FileProbe` lit la taille et les 8 premiers Kio (un octet nul ou de
    l'UTF-8 invalide signalent un contenu binaire ; un caractère coupé par la
    lecture partielle n'est pas compté comme invalide). Pour un fichier texte
    de 10 Mio au plus, il parcourt ensuite le fichier par blocs de 64 Kio à
    la recherche d'une ligne de plus de 32 Kio, en s'arrêtant dès qu'il la
    trouve. **Le fichier n'est jamais chargé en entier** ;
  - `EditorOpenPolicy.decide` :
    - binaire → hexadécimal, avec un message ;
    - plus de 10 Mio, ou une ligne de plus de 32 Kio → dialogue « Fichier
      volumineux » qui en explique la raison et propose l'aperçu hexadécimal
      (lecture partielle, en lecture seule au-delà de 32 Mio) ou l'annulation ;
    - code ou Markdown de plus de 2 Mio → texte brut, sans coloration
      syntaxique, avec un message ;
  - `EditorOpenPolicy.refuseSwitch` applique les mêmes limites au changement
    de mode (par exemple, passer en « Code » un fichier de 3 Mio, ou en texte
    un fichier à lignes géantes, est refusé avec une explication).
- Éditeur :
  - chaque ouverture passe par cette politique ;
  - le changement de mode sonde le fichier sur le disque, et se rabat sur le
    texte en mémoire si le fichier a été supprimé ailleurs (entre modes
    texte uniquement) ;
  - l'analyse des symboles ignore les fichiers de plus de 512 Kio et
    s'arrête après 2 000 fichiers.
- `EditorViewMode` est déplacé dans `models/editor_view_mode.dart` (et
  réexporté par l'écran), pour que la politique soit testable sans l'écran de
  2 100 lignes.

**Validation**
- 24 nouveaux tests :
  - `test/features/text_editor/editor_open_policy_test.dart` (17 tests) :
    détection du binaire (UTF-8 accentué, Latin-1, caractère coupé), sonde
    d'un fichier creux de 3 Gio sans le lire, ligne longue à cheval sur deux
    blocs de lecture, lignes juste sous la limite, décisions et refus ;
  - `test/features/text_editor/unified_editor_open_test.dart` (7 tests de
    widget sur l'éditeur réel) : binaire et `.docx` en hex, dialogue
    au-delà de 10 Mio (Annuler, Hexadécimal), code de plus de 2 Mio en texte
    brut avec passage en « Code » refusé, fichier minifié, hex → texte
    refusé au-delà de 10 Mio.
- Tests de mutation : sans la détection du binaire, des lignes longues, de la
  limite de taille, ou du report de longueur de ligne d'un bloc à l'autre,
  des tests échouent à chaque fois.
- `flutter test` : 159 tests réussis (deux exécutions complètes).
  `flutter analyze` : 0 erreur, 0 avertissement (12 remarques de style
  préexistantes). `flutter build apk --debug` : réussi.

**Limites et suite**
- Les fichiers texte en **Latin-1** ou en **UTF-16** sont vus comme binaires
  et s'ouvrent en hexadécimal (auparavant, ils ne s'ouvraient pas du tout).
  La détection d'encodage est prévue avec l'éditeur de code (P1.2).
- Un fichier à lignes géantes ne peut être vu qu'en hexadécimal. Une
  visionneuse texte en lecture seule, qui découpe les lignes pour
  l'affichage, serait plus utile (P2).
- Les seuils (10 Mio, 2 Mio, 32 Kio) viennent de mesures sur PC ; ils
  seront à ajuster après essai sur un téléphone.
- Les messages (SnackBar) s'affichent l'un après l'autre : un refus peut
  n'apparaître qu'après l'expiration du message précédent.
