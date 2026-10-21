import SwiftUI
import AppKit

struct WheelPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.wheel
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.wheel.symbol, title: "Roue des fichiers",
                     subtitle: "Glisse un fichier en marquant une petite pause, ou secoue-le : une roue d'actions s'ouvre sous ton pointeur. Lâche-le sur une action, la copie apparaît à côté de l'original, qui ne bouge pas.",
                     tint: Theme.brand, seed: 53) {
                WheelStatePill()
            }
            HStack(alignment: .top, spacing: 14) {
                WheelDesigner().fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 14) {
                    WheelGesturesPanel()
                    WheelTryZone()
                    WheelDestinationPanel()
                    if !m.history.isEmpty { WheelHistoryPanel() }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 340)
            }
        }
    }
}

/// "Active · clic pour mettre en pause".
struct WheelStatePill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.wheel
        let on = m.isActive
        Button { m.setEnabled(!m.settings.enabled) } label: {
            HStack(spacing: 7) {
                Circle().fill(on ? Theme.good : Theme.warn).frame(width: 7, height: 7)
                Text(on ? "Active" : "En pause").font(.ui(12, .semibold))
                Text(on ? "· clic pour mettre en pause" : "· clic pour l'activer").font(.ui(11.5)).foregroundStyle(Theme.text3)
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

// MARK: - The wheel of each kind of file

/// The wheel of a kind of file, live (point at a segment to read what it does), and what sits on it.
struct WheelDesigner: View {
    @Environment(AppModel.self) private var app
    @State private var preview = WheelOverlayState()

    var body: some View {
        let m = app.wheel
        let family = m.family
        let file = WheelModel.sample(family)
        let menu = m.menu(for: [file])
        Panel(title: "Ta roue", subtitle: "Ce qu'elle propose dépend du fichier. Survole-la pour lire chaque action ; coche, décoche et range les tiennes.",
              symbol: "dial.medium", tint: Theme.brand) {
            Button("Rétablir") { m.resetLayout(family) }
                .buttonStyle(SoftButtonStyle(small: true))
                .disabled(m.settings.layouts[family.rawValue] == nil)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                WheelChips(options: WheelFamily.allCases.filter { $0 != .folder }, selection: Binding(get: { m.family }, set: { m.family = $0 }),
                           label: \.title, symbol: { $0.symbol })
                ZStack {
                    WheelWallpaper()
                    WheelView(state: preview, inWindow: true)
                        .scaleEffect(0.86)
                        .frame(width: WheelGeometry.side * 0.86, height: WheelGeometry.side * 0.86)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p):
                                let s = WheelGeometry.side * 0.86
                                let hit = preview.geometry.hit(CGPoint(x: (p.x - s / 2) / 0.86, y: (p.y - s / 2) / 0.86))
                                if preview.hovered != hit { preview.hovered = hit }
                            case .ended:
                                preview.hovered = nil
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .frame(height: WheelGeometry.side * 0.86 + 24)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous))
                Group {
                    if let a = preview.action(at: preview.hovered) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(a.title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                            Text(a.detail).font(.ui(12)).foregroundStyle(Theme.text2)
                            if a.editor != nil { Tag(text: "petite fenêtre", symbol: "macwindow", tint: Theme.brand, filled: true) }
                        }
                    } else {
                        Text("Ici pour « \(file.name) ». Le centre, quand tu y lâches le fichier, montre toutes les actions possibles.")
                            .font(.ui(12)).foregroundStyle(Theme.text3)
                    }
                }
                .frame(minHeight: 34, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                WheelLayoutList(family: family)
            }
        }
        .onAppear { refresh(menu, file) }
        .onChange(of: menu) { _, new in refresh(new, file) }
    }

    private func refresh(_ menu: WheelMenu, _ file: WheelFile) {
        preview.files = [file]
        preview.menu = menu
        preview.shown = true
        if Snapshot.isActive && preview.hovered == nil && !menu.tools.isEmpty { preview.hovered = .tool(0) }
    }
}

/// A desktop of colors behind the settings' wheel, so that its glass shows.
struct WheelWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.brand.opacity(0.75), Theme.accent.opacity(0.55), Theme.palette[5].opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Theme.palette[2].opacity(0.55)).frame(width: 260).blur(radius: 60).offset(x: -170, y: -90)
            Circle().fill(Theme.palette[4].opacity(0.5)).frame(width: 220).blur(radius: 60).offset(x: 190, y: 110)
        }
    }
}

