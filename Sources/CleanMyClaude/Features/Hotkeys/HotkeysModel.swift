import SwiftUI
import AppKit
import Carbon.HIToolbox

/// What a shortcut opens.
enum HotkeysTarget: Codable, Equatable {
    case app(path: String, name: String)
    case folder(path: String)
    case website(url: String)
    case command(id: String, title: String)

    var title: String {
        switch self {
        case .app(_, let name): return name
        case .folder(let path): return (path as NSString).lastPathComponent
        case .website(let url): return URL(string: url)?.host ?? url
        case .command(_, let title): return title
        }
    }

    var kind: String {
        switch self {
        case .app: return "App"
        case .folder(let path): return "Dossier · " + FS.pretty((path as NSString).deletingLastPathComponent)
        case .website(let url): return "Site web · " + url
        case .command: return "Commande de Clean My Claude"
        }
    }
}

struct HotkeysBinding: Codable, Identifiable, Equatable {
    var id = UUID()
    var target: HotkeysTarget
    var combo: KeyCombo?
    /// For an app already in front: pressing again hides it (like rcmd or Thor).
    var toggles = true

    var hotKeyID: String { "hk_" + id.uuidString }
}

@Observable
@MainActor
final class HotkeysModel: AppModule {
    var bindings: [HotkeysBinding] = [] {
        didSet { if !DemoData.isEnabled { store.value = bindings } }
    }
    /// Shortcuts macOS refused (already taken by another app), by binding.
    var refused: Set<UUID> = []
    var siteDraft = ""
    var showCommandPicker = false

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let store = JSONStore<[HotkeysBinding]>("app-shortcuts", default: [])

    init() {
        bindings = store.value
    }

    var sidebarBadge: String? {
        let n = bindings.filter { $0.combo != nil }.count
        return n > 0 ? "\(n)" : nil
    }

    // MARK: Module

    func start(app: AppModel) {
        self.app = app
        registerAll()
    }

    func stop() {
        store.flush()
    }

    func loadDemo() {
        let apps = DemoData.apps()
        func app(_ index: Int) -> HotkeysTarget {
            let a = apps[min(index, apps.count - 1)]
            return .app(path: a.path, name: a.name)
        }
        bindings = [
            HotkeysBinding(target: app(0), combo: Self.hyper("M")),
            HotkeysBinding(target: app(1), combo: Self.hyper("H")),
            HotkeysBinding(target: app(3), combo: Self.hyper("S")),
            HotkeysBinding(target: .folder(path: FS.home + "/Documents/Atelier"), combo: Self.hyper("A")),
            HotkeysBinding(target: .website(url: "https://claude.ai"), combo: Self.hyper("C")),
            HotkeysBinding(target: .command(id: "act_smart_scan", title: "Analyse intelligente"), combo: nil)
        ]
    }

    func commands(app: AppModel) -> [AppCommand] {
        var out = [
            AppCommand(id: "hk_new", title: "Créer un raccourci pour une app", subtitle: "Ouvre n'importe quelle app d'un raccourci clavier",
                       keywords: ["raccourci", "clavier", "hotkey", "shortcut"], icon: .symbol("keyboard", Theme.brand), group: .tools, hint: "Ouvrir") { ctx in
                ctx.app.page = .hotkeys
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
                return .done
            }
        ]
        // Each shortcut is also a launcher command (shown with its keys).
        for b in bindings {
            out.append(AppCommand(id: "hk_" + String(b.id.uuidString.prefix(8)), title: b.target.title,
                                  subtitle: "Raccourci " + (b.combo?.display ?? "sans touches") + " · " + b.target.kind,
                                  keywords: ["raccourci"], icon: icon(b.target), group: .tools, hint: b.combo?.display) { ctx in
                ctx.app.hotkeys.fire(b.id)
                return .done
            })
        }
        return out
    }

