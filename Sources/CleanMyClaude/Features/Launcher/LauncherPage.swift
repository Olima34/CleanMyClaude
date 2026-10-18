import SwiftUI

struct LauncherPage: View {
    @Environment(AppModel.self) private var app

    private let examples: [(String, String, String)] = [
        ("app.badge", "slack", "Ouvre une app (les plus utilisées remontent en premier)"),
        ("doc.text.magnifyingglass", "facture mars", "Trouve un fichier avec Spotlight"),
        ("function", "1250*1,2 + 15%", "Calcule, virgule française comprise"),
        ("ruler", "10 km en miles", "Convertit longueurs, poids, °C, Go, durées…"),
        ("globe.europe.africa", "heure Tokyo", "Donne l'heure dans une autre ville"),
        ("moon.zzz", "veille", "Veille, verrouiller, mode sombre, éjecter, fichiers cachés…"),
        ("xmark.app", "quitter Chrome", "Ferme ou force à quitter une app"),
        ("gearshape", "wifi", "Ouvre directement un panneau des Réglages Système"),
        ("magnifyingglass", "yt lofi", "Cherche sur Google (g), YouTube (yt), GitHub (gh), Wikipédia (wiki)"),
        ("face.smiling", ":coeur", "Copie un emoji"),
        ("speaker.wave.2", "volume 30", "Règle le volume"),
        ("sparkles", "analyse", "Lance n'importe quelle action de Clean My Claude")
    ]

    var body: some View {
        @Bindable var model = app.launcher
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "command", title: "Lanceur",
                     subtitle: "Un raccourci, une barre de recherche, et tout ton Mac au bout des doigts : apps, fichiers, calculs, réglages et toutes les actions de Clean My Claude.",
                     tint: Theme.brand, seed: 93) {
                ScanButton(title: "Ouvrir le lanceur", symbol: "command") { app.launcher.show() }
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
                        Text(model.hotKeyActive
                             ? "Appuie dessus depuis n'importe quelle app. S'il ne réagit pas, une autre app l'utilise peut-être : choisis-en un autre (⌃⌥Espace, ⇧⌘Espace…)."
                             : "macOS a refusé ce raccourci. Choisis-en un avec ⌘ ou ⌃ (⌥ seul n'est plus accepté par certaines versions de macOS).")
                            .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            IconBadge(symbol: "slider.horizontal.3", tint: Theme.accent, size: 28)
                            Text("Recherche").font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                        }
                        Toggle("Chercher aussi dans mes fichiers (Spotlight)", isOn: $model.includeFiles)
                            .switchToggles()
                            .font(.ui(12.5))
                        Text("La recherche de fichiers commence à 3 lettres, dans ton dossier personnel. Rien ne quitte ton Mac, sauf si tu choisis une recherche web.")
                            .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
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
            let top = mostUsed
            if !top.isEmpty {
                Panel(title: "Tes commandes favorites", subtitle: "Elles remontent en tête quand tu tapes", symbol: "star") {
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

    /// The titles of the most used commands, with their counts.
    private var mostUsed: [(String, Int)] {
        let all = ModuleRegistry.commands(app)
        return CommandRunner.usage.value
            .sorted { $0.value.count > $1.value.count }
            .prefix(6)
            .compactMap { id, u in all.first { $0.id == id }.map { ($0.title, u.count) } }
    }
}

struct LauncherBottomBar: View {
    var body: some View { EmptyView() }
}
