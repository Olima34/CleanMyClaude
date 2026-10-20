import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The clipboard history in its own floating window (its shortcut, « cb » or the command of the launcher):
/// the list on the left, the whole item on the right. ↩ pastes it where you were, ⌘↩ only copies it.
@Observable
@MainActor
final class ClipboardWindow {
    static let width: CGFloat = 860
    static let height: CGFloat = 500
    static let listWidth: CGFloat = 380

    var query = "" {
        didSet { if query != oldValue { selection = nil } }
    }
    var filter: ClipboardFilterTab = .all {
        didSet { if filter != oldValue { selection = nil } }
    }
    /// nil: the first item of the list.
    var selection: UUID?
    var isOpen = false
    /// Set by the arrow keys: only then does the list scroll to the selection (never while the trackpad scrolls it).
    @ObservationIgnored var scrollToSelection = false
    @ObservationIgnored private var panel: FloatingPanel?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored weak var model: ClipboardModel?

    // MARK: Opening

    /// The shortcut pressed again closes it, like the launcher's.
    func toggle() {
        isOpen ? close() : show()
    }

    func show(query: String = "") {
        guard let app = AppContext.model else { return }
        // One floating window at a time: the launcher steps aside.
        if app.launcher.isOpen { app.launcher.hide() }
        self.query = query
        filter = .all
        selection = nil
        let p = panel ?? makePanel()
        p.setContent(ClipboardWindowView().environment(app))
        p.present()
        isOpen = true
        installKeyMonitor()
    }

