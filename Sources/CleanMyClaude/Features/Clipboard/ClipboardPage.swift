import SwiftUI
import AppKit

struct ClipboardPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.clipboard
        let intro = !m.settings.acknowledged || m.showIntro
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "doc.on.clipboard", title: "Presse-papiers",
                     subtitle: "Tout ce que tu as copié, retrouvé en un instant.",
                     tint: Theme.palette[4], seed: 37, tip: intro ? nil : Self.tip) {
                if !intro {
                    HStack(spacing: 10) {
                        ClipboardStatePill()
                        ScanButton(title: "Ouvrir la fenêtre", symbol: "macwindow") { m.window.show() }
                    }
                }
            }
            if intro {
                ClipboardIntro()
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ClipboardHistoryColumn().fixedSize(horizontal: false, vertical: true)
                    ClipboardSideColumn().frame(width: 320).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static let tip = HelpTip(
        id: "clipboard.page", title: "Ton historique",
        text: "Clic ou ↩ recopie un élément, ↑ ↓ choisit, ⌫ l'efface. Clic droit pour l'épingler (il ne sera jamais effacé automatiquement) ou ne plus rien garder d'une app. Le raccourci de l'historique, ou « cb » dans le lanceur, ouvre sa fenêtre depuis n'importe où.")
}

/// The action bar pinned at the bottom of the page.
struct ClipboardBottomBar: View {
    @Environment(AppModel.self) private var app
    @State private var confirm = false

    var body: some View {
        let m = app.clipboard
        let unpinned = m.items.filter { !$0.pinned }.count
        if m.settings.acknowledged && (!m.items.isEmpty || !m.settings.enabled) {
            ActionBar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.isActive ? Fmt.plural(m.items.count, "élément", "éléments") : "Historique en pause")
                        .font(.serif(17)).foregroundStyle(Theme.text).monospacedDigit()
                    Text(m.isActive ? "\(Fmt.bytes(m.totalBytes)) sur ce Mac · \(Fmt.plural(m.items.filter(\.pinned).count, "épingle", "épingles"))"
                         : "Rien de ce que tu copies n'est enregistré")
                        .font(.ui(11)).foregroundStyle(Theme.text3)
                }
                Spacer()
                Button(m.settings.enabled ? "Mettre en pause" : "Reprendre") { m.setEnabled(!m.settings.enabled) }
                    .buttonStyle(SoftButtonStyle(prominent: !m.settings.enabled))
                // Pinned items are never cleared: with only those, there is nothing to clear.
                if unpinned > 0 {
                    Button("Tout effacer…") { confirm = true }
                        .buttonStyle(SoftButtonStyle(destructive: true))
                }
            }
            .confirmAction("Effacer l'historique ?",
                           message: unpinned == 1 ? "L'élément non épinglé sera effacé de ce Mac. Les épingles restent."
                               : "Les \(Fmt.int(unpinned)) éléments non épinglés seront effacés de ce Mac, images comprises. Les épingles restent.",
                           button: "Effacer", isPresented: $confirm) {
                m.clear()
            }
        }
    }
}

