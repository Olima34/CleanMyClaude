import SwiftUI
import AppKit
import ServiceManagement

/// The app model, reachable from AppKit entry points (delegate, Finder service) that SwiftUI does not reach.
@MainActor
enum AppContext {
    static var model: AppModel?
    /// Captured from the main window's view: SwiftUI's way to (re)create a closed window.
    static var openWindow: OpenWindowAction?

    /// Brings the main window to the front, recreating it if it was closed.
    static func showMainWindow() {
        // The pages come back before the window does, so it never shows up empty.
        setMainWindowOpen(true)
        if DockIconMode.current == .whileWindowOpen { NSApp.setActivationPolicy(.regular) }
        if let w = mainWindow {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { w in
            (w.identifier?.rawValue.hasPrefix("main") ?? false) && (w.isVisible || w.isMiniaturized)
        }
    }

    /// The system monitor samples only while something shows its values: here, the main window on screen
    /// (not closed, minimised, hidden, on another Space or fully covered).
    /// The pages, though, stay drawn until the window closes, so that they keep their state off screen.
    static func noteMainWindowVisibility(closing: Bool = false) {
        let windows = closing ? [] : NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") ?? false }
        // Closing is the only way to lose the pages; any way back on screen (Dock, menu bar, Window menu) brings them back.
        if closing { setMainWindowOpen(false) } else if windows.contains(where: \.isVisible) { setMainWindowOpen(true) }
        model?.monitor.show(.window, windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) })
    }

    private static func setMainWindowOpen(_ open: Bool) {
        guard let model, model.mainWindowOpen != open else { return }
        model.mainWindowOpen = open
    }

    /// No Dock icon by default, like Raycast: the app lives in the menu bar and behind its shortcut.
    static func applyDockIcon(windowClosing: Bool = false) {
        let windowOpen = !windowClosing && mainWindow != nil
        let regular: Bool
        switch DockIconMode.current {
        case .never: regular = false
        case .whileWindowOpen: regular = windowOpen
        case .always: regular = true
        }
        let policy: NSApplication.ActivationPolicy = regular ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Leaving .regular hides the app's windows from the front: keep the open window where it is.
        if !regular, windowOpen { DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) } }
    }
}

/// When the app shows an icon in the Dock (and in ⌘⇥).
enum DockIconMode: String, CaseIterable, Identifiable {
    case never, whileWindowOpen, always

    static let key = "app.dockIcon"
    var id: String { rawValue }

    static var current: DockIconMode {
        UserDefaults.standard.string(forKey: key).flatMap(DockIconMode.init(rawValue:)) ?? .never
    }

    var title: String {
        switch self {
        case .never: return "Jamais, comme Raycast"
        case .whileWindowOpen: return "Quand la fenêtre est ouverte"
        case .always: return "Toujours"
        }
    }
}