    func close() {
        panel?.close()
    }

    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(size: NSSize(width: Self.width, height: Self.height))
        p.onClose = { [weak self, weak p] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isOpen = false
                self.removeKeyMonitor()
                // The closed window keeps no view: each copy no longer recomputes a list nobody sees.
                DispatchQueue.main.async { [weak p] in
                    if let p, !p.isVisible { p.contentView = nil }
                }
            }
        }
        panel = p
        return p
    }

    // MARK: List

    /// What the window shows: the filter and the search applied, pinned items first when nothing is typed.
    func list(_ m: ClipboardModel) -> [ClipboardItem] {
        let q = Fuzzy.fold(query.trimmingCharacters(in: .whitespaces))
        return ClipboardHistory.search(m.items.filter { filter.accepts($0) }, query: q, keys: m.key, limit: 400, pinnedFirst: q.isEmpty)
    }

    func current(_ list: [ClipboardItem]) -> ClipboardItem? {
        list.first { $0.id == selection } ?? list.first
    }

    func move(_ delta: Int) {
        guard let m = model else { return }
        let items = list(m)
        guard !items.isEmpty else { return }
        let i = items.firstIndex { $0.id == current(items)?.id } ?? 0
        scrollToSelection = true
        selection = items[(i + delta + items.count) % items.count].id
    }

    func select(_ id: UUID) {
        scrollToSelection = false
        selection = id
    }

    // MARK: Actions

    /// ↩: back on the clipboard, then pasted into the app in front (when allowed); ⌘↩ or `copyOnly`: copied only.
    func use(_ item: ClipboardItem?, copyOnly: Bool = false) {
        guard let m = model, let item else { return }
        // Closed first: the app underneath takes the keyboard back for the ⌘V.
        close()
        switch m.recopy(item, paste: !copyOnly) {
        case .done: break
        case .copied(let text): HUD.show("Copié : \(text.count > 40 ? String(text.prefix(40)) + "…" : text)", symbol: "doc.on.clipboard.fill")
        case .message(let text): HUD.show(text, symbol: "info.circle.fill")
        case .failed(let text): HUD.show(text, symbol: "xmark.octagon.fill")
        }
    }

    func togglePin(_ item: ClipboardItem?) {
        guard let m = model, let item else { return }
        m.togglePin(item.id)
        selection = item.id
    }

    /// Removes the item from the history; the selection moves to the next one.
    func delete(_ item: ClipboardItem?) {
        guard let m = model, let item else { return }
        let before = list(m)
        let i = before.firstIndex { $0.id == item.id } ?? 0
        m.delete(item.id)
        let after = list(m)
        selection = after.isEmpty ? nil : after[min(i, after.count - 1)].id
    }

    func cycleFilter(_ delta: Int) {
        let all = ClipboardFilterTab.allCases
        let i = all.firstIndex(of: filter) ?? 0
        filter = all[(i + delta + all.count) % all.count]
    }

    // MARK: Keys

    /// Arrows, ↩, ⇥, ⎋, ⌘P and ⌘⌫ are caught before the search field sees them.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, let m = self.model else { return event }
            // A held ↩ pastes once, not once per key repeat.
            if event.isARepeat, [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) { return nil }
            let flags = event.modifierFlags
            let command = flags.contains(.command)
            switch Int(event.keyCode) {
            case kVK_DownArrow:
                self.move(1)
                return nil
            case kVK_UpArrow:
                self.move(-1)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.use(self.current(self.list(m)), copyOnly: command)
                return nil
            case kVK_Tab:
                self.cycleFilter(flags.contains(.shift) ? -1 : 1)
                return nil
            case kVK_Escape:
                if self.query.isEmpty { self.close() } else { self.query = "" }
                return nil
            case kVK_Delete where command, kVK_ForwardDelete where command:
                self.delete(self.current(self.list(m)))
                return nil
            default:
                if command, event.charactersIgnoringModifiers?.lowercased() == "p" {
                    self.togglePin(self.current(self.list(m)))
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - The window

struct ClipboardWindowView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        let m = app.clipboard
        let w = m.window
        let items = w.list(m)
        let item = w.current(items)
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            if !m.settings.acknowledged {
                ClipboardWindowNotice(title: "L'historique n'est pas encore activé",
                                      text: "Il garde ce que tu copies (⌘C) pour que tu le retrouves ici. La page Presse-papiers t'explique ce qui est enregistré avant d'allumer quoi que ce soit.",
                                      button: "Découvrir l'historique") {
                    w.close()
                    m.openPage()
                }
            } else {
                filters
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(alignment: .top, spacing: 0) {
                    ClipboardWindowList(items: items, selected: item?.id)
                        .frame(width: ClipboardWindow.listWidth)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .clipped()
                    Rectangle().fill(Theme.border).frame(width: 1)
                    Group {
                        if let item {
                            ClipboardWindowPreview(item: item)
                        } else {
                            EmptyHint(text: emptyText(m), symbol: w.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // The rest of the window, whatever the length of the list (snapshots lay it out at full height).
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            footer(item)
        }
        .frame(width: ClipboardWindow.width, height: ClipboardWindow.height)
        .background(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var header: some View {
        @Bindable var w = app.clipboard.window
        let m = app.clipboard
        return HStack(spacing: 12) {
            CommandIconView(icon: .symbol("doc.on.clipboard", Theme.palette[4]), size: 26)
            if Snapshot.isActive {
                Text(w.query.isEmpty ? "Rechercher dans ce que tu as copié…" : w.query)
                    .font(.ui(21)).foregroundStyle(w.query.isEmpty ? Theme.text3 : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Rechercher dans ce que tu as copié…", text: $w.query)
                    .textFieldStyle(.plain)
                    .font(.ui(21))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
            }
            if !w.query.isEmpty {
                Button { w.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.ui(14)).foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
            }
            if m.settings.acknowledged {
                Button { m.setEnabled(!m.settings.enabled) } label: {
                    HStack(spacing: 6) {
                        Circle().fill(m.isActive ? Theme.good : Theme.warn).frame(width: 7, height: 7)
                        Text(m.isActive ? "Actif" : "En pause").font(.ui(11.5, .medium)).foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(PillShape().fill(Theme.card))
                    .overlay(PillShape().strokeBorder(Theme.border, lineWidth: Theme.line))
                    .contentShape(PillShape())
                }
                .buttonStyle(.plain)
                .help(m.isActive ? "Mettre l'historique en pause" : "Reprendre l'historique")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var filters: some View {
        @Bindable var w = app.clipboard.window
        let m = app.clipboard
        return HStack(spacing: 10) {
            PillPicker(options: ClipboardFilterTab.allCases, selection: $w.filter, label: { $0.title }, badge: { tab in
                let n = m.count(tab)
                return n > 0 && tab != .all ? Fmt.int(n) : nil
            })
            Spacer(minLength: 0)
            Text(m.isActive ? Fmt.plural(m.items.count, "élément", "éléments") : "En pause : rien de nouveau n'est gardé")
                .font(.ui(11)).foregroundStyle(Theme.text3).monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footer(_ item: ClipboardItem?) -> some View {
        let m = app.clipboard
        let w = m.window
        return HStack(spacing: 14) {
            Button {
                w.close()
                m.openPage()
            } label: {
                HStack(spacing: 5) {
                    BrandMark(size: 11)
                    Text("Presse-papiers").font(.serif(12))
                }
                .foregroundStyle(Theme.text2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir la page Presse-papiers (réglages, apps ignorées)")
            LauncherKeyHint(key: "↑↓", label: "Naviguer")
            LauncherKeyHint(key: "⇥", label: "Type")
            LauncherKeyHint(key: "⌘P", label: item?.pinned == true ? "Désépingler" : "Épingler")
            LauncherKeyHint(key: "⌘⌫", label: "Supprimer")
            Spacer()
            if let item {
                // Without the right to paste, ↩ copies: one button says so.
                Button { w.use(item, copyOnly: true) } label: {
                    HStack(spacing: 6) {
                        Text("Copier").font(.ui(12, .medium)).foregroundStyle(m.canPaste ? Theme.text2 : Theme.text)
                        LauncherKeyCaps(keys: m.canPaste ? ["⌘", "↩"] : ["↩"])
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remet l'élément dans le presse-papiers, sans coller")
                if m.canPaste {
                    Rectangle().fill(Theme.border).frame(width: 1, height: 16)
                    Button { w.use(item) } label: {
                        HStack(spacing: 6) {
                            Text("Coller").font(.ui(12, .medium)).foregroundStyle(Theme.text)
                            LauncherKeyCaps(keys: ["↩"])
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Colle l'élément dans l'app où tu étais")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(height: 38)
        .background(Theme.sidebar.opacity(0.6))
    }

    private func emptyText(_ m: ClipboardModel) -> String {
        let w = m.window
        if !w.query.isEmpty { return "Rien ne correspond à « \(w.query) »." }
        if w.filter == .pinned { return "Épingle ce qui sert souvent (⌘P) : il restera en haut, et ne sera jamais effacé automatiquement." }
        if m.items.isEmpty { return m.isActive ? "Copie quelque chose (⌘C) : ça s'affichera ici." : "L'historique est en pause." }
        return "Rien dans cette catégorie pour l'instant."
    }
}

/// The left column: pinned items, then the most recent ones.
struct ClipboardWindowList: View {
    @Environment(AppModel.self) private var app
    var items: [ClipboardItem]
    var selected: UUID?

    var body: some View {
        if Snapshot.isActive {
            ScrollArea { list }
        } else {
            ScrollViewReader { proxy in
                ScrollView { list }
                    .onChange(of: app.clipboard.window.selection) { _, s in
                        if app.clipboard.window.scrollToSelection, let s { proxy.scrollTo(s) }
                    }
            }
        }
    }

    private var list: some View {
        let w = app.clipboard.window
        let q = w.query.trimmingCharacters(in: .whitespaces)
        let pinned = q.isEmpty ? items.filter(\.pinned) : []
        let rest = q.isEmpty ? items.filter { !$0.pinned } : items
        return VStack(alignment: .leading, spacing: 0) {
            if !pinned.isEmpty {
                label("Épinglés")
                ForEach(pinned) { row($0) }
            }
            if !rest.isEmpty {
                label(q.isEmpty ? "Récents" : "Résultats")
                ForEach(rest) { row($0) }
            }
        }
        .padding(.bottom, 8)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.ui(10, .semibold)).tracking(0.7).foregroundStyle(Theme.text3)
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
    }

    private func row(_ item: ClipboardItem) -> some View {
        let w = app.clipboard.window
        return ClipboardWindowRow(item: item, selected: item.id == selected)
            .id(item.id)
            // One click shows it on the right, a double click pastes it (or copies it).
            .onTapGesture(count: 2) { w.use(item) }
            .simultaneousGesture(TapGesture().onEnded { w.select(item.id) })
            .contextMenu {
                Button(app.clipboard.canPaste ? "Coller" : "Copier") { w.use(item) }
                if app.clipboard.canPaste { Button("Copier sans coller") { w.use(item, copyOnly: true) } }
                Button(item.pinned ? "Désépingler" : "Épingler") { w.togglePin(item) }
                Divider()
                Button("Supprimer de l'historique", role: .destructive) { w.delete(item) }
            }
    }
}

struct ClipboardWindowRow: View {
    var item: ClipboardItem
    var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            CommandIconView(icon: ClipboardLauncher.icon(item), size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(item.textKind == .code ? .mono(12) : .ui(13, selected ? .medium : .regular))
                    .foregroundStyle(item.textKind == .link ? Theme.accent : Theme.text)
                    .lineLimit(1)
                Text(meta).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.count > 1 {
                Text("×\(item.count)").font(.ui(10.5, .semibold)).foregroundStyle(Theme.text3).monospacedDigit()
            }
            if item.pinned { Image(systemName: "pin.fill").font(.ui(10)).foregroundStyle(Theme.palette[4]) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(selected ? Theme.accent.opacity(0.16) : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts: [String] = []
        if let a = item.appName { parts.append(a) }
        parts.append(Fmt.relative(item.date))
        return parts.joined(separator: " · ")
    }
}

/// The right column: the whole item (all the text, the picture, the files), then where and when it was copied.
struct ClipboardWindowPreview: View {
    var item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            Rectangle().fill(Theme.border).frame(height: 1)
            details
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            let text = item.text ?? ""
            if item.textKind == .color, let c = ClipboardText.color(text) {
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).fill(c)
                        .frame(width: 150, height: 110)
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: Theme.line))
                    Text(text).font(.mono(15, .medium)).foregroundStyle(Theme.text).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollArea {
                    Text(text)
                        .font(item.textKind == .code ? .mono(12.5) : .ui(14))
                        .foregroundStyle(item.textKind == .link ? Theme.accent : Theme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
            }
        case .image:
            ClipboardWindowImage(item: item)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .files:
            ScrollArea {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.files ?? [], id: \.self) { path in
                        HStack(spacing: 10) {
                            FileIcon(path: path, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((path as NSString).lastPathComponent).font(.ui(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Text(FS.pretty((path as NSString).deletingLastPathComponent))
                                    .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = item.appName {
                line("Copié depuis") {
                    HStack(spacing: 5) {
                        if let path = item.appPath { FileIcon(path: path, size: 14) }
                        Text(name)
                    }
                }
            }
            line("Dernière copie") { Text(Fmt.relative(item.date)) }
            if item.count > 1 { line("Copié") { Text(Fmt.plural(item.count, "fois", "fois")) } }
            line("Contenu") { Text(contentSummary) }
            if item.pinned { line("Épinglé") { Text("Jamais effacé automatiquement") } }
        }
    }

    private func line<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.ui(11.5)).foregroundStyle(Theme.text3).frame(width: 110, alignment: .leading)
            value().font(.ui(11.5, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var contentSummary: String {
        switch item.kind {
        case .text:
            let t = item.text ?? ""
            let words = t.split(whereSeparator: { $0.isWhitespace }).count
            let lines = ClipboardText.lineCount(t)
            var parts = [Fmt.plural(t.count, "caractère", "caractères"), Fmt.plural(words, "mot", "mots")]
            if lines > 1 { parts.append(Fmt.plural(lines, "ligne", "lignes")) }
            return parts.joined(separator: " · ")
        case .image:
            guard let i = item.image else { return "Image" }
            return "\(Fmt.int(i.width)) × \(Fmt.int(i.height)) px · \(Fmt.bytes(i.bytes))"
        case .files:
            return Fmt.plural(item.files?.count ?? 0, "fichier", "fichiers")
        }
    }
}

/// The picture of an image item: its thumbnail at once, then a sharper copy read from the history's folder.
struct ClipboardWindowImage: View {
    var item: ClipboardItem
    @State private var sharp: CGImage?

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.r(10), style: .continuous)
        Group {
            if let cg = sharp ?? item.image.flatMap(ClipboardThumbs.image) {
                Image(decorative: cg, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(tile)
                    .overlay(tile.strokeBorder(Theme.border, lineWidth: Theme.line))
            } else {
                EmptyHint(text: "Cette image n'est plus disponible.", symbol: "photo")
            }
        }
        .task(id: item.id) {
            sharp = nil
            guard let info = item.image, !DemoData.isEnabled else { return }
            sharp = await Task.detached(priority: .userInitiated) { ClipboardStorage.previewImage(info.file) }.value
        }
    }
}

/// Shown instead of the list while the history has never been turned on.
struct ClipboardWindowNotice: View {
    var title: String
    var text: String
    var button: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            IconBadge(symbol: "doc.on.clipboard", tint: Theme.palette[4], size: 44)
            Text(title).font(.serif(22)).foregroundStyle(Theme.text)
            Text(text).font(.ui(12.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).frame(maxWidth: 480)
            Button(button, action: action).buttonStyle(SoftButtonStyle(prominent: true))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
