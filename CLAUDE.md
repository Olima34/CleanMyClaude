# Clean My Claude : règles du projet

App macOS native (SwiftUI, SwiftPM, Swift 5, macOS 14 minimum, aucune dépendance). Interface en français, ton chaleureux et tutoyant, design repris de ClaudeStats (`UI/Theme.swift`, `UI/Components/`).

## Construire et vérifier

```bash
swift build                                         # sans erreur ni avertissement
.build/debug/CleanMyClaude --selftest              # garde-fous + autotests de chaque module
.build/debug/CleanMyClaude --selftest --demo       # le mode démo ne touche à rien
.build/debug/CleanMyClaude --snapshot out/ --demo --page <page> [--tab <onglet>] [--scale 2]
.build/debug/CleanMyClaude --dump --only <page>    # ce que le module voit, en texte
```

Relis toujours la capture PNG de ta page. `./scripts/build_app.sh` installe l'app dans `~/Applications` : **ne le lance pas depuis une copie de travail parallèle** (toutes partagent la même app installée et les mêmes autorisations macOS).

## Architecture

- `Core/` : services partagés. Toute suppression passe par `Remover` (`removeInternal` pour les fichiers de l'app dans `DataStore`, `discardOutput` pour une sortie à moitié écrite), toute écriture de fichier par `FileOps` (jamais d'écrasement, `makeDirectory` pour un dossier), tout accès réseau par `HTTP` (HTTPS, sur action de l'utilisateur), tout processus par `Shell` (`run`, `stream`, `which`, `runAsAdmin`). Commandes du lanceur : `Core/Commands.swift` (`CommandRunner.copy(_:concealed:)` pour un secret). Raccourcis globaux : `HotKeyCenter`. Panneaux flottants et messages furtifs : `FloatingPanel`, `HUD`. Persistance : `JSONStore` (dossier `DataStore`). Secrets : `Keychain`. Notifications : `Notifier`. Tâches périodiques : `Scheduler`. Autorisations : `AppPermission` + `PermissionCard`.
- `App/ModuleRegistry.swift` : le protocole `AppModule` et la liste des modules. Le lanceur, le mode démo, les autotests, les captures et le menu d'état passent par lui.
- `Features/<Module>/` : un dossier par module (`Launcher`, `Converter`, `Toolbox`, `Clipboard`, `Updates`, `Network`, `Windows`, `Automation`, `Assistant`), avec au minimum `<Module>Model` (`@Observable @MainActor`, conforme à `AppModule`), `<Module>Page` et `<Module>BottomBar`.

## Règles pour travailler sur un module

1. **Ne modifie que `Features/<TonModule>/`.** Si tu as besoin d'un changement ailleurs (Core, AppModel, build_app.sh…), écris-le dans la note de fin pour l'intégrateur au lieu de le faire.
2. **Préfixe tous tes types** par le nom du module (`ConverterJob`, `ToolboxHash`…). Pas d'extension non privée sur un type partagé, pas de fonction globale : tout est compilé dans un seul module Swift.
3. **Mode démo** (`DemoData.isEnabled`) : `start()` ne fait rien (le registre ne l'appelle pas), `loadDemo()` remplit le module avec des données **inventées** (jamais celles de ce Mac : pas de vrai nom, chemin, app ou réseau), et ta page doit s'afficher sous `--snapshot --demo`. Les services de `Core/` refusent déjà toute action réelle en démo.
4. **Lanceur** : expose tes actions via `commands(app:)` (identifiants `[a-zA-Z0-9_-]`, préfixés par ton module, ex. `conv_heic_jpeg`) et tes résultats calculés via `results(for:app:)` (rapide : appelé à chaque frappe). Toute commande destructrice ou risquée porte `risk: .confirm("…")`. `assistantSafe: true` seulement pour ce que Claude peut proposer sans danger.
5. **Performance** : pas d'animation `repeatForever` (elle recalcule toute l'app à chaque image), des minuteurs avec tolérance et arrêtés quand rien n'est visible, une mise à jour de progression au plus 4 fois par seconde. Objectif : ≈1 % de CPU au repos.
6. **Autorisations macOS** : demande-les seulement après un clic, avec `PermissionCard` et une explication.
7. **SDK** : rien au-delà de macOS 15 (la CI compile avec Xcode 16). Pas de `#available(macOS 26, *)`.
8. **Pas de ressources SwiftPM** (le script de build ne copie pas `Bundle.module`) : tout est dans le code.
9. **Rendu des captures** : les contrôles AppKit (`Menu`, `TextField`, `Toggle`, `Picker`) sortent en rectangles jaunes dans `ImageRenderer` et les `ScrollView` vides. Utilise `BorderlessMenu`, `ScrollArea`, `.switchToggles()` (`UI/Components/Components.swift`) ou teste `Snapshot.isActive`.
10. **Autotests** : implémente `selfTest()` (fonctions pures : conversions, calculs, règles…) et `dump()`.
11. Ajoute de vraies fonctionnalités, pas des maquettes : chaque bouton fait ce qu'il dit, et l'utilisateur garde toujours la main (aperçu avant action, Corbeille plutôt que suppression, annulation des longues tâches).
