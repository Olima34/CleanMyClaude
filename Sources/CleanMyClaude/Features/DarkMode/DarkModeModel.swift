import SwiftUI
import AppKit

/// What the module keeps between launches.
struct DarkModeSettings: Codable, Equatable {
    /// Bundle ID → what the user chose (absent: Auto).
    var choices: [String: DarkModeChoice] = [:]
    /// Bundle ID → `NSRequiresAquaSystemAppearance` as it was before the first change (absent key: nil).
    var originals: [String: DarkModeOriginal] = [:]
    /// Names of the apps set, for the list and the launcher even when the scan has not run yet.
    var names: [String: String] = [:]
}

struct DarkModeOriginal: Codable, Equatable {
    var value: Bool?
}

enum DarkModeAppFilter: String, CaseIterable, Identifiable {
    case lightOnly, ownUI, follows, chosen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lightOnly: return "Restent claires"
        case .ownUI: return "Thème maison"
        case .follows: return "Suivent le Mac"
        case .chosen: return "Réglées"
        }
    }
}

/// Dark mode everywhere, like Noir: the Mac's appearance, the apps that ignore it, and the web pages that stay light.
/// Nothing runs in the background, except the inversion of apps chosen "Inversée", which only listens to app switches.
@Observable
@MainActor
final class DarkModeModel: AppModule {
    var settings = DarkModeSettings() {
        didSet { store.value = settings }
    }
    var appearance: DarkModeAppearance = .dark
    /// The installed apps, nil until the page asked for them.
    var apps: [DarkModeApp]?
    var scanning = false
    var filter: DarkModeAppFilter = .lightOnly
    /// Apps changed while open: they show the change once relaunched.
    var pendingRelaunch: Set<String> = []
    var relaunching: Set<String> = []
    /// Apps whose setting is being written.
    var applying: Set<String> = []
    /// macOS refused to let the preferences of a sandboxed app be changed: Full Disk Access is needed.
    var needsDiskAccess = false
    var browsers: [DarkModeBrowser] = []
    var extensions: [DarkModeExtension]?
    /// The style sheet Safari used to darken pages with is still on disk (emptied: it inverts nothing any more).
    var oldStyleSheet = false
    /// The browser being closed, changed and reopened.
    var browserBusy: String?
    var switchingMac = false
    /// System Events refused (Automation permission).
    var macError: String?
    /// The inversion did not answer on this Mac.
    var invertFailed = false
    var testingInvert = false

    @ObservationIgnored private let store = JSONStore<DarkModeSettings>("darkmode", default: DarkModeSettings())
    @ObservationIgnored private let watcher = DarkModeInvertWatcher()
    @ObservationIgnored private var themeObserver: NSObjectProtocol?
    @ObservationIgnored private weak var app: AppModel?

    init() {
        settings = store.value
    }

    // MARK: Derived

    func choice(_ a: DarkModeApp) -> DarkModeChoice {
        if let c = settings.choices[a.bundleID] { return c }
        // A value set outside Clean My Claude (by hand, or by another tool) shows as what it does.
        switch a.override {
        case false?: return .dark
        case true?: return a.kind == .lightOnly ? .system : .light
        case nil: return .system
        }
    }

    /// The apps that still stay light: the ones to force.
    var toForce: [DarkModeApp] {
        (apps ?? []).filter { $0.kind == .lightOnly && choice($0) == .system }
    }

    func list(_ f: DarkModeAppFilter) -> [DarkModeApp] {
        let all = apps ?? []
        switch f {
        case .lightOnly: return all.filter { $0.kind == .lightOnly }
        case .ownUI: return all.filter { $0.kind == .ownUI }
        case .follows: return all.filter { $0.kind == .follows }
        case .chosen: return all.filter { choice($0) != .system }
        }
    }

    var invertApps: Set<String> {
        Set(settings.choices.filter { $0.value == .invert }.keys)
    }

    var chromiumForced: [DarkModeBrowser] { browsers.filter { $0.engine == .chromium && $0.forced == true } }

    // MARK: Module

    var sidebarBadge: String? {
        let n = toForce.count
        return n > 0 ? "\(n)" : nil
    }

