import SwiftUI

struct RefugePage: View {
    @Environment(AppModel.self) private var app
    static var tint: Color { Theme.warn }

    var body: some View {
        let m = app.refuge
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.refuge.symbol, title: "Le Refuge",
                     subtitle: "La maison de \(m.name). Prends soin de ton Mac : il récolte des myrtilles, grandit et raconte tout dans son carnet.",
                     tint: Self.tint, seed: 97) {
                if m.isBorn { Tag(text: "Jour \(m.day)", symbol: "sun.max", tint: Self.tint) }
            }
            if !m.isBorn {
                Card {
                    EmptyHint(text: "Il naîtra à la fin de l'accueil. Encore un peu de patience !", symbol: "house")
                }
            } else {
                if let ceremony = m.ceremony, !m.playful {
                    Card { RefugeCeremonyContent(ceremony: ceremony, compact: true) }
                }
                HStack(alignment: .top, spacing: 14) {
                    RefugeHomeCard()
                    VStack(spacing: 14) {
                        RefugeCountersCard()
                        RefugeMoodCard()
                    }
                    .frame(width: 330)
                }
                .fixedSize(horizontal: false, vertical: true)
                RefugeStagesPanel()
                HStack(alignment: .top, spacing: 14) {
                    RefugeHousePanel()
                    RefugeJournalPanel()
                        .frame(width: 400)
                }
                .fixedSize(horizontal: false, vertical: true)
                RefugeBadgesPanel()
                TileRow {
                    RefugeEarnPanel()
                    VStack(spacing: 14) {
                        Callout(symbol: "heart", title: "Il ne lui arrive jamais rien",
                                text: "Il ne tombe pas malade et ne perd rien de ce qu'il a gagné. Pas de reproche si tu t'absentes : il fait la sieste et t'attend.",
                                tint: Self.tint)
                        Callout(symbol: "lock", title: "Tout reste sur ce Mac",
                                text: "Ses myrtilles, son carnet et ses insignes sont rangés dans les données de l'app, nulle part ailleurs.",
                                tint: Self.tint)
                        RefugeSoberCard()
                    }
                }
            }
        }
        .onAppear { m.observe() }
    }
}

/// No action bar: everything happens on the page.
struct RefugeBottomBar: View {
    var body: some View { EmptyView() }
}

// MARK: - The room and its name

private struct RefugeHomeCard: View {
    @Environment(AppModel.self) private var app
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        let m = app.refuge
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                RefugeRoomView()
                    .aspectRatio(CGFloat(RefugeScene.cols) / CGFloat(RefugeScene.rows), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.r(14), topTrailingRadius: Theme.r(14), style: .continuous))
                    .overlay(alignment: .topLeading) { bubble(m.line()) }
                HStack(alignment: .center, spacing: 12) {
                    if editing && !Snapshot.isActive {
                        TextField("Son prénom", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.serif(22))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Theme.bg))
                            .overlay(RoundedRectangle(cornerRadius: Theme.r(8)).strokeBorder(Theme.borderStrong, lineWidth: max(1, Theme.line)))
                            .onSubmit(save)
                            .frame(maxWidth: 280)
                        Button("Garder", action: save).buttonStyle(SoftButtonStyle(prominent: true, small: true))
                        Button("Annuler") { editing = false }.buttonStyle(SoftButtonStyle(small: true))
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.name).font(.serif(24)).foregroundStyle(Theme.text)
                            Text("\(m.stage.title) · \(m.stage.change)").font(.ui(12)).foregroundStyle(Theme.text3)
                        }
                        Button {
                            draft = m.name
                            editing = true
                        } label: {
                            Label("Changer son prénom", systemImage: "pencil").labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .help("Tu peux le renommer quand tu veux")
                    }
                    Spacer()
                    Text("Clique sur lui pour une caresse").font(.ui(11)).foregroundStyle(Theme.text3)
                }
                .padding(16)
            }
        }
        .task(id: m.reaction) {
            // A reaction stays a few seconds, then it goes back to saying how it feels.
            guard m.reaction != nil else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { m.reaction = nil }
        }
    }

    private func save() {
        app.refuge.rename(draft)
        editing = false
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .font(.ui(12.5, .medium))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous).strokeBorder(Theme.border, lineWidth: Theme.line))
            .themedShadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .padding(14)
            .allowsHitTesting(false)
    }
}

// MARK: - The two counters

