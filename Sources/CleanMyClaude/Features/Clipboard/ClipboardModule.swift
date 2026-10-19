import SwiftUI
import AppKit
import Carbon.HIToolbox

enum ClipboardFilterTab: String, CaseIterable, Identifiable {
    case all, text, links, images, files, pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tout"
        case .text: return "Texte"
        case .links: return "Liens"
        case .images: return "Images"
        case .files: return "Fichiers"
        case .pinned: return "Épinglés"
        }
    }

    func accepts(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text && item.textKind != .link
        case .links: return item.textKind == .link
        case .images: return item.kind == .image
        case .files: return item.kind == .files
        case .pinned: return item.pinned
        }
    }
}

/// How macOS (15.4 and later) lets the app read the clipboard.
enum ClipboardAccess {
    case unknown, notAsked, ask, allowed, denied

    @MainActor
    static var current: ClipboardAccess {
        if DemoData.isEnabled { return .allowed }
        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow: return .allowed
            case .alwaysDeny: return .denied
            case .ask: return .ask
            case .default: return .notAsked
            @unknown default: return .unknown
            }
        }
        #endif
        return .unknown
    }

    var status: Status {
        switch self {
        case .allowed: return .ok
        case .denied: return .bad
        case .ask: return .warn
        case .notAsked, .unknown: return .info
        }
    }

    var label: String {
        switch self {
        case .allowed: return "Toujours autorisé"
        case .denied: return "Refusé"
        case .ask: return "Demande à chaque fois"
        case .notAsked: return "Pas encore demandé"
        case .unknown: return "Libre"
        }
    }

    var explanation: String {
        switch self {
        case .allowed: return "macOS laisse Clean My Claude lire le presse-papiers sans te déranger."
        case .denied: return "Tu as refusé l'accès au presse-papiers : l'historique ne peut rien enregistrer. Rouvre Réglages Système › Confidentialité et sécurité, cherche le réglage du presse-papiers (« Coller depuis d'autres apps ») et choisis « Toujours autoriser » pour Clean My Claude."
        case .ask: return "macOS te demandera ton accord à chaque nouvelle copie. Pour un historique tranquille, choisis « Toujours autoriser » pour Clean My Claude dans Réglages Système › Confidentialité et sécurité."
        case .notAsked: return "À la première copie, macOS te demandera si Clean My Claude peut lire le presse-papiers : choisis « Toujours autoriser ». Tu pourras changer d'avis dans Réglages Système › Confidentialité et sécurité."
        case .unknown: return "Ta version de macOS ne demande pas d'autorisation pour lire le presse-papiers."
        }
    }
}

@Observable
@MainActor
final class ClipboardModel: AppModule {
    static let hotKeyID = "clipboard"

    var items: [ClipboardItem] = [] {
        didSet {
            historyStore.value = items
            keys = [:]
        }
    }
    var settings = ClipboardSettings() {
        didSet { settingsStore.value = settings }
    }
    var filter: ClipboardFilterTab = .all
    var search = ""
    var selection: UUID?
    var combo: KeyCombo?
    /// Copies left out since launch (secrets, excluded apps), shown on the page.
    var skipped = 0
    var watching = false
    /// For `--snapshot --tab intro`: the page as it looks before the user turns the history on.
    var showIntro = false

    /// The general pasteboard; the live tests swap in a private one so the user's clipboard is never touched.
    @ObservationIgnored var pasteboard = NSPasteboard.general
    @ObservationIgnored private let historyStore = JSONStore<[ClipboardItem]>("clipboard-history", default: [])
    @ObservationIgnored private let settingsStore = JSONStore<ClipboardSettings>("clipboard", default: ClipboardSettings())
    @ObservationIgnored private var keys: [UUID: String] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChange = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored private weak var app: AppModel?

    init() {
        settings = settingsStore.value
        items = historyStore.value
    }

    var isActive: Bool { settings.enabled && settings.acknowledged }

