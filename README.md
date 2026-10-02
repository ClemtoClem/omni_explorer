# OmniExplorer — Application Android Flutter

Application Android tout-en-un combinant :

## Fonctionnalites

### Explorateur de fichiers
- Navigation complete dans le stockage interne et externe (SD)
- Barre de chemin interactive et editable (style Ubuntu)
  - Bouton remonter (↑), undo (←), redo (→)
  - Chaque segment est un bouton cliquable
  - Double-clic pour editer le chemin manuellement
- Raccourcis de répertoire personnalisables sur la page Stockage (ajout,
  modification du nom, du répertoire, de l'icône et de la couleur, ordre,
  retrait)
- Sert aussi de sélecteur (fichier, fichiers, dossier, enregistrement) pour
  toutes les autres fonctionnalités
- Filtres par nom et par categorie de fichier
- Tri par nom, date, taille, type
- Vue liste et vue grille
- Icones adaptees au type de fichier
- Affichage de la date de modification et de la taille
- Selection multiple avec actions groupees (copier, deplacer, corbeille, supprimer)
- Gestion de la corbeille (avec restauration et vidage)
- Creation de raccourcis (dossiers)
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

- **Linux** : le stockage sécurisé (`flutter_secure_storage`) exige le paquet
  système `libsecret-1-dev` à la compilation (`sudo apt install
  libsecret-1-dev`), et un service de trousseau (GNOME Keyring…) à
  l'exécution.

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
  **Correction (P0.6)** : ce retrait n'avait en réalité pas eu lieu. Le
  commit de P0.0 avait été fait avec `git commit -- <chemins>`, qui prend le
  contenu de l'arbre de travail : les caches ont été committés modifiés au
  lieu d'être retirés, et le zip est resté suivi. Le retrait a été refait
  (commit `chore(repo): actually untrack…`), et
  `git ls-files -ci --exclude-standard` est maintenant vide.
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

### P0.7 : secrets hors des préférences, sauvegarde désactivée, clé SSH vérifiée

Branche : `p0/secrets`

**Problèmes**
- Le **mot de passe SSH** était enregistré **en clair** dans les préférences
  (SharedPreferences), alors même que le terminal SSH n'est accessible nulle
  part dans l'application (seul le code mort `text_editor_screen.dart`
  l'utilise) : l'écran Paramètres le recueillait et le stockait quand même.
- **Sauvegarde Android** activée par défaut : préférences (donc ce mot de
  passe), index de la corbeille, etc. partaient dans la sauvegarde cloud et
  dans le transfert d'un téléphone à l'autre.
- **Clé d'hôte SSH jamais vérifiée** : sans `onVerifyHostKey`, `dartssh2`
  accepte n'importe quel serveur. Un serveur intercalé (attaque de l'homme du
  milieu) aurait reçu le mot de passe sans aucun avertissement.

**Décision** : sur la question « ne plus enregistrer le mot de passe » ou
« le mettre en stockage sécurisé », le stockage sécurisé a été retenu.

**Modifications**
- Dépendance `flutter_secure_storage` 10.3.4 : Keystore sur Android, DPAPI
  sur Windows, Secret Service sur Linux. Elle servira aussi au coffre-fort
  (P1).
- `SettingsService` :
  - le mot de passe SSH est lu et écrit **uniquement** dans le stockage
    sécurisé ;
  - **migration** : l'ancienne valeur en clair y est copiée, puis effacée des
    préférences, et seulement si la copie a réussi ;
  - si le stockage sécurisé est indisponible, l'ancienne valeur est
    conservée (pas de perte) et la migration est retentée au lancement
    suivant ; enregistrer un nouveau mot de passe affiche alors un message ;
  - chaque accès au stockage sécurisé a un **délai maximal de 5 s** : un
    stockage qui ne répond pas ne bloque plus le démarrage de l'application ;
  - le secret n'est jamais journalisé.
- Android :
  - `allowBackup="false"` et `fullBackupContent="false"` (Android ≤ 11) ;
  - `dataExtractionRules` (Android 12+) excluent toutes les données de la
    sauvegarde cloud **et** du transfert d'appareil à appareil (que
    `allowBackup` seul ne bloque plus depuis Android 12).
- SSH, avec « confiance à la première connexion » (TOFU) :
  - nouveau `ssh_known_hosts.dart`, équivalent de `~/.ssh/known_hosts` :
    empreintes SHA-256 au format OpenSSH, par hôte et par port ;
  - nouveau `ssh_host_key_dialog.dart` :
    - premier contact : l'empreinte est affichée, avec la commande qui
      permet de la vérifier côté serveur ; l'utilisateur accepte ou refuse ;
    - clé différente de celle acceptée : connexion **refusée**, avec un
      avertissement d'interception possible ;
  - branché sur le panneau SSH (`onVerifyHostKey`). `dartssh2` vérifie de son
    côté la signature de l'échange avec cette clé, vérifié dans son code ;
  - Paramètres → VM Debian — SSH : bouton « Oublier la clé du serveur »,
    pour un serveur réinstallé.
