import SwiftUI
import AppKit
import Carbon.HIToolbox

/// What a shortcut opens.
enum HotkeysTarget: Codable, Equatable {
    case app(path: String, name: String)
    case folder(path: String)
    case file(path: String)
    case website(url: String)
    case command(id: String, title: String)

    var title: String {
        switch self {
        case .app(_, let name): return name
        case .folder(let path), .file(let path): return (path as NSString).lastPathComponent
        case .website(let url): return URL(string: url)?.host ?? url
        case .command(_, let title): return title
        }
    }

    var kind: String {
        switch self {
        case .app: return "App"
        case .folder(let path): return "Dossier · " + FS.pretty((path as NSString).deletingLastPathComponent)
        case .file(let path): return "Fichier · " + FS.pretty((path as NSString).deletingLastPathComponent)
        case .website(let url): return "Site web · " + url
        case .command: return "Commande de Clean My Claude"
        }
    }

    /// What makes two targets the same (a command keeps its shortcut if its title changes).
    var key: String {
        switch self {
        case .app(let path, _): return "app:" + path
        case .folder(let path): return "folder:" + path
        case .file(let path): return "file:" + path
        case .website(let url): return "web:" + url
        case .command(let id, _): return "cmd:" + id
        }
    }
}

/// Who asks whether a shortcut is free (it does not conflict with itself).
/// `.windows` leaves out every window action: that page moves a shortcut from one action to another itself.
enum HotkeysOwner: Equatable {
    case launcher, clipboard, windows
    case binding(String)

    var bindingKey: String? {
        if case .binding(let key) = self { return key }
        return nil
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
        // Which launcher results can get a shortcut, and what they open.
        func command(_ id: String, _ group: CommandSection, _ icon: CommandIcon) -> AppCommand {
            AppCommand(id: id, title: "Essai", icon: icon, group: group) { _ in .done }
        }
        let ids: Set<String> = ["open_translator", "act_smart_scan"]
        let folders: (String) -> Bool = { $0.hasSuffix("/Factures") }
        let targets: [(AppCommand, String?)] = [
            (command("app_x", .apps, .file("/Applications/Essai.app")), "app:/Applications/Essai.app"),
            (command("file_1", .files, .file("/Users/t/Documents/Factures")), "folder:/Users/t/Documents/Factures"),
            (command("file_2", .files, .file("/Users/t/Documents/devis.pdf")), "file:/Users/t/Documents/devis.pdf"),
            (command("open_translator", .actions, .symbol("character.bubble")), "cmd:open_translator"),
            (command("calc_result", .calculator, .symbol("function")), nil),
            (command("hk_1234", .tools, .symbol("keyboard")), nil)
        ]
        for (c, expected) in targets where Self.target(for: c, catalogIDs: ids, isFolder: folders)?.key != expected {
            failures.append("raccourcis : cible de « \(c.id) » (\(Self.target(for: c, catalogIDs: ids, isFolder: folders)?.key ?? "aucune"))")
        }
        let k1 = KeyCombo(keyCode: 17, modifiers: UInt32(cmdKey | optionKey)), k2 = KeyCombo(keyCode: 3, modifiers: UInt32(controlKey | optionKey))
        var list = Self.upserting(.command(id: "open_translator", title: "Traducteur"), combo: k1, into: [])
        list = Self.upserting(.command(id: "open_translator", title: "Traducteur (nouveau titre)"), combo: k2, into: list)
        if list.count != 1 || list.first?.combo != k2 { failures.append("raccourcis : un même élément ne doit avoir qu'un raccourci") }
        list = Self.upserting(.app(path: "/Applications/Essai.app", name: "Essai"), combo: k1, into: list)
        if Self.conflict(k1, among: list, exceptKey: "cmd:open_translator") != "Essai" { failures.append("raccourcis : conflit non vu") }
        if Self.conflict(k1, among: list, exceptKey: "app:/Applications/Essai.app") != nil { failures.append("raccourcis : faux conflit avec soi-même") }
        if Self.reservedReason(KeyCombo(keyCode: 8, modifiers: UInt32(cmdKey))) == nil { failures.append("raccourcis : ⌘C global aurait dû être refusé") }
        if Self.reservedReason(KeyCombo(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey))) == nil { failures.append("raccourcis : ⌘⇧C global aurait dû être refusé") }
        if Self.reservedReason(k1) != nil || Self.reservedReason(k2) != nil { failures.append("raccourcis : ⌥⌘ et ⌃⌥ doivent être acceptés") }
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

    /// The other shortcut of the app that already uses `combo`, if any (launcher, clipboard, windows, another binding).
    func conflict(for combo: KeyCombo?, except id: UUID) -> String? {
        guard let combo else { return nil }
        if let reserved = Self.reservedReason(combo) { return reserved }
        let exceptKey = bindings.first { $0.id == id }?.target.key ?? ""
        return owner(of: combo, except: .binding(exceptKey))
    }

