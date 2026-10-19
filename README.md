<p align="center">
  <img src="docs/icon.png" alt="Icône de Clean My Claude : la petite créature pixel de Claude Code balaie des fichiers qui s'envolent" width="200">
</p>

<h1 align="center">Clean My Claude</h1>

<p align="center"><b>« Claude, nettoie mon Mac. » Et tant qu'à faire, tout le reste.</b><br>
L'app Mac tout-en-un, native et sans dépendance : entretien façon CleanMyMac, lanceur façon Raycast avec recherche de fichiers instantanée,<br>
convertisseur, traducteur, raccourcis d'apps, outils du quotidien, mises à jour, réseau, fenêtres, automatisations et un assistant Claude.<br>
Toujours là en arrière-plan, sans icône dans le Dock. Libre, gratuite, et rien ne sort de ton Mac sans ton clic.</p>

<p align="center">
  <img src="docs/screenshots/dashboard.png" alt="Tableau de bord : score de santé, stockage, mémoire, processeur, batterie, analyse intelligente, activité en direct, conseils et état de chaque outil" width="900">
</p>

<table>
  <tr>
    <th>Lanceur (⌥Espace)</th>
    <th>Convertisseur</th>
  </tr>
  <tr>
    <td valign="top" align="center"><img src="docs/screenshots/launcher-panel.png" alt="Lanceur : la recherche « facture » trouve un dossier et des PDF en un instant, avec l'aperçu du dossier sélectionné à droite"></td>
    <td valign="top"><img src="docs/screenshots/converter.png" alt="Convertisseur : photos HEIC à convertir en JPEG sans localisation, vidéos en cours de compression"></td>
  </tr>
  <tr>
    <th>Traducteur</th>
    <th>Raccourcis</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/translator.png" alt="Traducteur : un texte français traduit en anglais sur le Mac, la liste des langues téléchargées ou à télécharger et l'historique"></td>
    <td valign="top"><img src="docs/screenshots/hotkeys.png" alt="Raccourcis : des apps, un dossier, un site et une action ouverts par ⌃⌥⌘ + une lettre, avec des suggestions"></td>
  </tr>
  <tr>
    <th>Nettoyage du système</th>
    <th>Protection et confidentialité</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/cleanup.png" alt="Nettoyage : fichiers inutiles classés par catégorie, avec le détail des caches d'applications et les éléments verrouillés par une app ouverte"></td>
    <td valign="top"><img src="docs/screenshots/protection.png" alt="Protection : bilan de sécurité de macOS (FileVault, coupe-feu, Gatekeeper, SIP, mises à jour…)"></td>
  </tr>
  <tr>
    <th>Mises à jour</th>
    <th>Assistant Claude</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/updates.png" alt="Mises à jour : paquets Homebrew, apps Sparkle, App Store et macOS, avec le journal d'une mise à jour en direct"></td>
    <td valign="top"><img src="docs/screenshots/assistant.png" alt="Assistant : Claude explique pourquoi le Mac rame et propose deux actions à exécuter d'un clic"></td>
  </tr>
  <tr>
    <th>Boîte à outils</th>
    <th>Presse-papiers</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/toolbox.png" alt="Boîte à outils : sélecteur de couleur avec formats HEX, RGB, HSL, SwiftUI et nuances"></td>
    <td valign="top"><img src="docs/screenshots/clipboard.png" alt="Presse-papiers : historique de textes, images et fichiers avec épingles et recherche"></td>
  </tr>
  <tr>
    <th>Réseau</th>
    <th>Fenêtres</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/network.png" alt="Réseau : Wi-Fi, adresses, test de débit et latence"></td>
    <td valign="top"><img src="docs/screenshots/windows.png" alt="Fenêtres : moitiés, quarts, tiers et écrans, chacun avec son raccourci modifiable"></td>
  </tr>
  <tr>
    <th>Automatisations</th>
    <th>Applications</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/automation.png" alt="Automatisations : nettoyage planifié, purge de la Corbeille, rangement de Téléchargements et historique de santé"></td>
    <td valign="top"><img src="docs/screenshots/apps.png" alt="Applications : inventaire avec taille, version, dernière ouverture, apps Intel et apps de l'App Store"></td>
  </tr>
  <tr>
    <th>Espace de stockage</th>
    <th>Optimisation</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/storage.png" alt="Stockage : carte proportionnelle du dossier personnel et liste de son contenu"></td>
    <td valign="top"><img src="docs/screenshots/performance.png" alt="Optimisation : jauges du processeur et de la mémoire, courbes en direct et apps les plus gourmandes"></td>
  </tr>
  <tr>
    <th colspan="2">Menu d'état</th>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="docs/screenshots/menubar-panel.png" alt="Menu d'état : processeur, mémoire, disque, batterie, réseau, apps gourmandes, interrupteurs Caféine, presse-papiers et fenêtres, actions express" width="300"></td>
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
| **Optimisation** | Moniteur temps réel, apps les plus gourmandes (processus d'aide regroupés par app), éléments au démarrage activables ou désactivables, tâches de maintenance (mémoire, DNS, Launch Services, Spotlight, instantanés Time Machine…) |
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

Tes fichiers, ton historique de presse-papiers et l'état de ton Mac restent sur ton Mac. Les seules connexions partent quand tu cliques, et chacune dit ce qu'elle fait :

| Quand | Vers qui | Quoi |
| --- | --- | --- |
| « Vérifier » dans Mises à jour, bilan de sécurité | Apple (`softwareupdate`, `itunes.apple.com/lookup`), les flux Sparkle de tes apps, Homebrew | Les noms et versions de tes apps |
| « Lancer le test » dans Réseau | Apple (`networkQuality`) | Un test de débit |
| « Afficher » l'IP publique | `api.ipify.org` | Aucune donnée : il te renvoie ton adresse |
| Une question à l'assistant | Anthropic, via ton abonnement Claude ou ta clé API | Ta question ; l'état du Mac (charge, espace, apps gourmandes) seulement si tu actives « Consulter l'état du Mac » |
| « Traduire avec Claude » | Anthropic, via ton abonnement Claude ou ta clé API | Le texte à traduire (la traduction Apple, elle, reste sur ton Mac) |
| Une recherche web dans le lanceur | Ton navigateur | Ce que tu as tapé, comme dans la barre d'adresse |

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

## Installation

Prérequis : macOS 14 (Sonoma) ou plus récent, et les outils de développement d'Apple (Xcode 15.3 ou plus, ou simplement `xcode-select --install`).

```bash
git clone https://github.com/Olima34/CleanMyClaude.git
cd CleanMyClaude
./scripts/build_app.sh
```

Le script compile en release, vérifie les garde-fous, génère l'icône, assemble `Clean My Claude.app` et l'installe dans `~/Applications` (`--no-install` la laisse dans `build/`, `--zip` produit une archive).

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
    <td valign="top"><img src="docs/screenshots/theme-graphite.png" alt="Tableau de bord en thème Graphite : gris neutres, angles droits, sans icônes ni mascotte"></td>
    <td valign="top"><img src="docs/screenshots/theme-phosphore.png" alt="Tableau de bord en thème Phosphore : fond noir, texte vert en chasse fixe"></td>
  </tr>
  <tr>
    <th>Sorbet</th>
    <th>Minuit</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/theme-sorbet.png" alt="Tableau de bord en thème Sorbet : pastels, police arrondie, angles très ronds"></td>
    <td valign="top"><img src="docs/screenshots/theme-minuit.png" alt="Tableau de bord en thème Minuit : bleu nuit, accents violets et turquoise"></td>
  </tr>
  <tr>
    <th colspan="2">Réglages › Apparence</th>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="docs/screenshots/appearance-panel.png" alt="Réglages › Apparence : les cinq thèmes de base en miniature et la création d'un thème personnel" width="560"></td>
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
rm docs/screenshots/menubar.png docs/screenshots/launcher.png docs/screenshots/onboarding-panel.png
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

Chaque module de `Features/` se branche sur `App/ModuleRegistry.swift` (commandes du lanceur, données de démo, autotests, captures, interrupteurs du menu d'état). Les règles pour en écrire un sont dans [`CLAUDE.md`](CLAUDE.md).

Le thème Atelier reprend le design de [ClaudeStats](https://github.com/Olima34/ClaudeStats) : surfaces chaudes, titres en serif, accent bleu, étincelle et créature de Claude. Les vues lisent tout dans `Theme` (couleurs, `Theme.r(…)` pour les angles, `PillShape` pour les capsules, `Theme.line` pour les bordures, `Theme.icons` pour les icônes décoratives) : `ThemeStore` est observable, changer de thème redessine l'app sans la relancer.

## Feuille de route

- Automatisations même quand l'app est fermée (agent de connexion)
- Vue en rayons de soleil pour la carte du disque
- Application signée et notarisée à télécharger, avec mises à jour automatiques
- Localisation en anglais

## Licence

[MIT](LICENSE). Utilise-le à tes risques : relis ce que tu coches avant de nettoyer.
