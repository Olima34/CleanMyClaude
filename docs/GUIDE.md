# Clean My Claude : le guide complet

Tout ce que fait l'app, comment elle protège tes données, et comment la compiler toi-même. Pour l'installer, deux lignes suffisent : voir le [README](../README.md).

<p align="center">
  <img src="screenshots/dashboard.png" alt="Tableau de bord : score de santé, stockage, mémoire, processeur, batterie, analyse intelligente, activité en direct, conseils et état de chaque outil" width="900">
</p>

<table>
  <tr>
    <th>Lanceur (⌥Espace)</th>
    <th>Convertisseur</th>
  </tr>
  <tr>
    <td valign="top" align="center"><img src="screenshots/launcher-panel.png" alt="Lanceur : la recherche « facture » trouve un dossier et des PDF en un instant, avec l'aperçu du dossier sélectionné à droite"></td>
    <td valign="top"><img src="screenshots/converter.png" alt="Convertisseur : photos HEIC à convertir en JPEG sans localisation, vidéos en cours de compression"></td>
  </tr>
  <tr>
    <th>Traducteur</th>
    <th>Raccourcis</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/translator.png" alt="Traducteur : un texte français traduit en anglais sur le Mac, la liste des langues téléchargées ou à télécharger et l'historique"></td>
    <td valign="top"><img src="screenshots/hotkeys.png" alt="Raccourcis : des apps, un dossier, un site et une action ouverts par ⌃⌥⌘ + une lettre, avec des suggestions"></td>
  </tr>
  <tr>
    <th>Nettoyage du système</th>
    <th>Protection et confidentialité</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/cleanup.png" alt="Nettoyage : fichiers inutiles classés par catégorie, avec le détail des caches d'applications et les éléments verrouillés par une app ouverte"></td>
    <td valign="top"><img src="screenshots/protection.png" alt="Protection : bilan de sécurité de macOS (FileVault, coupe-feu, Gatekeeper, SIP, mises à jour…)"></td>
  </tr>
  <tr>
    <th>Mises à jour</th>
    <th>Assistant Claude</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/updates.png" alt="Mises à jour : paquets Homebrew, apps Sparkle, App Store et macOS, avec le journal d'une mise à jour en direct"></td>
    <td valign="top"><img src="screenshots/assistant.png" alt="Assistant : Claude explique pourquoi le Mac rame et propose deux actions à exécuter d'un clic"></td>
  </tr>
  <tr>
    <th>Boîte à outils</th>
    <th>Presse-papiers</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/toolbox.png" alt="Boîte à outils : sélecteur de couleur avec formats HEX, RGB, HSL, SwiftUI et nuances"></td>
    <td valign="top"><img src="screenshots/clipboard.png" alt="Presse-papiers : historique de textes, images et fichiers avec épingles et recherche"></td>
  </tr>
  <tr>
    <th>Réseau</th>
    <th>Fenêtres</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/network.png" alt="Réseau : Wi-Fi, adresses, test de débit et latence"></td>
    <td valign="top"><img src="screenshots/windows.png" alt="Fenêtres : moitiés, quarts, tiers et écrans, chacun avec son raccourci modifiable"></td>
  </tr>
  <tr>
    <th>Automatisations</th>
    <th>Applications</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/automation.png" alt="Automatisations : nettoyage planifié, purge de la Corbeille, rangement de Téléchargements et historique de santé"></td>
    <td valign="top"><img src="screenshots/apps.png" alt="Applications : inventaire avec taille, version, dernière ouverture, apps Intel et apps de l'App Store"></td>
  </tr>
  <tr>
    <th>Espace de stockage</th>
    <th>Optimisation</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/storage.png" alt="Stockage : carte proportionnelle du dossier personnel et liste de son contenu"></td>
    <td valign="top"><img src="screenshots/performance.png" alt="Optimisation : le Boost, température, consommation, fréquences des cœurs, apps passées sur les cœurs économes et diagnostic"></td>
  </tr>
  <tr>
    <th colspan="2">Menu d'état</th>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="screenshots/menubar-panel.png" alt="Menu d'état : processeur, mémoire, disque, batterie, réseau, apps gourmandes, interrupteurs Caféine, presse-papiers et fenêtres, actions express" width="300"></td>
  </tr>
</table>

<sub>Captures réalisées avec des données fictives (mode `--demo`) : ni les apps, ni les fichiers, ni les personnes montrés n'existent.</sub>

> *English: an all-in-one native macOS app that lives in the background: maintenance (cleanup, security audit, startup items, uninstaller, disk map), a Raycast-like launcher with instant file search and Quick Look previews, a file converter, an on-device or Claude-powered translator, app hotkeys, everyday tools, clipboard history, updates, network tools, window management, automations and a Claude assistant. The interface is in French.*