    /// Who uses `combo` in Clean My Claude, apart from `except`: the launcher, the clipboard history,
    /// a window action or one of these shortcuts. Every shortcut recorder of the app asks it before saving.
    func owner(of combo: KeyCombo, except: HotkeysOwner) -> String? {
        if let other = Self.conflict(combo, among: bindings, exceptKey: except.bindingKey ?? "") { return other }
        guard let app = app ?? AppContext.model else { return nil }
        if except != .launcher, app.launcher.combo == combo { return "le lanceur" }
        if except != .clipboard, app.clipboard.combo == combo { return "l'historique du presse-papiers" }
        if except != .windows, let action = app.windows.combos.first(where: { $0.value == combo })?.key { return "Fenêtres (\(action.title))" }
        return nil
    }

    static func conflict(_ combo: KeyCombo, among bindings: [HotkeysBinding], exceptKey: String) -> String? {
        bindings.first { $0.target.key != exceptKey && $0.combo == combo }?.target.title
    }

    /// `bindings` with `target` given `combo` (an existing shortcut of the same target is replaced).
    static func upserting(_ target: HotkeysTarget, combo: KeyCombo, into bindings: [HotkeysBinding]) -> [HotkeysBinding] {
        var out = bindings
        if let i = out.firstIndex(where: { $0.target.key == target.key }) {
            out[i].combo = combo
            out[i].target = target
        } else {
            out.append(HotkeysBinding(target: target, combo: combo))
        }
        return out
    }

    /// ⌘ alone (or ⌘⇧) belongs to the apps: a global ⌘C or ⌘K would stop working everywhere else.
    static func reservedReason(_ combo: KeyCombo) -> String? {
        combo.modifiers & UInt32(controlKey | optionKey) == 0
            ? "les apps (⌘ seul est réservé à leurs raccourcis : ajoute ⌃ ou ⌥)" : nil
    }

    /// Gives `target` this shortcut, creating it if needed. Returns what already uses the keys, or nil when it worked.
    @discardableResult
    func bind(_ target: HotkeysTarget, combo: KeyCombo) -> String? {
        if let reserved = Self.reservedReason(combo) { return reserved }
        let existing = bindings.first { $0.target.key == target.key }
        if let other = conflict(for: combo, except: existing?.id ?? UUID()) { return other }
        bindings = Self.upserting(target, combo: combo, into: bindings)
        guard let b = bindings.first(where: { $0.target.key == target.key }) else { return nil }
        register(b)
        return refused.contains(b.id) ? "une autre app (macOS l'a refusé)" : nil
    }

    func unbind(_ target: HotkeysTarget) {
        guard let b = bindings.first(where: { $0.target.key == target.key }) else { return }
        remove(b.id)
    }

    func binding(for target: HotkeysTarget) -> HotkeysBinding? {
        bindings.first { $0.target.key == target.key }
    }

    /// The shortcut given to a launcher result, if any: its command, or the app, file or folder it opens.
    func combo(for command: AppCommand) -> KeyCombo? {
        guard !bindings.isEmpty, !command.id.hasPrefix("hk_") else { return nil }
        var keys = ["cmd:" + command.id]
        if case .file(let path) = command.icon { keys += ["app:" + path, "folder:" + path, "file:" + path] }
        return bindings.first { keys.contains($0.target.key) }?.combo
    }

    /// What a launcher result opens, as a shortcut target; nil for results that change with the typing
    /// (calculations, translations…) and for the shortcuts themselves.
    static func target(for command: AppCommand, catalogIDs: Set<String>,
                       isFolder: (String) -> Bool = HotkeysModel.isPlainFolder) -> HotkeysTarget? {
        if case .file(let path) = command.icon {
            if command.group == .apps { return .app(path: path, name: command.title) }
            if command.group == .files { return isFolder(path) ? .folder(path: path) : .file(path: path) }
        }
        guard !command.id.hasPrefix("hk_"), catalogIDs.contains(command.id) else { return nil }
        return .command(id: command.id, title: command.title)
    }

    nonisolated static func isPlainFolder(_ path: String) -> Bool {
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return v?.isDirectory == true && v?.isPackage != true
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
        if let existing = bindings.first(where: { $0.target.key == target.key }) {
            HUD.show("Déjà là : \(existing.combo?.display ?? "sans raccourci")", symbol: "keyboard")
            return
        }
        let windowCombos = app.map { Array($0.windows.combos.values) } ?? []
        let taken = Set(bindings.compactMap(\.combo) + [app?.launcher.combo, app?.clipboard.combo].compactMap { $0 } + windowCombos)
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

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Ajouter"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { add(.file(path: url.path)) }
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
        case .folder(let path), .file(let path):
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
        case .app(let path, _), .folder(let path), .file(let path): return .file(path)
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