/// The actions of a family: on the wheel (in their order) or left aside.
struct WheelLayoutList: View {
    @Environment(AppModel.self) private var app
    var family: WheelFamily

    var body: some View {
        let m = app.wheel
        let chosen = m.actions(for: family)
        let pool = family.pool
        let sample = WheelModel.sample(family)
        let fits = Set(WheelMenu.available([sample], in: pool, capabilities: m.capabilities))
        VStack(alignment: .leading, spacing: 10) {
            ring("Anneau intérieur · convertir", limit: WheelMenu.maxFormats, chosen: chosen.filter(\.isFormat),
                 aside: pool.filter { $0.isFormat && !chosen.contains($0) }, fits: fits)
            ring("Anneau extérieur · outils", limit: WheelMenu.maxTools, chosen: chosen.filter { !$0.isFormat },
                 aside: pool.filter { !$0.isFormat && !chosen.contains($0) }, fits: fits)
        }
    }

    @ViewBuilder
    private func ring(_ title: String, limit: Int, chosen: [WheelAction], aside: [WheelAction], fits: Set<WheelAction>) -> some View {
        if !chosen.isEmpty || !aside.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionLabel(text: title)
                    Text("\(Fmt.int(limit)) au plus").font(.ui(10.5)).foregroundStyle(Theme.text3).padding(.top, 6)
                }
                ForEach(Array(chosen.enumerated()), id: \.element) { i, a in
                    row(a, on: true, overflow: i >= limit, first: i == 0, last: i == chosen.count - 1, fits: fits.contains(a))
                }
                ForEach(aside) { a in row(a, on: false, overflow: false, first: true, last: true, fits: fits.contains(a)) }
            }
        }
    }

    private func row(_ a: WheelAction, on: Bool, overflow: Bool, first: Bool, last: Bool, fits: Bool) -> some View {
        let m = app.wheel
        return HoverRow {
            HStack(spacing: 10) {
                CheckBox(state: on ? .on : .off) { m.toggle(a, in: family) }
                IconBadge(symbol: a.symbol, tint: a.tint, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(a.title).font(.ui(12.5, .medium)).foregroundStyle(on ? Theme.text : Theme.text2)
                        if a.editor != nil { Image(systemName: "macwindow").font(.ui(9.5)).foregroundStyle(Theme.text3).help("Ouvre une petite fenêtre") }
                        if overflow { Tag(text: "pas de place", tint: Theme.warn, filled: true) }
                        if a.needsFFmpeg && !m.capabilities.ffmpeg { Tag(text: "demande ffmpeg", tint: Theme.text3) }
                        if a.needsSeveral { Tag(text: "plusieurs fichiers", tint: Theme.text3) }
                        if !fits && !a.needsFFmpeg && !a.needsSeveral { Tag(text: "selon le fichier", tint: Theme.text3) }
                    }
                    Text(a.detail).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 6)
                if on {
                    HStack(spacing: 2) {
                        arrow("chevron.up", disabled: first) { m.move(a, in: family, by: -1) }
                        arrow("chevron.down", disabled: last) { m.move(a, in: family, by: 1) }
                    }
                }
            }
        }
    }

    private func arrow(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(10, .semibold)).foregroundStyle(Theme.text2).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

// MARK: - Side column

