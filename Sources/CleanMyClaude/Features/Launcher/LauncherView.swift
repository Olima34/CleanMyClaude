import SwiftUI

/// The floating search panel.
struct LauncherView: View {
    static let width: CGFloat = 860
    static let height: CGFloat = 500
    static let previewWidth: CGFloat = 340

    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = app.launcher
        VStack(spacing: 0) {
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
        .frame(width: Self.width, height: Self.height)
        .background(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
        .background(TranslatorHost(channel: .launcher))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    @ViewBuilder
    private var results: some View {
        if Snapshot.isActive {
            ScrollArea { list }
        } else {
            ScrollViewReader { proxy in
                ScrollView { list }
                    .onChange(of: app.launcher.selection) { _, s in proxy.scrollTo(s) }
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
                    LauncherRow(command: item, selected: index == model.selection)
                        .id(index)
                        .onTapGesture { model.selection = index; model.runSelected() }
                        .onHover { if $0 { model.selection = index } }
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
            hint("⎋", "Fermer")
            Spacer()
            Text("Clean My Claude").font(.serif(12)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Theme.sidebar.opacity(0.6))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.ui(10.5, .semibold)).foregroundStyle(Theme.text2)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: Theme.r(4)).fill(Theme.track))
            Text(label).font(.ui(11)).foregroundStyle(Theme.text3)
        }
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