    func selfTest() -> [String] {
        var failures: [String] = []
        let sample = HotkeysBinding(target: .website(url: "https://claude.ai"), combo: KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey | controlKey)))
        if let data = try? JSONEncoder().encode(sample), let back = try? JSONDecoder().decode(HotkeysBinding.self, from: data), back == sample {
        } else {
            failures.append("raccourcis : enregistrement et relecture")
        }
        let taken = Set([Self.hyper("S")].compactMap { $0 })
        if let c = Self.suggestedCombo(for: "Safari", taken: taken), c == Self.hyper("S") { failures.append("raccourcis : lettre déjà prise réattribuée") }
        if Self.suggestedCombo(for: "Safari", taken: []) == nil { failures.append("raccourcis : aucune lettre proposée") }
        if Self.normalizedURL("claude.ai") != "https://claude.ai" { failures.append("raccourcis : adresse web sans https") }
        if Self.normalizedURL("javascript:alert(1)") != nil { failures.append("raccourcis : seules les adresses web sont acceptées") }
        return failures
    }

    func dump() -> [String] {
        bindings.map { "\($0.combo?.display ?? "—") → \($0.target.title) (\($0.target.kind))" }
    }

    // MARK: Shortcuts

    private func registerAll() {
        refused = []
        for b in bindings { register(b) }
    }

    private func register(_ b: HotkeysBinding) {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        let id = b.id
        let ok = HotKeyCenter.shared.register(b.hotKeyID, combo: b.combo) { [weak self] in self?.fire(id) }
        if b.combo != nil, !ok { refused.insert(id) } else { refused.remove(id) }
    }

    /// The other shortcut of the app that already uses `combo`, if any (launcher, windows, another binding).
    func conflict(for combo: KeyCombo?, except id: UUID) -> String? {
        guard let combo, let app = app ?? AppContext.model else { return nil }
        if app.launcher.combo == combo { return "le lanceur" }
        if let action = app.windows.combos.first(where: { $0.value == combo })?.key { return "Fenêtres (\(action.title))" }
        if let other = bindings.first(where: { $0.id != id && $0.combo == combo }) { return other.target.title }
        return nil
    }

    func setCombo(_ combo: KeyCombo?, for id: UUID) {
        guard let i = bindings.firstIndex(where: { $0.id == id }) else { return }
        if let combo, conflict(for: combo, except: id) != nil { return }
        bindings[i].combo = combo
        register(bindings[i])
    }

    func setToggles(_ on: Bool, for id: UUID) {
        guard let i = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[i].toggles = on
        register(bindings[i])
    }

    func remove(_ id: UUID) {
        guard let b = bindings.first(where: { $0.id == id }) else { return }
        HotKeyCenter.shared.unregister(b.hotKeyID)
        bindings.removeAll { $0.id == id }
        refused.remove(id)
    }

    /// Adds a target with a free ⌃⌥⌘ + letter already set (changeable), and registers it.
    func add(_ target: HotkeysTarget) {
        if let existing = bindings.first(where: { $0.target == target }) {
            HUD.show("Déjà là : \(existing.combo?.display ?? "sans raccourci")", symbol: "keyboard")
            return
        }
        let windowCombos = app.map { Array($0.windows.combos.values) } ?? []
        let taken = Set(bindings.compactMap(\.combo) + [app?.launcher.combo].compactMap { $0 } + windowCombos)
        let b = HotkeysBinding(target: target, combo: Self.suggestedCombo(for: target.title, taken: taken))
        bindings.append(b)
        register(b)
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Ajouter"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { add(.app(path: url.path, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Ajouter"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(.folder(path: url.path))
    }

    func addSite() {
        guard let url = Self.normalizedURL(siteDraft) else {
            HUD.show("Adresse web invalide", symbol: "xmark.octagon.fill")
            return
        }
        add(.website(url: url))
        siteDraft = ""
    }

    static func normalizedURL(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return s
    }

    // MARK: Firing

    func fire(_ id: UUID) {
        guard let b = bindings.first(where: { $0.id == id }), !DemoData.isEnabled else { return }
        switch b.target {
        case .app(let path, _):
            let url = URL(fileURLWithPath: path)
            let bundleID = Bundle(url: url)?.bundleIdentifier
            if b.toggles, let id = bundleID,
               let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first, running.isActive {
                running.hide()
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { DispatchQueue.main.async { HUD.show("Impossible d'ouvrir : \(error.localizedDescription)", symbol: "xmark.octagon.fill") } }
            }
        case .folder(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .website(let raw):
            if let url = URL(string: raw) { NSWorkspace.shared.open(url) }
        case .command(let commandID, _):
            guard let app = app ?? AppContext.model,
                  let command = ModuleRegistry.commands(app).first(where: { $0.id == commandID }) else { return }
            Task { await CommandRunner.execute(command, app: app) }
        }
    }

    // MARK: Suggestions

    /// Common apps found on this Mac that have no shortcut yet.
    var suggestions: [HotkeysTarget] {
        if DemoData.isEnabled {
            return DemoData.apps().dropFirst(5).prefix(6).map { .app(path: $0.path, name: $0.name) }
        }
        let ids = ["com.apple.finder", "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.apple.mail",
                   "com.apple.MobileSMS", "com.apple.Notes", "com.apple.iCal", "com.apple.Terminal", "com.microsoft.VSCode",
                   "com.anthropic.claudefordesktop", "com.tinyspeck.slackmacgap", "notion.id", "com.spotify.client",
                   "com.apple.Music", "com.figma.Desktop", "com.apple.dt.Xcode", "com.apple.systempreferences"]
        let bound = Set(bindings.compactMap { b -> String? in if case .app(let p, _) = b.target { return p }; return nil })
        return ids.compactMap { id -> HotkeysTarget? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), !bound.contains(url.path) else { return nil }
            return .app(path: url.path, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
    }

    func icon(_ target: HotkeysTarget) -> CommandIcon {
        switch target {
        case .app(let path, _), .folder(let path): return .file(path)
        case .website: return .symbol("globe", Theme.palette[1])
        case .command: return .symbol("sparkles", Theme.accent)
        }
    }

    // MARK: Keys

    /// ⌃⌥⌘ + a letter of the name not used yet (the first letter if possible).
    static func suggestedCombo(for name: String, taken: Set<KeyCombo>) -> KeyCombo? {
        let letters = Fuzzy.fold(name).uppercased().filter { $0.isLetter && $0.isASCII } + "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for letter in letters {
            guard let combo = hyper(String(letter)), !taken.contains(combo) else { continue }
            return combo
        }
        return nil
    }

    /// ⌃⌥⌘ + the key that types `letter` on the current keyboard (A is not at the same place in AZERTY and QWERTY).
    static func hyper(_ letter: String) -> KeyCombo? {
        guard let code = keyCode(for: letter) else { return nil }
        return KeyCombo(keyCode: code, modifiers: UInt32(controlKey | optionKey | cmdKey))
    }

    private static let letterCodes: [UInt32] = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J,
        kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T,
        kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z
    ].map { UInt32($0) }

    private static func keyCode(for letter: String) -> UInt32? {
        let wanted = letter.uppercased()
        // The letter keys first, then every key (on AZERTY, M sits where QWERTY has the semicolon).
        if let code = letterCodes.first(where: { KeyCombo.keyName($0) == wanted }) { return code }
        if let code = (0..<UInt32(128)).first(where: { KeyCombo.keyName($0) == wanted }) { return code }
        // No layout information (command line): the US position.
        guard let scalar = wanted.unicodeScalars.first, scalar.value >= 65, scalar.value <= 90 else { return nil }
        return letterCodes[Int(scalar.value - 65)]
    }
}
