import SwiftUI
import AppKit
import Carbon.HIToolbox

/// One block of the results list.
struct LauncherSection: Identifiable {
    let id: String
    let title: String
    let items: [AppCommand]
}

@Observable
@MainActor
final class LauncherModel: AppModule {
    static let hotKeyID = "launcher"
    /// ⌥Espace, like Alfred or Raycast. macOS 27 accepts it; the page lets the user pick another one.
    static let defaultCombo = KeyCombo(keyCode: KeyCombo.space, modifiers: UInt32(optionKey))

    var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    var sections: [LauncherSection] = []
    var selection = 0
    var isOpen = false
    var combo: KeyCombo?
    var hotKeyActive = false
    var includeFiles = UserDefaults.standard.object(forKey: "launcher.files") as? Bool ?? true {
        didSet { UserDefaults.standard.set(includeFiles, forKey: "launcher.files") }
    }

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var panel: FloatingPanel?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var catalog: [AppCommand] = []
    @ObservationIgnored private var apps: [LauncherApp] = []
    @ObservationIgnored private var appsIndexedAt = Date.distantPast
    @ObservationIgnored private var fileResults: [AppCommand] = []
    @ObservationIgnored private var fileQuery: NSMetadataQuery?
    @ObservationIgnored private var fileObserver: NSObjectProtocol?
    @ObservationIgnored private var fileWork: DispatchWorkItem?

    /// Flat list of what is shown, in order (for keyboard navigation).
    var flat: [AppCommand] { sections.flatMap(\.items) }

    var sidebarBadge: String? { combo?.display }

    // MARK: Module

    func start(app: AppModel) {
        self.app = app
        combo = HotKeyCenter.shared.combo(for: Self.hotKeyID, fallback: Self.defaultCombo)
        hotKeyActive = HotKeyCenter.shared.register(Self.hotKeyID, combo: combo) { [weak self] in self?.toggle() }
        reindexApps()
    }

    func setCombo(_ newCombo: KeyCombo?) {
        combo = newCombo
        hotKeyActive = HotKeyCenter.shared.change(Self.hotKeyID, to: newCombo) { [weak self] in self?.toggle() }
    }

    func loadDemo() {
        combo = Self.defaultCombo
        hotKeyActive = true
        apps = DemoData.apps().map { LauncherApp(name: $0.name, path: $0.path, keywords: []) }
        appsIndexedAt = Date()
        for (id, n) in [("act_smart_scan", 14), ("open_converter", 9), ("sys_darkmode", 7), ("set_com_apple_wifi_settings_extension", 4)] {
            CommandRunner.usage.value[id] = .init(count: n, last: Date().addingTimeInterval(-3600))
        }
    }

    func commands(app: AppModel) -> [AppCommand] {
        LauncherSystem.commands() + LauncherSettings.commands() + LauncherAppActions.commands(app) + [
            AppCommand(id: "launcher_open", title: "Ouvrir le lanceur", keywords: ["lanceur", "launcher", "recherche"],
                       icon: .spark, group: .actions) { ctx in
                ctx.app.launcher.show()
                return .done
            }
        ]
    }

    func results(for query: String, app: AppModel) -> [AppCommand] {
        LauncherDynamic.results(query)
    }