> Projet personnel et non officiel, sans lien avec Anthropic, MacPaw ni Raycast. « Claude » est une marque d'Anthropic, « CleanMyMac » une marque de MacPaw.

## Ce que fait l'app

### Entretien

| Section | Contenu |
| --- | --- |
| **Tableau de bord** | Score de santé sur 100, stockage, mémoire, processeur, batterie (santé, cycles), activité en direct, **analyse intelligente** qui passe tout en revue en une minute, conseils classés par utilité, et l'état de chaque outil |
| **Nettoyage du système** | Caches d'apps et de macOS, journaux, fichiers temporaires, Xcode (données dérivées, appareils, archives, simulateurs), caches npm / Yarn / pip / Homebrew / CocoaPods / Go / Cargo…, dépendances de **projets endormis** (`node_modules`, `.build`, `Pods`, `target`), caches de l'**app Claude** et journaux de **Claude Code**, caches des navigateurs et des apps Electron, Corbeille, pièces jointes Mail, installeurs oubliés, sauvegardes d'iPhone |
| **Protection et confidentialité** | Bilan de sécurité (FileVault, coupe-feu, Gatekeeper, SIP, XProtect, mises à jour, verrouillage, partages), audit des **éléments persistants** avec vérification des signatures, liste des **autorisations** (caméra, micro, écran, disque…), effacement des **traces** (éléments récents, téléchargements, vignettes, Terminal, historique et cookies des navigateurs) |
| **Optimisation** | **Boost** (les apps en arrière-plan passent sur les cœurs économes : modes Intelligent, Performance et Fraîcheur, réflexe thermique, mode Jeu de macOS), **capteurs** sans mot de passe (température du processeur et du GPU, consommation du Mac en watts, fréquences des cœurs, ventilateurs), diagnostic « ce qui ralentit ou chauffe ton Mac », **benchmark** (processeur, GPU en images par seconde, mémoire, SSD, réactivité, test du Boost, endurance thermique, historique), réglages de **fluidité** réversibles (animations, Dock, Finder, compteur FPS des jeux, fréquence des écrans), moniteur temps réel, éléments au démarrage, tâches de maintenance |
| **Mises à jour** | **Homebrew** en un clic (sortie en direct, annulable ; les paquets qui demandent un mot de passe sont signalés avec la commande à copier), apps **Sparkle** (lecture de leur flux, l'app s'installe elle-même), **App Store** et **macOS** |
| **Applications** | Inventaire avec taille, version, dernière ouverture, apps **Intel** qui passent par Rosetta, désinstallation **complète** (l'app et tous ses fichiers dans `~/Library`), restes d'apps déjà supprimées |
| **Espace de stockage** | Carte proportionnelle cliquable de n'importe quel dossier, gros fichiers anciens, **doublons** (comparaison du contenu par SHA-256) |

### Outils

| Section | Contenu |
| --- | --- |
| **Lanceur** | `⌥Espace` partout, comme Spotlight ou Raycast : apps classées par fréquence, **fichiers trouvés instantanément** avec leur **aperçu Quick Look** à côté (voir plus bas), parcours des dossiers (`~/Documents/`, ⇥ pour entrer), recherche dans le contenu (`dans devis cuisine`), **calculatrice** (virgule française acceptée), **unités** (`10 km en miles`, `5 Go en Mo`, `100 °F en °C`), **traduction** (`trad bonjour en espagnol`, ou le **Traducteur directement dans le panneau** : tu tapes, la traduction suit, ↩ la copie, ⇥ change de langue, ⌘↩ demande à Claude), heure dans le monde, veille, verrouillage, mode sombre, éjection des disques, `quitter Slack`, recherche web (`g`, `ddg`, `yt`, `gh`, `wiki`, `maps`, `gtrad`), réglages système, emoji, et **toutes les actions de l'app** (`caféine 1h`, `mdp 24`, `#ff8800`, `qr …`, `cb …`, `gauche`, `? une question pour Claude`…) |
| **Raccourcis** | Un raccourci clavier pour ouvrir **n'importe quelle app** (appuie de nouveau : elle se masque), un fichier, un dossier, un site ou **n'importe quelle action de l'app** : la liste « Tout associer » les propose toutes, et dans le lanceur **⌘K** donne un raccourci au résultat choisi (affiché ensuite à droite, comme dans Raycast). Un raccourci sur « Traducteur » ou « Traduire le presse-papiers » ouvre directement le panneau de traduction. Un clic sur une suggestion donne `⌃⌥⌘` + une lettre libre du nom, adaptée à ton clavier (AZERTY ou QWERTY). Aucune autorisation nécessaire |
| **Convertisseur** | **Aperçu du résultat réel avant d'enregistrer** : l'opération tourne pour de vrai sur le fichier choisi, dans un dossier temporaire, et le rendu s'affiche à côté de l'original (images, PDF page par page, vidéo dans le lecteur de macOS, sur un morceau au choix (10 s, 30 s, 1 min ou tout) à partir du passage voulu, avec la taille estimée ; son et GIF en entier, son, documents, contenu d'une archive, texte reconnu), avec la taille avant et après. Enregistrement dans **Téléchargements** (par défaut), à côté des originaux ou dans un dossier choisi. Glisser-déposer, lanceur, Dock ou clic droit dans le Finder (**Services › Convertir avec Clean My Claude**). Images (HEIC, JPEG, PNG, AVIF, TIFF, GIF, BMP, PDF, JPEG 2000 ; redimensionner, compresser, **retirer le GPS** sans recompresser), vidéo (H.264, HEVC, MOV ↔ MP4 sans réencodage, **vidéo → GIF**, extraction de l'audio), audio (AAC, ALAC, WAV, AIFF, FLAC), PDF (fusionner, découper, pivoter, alléger, images ↔ PDF), documents (Word, RTF, HTML, TXT, ODT, Markdown → HTML ou PDF), ZIP, **renommage par lot** avec aperçu, **OCR** en français et en anglais, QR codes. MP3, OGG, MKV ou WebM si `ffmpeg` est installé |
| **Traducteur** | Deux moteurs : **Apple, sur ton Mac**, hors ligne et instantané (les langues se téléchargent une fois depuis la page), ou **Claude** pour le ton (neutre, formel, familier) et les nuances. Détection de la langue, inversion, historique local, et traduction en direct dans le lanceur |
| **Boîte à outils** | Pipette et conversions de couleurs, mots de passe et phrases de passe (copie confidentielle effacée au bout de 90 s), empreintes SHA et MD5 de fichiers, Base64, URL, JSON, casse, compteur de mots, Lorem ipsum, UUID, horodatages, et **Caféine** pour empêcher la veille (aussi depuis le menu d'état) |
| **Presse-papiers** | Historique des textes, images et fichiers copiés, épingles, recherche, rappel depuis le lanceur (`cb …`). **Désactivé tant que tu ne l'actives pas**, il ignore les mots de passe et ce qui est copié depuis un gestionnaire de mots de passe |
| **Réseau** | Wi-Fi (signal, bruit, canal, débit), adresses locales et publique, **test de débit** (`networkQuality` d'Apple), latence en direct, **ports ouverts** et l'app qui les écoute |

### Contrôle et Claude

| Section | Contenu |
| --- | --- |
| **Fenêtres** | Moitiés, tiers, deux tiers, quarts, plein écran, centrer, écran suivant ou précédent, taille précédente, au clavier (`⌃⌥` + flèches…) ou depuis le lanceur. Appuyer de nouveau fait défiler ½, ⅔ et ⅓. Raccourcis modifiables, marge réglable |
| **Automatisations** | Nettoyage planifié (seulement le « sans risque »), purge de la Corbeille au-delà de N jours, **rangement de Téléchargements** par règles, historique de santé du Mac en graphiques, journal. Tout est désactivé au départ et chaque automatisation montre un **aperçu à blanc** avant de s'activer. Elles tournent tant que l'app est ouverte (fenêtre fermée comprise) |
| **Assistant Claude** | Pose tes questions sur ton Mac en langage naturel : Claude explique et propose jusqu'à trois actions de l'app, que tu lances d'un clic. « Demander à Claude » est aussi dans le clic droit d'un processus, d'un agent de démarrage ou d'un dossier, et dans le lanceur (`?`) |
| **Menu d'état** | Dans la barre des menus : processeur, mémoire, disque, réseau, batterie, apps gourmandes, interrupteurs (Caféine, presse-papiers, fenêtres) et actions express. Alertes optionnelles si le disque est presque plein ou la mémoire saturée |

## Le Boost, mesuré

macOS range chaque processus dans une bande de priorité. Celle de l'arrière-plan (`PRIO_DARWIN_BG`, celle de `taskpolicy -b`) fait tourner un processus sur les **cœurs économes** de la puce, avec des accès disque et réseau ralentis. Le Boost y place ce que tu ne regardes pas, et rend sa priorité à une app **dès qu'elle revient au premier plan** (sans attendre), dès qu'elle joue ou enregistre du son, ou quand tu changes de mode. Mesuré sur un MacBook Air M2 sans ventilateur, avec huit tâches lourdes en fond :

| | Sans Boost | Avec le Boost |
| --- | --- | --- |
| Vitesse de l'app au premier plan | 70 % de sa vitesse seule | 102 % |
| Consommation du Mac | 17 W | 5,8 W |
| Température du processeur, après quelques secondes | 83 °C et en hausse | 54 °C |
| Attente d'une tâche urgente avant d'avoir un cœur (99 % des cas) | 4,7 ms : des images sautent | 0,1 ms |

Les tâches de fond continuent, plus lentement. L'onglet **Benchmark › Test du Boost** refait cette mesure sur ton Mac en dix secondes.

- **Intelligent** : seules les apps qui s'emballent (plus de 15 % de processeur pendant 20 s) passent sur les cœurs économes ; tout l'arrière-plan quand macOS signale que la puce chauffe, et le mode Performance quand un jeu est au premier plan.
- **Performance** : tout ce qui est en arrière-plan, pour un jeu, un export ou une compilation ; peut forcer le **mode Jeu** de macOS (avec Xcode installé).
- **Fraîcheur** : comme Performance, et l'économie d'énergie de macOS (mot de passe), remise comme avant en quittant ce mode.

Jamais ralentis : l'app au premier plan et ce qu'elle a lancé (une compilation depuis le Terminal), les apps qui jouent ou enregistrent du son (appels, musique), celles qui surveillent le clavier, le Finder, le Dock et tout composant de macOS, ce que macOS garde déjà lui-même en arrière-plan, et une liste d'apps dont le travail en fond compte (OBS, Final Cut Pro, Logic Pro, DaVinci Resolve, HandBrake, Blender, Xcode, machines virtuelles…), modifiable. Chaque processus déplacé est noté avec son heure de démarrage : un numéro de processus réutilisé n'est jamais touché, tout est rétabli quand l'app quitte, et au lancement suivant après un plantage. Le gouverneur ne travaille qu'une dizaine de millisecondes toutes les dix secondes, et pas du tout quand le Boost est désactivé.

## Les garde-fous

Un nettoyeur qui supprime trop, c'est pire que pas de nettoyeur. Clean My Claude est prudent par construction :

- **Rien n'est supprimé sans ton accord.** Les analyses sont en lecture seule ; chaque nettoyage passe par une confirmation qui dit ce qui part et comment.
- **Une seule porte de sortie.** Toutes les suppressions passent par `Remover`, qui refuse tout ce qui n'est pas dans ton dossier personnel (et `~/Library` lui-même, les trousseaux, Mail, Messages, iCloud Drive, Photos…). `CleanMyClaude --selftest` vérifie ces règles et que le catalogue ne propose jamais un chemin protégé ; le script de build le lance à chaque compilation.
- **La Corbeille d'abord.** Seuls les caches et journaux que les apps recréent sont supprimés directement. Tes fichiers, les apps désinstallées, les doublons partent dans la Corbeille.
- **Jamais d'écrasement.** Conversions, renommages et rangements écrivent toujours un nouveau fichier (`photo 2.jpg` si `photo.jpg` existe) ; tes originaux ne bougent pas.
- **Une seule porte de confirmation.** Les commandes risquées du lanceur, des liens `cleanmyclaude://` ou de l'assistant demandent toujours ton accord ; Claude ne peut proposer que des actions sans danger.
- **Les apps ouvertes sont respectées.** Les caches de Claude, Chrome, Slack… sont verrouillés tant que l'app tourne.
- **Un journal** de chaque action : `~/Library/Logs/CleanMyClaude/actions.log`.

### Rien ne sort sans ton clic

Tes fichiers, ton historique de presse-papiers et l'état de ton Mac restent sur ton Mac. Les connexions partent quand tu cliques, et chacune dit ce qu'elle fait. Une seule exception, que tu peux couper : Clean My Claude demande à GitHub s'il existe une nouvelle version de lui-même (voir plus bas).

| Quand | Vers qui | Quoi |
| --- | --- | --- |
| « Vérifier » dans Mises à jour, bilan de sécurité | Apple (`softwareupdate`, `itunes.apple.com/lookup`), les flux Sparkle de tes apps, Homebrew | Les noms et versions de tes apps |
| « Lancer le test » dans Réseau | Apple (`networkQuality`) | Un test de débit |
| « Afficher » l'IP publique | `api.ipify.org` | Aucune donnée : il te renvoie ton adresse |
| Une question à l'assistant | Anthropic, via ton abonnement Claude ou ta clé API | Ta question ; l'état du Mac (charge, espace, apps gourmandes) seulement si tu actives « Consulter l'état du Mac » |
| « Traduire avec Claude » | Anthropic, via ton abonnement Claude ou ta clé API | Le texte à traduire (la traduction Apple, elle, reste sur ton Mac) |
| Une recherche web dans le lanceur | Ton navigateur | Ce que tu as tapé, comme dans la barre d'adresse |
| Au lancement, puis toutes les 6 h (désactivable) | GitHub (`api.github.com`) | Rien : l'app lit le numéro de sa dernière version publiée et, s'il est plus récent, la liste des changements |
| « Mettre à jour » dans le panneau de nouvelle version | GitHub (`github.com`) | Rien : l'app télécharge l'archive publiée |

## La recherche de fichiers, en un millième de seconde

Spotlight met une à quatre secondes à répondre à une recherche par nom : trop lent pour suivre la frappe. Le lanceur garde donc **en mémoire les noms des fichiers** de ton dossier personnel et d'iCloud Drive (environ 2 Mo pour 100 000 fichiers), lus une fois en arrière-plan en quelques secondes, puis **tenus à jour en direct** : macOS (FSEvents) signale les dossiers qui changent et seuls ceux-là sont relus.

| Mesuré sur un Mac de 116 000 fichiers | Temps |
| --- | --- |
| Spotlight, nom contenant « facture » | 0,9 s |
| Spotlight, nom contenant « png » | 3,6 s |
| Index du lanceur, n'importe quelle recherche | 1 à 3 ms |
| Construction de l'index (une fois, au lancement) | 2,8 s |

Le classement favorise le nom exact, puis le début du nom, puis le début d'un mot ; ensuite les fichiers modifiés récemment, ceux du Bureau, des Documents, des Téléchargements et d'iCloud Drive, et ceux que tu ouvres souvent. Un mot peut viser un dossier : `edf mars` trouve `Factures/EDF/mars.pdf`. Les dossiers cachés, `~/Library` et les dépendances (`node_modules`, `Pods`…) sont laissés de côté, et l'intérieur des paquets (`.app`, `.photoslibrary`…) n'est pas parcouru. L'index ne quitte jamais la mémoire de ton Mac. Spotlight reste utilisé pour chercher dans le contenu (`dans …`).

## Toujours là, sans prendre de place

Comme Raycast, Clean My Claude n'a pas d'icône dans le Dock : il vit dans la barre des menus et derrière `⌥Espace`. Il s'ouvre à l'ouverture de session sans afficher de fenêtre (réglable), et sa fenêtre se rouvre depuis l'étincelle de la barre des menus, le lanceur ou en relançant l'app. Les réglages permettent de garder l'icône dans le Dock, toujours ou seulement quand la fenêtre est ouverte. Au repos, fenêtre ouverte et tous les modules actifs : environ 1,7 % de processeur et 93 Mo de mémoire.

## Mises à jour de Clean My Claude

Au lancement, puis toutes les 6 h tant que l'app tourne en arrière-plan, Clean My Claude demande à GitHub le numéro de sa **dernière version publiée** (la plus récente de la [page des versions](https://github.com/Olima34/CleanMyClaude/releases/latest)). Chaque push sur `main` en devient une : une fois la compilation et les autotests réussis sur GitHub, la CI publie l'app sous un nouveau numéro, environ 7 minutes après le push. S'il est plus récent que le tien, la fenêtre de Clean My Claude s'ouvre avec un panneau en son centre, l'app légèrement assombrie derrière : tant que tu n'y as pas répondu (ou fermé avec Échap), le reste de la fenêtre ne réagit plus. Le panneau liste **ce qui a changé**, c'est-à-dire les commits entre ta version et la nouvelle (les fusions sont laissées de côté, les points « - … » des messages deviennent des détails).

<p align="center"><img src="screenshots/selfupdate-window-panel.png" alt="La fenêtre de Clean My Claude assombrie, avec au centre le panneau de nouvelle version : ce qui change, puis Ignorer cette version, Plus tard et Mettre à jour" width="760"></p>

- **Mettre à jour** télécharge `CleanMyClaude.zip` depuis la version publiée, vérifie son empreinte SHA-256 (celle que GitHub a calculée à la publication), l'ouvre, contrôle que c'est bien Clean My Claude dans la version annoncée et que sa signature est intacte. Rien n'est remplacé avant que tu cliques sur **Installer et relancer** : l'ancienne version part alors à la Corbeille, la nouvelle prend sa place et se rouvre. Le téléchargement s'annule à tout moment ; une erreur dit ce qui s'est passé et ce qui n'a pas changé.
- **Plus tard** (ou ✕, ou Échap) ferme le panneau : il revient au prochain lancement (pas dans les 24 h qui suivent tant que l'app reste ouverte). Pendant un téléchargement, le fermer le masque seulement : il revient quand la nouvelle version est prête.
- **Ignorer cette version** : le panneau ne revient tout seul qu'à la version suivante. La page Mises à jour la montre toujours.
- **Les autorisations de macOS.** La version publiée est signée « ad hoc » (pas de certificat de développeur Apple) : macOS peut redemander l'Accessibilité ou l'accès complet au disque après la mise à jour. Si ta copie est signée avec le certificat local de `scripts/setup_signing.sh`, la nouvelle version est re-signée avec lui et garde ses autorisations.
- **Quand la mise à jour sur place est impossible** (app lancée depuis le code source, depuis une image disque, ou dans un dossier qui demande un mot de passe administrateur), le panneau le dit et propose la page de la version ou la commande d'installation à copier.

La vérification automatique se coupe dans **Réglages › Général** ou sur la page **Mises à jour**, où « Vérifier » la relance à la main.

**Les numéros de version.** Une version porte le numéro de la dernière étiquette `vX.Y.Z` augmenté du nombre de commits faits depuis : la v0.3.0 suivie de 6 commits donne la 0.3.6, puis chaque push avance le dernier chiffre (0.3.7, 0.3.8… 0.3.10). Une copie compilée chez toi avec `./scripts/build_app.sh` porte le même numéro que la version que GitHub publie pour le même commit. Elle n'est donc pas invitée à « se mettre à jour » vers ce qu'elle contient déjà, et une copie compilée sur un commit plus récent non plus. Si plusieurs pushes arrivent pendant qu'une version se publie, seul le dernier est publié : il contient les autres.

## Compiler toi-même

La version prête à l'emploi se télécharge depuis la [page des versions](https://github.com/Olima34/CleanMyClaude/releases/latest) (voir le [README](../README.md)). Pour compiler depuis le code :

Prérequis : macOS 14 (Sonoma) ou plus récent, et les outils de développement d'Apple (Xcode 15.3 ou plus, ou simplement `xcode-select --install`).

```bash
git clone https://github.com/Olima34/CleanMyClaude.git
cd CleanMyClaude
./scripts/build_app.sh
```

Le script compile en release, vérifie les garde-fous, génère l'icône, assemble `Clean My Claude.app` et l'installe dans `~/Applications` (`--no-install` la laisse dans `build/`, `--zip` produit une archive, `--universal` compile pour Apple Silicon et Intel). Le numéro de version vient de `CMC_VERSION`, sinon de `scripts/version.sh` (la dernière étiquette `vX.Y.Z` plus les commits depuis) ; le commit compilé est noté dans l'app (`CMCCommit`), qui s'en sert pour lister ce qu'une nouvelle version change et pour ne pas proposer une version plus ancienne que ce qu'elle contient.

Publier une version : il suffit de pousser sur `main`. Le workflow `Build` compile l'app universelle (Apple Silicon et Intel) et vérifie ses garde-fous. S'il réussit, il la dépose sur la page des versions sous le numéro suivant, avec en notes la liste des commits depuis la version précédente. Le bouton du README et `scripts/install.sh` vont l'y chercher, et les apps déjà installées la trouvent au lancement ou dans les 6 h. Pour changer de numéro mineur ou majeur, pousse une étiquette avec le commit : `git tag v0.4.0 && git push origin main v0.4.0`. Le workflow `Release` publie alors la 0.4.0, et les pushes suivants donnent 0.4.1, 0.4.2…

### Les autorisations

Aucune n'est obligatoire : chacune est demandée dans la section qui en a besoin, au moment où tu t'en sers. Ou toutes d'un coup : **Réglages › Autorisations › Tout autoriser** (aussi sur l'écran d'accueil). macOS pose alors ses questions l'une après l'autre, puis ouvre Réglages Système au bon endroit pour les deux qui s'activent à la main (accès complet au disque et accessibilité) ; l'app attend que l'interrupteur soit mis, ou que tu cliques sur « Passer ».

| Autorisation | Pour quoi faire |
| --- | --- |
| **Accès complet au disque** (recommandé) | Voir la Corbeille, Mail, Safari et la liste des autorisations de tes apps, et indexer tes fichiers sans que macOS demande dossier par dossier |
| **Accessibilité** | Ranger les fenêtres au clavier, coller directement depuis l'historique du presse-papiers |
| **Bureau, Documents, Téléchargements** | Index des fichiers du lanceur, rangement de Téléchargements, conversions (inutile avec l'accès complet au disque) |
| **Piloter le Finder et Événements système** | Corbeille des apps installées par un administrateur, mode sombre, redémarrer, éteindre depuis le lanceur |
| **Localisation** | Afficher le nom du réseau Wi-Fi (ta position n'est jamais lue) |
| **Réseau local** | Mesurer la latence de ta box et des appareils de ton réseau |
| **Notifications** | Alertes de disque ou de mémoire, bilan des automatisations |

### Garder les autorisations après chaque compilation

Signée « ad hoc » (par défaut), l'app change d'identité à chaque compilation : macOS la prend pour une nouvelle app et oublie ses autorisations. Pour qu'il s'en souvienne, crée une fois pour toutes un certificat de signature local :

```bash
./scripts/setup_signing.sh
```

Le script ajoute à ton trousseau de session un certificat auto-signé « Clean My Claude Dev » (valable 10 ans, clé non exportable, réservée à `codesign`, aucun réglage de confiance modifié). `build_app.sh` l'utilise ensuite tout seul. À la première compilation, macOS demande une fois si `codesign` peut utiliser la clé : saisis ton mot de passe de session et choisis « Toujours autoriser ». Accorde ensuite les autorisations une dernière fois : elles restent acquises après chaque reconstruction. Pour le retirer : `security delete-identity -c "Clean My Claude Dev"`. Une autre identité reste possible avec `CMC_SIGN_IDENTITY="…" ./scripts/build_app.sh`.

### Connecter l'assistant Claude

Deux possibilités, au choix dans la section **Assistant Claude** :

- **Ton abonnement Claude (Pro ou Max), sans clé API.** L'assistant passe par Claude Code, livré avec l'[app Claude](https://claude.ai/download). Clique sur « Connecter Claude » : un Terminal s'ouvre, tu valides dans le navigateur, c'est fait. Claude Code y tourne bridé : aucun outil, aucun accès à tes fichiers, aucune session conservée, une réponse au format imposé. Les messages comptent dans ton quota d'abonnement.
- **Une clé API Anthropic**, rangée dans ton Trousseau, facturée à l'usage (coût affiché après chaque réponse).

Modèles proposés : Opus (par défaut), Sonnet, Haiku et Fable.

### Piloter l'app depuis Raccourcis, Raycast ou le Terminal

```bash
open "cleanmyclaude://launcher"                 # ouvre le lanceur
open "cleanmyclaude://page/converter"           # ouvre une section
open "cleanmyclaude://run/act_smart_scan"       # lance une commande du lanceur (les actions risquées demandent confirmation)
```

## Cinq thèmes, et le tien

Réglages (⌘,) › Apparence change toute l'app d'un clic, fenêtre, lanceur et menu d'état compris :

| Thème | Le style |
| --- | --- |
| **Atelier** | Le thème d'origine : papier chaud, titres à empattements, bleu Claude. Suit le mode clair ou sombre de macOS. |
| **Graphite** | Le contraire d'une app d'IA : gris neutres, une seule encre, angles droits, aucune ombre, ni icônes décoratives, ni étincelle, ni mascotte. |
| **Phosphore** | Un vieux terminal : verre noir, lettres vertes, tout en chasse fixe, couleurs ANSI. Toujours sombre. |
| **Sorbet** | Pastel et joueur : police arrondie, angles très ronds, couleurs acidulées, ombres douces. Toujours clair. |
| **Minuit** | Bleu nuit profond, reflets violets et turquoise, titres fins, angles adoucis. Toujours sombre. |

« Créer mon thème » part de n'importe lequel et règle tout : le mode (comme macOS, clair ou sombre), les dix-neuf couleurs de chaque variante et les dix des graphiques (au sélecteur ou en hexadécimal, avec « Harmoniser » qui déduit les nuances du fond, du texte et de l'accent), la police des titres et du texte, leur graisse et leur taille, l'arrondi des angles, l'épaisseur des bordures, les ombres, les icônes décoratives (en couleur, monochromes ou masquées), le motif de caractères et la mascotte. Un thème se copie en JSON pour le sauvegarder ou le partager, et « Coller un thème » le recrée.

<table>
  <tr>
    <th>Graphite</th>
    <th>Phosphore</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/theme-graphite.png" alt="Tableau de bord en thème Graphite : gris neutres, angles droits, sans icônes ni mascotte"></td>
    <td valign="top"><img src="screenshots/theme-phosphore.png" alt="Tableau de bord en thème Phosphore : fond noir, texte vert en chasse fixe"></td>
  </tr>
  <tr>
    <th>Sorbet</th>
    <th>Minuit</th>
  </tr>
  <tr>
    <td valign="top"><img src="screenshots/theme-sorbet.png" alt="Tableau de bord en thème Sorbet : pastels, police arrondie, angles très ronds"></td>
    <td valign="top"><img src="screenshots/theme-minuit.png" alt="Tableau de bord en thème Minuit : bleu nuit, accents violets et turquoise"></td>
  </tr>
  <tr>
    <th colspan="2">Réglages › Apparence</th>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="screenshots/appearance-panel.png" alt="Réglages › Apparence : les cinq thèmes de base en miniature et la création d'un thème personnel" width="560"></td>
  </tr>
</table>

## Pour les développeurs

```bash
swift build
.build/debug/CleanMyClaude --selftest             # garde-fous de suppression et autotests de chaque module
.build/debug/CleanMyClaude --dump                 # ce que trouve chaque scanner, sans rien supprimer
.build/debug/CleanMyClaude --dump --only cleanup  # cleanup | security | apps | processes, ou le nom d'un module
.build/debug/CleanMyClaude --dump --storage ~/Developer --duplicates ~/Downloads
.build/debug/CleanMyClaude --snapshot out/        # rend chaque page en PNG (--page, --tab, --light, --theme graphite, --scale 2)
.build/debug/CleanMyClaude --ask "Pourquoi mon Mac chauffe ?" --model haiku   # une question à l'assistant
.build/debug/CleanMyClaude --translate "Merci pour ton aide" --to en --tone formal   # le traducteur, moteur Claude
.build/debug/CleanMyClaude --dump --only launcher # construit l'index des fichiers et chronomètre quelques recherches
.build/debug/CleanMyClaude --dump --only performance   # capteurs, énergie, réglages, et ce que chaque mode du Boost ralentirait
.build/release/CleanMyClaude --dump --only performance --bench --boost-test   # le benchmark et le test du Boost
.build/debug/CleanMyClaude --dump --only performance --boost-live-test   # le mode Performance pour de vrai, 3 s, vérifié dans le noyau
.build/debug/CleanMyClaude --update-check --as-version 0.2.0   # ce que GitHub publie, comparé à une version au choix
.build/debug/CleanMyClaude --update-install "build/essai/Clean My Claude.app"   # met à jour cette copie de bout en bout (sans relancer)
.build/debug/CleanMyClaude --demo                 # lance l'app avec des données fictives, sans lire le disque
```

`--demo` fonctionne aussi avec `--dump` et `--snapshot`. Les données de démonstration décrivent un Mac inventé : un dossier personnel fictif, des apps aux noms et icônes inventés, leurs caches, processus, agents de démarrage, mises à jour, conversions et historique de presse-papiers. En mode démo, aucun scanner ne lit le disque, aucune commande ni requête n'est lancée et `Remover` refuse toute suppression ; `--selftest --demo` le vérifie sur un fichier témoin. Les captures de ce README en sortent :

```bash
for p in dashboard cleanup protection performance apps storage menubar updates converter translator hotkeys toolbox clipboard network windows automation assistant; do
  .build/debug/CleanMyClaude --snapshot docs/screenshots --demo --scale 2 --page $p
done
.build/debug/CleanMyClaude --snapshot docs/screenshots --demo --scale 2 --page launcher --query facture
.build/debug/CleanMyClaude --snapshot docs/screenshots --demo --scale 2 --page appearance
for t in graphite phosphore sorbet minuit; do
  .build/debug/CleanMyClaude --snapshot /tmp/theme-$t --demo --page dashboard --theme $t && mv /tmp/theme-$t/dashboard.png docs/screenshots/theme-$t.png
done
rm docs/screenshots/menubar.png docs/screenshots/launcher.png docs/screenshots/onboarding-panel.png docs/screenshots/selfupdate-panel.png
pngquant --quality 80-95 --force --ext .png docs/screenshots/*.png   # optionnel : divise le poids par quatre
```

Pendant `--snapshot`, les menus, champs de texte, interrupteurs, zones de dépôt et de défilement d'AppKit sont remplacés par des équivalents dessinés en SwiftUI : `ImageRenderer` les rendrait en rectangles jaunes ou vides.

Le code, en SwiftUI pur, sans dépendance :

```
Sources/CleanMyClaude/
├── App/        point d'entrée, scènes, modèle global, registre des modules, outils en ligne de commande
├── Core/       mesures système, tailles via fts(3), Shell, Remover, FileOps, HTTP, commandes du lanceur,
│               raccourcis globaux, panneaux flottants, stockage, Trousseau, notifications, planificateur
├── Features/   une section par dossier : Dashboard, Cleanup, Protection, Performance, Updates, Apps, Storage,
│               Launcher, Hotkeys, Converter, Translator, Toolbox, Clipboard, Network, Windows, Automation,
│               Assistant, MenuBar
└── UI/         thèmes (catalogue, réglages, éditeur) et composants partagés avec ClaudeStats
```

Chaque module de `Features/` se branche sur `App/ModuleRegistry.swift` (commandes du lanceur, données de démo, autotests, captures, interrupteurs du menu d'état). Les règles pour en écrire un sont dans [`CLAUDE.md`](../CLAUDE.md).

Le thème Atelier reprend le design de [ClaudeStats](https://github.com/Olima34/ClaudeStats) : surfaces chaudes, titres en serif, accent bleu, étincelle et créature de Claude. Les vues lisent tout dans `Theme` (couleurs, `Theme.r(…)` pour les angles, `PillShape` pour les capsules, `Theme.line` pour les bordures, `Theme.icons` pour les icônes décoratives) : `ThemeStore` est observable, changer de thème redessine l'app sans la relancer.

## Feuille de route

- Automatisations même quand l'app est fermée (agent de connexion)
- Vue en rayons de soleil pour la carte du disque
- Application notarisée par Apple (plus besoin d'« Ouvrir quand même ») et mises à jour automatiques
- Localisation en anglais

## Licence

[MIT](../LICENSE). Utilise-le à tes risques : relis ce que tu coches avant de nettoyer.