private struct RefugeCountersCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.refuge.state
        let p = RefugeRules.progress(s.harvested)
        Card {
            HStack(alignment: .top, spacing: 16) {
                counter(value: s.harvested, title: "Récoltées", detail: "Depuis sa naissance. Ne baisse jamais : c'est ce qui le fait grandir.")
                counter(value: s.basket, title: "Le panier", detail: "Ce qu'il peut dépenser. La boutique ouvre bientôt.")
            }
            VStack(alignment: .leading, spacing: 7) {
                if let next = p.next {
                    HStack {
                        Text("Prochain stade : \(next.title)").font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("encore \(Fmt.int(p.left))").font(.ui(11.5)).foregroundStyle(Theme.text3)
                    }
                    UsageBar(fraction: p.fraction, tint: RefugePage.tint, height: 8)
                    Text("Il y gagnera \(next.change).").font(.ui(11.5)).foregroundStyle(Theme.text3)
                } else {
                    Text("Il a atteint le dernier stade. Bravo à vous deux !").font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                }
            }
        }
    }

    private func counter(value: Int, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RefugeBerry(size: 12)
                Text(title).font(.ui(12)).foregroundStyle(Theme.text2)
            }
            Text(Fmt.int(value)).font(.serif(30)).foregroundStyle(Theme.text).contentTransition(.numericText())
            Text(detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A blueberry, in pixels: the currency of the Refuge.
struct RefugeBerry: View {
    var size: CGFloat = 12

    var body: some View {
        Canvas { ctx, s in
            let p = s.width / 5
            let rows = [".gg..", "bbbb.", "bBbbb", "bbbbb", ".bbb."]
            let colors: [Character: Color] = ["g": Theme.good, "b": Theme.mascot.night, "B": Theme.mascot.glassShine]
            for (y, line) in rows.enumerated() {
                for (x, ch) in line.enumerated() {
                    if let c = colors[ch] { ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: p, height: p)), with: .color(c)) }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Its mood

private struct RefugeMoodCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.refuge
        let look = m.scene()
        let s = m.signals()
        Card {
            HStack(spacing: 8) {
                IconBadge(symbol: symbol(look.mood), tint: RefugePage.tint)
                Text("Humeur : \(look.mood.title.lowercased())").font(.ui(13, .semibold)).foregroundStyle(Theme.text)
            }
            VStack(alignment: .leading, spacing: 6) {
                row("Moutons de poussière", look.dust == 0 ? "aucun" : "\(look.dust)", detail: s.junk > 0 ? Fmt.bytes(s.junk) : nil, page: .cleanup)
                row("Mites", look.moths == 0 ? "aucune" : "\(look.moths)", detail: nil, page: .protection)
                row("Boost", s.boost ? "actif" : "au repos", detail: nil, page: .performance)
            }
        }
    }

    private func symbol(_ mood: RefugeMood) -> String {
        switch mood {
        case .happy: return "face.smiling"
        case .sleepy: return "moon.zzz"
        case .sneezy: return "wind"
        case .hot: return "thermometer.sun"
        case .boosted: return "bolt"
        case .worried: return "ant"
        }
    }

    private func row(_ title: String, _ value: String, detail: String?, page: Page) -> some View {
        Button { app.page = page } label: {
            HStack {
                Text(title).font(.ui(12)).foregroundStyle(Theme.text2)
                Spacer()
                if let detail { Text(detail).font(.ui(11)).foregroundStyle(Theme.text3) }
                Text(value).font(.ui(12, .semibold)).foregroundStyle(Theme.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvrir \(page.title)")
    }
}

// MARK: - The six stages

private struct RefugeStagesPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.refuge.state
        Panel(title: "Il grandit", subtitle: "Six stades où il change vraiment, selon les myrtilles récoltées depuis sa naissance.",
              symbol: "chart.line.uptrend.xyaxis", tint: RefugePage.tint) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(RefugeStage.allCases, id: \.rawValue) { stage in
                    let reached = s.harvested >= stage.threshold
                    let current = s.stage == stage
                    VStack(spacing: 6) {
                        RefugeAvatar(stage: stage, pixel: 5, animated: false)
                            .opacity(reached ? 1 : 0.28)
                            .saturation(reached ? 1 : 0)
                        Text(stage.title).font(.ui(12, current ? .semibold : .regular)).foregroundStyle(current ? Theme.text : Theme.text2)
                        Text(stage.threshold == 0 ? "le premier jour" : "\(Fmt.int(stage.threshold)) myrtilles")
                            .font(.ui(10.5)).foregroundStyle(Theme.text3)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(current ? RefugePage.tint.opacity(0.12) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(current ? RefugePage.tint.opacity(0.4) : .clear, lineWidth: max(1, Theme.line)))
                }
            }
        }
    }
}

// MARK: - The house

private struct RefugeHousePanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let lit = Set(RefugeRules.discovered(app.refuge.state).map(\.page))
        Panel(title: "Le plan de la maison", subtitle: "Chaque outil est une pièce. Elle s'allume la première fois que tu y entres (+10 myrtilles).",
              symbol: "map", tint: RefugePage.tint) {
            Text("\(lit.count) pièces sur \(RefugeRules.rooms.count)").font(.ui(11.5, .medium)).foregroundStyle(Theme.text3)
        } content: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(RefugeRules.rooms) { room in
                    let on = lit.contains(room.page)
                    Button { app.page = room.page } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if Theme.icons != .hidden {
                                    Image(systemName: on ? room.page.symbol : "questionmark")
                                        .font(.ui(11, .semibold))
                                        .foregroundStyle(on ? RefugePage.tint : Theme.text3)
                                }
                                Text(room.name).font(.ui(11.5, .semibold)).foregroundStyle(on ? Theme.text : Theme.text3).lineLimit(1)
                            }
                            Text(on ? room.page.title : "Pas encore visitée").font(.ui(10.5)).foregroundStyle(Theme.text3).lineLimit(1)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(on ? RefugePage.tint.opacity(0.1) : Theme.track.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(9)).strokeBorder(on ? RefugePage.tint.opacity(0.3) : Theme.border,
                                                                                    lineWidth: max(1, Theme.line)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(on ? "Aller à \(room.page.title)" : "Découvrir \(room.page.title) : \(room.page.pitch)")
                }
            }
        }
    }
}