- Tests : le stockage sécurisé est simulé partout où `SettingsService` est
  initialisé. Sans cela, les tests restaient bloqués, ce qui a révélé le
  risque de blocage au démarrage corrigé ci-dessus.

**Validation**
- 16 nouveaux tests :
  - `test/core/services/settings_service_ssh_test.dart` (6 tests) : migration
    puis effacement, valeur vide, lecture existante, écriture jamais en
    clair, stockage en panne (valeur conservée), stockage muet (démarrage
    non bloqué) ;
  - `test/features/text_editor/ssh_known_hosts_test.dart` (6 tests unitaires
    et 4 tests de widget) : format de l'empreinte, inconnu → accepté →
    reconnu, clé ou type changé, hôte et port, oubli, données corrompues ;
    dialogue accepté, refusé, clé connue sans question, clé changée refusée.
- Tests de mutation : mot de passe en clair non effacé, délai retiré, clé
  changée reconnue, dialogue qui accepte une clé changée : chacun de ces
  sabotages fait échouer des tests.
- `flutter test` : 175 tests réussis (deux exécutions complètes).
  `flutter analyze` : 0 erreur, 0 avertissement (12 remarques de style
  préexistantes). `flutter build apk --debug` et `flutter build linux
  --debug` : réussis.

**Limites et suite**
- Le **panneau SSH** reste inaccessible (code mort) : le branchement de la
  vérification de clé n'est testé qu'à travers le dialogue et le service, pas
  sur une vraie connexion SSH.
- Sur Linux, le stockage sécurisé suppose un trousseau (GNOME Keyring…)
  actif ; sinon, le mot de passe n'est pas mémorisé (message), et un ancien
  mot de passe en clair reste dans les préférences jusqu'à une migration
  réussie.
- Désactiver la sauvegarde Android signifie que les réglages ne suivent pas
  l'utilisateur sur un nouveau téléphone ; un export chiffré, notamment pour
  le coffre-fort, sera à prévoir.
- L'Android Lint signalera que `dataExtractionRules` n'a d'effet qu'à partir
  de l'API 31 : c'est attendu, `allowBackup` couvre les versions
  antérieures.

### P1.1 : coffre-fort de mots de passe (cœur)

Branche : `p1/vault`

**Point de départ** : l'écran du coffre-fort n'était qu'un texte « en cours de
développement ». Aucune cryptographie, aucun stockage.

**Dépendances**
- `sodium` 4.1.1 (libsodium 1.0.22). `sodium_libs`, choisi à l'origine, est
  déprécié au profit de ce paquet (même API). Ses « build hooks » **compilent
  libsodium depuis ses sources**, fournies avec le paquet et signées, pour
  Android (NDK) comme pour Linux. Aucun binaire précompilé, ce qui convient à
  F-Droid ; vérifié dans les deux builds (`libsodium.so` pour arm64-v8a,
  armeabi-v7a, x86_64 et Linux x64).