/// Launch at login: on by default (the launcher and the shortcuts must always answer), once per Mac; the user can turn it off.
enum LoginItem {
    static let defaultAppliedKey = "app.loginItemDefaulted"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ on: Bool) -> String? {
        guard !DemoData.isEnabled else { return DemoData.refusal }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Impossible : lance l'app assemblée depuis Applications (\(error.localizedDescription))."
        }
    }

    static func applyDefaultOnce() {
        guard !DemoData.isEnabled, !UserDefaults.standard.bool(forKey: defaultAppliedKey),
              Bundle.main.bundlePath.hasSuffix(".app") else { return }
        UserDefaults.standard.set(true, forKey: defaultAppliedKey)
        if !isEnabled { set(true) }
    }

    /// True when macOS opened the app at login (no window then, just the menu bar and the shortcuts).
    static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = FinderServices()
    private var statusItem: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Read now: the launch event is gone once the app has finished launching.
        atLogin = LoginItem.launchedAtLogin
        // Before the first window: a theme that is always light or dark sets the appearance of every window.
        MainActor.assumeIsolated { ThemeStore.shared.applyAppearance() }
    }

    private var atLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppContext.applyDockIcon()
            if atLogin {
                // Opened at login: stay in the background, like Raycast.
                DispatchQueue.main.async { AppContext.mainWindow?.close() }
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            LoginItem.applyDefaultOnce()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
                guard let w = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    if w.identifier?.rawValue.hasPrefix("main") ?? false {
                        AppContext.applyDockIcon(windowClosing: true)
                        AppContext.noteMainWindowVisibility(closing: true)
                    } else if !(w is NSPanel), w.styleMask.contains(.titled), w.isKeyWindow {
                        // Without a Dock icon, closing the settings would send the app behind the others and hide its
                        // main window: it comes back to the front instead.
                        DispatchQueue.main.async {
                            guard let main = AppContext.mainWindow, !main.isMiniaturized else { return }
                            main.makeKeyAndOrderFront(nil)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                guard let w = note.object as? NSWindow, w.identifier?.rawValue.hasPrefix("main") ?? false else { return }
                MainActor.assumeIsolated {
                    AppContext.applyDockIcon()
                    AppContext.noteMainWindowVisibility()
                }
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { note in
                guard let w = note.object as? NSWindow, w.identifier?.rawValue.hasPrefix("main") ?? false else { return }
                MainActor.assumeIsolated { AppContext.noteMainWindowVisibility() }
            }
        }
        MainActor.assumeIsolated {
            Notifier.setUp()
            NSApp.servicesProvider = services
            NSUpdateDynamicServices()
            if let app = AppContext.model {
                statusItem = StatusItemController(app: app)
                AppContext.noteMainWindowVisibility()
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

    /// Modules release what they hold (Caféine, timers) and save their data.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let app = AppContext.model { ModuleRegistry.stopAll(app) }
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
/// `cleanmyclaude://run/act_smart_scan` a launcher command. Any web page, mail or app can open such a link (`open -g` too):
/// only `urlSafe` commands (navigation, read-only analyses) run straight away; any other asks first, "Annuler" being the
/// default answer; a risky (`.confirm`) one never runs from a link: the launcher opens with it selected, the user decides there.
@MainActor
enum URLActions {
    /// Opening a link brings the app to the front, and its main window would take the keyboard from the launcher panel
    /// (which then closes): the app steps back first, like when the panel opens with its shortcut.
    private static func inPanel(_ open: @escaping @MainActor () -> Void) {
        NSApp.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { open() } }
    }

    static func handle(_ url: URL, app: AppModel) {
        let parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "launcher":
            inPanel { app.launcher.show() }
        case "page":
            if let name = parts.dropFirst().first, let page = Page(rawValue: name) {
                app.page = page
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
            }
        case "run":
            guard let id = parts.dropFirst().first, let command = ModuleRegistry.commands(app).first(where: { $0.id == id }) else { return }
            if case .confirm = command.risk {
                inPanel { select(command, app: app) }
                return
            }
            guard command.urlSafe || confirmFromLink(command) else { return }
            if command.staysInLauncher {
                inPanel { Task { await CommandRunner.execute(command, app: app) } }
            } else {
                Task { await CommandRunner.execute(command, app: app) }
            }
        default:
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
    }

    /// A risky command asked by a link: the launcher opens on it, nothing runs before the user's Entrée (and its confirmation).
    private static func select(_ command: AppCommand, app: AppModel) {
        let launcher = app.launcher
        launcher.show()
        launcher.query = command.title
        if let i = launcher.flat.firstIndex(where: { $0.id == command.id }) {
            launcher.selection = i
        } else {
            launcher.hide()
            HUD.show("Un lien a demandé « \(command.title) » : lance-le toi-même depuis le lanceur si tu le veux.",
                     symbol: "hand.raised.fill")
        }
    }

    /// Any other command not marked `urlSafe`: a link cannot run it without the user's yes.
    /// "Annuler" answers Entrée; "Exécuter" has no key, it needs a click.
    static func confirmFromLink(_ command: AppCommand) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Un lien venu d'une autre app demande : \(command.title)"
        alert.informativeText = (command.subtitle.map { "\($0)\n\n" } ?? "")
            + "Une page web, un message ou une autre app a ouvert un lien Clean My Claude. Si tu n'es pas à l'origine de cette demande, annule."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Annuler").keyEquivalent = "\r"
        alert.addButton(withTitle: "Exécuter").keyEquivalent = ""
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
