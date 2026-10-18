import SwiftUI
import AppKit

struct HotkeysPage: View {
    @Environment(AppModel.self) private var app
    @State private var commandQuery = ""

    var body: some View {
        @Bindable var model = app.hotkeys
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "keyboard", title: "Raccourcis",
                     subtitle: "Un raccourci clavier pour ouvrir n'importe quelle app, depuis n'importe où. Appuie de nouveau : elle se masque. Marche aussi pour un dossier, un site ou une action de Clean My Claude.",
                     tint: Theme.brand, seed: 57) {
                HStack(spacing: 8) {
                    Button { model.chooseApp() } label: { Label("Ajouter une app", systemImage: "plus") }
                        .buttonStyle(SoftButtonStyle(prominent: true))
                    Button { model.showCommandPicker = true } label: { Label("Ajouter une action", systemImage: "sparkles") }
                        .buttonStyle(SoftButtonStyle())
                    BorderlessMenu {
                        Button("Un dossier…") { model.chooseFolder() }
                        Button("Un fichier…") { model.chooseFile() }
                    } label: {
                        Text("Autre…").font(.ui(12.5, .medium)).foregroundStyle(Theme.text2)
                    }
                }
            }

            Panel(title: "Tes raccourcis", subtitle: model.bindings.isEmpty ? nil : "Clique sur les touches pour les changer ; ⌫ les retire",
                  symbol: "command", tint: Theme.brand) {
                VStack(spacing: 6) {
                    if model.bindings.isEmpty {
                        HStack(spacing: 12) {
                            PixelMascot(pixel: 4)
                            Text("Aucun raccourci pour l'instant. Ajoute une app, ou pioche dans les suggestions : je lui donne ⌃⌥⌘ + une lettre de son nom, que tu peux changer.")
                                .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach(model.bindings) { b in
                        HotkeysRow(binding: b)
                    }
                }
            }

            HotkeysCatalogPanel()

            HStack(alignment: .top, spacing: 14) {
                let suggestions = model.suggestions
                if !suggestions.isEmpty {
                    Panel(title: "Suggestions", subtitle: "Un clic : l'app reçoit ⌃⌥⌘ + une lettre libre", symbol: "wand.and.stars", tint: Theme.palette[1]) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, target in
                                Button { model.add(target) } label: {
                                    HStack(spacing: 8) {
                                        CommandIconView(icon: model.icon(target), size: 22)
                                        Text(target.title).font(.ui(12.5)).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardRaised.opacity(0.5)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Panel(title: "Un site web", subtitle: "Ouvert dans ton navigateur par défaut", symbol: "globe", tint: Theme.palette[4]) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            if Snapshot.isActive {
                                Text("claude.ai").font(.ui(12.5)).foregroundStyle(Theme.text3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg.opacity(0.6)))
                            } else {
                                TextField("claude.ai", text: $model.siteDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { model.addSite() }
                            }
                            Button("Ajouter") { model.addSite() }.buttonStyle(SoftButtonStyle(small: true))
                        }
                        Text("Aucune autorisation n'est nécessaire : ces raccourcis passent par le même mécanisme que ceux du lanceur. Ceux des fenêtres se règlent dans la section Fenêtres.")
                            .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 420)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $model.showCommandPicker) { HotkeysCommandPicker() }
    }
}

private struct HotkeysRow: View {
    @Environment(AppModel.self) private var app
    var binding: HotkeysBinding
    @State private var warning: String?

    var body: some View {
        let model = app.hotkeys
        HStack(spacing: 12) {
            CommandIconView(icon: model.icon(binding.target), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.target.title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                Text(warning ?? binding.target.kind).font(.ui(11)).foregroundStyle(warning == nil ? Theme.text3 : Theme.warn).lineLimit(1)
            }
            Spacer()
            if case .app = binding.target {
                Toggle("Masquer si déjà devant", isOn: Binding(get: { binding.toggles }, set: { model.setToggles($0, for: binding.id) }))
                    .switchToggles()
                    .font(.ui(11.5))
                    .foregroundStyle(Theme.text2)
                    .fixedSize()
            }
            if model.refused.contains(binding.id) {
                StatusBadge(status: .bad, text: "Pris ailleurs")
            }
            ShortcutRecorder(combo: binding.combo) { combo in
                if let other = model.conflict(for: combo, except: binding.id) {
                    warning = "Déjà utilisé par \(other)"
                } else {
                    warning = nil
                    model.setCombo(combo, for: binding.id)
                }
            }
            .frame(width: 130)
            Button { model.fire(binding.id) } label: { Image(systemName: "play.circle").font(.ui(14)).foregroundStyle(Theme.text3) }
                .buttonStyle(.plain).help("Essayer")
            Button { model.remove(binding.id) } label: { Image(systemName: "xmark.circle.fill").font(.ui(14)).foregroundStyle(Theme.text3) }
                .buttonStyle(.plain).help("Supprimer ce raccourci")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardRaised.opacity(0.45)))
    }
}

/// Picks one of the app's actions (the launcher's catalogue) for a shortcut.
private struct HotkeysCommandPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let all = ModuleRegistry.commands(app).filter { !$0.id.hasPrefix("hk_") }
        let shown = query.isEmpty ? Array(all.prefix(80))
            : all.compactMap { c in Fuzzy.best(query, title: c.title, keywords: c.keywords).map { (c, $0) } }.sorted { $0.1 > $1.1 }.prefix(80).map(\.0)
        VStack(alignment: .leading, spacing: 12) {
            Text("Une action pour ce raccourci").font(.serif(20)).foregroundStyle(Theme.text)
            TextField("Chercher : analyse, mode sombre, Caféine…", text: $query).textFieldStyle(.roundedBorder)
            List(shown, id: \.id) { c in
                Button {
                    app.hotkeys.add(.command(id: c.id, title: c.title))
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        CommandIconView(icon: c.icon, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title).font(.ui(12.5)).foregroundStyle(Theme.text)
                            if let s = c.subtitle { Text(s).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1) }
                        }
                        Spacer()
                        if case .confirm = c.risk { Image(systemName: "exclamationmark.shield").foregroundStyle(Theme.warn).help("Demandera confirmation") }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 380)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

enum HotkeysCatalogKind: String, CaseIterable, Identifiable {
    case actions, apps