    // MARK: Module

    var sidebarBadge: String? {
        if isActive { return items.isEmpty ? nil : Fmt.int(items.count) }
        return settings.acknowledged ? "Pause" : nil
    }

    func start(app: AppModel) {
        self.app = app
        started = true
        combo = HotKeyCenter.shared.combo(for: Self.hotKeyID, fallback: nil)
        HotKeyCenter.shared.register(Self.hotKeyID, combo: combo) { [weak self] in self?.showInLauncher() }
        prune()
        let names = Set(items.compactMap(\.image).flatMap { [$0.file, $0.thumb] })
        _ = ClipboardStorage.removeOrphans(keeping: names)
        if isActive { startWatching() }
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        stopWatching()
        historyStore.flush()
        settingsStore.flush()
    }

    func applySnapshotTab(_ tab: String) {
        if tab == "intro" { showIntro = true }
        if let f = ClipboardFilterTab(rawValue: tab) { filter = f }
    }

    var quickToggles: [QuickToggle] {
        [QuickToggle(id: "clip_history", title: "Presse-papiers", symbol: "doc.on.clipboard", isOn: isActive) { [weak self] in
            guard let self else { return }
            if self.settings.acknowledged {
                self.setEnabled(!self.settings.enabled)
            } else {
                // The first time, the page explains what is recorded before anything starts.
                self.openPage()
            }
        }]
    }

    func commands(app: AppModel) -> [AppCommand] { ClipboardLauncher.commands(self) }

    func results(for query: String, app: AppModel) -> [AppCommand] { ClipboardLauncher.results(query, model: self) }

    // MARK: On / off

    func setEnabled(_ on: Bool) {
        settings.enabled = on
        if on { settings.acknowledged = true }
        if on { startWatching() } else { stopWatching() }
        HUD.show(on ? "Historique du presse-papiers activé" : "Historique du presse-papiers en pause",
                 symbol: on ? "doc.on.clipboard.fill" : "pause.circle.fill")
    }

