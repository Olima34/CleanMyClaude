import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The menu bar keeps running when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct CleanMyClaudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Clean My Claude", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Analyse") {
                Button("Analyse intelligente") {
                    model.page = .dashboard
                    Task { await model.smartScan() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Analyser les fichiers inutiles") {
                    model.page = .cleanup
                    Task { await model.cleanup.scan() }
                }
                Button("Faire le bilan de sécurité") {
                    model.page = .protection
                    Task { await model.protection.audit() }
                }
                Button("Explorer le dossier personnel") {
                    model.page = .storage
                    Task { await model.storage.scan(FS.home) }
                }
                Divider()
                Button("Journal des suppressions") {
                    if FS.exists(ActionLog.file) { NSWorkspace.shared.open(URL(fileURLWithPath: ActionLog.file)) }
                }
            }
            CommandMenu("Aller à") {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, p in
                    Button(p.title) { model.page = p }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }

        // No `isInserted:` binding: on recent macOS it ping-pongs with the system and redraws the item in a loop.
        // To hide the icon, macOS has its own setting (Réglages › Barre des menus).
        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
        } label: {
            MenuBarLabel(app: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
