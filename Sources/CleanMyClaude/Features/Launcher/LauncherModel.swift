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
        didSet {
            guard !DemoData.isEnabled else { return }
            UserDefaults.standard.set(includeFiles, forKey: "launcher.files")
            if includeFiles { startIndexIfAllowed() } else { fileIndex.stop() }
        }
    }
    /// The instant file index: off, being built, or ready with its number of items.
    var indexState: LauncherFileIndex.State = .off
    /// The user asked for the index (without Full Disk Access, reading Documents or Desktop makes macOS ask first).
    var indexConsent = UserDefaults.standard.bool(forKey: "launcher.indexConsent") {
        didSet { if !DemoData.isEnabled { UserDefaults.standard.set(indexConsent, forKey: "launcher.indexConsent") } }
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
    @ObservationIgnored let fileIndex = LauncherFileIndex()
    /// The demo's fictional files, searched like the real index.
    @ObservationIgnored private var demoFiles: LauncherFileIndex.Snapshot?
    @ObservationIgnored private var fileKinds: [String: Bool] = [:]

    /// Flat list of what is shown, in order (for keyboard navigation).
    var flat: [AppCommand] { sections.flatMap(\.items) }

    var sidebarBadge: String? { combo?.display }

    // MARK: Module

    func start(app: AppModel) {
        self.app = app
        combo = HotKeyCenter.shared.combo(for: Self.hotKeyID, fallback: Self.defaultCombo)
        hotKeyActive = HotKeyCenter.shared.register(Self.hotKeyID, combo: combo) { [weak self] in self?.toggle() }
        reindexApps()
        fileIndex.onChange = { [weak self] state in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.indexState = state
                    if self.isOpen, case .ready = state { self.refreshKeepingSelection() }
                }
            }
        }
        startIndexIfAllowed()
    }

    func stop() {
        fileIndex.stop()
    }

    /// With Full Disk Access, or once the user asked for it: no surprise macOS prompt at launch.
    private func startIndexIfAllowed() {
        guard includeFiles, !DemoData.isEnabled, !Snapshot.isActive, let app else { return }
        if app.fullDiskAccess || indexConsent { fileIndex.start() }
    }

    func enableIndex() {
        indexConsent = true
        includeFiles = true
        startIndexIfAllowed()
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
        demoFiles = LauncherFileIndex.snapshot(paths: LauncherDemoFiles.paths, home: FS.home)
        indexState = .ready(count: 148_312)
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
        failures += Self.fileIndexChecks()
        return failures
    }

    /// The index's rules and ranking, on made-up paths (nothing is read from the disk).
    static func fileIndexChecks() -> [String] {
        var failures: [String] = []
        let h = "/Users/test"
        let roots = [h, h + "/Library/Mobile Documents/com~apple~CloudDocs"]
        let indexable: [(String, Bool)] = [
            (h + "/Documents/Factures", true), (h + "/Library/Caches", false), (h + "/Developer/app/node_modules/x", false),
            (h + "/.config", false), (h + "/Developer/site/.git", false), (h + "/Pictures/Photos.photoslibrary/originals", false),
            (h + "/Library/Mobile Documents/com~apple~CloudDocs/Notes", true), ("/private/tmp", false)
        ]
        for (path, expected) in indexable where LauncherFileIndex.isIndexable(path, roots: roots, home: h) != expected {
            failures.append("index : « \(path) » \(expected ? "aurait dû être indexé" : "n'aurait pas dû l'être")")
        }
        let snapshot = LauncherFileIndex.snapshot(paths: [
            (h + "/Documents/Factures", true), (h + "/Documents/Factures/EDF", true),
            (h + "/Documents/Factures/EDF/mars 2026.pdf", false), (h + "/Documents/Résumé.pdf", false),
            (h + "/Documents/Archives/vieux/très/loin/facture.pdf", false), (h + "/Desktop/facture.pdf", false),
            (h + "/Documents/préfacture.txt", false), (h + "/Documents/Rapport annuel.pages", false)
        ], home: h)
        func first(_ q: String) -> String? {
            LauncherFileIndex.search(q, in: snapshot, checkDates: false).first.map { ($0.path as NSString).lastPathComponent }
        }
        if first("facture") != "facture.pdf" { failures.append("index : « facture » devrait d'abord trouver facture.pdf (\(first("facture") ?? "rien"))") }
        if LauncherFileIndex.search("facture", in: snapshot, checkDates: false).first?.path != h + "/Desktop/facture.pdf" {
            failures.append("index : le fichier du Bureau devrait passer avant celui rangé très loin")
        }
        if first("resume") != "Résumé.pdf" { failures.append("index : recherche sans accents") }
        if first("edf mars") != "mars 2026.pdf" { failures.append("index : un mot peut viser le dossier (« edf mars »)") }
        if first("rapport annuel") != "Rapport annuel.pages" { failures.append("index : plusieurs mots") }
        if !LauncherFileIndex.search("zzz", in: snapshot, checkDates: false).isEmpty { failures.append("index : résultat inventé") }
        let order = LauncherFileIndex.search("fact", in: snapshot, checkDates: false).map(\.name)
        if let pre = order.firstIndex(of: "préfacture.txt"), let start = order.firstIndex(of: "Factures"), pre < start {
            failures.append("index : un nom qui commence par la recherche passe avant un nom qui la contient")
        }
        if LauncherModel.fileID("/a/b") == LauncherModel.fileID("/a/c") || !AppCommand.isValidID(LauncherModel.fileID("/a/b é")) {
            failures.append("index : identifiants de fichiers")
        }
        return failures
    }

    func dump() -> [String] {
        let apps = LauncherAppIndex.scan()
        var lines: [String] = []
        if !DemoData.isEnabled {
            let index = LauncherFileIndex()
            let built = index.buildNow()
            lines.append("index des fichiers : \(Fmt.int(built.count)) éléments en \(String(format: "%.2f", built.seconds)) s")
            for q in ["facture", "rapport annuel", "png", "a"] {
                let t = Date()
                let hits = LauncherFileIndex.search(q, in: index.snapshot, limit: 5)
                lines.append("« \(q) » : \(String(format: "%.1f", Date().timeIntervalSince(t) * 1000)) ms → \(hits.prefix(3).map { FS.pretty($0.path) }.joined(separator: " · "))")
            }
        }
        return lines + ["\(apps.count) apps indexées : \(apps.prefix(8).map(\.name).joined(separator: ", "))…",
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
        let p = FloatingPanel(size: NSSize(width: LauncherView.width, height: LauncherView.height))
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
            case kVK_Tab:
                // Tab enters the selected folder ("~/Documents/Factures/"), or completes a path being typed.
                if let path = self.selectedFile, self.isPathQuery(self.query) || self.fileKinds[path] == true {
                    self.query = FS.pretty(path) + (self.fileKinds[path] == true ? "/" : "")
                    return nil
                }
                return event
            case kVK_ANSI_C where event.modifierFlags.contains([.command, .shift]):
                if let path = self.selectedFile {
                    _ = CommandRunner.copy(path)
                    HUD.show("Chemin copié", symbol: "doc.on.clipboard.fill")
                    return nil
                }
                return event
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

    /// The file or folder under the selection, for the preview pane.
    var selectedFile: String? {
        let items = flat
        guard items.indices.contains(selection), items[selection].group == .files,
              case .file(let path) = items[selection].icon else { return nil }
        return path
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
        // "~/Documents/fa" or "/Applications": browse the folders, nothing else.
        if isPathQuery(q) {
            fileWork?.cancel()
            fileQuery?.stop()
            let items = pathResults(q)
            sections = items.isEmpty ? [] : [LauncherSection(id: "path", title: "Dossier", items: items)]
            return
        }
        let instant = instantFiles(q)
        if let instant { fileResults = instant }
        var scored: [(AppCommand, Double)] = []
        for c in catalog {
            if let s = Fuzzy.best(q, title: c.title, keywords: c.keywords + [c.subtitle ?? ""]) {
                scored.append((c, s + CommandRunner.frecency(c.id) + c.boost))
            }
        }
        for c in ModuleRegistry.results(for: q, app: app) {
            scored.append((c, c.boost + CommandRunner.frecency(c.id)))
        }
        for c in fileResults { scored.append((c, c.boost + CommandRunner.frecency(c.id))) }
        scored.sort { $0.1 > $1.1 }
        sections = arrange(scored.map(\.0))
        if instant == nil { scheduleFileSearch(q) } else { fileWork?.cancel(); fileQuery?.stop() }
    }

    private func refreshKeepingSelection() {
        let keep = selection
        refreshKeepingFiles()
        selection = min(keep, max(0, flat.count - 1))
    }

    /// Best match first, then each kind of result together, capped per kind.
    private func arrange(_ ranked: [AppCommand]) -> [LauncherSection] {
        guard let best = ranked.first else { return [] }
        var out = [LauncherSection(id: "best", title: "Meilleur résultat", items: [best])]
        var byGroup: [CommandSection: [AppCommand]] = [:]
        for c in ranked.dropFirst() { byGroup[c.group, default: []].append(c) }
        let caps: [CommandSection: Int] = [.apps: 6, .files: 12, .emoji: 24, .settings: 4, .web: 2]
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

    // MARK: Files

    /// "dans facture edf": Spotlight looks inside the files too.
    static let contentPrefixes = ["dans ", "in "]

    func isPathQuery(_ q: String) -> Bool {
        q.hasPrefix("/") || q.hasPrefix("~/") || q == "~"
    }

    /// Results from the instant index, or nil when Spotlight must answer (content search, index not ready).
    private func instantFiles(_ q: String) -> [AppCommand]? {
        guard includeFiles, q.count >= 2, !q.hasPrefix(":"), !q.hasPrefix("?") else { return [] }
        if Self.contentPrefixes.contains(where: { q.lowercased().hasPrefix($0) }) { return nil }
        let snapshot: LauncherFileIndex.Snapshot
        if let demoFiles {
            snapshot = demoFiles
        } else if case .ready = indexState {
            snapshot = fileIndex.snapshot
        } else {
            return nil
        }
        let hits = LauncherFileIndex.search(q, in: snapshot, limit: 24, checkDates: !DemoData.isEnabled)
        return hits.enumerated().map { rank, hit in
            fileKinds[hit.path] = hit.isDir
            return fileCommand(hit.path, isDir: hit.isDir, boost: hit.score * 0.45 - Double(rank) * 0.01)
        }
    }

    /// The content of the folder being typed, filtered by the last part.
    private func pathResults(_ q: String) -> [AppCommand] {
        let expanded = FS.expand(q)
        let dir: String, partial: String
        if expanded.hasSuffix("/") || q == "~" {
            dir = q == "~" ? FS.home : String(expanded.dropLast())
            partial = ""
        } else {
            dir = (expanded as NSString).deletingLastPathComponent
            partial = (expanded as NSString).lastPathComponent
        }
        guard !DemoData.isEnabled, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.isEmpty ? "/" : dir) else { return [] }
        let wanted = Fuzzy.fold(partial)
        var rows: [(name: String, isDir: Bool, score: Int)] = []
        for name in names where partial.hasPrefix(".") || !name.hasPrefix(".") {
            let folded = Fuzzy.fold(name)
            let score = wanted.isEmpty ? 1 : (folded.hasPrefix(wanted) ? 2 : (folded.contains(wanted) ? 1 : 0))
            guard score > 0 else { continue }
            rows.append((name, FS.isDirectory((dir == "/" ? "" : dir) + "/" + name), score))
        }
        rows.sort { ($0.score, $0.isDir ? 1 : 0, $1.name.lowercased()) > ($1.score, $1.isDir ? 1 : 0, $0.name.lowercased()) }
        return rows.prefix(40).enumerated().map { rank, row in
            let path = (dir == "/" ? "" : dir) + "/" + row.name
            fileKinds[path] = row.isDir
            return fileCommand(path, isDir: row.isDir, boost: 400 - Double(rank))
        }
    }

    /// Spotlight, a moment after the last keystroke: for content searches, and while the index is not ready.
    private func scheduleFileSearch(_ q: String) {
        fileWork?.cancel()
        let content = Self.contentPrefixes.first { q.lowercased().hasPrefix($0) }
        let text = content.map { String(q.dropFirst($0.count)).trimmingCharacters(in: .whitespaces) } ?? q
        guard includeFiles, text.count >= (content == nil ? 3 : 2), !DemoData.isEnabled, !q.hasPrefix(":") else {
            if !fileResults.isEmpty { fileResults = [] }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.searchSpotlight(text, query: q, content: content != nil) }
        }
        fileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func searchSpotlight(_ text: String, query q: String, content: Bool) {
        fileQuery?.stop()
        if let fileObserver { NotificationCenter.default.removeObserver(fileObserver) }
        let mq = NSMetadataQuery()
        mq.predicate = content
            ? NSPredicate(format: "(kMDItemTextContent CONTAINS[cd] %@ OR kMDItemDisplayName CONTAINS[cd] %@) AND NOT (kMDItemContentType == 'com.apple.application-bundle')", text, text)
            : NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@ AND NOT (kMDItemContentType == 'com.apple.application-bundle')", text)
        mq.searchScopes = [NSMetadataQueryUserHomeScope]
        mq.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        fileObserver = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: mq, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let mq = self.fileQuery, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                mq.stop()
                var found: [AppCommand] = []
                for i in 0..<min(mq.resultCount, 16) {
                    guard let item = mq.result(at: i) as? NSMetadataItem,
                          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                    let isDir = (item.value(forAttribute: "kMDItemContentType") as? String) == "public.folder"
                    self.fileKinds[path] = isDir
                    found.append(self.fileCommand(path, isDir: isDir, boost: (content ? 600 : 300) - Double(i) * 5))
                }
                self.fileResults = found
                self.refreshKeepingSelection()
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

    /// Stable id per path (FNV-1a), so that the files opened often come first next time.
    static func fileID(_ path: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in path.utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return "file_" + String(hash, radix: 16)
    }

    private func fileCommand(_ path: String, isDir: Bool, boost: Double) -> AppCommand {
        let name = (path as NSString).lastPathComponent
        return AppCommand(id: Self.fileID(path), title: name, subtitle: FS.pretty((path as NSString).deletingLastPathComponent),
                          icon: .file(path), group: .files, hint: isDir ? "Ouvrir · ⇥ Entrer" : "Ouvrir · ⌘ Afficher", boost: boost) { ctx in
            if ctx.alternate { Finder.reveal(path) } else { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            return .done
        }
    }
}