    func openPage() {
        guard let app = app ?? AppContext.model else { return }
        app.page = .clipboard
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    func showInLauncher() {
        guard let app = app ?? AppContext.model else { return }
        app.launcher.show()
        app.launcher.query = "cb "
    }

    func setCombo(_ c: KeyCombo?) {
        // A shortcut already used elsewhere in Clean My Claude would answer only one of the two.
        if let c, let other = (app ?? AppContext.model)?.hotkeys.owner(of: c, except: .clipboard) {
            HUD.show("\(c.display) est déjà utilisé par \(other).", symbol: "exclamationmark.triangle.fill")
            return
        }
        combo = c
        HotKeyCenter.shared.change(Self.hotKeyID, to: c) { [weak self] in self?.showInLauncher() }
    }

    // MARK: Watching

    /// Reads only the change counter, twice a second or so; the content is read only when it changed.
    private func startWatching() {
        guard started, timer == nil, isActive, !DemoData.isEnabled, !Snapshot.isActive else { return }
        // What was already on the clipboard before is not recorded.
        lastChange = pasteboard.changeCount
        let t = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        watching = true
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        watching = false
    }

    private func poll() {
        let pb = pasteboard
        let change = pb.changeCount
        guard change != lastChange else { return }
        lastChange = change
        // Reading the list of types does not read the content (and does not make macOS ask anything).
        let types = (pb.types ?? []).map(\.rawValue)
        guard !types.isEmpty else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if ClipboardFilter.isSensitive(types) || ClipboardFilter.isExcluded(front?.bundleIdentifier, list: settings.excluded) {
            skipped += 1
            return
        }
        if ClipboardAccess.current == .denied { return }
        let source = (name: front?.localizedName, id: front?.bundleIdentifier, path: front?.bundleURL?.path)
        let now = Date()

        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            // Files left out: the file name the Finder also puts on the clipboard as text is not kept either.
            guard settings.keepFiles else { return }
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                let paths = urls.map(\.path)
                add(ClipboardItem(kind: .files, files: paths, digest: ClipboardStorage.digest(Data(paths.joined(separator: "\n").utf8)),
                                  date: now, firstDate: now, appName: source.name, appBundleID: source.id, appPath: source.path))
                return
            }
        }
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.utf8.count <= ClipboardHistory.maxTextBytes else { skipped += 1; return }
            add(ClipboardItem(kind: .text, text: text, digest: ClipboardStorage.digest(Data(text.utf8)),
                              date: now, firstDate: now, appName: source.name, appBundleID: source.id, appPath: source.path))
            return
        }
        guard settings.keepImages else { return }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")]
        guard let type = imageTypes.first(where: { types.contains($0.rawValue) }), let data = pb.data(forType: type),
              data.count <= ClipboardStorage.maxImageBytes else { return }
        Task.detached(priority: .utility) { [self] in
            guard let p = ClipboardStorage.prepare(data) else { return }
            await MainActor.run {
                let info = ClipboardImageInfo(file: p.file, thumb: p.thumb, width: p.width, height: p.height, bytes: p.bytes)
                self.add(ClipboardItem(id: p.id, kind: .image, image: info, digest: p.digest, date: now, firstDate: now,
                                       appName: source.name, appBundleID: source.id, appPath: source.path))
            }
        }
    }

    private func add(_ item: ClipboardItem) {
        let r = ClipboardHistory.insert(item, into: items)
        if r.duplicate, let image = item.image {
            ClipboardStorage.remove(image.file)
            ClipboardStorage.remove(image.thumb)
        }
        items = r.list
        prune()
    }

    /// Applies the caps (count, weight, age) and deletes the images of what goes away.
    func prune() {
        let r = ClipboardHistory.prune(items, maxItems: settings.maxItems, maxBytes: settings.maxStorageMB * 1_000_000,
                                       retentionDays: settings.retentionDays)
        guard !r.removed.isEmpty || r.kept.map(\.id) != items.map(\.id) else { return }
        deleteFiles(of: r.removed)
        items = r.kept
    }

    private func deleteFiles(of removed: [ClipboardItem]) {
        for item in removed {
            if let i = item.image {
                ClipboardStorage.remove(i.file)
                ClipboardStorage.remove(i.thumb)
            }
        }
    }

    // MARK: Actions

    /// Puts the item back on the clipboard, then pastes it into the app in front when allowed.
    @discardableResult
    func recopy(_ item: ClipboardItem, paste: Bool = false) -> CommandOutcome {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return .message(DemoData.refusal) }
        let pb = pasteboard
        switch item.kind {
        case .text:
            pb.clearContents()
            pb.setString(item.text ?? "", forType: .string)
        case .files:
            let urls = (item.files ?? []).filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return .failed("Ce fichier n'existe plus.") }
            pb.clearContents()
            pb.writeObjects(urls)
        case .image:
            guard let info = item.image, let data = ClipboardStorage.read(info.file) else { return .failed("Cette image n'est plus disponible.") }
            pb.clearContents()
            pb.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        }
        // Our own copy is not recorded again: the item just moves to the top.
        lastChange = pb.changeCount
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            var moved = items.remove(at: i)
            moved.date = Date()
            items.insert(moved, at: 0)
        }
        if paste && canPaste {
            // The launcher has just closed: give the app underneath a moment to take the keyboard back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Self.postPaste() }
            return .done
        }
        return .copied(item.kind == .text ? (item.text ?? "") : item.title)
    }

    var canPaste: Bool { settings.pasteDirectly && AppPermission.accessibility.isGranted && !DemoData.isEnabled }

    /// ⌘V for the app in front (needs Accessibility).
    private static func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Rewrites what is on the clipboard as plain text (no fonts, colors or links), then pastes it when allowed.
    func pastePlainText() -> CommandOutcome {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return .message(DemoData.refusal) }
        let pb = pasteboard
        guard let text = pb.string(forType: .string), !text.isEmpty else { return .failed("Le presse-papiers ne contient pas de texte.") }
        let types = (pb.types ?? []).map(\.rawValue)
        // Already plain (a password from a manager, typically): left as it is, so the change count the manager
        // compares before clearing it does not move.
        if !ClipboardFilter.isPlainTextOnly(types) {
            // Secrets and temporary data keep their markers: histories (this one included) still skip them.
            let markers = ClipboardFilter.markers(in: types).map { NSPasteboard.PasteboardType($0) }
            let saved = markers.map { ($0, pb.data(forType: $0) ?? Data()) }
            pb.clearContents()
            pb.declareTypes([.string] + markers, owner: nil)
            pb.setString(text, forType: .string)
            for (type, data) in saved { pb.setData(data, forType: type) }
            lastChange = pb.changeCount
            if markers.contains(where: { $0.rawValue == ClipboardFilter.concealed }) {
                // The app that copied the secret no longer recognizes the clipboard: clear it after 90 s ourselves.
                let count = pb.changeCount
                DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                    if pb.changeCount == count { pb.clearContents() }
                }
            }
        }
        if canPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Self.postPaste() }
            return .done
        }
        return .message("Texte brut prêt : colle-le avec ⌘V")
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        if !items[i].pinned { prune() }
    }

    func delete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        deleteFiles(of: [items[i]])
        items.remove(at: i)
        if selection == id { selection = nil }
    }

    /// Clears the history; pinned items stay unless `includingPinned`.
    func clear(includingPinned: Bool = false) {
        let removed = items.filter { includingPinned || !$0.pinned }
        deleteFiles(of: removed)
        items.removeAll { includingPinned || !$0.pinned }
        selection = nil
    }

    func exclude(bundleID: String, name: String) {
        guard !ClipboardFilter.isExcluded(bundleID, list: settings.excluded) else { return }
        settings.excluded.append(ClipboardExcludedApp(bundleID: bundleID, name: name))
    }

    func removeExclusion(_ bundleID: String) {
        settings.excluded.removeAll { $0.bundleID == bundleID }
    }

    /// Picks an app in /Applications and adds it to the excluded list.
    func chooseExcludedApp() {
        guard !DemoData.isEnabled else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignorer"
        panel.message = "Ce que tu copies dans ces apps ne sera jamais enregistré."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            exclude(bundleID: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
    }

    // MARK: Search

    func key(_ item: ClipboardItem) -> String {
        if let k = keys[item.id] { return k }
        let k = item.searchKey
        keys[item.id] = k
        return k
    }

    /// What the page shows: the filter and the search applied, pinned items first.
    var visible: [ClipboardItem] {
        let q = Fuzzy.fold(search.trimmingCharacters(in: .whitespaces))
        let base = items.filter { filter.accepts($0) }
        return ClipboardHistory.search(base, query: q, keys: key, limit: .max, pinnedFirst: true)
    }

    func count(_ tab: ClipboardFilterTab) -> Int { items.filter { tab.accepts($0) }.count }

    var totalBytes: Int { items.reduce(0) { $0 + $1.bytes } }

    // MARK: Demo

    func loadDemo() {
        settings = ClipboardSettings()
        settings.enabled = true
        settings.acknowledged = true
        combo = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey | optionKey))
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func app(_ name: String, _ id: String) -> (String, String, String) { (name, id, "/Applications/\(name).app") }
        let helios = app("Hélios Code", "com.helios.code"), ruche = app("Ruche", "com.ruche.desktop")
        let claude = app("Claude", "com.anthropic.claudefordesktop"), pixel = app("Pixelune", "com.pixelune.Pixelune")
        let tisserand = app("Tisserand", "app.tisserand.mac")
        func text(_ s: String, _ minutes: Double, _ a: (String, String, String), pinned: Bool = false, count: Int = 1) -> ClipboardItem {
            ClipboardItem(kind: .text, text: s, digest: ClipboardStorage.digest(Data(s.utf8)), date: ago(minutes), firstDate: ago(minutes + 600),
                          count: count, pinned: pinned, appName: a.0, appBundleID: a.1, appPath: a.2)
        }
        func image(_ kind: Int, _ w: Int, _ h: Int, _ minutes: Double, _ a: (String, String, String)) -> ClipboardItem {
            let id = UUID()
            let info = ClipboardImageInfo(file: "demo-\(kind).png", thumb: "demo-\(kind)-thumb.png", width: w, height: h, bytes: w * h / 3)
            if let cg = ClipboardThumbs.demoImage(kind: kind) { ClipboardThumbs.put(info.thumb, cg) }
            return ClipboardItem(id: id, kind: .image, image: info, digest: "demo-image-\(kind)", date: ago(minutes), firstDate: ago(minutes),
                                 appName: a.0, appBundleID: a.1, appPath: a.2)
        }
        items = [
            text("git commit -m \"Boussole : nouvelle page d'accueil\"", 2, helios),
            text("https://atelier-camille.fr/projets/boussole/maquettes", 6, ruche),
            image(0, 2880, 1800, 11, pixel),
            text("#D97757", 19, pixel),
            text("Rendez-vous jeudi 14 h avec l'équipe Lumière, salle Ventoux (3e étage). Penser aux maquettes imprimées.", 34, tisserand, count: 3),
            text("func greet(_ name: String) -> String {\n    \"Bonjour, \\(name) !\"\n}", 52, helios),
            ClipboardItem(kind: .files, files: [DemoData.home + "/Documents/Devis-Atelier.pdf"], digest: "demo-files", date: ago(75), firstDate: ago(75),
                          appName: "Finder", appBundleID: "com.apple.finder", appPath: "/System/Library/CoreServices/Finder.app"),
            text("Peux-tu résumer ce compte rendu en cinq points, avec les décisions et les prochaines étapes ?", 130, claude),
            image(1, 1600, 1000, 190, ruche),
            text("12 rue des Lilas, 69007 Lyon", 60 * 24 * 2, tisserand, pinned: true, count: 14),
            text("camille@atelier-camille.fr", 60 * 24 * 6, ruche, pinned: true, count: 9),
            text("Bien à toi,\nCamille — Atelier Camille, design et illustration", 60 * 24 * 9, tisserand, pinned: true, count: 21)
        ]
        skipped = 4
        selection = items.first?.id
    }

    // MARK: Checks

    func selfTest() -> [String] { ClipboardChecks.run(self) }

    func dump() -> [String] {
        let byKind = ClipboardKind.allCases.map { k in "\(k.rawValue) \(items.filter { $0.kind == k }.count)" }.joined(separator: ", ")
        return [
            "Historique : \(isActive ? "actif" : (settings.acknowledged ? "en pause" : "jamais activé")) · surveillance \(watching ? "en cours" : "arrêtée")",
            "Éléments : \(items.count) (\(byKind)) · \(items.filter(\.pinned).count) épinglés · \(Fmt.bytes(totalBytes))",
            "Dossier des images : \(FS.pretty(ClipboardStorage.folder.path)) · \(Fmt.bytes(ClipboardStorage.folderSize()))",
            "Plafonds : \(settings.maxItems) éléments, \(settings.maxStorageMB) Mo, \(settings.retentionDays == 0 ? "sans limite d'âge" : "\(settings.retentionDays) jours")",
            "Accès macOS au presse-papiers : \(ClipboardAccess.current.label) · Accessibilité : \(AppPermission.accessibility.isGranted ? "accordée" : "non accordée")",
            "Apps ignorées : \(settings.excluded.map(\.name).joined(separator: ", "))",
            "Raccourci : \(combo?.display ?? "aucun")",
            "Types ignorés : \(ClipboardFilter.sensitiveTypes.sorted().joined(separator: ", "))"
        ]
    }
}