    func start(app: AppModel) {
        self.app = app
        appearance = DarkModeSystem.appearance()
        themeObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appearance = DarkModeSystem.appearance() }
        }
        watcher.onFailure = { [weak self] in self?.invertFailed = true }
        watcher.update(apps: invertApps)
        Task {
            oldStyleSheet = await Task.detached(priority: .utility) { DarkModeStyleSheet.retire() }.value
        }
    }

    func stop() {
        watcher.stop()
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
        store.flush()
    }

    func loadDemo() {
        appearance = .dark
        apps = DarkModeDemo.apps()
        settings = DarkModeDemo.settings()
        browsers = DarkModeDemo.browsers()
        extensions = []
        pendingRelaunch = ["fr.cartographe.desktop"]
        filter = .lightOnly
    }

    func applySnapshotTab(_ tab: String) {
        switch tab {
        case "intro":
            // Nothing set yet, the Mac still light.
            appearance = .light
            settings = DarkModeSettings()
            pendingRelaunch = []
            browsers = DarkModeDemo.browsers().map { var b = $0; b.forced = b.engine == .chromium ? false : nil; return b }
        case "clair":
            appearance = .light
        case "maison":
            filter = .ownUI
        case "suivent":
            filter = .follows
        case "reglees":
            filter = .chosen
        case "extension":
            extensions = [DarkModeExtension(identifier: "com.exemple.noir.Extension", name: "Noir", appPath: nil)]
        case "ancienne":
            // Back from a version that darkened Safari with a style sheet.
            oldStyleSheet = true
        case "acces":
            needsDiskAccess = true
        case "attente":
            // At work: the apps being read, a browser being closed and reopened.
            apps = nil
            scanning = true
            browserBusy = "com.google.Chrome"
        default:
            break
        }
    }

    var quickToggles: [QuickToggle] {
        guard DarkModeInvert.isAvailable else { return [] }
        return [QuickToggle(id: "darkmode_invert", title: "Inverser l'écran", symbol: "circle.righthalf.filled.inverse",
                     isOn: DarkModeInvert.isOn) { [weak self] in self?.toggleInvert() }]
    }

    func commands(app: AppModel) -> [AppCommand] { DarkModeCommands.list(self) }

    func results(for query: String, app: AppModel) -> [AppCommand] { DarkModeCommands.results(query, self) }

    func selfTest() -> [String] { DarkModeChecks.run() }

    func dump() -> [String] {
        let found = apps ?? DarkModeAppScan.scan()
        var lines = ["Apparence du Mac : \(DarkModeSystem.appearance().title)"]
        let groups: [(DarkModeAppKind, String)] = [(.lightOnly, "Restent claires"), (.ownUI, "Thème maison"), (.follows, "Suivent le Mac")]
        for (kind, title) in groups {
            let list = found.filter { $0.kind == kind }
            lines.append("\(title) (\(list.count)) : " + list.map { "\($0.name)\($0.toolkit.map { " [\($0)]" } ?? "")" }.joined(separator: ", "))
        }
        for a in found where a.kind == .lightOnly { lines.append("  · \(a.name) : \(a.reason)") }
        lines.append("Réglées par l'app : " + (settings.choices.isEmpty ? "aucune"
            : settings.choices.map { "\(settings.names[$0.key] ?? $0.key) → \($0.value.title)" }.sorted().joined(separator: ", ")))
        for b in DarkModeBrowsers.installed() {
            let state: String
            switch b.engine {
            case .safari:
                let ext = extensions ?? DarkModeExtensions.installed()
                state = (ext.isEmpty ? "aucune extension sombre" : "extension " + ext.map(\.name).joined(separator: ", "))
                    + (!DemoData.isEnabled && FS.exists(DarkModeStyleSheet.path) ? " · ancienne feuille de style encore là" : "")
            case .chromium: state = b.forced.map { $0 ? "pages sombres forcées" : "pages telles quelles" } ?? "jamais ouvert (pas de Local State)"
            case .firefox: state = "réglage guidé"
            }
            lines.append("Navigateur \(b.name) : \(state)\(b.running ? " · ouvert" : "")")
        }
        lines.append("Inversion des couleurs : \(DarkModeInvert.isAvailable ? (DarkModeInvert.isOn ? "active" : "disponible") : "indisponible sur ce macOS")")
        return lines
    }

    // MARK: Mac appearance

    func refresh() {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        appearance = DarkModeSystem.appearance()
        scanApps()
        refreshBrowsers()
    }

    func setMacDark() {
        guard !switchingMac else { return }
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        switchingMac = true
        macError = nil
        Task {
            let r = await Task.detached(priority: .userInitiated) { DarkModeSystem.setDark(true) }.value
            switchingMac = false
            appearance = DarkModeSystem.appearance()
            if !r.ok {
                macError = r.status == -1743
                    ? "macOS n'a pas laissé \(AppEdition.name) piloter Événements système. Autorise-le dans Réglages Système › Confidentialité et sécurité › Automatisation, puis réessaie."
                    : "Le Mac n'a pas changé d'apparence : \(r.err)"
            } else {
                ActionLog.write("SOMBRE PARTOUT Mac passé en sombre")
            }
        }
    }

    func openAppearanceSettings() { Finder.open(DarkModeSystem.appearancePane) }
    func openAutomationSettings() { Finder.open(DarkModeSystem.automationPane) }

    // MARK: Apps

    func scanApps() {
        guard !scanning, !DemoData.isEnabled, !Snapshot.isActive else { return }
        scanning = true
        Task {
            let found = await Task.detached(priority: .utility) { DarkModeAppScan.scan() }.value
            apps = found
            scanning = false
            pendingRelaunch = pendingRelaunch.filter(DarkModeRelaunch.isRunning)
            for a in found where settings.choices[a.bundleID] != nil { settings.names[a.bundleID] = a.name }
        }
    }

    /// Writes the app's setting (after reading the original once), then offers to relaunch it if it is open.
    func setChoice(_ a: DarkModeApp, _ c: DarkModeChoice) {
        guard !applying.contains(a.bundleID), choice(a) != c else { return }
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        let id = a.bundleID
        let before = choice(a)
        let known = settings.originals[id]
        // Between Auto and Inversée the app's preferences stay as they are: nothing to write.
        guard before.requiresAqua != c.requiresAqua else {
            settings.choices[id] = c == .system ? nil : c
            settings.names[id] = c == .system ? nil : a.name
            if c == .system { settings.originals[id] = nil }
            ActionLog.write("SOMBRE PARTOUT \(a.name) (\(id)) : \(c.title)")
            updateWatcher()
            return
        }
        applying.insert(id)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(original: Bool?, written: Bool?), DarkModeFailure> in
                var original = known?.value
                if known == nil {
                    switch DarkModeAppPrefs.read(id) {
                    case .value(let v): original = v
                    case .refused(let why): return .failure(DarkModeFailure(message: why))
                    }
                }
                // Back to Auto from a value set outside Clean My Claude: the key goes, the app decides again.
                let target = c.requiresAqua ?? (known == nil && c == .system ? nil : original)
                if let error = DarkModeAppPrefs.write(id, target) { return .failure(DarkModeFailure(message: error)) }
                return .success((original, target))
            }.value
            applying.remove(id)
            switch result {
            case .success(let values):
                if known == nil { settings.originals[id] = DarkModeOriginal(value: values.original) }
                if let i = apps?.firstIndex(where: { $0.bundleID == id }) { apps?[i].override = values.written }
                if c == .system {
                    settings.choices[id] = nil
                    settings.originals[id] = nil
                    settings.names[id] = nil
                } else {
                    settings.choices[id] = c
                    settings.names[id] = a.name
                }
                needsDiskAccess = false
                ActionLog.write("SOMBRE PARTOUT \(a.name) (\(id)) : \(c.title)")
                // The appearance is read when the app starts: an open app shows it once relaunched.
                if before.requiresAqua != c.requiresAqua, DarkModeRelaunch.isRunning(id) { pendingRelaunch.insert(id) }
                if c == .invert || before == .invert { updateWatcher() }
            case .failure(let why):
                if a.sandboxed, !Permissions.hasFullDiskAccess { needsDiskAccess = true }
                HUD.show("Réglage refusé pour \(a.name)", symbol: "xmark.octagon.fill")
                ActionLog.write("SOMBRE PARTOUT \(a.name) : échec · \(why.message)")
            }
        }
    }

    /// Every app that stays light, switched to follow the Mac.
    func forceAll() {
        let list = toForce
        guard !list.isEmpty else { return }
        for a in list { setChoice(a, .dark) }
    }

    /// Every app back to its original setting.
    func resetAll() {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        let byID = Dictionary((apps ?? []).map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, _) in settings.choices {
            // An app uninstalled since: its preference is put back all the same.
            let a = byID[id] ?? DarkModeApp(path: "", name: settings.names[id] ?? id, bundleID: id, kind: .follows, reason: "",
                                            toolkit: nil, sandboxed: FS.exists(FS.home + "/Library/Containers/" + id), override: nil)
            setChoice(a, .system)
        }
    }

    func relaunch(_ id: String) {
        guard !relaunching.contains(id) else { return }
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        guard let path = apps?.first(where: { $0.bundleID == id })?.path ?? DarkModeBrowsers.appPath(id) else {
            pendingRelaunch.remove(id)
            return
        }
        let name = apps?.first { $0.bundleID == id }?.name ?? settings.names[id] ?? id
        relaunching.insert(id)
        Task {
            let ok = await DarkModeRelaunch.relaunch(bundleID: id, path: path)
            relaunching.remove(id)
            if ok {
                pendingRelaunch.remove(id)
            } else {
                HUD.show("\(name) ne s'est pas fermée : un document à enregistrer ?", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func relaunchAll() {
        for id in pendingRelaunch { relaunch(id) }
    }

    // MARK: Inversion

    private func updateWatcher() {
        invertFailed = false
        watcher.update(apps: invertApps)
    }

    func toggleInvert() {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        let on = !DarkModeInvert.isOn
        // macOS' answer comes back without holding the main thread.
        DarkModeInvert.set(on) { [weak self] ok in
            guard !ok else { return }
            self?.invertFailed = true
            HUD.show("macOS n'a pas inversé l'écran : Réglages › Accessibilité › Écran", symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Three seconds of inversion, to see what "Inversée" does on this Mac.
    func testInvert() {
        guard !testingInvert else { return }
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        guard !DarkModeInvert.isOn else { return HUD.show("L'écran est déjà inversé", symbol: "info.circle.fill") }
        testingInvert = true
        DarkModeInvert.set(true) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.invertFailed = true
                self.testingInvert = false
                return
            }
            self.invertFailed = false
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                DarkModeInvert.set(false) { _ in self?.testingInvert = false }
            }
        }
    }

    func openDisplaySettings() { Finder.open(DarkModeSystem.displayPane) }

    // MARK: Browsers

    func refreshBrowsers() {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        Task {
            let (found, ext) = await Task.detached(priority: .utility) { (DarkModeBrowsers.installed(), DarkModeExtensions.installed()) }.value
            if found != browsers { browsers = found }
            if ext != extensions { extensions = ext }
        }
    }

    /// Closes the browser if it is open (it asks about its tabs as on ⌘Q), flips the switch, and reopens it on its tabs.
    func setChromium(_ b: DarkModeBrowser, _ on: Bool) {
        guard browserBusy == nil else { return }
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        let wasRunning = DarkModeRelaunch.isRunning(b.bundleID)
        if wasRunning {
            guard CommandRunner.confirm("Fermer \(b.name) ?", "\(b.name) garde ce réglage dans un fichier qu'il réécrit en se fermant : il va se fermer, puis se rouvrir sur tes onglets.",
                                        button: "Fermer et appliquer") else { return }
        }
        browserBusy = b.bundleID
        Task {
            if wasRunning, !(await DarkModeRelaunch.quit(bundleID: b.bundleID)) {
                browserBusy = nil
                return HUD.show("\(b.name) ne s'est pas fermé : rien n'a changé", symbol: "exclamationmark.triangle.fill")
            }
            let r = await Task.detached(priority: .userInitiated) { DarkModeChromium.apply(b, enable: on) }.value
            switch r {
            case .success:
                HUD.show(on ? "\(b.name) : toutes les pages en sombre" : "\(b.name) : les pages reprennent leurs couleurs", symbol: "moon.fill")
            case .failure(.stillRunning):
                HUD.show("\(b.name) est encore ouvert : rien n'a changé", symbol: "exclamationmark.triangle.fill")
            case .failure(.unreadable):
                HUD.show("Réglages de \(b.name) illisibles : ouvre-le une fois, puis réessaie", symbol: "xmark.octagon.fill")
            case .failure(.write(let why)):
                HUD.show("Écriture refusée : \(why)", symbol: "xmark.octagon.fill")
            }
            if wasRunning {
                let config = NSWorkspace.OpenConfiguration()
                config.arguments = ["--restore-last-session"]
                _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: b.appPath), configuration: config)
            }
            browserBusy = nil
            browsers = await Task.detached(priority: .utility) { DarkModeBrowsers.installed() }.value
        }
    }

    // MARK: Safari

    /// The old style sheet, emptied at launch, thrown away once Safari no longer points to it.
    func discardOldStyleSheet() {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return HUD.show(DemoData.refusal, symbol: "info.circle.fill") }
        Remover.removeInternal(DarkModeStyleSheet.path)
        oldStyleSheet = FS.exists(DarkModeStyleSheet.path)
        if !oldStyleSheet { HUD.show("Ancienne feuille de style jetée", symbol: "checkmark.circle.fill") }
    }

    func open(_ path: String) {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    func openLink(_ url: String) {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        Finder.open(url)
    }

    func openPage() {
        guard let app = app ?? AppContext.model else { return }
        app.page = .darkmode
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }
}
