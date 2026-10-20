import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().frame(width: 520, height: 520).tabItem { Label("Général", systemImage: "gearshape") }
            AppearanceSettings().frame(width: AppearanceSettings.width, height: 680).tabItem { Label("Apparence", systemImage: "paintpalette") }
            ShortcutSettings().frame(width: 520, height: 400).tabItem { Label("Raccourcis", systemImage: "keyboard") }
            PermissionsSettings().frame(width: 520, height: 400).tabItem { Label("Autorisations", systemImage: "lock.shield") }
            CleanupSettings().frame(width: 520, height: 400).tabItem { Label("Nettoyage", systemImage: "sparkles") }
            AboutSettings().frame(width: 520, height: 400).tabItem { Label("À propos", systemImage: "info.circle") }
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.menuMetricKey) private var metric: MenuMetric = .cpuMemory
    @AppStorage(Preferences.alertsKey) private var alerts = false
    @AppStorage(DockIconMode.key) private var dockIcon: DockIconMode = .never
    @AppStorage(UpdatesSelfModel.autoKey) private var autoUpdate = true

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle()
                Picker("Icône dans le Dock", selection: $dockIcon) {
                    ForEach(DockIconMode.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: dockIcon) { _, _ in AppContext.applyDockIcon() }
                Picker("Barre des menus", selection: $metric) {
                    ForEach(MenuMetric.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Alertes disque plein et mémoire saturée", isOn: $alerts)
                    .onChange(of: alerts) { _, on in if on { Alerts.requestPermission() } }
                    .disabled(!Alerts.available)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profil")
                        Text(app.profile.isChosen ? app.profile.summary : "Aucun : tous les outils sont dans la barre latérale")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Modifier") {
                        app.showProfilePanel = true
                        AppContext.showMainWindow()
                    }
                    .disabled(app.showOnboarding)
                }
                HStack {
                    Text("Présentation de l'app")
                    Spacer()
                    Button("Revoir") {
                        app.showOnboarding = true
                        AppContext.showMainWindow()
                    }
                    .disabled(app.showOnboarding)
                }
            }
            Section {
                Toggle("Rechercher les nouvelles versions de Clean My Claude", isOn: $autoUpdate)
                    .disabled(DemoData.isEnabled || !app.updates.selfUpdate.canCheck)
                HStack {
                    Text(selfUpdateStatus)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(app.updates.selfUpdate.release == nil ? "Rechercher maintenant" : "Voir les nouveautés") {
                        Task { await app.updates.selfUpdate.check() }
                    }
                    .disabled(app.updates.selfUpdate.state.isChecking || !app.updates.selfUpdate.canCheck)
                }
            } header: {
                Text("Mises à jour de Clean My Claude")
            } footer: {
                Text("Au lancement puis toutes les 6 h, l'app demande à GitHub le numéro de sa dernière version publiée. C'est la seule connexion faite sans ton clic, et rien d'autre n'est envoyé. Une nouvelle version s'annonce dans un petit panneau : rien ne s'installe sans ton accord.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Autorisations") {
                HStack {
                    Label(app.fullDiskAccess ? "Accès complet au disque accordé" : "Accès complet au disque non accordé",
                          systemImage: app.fullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(app.fullDiskAccess ? Theme.good : Theme.warn)
                    Spacer()
                    Button("Ouvrir le réglage") { Finder.open(Permissions.fullDiskAccessURL) }
                }
                Text("Après une recompilation, macOS peut considérer l'app comme nouvelle : réactive alors l'accès.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var selfUpdateStatus: String {
        let m = app.updates.selfUpdate
        if m.state.isChecking { return "Vérification…" }
        if let r = m.release { return "Version \(r.version) disponible, tu as la \(m.build.label)" }
        guard m.canCheck else { return "Version de développement" }
        if case .failed(let message) = m.state { return message }
        if let d = m.state.date { return "À jour : \(m.build.label), vérifié \(Fmt.relative(d))" }
        return "Version \(m.build.label)"
    }
}

struct ShortcutSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Ouvrir le lanceur")
                    Spacer()
                    ShortcutRecorder(combo: app.launcher.combo) { app.launcher.setCombo($0) }
                }
                if app.launcher.combo != nil && !app.launcher.hotKeyActive {
                    Text("macOS a refusé ce raccourci : choisis-en un avec ⌘ ou ⌃.").font(.caption).foregroundStyle(Theme.warn)
                }
            } footer: {
                Text("Clique sur le raccourci puis tape le nouveau. ⎋ annule, ⌫ le supprime. Les raccourcis des fenêtres se règlent dans la section Fenêtres.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct CleanupSettings: View {
    @AppStorage(Preferences.alwaysTrashKey) private var alwaysTrash = false
    // The demo shows none of this Mac's folders and changes none of its settings.
    @State private var exclusions = DemoData.isEnabled ? [] : Preferences.exclusions

    var body: some View {
        Form {
            Section {
                Toggle("Toujours passer par la Corbeille", isOn: $alwaysTrash)
                    .disabled(DemoData.isEnabled)
                Text("Par défaut, les caches et journaux sont supprimés directement (les apps les recréent). Avec ce réglage, tout part d'abord à la Corbeille.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ne jamais toucher à") {
                if exclusions.isEmpty {
                    Text("Aucune exclusion.").foregroundStyle(.secondary)
                }
                ForEach(exclusions, id: \.self) { p in
                    HStack {
                        Image(systemName: "folder")
                        Text(FS.pretty(p)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { remove(p) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                Button("Ajouter un dossier…") { add() }
                    .disabled(DemoData.isEnabled)
            }
            Section {
                Button("Ouvrir le journal des suppressions") {
                    if FS.exists(ActionLog.file) { NSWorkspace.shared.open(URL(fileURLWithPath: ActionLog.file)) } else { Finder.reveal(ActionLog.folder) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            exclusions = Array(Set(exclusions + panel.urls.map(\.path))).sorted()
            Preferences.exclusions = exclusions
        }
    }

    private func remove(_ p: String) {
        guard !DemoData.isEnabled else { return }
        exclusions.removeAll { $0 == p }
        Preferences.exclusions = exclusions
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            PixelMascot(pixel: 5)
            Text("Clean My Claude").font(.serif(24))
            Text("Version \(UpdatesSelfBuild.current.label)")
                .font(.ui(12)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Un utilitaire d'entretien pour macOS, construit avec Claude. Libre, gratuit, et tout se passe en local.")
                .font(.ui(12.5)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Link("Code source sur GitHub", destination: URL(string: "https://github.com/Olima34/CleanMyClaude")!)
                .font(.ui(12.5))
            Text("Projet personnel, sans lien avec Anthropic ni avec MacPaw. « Claude » est une marque d'Anthropic.")
                .font(.ui(10.5)).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