struct WheelGesturesPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.wheel
        Panel(title: "Pour l'ouvrir", subtitle: "Pendant que tu glisses un ou plusieurs fichiers, depuis le Finder ou une autre app.",
              symbol: "hand.draw", tint: Theme.brand) {
            VStack(alignment: .leading, spacing: 12) {
                gesture("Maintenir puis glisser", "Appuie sur le fichier, garde-le immobile un instant, puis glisse-le.",
                        isOn: Binding(get: { m.settings.hold }, set: { m.settings.hold = $0 }))
                if m.settings.hold {
                    HStack(spacing: 8) {
                        Text("Pause").font(.ui(11)).foregroundStyle(Theme.text3)
                        WheelChips(options: [0.3, 0.45, 0.7], selection: Binding(get: { m.settings.holdDelay }, set: { m.settings.holdDelay = $0 }),
                                   label: { String(format: "%g s", $0).replacingOccurrences(of: ".", with: ",") })
                    }
                    .padding(.leading, 2)
                }
                gesture("Secouer le fichier", "Deux ou trois petits allers-retours de côté pendant le glisser.",
                        isOn: Binding(get: { m.settings.shake }, set: { m.settings.shake = $0 }))
                gesture("Glisser avec ⇧", "Appuie sur Maj pendant que tu glisses.",
                        isOn: Binding(get: { m.settings.shift }, set: { m.settings.shift = $0 }))
                Divider().overlay(Theme.border)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Raccourci : la roue du fichier sélectionné dans le Finder").font(.ui(12, .medium)).foregroundStyle(Theme.text)
                    HStack {
                        ShortcutRecorder(combo: m.combo) { m.setCombo($0) }
                        Spacer()
                    }
                    Text("Ensuite, clique une action (ou ← → et ↩). Le Finder te demandera une fois l'autorisation.")
                        .font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .switchToggles()
            .disabled(!m.settings.enabled)
            .opacity(m.settings.enabled ? 1 : 0.55)
        }
    }

    private func gesture(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(12.5, .medium)).foregroundStyle(Theme.text)
                Text(detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Drop a file here: its wheel opens under the pointer, to try it out.
struct WheelTryZone: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DropZone(title: "Essaie ici", subtitle: "dépose un fichier : sa roue s'ouvre", symbol: "dial.medium") { urls in
            app.wheel.openWheel(urls, at: NSEvent.mouseLocation, clicking: true)
        }
    }
}

struct WheelDestinationPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.wheel
        Panel(title: "Où vont les copies", symbol: "folder", tint: Theme.palette[1]) {
            VStack(alignment: .leading, spacing: 8) {
                WheelChips(options: WheelDestination.allCases, selection: Binding(get: { m.settings.destination }, set: { m.settings.destination = $0 }),
                           label: \.title)
                Text(m.settings.destination == .beside
                     ? "« photo recadrée.jpg » à côté de « photo.jpg ». Sur un disque en lecture seule, elle va dans Téléchargements. La première copie sur le Bureau, macOS te demandera d'autoriser l'accès."
                     : "Toutes les copies dans Téléchargements, quel que soit l'endroit d'où vient le fichier.")
                    .font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WheelHistoryPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.wheel
        Panel(title: "Dernières copies", subtitle: Fmt.plural(m.history.count, "copie faite avec la roue", "copies faites avec la roue"),
              symbol: "clock.arrow.circlepath", tint: Theme.good) {
            Button("Effacer") { m.clearHistory() }.buttonStyle(SoftButtonStyle(small: true))
        } content: {
            VStack(spacing: 2) {
                ForEach(m.history.prefix(8)) { r in
                    HoverRow {
                        HStack(spacing: 9) {
                            FileIcon(path: r.outputs.first ?? r.source, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.outputs.first.map { ($0 as NSString).lastPathComponent } ?? r.source)
                                    .font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                                Text("\(r.wheelAction?.title ?? r.action) · \(Fmt.relative(r.date))")
                                    .font(.ui(10.5)).foregroundStyle(Theme.text3).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let path = r.outputs.first {
                                Button { Finder.reveal(path) } label: {
                                    Image(systemName: "magnifyingglass").font(.ui(10.5)).foregroundStyle(Theme.text2).frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .help("Afficher dans le Finder")
                                .disabled(DemoData.isEnabled)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Bottom bar

struct WheelBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.wheel
        let running = m.runner.tasks.filter(\.isRunning).count
        ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.isActive ? "Roue active" : "Roue en pause").font(.serif(17)).foregroundStyle(Theme.text)
                Text(running > 0 ? "\(Fmt.plural(running, "action en cours", "actions en cours"))"
                     : (m.isActive ? "Glisse un fichier en marquant une pause, ou secoue-le" : "Les fichiers que tu glisses ne l'ouvrent plus"))
                    .font(.ui(11)).foregroundStyle(Theme.text3)
            }
            Spacer()
            Button(m.settings.enabled ? "Mettre en pause" : "Activer") { m.setEnabled(!m.settings.enabled) }
                .buttonStyle(SoftButtonStyle(prominent: !m.settings.enabled))
        }
    }
}
