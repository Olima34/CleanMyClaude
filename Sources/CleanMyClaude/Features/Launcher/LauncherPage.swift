import SwiftUI

struct LauncherPage: View {
    @Environment(AppModel.self) private var app
    /// Why the last shortcut typed for the file window was refused.
    @State private var filesRefusal: String?

    private let examples: [(String, String, String)] = [
        ("app.badge", "slack", "Ouvre une app (les plus utilisées remontent en premier)"),
        ("doc.text.magnifyingglass", "facture edf", "Propose de chercher ce fichier dans la fenêtre Fichiers, avec son aperçu à côté"),
        ("command", "⌘K", "Les actions du résultat choisi : une app (quitter, désinstaller…), un fichier (convertir, partager…), une commande"),
        ("folder", "~/Documents/", "Parcourt les dossiers dans la fenêtre Fichiers (⇥ entre dans le dossier choisi)"),
        ("text.magnifyingglass", "dans devis cuisine", "Cherche aussi dans le contenu des fichiers (Spotlight), dans la fenêtre Fichiers"),
        ("checkmark.circle", "⌘-clic", "Choisit plusieurs fichiers et dossiers dans la fenêtre Fichiers ; glissés ensemble, ils sont copiés (jamais déplacés)"),
        ("doc.on.clipboard", "cb adresse", "Ouvre l'historique du presse-papiers dans sa fenêtre, la recherche déjà tapée"),
        ("character.bubble", "trad bonjour en anglais", "Traduit sur ton Mac ou avec Claude ; ↩ ouvre le traducteur avec tout le texte, ⌘↩ copie"),
        ("function", "1250*1,2 + 15%", "Calcule, virgule française comprise"),
        ("ruler", "10 km en miles", "Convertit longueurs, poids, °C, Go, durées…"),
        ("globe.europe.africa", "heure Tokyo", "Donne l'heure dans une autre ville"),
        ("moon.zzz", "veille", "Veille, verrouiller, mode sombre, éjecter, fichiers cachés…"),
        ("xmark.app", "quitter Chrome", "Ferme ou force à quitter une app"),
        ("gearshape", "wifi", "Ouvre directement un panneau des Réglages Système"),
        ("magnifyingglass", "yt lofi", "Cherche sur Google (g), YouTube (yt), GitHub (gh), Wikipédia (wiki)"),
        ("face.smiling", ":coeur", "Copie un emoji"),
        ("speaker.wave.2", "volume 30", "Règle le volume"),
        ("sparkles", "analyse", "Lance n'importe quelle action de Chamois")
    ]

