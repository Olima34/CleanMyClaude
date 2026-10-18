import SwiftUI

struct CleanupPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.cleanup
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "sparkles", title: "Nettoyage du système",
                     subtitle: "Caches, journaux, restes de développement, fichiers oubliés : je trouve ce qui encombre ton Mac, tu choisis ce qui part.",
                     seed: 21) {
                ScanButton(title: model.hasResults ? "Relancer l'analyse" : "Analyser", running: model.isScanning) {
                    Task { await model.scan() }
                }
            }

            if model.isScanning {
                ScanProgressCard(title: "J'inspecte les recoins de ton Mac…", label: model.progressLabel, progress: model.progress)
            } else if !model.hasResults {
                CleanupIntro()
            } else {
                summary(model)
                if let r = model.lastReport {
                    Callout(symbol: r.failures.isEmpty ? "checkmark.seal" : "exclamationmark.triangle",
                            title: r.freed > 0 ? "\(Fmt.bytes(r.freed)) libérés" : "Nettoyage terminé",
                            text: r.summary + " Le détail est dans ~/Library/Logs/CleanMyClaude/actions.log.",
                            tint: r.failures.isEmpty ? Theme.good : Theme.warn)
                }
                ForEach(CleanupGroup.allCases) { g in
                    if !model.targets(in: g).isEmpty {
                        CleanupGroupPanel(group: g)
                    }
                }
                if model.claude.transcripts + model.claude.vm > 0 {
                    claudeKept(model.claude)
                }
            }
        }
    }

    private func summary(_ model: CleanupModel) -> some View {
        TileRow {
            StatTile(symbol: "magnifyingglass", value: Fmt.bytes(model.totalSize), label: "Trouvé",
                     detail: "\(Fmt.plural(model.targets.reduce(0) { $0 + $1.items.count }, "élément", "éléments")) dans \(Fmt.plural(CleanupGroup.allCases.filter { !model.targets(in: $0).isEmpty }.count, "catégorie", "catégories"))")
            StatTile(symbol: "checkmark.circle", value: Fmt.bytes(model.selectedSize), label: "Sélectionné",
                     detail: "\(Fmt.plural(model.selectedCount, "élément coché", "éléments cochés"))", tint: Theme.good)
            StatTile(symbol: "hand.thumbsup", value: Fmt.bytes(model.recommendedSize), label: "Sans risque",
                     detail: "Ce que je coche d'office : tout se reconstruit seul", tint: Theme.brand)
            StatTile(symbol: "leaf", value: Fmt.bytes(app.history.totalFreed), label: "Libéré au total",
                     detail: app.history.runs > 0 ? "En \(Fmt.plural(app.history.runs, "nettoyage", "nettoyages"))" : "Ton premier nettoyage t'attend",
                     tint: Theme.palette[2])
        }
    }

    private func claudeKept(_ c: ClaudeFootprint) -> some View {
        Callout(symbol: "lock.shield",
                title: "Ce que je garde exprès côté Claude",
                text: "Tes transcripts Claude Code (\(Fmt.bytes(c.transcripts))) servent à reprendre tes sessions et à ClaudeStats. La machine virtuelle de Cowork (\(Fmt.bytes(c.vm))) et les versions de Claude Code (\(Fmt.bytes(c.codeVersions))) sont gérées par l'app Claude elle-même : je n'y touche pas.",
                tint: Theme.brand)
    }
}

// MARK: - Intro