    var id: String { rawValue }
    var title: String { self == .actions ? "Actions de Clean My Claude" : "Apps" }
}

/// Every action of the app, or every installed app, each with its shortcut recorder.
private struct HotkeysCatalogPanel: View {
    @Environment(AppModel.self) private var app
    @State private var kind: HotkeysCatalogKind = .actions
    @State private var query = ""

    private struct Row: Identifiable {
        let id: String
        let target: HotkeysTarget
        let title: String
        let subtitle: String?
        let icon: CommandIcon
        let section: String
    }

    var body: some View {
        let rows = filtered
        Panel(title: "Tout associer", subtitle: "Chaque action de Clean My Claude et chaque app peut avoir son raccourci. Dans le lanceur, ⌘K fait pareil sur le résultat choisi.",
              symbol: "list.bullet.rectangle", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    PillPicker(options: HotkeysCatalogKind.allCases, selection: $kind, label: \.title)
                    Spacer()
                    if Snapshot.isActive {
                        Text("Chercher…").font(.ui(12.5)).foregroundStyle(Theme.text3)
                            .frame(width: 240, alignment: .leading)
                            .padding(7).background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg.opacity(0.6)))
                    } else {
                        TextField(kind == .actions ? "Chercher : analyse, Caféine, traduire…" : "Chercher une app…", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    }
                }
                if rows.isEmpty {
                    Text(kind == .apps && app.launcher.installedApps.isEmpty ? "La liste des apps se charge…" : "Rien ne correspond.")
                        .font(.ui(12)).foregroundStyle(Theme.text3).padding(.vertical, 6)
                }
                let shown = Snapshot.isActive ? Array(rows.prefix(9)) : rows
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                    if i == 0 || shown[i - 1].section != row.section, !row.section.isEmpty {
                        Text(row.section.uppercased()).font(.ui(10, .semibold)).tracking(0.7).foregroundStyle(Theme.text3)
                            .padding(.top, i == 0 ? 0 : 8)
                    }
                    line(row)
                }
                if Snapshot.isActive, rows.count > shown.count {
                    Text("… et \(rows.count - shown.count) autres").font(.ui(11.5)).foregroundStyle(Theme.text3)
                }
            }
        }
    }

    private func line(_ row: Row) -> some View {
        let combo = app.hotkeys.binding(for: row.target)?.combo
        return HStack(spacing: 10) {
            CommandIconView(icon: row.icon, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.ui(12.5)).foregroundStyle(Theme.text).lineLimit(1)
                if let s = row.subtitle, !s.isEmpty { Text(s).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1) }
            }
            Spacer()
            ShortcutRecorder(combo: combo) { new in
                if let new {
                    if let other = app.hotkeys.bind(row.target, combo: new) {
                        HUD.show("\(new.display) est déjà utilisé par \(other)", symbol: "exclamationmark.triangle.fill")
                    }
                } else {
                    app.hotkeys.unbind(row.target)
                }
            }
            .frame(width: 130)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(combo == nil ? Color.clear : Theme.accent.opacity(0.07)))
    }

    private var filtered: [Row] {
        let all = kind == .actions ? actions : apps
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.compactMap { r in Fuzzy.best(q, title: r.title, keywords: [r.subtitle ?? ""]).map { (r, $0) } }
            .sorted { $0.1 > $1.1 }.map(\.0)
    }

    private var actions: [Row] {
        ModuleRegistry.commands(app)
            .filter { !$0.id.hasPrefix("hk_") }
            .sorted { ($0.group, $0.title) < ($1.group, $1.title) }
            .map { c in
                Row(id: c.id, target: .command(id: c.id, title: c.title), title: c.title, subtitle: c.subtitle, icon: c.icon, section: c.group.title)
            }
    }

    private var apps: [Row] {
        app.launcher.installedApps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { a in Row(id: a.path, target: .app(path: a.path, name: a.name), title: a.name, subtitle: nil, icon: .file(a.path), section: "") }
    }
}

struct HotkeysBottomBar: View {
    var body: some View { EmptyView() }
}
