import SwiftUI

/// An on/off switch a module shows in the menu bar panel (Caféine, presse-papiers…).
struct QuickToggle: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let isOn: Bool
    let toggle: @MainActor () -> Void
}

/// What every module of `Features/<Module>/` gives the rest of the app.
/// All requirements have defaults, so a module only implements what it uses.
@MainActor
protocol AppModule: AnyObject {
    /// Short text next to the module in the sidebar (a count, a size…), or nil.
    var sidebarBadge: String? { get }
    /// Called once at launch of the real app (never in demo, snapshot or command line modes), or at the end of the
    /// first-launch cards: register hot keys, timers, scheduler jobs, observers.
    func start(app: AppModel)
    func stop()
    /// Fills the module with fictional data for `--demo` (README screenshots).
    func loadDemo()
    /// Selects a tab for `--snapshot --tab <name>` (ignore names that are not yours).
    func applySnapshotTab(_ tab: String)
    /// Switches shown in the menu bar panel.
    var quickToggles: [QuickToggle] { get }
    /// Fixed commands for the launcher (and Claude).
    func commands(app: AppModel) -> [AppCommand]
    /// Results computed from what the user typed (calculator, search…). Keep it fast: called on every keystroke.
    func results(for query: String, app: AppModel) -> [AppCommand]
    /// Pure checks run by `--selftest`: return the failures, or [] when all is well.
    func selfTest() -> [String]
    /// Lines printed by `--dump --only <rawValue of the page>`.
    func dump() -> [String]
}

extension AppModule {
    var sidebarBadge: String? { nil }
    func start(app: AppModel) {}
    func stop() {}
    func loadDemo() {}
    func applySnapshotTab(_ tab: String) {}
    var quickToggles: [QuickToggle] { [] }
    func commands(app: AppModel) -> [AppCommand] { [] }
    func results(for query: String, app: AppModel) -> [AppCommand] { [] }
    func selfTest() -> [String] { [] }
    func dump() -> [String] { [] }
}

/// The single list of modules. Adding a module means adding it here, in `Page`, `AppModel`, `PageView`, `BottomBar` and the
/// profiles that need it (`ToolProfileKind.pages`);
/// everything else (launcher, demo, self-tests, snapshots, menu bar) goes through this registry.
@MainActor
enum ModuleRegistry {
    static func modules(_ app: AppModel) -> [(page: Page, module: any AppModule)] {
        // One append per module: a single literal of existentials takes Xcode 16's type checker too long.
        var list: [(page: Page, module: any AppModule)] = []
        list.append((.performance, app.performance))
        list.append((.battery, app.battery))
        list.append((.phone, app.phone))
        list.append((.launcher, app.launcher))
        list.append((.hotkeys, app.hotkeys))
        list.append((.converter, app.converter))
        list.append((.wheel, app.wheel))
        list.append((.fillsign, app.fillSign))
        list.append((.youtube, app.youtube))
        list.append((.cinema, app.cinema))
        list.append((.translator, app.translator))
        list.append((.toolbox, app.toolbox))
        list.append((.clipboard, app.clipboard))
        list.append((.updates, app.updates))
        list.append((.network, app.network))
        list.append((.adblock, app.adblock))
        list.append((.darkmode, app.darkmode))
        list.append((.windows, app.windows))
        list.append((.automation, app.automation))
        list.append((.assistant, app.assistant))
        list.append((.protection, app.protection))
        list.append((.refuge, app.refuge))
        return list
    }

    static func module(for page: Page, app: AppModel) -> (any AppModule)? {
        modules(app).first { $0.page == page }?.module
    }

    /// `only`: just these pages' modules (`AppModel.startModules` holds the others back during the first-launch cards).
    static func startAll(_ app: AppModel, only pages: Set<Page>? = nil) {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        for (page, m) in modules(app) where pages?.contains(page) ?? true { m.start(app: app) }
    }

    /// Called when the app quits: modules release what they hold (Caféine, timers) and save their data.
    /// `only`: the modules that were started.
    static func stopAll(_ app: AppModel, only pages: Set<Page>? = nil) {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        for (page, m) in modules(app) where pages?.contains(page) ?? true { m.stop() }
    }

    static func loadDemo(_ app: AppModel) {
        for (_, m) in modules(app) { m.loadDemo() }
    }

    /// `only`: the page being captured, so that a tab name shared by two modules reaches the right one.
    static func applySnapshotTab(_ tab: String, only: Page? = nil, app: AppModel) {
        for (page, m) in modules(app) where only == nil || only == page { m.applySnapshotTab(tab) }
    }

    static func quickToggles(_ app: AppModel) -> [QuickToggle] {
        modules(app).flatMap { $0.module.quickToggles }
    }

    static func commands(_ app: AppModel) -> [AppCommand] {
        modules(app).flatMap { $0.module.commands(app: app) }
    }

    static func results(for query: String, app: AppModel) -> [AppCommand] {
        modules(app).flatMap { $0.module.results(for: query, app: app) }
    }

    /// Module self-tests plus the rules every command must follow.
    static func selfTest(_ app: AppModel) -> [String] {
        var failures: [String] = []
        for (page, m) in modules(app) {
            failures += m.selfTest().map { "[\(page.title)] \($0)" }
        }
        // Each floating window keeps to its own job: the launcher, the file window, the clipboard history.
        if DemoData.isEnabled { failures += LauncherModel.windowChecks(app).map { "[Lanceur] \($0)" } }
        var seen = Set<String>()
        for c in commands(app) {
            if !AppCommand.isValidID(c.id) { failures.append("Identifiant de commande invalide : \(c.id)") }
            if !seen.insert(c.id).inserted { failures.append("Identifiant de commande en double : \(c.id)") }
            // A cleanmyclaude://run/… link never runs a risky command by itself.
            if case .confirm = c.risk, c.urlSafe { failures.append("Commande risquée exécutable par lien : \(c.id)") }
        }
        // Navigation still works from a link; a system action asks first.
        let byID = Dictionary(commands(app).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, safe) in [("open_dashboard", true), ("launcher_open", true), ("act_scan_junk", true), ("sys_sleep", false),
                           ("sys_empty_trash", false), ("tool_password", false)] where byID[id]?.urlSafe != safe {
            failures.append("Commande \(id) : exécution par lien \(safe ? "refusée" : "permise") à tort")
        }
        if case .confirm = byID["sys_hidden_files"]?.risk {} else { failures.append("sys_hidden_files relance le Finder sans demander") }
        return failures
    }
}