    func selfTest() -> [String] {
        var failures: [String] = []
        let calc: [(String, Double?)] = [
            ("2+2", 4), ("3*(4+1)", 15), ("2^10", 1024), ("1,5*2", 3), ("10/4", 2.5), ("20%", 0.2), ("sqrt(16)", 4),
            ("-3+5", 2), ("2x3", 6), ("2++", nil), ("bonjour", nil), ("2024", nil), ("(1+2", nil), ("1/0", nil)
        ]
        for (input, expected) in calc {
            let got = LauncherCalculator.evaluate(input)
            if let e = expected {
                if got == nil || abs(got! - e) > 1e-9 { failures.append("calcul « \(input) » = \(got.map { "\($0)" } ?? "rien"), attendu \(e)") }
            } else if got != nil {
                failures.append("calcul « \(input) » aurait dû être refusé")
            }
        }
        let units: [(String, Double)] = [("10 km en mi", 6.2137), ("100 °F en °C", 37.7778), ("5 Go en Mo", 5000),
                                          ("1 Gio en Mo", 1073.7418), ("2 h en min", 120), ("3 jours en h", 72), ("8 Mb en MB", 1)]
        for (input, expected) in units {
            let got = LauncherUnits.convert(input)?.value
            if got == nil || abs(got! - expected) > 0.001 { failures.append("conversion « \(input) » = \(got.map { "\($0)" } ?? "rien")") }
        }
        if LauncherUnits.convert("10 km en kg") != nil { failures.append("conversion km → kg aurait dû être refusée") }
        if Fuzzy.score("reglages", in: "Réglages Système") == nil { failures.append("recherche sans accents") }
        if Fuzzy.score("vsc", in: "Visual Studio Code") == nil { failures.append("recherche par initiales") }
        if LauncherEmoji.search("coeur").isEmpty { failures.append("emoji introuvables") }
        return failures
    }

    func dump() -> [String] {
        let apps = LauncherAppIndex.scan()
        return ["\(apps.count) apps indexées : \(apps.prefix(8).map(\.name).joined(separator: ", "))…",
                "2,5*(3+1) = \(LauncherCalculator.evaluate("2,5*(3+1)").map(LauncherCalculator.format) ?? "?")",
                "10 km en miles : \(LauncherUnits.convert("10 km en miles")?.to ?? "?")",
                "heure Tokyo : \(LauncherWorldClock.answer("heure Tokyo")?.time ?? "?")"]
    }

    /// Fills the results as if the user had typed `text` (for `--snapshot`).
    func preview(_ text: String, app: AppModel) {
        self.app = app
        catalog = ModuleRegistry.commands(app) + LauncherAppIndex.commands(apps)
        query = text
        refresh()
    }

    // MARK: Panel

    func toggle() {
        isOpen ? hide() : show()
    }

    func show() {
        guard let app = app ?? AppContext.model else { return }
        self.app = app
        if !DemoData.isEnabled, Date().timeIntervalSince(appsIndexedAt) > 600 { reindexApps() }
        catalog = ModuleRegistry.commands(app) + LauncherAppIndex.commands(apps)
        query = ""
        refresh()
        let p = panel ?? makePanel()
        p.setContent(LauncherView().environment(app))
        p.present()
        isOpen = true
        installKeyMonitor()
    }