/// "Actif · 128 éléments", with a click to pause.
struct ClipboardStatePill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.clipboard
        Button { m.setEnabled(!m.settings.enabled) } label: {
            HStack(spacing: 7) {
                Circle().fill(m.isActive ? Theme.good : Theme.warn).frame(width: 7, height: 7)
                Text(m.isActive ? "Actif" : "En pause").font(.ui(12, .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(PillShape().fill(Theme.card))
            .overlay(PillShape().strokeBorder(Theme.border, lineWidth: Theme.line))
            .contentShape(PillShape())
        }
        .buttonStyle(.plain)
        .help(m.isActive ? "Mettre l'historique en pause" : "Reprendre l'historique")
    }
}

// MARK: - Introduction

struct ClipboardIntro: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.clipboard
        // The demo shows the screen of someone who has never been asked.
        let access = DemoData.isEnabled ? ClipboardAccess.notAsked : ClipboardAccess.current
        Card(padding: 24) {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Retrouve tout ce que tu as copié").font(.serif(26)).foregroundStyle(Theme.text)
                    VStack(alignment: .leading, spacing: 10) {
                        point("tray.full", "Le texte, les liens, les images et les fichiers que tu copies, avec leur app.")
                        point("lock.shield", "Jamais les mots de passe, ni ce qui ressemble à un secret.")
                            .help("Ce qu'un gestionnaire marque comme confidentiel, ce qui est copié pendant que 1Password, Bitwarden, Mots de passe ou une autre app de ta liste est au premier plan, et ce qui ressemble à un secret : clé d'API, jeton, clé privée, code à usage unique.")
                        point("internaldrive", "Tout reste sur ce Mac : 200 éléments et 30 jours par défaut.")
                    }
                    HStack(spacing: 10) {
                        Button {
                            m.showIntro = false
                            m.setEnabled(true)
                        } label: {
                            Label("Activer l'historique", systemImage: "doc.on.clipboard.fill")
                        }
                        .buttonStyle(SoftButtonStyle(prominent: true))
                        .disabled(DemoData.isEnabled && !Snapshot.isActive)
                        Text("Tu pourras le mettre en pause à tout moment.").font(.ui(11.5)).foregroundStyle(Theme.text3)
                    }
                    .padding(.top, 4)
                    Divider().overlay(Theme.border)
                    ClipboardAccessRow(access: access, badgeAtEnd: false)
                }
                Spacer(minLength: 0)
                ClipboardIllustration().padding(.top, 8)
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if Theme.icons != .hidden {
                Image(systemName: symbol).font(.ui(12, .medium))
                    .foregroundStyle(Theme.icons == .tinted ? Theme.palette[4] : Theme.text2).frame(width: 18).padding(.top, 1)
            }
            Text(text).font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Three little cards in a stack: a text, a picture, a link.
struct ClipboardIllustration: View {
    var body: some View {
        ZStack {
            card(symbol: "link", lines: [0.8, 0.5], tint: Theme.palette[1]).rotationEffect(.degrees(-9)).offset(x: -50, y: 62)
            card(symbol: "text.alignleft", lines: [0.9, 0.7, 0.45], tint: Theme.palette[4]).offset(x: -30, y: -46)
            card(symbol: "photo", lines: [0.6], tint: Theme.palette[5]).rotationEffect(.degrees(7)).offset(x: 66, y: 34)
        }
        .frame(width: 280, height: 250)
    }

    private func card(symbol: String, lines: [CGFloat], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.ui(15, .semibold)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(tint.opacity(0.15)))
            ForEach(Array(lines.enumerated()), id: \.offset) { _, w in
                PillShape().fill(Theme.borderStrong).frame(width: 120 * w, height: 6)
            }
        }
        .padding(14)
        .frame(width: 150, height: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).fill(Theme.cardRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).strokeBorder(Theme.border, lineWidth: Theme.line))
        .themedShadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

/// What macOS says about reading the clipboard (15.4 and later), in one row: its sentence only when something is to be done.
struct ClipboardAccessRow: View {
    var access: ClipboardAccess
    /// In a column of settings, the badge sits at the end of the row like the other values.
    var badgeAtEnd = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Accès macOS").font(.ui(12.5)).foregroundStyle(Theme.text)
                if badgeAtEnd { Spacer(minLength: 6) }
                StatusBadge(status: access.status, text: access.label)
            }
            if access != .allowed && access != .unknown {
                Text(access.explanation)
                    .font(.ui(11.5)).foregroundStyle(access == .denied ? Theme.bad : Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if access == .denied || access == .ask {
                Button("Ouvrir Confidentialité et sécurité") { Finder.open("x-apple.systempreferences:com.apple.preference.security") }
                    .buttonStyle(SoftButtonStyle(small: true))
            }
        }
        .help(access.explanation)
    }
}

