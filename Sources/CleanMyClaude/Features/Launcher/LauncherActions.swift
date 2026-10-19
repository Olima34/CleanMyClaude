import SwiftUI
import AppKit
import Carbon.HIToolbox
import PDFKit
import UniformTypeIdentifiers

// MARK: - Shortcuts

/// A key pressed in the launcher, as the shortcuts of the actions panel read it.
struct LauncherKeyPress {
    var keyCode: Int
    /// What the key types on its own, without any modifier (follows the layout: the A of an AZERTY keyboard is "a").
    var base: String
    /// What it types with Shift when Shift is held ("." for ⇧; on an AZERTY keyboard).
    var typed: String
    var command = false
    var shift = false
    var option = false
    var control = false

    init(keyCode: Int, base: String, typed: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.keyCode = keyCode
        self.base = base
        self.typed = typed
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    init(_ event: NSEvent) {
        let flags = event.modifierFlags
        self.init(keyCode: Int(event.keyCode), base: event.characters(byApplyingModifiers: []) ?? "",
                  typed: event.charactersIgnoringModifiers ?? "", command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
    }
}

/// A key and its modifiers, drawn like Raycast does ("⇧ ⌘ D") and matched by the character the key types,
/// so that ⌘D is the D key on an AZERTY keyboard too.
struct LauncherShortcut: Equatable {
    enum Key: Equatable {
        /// Lowercase.
        case character(String)
        case up
        case enter
    }

    var key: Key
    var command = false
    var shift = false
    var option = false
    var control = false

    /// `modifiers` in macOS's own symbols: "⇧⌘", "⌃⌘", "⌥⌘"…
    init(_ key: Key, _ modifiers: String = "") {
        self.key = key
        command = modifiers.contains("⌘")
        shift = modifiers.contains("⇧")
        option = modifiers.contains("⌥")
        control = modifiers.contains("⌃")
    }

    /// One key cap per symbol, in macOS's order (⌃ ⌥ ⇧ ⌘).
    var keys: [String] {
        var out: [String] = []
        if control { out.append("⌃") }
        if option { out.append("⌥") }
        if shift { out.append("⇧") }
        if command { out.append("⌘") }
        switch key {
        case .character(let c): out.append(c.uppercased())
        case .up: out.append("↑")
        case .enter: out.append("↩")
        }
        return out
    }

    func matches(_ p: LauncherKeyPress) -> Bool {
        guard p.command == command, p.option == option, p.control == control else { return false }
        switch key {
        case .up:
            return p.keyCode == kVK_UpArrow && p.shift == shift
        case .enter:
            return (p.keyCode == kVK_Return || p.keyCode == kVK_ANSI_KeypadEnter) && p.shift == shift
        case .character(let c):
            let base = p.base.lowercased(), typed = p.typed.lowercased()
            // The key types it by itself: Shift must be as written (⇧⌘, on an AZERTY keyboard).
            if base == c { return p.shift == shift }
            // Shift is needed to type it ("." on an AZERTY keyboard is ⇧;): it belongs to the character.
            return !shift && p.shift && typed == c && base != typed
        }
    }
}

// MARK: - Actions

enum LauncherFileActionKind: String, CaseIterable {
    case open, reveal, quickLook = "quick_look", openWith = "open_with", getInfo = "get_info"
    case parent, details, share, claude
    case move, copyTo = "copy_to", duplicate
    case hotkey
    case copyFile = "copy_file", copyName = "copy_name", copyPath = "copy_path"
    case trash
}

/// One line of the ⌘K panel of a file or a folder.
struct LauncherFileAction: Identifiable, Equatable {
    let kind: LauncherFileActionKind
    let title: String
    let symbol: String
    let shortcut: LauncherShortcut
    /// The actions of a group are drawn together, a line between two groups.
    let group: Int
    var keywords: [String] = []

    var id: String { "launcher_fa_" + kind.rawValue }
    var destructive: Bool { kind == .trash }
    /// Opens, copies, moves or shares something on the Mac: refused in the demo (the others only change the panel).
    var touchesMac: Bool { ![.quickLook, .openWith, .parent, .details, .hotkey].contains(kind) }
}

/// An app that can open the file, for "Ouvrir avec…".
struct LauncherOpenWithApp: Identifiable, Equatable {
    let name: String
    let path: String
    let isDefault: Bool

    var id: String { path }

    /// The apps macOS knows for this file, its default one first.
    static func list(for path: String) -> [LauncherOpenWithApp] {
        if DemoData.isEnabled {
            // The demo's fictional apps, never the ones installed on this Mac.
            let names = ["Plume", "Ardoise", "Archiviste", "Hélios Code", "Keynote"]
            return DemoData.apps().filter { names.contains($0.name) }
                .map { LauncherOpenWithApp(name: $0.name, path: $0.path, isDefault: $0.name == names[0]) }
                .sorted(by: order)
        }
        let url = URL(fileURLWithPath: path)
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: url)?.standardizedFileURL.path
        var seen = Set<String>()
        var out: [LauncherOpenWithApp] = []
        for app in NSWorkspace.shared.urlsForApplications(toOpen: url) {
            let p = app.standardizedFileURL.path
            guard seen.insert(p).inserted else { continue }
            let name = FileManager.default.displayName(atPath: p)
            out.append(LauncherOpenWithApp(name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name, path: p, isDefault: p == preferred))
        }
        return out.sorted(by: order)
    }

    private static func order(_ a: LauncherOpenWithApp, _ b: LauncherOpenWithApp) -> Bool {
        if a.isDefault != b.isDefault { return a.isDefault }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

enum LauncherFileActions {
    /// Every action of the panel, in Raycast's order. A folder cannot be read by Claude.
    static func all(isFolder: Bool, detailsShown: Bool) -> [LauncherFileAction] {
        var list: [LauncherFileAction] = [
            LauncherFileAction(kind: .open, title: "Ouvrir", symbol: "doc", shortcut: .init(.enter), group: 0, keywords: ["lancer", "open"]),
            LauncherFileAction(kind: .reveal, title: "Afficher dans le Finder", symbol: "folder", shortcut: .init(.enter, "⌘"), group: 0,
                               keywords: ["finder", "montrer", "reveal"]),
            LauncherFileAction(kind: .quickLook, title: "Coup d'œil", symbol: "eye", shortcut: .init(.character("y"), "⌘"), group: 0,
                               keywords: ["oeil", "apercu", "quick look", "previsualiser"]),
            LauncherFileAction(kind: .openWith, title: "Ouvrir avec…", symbol: "arrow.up.forward.app", shortcut: .init(.character("o"), "⌘"), group: 0,
                               keywords: ["application", "app", "open with"]),
            LauncherFileAction(kind: .getInfo, title: "Lire les informations dans le Finder", symbol: "info.circle", shortcut: .init(.character("i"), "⌘"),
                               group: 0, keywords: ["infos", "proprietes", "get info"]),
            LauncherFileAction(kind: .parent, title: "Dossier parent", symbol: "arrow.up", shortcut: .init(.up, "⌥⌘"), group: 1,
                               keywords: ["remonter", "dossier", "enclosing folder"]),
            LauncherFileAction(kind: .details, title: detailsShown ? "Masquer les détails" : "Afficher les détails", symbol: "sidebar.right",
                               shortcut: .init(.character("d"), "⇧⌘"), group: 1, keywords: ["details", "apercu", "panneau"]),
            LauncherFileAction(kind: .share, title: "Partager…", symbol: "square.and.arrow.up", shortcut: .init(.character("e"), "⇧⌘"), group: 1,
                               keywords: ["airdrop", "mail", "messages", "envoyer", "share"]),
            LauncherFileAction(kind: .claude, title: "Joindre à la discussion avec Claude", symbol: "sparkles", shortcut: .init(.character("a"), "⌃⌘"),
                               group: 1, keywords: ["claude", "assistant", "ia", "ai chat"]),
            LauncherFileAction(kind: .move, title: "Déplacer vers…", symbol: "tray.and.arrow.down", shortcut: .init(.character("m"), "⇧⌘"), group: 2,
                               keywords: ["ranger", "move"]),
            LauncherFileAction(kind: .copyTo, title: "Copier vers…", symbol: "doc.on.doc", shortcut: .init(.character("c"), "⇧⌘"), group: 2,
                               keywords: ["copy to"]),
            LauncherFileAction(kind: .duplicate, title: "Dupliquer", symbol: "plus.square.on.square", shortcut: .init(.character("d"), "⌘"), group: 2,
                               keywords: ["copie", "duplicate"]),
            LauncherFileAction(kind: .hotkey, title: "Créer un raccourci rapide", symbol: "keyboard", shortcut: .init(.character("l"), "⇧⌘"), group: 3,
                               keywords: ["raccourci clavier", "hotkey", "quicklink"]),
            LauncherFileAction(kind: .copyFile, title: "Copier le fichier", symbol: "doc.on.clipboard", shortcut: .init(.character("."), "⌘"), group: 4,
                               keywords: ["presse-papiers", "copy file"]),
            LauncherFileAction(kind: .copyName, title: "Copier le nom", symbol: "textformat", shortcut: .init(.character("."), "⇧⌘"), group: 4,
                               keywords: ["presse-papiers", "copy name"]),
            LauncherFileAction(kind: .copyPath, title: "Copier le chemin", symbol: "link", shortcut: .init(.character(","), "⇧⌘"), group: 4,
                               keywords: ["presse-papiers", "copy path"]),
            LauncherFileAction(kind: .trash, title: "Placer dans la Corbeille", symbol: "trash", shortcut: .init(.character("x"), "⌃"), group: 5,
                               keywords: ["supprimer", "effacer", "jeter", "delete", "move to trash"])
        ]
        if isFolder { list.removeAll { $0.kind == .claude } }
        return list
    }

    /// What the panel's search field keeps, best match first; everything, in order, when it is empty.
    static func filter(_ actions: [LauncherFileAction], _ query: String) -> [LauncherFileAction] {
        rank(actions, query, title: \.title, keywords: \.keywords)
    }

    static func rank<T>(_ items: [T], _ query: String, title: (T) -> String, keywords: (T) -> [String]) -> [T] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.enumerated()
            .compactMap { i, item in Fuzzy.best(q, title: title(item), keywords: keywords(item)).map { (item, $0, i) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    /// The action a key runs, if any (a key without ⌘, ⌃ or ⌥ never runs one: it is typed in the search).
    static func action(for press: LauncherKeyPress, in actions: [LauncherFileAction]) -> LauncherFileAction? {
        actions.first { $0.shortcut.matches(press) }
    }

    /// "Rapport.pdf" → "Rapport copie.pdf", like the Finder (FileOps adds " 2" if it is taken).
    static func duplicateName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return ext.isEmpty ? "\(name) copie" : "\(base) copie.\(ext)"
    }

    /// A path inside an AppleScript string.
    static func appleScriptString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The panel's rules, on made-up keys and names (nothing is read from the disk).
    static func checks() -> [String] {
        var failures: [String] = []
        let file = all(isFolder: false, detailsShown: true)
        let folder = all(isFolder: true, detailsShown: true)
        if file.count != 17 || folder.contains(where: { $0.kind == .claude }) {
            failures.append("actions : \(file.count) pour un fichier, Claude proposé pour un dossier ?")
        }
        if file.first?.kind != .open || file.last?.kind != .trash || file.last?.destructive != true {
            failures.append("actions : Ouvrir d'abord, la Corbeille en dernier")
        }
        for a in file where !AppCommand.isValidID(a.id) { failures.append("actions : identifiant invalide \(a.id)") }
        for a in file where NSImage(systemSymbolName: a.symbol, accessibilityDescription: nil) == nil {
            failures.append("actions : symbole introuvable \(a.symbol)")
        }
        let keys = file.map { $0.shortcut.keys.joined() }
        if Set(keys).count != keys.count { failures.append("actions : deux actions ont le même raccourci") }
        for a in file where a.kind != .open && !(a.shortcut.command || a.shortcut.control || a.shortcut.option) {
            failures.append("actions : « \(a.title) » sans ⌘, ⌃ ni ⌥ serait tapé dans la recherche")
        }
        // The search field of the panel.
        if filter(file, "").map(\.kind) != file.map(\.kind) { failures.append("actions : sans recherche, tout dans l'ordre") }
        if filter(file, "corb").first?.kind != .trash { failures.append("actions : « corb » devrait trouver la Corbeille") }
        if filter(file, "supprimer").first?.kind != .trash { failures.append("actions : « supprimer » devrait trouver la Corbeille") }
        if filter(file, "oeil").first?.kind != .quickLook { failures.append("actions : « oeil » devrait trouver Coup d'œil") }
        if filter(file, "dupl").first?.kind != .duplicate { failures.append("actions : « dupl » devrait trouver Dupliquer") }
        let copies = Set(filter(file, "copier").map(\.kind))
        if !copies.isSuperset(of: [.copyTo, .copyFile, .copyName, .copyPath]) { failures.append("actions : « copier » oublie une copie") }
        if !filter(file, "zzqx").isEmpty { failures.append("actions : résultat inventé pour « zzqx »") }
        // Keys: an American keyboard, then an AZERTY one.
        func hit(_ keyCode: Int, _ base: String, _ typed: String, _ mods: String = "") -> LauncherFileActionKind? {
            action(for: LauncherKeyPress(keyCode: keyCode, base: base, typed: typed, command: mods.contains("⌘"), shift: mods.contains("⇧"),
                                         option: mods.contains("⌥"), control: mods.contains("⌃")), in: file)?.kind
        }
        let presses: [(String, LauncherFileActionKind?, LauncherFileActionKind?)] = [
            ("⌘↩", hit(kVK_Return, "\r", "\r", "⌘"), .reveal), ("↩", hit(kVK_Return, "\r", "\r"), .open),
            ("⌘Y", hit(kVK_ANSI_Y, "y", "y", "⌘"), .quickLook), ("⌘O", hit(kVK_ANSI_O, "o", "o", "⌘"), .openWith),
            ("⌘I", hit(kVK_ANSI_I, "i", "i", "⌘"), .getInfo), ("⌥⌘↑", hit(kVK_UpArrow, "", "", "⌥⌘"), .parent),
            ("⌘↑", hit(kVK_UpArrow, "", "", "⌘"), nil), ("⇧⌘D", hit(kVK_ANSI_D, "d", "D", "⇧⌘"), .details),
            ("⌘D", hit(kVK_ANSI_D, "d", "d", "⌘"), .duplicate), ("⇧⌘E", hit(kVK_ANSI_E, "e", "E", "⇧⌘"), .share),
            ("⇧⌘M", hit(kVK_ANSI_Semicolon, "m", "M", "⇧⌘"), .move), ("⇧⌘C", hit(kVK_ANSI_C, "c", "C", "⇧⌘"), .copyTo),
            ("⇧⌘L", hit(kVK_ANSI_L, "l", "L", "⇧⌘"), .hotkey), ("⌘.", hit(kVK_ANSI_Period, ".", ".", "⌘"), .copyFile),
            ("⇧⌘. (US)", hit(kVK_ANSI_Period, ".", ">", "⇧⌘"), .copyName), ("⇧⌘, (US)", hit(kVK_ANSI_Comma, ",", "<", "⇧⌘"), .copyPath),
            ("⌃X", hit(kVK_ANSI_X, "x", "x", "⌃"), .trash), ("⌘X", hit(kVK_ANSI_X, "x", "x", "⌘"), nil),
            // AZERTY: A is where Q is, "." is ⇧; and "," has its own key.
            ("⌃⌘A (AZERTY)", hit(kVK_ANSI_Q, "a", "a", "⌃⌘"), .claude), ("⌘Q (AZERTY)", hit(kVK_ANSI_A, "q", "q", "⌘"), nil),
            ("⌘. (AZERTY)", hit(kVK_ANSI_Comma, ";", ".", "⇧⌘"), .copyFile), ("⇧⌘, (AZERTY)", hit(kVK_ANSI_M, ",", "?", "⇧⌘"), .copyPath),
            // Plain keys are typed in the search, ⌘K opens the panel.
            ("d", hit(kVK_ANSI_D, "d", "d"), nil), ("D", hit(kVK_ANSI_D, "d", "D", "⇧"), nil), ("⌘K", hit(kVK_ANSI_K, "k", "k", "⌘"), nil)
        ]
        for (name, got, expected) in presses where got != expected {
            failures.append("actions : \(name) lance \(got?.rawValue ?? "rien") au lieu de \(expected?.rawValue ?? "rien")")
        }
        if file.first(where: { $0.kind == .parent })?.shortcut.keys != ["⌥", "⌘", "↑"]
            || file.first(where: { $0.kind == .claude })?.shortcut.keys != ["⌃", "⌘", "A"] {
            failures.append("actions : ordre des touches affichées (⌃ ⌥ ⇧ ⌘)")
        }
        if all(isFolder: false, detailsShown: false).first(where: { $0.kind == .details })?.title != "Afficher les détails" {
            failures.append("actions : le libellé des détails suit leur état")
        }
        if duplicateName("Rapport annuel.pdf") != "Rapport annuel copie.pdf" || duplicateName("Factures") != "Factures copie"
            || duplicateName("archive.tar.gz") != "archive.tar copie.gz" {
            failures.append("actions : nom du double « \(duplicateName("Rapport annuel.pdf")) »")
        }
        if appleScriptString("a\"b\\c") != "a\\\"b\\\\c" { failures.append("actions : chemin mal protégé pour AppleScript") }
        // What Claude receives.
        let long = String(repeating: "é", count: LauncherClaudeAttachment.limit + 50)
        let cut = LauncherClaudeAttachment.compose(name: "notes.md", details: "Markdown, 2 Ko, dans ~/Documents", content: long)
        if !cut.contains("« notes.md »") || !cut.contains("premiers caractères") || cut.count > LauncherClaudeAttachment.limit + 400 {
            failures.append("actions : pièce jointe pour Claude mal coupée")
        }
        let photo = LauncherClaudeAttachment.compose(name: "photo.heic", details: "Image HEIF", content: nil)
        if photo.contains("début du fichier") || !photo.contains("pas du texte") { failures.append("actions : pièce jointe sans texte") }
        return failures
    }
}

// MARK: - What Claude receives

/// A file joined to the conversation with Claude: its text goes in the message (Claude reads nothing on the Mac by itself),
/// and the user sees all of it before sending.
enum LauncherClaudeAttachment {
    static let limit = 20_000

    /// The message and whether the file's content is in it.
    static func message(for path: String) -> (text: String, readable: Bool) {
        let info = LauncherFileInfo.read(path)
        var details = [info.kind, info.size == "…" ? "" : info.size].filter { !$0.isEmpty }
        details.append("dans " + FS.pretty((path as NSString).deletingLastPathComponent))
        let content = text(of: path)
        let readable = !(content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return (compose(name: (path as NSString).lastPathComponent, details: details.joined(separator: ", "), content: readable ? content : nil), readable)
    }

    static func compose(name: String, details: String, content: String?) -> String {
        guard let content else {
            return "Je te joins le fichier « \(name) » (\(details)). Son contenu n'est pas du texte : tu n'en as que le nom et le type."
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = text.count > limit
        return "Je te joins le fichier « \(name) » (\(details)).\n\n--- début du fichier ---\n" + (cut ? String(text.prefix(limit)) : text)
            + "\n--- fin du fichier" + (cut ? " (seulement ses \(Fmt.int(limit)) premiers caractères)" : "") + " ---\n\n"
    }

    /// The readable text of a file: text and code, PDF, RTF, Word and OpenDocument. nil for anything else.
    static func text(of path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey]),
              values.isDirectory != true, let type = values.contentType else { return nil }
        if type.conforms(to: .pdf) {
            guard let doc = PDFDocument(url: url) else { return nil }
            var out = ""
            for i in 0..<doc.pageCount {
                out += (doc.page(at: i)?.string ?? "") + "\n"
                if out.count > limit { break }
            }
            return out
        }
        let documents: Set<String> = ["docx", "doc", "odt", "rtf", "rtfd"]
        if documents.contains(url.pathExtension.lowercased()) {
            return (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        }
        guard type.conforms(to: .text) else { return nil }
        // A huge log is cut: what is past the limit would not be sent anyway.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: limit * 4)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Running the actions

extension LauncherModel {
    /// The actions of the file the panel is open for.
    var fileActions: [LauncherFileAction] {
        guard actionsFor != nil else { return [] }
        return LauncherFileActions.all(isFolder: actionsIsFolder, detailsShown: showDetails)
    }

    var visibleActions: [LauncherFileAction] { LauncherFileActions.filter(fileActions, actionFilter) }

    var visibleApps: [LauncherOpenWithApp] {
        LauncherFileActions.rank(openWithApps ?? [], actionFilter, title: \.name, keywords: { _ in [] })
    }

    /// ⌘K on a file or a folder.
    func openActions() {
        guard let path = selectedFile else { return }
        actionsIsFolder = isFolder(path)
        openWithApps = nil
        actionFilter = ""
        actionSelection = 0
        actionsFor = path
    }

    func closeActions() {
        actionsFor = nil
        openWithApps = nil
        actionFilter = ""
        actionSelection = 0
    }

    func toggleActions() {
        actionsFor == nil ? openActions() : closeActions()
    }

    func moveAction(_ delta: Int) {
        let count = openWithApps == nil ? visibleActions.count : visibleApps.count
        guard count > 0 else { return }
        actionSelection = (actionSelection + delta + count) % count
    }

    func runSelectedAction() {
        guard let path = actionsFor else { return }
        if openWithApps != nil {
            let apps = visibleApps
            if apps.indices.contains(actionSelection) { open(path, with: apps[actionSelection]) }
            return
        }
        let actions = visibleActions
        if actions.indices.contains(actionSelection) { perform(actions[actionSelection], path: path) }
    }

    /// The keys of the panel: arrows, ↩, ⎋ (back, then close), ⌘K, and every action's own shortcut.
    func actionsKey(_ event: NSEvent) -> NSEvent? {
        let press = LauncherKeyPress(event)
        let plain = !press.command && !press.option && !press.control && !press.shift
        switch Int(event.keyCode) {
        case kVK_Escape:
            if openWithApps != nil {
                openWithApps = nil
                actionFilter = ""
                actionSelection = 0
            } else {
                closeActions()
            }
            return nil
        case kVK_DownArrow where plain:
            moveAction(1)
            return nil
        case kVK_UpArrow where plain:
            moveAction(-1)
            return nil
        case kVK_Return where plain, kVK_ANSI_KeypadEnter where plain:
            runSelectedAction()
            return nil
        default:
            break
        }
        if press.command, press.typed.lowercased() == "k" {
            closeActions()
            return nil
        }
        if openWithApps == nil, let path = actionsFor, let action = LauncherFileActions.action(for: press, in: fileActions) {
            perform(action, path: path)
            return nil
        }
        return event
    }

    /// An action's shortcut on the selected file, without opening the panel (↩ and ⌘↩ keep their usual way).
    func fileShortcut(_ event: NSEvent) -> Bool {
        guard let path = selectedFile else { return false }
        let actions = LauncherFileActions.all(isFolder: isFolder(path), detailsShown: showDetails)
        guard let action = LauncherFileActions.action(for: LauncherKeyPress(event), in: actions),
              action.kind != .open, action.kind != .reveal else { return false }
        perform(action, path: path)
        return true
    }

    func perform(_ action: LauncherFileAction, path: String) {
        if DemoData.isEnabled, action.touchesMac {
            closeActions()
            HUD.show(DemoData.refusal, symbol: "info.circle.fill")
            return
        }
        let name = (path as NSString).lastPathComponent
        switch action.kind {
        case .open, .reveal:
            closeActions()
            openFile(path, reveal: action.kind == .reveal)
        case .quickLook:
            closeActions()
            mode = .quickLook(path: path)
        case .openWith:
            let apps = LauncherOpenWithApp.list(for: path)
            guard !apps.isEmpty else {
                HUD.show("Aucune app ne sait ouvrir « \(name) »", symbol: "exclamationmark.circle.fill")
                return
            }
            actionsIsFolder = isFolder(path)
            actionsFor = path
            actionFilter = ""
            actionSelection = 0
            openWithApps = apps
        case .getInfo:
            closeActions()
            showInfo(path)
        case .parent:
            closeActions()
            showParent(of: path)
        case .details:
            closeActions()
            showDetails.toggle()
        case .share:
            closeActions()
            share(path)
        case .claude:
            closeActions()
            attachToClaude(path)
        case .move, .copyTo:
            closeActions()
            transfer(path, move: action.kind == .move)
        case .duplicate:
            closeActions()
            duplicate(path)
        case .hotkey:
            closeActions()
            if let i = flat.firstIndex(where: { Self.filePath(of: $0) == path }) { selection = i }
            startAssign()
        case .copyFile:
            closeActions()
            guard !Snapshot.isActive else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
            HUD.show("Fichier copié : colle-le dans le Finder ou un message", symbol: "doc.on.clipboard.fill")
        case .copyName, .copyPath:
            closeActions()
            if case .copied = CommandRunner.copy(action.kind == .copyName ? name : path) {
                HUD.show(action.kind == .copyName ? "Nom copié" : "Chemin copié", symbol: "doc.on.clipboard.fill")
            }
        case .trash:
            closeActions()
            trash(path)
        }
    }

    /// The file's own result runs (so that it counts for the next searches); otherwise it opens directly.
    private func openFile(_ path: String, reveal: Bool) {
        if let command = flat.first(where: { Self.filePath(of: $0) == path }) {
            run(command, alternate: reveal)
            return
        }
        hide()
        if reveal { Finder.reveal(path) } else { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }

    private func open(_ path: String, with app: LauncherOpenWithApp) {
        closeActions()
        guard !DemoData.isEnabled else {
            HUD.show(DemoData.refusal, symbol: "info.circle.fill")
            return
        }
        hide()
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: URL(fileURLWithPath: app.path),
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            let message = error.localizedDescription
            DispatchQueue.main.async { HUD.show(message, symbol: "xmark.octagon.fill") }
        }
    }

    /// The Finder's own "Lire les informations" window (macOS asks once to let Clean My Claude drive the Finder).
    private func showInfo(_ path: String) {
        hide()
        let script = """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(LauncherFileActions.appleScriptString(path))" as alias)
        end tell
        """
        Task {
            let r = await Task.detached(priority: .userInitiated) { Shell.appleScript(script) }.value
            guard !r.ok, r.status != -128 else { return }
            HUD.show(r.status == -1743 ? "Autorise Clean My Claude à piloter le Finder : Réglages Système › Confidentialité › Automatisation"
                                       : (r.err.isEmpty ? "Le Finder n'a pas répondu." : r.err), symbol: "xmark.octagon.fill")
        }
    }

    /// The folder that holds the file, browsed right in the launcher, the file still selected.
    private func showParent(of path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        query = parent == "/" ? "/" : FS.pretty(parent) + "/"
        if let i = flat.firstIndex(where: { Self.filePath(of: $0) == path }) {
            scrollToSelection = true
            selection = i
        }
    }

    private func share(_ path: String) {
        guard let view = panelView else { return }
        let picker = NSSharingServicePicker(items: [URL(fileURLWithPath: path)])
        let delegate = LauncherShareDelegate { [weak self] in self?.hide() }
        shareDelegate = delegate
        picker.delegate = delegate
        let b = view.bounds
        picker.show(relativeTo: NSRect(x: b.maxX - 220, y: b.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    /// Puts the file's text in the message being written to Claude, then shows the conversation: nothing leaves before the user sends it.
    private func attachToClaude(_ path: String) {
        guard let app = app ?? AppContext.model else { return }
        hide()
        Task {
            let attachment = await Task.detached(priority: .userInitiated) { LauncherClaudeAttachment.message(for: path) }.value
            let assistant = app.assistant
            let current = assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            assistant.draft = current.isEmpty ? attachment.text : current + "\n\n" + attachment.text
            app.page = .assistant
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
            HUD.show(attachment.readable ? "Fichier joint : écris ta question, puis envoie" : "Claude ne verra que le nom et le type de ce fichier",
                     symbol: attachment.readable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        }
    }

    /// "Déplacer vers…" and "Copier vers…": the user picks the folder, a name already taken there gets " 2".
    private func transfer(_ path: String, move: Bool) {
        hide()
        let source = URL(fileURLWithPath: path)
        let name = source.lastPathComponent
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        picker.allowsMultipleSelection = false
        picker.directoryURL = source.deletingLastPathComponent()
        picker.message = move ? "Où ranger « \(name) » ?" : "Où copier « \(name) » ?"
        picker.prompt = move ? "Déplacer ici" : "Copier ici"
        NSApp.activate()
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        if move, folder.standardizedFileURL.path == source.deletingLastPathComponent().standardizedFileURL.path {
            HUD.show("« \(name) » est déjà dans ce dossier", symbol: "exclamationmark.circle.fill")
            return
        }
        let target = folder.appendingPathComponent(name)
        Task {
            let (done, failure) = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
                do {
                    let url = move ? try FileOps.move(source, to: target) : try FileOps.copy(source, to: target)
                    return (url.path, nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            if let done {
                HUD.show("\(move ? "Déplacé" : "Copié") dans \(FS.pretty((done as NSString).deletingLastPathComponent))", symbol: "checkmark.circle.fill")
            } else {
                HUD.show(failure ?? "Échec.", symbol: "xmark.octagon.fill")
            }
        }
    }

    private func duplicate(_ path: String) {
        let source = URL(fileURLWithPath: path)
        let target = source.deletingLastPathComponent().appendingPathComponent(LauncherFileActions.duplicateName(source.lastPathComponent))
        Task {
            let (done, failure) = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
                do { return (try FileOps.copy(source, to: target).lastPathComponent, nil) } catch { return (nil, error.localizedDescription) }
            }.value
            if let done {
                HUD.show("Dupliqué : \(done)", symbol: "checkmark.circle.fill")
                refreshKeepingSelection()
            } else {
                HUD.show(failure ?? "Échec.", symbol: "xmark.octagon.fill")
            }
        }
    }

    /// Always to the Trash, after a confirmation: the file can be put back from there.
    private func trash(_ path: String) {
        let name = (path as NSString).lastPathComponent
        guard CommandRunner.confirm("Placer « \(name) » dans la Corbeille ?",
                                    "Tu pourras le remettre à sa place depuis la Corbeille tant qu'elle n'est pas vidée.",
                                    button: "Placer dans la Corbeille") else {
            refocus()
            return
        }
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                Remover.remove([RemovalEntry(path: path, size: FileSizer.size(of: path))], mode: .trash)
            }.value
            if report.removed > 0 {
                HUD.show("« \(name) » est dans la Corbeille", symbol: "checkmark.circle.fill")
                refreshKeepingSelection()
            } else if let failure = report.failures.first {
                HUD.show(failure.reason == "Emplacement protégé" ? "Clean My Claude ne touche pas à cet emplacement" : failure.reason,
                         symbol: "xmark.octagon.fill")
            }
            refocus()
        }
    }

    static func filePath(of command: AppCommand) -> String? {
        guard command.group == .files, case .file(let path) = command.icon else { return nil }
        return path
    }
}

/// Closes the launcher once a way of sharing is chosen (Mail, AirDrop… open their own window under it otherwise).
final class LauncherShareDelegate: NSObject, NSSharingServicePickerDelegate {
    private let onChoose: @MainActor () -> Void

    init(onChoose: @escaping @MainActor () -> Void) {
        self.onChoose = onChoose
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard service != nil else { return }
        MainActor.assumeIsolated { onChoose() }
    }
}
