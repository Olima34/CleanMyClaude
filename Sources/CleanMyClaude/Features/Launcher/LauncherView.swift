import SwiftUI

/// The floating search panel.
struct LauncherView: View {
    static let width: CGFloat = 860
    static let height: CGFloat = 500
    static let previewWidth: CGFloat = 340

    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            switch app.launcher.mode {
            case .search: search
            case .translator: TranslatorPanelView()
            case .assign(let target, let title): LauncherAssignView(target: target, title: title)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .background(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
        .background(TranslatorHost(channel: .launcher))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: app.launcher.mode) { _, mode in
            if mode == .search { DispatchQueue.main.async { focused = true } }
        }
    }

    private var search: some View {
        @Bindable var model = app.launcher
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ClaudeSpark(size: 22)
                if Snapshot.isActive {
                    Text(model.query).font(.system(size: 21)).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Apps, fichiers, calculs, traductions, commandes…", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(Theme.text)
                        .focused($focused)
                }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.text3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                results
                    .frame(maxWidth: .infinity, alignment: .top)
                if let path = model.selectedFile {
                    Rectangle().fill(Theme.border).frame(width: 1)
                    LauncherPreview(path: path)
                        .frame(width: Self.previewWidth)
                }
            }
            .frame(height: Self.height - 58 - 38 - 2, alignment: .top)
            .clipped()
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
    }

    @ViewBuilder
    private var results: some View {
        if Snapshot.isActive {
            ScrollArea { list }
        } else {
            ScrollViewReader { proxy in
                ScrollView { list }
                    .onChange(of: app.launcher.selection) { _, s in
                        // Only for the arrow keys: a trackpad scroll is never pulled back to the selection.
                        if app.launcher.scrollToSelection { proxy.scrollTo(s) }
                    }
            }
        }
    }

    private var list: some View {
        let model = app.launcher
        let offsets = Self.offsets(model.sections)
        return VStack(alignment: .leading, spacing: 0) {
            if model.sections.isEmpty {
                Text("Aucun résultat.")
                    .font(.ui(12.5)).foregroundStyle(Theme.text3).padding(18)
            }
            ForEach(Array(model.sections.enumerated()), id: \.element.id) { si, section in
                Text(section.title.uppercased())
                    .font(.ui(10, .semibold)).tracking(0.7).foregroundStyle(Theme.text3)
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
                ForEach(Array(section.items.enumerated()), id: \.offset) { i, item in
                    let index = offsets[si] + i
                    LauncherRow(command: item, selected: index == model.selection, hotkey: app.hotkeys.combo(for: item)?.display)
                        .modifier(LauncherFileDrag(command: item))
                        .id(index)
                        .onTapGesture { model.selection = index; model.runSelected() }
                        // Every movement of the pointer (not only entering a row): after a trackpad scroll,
                        // the row under the pointer is selected as soon as the mouse moves again.
                        .onContinuousHover { phase in
                            if case .active = phase { model.hover(index) }
                        }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "Naviguer")
            hint("↩", "Lancer")
            hint("⌘↩", "Action secondaire")
            hint("⌘K", "Raccourci")
            hint("⎋", "Fermer")
            Spacer()
            // Opens the app on the dashboard.
            Button {
                app.launcher.hide()
                app.page = .dashboard
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
            } label: {
                HStack(spacing: 5) {
                    ClaudeSpark(size: 11)
                    Text("Clean My Claude").font(.serif(12))
                }
                .foregroundStyle(Theme.text2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir Clean My Claude sur le tableau de bord")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Theme.sidebar.opacity(0.6))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        LauncherKeyHint(key: key, label: label)
    }

    private static func offsets(_ sections: [LauncherSection]) -> [Int] {
        var out: [Int] = []
        var n = 0
        for s in sections { out.append(n); n += s.items.count }
        return out
    }
}

struct LauncherRow: View {
    var command: AppCommand
    var selected: Bool
    /// The keyboard shortcut given to this result in Raccourcis, shown like Raycast does.
    var hotkey: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            CommandIconView(icon: command.icon, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title).font(.ui(13.5, selected ? .medium : .regular)).foregroundStyle(Theme.text).lineLimit(1)
                if let s = command.subtitle, !s.isEmpty {
                    Text(s).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if case .confirm = command.risk {
                Image(systemName: "exclamationmark.shield").font(.ui(11)).foregroundStyle(Theme.warn).help("Demande confirmation")
            }
            if selected, let h = command.hint {
                Text(h).font(.ui(11)).foregroundStyle(Theme.text3)
            }
            if let hotkey {
                Text(hotkey).font(.ui(10.5, .semibold)).foregroundStyle(Theme.text2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: Theme.r(5)).fill(Theme.track))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(selected ? Theme.accent.opacity(0.16) : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

struct CommandIconView: View {
    var icon: CommandIcon
    var size: CGFloat = 24

    var body: some View {
        switch icon {
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Theme.r(size * 0.26)).fill(tint.opacity(0.13)))
        case .file(let path):
            FileIcon(path: path, size: size)
        case .emoji(let e):
            Text(e).font(.system(size: size * 0.78)).frame(width: size, height: size)
        case .color(let c):
            RoundedRectangle(cornerRadius: Theme.r(size * 0.26)).fill(c).frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: Theme.r(size * 0.26)).strokeBorder(Theme.borderStrong, lineWidth: Theme.line))
        case .spark:
            ClaudeSpark(size: size * 0.8).frame(width: size, height: size)
        }
    }
}

/// ⌘K: the panel waits for the keys of the new shortcut.
struct LauncherAssignView: View {
    @Environment(AppModel.self) private var app
    var target: HotkeysTarget
    var title: String

    var body: some View {
        let current = app.hotkeys.binding(for: target)?.combo
        VStack(spacing: 18) {
            Spacer()
            CommandIconView(icon: app.hotkeys.icon(target), size: 56)
            VStack(spacing: 6) {
                Text("Un raccourci pour « \(title) »").font(.serif(24)).foregroundStyle(Theme.text)
                Text(target.kind).font(.ui(12)).foregroundStyle(Theme.text3)
            }
            Text(current?.display ?? "Tape les touches…")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(current == nil ? Theme.text3 : Theme.text)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.r(12)).strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            Text(app.launcher.assignMessage ?? (current == nil
                 ? "Avec ⌘, ⌃ ou ⌥. Il marchera partout, même quand Clean My Claude est caché."
                 : "Tape d'autres touches pour le changer."))
                .font(.ui(12.5)).foregroundStyle(app.launcher.assignMessage == nil ? Theme.text2 : Theme.warn)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Spacer()
            HStack(spacing: 16) {
                LauncherKeyHint(key: "⌫", label: current == nil ? "Aucun raccourci" : "Retirer le raccourci")
                LauncherKeyHint(key: "⎋", label: "Annuler")
                Spacer()
                Text("Tous tes raccourcis : section Raccourcis").font(.ui(11)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Theme.sidebar.opacity(0.6))
        }
    }
}

/// A key and what it does, in the panel's footers.
struct LauncherKeyHint: View {
    var key: String
    var label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key).font(.ui(10.5, .semibold)).foregroundStyle(Theme.text2)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: Theme.r(4)).fill(Theme.track))
            Text(label).font(.ui(11)).foregroundStyle(Theme.text3)
        }
    }
}

/// A file, a folder or an app of the results can be dragged anywhere (Finder, Mail, a message, the Desktop…).
struct LauncherFileDrag: ViewModifier {
    var command: AppCommand

    func body(content: Content) -> some View {
        if case .file(let path) = command.icon, command.group == .files || command.group == .apps, !DemoData.isEnabled {
            content.onDrag {
                let provider = NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
                provider.suggestedName = (path as NSString).lastPathComponent
                return provider
            } preview: {
                LauncherDragPreview(path: path)
            }
        } else {
            content
        }
    }
}

/// What follows the pointer while dragging: the file's icon and name.
struct LauncherDragPreview: View {
    var path: String

    var body: some View {
        HStack(spacing: 8) {
            FileIcon(path: path, size: 32)
            Text((path as NSString).lastPathComponent).font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardRaised))
    }
}
