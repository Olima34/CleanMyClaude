import SwiftUI
import AppKit

struct ClipboardPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.clipboard
        let intro = !m.settings.acknowledged || m.showIntro
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "doc.on.clipboard", title: "Presse-papiers",
                     subtitle: "Tout ce que tu as copié, retrouvable en un instant : texte, liens, images et fichiers. Tout reste sur ce Mac, et les mots de passe ne sont jamais gardés.",
                     tint: Theme.palette[4], seed: 37) {
                if !intro { ClipboardStatePill() }
            }
            if intro {
                ClipboardIntro()
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ClipboardHistoryColumn().fixedSize(horizontal: false, vertical: true)
                    ClipboardSideColumn().frame(width: 340)
                }
            }
        }
    }
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
                Text(m.isActive ? "· clic pour mettre en pause" : "· clic pour reprendre").font(.ui(11.5)).foregroundStyle(Theme.text3)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(PillShape().fill(Theme.card))
            .overlay(PillShape().strokeBorder(Theme.border, lineWidth: Theme.line))
            .contentShape(PillShape())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Introduction

struct ClipboardIntro: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.clipboard
        // The demo shows the screen of someone who has never been asked.
        let access = DemoData.isEnabled ? ClipboardAccess.notAsked : ClipboardAccess.current
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 24) {
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Retrouve tout ce que tu as copié").font(.serif(26)).foregroundStyle(Theme.text)
                        Text("L'historique est désactivé tant que tu ne l'allumes pas. Voici exactement ce qu'il fait :")
                            .font(.ui(13)).foregroundStyle(Theme.text2)
                        VStack(alignment: .leading, spacing: 10) {
                            point("tray.full", "Il garde le texte, les liens, les images et les fichiers que tu copies, avec l'app d'où ils viennent.")
                            point("lock.shield", "Il ignore les mots de passe : tout ce qu'un gestionnaire marque comme confidentiel, et tout ce qui est copié pendant que 1Password, Bitwarden, Mots de passe ou une autre app de ta liste est au premier plan.")
                            point("internaldrive", "Tout reste sur ce Mac, dans le dossier de Clean My Claude. Rien n'est envoyé nulle part.")
                            point("slider.horizontal.3", "Tu choisis combien garder (200 éléments, 200 Mo et 30 jours par défaut), tu épingles, tu effaces quand tu veux.")
                            point("command", "Depuis le lanceur, tape « cb » et quelques mots pour retrouver un élément et le recoller.")
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
                    }
                    Spacer(minLength: 0)
                    ClipboardIllustration().padding(.top, 8)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                ClipboardAccessCard(access: access)
                Callout(symbol: "hand.raised", title: "Et si macOS te pose une question ?",
                        text: "Depuis macOS 15.4, le système peut demander si une app a le droit de lire le presse-papiers. C'est normal pour un historique : choisis « Toujours autoriser » pour Clean My Claude. Sans cet accord, rien ne peut être enregistré.",
                        tint: Theme.palette[4])
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.ui(12, .medium)).foregroundStyle(Theme.palette[4]).frame(width: 18).padding(.top, 1)
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

/// What macOS says about reading the clipboard (15.4 and later).
struct ClipboardAccessCard: View {
    var access: ClipboardAccess

