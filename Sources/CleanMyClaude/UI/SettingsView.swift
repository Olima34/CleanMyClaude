import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Général", systemImage: "gearshape") }
            ShortcutSettings().tabItem { Label("Raccourcis", systemImage: "keyboard") }
            PermissionsSettings().tabItem { Label("Autorisations", systemImage: "lock.shield") }
            CleanupSettings().tabItem { Label("Nettoyage", systemImage: "sparkles") }
            AboutSettings().tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.menuMetricKey) private var metric: MenuMetric = .cpuMemory
    @AppStorage(Preferences.alertsKey) private var alerts = false
    @AppStorage(DockIconMode.key) private var dockIcon: DockIconMode = .never

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
    @State private var exclusions = Preferences.exclusions

    var body: some View {
        Form {
            Section {
                Toggle("Toujours passer par la Corbeille", isOn: $alwaysTrash)
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
        exclusions.removeAll { $0 == p }
        Preferences.exclusions = exclusions
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ClaudeSpark(size: 36)
                PixelMascot(pixel: 5, broom: true)
            }
            Text("Clean My Claude").font(.serif(24))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .font(.ui(12)).foregroundStyle(.secondary)
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