- `archive` passe de 3.6 à 4.3, **exigé par `sodium`**. Adaptations : les
  encodeurs ne renvoient plus `null`, les entrées « lien » et « dossier » ont
  des constructeurs dédiés. Les 21 tests d'archives (dont Zip Slip) passent
  sans changement de comportement ; un test vérifie en plus qu'un dossier vide
  reste un dossier dans une archive créée (il passait déjà avec l'ancien
  appel : c'est une non-régression, pas une correction).

**Cryptographie** (`services/vault_crypto.dart`)
- **KEK** dérivée du mot de passe maître par **Argon2id** (3 passes,
  128 Mio, sel aléatoire de 16 octets), calculée dans un isolate pour ne pas
  figer l'interface. Mesure : 0,05 s (64 Mio) à 0,33 s (256 Mio) sur PC ;
  128 Mio sont un compromis pour les téléphones modestes.
- **DEK** aléatoire de 32 octets, qui chiffre le contenu en
  **XChaCha20-Poly1305** ; elle est elle-même chiffrée par la KEK. Les clés
  sont gardées en mémoire native (`SecureKey`), effacées au verrouillage.
- **Format de fichier versionné** : `OMNIVLT1` | longueur | en-tête JSON
  (paramètres Argon2id, sel, DEK chiffrée, nonces) | contenu chiffré.
  **Tout ce qui précède le contenu est authentifié** (données associées) : la
  moindre modification de l'en-tête ou du contenu est détectée. Un format ou
  un schéma plus récent est refusé avec un message clair. Le contenu a son
  propre numéro de schéma et une table de migrations. Les fichiers malformés
  (tronqué, signature, longueur, paramètres, algorithme) sont rejetés sans
  plantage.

**Fichier** (`services/vault_repository.dart`)
- Dossier privé de l'application (Linux : droits 700) ; sauvegarde Android
  désactivée depuis P0.7.
- Chaque sauvegarde **copie la version actuelle dans `.bak`**, puis écrit la
  nouvelle de façon atomique. Si le fichier principal est endommagé, la
  version précédente peut être ouverte, puis réinstallée.
- En cas d'échec d'écriture, le fichier et le contenu en mémoire restent
  inchangés.
- **Changement du mot de passe maître** : vérification du mot de passe
  actuel (comparaison en temps constant), puis **sel, KEK et DEK
  renouvelés**.

**Session et sécurité** (`providers/vault_session.dart`, `services/…`)
- **Verrouillage automatique** : après 5 min sans interaction, 60 s après
  le passage en arrière-plan (le temps d'aller coller un mot de passe), et
  immédiatement si l'application se termine. Le verrouillage efface les clés,
  le contenu déchiffré et le presse-papiers.
- **Presse-papiers** : effacé 30 s après une copie. Sur Android, la copie est
  marquée « sensible » (Android 13+ ne l'affiche pas en aperçu), et
  l'effacement se fait côté natif. Une application en arrière-plan ne peut
  plus lire le presse-papiers (Android 10+) : si la vérification est
  impossible, l'effacement a lieu quand même.
- **Captures d'écran bloquées** (`FLAG_SECURE`) tant qu'un écran du coffre
  est affiché ; la vignette dans les applications récentes est masquée
  (`lib/core/utils/secure_window.dart`, canal natif dans `MainActivity.kt`).
- **Générateur de mots de passe** : `Random.secure()` (générateur
  cryptographique, tirage sans biais), au moins un caractère de chaque
  famille choisie, mélange de Fisher-Yates, option « sans caractères
  ambigus », estimation de l'entropie.

**Interface**
- Création : double saisie, 8 caractères minimum, avertissement « aucune
  récupération possible ».
- Déverrouillage : erreur claire en cas de mauvais mot de passe ; reprise
  sur la version précédente si le fichier est endommagé ; « Mot de passe
  oublié… » (suppression du coffre, confirmée par la saisie de SUPPRIMER).
- Liste avec recherche (titre, identifiant, adresse ; jamais le mot de
  passe), copie de l'identifiant ou du mot de passe, bouton de verrouillage,
  changement du mot de passe maître.
- Entrée : titre, identifiant, mot de passe (masqué, générateur, copie),
  adresse, notes ; clavier sans suggestions ni apprentissage ; confirmation
  avant d'abandonner des modifications ; l'écran se ferme si le coffre se
  verrouille.

**Validation**
- 40 tests dans `test/features/password_vault/` :
  - chiffrement (11 tests) : aller-retour, aucune donnée en clair dans le
    fichier, sel et nonces neufs à chaque sauvegarde, mauvais mot de passe,
    contenu et en-tête modifiés, format et schéma trop récents, fichiers
    malformés ;
  - fichier (12 tests) : création, refus d'écraser, sauvegarde et `.bak`,
    échec d'écriture sans perte, reprise après corruption, changement de mot
    de passe, effacement au verrouillage, suppression, droits 700 ;
  - session (6 tests) : cycle complet, verrouillage par inactivité et en
    arrière-plan, interaction qui repousse le verrouillage, presse-papiers
    vidé, échec de sauvegarde ;
  - générateur (6 tests), presse-papiers (3 tests) ;
  - interface (2 tests de widget) : parcours créer → ajouter → verrouiller →
    mauvais puis bon mot de passe, recherche.
- Tests de mutation : en-tête non authentifié, mot de passe actuel non
  vérifié, pas de `.bak`, contenu non effacé au verrouillage, générateur
  sans garantie de famille : chacun de ces sabotages fait échouer des tests.
  Le quatrième n'était pas détecté au départ ; le test manquant a été ajouté.
- `flutter test` : 216 tests réussis (deux exécutions complètes).
  `flutter analyze` : 0 erreur, 0 avertissement (12 remarques de style
  préexistantes). `flutter build apk --debug` et `flutter build linux
  --debug` : réussis.

**Découvertes pendant les tests**
- Un `Process.run` (le `chmod 700` du dossier sous Linux), lancé depuis
  l'interface, ne rendait jamais la main dans les tests de widget : il est
  remplacé par `Process.runSync`, appelé une seule fois.
- La dérivation par isolate ne peut pas être pilotée par les tests de widget
  (horloge fictive) : ces tests la désactivent (`useIsolate: false`) ; le
  chemin par isolate est couvert par les tests unitaires.

**Pas encore fait (P1.1b)**
- **Déverrouillage biométrique** (Android) : il faut une clé du Keystore
  exigeant l'authentification de l'utilisateur pour protéger la DEK. Le
  format à deux niveaux de clés le permet sans changer le fichier, mais il
  faut du code natif (BiometricPrompt) ou une dépendance supplémentaire, à
  décider.
- **Export et import chiffrés** du coffre, d'autant plus utiles que la
  sauvegarde Android est désactivée.
- Calibrage d'Argon2id selon l'appareil, et renforcement automatique des
  paramètres d'un ancien coffre à l'ouverture.
- Délais de verrouillage réglables dans les paramètres.

**Limites connues**
- Le mot de passe maître saisi est une chaîne Dart, qui ne peut pas être
  effacée de la mémoire : seules ses copies en octets et les clés le sont.
- Pas de test sur un appareil réel : `FLAG_SECURE`, le presse-papiers
  sensible et le temps d'Argon2id sur téléphone restent à vérifier en
  conditions réelles.

### P1.1b : export et import du coffre par paquet verrouillé

Branche : `p1/vault-export`

**Décisions**
- Pas de déverrouillage biométrique : l'appareil cible n'a pas de capteur
  d'empreinte.
- Export et import passent par un **paquet verrouillé avec le mot de passe
  du coffre**.

**Format du paquet** (`.omnivault`)
- Même format et même chiffrement que le coffre (Argon2id,
  XChaCha20-Poly1305, en-tête authentifié), avec une **signature distincte**
  (`OMNIEXP1`) : un export ne peut pas être pris pour le coffre, ni
  l'inverse. Une nouvelle clé de données est tirée pour chaque export.
- Ce n'est pas un ZIP à mot de passe : sur Android, le chiffrement ZIP
  passerait par 7z (absent), et le ZipCrypto standard est faible.

**Export** (menu du coffre → « Exporter… »)
- Le mot de passe maître doit être **ressaisi** et est vérifié (précaution
  si le téléphone est laissé déverrouillé).
- Le paquet est protégé par ce mot de passe maître. Nom proposé :
  `coffre-omniexplorer-AAAA-MM-JJ.omnivault`. Sur Android, c'est le
  sélecteur du système qui l'enregistre ; sur Linux, écriture atomique à
  l'emplacement choisi.

**Import** (menu → « Importer… »)
- Le paquet est déchiffré avec le mot de passe du coffre qui l'a créé
  (celui en vigueur au moment de l'export) : il peut donc venir d'un autre
  coffre ou d'un autre appareil.
- **Aperçu avant toute modification** :
  - entrées nouvelles ;
  - entrées identiques à une existante, ignorées ;
  - conflits, c'est-à-dire une entrée qui correspond à une existante (même
    identifiant interne, ou même titre, identifiant et adresse) mais dont le
    contenu diffère. Au choix : garder les deux (l'importée reçoit
    « (importé) » dans son titre), remplacer (l'entrée existante garde son
    identifiant), ou garder celles du coffre.
- Refus clairs : fichier qui n'est pas un export, fichier de plus de 32 Mio,
  export modifié ou endommagé, mauvais mot de passe (qui s'affiche sous le
  champ, sans fermer le dialogue).
- Sur Android, la copie du fichier que le sélecteur dépose dans le cache est
  supprimée après l'import.

**Code**
- `services/vault_crypto.dart` : signature paramétrable (coffre / export).
- `services/vault_repository.dart` : `verifyPassword` (extrait de
  `changePassword`), `exportPackage`, `readExportPackage`.
- `services/vault_merge.dart` : analyse (`plan`) puis application
  (`apply`) de la fusion, en pur Dart.
- `providers/vault_session.dart` : `exportPackage`, `previewImport` (ne
  modifie rien), `applyImport`.
- `widgets/vault_transfer_dialogs.dart` : dialogues d'export et d'import.

**Validation**
- 15 nouveaux tests :
  - `test/features/password_vault/vault_export_test.dart` (8 tests) :
    mot de passe exigé, aller-retour, signature d'export, aucune donnée en
    clair, import dans un autre coffre avec le mot de passe d'origine,
    export avant et après un changement de mot de passe, fichier du coffre
    ou quelconque refusé, export modifié, taille maximale ; aperçu sans
    modification puis application persistée ;
  - `test/features/password_vault/vault_merge_test.dart` (7 tests) :
    classement nouveau / identique / conflit (par identifiant ou par
    compte), doublons dans l'export, les trois stratégies, identifiant
    conservé en cas de remplacement depuis un autre coffre, identifiants
    toujours uniques.
- Tests de mutation : export sans vérification du mot de passe, export avec
  la signature du coffre, fusion sans rapprochement par compte, remplacement
  qui prend l'identifiant importé : chacun de ces sabotages fait échouer des
  tests. Le dernier n'était pas détecté au départ ; le test « remplacer
  depuis un autre coffre » a été ajouté.
- `flutter test` : 231 tests réussis (deux exécutions complètes).
  `flutter analyze` : 0 erreur, 0 avertissement (12 remarques de style
  préexistantes). `flutter build apk --debug` et `flutter build linux
  --debug` : réussis.

**Limites**
- Les dialogues d'export et d'import eux-mêmes ne sont pas couverts par des
  tests de widget (le sélecteur de fichiers est natif) ; la logique qu'ils
  appellent l'est.
- À vérifier sur téléphone : l'enregistrement via le sélecteur Android et
  l'import depuis un autre appareil.

### P1.3 : archives et paquets — formats, navigation, édition, doublons

Branche : `p1/archives`

**Demande** : empaqueter et désarchiver « n'importe quel format » ; corriger
l'arborescence dans une archive ; ajouter, déplacer, renommer et dupliquer
comme dans l'explorateur ; mettre à jour une archive depuis un dossier ;
numéroter les doublons (`nom.1.ext`) ou demander s'il faut écraser ou
ignorer, à l'extraction comme lors des déplacements ; dupliquer
(`nom.copy.N.ext`).

**Ce qui est possible, et pourquoi**

| Format | Lire / extraire | Créer | Modifier |
|---|---|---|---|
| ZIP et dérivés (`.jar`, `.apk`, `.docx`, `.odt`, `.epub`…) | oui | oui, chiffrement AES possible | oui |
| TAR, TAR.GZ, TAR.BZ2 | oui | oui | oui |
| GZ, BZ2 (fichier unique) | oui | oui (un fichier) | — |
| TAR.XZ, XZ | oui | non | non |
| 7z | Linux, avec `7z` installé | Linux | non |
| RAR | Linux, avec `unrar` | **impossible** | non |

- **RAR** : format propriétaire, aucun outil libre ne sait l'écrire, et
  `unrar` n'est pas libre (F-Droid).
- **XZ** : l'encodeur du paquet `archive` n'écrit que des données **non
  compressées** (précisé dans sa documentation) ; réécrire un `.tar.xz`
  le ferait gonfler en silence, d'où la lecture seule.
- **7z sous Android** : il faudrait une bibliothèque native (libarchive, par
  exemple) ; c'est un chantier à part.

**Doublons et conflits** (`lib/core/utils/file_naming.dart`)
- Conflit (extraction, déplacement, copie vers un autre dossier) : au choix
  **Renommer** (`rapport.1.txt`, puis `rapport.2.txt`…), **Remplacer** ou
  **Ignorer**, avec « Appliquer aux éléments suivants ».
- **Dupliquer** (explorateur et archives) : `rapport.copy.1.txt`,
  `rapport.copy.2.txt`… Dupliquer une copie reprend la numérotation de
  l'original. Copier un élément dans son propre dossier est une duplication.
- Doubles extensions respectées (`site.1.tar.gz`) ; dossiers et fichiers
  cachés : suffixe à la fin (`photos.1`, `.bashrc.1`). Remplace l'ancien
  suffixe « (copie) ».

**Arborescence : les erreurs d'affichage** (`models/archive_tree.dart`)
1. La liste visible était triée d'un bloc (dossiers d'abord, puis par
   nom) : les fichiers s'éloignaient de leur dossier.
2. Beaucoup d'archives ne listent que `a/b/c.txt`, sans entrée pour `a/`
   ni `a/b/` : ces dossiers n'existaient pas, et leur contenu était
   inaccessible.
3. Chemins hétérogènes (`./`, `\`, `//`, `/` initial).

`ArchiveTree` normalise les chemins, recrée les dossiers implicites et liste
chaque dossier séparément. L'écran passe à une navigation **dossier par
dossier**, comme l'explorateur : fil d'Ariane, et le retour arrière remonte
d'un dossier.

**Reconnaissance des formats** : par **signature binaire** (ZIP, GZip, BZip2,
XZ, 7z, RAR, TAR). Pour TAR, la marque `ustar` ou une **somme de contrôle
d'en-tête valide**, ce qui couvre l'ancien format V7 que produit le paquet
`archive` lui-même. Les fichiers dérivés de ZIP et les archives mal nommées
sont reconnus.

**Modifier une archive** (`services/archive_document.dart`)
- Ajouter des fichiers ou un dossier du disque (un dossier déjà présent est
  fusionné ; les liens symboliques ne sont pas ajoutés), nouveau dossier,
  renommer, déplacer (vers un dossier de l'archive, avec gestion des
  conflits), dupliquer, supprimer.
- **Mettre à jour depuis un dossier**, pour les sauvegardes de projet :
  ajoute les fichiers absents, remplace ceux dont le contenu diffère
  (comparaison du contenu, pas de la date), **ne supprime rien**.
  Exclusions possibles (`build`, `.dart_tool`, `node_modules`…).
- Mot de passe ZIP : chiffrement **AES, natif sur toutes les plateformes**
  (auparavant via 7z, donc impossible sur Android). Un mot de passe absent
  ou faux est détecté dès l'ouverture, par contrôle du CRC32 d'un fichier.
- Enregistrement atomique après chaque opération. En cas d'échec,
  l'archive est relue depuis le disque : rien n'est à moitié appliqué.

**Créer une archive** (`widgets/compress_dialog.dart`,
`ArchiveService.createArchive`) : ZIP (AES en option), TAR, TAR.GZ, TAR.BZ2,
GZ ou BZ2 pour un fichier unique, 7z sous Linux. Les liens symboliques ne
sont plus suivis : un lien vers un dossier parent faisait boucler la
création.

**Autres corrections**
- `extractEntry` compare des chemins normalisés : `./src/a.txt` était
  introuvable sous `src`.
- Code mort retiré : `addFilesToZip`, `removeFromZip`, `setPassword`,
  `removePassword`, que remplace `ArchiveDocument`. L'ancien écran (1 238
  lignes) est remplacé ; la boîte de création passe dans son propre fichier.
- Tests : délai maximal des attentes porté de 10 s à 30 s (plafond
  seulement). Deux tests échouaient parfois quand plusieurs suites
  tournaient en parallèle, dont celui de l'éditeur, déjà vu une fois en
  P0.5. Le test d'interface du coffre attend désormais la fermeture réelle
  de l'écran d'édition.
- Un commit de pur formatage (`style(archive): …`) est séparé des
  changements fonctionnels.

**Validation**
- 43 nouveaux tests :
  - nommage (11), duplication dans l'explorateur (3) ;
  - arborescence (6), reconnaissance des formats (4) ;
  - document (14), dont les modifications et la mise à jour depuis un
    dossier **pour chacun des quatre formats modifiables**, les conflits, le
    ZIP AES et la lecture seule ;
  - écran (5 tests de widget) : navigation dans une archive sans entrées de
    dossier, fil d'Ariane et retour, dupliquer puis supprimer (vérifié dans
    le fichier), recherche, lecture seule, mot de passe.
- Tests de mutation : pas de dossiers implicites, tri global, contenu
  toujours jugé identique, conflit de déplacement ignoré, numéro placé après
  l'extension, pas de reprise de numérotation, retour arrière qui quitte
  l'écran : chacun de ces sabotages fait échouer des tests.
- `flutter test` : 274 tests réussis, **6 exécutions complètes consécutives**
  après la correction des attentes. `flutter analyze` : 0 erreur,
  0 avertissement (12 remarques de style préexistantes). `flutter build apk
  --debug` et `flutter build linux --debug` : réussis.

**Limites et suite**
- Les archives sont chargées entièrement en mémoire, à l'ouverture comme à
  l'enregistrement : le streaming des très grosses archives reste prévu en
  P2.
- Les actions qui passent par le sélecteur de fichiers (ajouter, mettre à
  jour, extraire vers) ne sont pas couvertes par des tests de widget ; les
  opérations qu'elles appellent le sont.
- Ouvrir un fichier contenu dans l'archive sans l'extraire n'est pas encore
  possible (seules les actions d'extraction le permettent).
- 7z et RAR restent en lecture seule, et sous Linux uniquement.

### Explorateur unique pour la navigation et raccourcis personnalisables

**Problème**
- Plusieurs fonctionnalités naviguaient dans les répertoires sans passer par
  l'explorateur de l'application :
  - l'éditeur multimédia (éditer une vidéo, un audio ou une image ;
    assembler des clips), via le sélecteur système de `file_picker` ;
  - les archives (ajouter des fichiers ou un dossier, mettre à jour depuis
    un dossier, extraire vers…), via le même sélecteur ;
  - le coffre-fort (export et import), via le même sélecteur ;
  - l'ancien éditeur de texte (`text_editor_screen.dart`, plus importé
    nulle part), via son propre navigateur de dossiers `_FolderPickerSheet`.