    var body: some View {
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: access == .allowed ? "checkmark.shield" : "doc.on.clipboard", tint: access.status.color, size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accès au presse-papiers").font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                    StatusBadge(status: access.status, text: access.label)
                    Text(access.explanation).font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    if access == .denied || access == .ask {
                        Button("Ouvrir Confidentialité et sécurité") { Finder.open("x-apple.systempreferences:com.apple.preference.security") }
                            .buttonStyle(SoftButtonStyle(small: true))
                    }
                }
                Spacer(minLength: 0)
            }
        }
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
            Text("Clic ou ↩ pour recopier · ↑ ↓ pour choisir · ⌫ pour supprimer" + (m.combo.map { " · \($0.display) ouvre l'historique dans le lanceur" } ?? ""))
                .font(.ui(11)).foregroundStyle(Theme.text3)
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
        if item.textKind == .link, let s = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
            Button("Ouvrir le lien") { Finder.open(s) }
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

    var body: some View {
        @Bindable var m = app.clipboard
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                stat(Fmt.int(m.items.count), m.items.count > 1 ? "éléments" : "élément")
                stat(Fmt.bytes(m.totalBytes), "sur ce Mac")
                stat(Fmt.int(m.skipped), m.skipped > 1 ? "ignorés" : "ignoré")
                    .help("Copies laissées de côté depuis le lancement : mots de passe, données temporaires, apps ignorées.")
            }
            Panel(title: "Réglages", symbol: "slider.horizontal.3", tint: Theme.palette[4]) {
                choice("Garder au plus", [50, 100, 200, 500, 1000], m.settings.maxItems, { Fmt.int($0) }) { m.settings.maxItems = $0; m.prune() }
                choice("Taille maximale", [50, 200, 500, 1000], m.settings.maxStorageMB, { $0 >= 1000 ? "1 Go" : "\($0) Mo" }) { m.settings.maxStorageMB = $0; m.prune() }
                choice("Conserver", [1, 7, 30, 0], m.settings.retentionDays, { $0 == 0 ? "Toujours" : ($0 == 1 ? "1 jour" : "\($0) jours") }) {
                    m.settings.retentionDays = $0
                    m.prune()
                }
                Text("Les épingles ne sont jamais effacées automatiquement.").font(.ui(11)).foregroundStyle(Theme.text3)
                Divider().overlay(Theme.border)
                VStack(spacing: 10) {
                    ClipboardSwitch(title: "Garder les images", detail: "Captures, photos copiées : enregistrées en PNG dans le dossier de l'app.", isOn: $m.settings.keepImages)
                    ClipboardSwitch(title: "Garder les fichiers", detail: "Seul le chemin est gardé, pas une copie du fichier.", isOn: $m.settings.keepFiles)
                    ClipboardSwitch(title: "Coller directement depuis le lanceur", detail: "Sinon, l'élément est copié et tu colles avec ⌘V.", isOn: $m.settings.pasteDirectly)
                }
                Divider().overlay(Theme.border)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raccourci de l'historique").font(.ui(12.5)).foregroundStyle(Theme.text)
                        Text("Ouvre le lanceur sur « cb »").font(.ui(11)).foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    ShortcutRecorder(combo: m.combo) { m.setCombo($0) }
                }
            }
            if m.settings.pasteDirectly {
                PermissionCard(permission: .accessibility,
                               reason: "Pour coller directement dans l'app au premier plan quand tu choisis un élément dans le lanceur. Sans elle, l'élément est simplement copié.")
            }
            ClipboardAccessCard(access: ClipboardAccess.current)
            Panel(title: "Apps ignorées", subtitle: "Rien de ce que tu copies dans ces apps n'est gardé", symbol: "eye.slash", tint: Theme.palette[4]) {
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

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.serif(21)).foregroundStyle(Theme.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.ui(11)).foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(12)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }

    private func choice(_ title: String, _ values: [Int], _ current: Int, _ label: @escaping (Int) -> String,
                        _ pick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.ui(12)).foregroundStyle(Theme.text2)
            HStack(spacing: 5) {
                ForEach(values, id: \.self) { v in
                    ClipboardChip(title: label(v), selected: v == current) { pick(v) }
                }
            }
        }
    }
}

struct ClipboardChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(11.5, selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.ink(on: Theme.palette[4]) : Theme.text2)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(PillShape().fill(selected ? Theme.palette[4] : Theme.bg))
                .overlay(PillShape().strokeBorder(selected ? Color.clear : Theme.border, lineWidth: Theme.line))
                .contentShape(PillShape())
        }
        .buttonStyle(.plain)
    }
}

struct ClipboardSwitch: View {
    var title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(12.5)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .switchToggles()
        .controlSize(.small)
    }
}