    func hide() {
        panel?.close()
    }

    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(size: NSSize(width: 700, height: 470))
        p.onClose = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isOpen = false
                self.removeKeyMonitor()
                self.fileQuery?.stop()
            }
        }
        panel = p
        return p
    }

    /// Arrows, Return and Esc are caught before the text field sees them.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            switch Int(event.keyCode) {
            case kVK_DownArrow:
                self.move(1); return nil
            case kVK_UpArrow:
                self.move(-1); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.runSelected(alternate: event.modifierFlags.contains(.command)); return nil
            case kVK_Escape:
                if self.query.isEmpty { self.hide() } else { self.query = "" }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func move(_ delta: Int) {
        let count = flat.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    func runSelected(alternate: Bool = false) {
        let items = flat
        guard items.indices.contains(selection) else { return }
        run(items[selection], alternate: alternate)
    }

    func run(_ command: AppCommand, alternate: Bool = false) {
        guard let app else { return }
        let q = query
        hide()
        Task { await CommandRunner.execute(command, app: app, query: q, alternate: alternate) }
    }

    // MARK: Search

    private func reindexApps() {
        appsIndexedAt = Date()
        Task {
            let found = await Task.detached(priority: .utility) { LauncherAppIndex.scan() }.value
            apps = found
            if isOpen, let app { catalog = ModuleRegistry.commands(app) + LauncherAppIndex.commands(found); refresh() }
        }
    }

    func refresh() {
        guard let app else { sections = []; return }
        let q = query.trimmingCharacters(in: .whitespaces)
        selection = 0
        if q.isEmpty {
            sections = suggestions()
            fileResults = []
            fileQuery?.stop()
            return
        }
        var scored: [(AppCommand, Double)] = []
        for c in catalog {
            if let s = Fuzzy.best(q, title: c.title, keywords: c.keywords + [c.subtitle ?? ""]) {
                scored.append((c, s + CommandRunner.frecency(c.id) + c.boost))
            }
        }
        for c in ModuleRegistry.results(for: q, app: app) {
            scored.append((c, c.boost + CommandRunner.frecency(c.id)))
        }
        for c in fileResults { scored.append((c, c.boost)) }
        scored.sort { $0.1 > $1.1 }
        sections = arrange(scored.map(\.0))
        scheduleFileSearch(q)
    }

    /// Best match first, then each kind of result together, capped per kind.
    private func arrange(_ ranked: [AppCommand]) -> [LauncherSection] {
        guard let best = ranked.first else { return [] }
        var out = [LauncherSection(id: "best", title: "Meilleur résultat", items: [best])]
        var byGroup: [CommandSection: [AppCommand]] = [:]
        for c in ranked.dropFirst() { byGroup[c.group, default: []].append(c) }
        let caps: [CommandSection: Int] = [.apps: 6, .files: 8, .emoji: 24, .settings: 4, .web: 2]
        for g in CommandSection.allCases {
            guard let items = byGroup[g], !items.isEmpty else { continue }
            out.append(LauncherSection(id: "\(g.rawValue)", title: g.title, items: Array(items.prefix(caps[g] ?? 5))))
        }
        return out
    }

    private func suggestions() -> [LauncherSection] {
        let used = catalog.filter { CommandRunner.frecency($0.id) > 0 }
            .sorted { CommandRunner.frecency($0.id) > CommandRunner.frecency($1.id) }
            .prefix(6)
        let picks = ["act_smart_scan", "open_converter", "open_clipboard", "sys_darkmode", "sys_empty_trash", "act_free_ram"]
        let defaults = picks.compactMap { id in catalog.first { $0.id == id } }.filter { d in !used.contains { $0.id == d.id } }
        var out: [LauncherSection] = []
        if !used.isEmpty { out.append(LauncherSection(id: "recent", title: "Les plus utilisés", items: Array(used))) }
        out.append(LauncherSection(id: "ideas", title: "Suggestions", items: Array(defaults.prefix(6 - min(used.count, 3)))))
        return out
    }

    /// Spotlight search in the home folder, a moment after the last keystroke.
    private func scheduleFileSearch(_ q: String) {
        fileWork?.cancel()
        guard includeFiles, q.count >= 3, !DemoData.isEnabled, !q.hasPrefix(":") else {
            if !fileResults.isEmpty { fileResults = [] }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.searchFiles(q) }
        }
        fileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func searchFiles(_ q: String) {
        fileQuery?.stop()
        if let fileObserver { NotificationCenter.default.removeObserver(fileObserver) }
        let mq = NSMetadataQuery()
        mq.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@ AND NOT (kMDItemContentType == 'com.apple.application-bundle')", q)
        mq.searchScopes = [NSMetadataQueryUserHomeScope]
        mq.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        fileObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: mq, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let mq = self.fileQuery, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                mq.stop()
                var found: [AppCommand] = []
                for i in 0..<min(mq.resultCount, 12) {
                    guard let item = mq.result(at: i) as? NSMetadataItem,
                          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                    found.append(Self.fileCommand(path, rank: i))
                }
                self.fileResults = found
                let keep = self.selection
                self.refreshKeepingFiles()
                self.selection = min(keep, max(0, self.flat.count - 1))
            }
        }
        fileQuery = mq
        mq.start()
    }

    /// Re-ranks with the latest file results, without starting a new file search.
    private func refreshKeepingFiles() {
        let work = fileWork
        refresh()
        fileWork?.cancel()
        fileWork = work
    }

    private static func fileCommand(_ path: String, rank: Int) -> AppCommand {
        let name = (path as NSString).lastPathComponent
        return AppCommand(id: "file_\(rank)", title: name, subtitle: FS.pretty((path as NSString).deletingLastPathComponent),
                          icon: .file(path), group: .files, hint: "Ouvrir · ⌘ Afficher", boost: 300 - Double(rank) * 5) { ctx in
            if ctx.alternate { Finder.reveal(path) } else { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            return .done
        }
    }
}
