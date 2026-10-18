import SwiftUI
import AppKit

/// The app model, reachable from AppKit entry points (delegate, Finder service) that SwiftUI does not reach.
@MainActor
enum AppContext {
    static var model: AppModel?
    /// Captured from the main window's view: SwiftUI's way to (re)create a closed window.
    static var openWindow: OpenWindowAction?

    /// Brings the main window to the front, recreating it if it was closed.
    static func showMainWindow() {
        let existing = NSApp.windows.first { w in
            (w.identifier?.rawValue.hasPrefix("main") ?? false) && (w.isVisible || w.isMiniaturized)
        }
        if let w = existing {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = FinderServices()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        MainActor.assumeIsolated {
            Notifier.setUp()
            NSApp.servicesProvider = services
            NSUpdateDynamicServices()
            if let app = AppContext.model {
                statusItem = StatusItemController(app: app)
                ModuleRegistry.startAll(app)
            }
            NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppContext.showMainWindow() }
            }
        }
    }

    /// Files dropped on the Dock icon go to the converter; `cleanmyclaude://` links drive the app
    /// (Shortcuts, Raycast, Terminal: `open cleanmyclaude://launcher`).
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            guard let app = AppContext.model else { return }
            let files = urls.filter(\.isFileURL)
            if !files.isEmpty {
                app.converter.receive(files)
                app.page = .converter
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
            }
            for url in urls where url.scheme == "cleanmyclaude" { URLActions.handle(url, app: app) }
        }
    }

    /// The menu bar keeps running when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock click, Raycast, Spotlight or Finder on an app that is already running: bring the window back.
    /// SwiftUI does not recreate a closed `Window` scene by itself, so the menu bar label (always alive) opens it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .openMainWindow, object: nil) }
        return true
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("cleanmyclaude.openMainWindow")
}

struct CleanMyClaudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let m = AppModel()
        AppContext.model = m
        _model = State(initialValue: m)
    }

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
                Button("Ouvrir le lanceur") { model.launcher.show() }
                Divider()
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
                    // Only the first nine pages get ⌘1…⌘9 (Character("10") would crash).
                    if i < 9 {
                        Button(p.title) { model.page = p }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    } else {
                        Button(p.title) { model.page = p }
                    }
                }
            }
        }


        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// "Convertir avec Clean My Claude" in the Finder's right-click › Services menu (declared in Info.plist by build_app.sh).
final class FinderServices: NSObject {
    @objc func convertFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "Aucun fichier reçu." as NSString
            return
        }
        MainActor.assumeIsolated {
            guard let app = AppContext.model else { return }
            app.converter.receive(urls)
            app.page = .converter
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
    }
}

/// `cleanmyclaude://launcher` opens the launcher, `cleanmyclaude://page/converter` a section,
/// `cleanmyclaude://run/act_smart_scan` a launcher command (risky ones still ask first).
@MainActor
enum URLActions {
    static func handle(_ url: URL, app: AppModel) {
        let parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "launcher":
            app.launcher.show()
        case "page":
            if let name = parts.dropFirst().first, let page = Page(rawValue: name) {
                app.page = page
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
            }
        case "run":
            if let id = parts.dropFirst().first, let command = ModuleRegistry.commands(app).first(where: { $0.id == id }) {
                Task { await CommandRunner.execute(command, app: app) }
            }
        default:
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
    }
}
