import SwiftUI

struct LauncherPage: View {
    @Environment(AppModel.self) private var app
    /// Why the last shortcut typed for the file window was refused.
    @State private var filesRefusal: String?

    static let tip = HelpTip(
        id: "launcher.typing",
        title: "Ce que tu peux taper",
        text: """
        Le nom d'une app, un calcul (1250*1,2 + 15%), une conversion (10 km en miles), l'heure d'une ville (heure Tokyo), \
        un réglage (wifi), une phrase à traduire, un lien YouTube à télécharger ou n'importe quelle action de Chamois.
        """,
        steps: [
            "⌘K : les actions du résultat choisi (quitter une app, convertir un fichier, lui donner un raccourci…).",
            "Un lien YouTube collé : ↩ le télécharge, ses options sont à droite.",
            "« trad bonjour en anglais » ouvre le traducteur ; son engrenage (⌘,) règle les langues.",
            "« ~/Documents/ » ou « dans devis » passe à la fenêtre Fichiers."
        ])

    var body: some View {
        @Bindable var model = app.launcher
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "command", title: "Lanceur",
                     subtitle: "Tout ton Mac au bout d'un raccourci.",
                     tint: Theme.brand, seed: 93, tip: Self.tip) {
                HStack(spacing: 10) {
                    ScanButton(title: "Ouvrir le lanceur", symbol: "command") { app.launcher.show() }
                    ScanButton(title: "Rechercher des fichiers", symbol: "doc.text.magnifyingglass") { app.launcher.showFiles() }
                }
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    row("Lanceur") {
                        if model.combo != nil, !model.hotKeyActive {
                            StatusBadge(status: .bad, text: "Refusé par macOS")
                                .help("Choisis-en un avec ⌘ ou ⌃ (⌥ seul n'est pas accepté par toutes les versions de macOS)")
                        }
                        ShortcutRecorder(combo: model.combo) { app.launcher.setCombo($0) }
                    } note: { model.comboRefusal }
                    divider
                    row("Fenêtre Fichiers") {
                        ShortcutRecorder(combo: app.hotkeys.binding(for: LauncherModel.filesHotkeyTarget)?.combo) { setFilesCombo($0) }
                    } note: { filesRefusal }
                    divider
                    row("Index instantané des fichiers") {
                        indexBadge
                        if model.includeFiles, model.indexState == .off, !DemoData.isEnabled {
                            Button("Activer") { app.launcher.enableIndex() }
                                .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                                .help("Sans l'accès complet au disque, macOS demandera d'autoriser Documents, Bureau et Téléchargements")
                        } else if case .ready = model.indexState, !DemoData.isEnabled {
                            Button("Tout relire") { app.launcher.fileIndex.rebuild() }
                                .buttonStyle(SoftButtonStyle(small: true))
                                .help("Relit tout ton dossier personnel, en arrière-plan")
                        }
                        Toggle("", isOn: $model.includeFiles).labelsHidden().switchToggles().fixedSize()
                    } note: { nil }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                let top = mostUsed
                if !top.isEmpty {
                    Panel(title: "Les plus utilisées", symbol: "chart.bar") {
                        VStack(spacing: 8) {
                            let maxCount = Double(top.first?.1 ?? 1)
                            ForEach(top, id: \.0) { title, count in
                                RankRow(name: title, value: Fmt.plural(count, "fois", "fois"), fraction: Double(count) / maxCount, tint: Theme.brand)
                            }
                        }
                    }
                }
                let hidden = hiddenRows
                if !hidden.isEmpty {
                    Panel(title: "Masqués de la recherche", symbol: "eye.slash") {
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
                    .help("⌘K › Masquer de la recherche, sur un résultat du lanceur")
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.line).padding(.horizontal, 16)
    }

    /// A setting on one line: its name, its controls on the right, and a refusal under it when there is one.
    private func row<Controls: View>(_ title: String, @ViewBuilder controls: () -> Controls, note: () -> String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(title).font(.ui(13)).foregroundStyle(Theme.text)
                Spacer(minLength: 12)
                controls()
            }
            if let note = note() {
                Text(note).font(.ui(11.5, .medium)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        case .off:
            StatusBadge(status: .warn, text: app.launcher.includeFiles ? "Spotlight" : "Désactivé")
                .help("Spotlight cherche les fichiers, en une seconde ou plus")
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
