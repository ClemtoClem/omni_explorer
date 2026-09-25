# Étape A : diagnostic

## État actuel

| Élément | Constat |
|---|---|
| Taille | 112 fichiers Dart, environ 29 700 lignes. Plateformes : Android, Linux, Windows |
| Organisation | Dossiers par fonctionnalité (`lib/features/*`) plus `lib/core` et `lib/app`. **C'est une base saine, je propose de la garder** |
| Gestion de l'état | Provider avec ChangeNotifier. Des singletons (`SettingsService`, `TrashService`, `LanguageRegistry`, `FileService`) et des services statiques (`ArchiveService`, `VideoExportService`). Pas d'injection de dépendances |
| Navigation | `Navigator.push` classique. `go_router` est déclaré mais jamais utilisé |
| Code natif | [MainActivity.kt](android/app/src/main/kotlin/com/example/omni_explorer/MainActivity.kt) ouvre l'écran WRITE_SETTINGS. [VideoThumbnailPlugin.java](android/app/src/main/java/io/flutter/plugins/VideoThumbnailPlugin.java) **n'est pas branché** (voir plus bas) |
| Paquets modifiés localement | `re_editor` : un seul changement, `onFocusReceived`, pour rester compatible avec la version récente de Flutter. `material_design_icons_flutter` : fichier `icon_map` régénéré. Ces écarts avec l'original ne sont documentés nulle part |
| Analyse statique | `flutter analyze` : **0 erreur**. 13 remarques mineures dans `lib/`, le reste vient des paquets modifiés |
| Tests | Un seul : le test « Counter » généré par Flutter. **Il échoue** |
| CI/CD | Aucune. Le dépôt GitHub `ClemtoClem/omni_explorer` a 2 commits |
| Arbre Git | 30 fichiers modifiés et 7 fichiers non suivis (travail en cours sur l'éditeur multimédia), non commités |
| Build Android | **Pas lancé pendant l'audit.** Ce sera la première étape de l'étape C |

**Avancement des modules :**
- **Coffre-fort : 0 %.** [password_vault_home_screen.dart](lib/features/password_vault/screens/password_vault_home_screen.dart) est un simple écran d'attente. Il n'existe ni crypto, ni stockage, ni dépendance adaptée.
- **Éditeur de code :** il repose sur `re_editor`, avec 19 langages déclarés dans le registre. Il n'a pas de numéros de ligne, alors que `re_editor` fournit déjà `indicatorBuilder`, une gouttière synchronisée avec le défilement. La recherche se limite à un `replaceFirst` sur le texte entier. Il n'y a ni aperçu HTML, ni Go Live, ni WebView dans les dépendances.
- **Éditeur multimédia :** les écrans existent (vidéo, audio, image, caméra, micro, assemblage) et l'export FFmpeg est branché, mais plusieurs défauts bloquants existent (voir la liste ci-dessous).
- **Lecteur multimédia :** propre. Les timers et abonnements sont bien libérés.
- **Code mort (environ 2 000 lignes) :** `text_editor_screen.dart` (1 250 lignes, avec son propre `LanguageRegistry` en double), `database_service.dart`, `project_tree.dart`, `scroll_visibility_listener.dart` et `track_picker_sheet.dart` (qui est pourtant modifié dans ton arbre de travail). `FileService` n'est utilisé que par ce code mort, et reproduit la logique de `FileExplorerProvider`.
- **Dépendances jamais importées :** `mime`, `photo_view`, `extended_image`, `markdown`, `open_filex`, `go_router`, `cupertino_icons`. Par ailleurs, `flutter_markdown` a été abandonné par l'équipe Flutter.

## Problèmes

### CRITIQUE (perte de données, faille exploitable ou plantage)

| # | Problème | Scénario |
|---|---|---|
| C1 | **Zip Slip** : `p.join(dest, file.name)` n'est pas validé dans [archive_service.dart](lib/features/archive/services/archive_service.dart) (`_writeArchive`, `extractEntry`) | Une archive téléchargée contient `../../DCIM/x.jpg` ou `/storage/emulated/0/...` (avec un chemin absolu, `p.join` ignore `dest`). Comme l'app a MANAGE_EXTERNAL_STORAGE, l'extraction peut écraser n'importe quel fichier utilisateur |
| C2 | **L'éditeur hex tronque les fichiers** : au-delà de 32 Mo, seuls les 32 premiers Mo sont chargés, et `_save` réécrit le fichier sans vérifier `hexTruncated` ([unified_editor_screen.dart:593](lib/features/text_editor/screens/unified_editor_screen.dart#L593), [:629](lib/features/text_editor/screens/unified_editor_screen.dart#L629)) | Un octet modifié dans une vidéo de 2 Go, puis Sauvegarder : le fichier est réduit à 32 Mo |
| C3 | **Renommer écrase sans prévenir** ([file_explorer_provider.dart:373](lib/features/file_explorer/providers/file_explorer_provider.dart#L373)). Sous Linux/Android, `File.rename` remplace une cible existante, et `/` ou `..` sont acceptés dans le nouveau nom | Renommer `a.txt` en `b.txt` alors que `b.txt` existe : `b.txt` est perdu |
| C4 | **Restauration depuis la corbeille** ([trash_service.dart](lib/core/services/trash_service.dart)) : un dossier situé sur un autre stockage (carte SD) n'est pas restauré, mais il est quand même retiré de l'index et l'opération renvoie `true`. De plus, la restauration écrase un fichier recréé au même emplacement | Le dossier devient orphelin dans la corbeille, ou un fichier plus récent est écrasé |
| C5 | **Le fichier est lu en entier avant d'être ouvert** : `readAsString` et `readAsBytes` sans limite de taille (éditeur, hex, archives) | Ouvrir un log de 2 Go, ou un gros fichier en hex, fait planter l'app par manque de mémoire |
| C6 | **Écritures non atomiques** : la sauvegarde de l'éditeur écrit directement dans le fichier. `setPassword` sur une archive supprime l'original avant de renommer la copie | Si l'app est tuée pendant l'écriture, le fichier est corrompu |

### ÉLEVÉ

- **Mot de passe SSH en clair dans SharedPreferences** ([settings_service.dart:103](lib/core/services/settings_service.dart#L103)). `allowBackup` n'est pas défini, donc vaut `true` par défaut : le mot de passe part dans la sauvegarde Android. La connexion SSH ne vérifie pas la clé du serveur (`onVerifyHostKey` absent), ce qui permet une interception.
- **Les miniatures vidéo ne fonctionnent pas** : le plugin Java n'est enregistré nulle part, son `package` ne correspond pas à son dossier, et le nom de canal diffère entre le Java et le Dart (`plugins.justsoft.xyz/...` contre `plugins.io.flutter/...`). La timeline de découpe, le choix de la couverture (cover) et son export échouent tous.
- **FFmpeg casse sur les apostrophes** : les chemins sont entourés de `'...'`, y compris dans la liste de concaténation. Un nom de fichier comme `l'été.mp4` fait échouer tous les exports.
- **Les exports et enregistrements vont dans le dossier temporaire** (`getTemporaryDirectory`). Ce dossier peut être vidé par le système, et l'utilisateur ne voit pas ces fichiers.
- **L'export « en arrière-plan » s'arrête dès qu'on quitte l'écran**, parce que `dispose()` appelle `ExportService.disposeAll()`. L'inversion (`-vf reverse`) charge toute la vidéo en mémoire.
- **La caméra ignore le cycle de vie de l'application** : elle reste bloquée, ou l'app plante, au retour d'arrière-plan.
- **Archives entièrement en mémoire**, sans annulation. Le 7z et le RAR passent par `which 7z`, qui n'existe pas sur Android, et le mot de passe apparaît dans la ligne de commande.
- **Permissions :**
  - La liste d'un dossier est refusée entièrement si MANAGE_EXTERNAL_STORAGE manque.
  - Les permissions Bluetooth sont demandées alors qu'elles ne servent à rien.
  - `READ_DEVICE_CONFIG` n'est pas une permission valide pour une app.
  - La demande est relancée à chaque démarrage.
  - Cinq appels natifs de vérification de permissions ont lieu à chaque ouverture de dossier.
- **Build Android :**
  - `org.gradle.java.home` pointe vers un chemin de ta machine, ce qui cassera la CI.
  - La version release est signée avec la clé de debug.
  - L'`applicationId` est `com.example.*`.
  - La minification (R8) est désactivée.
  - Le dépôt contient des fichiers qui ne devraient pas y être : `omni_explorer.zip` et des caches `.gradle`.

### MOYEN

- `unified_editor_screen.dart` fait **2 106 lignes** : cinq modes d'édition, hex, texte enrichi, terminal, arborescence de projet et autocomplétion dans un seul `State`. Le Provider expose une classe privée `_UTab` en contournant les règles d'analyse (`// ignore`).
- Autocomplétion : un `split('\
')` du texte entier et un `setState` de tout l'écran à chaque frappe. La comparaison `sug != _completions` compare les références des listes, donc elle est toujours vraie. Le résultat : lenteur sur les gros fichiers.
- Éditeur :
  - Seul l'UTF-8 est géré ; un fichier Latin-1 ne s'ouvre pas.
  - Le comportement des fins de ligne CRLF n'a pas été vérifié.
  - Rien ne prévient des modifications non sauvegardées quand on quitte l'app.
  - Les fichiers `.docx` et `.odt` sont traités comme du texte.
  - Le mode texte enrichi écrit un fichier annexe `.fmt` à côté du fichier de l'utilisateur.
- Gestion des erreurs : 50 `catch (_)`, dont 33 vides. Le déplacement vers la corbeille n'est pas attendu (pas de `await`) et le message de succès s'affiche même en cas d'échec. Les erreurs de collage sont seulement journalisées. Aucun isolate n'est utilisé.
- La copie de dossier suit les liens symboliques, ce qui peut boucler à l'infini.
- Le Markdown charge les images distantes (pixels de suivi) quand on ouvre un `.md` local.

### FAIBLE

- 13 remarques de l'analyseur dans `lib/`.
- README obsolète (il mentionne `chewie` et une arborescence qui n'existe plus).
- 36 `debugPrint`.

# Étape B : plan priorisé

Chaque tâche se termine par : `flutter analyze` sans erreur, les tests de la tâche au vert, et un commit atomique.

### P0 : sécurité et intégrité des données

| Tâche | Fichiers | Tests | Critère d'acceptation |
|---|---|---|---|
| **0.0** Mettre en sécurité ton travail en cours (branche + commit), nettoyer `.gitignore` et le suivi Git, retirer `org.gradle.java.home`, remplacer le test Counter | `.gitignore`, `gradle.properties`, `test/` | Test de démarrage de l'app | `flutter test` passe, build APK debug réussi |
| **0.1** Utilitaire `SafePath` qui refuse `..`, les chemins absolus et les liens symboliques, appliqué à toutes les extractions | nouveau `core/utils/safe_path.dart`, `archive_service.dart` | Unitaires avec des archives piégées | Aucune écriture hors de `dest` |
| **0.2** Hex : refuser la sauvegarde d'un fichier tronqué, puis (en P2) lecture par pages | `unified_editor_screen.dart` | Unitaire | Un fichier de 40 Mo ne peut jamais être tronqué |
| **0.3** Opérations fichiers : vérifier les noms, gérer les conflits (renommer / remplacer / ignorer), ne pas suivre les liens symboliques, remonter les erreurs à l'utilisateur. Un seul `FileOperationsService` remplace le doublon `FileService` | `file_explorer_provider.dart`, `file_list_item.dart` | Unitaires sur un dossier temporaire | Aucun écrasement silencieux |
| **0.4** Corbeille : restauration inter-stockages, conflits, index mis à jour seulement après succès, `await` et vrai message d'erreur | `trash_service.dart`, `file_list_item.dart` | Unitaires | Aucun élément orphelin |
| **0.5** Écriture atomique (fichier `.tmp`, flush, puis renommage) pour l'éditeur et les archives | nouveau `atomic_write.dart` | Unitaires | Pas de fichier partiel en cas d'interruption |
| **0.6** Limites de taille à l'ouverture (avertissement, puis lecture seule ou mode hex) | `file_opener.dart`, éditeur | Widget | Pas de plantage mémoire sur un fichier de 2 Go |
| **0.7** Déplacer le mot de passe SSH vers le stockage sécurisé Android (Keystore), migrer puis effacer l'ancienne valeur, `allowBackup=false` et règles d'extraction de données, vérification de la clé du serveur SSH (TOFU : la première clé est mémorisée, puis vérifiée à chaque connexion) | `settings_service.dart`, `ssh_terminal_panel.dart`, manifeste | Unitaire sur la migration | Plus aucun secret dans les préférences |

### P1 : fonctionnalités prioritaires

1. **Coffre-fort, créé de zéro.**
   - **Crypto** : Argon2id avec des paramètres calibrés sur l'appareil, puis XChaCha20-Poly1305 ou AES-256-GCM.
   - **Format de fichier** : versionné (magic, version, paramètres KDF, sel, nonce, texte chiffré), avec migrations.
   - **Écriture** : atomique, avec une sauvegarde `.bak`.
   - **Biométrie** : `local_auth`, avec une clé enveloppée par le Keystore. Le mot de passe maître reste obligatoire.
   - **Protections** : captures d'écran bloquées (FLAG_SECURE), verrouillage automatique à l'inactivité et en arrière-plan, presse-papiers marqué sensible et effacé après 30 s, générateur de mots de passe.
   - **Gestion du coffre** : changement du mot de passe maître par re-chiffrement, export chiffré.
   - **Tests** : bon et mauvais mot de passe, coffre corrompu, écriture interrompue, migration.
2. **Éditeur de code :**
   - brancher la gouttière de numéros de ligne (`indicatorBuilder`) et la recherche/remplacement native de `re_editor` (`CodeFindController` : suivant, précédent, tout remplacer, expression régulière, casse) ;
   - autocomplétion en différé (debounce), sans reconstruire tout l'écran ;
   - détection de l'encodage (UTF-8 avec ou sans BOM, puis Latin-1 en secours) et conservation des fins de ligne CRLF ;
   - avertissement pour les modifications non sauvegardées ;
   - découper le fichier de 2 106 lignes en un widget par mode.
3. **Aperçu HTML et Go Live :**
   - serveur `dart:io` `HttpServer` écoutant **uniquement sur 127.0.0.1**, port choisi automatiquement, jeton aléatoire dans l'URL ;
   - fichiers servis uniquement depuis la racine du projet (via `SafePath`), types MIME corrects, erreurs 404 et 403 ;
   - rechargement automatique quand un fichier change (surveillance du dossier + SSE, c'est-à-dire une connexion que le serveur utilise pour pousser l'ordre de rechargement) ;
   - WebView dont la navigation est limitée à ce serveur local ; les liens externes s'ouvrent dans le navigateur ;
   - `networkSecurityConfig` autorisant le HTTP non chiffré pour 127.0.0.1 seulement ;
   - arrêt du serveur à la fermeture et en arrière-plan.
4. **Éditeur multimédia :**
   - réparer le plugin de miniatures (ou utiliser FFmpeg pour les générer) ;
   - passer les arguments à FFmpeg sous forme de liste (`executeWithArgumentsAsync`), ce qui règle le problème des apostrophes ;
   - enregistrer les résultats dans un dossier visible par l'utilisateur via MediaStore ;
   - export réellement indépendant de l'écran, avec annulation ;
   - gestion du cycle de vie de la caméra ;
   - éditeur audio : forme d'onde calculée par FFmpeg, fondus entrant et sortant, suppression d'un passage, lecture limitée à la zone de découpe.

### P2 : performances et architecture

- Archives en streaming (`InputFileStream` / `OutputFileStream`) dans un isolate, avec progression et annulation. 7z et RAR désactivés sur Android.
- Éditeur hex paginé (lecture par blocs avec `RandomAccessFile`, modifications gardées en mémoire à part, annuler/rétablir, recherche, insertion et suppression).
- Permissions :
  - retirer Bluetooth et `READ_DEVICE_CONFIG` ;
  - fonctionner en mode dégradé sans MANAGE_EXTERNAL_STORAGE ;
  - vérifier les permissions en cache plutôt qu'à chaque dossier.
- Supprimer le code mort et les 7 dépendances inutiles ; remplacer `flutter_markdown` ; documenter les paquets modifiés localement.
- CI GitHub Actions : format, analyse, tests, APK debug, puis APK release signé via des secrets documentés.

### P3 : UX et finitions

- Accessibilité et grandes polices, messages d'erreur homogènes, bouton d'annulation (undo) après une mise à la corbeille.
- `applicationId` définitif et signature de la version release.
- README à jour, tests d'intégration des parcours critiques.

## Décisions à valider avant l'étape C

1. **Ton travail en cours non commité** : je propose de le committer tel quel sur une branche `wip/media-editor`, puis de travailler sur des branches dédiées. D'accord ?
2. **Dépendances à ajouter** :
   - `sodium_libs` (libsodium natif ; Argon2id y est rapide, alors qu'une version pur Dart prendrait plusieurs secondes sur mobile) ;
   - `local_auth` ;
   - `flutter_secure_storage` ;
   - `webview_flutter`.

   Tu préfères peut-être `cryptography` (pur Dart, plus léger, mais Argon2id lent) plutôt que `sodium_libs` ?
3. **MANAGE_EXTERNAL_STORAGE** : on le garde (normal pour un explorateur de fichiers), mais l'app doit fonctionner en mode dégradé sans. Vises-tu une publication sur le Play Store ? Cela impose une déclaration spécifique à Google.
4. **Linux et Windows** : faut-il continuer à les maintenir ? Cela fixe le périmètre de la CI et des alternatives au 7z/RAR.

Dès que tu valides, je commence par la tâche P0.0 puis P0.1 à P0.7, dans l'ordre. Je peux aussi publier ce diagnostic sous forme de page partageable si tu veux le transmettre.
