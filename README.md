<p align="center">
  <img src="docs/icon.png" alt="Icône de Clean My Claude : la petite créature pixel de Claude Code balaie des fichiers qui s'envolent" width="200">
</p>

<h1 align="center">Clean My Claude</h1>

<p align="center"><b>« Claude, nettoie mon Mac. »</b><br>
Un utilitaire d'entretien natif pour macOS, dans l'esprit de CleanMyMac, construit avec Claude.<br>
Libre, gratuit, et tout se passe en local.</p>

> *English: a native macOS maintenance utility (cleanup, security audit, startup items, app uninstaller, disk map, live menu bar monitor). The interface is in French.*

> Projet personnel et non officiel, sans lien avec Anthropic ni avec MacPaw. « Claude » est une marque d'Anthropic, « CleanMyMac » une marque de MacPaw.

## Ce que fait l'app

| Section | Contenu |
| --- | --- |
| **Tableau de bord** | Score de santé sur 100, stockage, mémoire, processeur, batterie (santé, cycles), activité en direct, **analyse intelligente** qui passe tout en revue en une minute, et des conseils classés par utilité |
| **Nettoyage du système** | Caches d'apps et de macOS, journaux, fichiers temporaires, Xcode (données dérivées, appareils, archives, simulateurs), caches npm / Yarn / pip / Homebrew / CocoaPods / Go / Cargo…, dépendances de **projets endormis** (`node_modules`, `.build`, `Pods`, `target`), caches de l'**app Claude** et journaux de **Claude Code**, caches des navigateurs et des apps Electron, Corbeille, pièces jointes Mail, installeurs oubliés, sauvegardes d'iPhone |
| **Protection et confidentialité** | Bilan de sécurité (FileVault, coupe-feu, Gatekeeper, SIP, XProtect, mises à jour, verrouillage, partages), audit des **éléments persistants** avec vérification des signatures, liste des **autorisations** (caméra, micro, écran, disque…), effacement des **traces** (éléments récents, historique des téléchargements, vignettes, historique du Terminal, historique et cookies des navigateurs) |
| **Optimisation** | Moniteur temps réel, apps les plus gourmandes (processus d'aide regroupés par app), éléments au démarrage activables / désactivables, tâches de maintenance (mémoire, DNS, Launch Services, Spotlight, instantanés Time Machine…) |
| **Applications** | Inventaire avec taille, version, dernière ouverture, apps **Intel** qui passent par Rosetta, désinstallation **complète** (l'app et tous ses fichiers dans `~/Library`), restes d'apps déjà supprimées |
| **Espace de stockage** | Carte proportionnelle cliquable de n'importe quel dossier, gros fichiers anciens, **doublons** (comparaison du contenu par SHA-256) |
| **Menu d'état** | Dans la barre des menus : processeur, mémoire, disque, réseau, batterie, apps gourmandes et actions express. Alertes optionnelles si le disque est presque plein ou la mémoire saturée |

## Les garde-fous

Un nettoyeur qui supprime trop, c'est pire que pas de nettoyeur. Clean My Claude est prudent par construction :

- **Rien n'est supprimé sans ton accord.** Les analyses sont en lecture seule ; chaque nettoyage passe par une confirmation qui dit ce qui part et comment.
- **Une seule porte de sortie.** Toutes les suppressions de fichiers passent par `Remover`, qui refuse tout ce qui n'est pas dans ton dossier personnel (et `~/Library` lui-même, les trousseaux, Mail, Messages, iCloud Drive, Photos…). `CleanMyClaude --selftest` vérifie ces règles et que le catalogue ne propose jamais un chemin protégé ; le script de build le lance à chaque compilation.
- **La Corbeille d'abord.** Seuls les caches et journaux que les apps recréent sont supprimés directement. Tes fichiers, les apps désinstallées, les doublons partent dans la Corbeille. Un réglage permet de tout y envoyer.
- **Les apps ouvertes sont respectées.** Les caches de Claude, Chrome, Slack… sont verrouillés tant que l'app tourne.
- **Rien n'est coché d'office** dans les fichiers personnels, les restes d'apps ou les doublons.
- **Un journal** de chaque action : `~/Library/Logs/CleanMyClaude/actions.log`.
- **Aucune connexion réseau.** Seule la recherche de mises à jour macOS (`softwareupdate -l`) interroge Apple.

## Installation

Prérequis : macOS 14 (Sonoma) ou plus récent, et les outils de développement d'Apple (Xcode 15.3 ou plus, ou simplement `xcode-select --install`).

```bash
git clone https://github.com/Olima34/CleanMyClaude.git
cd CleanMyClaude
./scripts/build_app.sh
```

Le script compile en release, vérifie les garde-fous, génère l'icône, assemble `Clean My Claude.app` et l'installe dans `~/Applications` (`--no-install` la laisse dans `build/`, `--zip` produit une archive).

### L'accès complet au disque

macOS cache certains dossiers aux apps (Corbeille, Mail, Safari, bases d'autorisations). Pour que Clean My Claude les voie : **Réglages Système › Confidentialité et sécurité › Accès complet au disque**, puis active Clean My Claude. Sans cet accès, l'app fonctionne quand même et signale ce qu'elle ne peut pas voir.

L'app est signée localement (signature « ad hoc ») : après une recompilation, macOS peut la considérer comme nouvelle et il faut réactiver l'accès.

## Pour les développeurs

```bash
swift build
.build/debug/CleanMyClaude --dump                 # ce que trouve chaque scanner, sans rien supprimer
.build/debug/CleanMyClaude --dump --only cleanup  # cleanup | security | apps | processes
.build/debug/CleanMyClaude --dump --storage ~/Developer --duplicates ~/Downloads
.build/debug/CleanMyClaude --selftest             # garde-fous de suppression
.build/debug/CleanMyClaude --snapshot out/        # rend chaque page en PNG (--page, --tab, --light, --scale 2)
```

Le code, en SwiftUI pur, sans dépendance :

```
Sources/CleanMyClaude/
├── App/        point d'entrée, scènes (fenêtre, barre des menus, réglages), modèle global, outils CLI
├── Core/       mesures système (CPU, mémoire, réseau, batterie), tailles via fts(3), shell, suppression sécurisée
├── Features/   une section par dossier : Dashboard, Cleanup, Protection, Performance, Apps, Storage, MenuBar
└── UI/         thème et composants partagés avec ClaudeStats
```

Le design reprend celui de [ClaudeStats](https://github.com/Olima34/ClaudeStats) : surfaces chaudes, titres en serif, accent bleu, étincelle et créature de Claude.

## Feuille de route

- Mode démo à données fictives, pour des captures d'écran publiables
- « Demande à Claude » : expliquer un processus, un agent ou un dossier inconnu via l'API Claude (clé fournie par l'utilisateur)
- Mises à jour des apps (Homebrew, Sparkle, App Store)
- Nettoyage planifié et rappels
- Vue en rayons de soleil pour la carte du disque
- Localisation en anglais

## Licence

[MIT](LICENSE). Utilise-le à tes risques : relis ce que tu coches avant de nettoyer.