// MARK: - History

struct ClipboardHistoryColumn: View {
    @Environment(AppModel.self) private var app
    @State private var limit = 60
    @State private var copiedID: UUID?
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var m = app.clipboard
        let visible = m.visible
        let shown = Array(visible.prefix(limit))
        let pinned = shown.filter(\.pinned)
        let recent = shown.filter { !$0.pinned }
        VStack(alignment: .leading, spacing: 12) {
            ClipboardSearchField(text: $m.search, onSubmit: { copySelected(visible) }, onMove: { move($0, in: visible) })
            PillPicker(options: ClipboardFilterTab.allCases, selection: $m.filter, label: { $0.title }, badge: { tab in
                let n = m.count(tab)
                return n > 0 && tab != .all ? Fmt.int(n) : nil
            })
            if ClipboardAccess.current == .denied {
                Callout(symbol: "exclamationmark.triangle", title: "macOS refuse l'accès au presse-papiers",
                        text: ClipboardAccess.denied.explanation, tint: Theme.bad)
            }
            Card(padding: 8) {
                if visible.isEmpty {
                    EmptyHint(text: emptyText(m), symbol: m.search.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .padding(.vertical, 30)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        if !pinned.isEmpty {
                            label("Épinglés")
                            ForEach(pinned) { row($0, m) }
                        }
                        if !recent.isEmpty {
                            if !pinned.isEmpty { label(m.search.isEmpty ? "Récents" : "Résultats") }
                            ForEach(recent) { row($0, m) }
                        }
                        if visible.count > limit {
                            Button("Afficher \(min(60, visible.count - limit)) de plus") { limit += 60 }
                                .buttonStyle(SoftButtonStyle(small: true))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.upArrow) { move(-1, in: visible); return .handled }
            .onKeyPress(.downArrow) { move(1, in: visible); return .handled }
            .onKeyPress(.return) { copySelected(visible); return .handled }
            .onKeyPress(.delete) {
                if let id = m.selection { m.delete(id) }
                return .handled
            }
        }
        .onChange(of: m.search) { _, _ in limit = 60 }
        .onChange(of: m.filter) { _, _ in limit = 60 }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.ui(10, .semibold)).tracking(0.7).foregroundStyle(Theme.text3)
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }

    private func row(_ item: ClipboardItem, _ m: ClipboardModel) -> some View {
        ClipboardRow(item: item, selected: m.selection == item.id, copied: copiedID == item.id) {
            m.selection = item.id
            listFocused = true
            copy(item, m)
        }
    }

    private func emptyText(_ m: ClipboardModel) -> String {
        if !m.search.isEmpty { return "Rien ne correspond à « \(m.search) »." }
        if m.filter == .pinned { return "Épingle ce qui sert souvent : il restera en haut, et ne sera jamais effacé automatiquement." }
        if m.items.isEmpty { return m.isActive ? "Copie quelque chose (⌘C) : ça s'affichera ici." : "L'historique est en pause." }
        return "Rien dans cette catégorie pour l'instant."
    }

    private func move(_ delta: Int, in list: [ClipboardItem]) {
        let m = app.clipboard
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == m.selection } ?? (delta > 0 ? -1 : list.count)
        let next = min(list.count - 1, max(0, i + delta))
        m.selection = list[next].id
        if next >= limit { limit = next + 20 }
    }

    private func copySelected(_ list: [ClipboardItem]) {
        let m = app.clipboard
        guard let item = list.first(where: { $0.id == m.selection }) ?? list.first else { return }
        m.selection = item.id
        copy(item, m)
    }

    private func copy(_ item: ClipboardItem, _ m: ClipboardModel) {
        let outcome = m.recopy(item)
        switch outcome {
        case .failed(let message): HUD.show(message, symbol: "xmark.octagon.fill")
        case .message(let message): HUD.show(message, symbol: "theatermasks")
        default:
            copiedID = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if copiedID == item.id { copiedID = nil } }
        }
    }
}