struct CleanupIntro: View {
    var body: some View {
        Card(padding: 24) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Prêt quand tu l'es")
                        .font(.serif(24))
                        .foregroundStyle(Theme.text)
                    Text("Lance l'analyse : je mesure chaque catégorie sans rien toucher. Ensuite, tu coches, je nettoie.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.text2)
                    VStack(alignment: .leading, spacing: 10) {
                        promise("hand.raised", "Rien n'est supprimé sans ton accord, et seulement dans ton dossier personnel.")
                        promise("trash", "Tes fichiers personnels passent toujours par la Corbeille.")
                        promise("app.badge.checkmark", "Les caches d'une app ouverte sont laissés tranquilles.")
                        promise("doc.text", "Chaque suppression est notée dans un journal lisible.")
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                PixelMascot(pixel: 7, broom: true)
                    .padding(.top, 20)
                    .padding(.trailing, 12)
            }
            Divider().padding(.vertical, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(CleanupGroup.allCases) { g in
                    HStack(alignment: .top, spacing: 10) {
                        IconBadge(symbol: g.symbol, tint: Theme.color(index: g.tint), size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                            Text(g.blurb).font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.ui(11.5, .medium)).foregroundStyle(Theme.good).frame(width: 18)
            Text(text).font(.ui(12.5)).foregroundStyle(Theme.text2)
        }
    }
}

// MARK: - Progress

struct ScanProgressCard: View {
    var title: String
    var label: String
    var progress: Double?

    var body: some View {
        Card(padding: 22) {
            HStack(spacing: 18) {
                ClaudeSpark(size: 38, spin: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.serif(20)).foregroundStyle(Theme.text)
                    Text(label.isEmpty ? " " : label)
                        .font(.ui(12))
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let progress {
                        UsageBar(fraction: progress, tint: Theme.accent, height: 6)
                            .animation(.easeOut(duration: 0.25), value: progress)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                    }
                }
                PixelMascot(pixel: 5, bob: true, broom: true)
            }
        }
    }
}

// MARK: - Groups

struct CleanupGroupPanel: View {
    @Environment(AppModel.self) private var app
    var group: CleanupGroup

    var body: some View {
        let model = app.cleanup
        let tint = Theme.color(index: group.tint)
        Card(padding: 0) { VStack(spacing: 0) {
            HStack(spacing: 12) {
                CheckBox(state: model.state(of: group)) { model.toggle(group) }
                IconBadge(symbol: group.symbol, tint: tint, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).font(.ui(14, .semibold)).foregroundStyle(Theme.text)
                    Text(group.blurb).font(.ui(11.5)).foregroundStyle(Theme.text3).lineLimit(2)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.bytes(model.size(of: group))).font(.serif(20)).foregroundStyle(Theme.text).monospacedDigit()
                    let sel = model.selectedSize(of: group)
                    Text(sel > 0 ? "\(Fmt.bytes(sel)) cochés" : "rien de coché")
                        .font(.ui(11)).foregroundStyle(sel > 0 ? Theme.good : Theme.text3)
                }
            }
            .padding(16)
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(spacing: 0) {
                ForEach(model.targets(in: group)) { t in
                    CleanupTargetRow(target: t, tint: tint)
                    if t.id != model.targets(in: group).last?.id {
                        Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 4)
        } }
    }
}

struct CleanupTargetRow: View {
    @Environment(AppModel.self) private var app
    var target: CleanupTarget
    var tint: Color
    @State private var showAll = false

    var body: some View {
        let model = app.cleanup
        let open = model.expanded.contains(target.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CheckBox(state: model.state(of: target), disabled: target.cleanable.isEmpty) { model.toggle(target) }
                Image(systemName: target.symbol)
                    .font(.ui(13))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(target.title).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                        if target.mode == .trash { Tag(text: "Corbeille", symbol: "arrow.uturn.backward", tint: Theme.text3) }
                    }
                    Text(target.explanation).font(.ui(11.5)).foregroundStyle(Theme.text3).lineLimit(2)
                }
                Spacer(minLength: 8)
                if target.needsFullDiskAccess {
                    Button("Accès complet requis") { Finder.open(Permissions.fullDiskAccessURL) }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .help("macOS protège ce dossier : accorde l'accès complet au disque à Clean My Claude")
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.bytes(target.size)).font(.ui(13, .medium)).foregroundStyle(Theme.text).monospacedDigit()
                        let locked = target.items.count - target.cleanable.count
                        if locked > 0 {
                            Label("\(locked) verrouillé\(locked > 1 ? "s" : "") (app ouverte)", systemImage: "lock")
                                .font(.ui(10.5)).foregroundStyle(Theme.warn)
                        } else {
                            Text(Fmt.plural(target.items.count, "élément", "éléments")).font(.ui(10.5)).foregroundStyle(Theme.text3)
                        }
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            if open { model.expanded.remove(target.id) } else { model.expanded.insert(target.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.ui(11, .semibold))
                            .foregroundStyle(Theme.text3)
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(open ? "Masquer le détail" : "Voir le détail")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if open {
                let items = showAll ? target.items : Array(target.items.prefix(25))
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        CleanupItemRow(item: item)
                    }
                    if target.items.count > 25 {
                        Button(showAll ? "Afficher moins" : "Afficher les \(target.items.count - 25) autres") {
                            withAnimation { showAll.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.leading, 50)
                .padding(.trailing, 16)
                .padding(.bottom, 10)
            }
        }
    }
}

struct CleanupItemRow: View {
    @Environment(AppModel.self) private var app
    var item: CleanupItem
    @State private var hovering = false

    var body: some View {
        let model = app.cleanup
        HStack(spacing: 10) {
            CheckBox(state: model.selection.contains(item.id) ? .on : .off, disabled: item.blockedReason != nil) {
                model.toggle(item)
            }
            FileIcon(path: item.path, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.ui(12)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                if let reason = item.blockedReason {
                    Label(reason, systemImage: "lock").font(.ui(10.5)).foregroundStyle(Theme.warn)
                } else if let d = item.detail {
                    Text(d).font(.ui(10.5)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if hovering {
                Button { Finder.reveal(item.path) } label: {
                    Image(systemName: "magnifyingglass").font(.ui(10.5)).foregroundStyle(Theme.text2)
                }
                .buttonStyle(.plain)
                .help("Afficher dans le Finder")
            }
            Text(Fmt.bytes(item.size)).font(.ui(11.5)).foregroundStyle(Theme.text2).monospacedDigit()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.hover.opacity(0.5) : .clear))
        .onHover { hovering = $0 }
        .help(FS.pretty(item.path))
    }
}

// MARK: - Bottom bar

struct CleanupActionBar: View {
    @Environment(AppModel.self) private var app
    @State private var confirm = false

    var body: some View {
        let model = app.cleanup
        ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.bytes(model.selectedSize)) à libérer")
                    .font(.serif(18)).foregroundStyle(Theme.text).monospacedDigit()
                Text(Fmt.plural(model.selectedCount, "élément sélectionné", "éléments sélectionnés"))
                    .font(.ui(11)).foregroundStyle(Theme.text3)
            }
            Spacer()
            Button("Sélection conseillée") { model.selectRecommended() }
                .buttonStyle(SoftButtonStyle())
            Button("Tout décocher") { model.clearSelection() }
                .buttonStyle(SoftButtonStyle())
                .disabled(model.selection.isEmpty)
            Button {
                confirm = true
            } label: {
                HStack(spacing: 6) {
                    if model.isCleaning { ProgressView().controlSize(.small).scaleEffect(0.7).tint(.white) }
                    Text(model.isCleaning ? "Nettoyage…" : "Nettoyer")
                }
            }
            .buttonStyle(SoftButtonStyle(prominent: true))
            .disabled(model.selection.isEmpty || model.isCleaning)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .confirmAction("Nettoyer \(Fmt.bytes(model.selectedSize)) ?", message: confirmMessage(model),
                       button: "Nettoyer", isPresented: $confirm) {
            Task { await model.clean() }
        }
    }

    private func confirmMessage(_ model: CleanupModel) -> String {
        var parts: [String] = []
        if model.selectedDeletesForGood { parts.append("Les caches, journaux et la Corbeille seront supprimés définitivement : les apps recréent ce dont elles ont besoin.") }
        if model.selectedNeedsTrash { parts.append("Tes fichiers personnels iront dans la Corbeille : tu pourras encore les récupérer.") }
        if Preferences.alwaysTrash { parts = ["Tout ira dans la Corbeille (réglage « Toujours passer par la Corbeille »)."] }
        return parts.joined(separator: "\n\n")
    }
}

/// The bar pinned at the bottom of a page.
struct ActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .background(Theme.bg.opacity(0.6))
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