- L'explorateur ramenait tout chemin hors du stockage interne à sa racine :
  le bouton « Explorer » d'une carte SD ouvrait le stockage interne.
- Les raccourcis de la page Stockage n'étaient pas modifiables, et les
  « Favoris » (ajoutés depuis l'explorateur) avaient tous la même icône.
- Sous Linux, la page Stockage était vide (aucun stockage détecté).

**Modifications**
- `ExplorerPicker` (`features/file_explorer/explorer_picker.dart`) ouvre
  `FileExplorerScreen` en mode sélecteur : `pickFile`, `pickFiles`,
  `pickDirectory`, `saveFile`. Le mode sélecteur garde la navigation de
  l'explorateur (barre de chemin, tri, filtres, fichiers cachés, cartes SD).
  Il masque les fichiers refusés (catégories, extensions), cache le menu
  contextuel et le collage, et affiche une barre de validation en bas
  (« Valider », « Choisir ce dossier », ou un nom de fichier avec
  « Enregistrer »). Le remplacement d'un fichier existant est confirmé. Un
  sélecteur ne modifie pas la dernière position mémorisée de l'explorateur.
- Toutes les fonctionnalités citées plus haut utilisent `ExplorerPicker`. Le
  coffre écrit maintenant son export de façon atomique sur Android aussi, et
  l'import lit le fichier sur place (plus de copie dans le cache).
  La dépendance `file_picker` est retirée.
- Navigation entre stockages : les racines des stockages détectés (interne,
  cartes SD) sont connues du provider. Un chemin situé sur une carte SD fait
  basculer la racine sur cette carte, y compris avec Précédent / Suivant.
- Raccourcis (page Stockage) : une seule grille « Raccourcis » remplace
  « Favoris » et les raccourcis fixes. Les dossiers par défaut (Images,
  Vidéos, Documents, Musique, Téléchargements, Apps, Tout) y sont ajoutés
  une seule fois, devant les favoris existants. Ensuite, l'utilisateur les
  gère :
  - **ajouter** : bouton « + » ou case « Ajouter » ;
  - **modifier** (appui long) : nom, répertoire (choisi dans
    l'explorateur), icône (32 au choix), couleur (10 au choix), avec un
    aperçu ;
  - **déplacer** avant / après, et **retirer** (annulable).
  Un raccourci dont le répertoire n'existe plus apparaît grisé et propose
  « Modifier ». « Ajouter aux raccourcis » dans l'explorateur n'est plus
  proposé que pour les dossiers ; un ancien favori pointant sur un fichier
  ouvre son dossier.
- `ShortcutItem` gagne une couleur (`color`, ARGB) et `copyWith`. Les
  anciens favoris se relisent sans changement.
- `SettingsService` : `updateShortcut`, `moveShortcut`,
  `seedDefaultShortcuts`. `addShortcut` signale un doublon. Correction : la
  relecture des raccourcis repartait de la liste précédente quand la
  préférence était absente.
- Linux : le dossier personnel sert d'espace de stockage principal (page
  Stockage, raccourcis par défaut).

**Validation**
- 19 nouveaux tests :
  - provider (5) : filtres du sélecteur (catégorie, extension sans tenir
    compte de la casse, mode dossier) et bascule vers une carte SD, aller et
    retour ;
  - raccourcis dans `SettingsService` (5) : défauts ajoutés une seule fois,
    doublons, modification persistée, déplacement aux bornes, relecture des
    anciens favoris ;
  - sélecteur, par l'interface (5) : fichier unique filtré, fichiers
    multiples, dossier, annulation, enregistrement avec remplacement
    confirmé ;
  - page Stockage (4) : modifier l'icône et le nom, retirer puis annuler,
    changer de répertoire en passant par l'explorateur, champs obligatoires
    à l'ajout.
- `flutter test` : 293 tests réussis. `flutter analyze lib test` : 0 erreur
  (13 remarques préexistantes) ; `flutter build apk --release` :
  réussi.

**Limites et suite**
- Sous Android, l'explorateur (donc le sélecteur) ne voit que ce que
  permettent les autorisations de stockage. Sans « Accès à tous les
  fichiers », un export du coffre ne peut pas être écrit hors des dossiers
  autorisés.
- À l'ouverture, l'explorateur affiche brièvement « Répertoire vide » avant
  le premier chargement (défaut préexistant, visible aussi dans le
  sélecteur).

### Coffre-fort : catégories d'informations et tri

**Problème**
- Le coffre ne savait enregistrer qu'un seul type d'information :
  identifiant, mot de passe, adresse et notes.
- La liste était toujours triée par titre, de A à Z.

**Modifications**
- Catégories (`models/vault_category.dart`). Chaque entrée a un **tag**
  (son nom, obligatoire, clé de tri) et les champs de sa catégorie :

  | Catégorie | Champs (en plus des notes) |
  |---|---|
  | Site web | identifiant, mot de passe, adresse (URL) |
  | Messagerie | adresse e-mail, mot de passe, serveur |
  | Message secret | message |
  | Banque | nom de la banque, titulaire de la carte, numéro de carte complet, date d'expiration, cryptogramme, code PIN, IBAN, BIC, RIB, identifiant et code d'accès en ligne |
  | Réseau Wi-Fi | nom du réseau, mot de passe, sécurité |
  | Serveur / SSH | hôte, port, utilisateur, mot de passe, clé privée |
  | Pièce d'identité | type, nom complet, numéro, dates de délivrance et d'expiration, autorité |
  | Santé | numéro de sécurité sociale, mutuelle, numéro d'adhérent, groupe sanguin |
  | Téléphone / SIM | numéro, opérateur, PIN, PUK, code de déverrouillage |
  | Licence logicielle | logiciel, clé, titulaire, e-mail du compte |
  | Portefeuille crypto | portefeuille, adresse publique, phrase de récupération, mot de passe |

  Chaque champ a une nature : texte, e-mail, URL, secret, mot de passe
  (avec le générateur), code, texte long, texte long secret. Les champs
  secrets sont masqués à la saisie (bouton afficher / masquer) et exclus de
  la recherche. Tous les champs sauf les notes sont copiables, avec
  effacement automatique du presse-papiers.
- Formulaire (`vault_entry_screen.dart`) : la catégorie se choisit à
  l'ajout (liste des catégories avec leurs champs) et peut être changée
  ensuite. Les valeurs des champs de même clé sont gardées (mot de passe,
  notes…). Les champs d'une catégorie inconnue de cette version (coffre
  écrit par une version plus récente) sont conservés.