struct ClipboardSearchField: View {
    @Binding var text: String
    var onSubmit: () -> Void
    var onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.ui(12)).foregroundStyle(Theme.text3)
            if Snapshot.isActive {
                Text(text.isEmpty ? "Rechercher dans l'historique (texte, app, nom de fichier…)" : text)
                    .font(.ui(13)).foregroundStyle(text.isEmpty ? Theme.text3 : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Rechercher dans l'historique (texte, app, nom de fichier…)", text: $text)
                    .textFieldStyle(.plain)
                    .font(.ui(13))
                    .onSubmit(onSubmit)
                    .onKeyPress(.downArrow) { onMove(1); return .handled }
                    .onKeyPress(.upArrow) { onMove(-1); return .handled }
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

struct ClipboardRow: View {
    var item: ClipboardItem
    var selected: Bool
    var copied: Bool
    var onCopy: () -> Void
    @Environment(AppModel.self) private var app
    @State private var hovering = false

    var body: some View {
        let m = app.clipboard
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(preview)
                    .font(item.textKind == .code ? .mono(11.5) : .ui(12.5))
                    .foregroundStyle(item.textKind == .link ? Theme.accent : Theme.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    if let path = item.appPath {
                        FileIcon(path: path, size: 13)
                    }
                    Text(meta).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
            }
            if copied {
                Tag(text: "Copié", symbol: "checkmark", tint: Theme.good, filled: true)
            } else if hovering || selected {
                HStack(spacing: 2) {
                    action(item.pinned ? "pin.slash" : "pin", item.pinned ? "Désépingler" : "Épingler") { m.togglePin(item.id) }
                    action("doc.on.doc", "Copier") { onCopy() }
                    action("trash", "Supprimer de l'historique") { m.delete(item.id) }
                }
            } else {
                HStack(spacing: 6) {
                    if item.count > 1 {
                        Text("×\(item.count)").font(.ui(10.5, .semibold)).foregroundStyle(Theme.text3).monospacedDigit()
                            .help("Copié \(item.count) fois")
                    }
                    if item.pinned { Image(systemName: "pin.fill").font(.ui(10.5)).foregroundStyle(Theme.palette[4]) }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(selected ? Theme.selected : (hovering ? Theme.hover.opacity(0.6) : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
        .contextMenu { menu(m) }
    }

    @ViewBuilder
    private var leading: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.r(8), style: .continuous)
        switch item.kind {
        case .image:
            if let info = item.image, let cg = ClipboardThumbs.image(info) {
                Image(decorative: cg, scale: 2).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 40).clipShape(tile)
                    .overlay(tile.strokeBorder(Theme.border, lineWidth: Theme.line))
            } else {
                icon("photo")
            }
        case .files:
            FileIcon(path: item.files?.first ?? "/", size: 34).frame(width: 52, height: 40)
        case .text:
            if item.textKind == .color, let c = ClipboardText.color(item.text ?? "") {
                tile.fill(c).frame(width: 52, height: 40).overlay(tile.strokeBorder(Theme.border, lineWidth: Theme.line))
            } else {
                icon(item.textKind == .link ? "link" : (item.textKind == .code ? "chevron.left.forwardslash.chevron.right" : "text.alignleft"))
            }
        }
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.ui(15, .medium))
            .foregroundStyle(Theme.palette[4])
            .frame(width: 52, height: 40)
            .background(RoundedRectangle(cornerRadius: Theme.r(8), style: .continuous).fill(Theme.palette[4].opacity(0.12)))
    }

    private var preview: String {
        switch item.kind {
        case .text:
            let lines = (item.text ?? "").split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
            if item.textKind == .code { return lines.prefix(2).joined(separator: "\n") }
            return lines.prefix(3).map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }.joined(separator: " ⏎ ")
        default:
            return item.title
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let a = item.appName { parts.append(a) }
        parts.append(Fmt.relative(item.date))
        switch item.kind {
        case .text:
            let lines = ClipboardText.lineCount(item.text ?? "")
            parts.append(lines > 1 ? Fmt.plural(lines, "ligne", "lignes") : Fmt.plural((item.text ?? "").count, "caractère", "caractères"))
        case .image:
            if let i = item.image { parts.append(Fmt.bytes(i.bytes)) }
        case .files:
            if let f = item.files?.first { parts.append(FS.pretty((f as NSString).deletingLastPathComponent)) }
        }
        return parts.joined(separator: " · ")
    }

    private func action(_ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.ui(11.5)).foregroundStyle(Theme.text2).frame(width: 26, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func menu(_ m: ClipboardModel) -> some View {
        Button("Copier") { onCopy() }
        Button(item.pinned ? "Désépingler" : "Épingler") { m.togglePin(item.id) }
        if item.textKind == .link, let s = item.text {
            // Web pages and mail open; a file:// link is only shown in the Finder; any other kind of link stays closed.
            switch ClipboardLinks.action(for: s) {
            case .open(let url): Button("Ouvrir le lien") { NSWorkspace.shared.open(url) }
            case .reveal(let path): Button("Afficher dans le Finder") { Finder.reveal(path) }
            case .refuse: EmptyView()
            }
        }
        if item.kind == .files, let f = item.files?.first {
            Button("Afficher dans le Finder") { Finder.reveal(f) }
        }
        if let id = item.appBundleID, let name = item.appName, !ClipboardFilter.isExcluded(id, list: m.settings.excluded) {
            Divider()
            Button("Ne plus rien garder de \(name)") { m.exclude(bundleID: id, name: name) }
        }
        Divider()
        Button("Supprimer de l'historique", role: .destructive) { m.delete(item.id) }
    }
}

// MARK: - Settings

struct ClipboardSideColumn: View {
    @Environment(AppModel.self) private var app
    /// The list of ignored apps stays folded: its count says enough most of the time.
    @State private var showExcluded = false

    var body: some View {
        @Bindable var m = app.clipboard
        VStack(alignment: .leading, spacing: 14) {
            Panel(title: "Réglages", symbol: "slider.horizontal.3", tint: Theme.palette[4]) {
                if m.skipped > 0 {
                    Text(m.skipped > 1 ? "\(Fmt.int(m.skipped)) ignorés" : "1 ignoré")
                        .font(.ui(11.5)).foregroundStyle(Theme.text3).monospacedDigit()
                        .help("Copies laissées de côté depuis le lancement : mots de passe, secrets probables, données temporaires, apps ignorées.")
                }
            } content: {
                VStack(spacing: 8) {
                    choice("Garder au plus", [50, 100, 200, 500, 1000], m.settings.maxItems, { Fmt.plural($0, "élément", "éléments") }) {
                        m.settings.maxItems = $0
                        m.prune()
                    }
                    choice("Jusqu'à", [50, 200, 500, 1000], m.settings.maxStorageMB, { $0 >= 1000 ? "1 Go" : "\($0) Mo" }) {
                        m.settings.maxStorageMB = $0
                        m.prune()
                    }
                    choice("Pendant", [1, 7, 30, 0], m.settings.retentionDays, { $0 == 0 ? "Toujours" : ($0 == 1 ? "1 jour" : "\($0) jours") }) {
                        m.settings.retentionDays = $0
                        m.prune()
                    }
                }
                .help("Les épingles ne sont jamais effacées automatiquement.")
                Divider().overlay(Theme.border)
                VStack(spacing: 10) {
                    ClipboardSwitch(title: "Garder les images", help: "Captures et photos copiées, enregistrées en PNG dans le dossier de l'app.", isOn: $m.settings.keepImages)
                    ClipboardSwitch(title: "Garder les fichiers", help: "Seul le chemin est gardé, pas une copie du fichier.", isOn: $m.settings.keepFiles)
                    ClipboardSwitch(title: "Coller directement", help: "Depuis la fenêtre de l'historique, dans l'app au premier plan. Sinon, l'élément est copié et tu colles avec ⌘V.",
                                    isOn: $m.settings.pasteDirectly)
                    ClipboardSwitch(title: "Ignorer les secrets probables",
                                    help: "Clés d'API, jetons, clés privées, codes à usage unique, mots de passe copiés depuis un navigateur ou un terminal : reconnus à leur forme, ils ne sont pas enregistrés.",
                                    isOn: $m.settings.skipSecrets)
                }
                Divider().overlay(Theme.border)
                HStack {
                    Text("Raccourci").font(.ui(12.5)).foregroundStyle(Theme.text)
                        .help("Ouvre la fenêtre de l'historique depuis n'importe quelle app")
                    Spacer()
                    ShortcutRecorder(combo: m.combo) { m.setCombo($0) }
                }
                Divider().overlay(Theme.border)
                ClipboardAccessRow(access: ClipboardAccess.current)
            }
            if m.settings.pasteDirectly && !AppPermission.accessibility.isGranted {
                PermissionCard(permission: .accessibility,
                               reason: "Pour coller dans l'app au premier plan. Sans elle, l'élément est simplement copié.")
            }
            Panel(title: "Apps ignorées",
                  subtitle: Fmt.plural(m.settings.excluded.count, "app", "apps"),
                  symbol: "eye.slash", tint: Theme.palette[4]) {
                if !m.settings.excluded.isEmpty {
                    Button(showExcluded ? "Masquer" : "Voir la liste") { showExcluded.toggle() }
                        .buttonStyle(SoftButtonStyle(small: true))
                }
            } content: {
                if showExcluded {
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(m.settings.excluded) { a in
                            HStack(spacing: 4) {
                                Text(a.name).font(.ui(11.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Button { m.removeExclusion(a.bundleID) } label: {
                                    Image(systemName: "xmark").font(.ui(8.5, .bold)).foregroundStyle(Theme.text3).frame(width: 14, height: 14)
                                }
                                .buttonStyle(.plain)
                                .help("Ne plus ignorer \(a.name)")
                            }
                            .padding(.leading, 9)
                            .padding(.trailing, 4)
                            .padding(.vertical, 4)
                            .background(PillShape().fill(Theme.bg))
                            .overlay(PillShape().strokeBorder(Theme.border, lineWidth: Theme.line))
                            .help(a.bundleID)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button { m.chooseExcludedApp() } label: { Label("Ajouter une app…", systemImage: "plus") }
                        .buttonStyle(SoftButtonStyle(small: true))
                    if m.settings.excluded != ClipboardFilter.passwordManagers {
                        Button("Liste par défaut") { m.settings.excluded = ClipboardFilter.passwordManagers }
                            .buttonStyle(SoftButtonStyle(small: true))
                    }
                }
            }
        }
    }

    /// "Garder au plus ……… 200 éléments ⌄": a value chosen from a short menu, on one line.
    private func choice(_ title: String, _ values: [Int], _ current: Int, _ label: @escaping (Int) -> String,
                        _ pick: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title).font(.ui(12.5)).foregroundStyle(Theme.text)
            Spacer()
            BorderlessMenu {
                Picker(title, selection: Binding(get: { current }, set: pick)) {
                    ForEach(values, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(label(current)).font(.ui(12, .medium)).foregroundStyle(Theme.text2)
            }
        }
    }
}

struct ClipboardSwitch: View {
    var title: String
    var help: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(.ui(12.5)).foregroundStyle(Theme.text)
        }
        .switchToggles()
        .controlSize(.small)
        .help(help ?? title)
    }
}