// MARK: - Its notebook

private struct RefugeJournalPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.refuge.state
        Panel(title: "Le carnet de \(s.name)", subtitle: "Ce qu'il a vécu, écrit de sa main.", symbol: "book", tint: RefugePage.tint) {
            if s.journal.isEmpty {
                EmptyHint(text: "Son carnet est encore vide.", symbol: "book")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(s.journal.suffix(9).reversed()) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Jour \(RefugeRules.dayNumber(s, now: e.date))")
                                .font(.ui(10.5, .semibold)).foregroundStyle(Theme.text3)
                                .frame(width: 52, alignment: .leading)
                            Text(e.count > 1 ? "\(e.text) (\(e.count) fois)" : e.text)
                                .font(.ui(12)).foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            if e.amount > 0 {
                                Text("+\(e.amount)").font(.ui(11, .semibold)).foregroundStyle(RefugePage.tint)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Badges

private struct RefugeBadgesPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.refuge.state
        let won = RefugeRules.badges.filter { s.badges[$0.id] != nil }.count
        Panel(title: "Ses insignes", subtitle: "Les bons gestes, la régularité et la curiosité. Deux sont secrets.", symbol: "rosette", tint: RefugePage.tint) {
            Text("\(won) sur \(RefugeRules.badges.count)").font(.ui(11.5, .medium)).foregroundStyle(Theme.text3)
        } content: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(RefugeRules.badges) { b in
                    let date = s.badges[b.id]
                    let hidden = b.secret && date == nil
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(date == nil ? Theme.track : metal(b.metal).opacity(0.22))
                            Circle().strokeBorder(date == nil ? Theme.border : metal(b.metal), lineWidth: 2)
                            Image(systemName: hidden ? "questionmark" : b.symbol)
                                .font(.ui(15, .semibold))
                                .foregroundStyle(date == nil ? Theme.text3 : metal(b.metal))
                        }
                        .frame(width: 44, height: 44)
                        Text(hidden ? "Secret" : b.title).font(.ui(11, .semibold)).foregroundStyle(date == nil ? Theme.text3 : Theme.text)
                            .multilineTextAlignment(.center).lineLimit(2)
                        Text(hidden ? "À toi de le trouver" : (date.map { "le \(Fmt.day($0))" } ?? b.detail))
                            .font(.ui(10)).foregroundStyle(Theme.text3).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .help(hidden ? "Un insigne secret" : b.detail)
                }
            }
        }
    }

    private func metal(_ m: RefugeMetal) -> Color {
        switch m {
        case .bronze: return Theme.mascot.bronze
        case .silver: return Theme.mascot.silver
        case .gold: return Theme.mascot.goldFurShade
        }
    }
}

// MARK: - How to earn

private struct RefugeEarnPanel: View {
    var body: some View {
        Panel(title: "Gagner des myrtilles", subtitle: "En prenant soin du Mac. Jamais selon ce que tu supprimes : on ne pousse personne à effacer pour grandir.",
              symbol: "leaf", tint: RefugePage.tint) {
            VStack(spacing: 7) {
                ForEach(RefugeSource.allCases.filter { $0 != .welcome }, id: \.rawValue) { src in
                    HStack(spacing: 10) {
                        if Theme.icons != .hidden {
                            Image(systemName: src.symbol).font(.ui(11, .medium)).foregroundStyle(Theme.text3).frame(width: 16)
                        }
                        Text(src.what).font(.ui(12)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(src.limit).font(.ui(11)).foregroundStyle(Theme.text3)
                        Text("+\(src.amount)").font(.ui(12, .semibold)).foregroundStyle(RefugePage.tint).frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Sober mode

private struct RefugeSoberCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.refuge
        Card {
            Toggle(isOn: Binding(get: { m.state.sober }, set: { m.setSober($0) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mode sobre").font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                    Text("Ni moment de mue, ni message : l'app sans le jeu. Le Refuge quitte la barre latérale, \(m.name) continue de grandir en silence.")
                        .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .switchToggles()
        }
    }
}