- Liste : icône et couleur de la catégorie, sous-titre « catégorie · champ
  résumé » (identifiant, adresse e-mail, banque, réseau…), copie rapide du
  résumé et du secret principal. Menu **Trier** : tag de A à Z, tag de Z à
  A, ou catégorie. Le tri par catégorie regroupe les entrées sous un
  en-tête par catégorie (catégories et tags de A à Z). La comparaison
  ignore la casse et les accents (« Écran » se range avec les « e »). Le
  tri choisi est retenu dans les préférences (il ne révèle rien du
  contenu).
- Schéma du contenu 1 → 2 (`VaultContent`) : entrées
  `{id, title, category, fields, createdAt, updatedAt}`. Une migration
  transforme les entrées du schéma 1 en « Site web », à l'ouverture d'un
  ancien coffre comme à l'import d'un ancien export. Une version antérieure
  de l'application refuse un coffre du schéma 2 (« coffre trop récent »)
  au lieu de l'abîmer.
- Fusion à l'import : deux entrées se correspondent si elles ont la même
  catégorie, le même tag et le même champ résumé (et la même adresse pour
  un site web). Le contenu est comparé champ par champ.

**Validation**
- 18 nouveaux tests :
  - modèle (5) : migration du schéma 1, fiche bancaire complète inchangée
    après enregistrement, catégorie inconnue conservée, champ mal formé
    signalé comme corruption, cohérence du catalogue ;
  - recherche (1) : jamais dans les secrets ;
  - tri (5) : tag croissant et décroissant sans casse ni accents, par
    catégorie puis par tag, liste d'origine intacte, préférence inconnue ;
  - fusion (3) : même tag dans deux catégories, conflit sur un champ de
    catégorie puis remplacement, doublon ;
  - interface (4) : saisie d'une fiche bancaire complète (numéros masqués),
    tri A → Z / Z → A / par catégorie avec en-têtes, changement de
    catégorie qui garde les champs communs, tri retrouvé à la session
    suivante.
- Les tests existants du coffre sont adaptés au modèle par champs. Le test
  d'interface d'origine attendait 30 s (plafond) la fermeture du formulaire
  sans avancer l'horloge des animations ; il passe maintenant par une
  attente qui la fait avancer : de 43 s à 5 s.
- `flutter test` : 311 tests réussis. `flutter analyze lib test` : 0 erreur
  (13 remarques préexistantes). `flutter build apk --release` : réussi.

**Limites et suite**
- Les champs sont fixes par catégorie : pas encore de champs
  personnalisés ni de catégorie créée par l'utilisateur.
- Pas de filtre par catégorie (seulement le tri et la recherche, qui
  reconnaît le nom de la catégorie).
- Les formats ne sont pas validés (IBAN, numéro de carte, dates) : ce sont
  des textes libres.
