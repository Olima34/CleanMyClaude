import SwiftUI

/// Chamois' own keys in one list. Each one stays saved by its module, through that module's own setter
/// (lanceur, presse-papiers, roue), or as a shortcut of this page for the actions (fenêtre Fichiers, Vidéo seule).
struct HotkeysChamoisSection: View {
    @Environment(AppModel.self) private var app
    /// Why a key was refused, by row (the launcher keeps its own).
    @State private var warnings: [String: String] = [:]

    static let videoOnly = HotkeysTarget.command(id: AdBlockVideoOnly.commandID, title: "Vidéo seule")

    var body: some View {
        let launcher = app.launcher
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HotkeysChamoisRow(symbol: "command", tint: Theme.brand, title: "Ouvrir le lanceur",
                                  detail: "Chercher une app, un fichier, calculer, traduire…",
                                  warning: launcher.comboRefusal ?? launcherRefused,
                                  combo: launcher.combo, set: { launcher.setCombo($0) },
                                  openTitle: "Réglages du lanceur") { app.page = .launcher }
                HotkeysChamoisRow(symbol: "doc.text.magnifyingglass", tint: Theme.accent, title: "Rechercher des fichiers",
                                  detail: "La fenêtre Fichiers du lanceur",
                                  warning: warnings["files"],
                                  combo: app.hotkeys.binding(for: LauncherModel.filesHotkeyTarget)?.combo,
                                  set: { bind(LauncherModel.filesHotkeyTarget, $0, row: "files") },
                                  openTitle: "Réglages du lanceur") { app.page = .launcher }
                HotkeysChamoisRow(symbol: "doc.on.clipboard", tint: Theme.palette[2], title: "Historique du presse-papiers",
                                  detail: "Tout ce que tu as copié, prêt à recoller",
                                  warning: nil,
                                  combo: app.clipboard.combo, set: { app.clipboard.setCombo($0) },
                                  openTitle: "Ouvrir Presse-papiers") { app.page = .clipboard }
                HotkeysChamoisRow(symbol: "dial.medium", tint: Theme.palette[3], title: "Roue des fichiers",
                                  detail: "Sur les fichiers choisis dans le Finder",
                                  warning: nil,
                                  combo: app.wheel.combo, set: { app.wheel.setCombo($0) },
                                  openTitle: "Ouvrir la roue") { app.page = .wheel }
                HotkeysChamoisRow(symbol: "pip", tint: Theme.palette[5], title: "Vidéo seule",
                                  detail: "La vidéo de Safari, seule dans une petite fenêtre",
                                  warning: warnings["video"],
                                  combo: app.hotkeys.binding(for: Self.videoOnly)?.combo,
                                  set: { bind(Self.videoOnly, $0, row: "video") },
                                  openTitle: "Ouvrir le lecteur sans pub") { app.media.show(.player, app: app) }
            }
        }
    }

    /// The launcher's key, refused by macOS (not by Chamois): only in the running app, where it was registered.
    private var launcherRefused: String? {
        let l = app.launcher
        guard l.combo != nil, !l.hotKeyActive, !DemoData.isEnabled, !Snapshot.isActive else { return nil }
        return "macOS a refusé ce raccourci : choisis-en un avec ⌘ ou ⌃."
    }

    private func bind(_ target: HotkeysTarget, _ combo: KeyCombo?, row: String) {
        warnings[row] = nil
        guard let combo else {
            app.hotkeys.unbind(target)
            return
        }
        if let other = app.hotkeys.bind(target, combo: combo) {
            warnings[row] = "\(combo.display) est déjà utilisé par \(other) : choisis-en un autre."
        } else if let id = app.hotkeys.binding(for: target)?.id, let note = app.hotkeys.takeovers[id] {
            warnings[row] = note
        }
    }
}

private struct HotkeysChamoisRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String
    var warning: String?
    var combo: KeyCombo?
    var set: (KeyCombo?) -> Void
    var openTitle: String
    var open: () -> Void

    var body: some View {
        HotkeysHoverRow {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, tint: tint, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(warning ?? detail)
                        .font(.ui(11))
                        .foregroundStyle(warning == nil ? Theme.text3 : Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ShortcutRecorder(combo: combo, onChange: set)
                Button(action: open) {
                    Image(systemName: "arrow.right.circle").font(.ui(14)).foregroundStyle(Theme.text2)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(openTitle)
            }
        }
    }
}