    var body: some View {
        @Bindable var model = app.launcher
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "command", title: "Lanceur",
                     subtitle: "Un raccourci, une barre de recherche, et tout ton Mac au bout des doigts : apps, calculs, réglages et toutes les actions de Chamois. Les fichiers ont leur propre fenêtre.",
                     tint: Theme.brand, seed: 93) {
                HStack(spacing: 10) {
                    ScanButton(title: "Ouvrir le lanceur", symbol: "command") { app.launcher.show() }
                    ScanButton(title: "Rechercher des fichiers", symbol: "doc.text.magnifyingglass") { app.launcher.showFiles() }
                }
            }
            TileRow {
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            IconBadge(symbol: "keyboard", tint: Theme.brand, size: 28)
                            Text("Raccourci global").font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                        }
                        HStack(spacing: 10) {
                            ShortcutRecorder(combo: model.combo) { app.launcher.setCombo($0) }
                            if model.combo != nil {
                                StatusBadge(status: model.hotKeyActive ? .ok : .bad, text: model.hotKeyActive ? "Actif" : "Refusé par macOS")
                            }
                        }
                        if let refusal = model.comboRefusal {
                            Text(refusal).font(.ui(11.5, .medium)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(model.hotKeyActive
                             ? "Appuie dessus depuis n'importe quelle app. S'il ne réagit pas, une autre app l'utilise peut-être : choisis-en un autre (⌃⌥Espace, ⇧⌘Espace…)."
                             : "macOS a refusé ce raccourci. Choisis-en un avec ⌘ ou ⌃ (⌥ seul n'est plus accepté par certaines versions de macOS).")
                            .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            IconBadge(symbol: "doc.text.magnifyingglass", tint: Theme.accent, size: 28)
                            Text("Fenêtre Fichiers").font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            indexBadge
                        }
                        HStack(spacing: 10) {
                            Text("Raccourci").font(.ui(12.5)).foregroundStyle(Theme.text2)
                            ShortcutRecorder(combo: app.hotkeys.binding(for: LauncherModel.filesHotkeyTarget)?.combo) { setFilesCombo($0) }
                        }
                        if let filesRefusal {
                            Text(filesRefusal).font(.ui(11.5, .medium)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("Index instantané des noms de fichiers", isOn: $model.includeFiles)
                            .switchToggles()
                            .font(.ui(12.5))
                        Text(indexExplanation)
                            .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                        if model.includeFiles, model.indexState == .off, !DemoData.isEnabled {
                            Button("Activer la recherche instantanée") { app.launcher.enableIndex() }
                                .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                        } else if case .ready = model.indexState, !DemoData.isEnabled {
                            Button("Tout relire") { app.launcher.fileIndex.rebuild() }
                                .buttonStyle(SoftButtonStyle(small: true))
                                .help("Relit tout ton dossier personnel (quelques secondes, en arrière-plan)")
                        }
                    }
                }
            }
            Panel(title: "Ce que tu peux taper", subtitle: "Quelques exemples ; les autres modules ajoutent leurs propres commandes", symbol: "text.cursor") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 12) {
                    ForEach(examples, id: \.1) { symbol, typed, what in
                        HStack(alignment: .top, spacing: 10) {
                            CommandIconView(icon: .symbol(symbol), size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(typed).font(.mono(12, .medium)).foregroundStyle(Theme.text)
                                Text(what).font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            let hidden = hiddenRows
            if !hidden.isEmpty {
                Panel(title: "Masqués de la recherche", subtitle: "Ils ne sortent plus quand tu tapes (⌘K › Masquer de la recherche)", symbol: "eye.slash") {
                    VStack(spacing: 8) {
                        ForEach(hidden, id: \.id) { row in
                            HStack(spacing: 10) {
                                Text(row.title).font(.ui(12.5)).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer()
                                Button("Réafficher") { app.launcher.hiddenIDs.removeAll { $0 == row.id } }
                                    .buttonStyle(SoftButtonStyle(small: true))
                            }
                        }
                    }
                }
            }
            let top = mostUsed
            if !top.isEmpty {
                Panel(title: "Tes commandes les plus utilisées", subtitle: "Elles remontent en tête quand tu tapes", symbol: "chart.bar") {
                    VStack(spacing: 8) {
                        let maxCount = Double(top.first?.1 ?? 1)
                        ForEach(top, id: \.0) { title, count in
                            RankRow(name: title, value: Fmt.plural(count, "fois", "fois"), fraction: Double(count) / maxCount, tint: Theme.brand)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var indexBadge: some View {
        switch app.launcher.indexState {
        case .ready(let count): StatusBadge(status: .ok, text: Fmt.plural(count, "fichier", "fichiers"))
        case .building:
            HStack(spacing: 6) {
                BusyMascot(.sorting, pixel: 1)
                StatusBadge(status: .info, text: "Indexation…")
            }
        case .off: StatusBadge(status: .warn, text: app.launcher.includeFiles ? "Spotlight" : "Désactivée")
        }
    }

    private var indexExplanation: String {
        switch app.launcher.indexState {
        case .ready, .building:
            return "Les noms de tes fichiers sont gardés en mémoire, sur ton Mac : une recherche prend un millième de seconde, et chaque changement est suivi en direct. ~/Library, les dossiers cachés et les dépendances (node_modules…) sont laissés de côté."
        case .off:
            if !app.launcher.includeFiles { return "Sans l'index, c'est Spotlight qui cherche dans la fenêtre Fichiers (une seconde ou plus)." }
            return "Pour l'instant, c'est Spotlight qui cherche (une seconde ou plus). L'index instantané lit les noms de tes fichiers une fois ; sans l'accès complet au disque, macOS te demandera d'autoriser Documents, Bureau et Téléchargements."
        }
    }

    /// The file window's own shortcut, kept with the others in the Raccourcis section.
    private func setFilesCombo(_ combo: KeyCombo?) {
        filesRefusal = nil
        guard let combo else {
            app.hotkeys.unbind(LauncherModel.filesHotkeyTarget)
            return
        }
        if let other = app.hotkeys.bind(LauncherModel.filesHotkeyTarget, combo: combo) {
            filesRefusal = "\(combo.display) est déjà utilisé par \(other) : choisis-en un autre."
        }
    }

    /// The apps and commands taken out of the search, with their names.
    private var hiddenRows: [(id: String, title: String)] {
        let all = ModuleRegistry.commands(app) + LauncherAppIndex.commands(app.launcher.installedApps)
        let titles = Dictionary(all.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return app.launcher.hiddenIDs.map { ($0, titles[$0] ?? $0) }
    }

    /// The titles of the most used commands, with their counts.
    private var mostUsed: [(String, Int)] {
        let titles = Dictionary(ModuleRegistry.commands(app).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        // Only the commands that still exist (files, results of a past query… are not in the catalogue), then the top 6.
        return Array(CommandRunner.usage.value
            .sorted { $0.value.count > $1.value.count }
            .compactMap { id, u in titles[id].map { ($0, u.count) } }
            .prefix(6))
    }
}

struct LauncherBottomBar: View {
    var body: some View { EmptyView() }
}
