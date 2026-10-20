import SwiftUI

// Its daily life, drawn: the trail of its round, the wall where it grows, its scarves on a line, its path.

// MARK: - The trail of the daily round

/// A little trail with three flags (today's missions) and a basket of blueberries at the end; the chamois walks along it.
struct RefugeRoundTrail: View {
    @Environment(AppModel.self) private var app
    private static let fractions: [CGFloat] = [0.2, 0.47, 0.74]

    var body: some View {
        let m = app.refuge
        let tasks = m.roundTasks
        let done = tasks.filter(\.done).count
        let finished = !tasks.isEmpty && done == tasks.count
        VStack(alignment: .leading, spacing: 10) {
            RefugeSectionTitle(title: "Sa tournée du jour",
                               subtitle: "Trois petites missions tirées de ton Mac. Toutes faites : +10 myrtilles et une petite danse.") {
                if finished { Tag(text: "Finie : +10 dans ton panier", symbol: "checkmark", tint: Theme.good, filled: true) }
                else if !tasks.isEmpty { Text("\(done) sur \(tasks.count)").font(.ui(12, .semibold)).foregroundStyle(Theme.text3) }
            }
            if tasks.isEmpty {
                Text("Sa tournée arrive avec ton premier passage de la journée.").font(.ui(12.5)).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, size in drawTrail(ctx, size: size, done: done, finished: finished) }
                        // The flags.
                        ForEach(Array(tasks.enumerated()), id: \.offset) { i, t in
                            let x = w * Self.fractions[i]
                            Image(systemName: t.done ? "flag.fill" : "flag")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(t.done ? Theme.good : Theme.text3)
                                .position(x: x + 8, y: Self.trailY(x / w) - 14)
                            mission(t.task, done: t.done)
                                .frame(width: min(230, w * 0.26))
                                .position(x: x, y: 104)
                        }
                        // The basket at the end.
                        VStack(spacing: 2) {
                            RefugeBasketIcon(count: finished ? 60 : 12, pixel: 3)
                            Text(finished ? "+10 reçues" : "+10").font(.ui(12, .bold)).foregroundStyle(finished ? Theme.good : RefugePage.tint)
                        }
                        .position(x: w - 40, y: Self.trailY(1) - 6)
                        // The chamois, on its way to the next flag (or dancing by the basket).
                        let at: CGFloat = finished ? w - 86 : (done == 0 ? 6 : w * Self.fractions[done - 1] + 22)
                        RefugeAvatar(look: m.look(), pixel: 2.5)
                            .offset(y: finished && m.dancing(now: Date()) ? -4 : 0)
                            .position(x: at + 20, y: Self.trailY(min(1, at / max(1, w))) - 22)
                    }
                }
                .frame(height: 136)
            }
        }
    }

    /// The trail's height at a point along it (0…1), in points.
    private static func trailY(_ f: CGFloat) -> CGFloat { 52 + 9 * sin(f * .pi * 3) }

    private func drawTrail(_ ctx: GraphicsContext, size: CGSize, done: Int, finished: Bool) {
        var x: CGFloat = 8
        let end = size.width - 60
        while x < end {
            let f = x / size.width
            let reached = finished || f <= (done == 0 ? 0 : Self.fractions[done - 1])
            ctx.fill(Path(roundedRect: CGRect(x: x, y: Self.trailY(f) + 2, width: 7, height: 4), cornerRadius: 2),
                     with: .color(reached ? RefugePage.tint.opacity(0.8) : Theme.borderStrong))
            x += 13
        }
        // A few tufts of grass beside the trail.
        for (i, f) in stride(from: 0.08, to: 0.95, by: 0.11).enumerated() {
            let gx = size.width * f, gy = Self.trailY(f) + (i % 2 == 0 ? 14 : -10)
            for dx in [-3.0, 0, 3] {
                ctx.fill(Path(CGRect(x: gx + dx, y: gy - abs(dx), width: 2, height: 5 + abs(dx) / 2)), with: .color(Theme.mascot.leaf.opacity(0.55)))
            }
        }
    }

    private func mission(_ task: RefugeTask, done: Bool) -> some View {
        VStack(spacing: 5) {
            Text(task.title).font(.ui(12, .semibold)).foregroundStyle(done ? Theme.text3 : Theme.text)
                .strikethrough(done, color: Theme.text3)
                .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if done {
                Text("Fait").font(.ui(11, .medium)).foregroundStyle(Theme.good)
            } else if let page = task.page {
                Button(page == .refuge ? "Son panier" : "Y aller") { app.page = page }
                    .buttonStyle(SoftButtonStyle(small: true))
            }
        }
    }
}

// MARK: - The growth wall

/// Its six stages side by side against the wall, like the height marks of a child: the ones it reached in color with the
/// day of their mue, the next one as a shadow with what is left to eat, the others as shadows.
struct RefugeGrowthWall: View {
    @Environment(AppModel.self) private var app
    private static let pixel: CGFloat = 6

    var body: some View {
        let m = app.refuge
        let s = m.state
        VStack(alignment: .leading, spacing: 12) {
            RefugeSectionTitle(title: "Il grandit", subtitle: "Six stades où il change vraiment. Les traits au mur gardent le jour de chaque mue.")
            ZStack(alignment: .bottom) {
                // The wall and its floor.
                RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).fill(Theme.track)
                Canvas { ctx, size in
                    for x in stride(from: 0, to: size.width, by: 64) {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height - 34)), with: .color(Theme.border))
                    }
                    ctx.fill(Path(CGRect(x: 0, y: size.height - 34, width: size.width, height: 34)), with: .color(Theme.mascot.wood))
                    ctx.fill(Path(CGRect(x: 0, y: size.height - 34, width: size.width, height: 3)), with: .color(Theme.mascot.woodShade))
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(RefugeStage.allCases, id: \.rawValue) { stage in
                        column(stage, s: s, m: m)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 236)
            HStack(alignment: .top, spacing: 14) {
                RefugeScarfLine()
                RefugePathCard()
                    .frame(width: 400)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func column(_ stage: RefugeStage, s: RefugeState, m: RefugeModel) -> some View {
        let reached = s.stage >= stage
        let current = s.stage == stage
        let next = s.stage.next == stage
        var look = m.look()
        look.stage = stage
        look.scarf = stage == .grand ? .bronze : (stage == .gold ? .laine : nil)
        if !current { look.head = nil; look.face = nil; look.path = stage >= .beau ? look.path : nil }
        let body = RefugeFigure.pixels(look).body
        let headTop = body.map(\.y).min() ?? 0
        let leftEdge = body.map(\.x).min() ?? 0
        let p = Self.pixel
        let c = Theme.mascot
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if current {
                    Circle().fill(RefugePage.tint.opacity(0.2)).frame(width: 110, height: 110).blur(radius: 18)
                        .offset(x: -14, y: -10)
                }
                Canvas { ctx, _ in
                    RefugeFigure.draw(in: ctx, pixel: p, look: look, ink: reached ? nil : Theme.text3.opacity(next ? 0.45 : 0.22))
                }
                .frame(width: p * CGFloat(RefugeFigure.cols), height: p * CGFloat(RefugeFigure.rows))
                if reached {
                    // The pencil mark at the height of its head, the day written beside it, on its left.
                    HStack(spacing: 3) {
                        Text(day(stage, s: s, m: m)).font(.ui(9.5, .semibold)).foregroundStyle(Theme.text2)
                        Rectangle().fill(Theme.text2).frame(width: 14, height: 2)
                    }
                    .fixedSize()
                    .frame(width: 70, alignment: .trailing)
                    .offset(x: CGFloat(leftEdge) * p - 72, y: CGFloat(headTop) * p - 6)
                }
            }
            .frame(height: p * CGFloat(RefugeFigure.rows) + 12, alignment: .bottom)
            // Written on the floorboards, in chalk.
            VStack(spacing: 2) {
                Text(stage.title).font(.ui(12, current ? .bold : .medium)).foregroundStyle(c.face.opacity(reached ? 1 : 0.6))
                if next {
                    Text("encore \(Fmt.int(max(0, stage.threshold - s.eaten)))").font(.ui(10.5, .semibold)).foregroundStyle(c.star)
                } else {
                    Text(stage.threshold == 0 ? "le premier jour" : "\(Fmt.int(stage.threshold)) mangées").font(.ui(10.5)).foregroundStyle(c.face.opacity(0.6))
                }
            }
            .padding(.top, 8)
            .frame(height: 40, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .help(reached ? "\(stage.title) : \(stage.change)" : "\(stage.title), à \(Fmt.int(stage.threshold)) myrtilles mangées : \(stage.change)")
    }

    /// The day of a stage's mue, read in its notebook.
    private func day(_ stage: RefugeStage, s: RefugeState, m: RefugeModel) -> String {
        if stage == .cabri { return "jour 1" }
        if let e = s.journal.first(where: { $0.kind == "mue" && $0.text.contains("me voilà \(stage.title) !") }) {
            return "jour \(RefugeRules.dayNumber(s, now: e.date))"
        }
        return "✓"
    }
}

// MARK: - The scarves on a line

/// The eight scarves hung on a line by clothes pegs: the ones it won in their material, the others as outlines. The
/// Chamois d'or picks the one it wears.
private struct RefugeScarfLine: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.refuge
        let s = m.state
        let won = s.stage >= .grand ? RefugeScarf.won(level: s.level) : []
        let worn = m.look().scarf
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ses écharpes").font(.serif(17)).foregroundStyle(Theme.text)
                Text(s.stage == .gold ? "Chamois d'or : choisis celle qu'il porte." : "Une nouvelle matière tous les 1 200 myrtilles mangées, dès le Grand Chamois.")
                    .font(.ui(11.5)).foregroundStyle(Theme.text3)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // The line, sagging a little.
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 8))
                        p.addQuadCurve(to: CGPoint(x: w, y: 8), control: CGPoint(x: w / 2, y: 26))
                    }
                    .stroke(Theme.text3.opacity(0.6), lineWidth: 1.5)
                    ForEach(RefugeScarf.allCases, id: \.rawValue) { scarf in
                        let f = (CGFloat(scarf.rawValue) + 0.5) / CGFloat(RefugeScarf.allCases.count)
                        let sag = 8 + 18 * 4 * f * (1 - f) * 0.5
                        Button {
                            if s.stage == .gold { m.chooseScarf(scarf) }
                        } label: {
                            VStack(spacing: 4) {
                                RefugeScarfIcon(scarf: scarf, won: won.contains(scarf), worn: worn == scarf && s.stage >= .grand)
                                Text(scarf.title).font(.ui(10, .semibold)).foregroundStyle(won.contains(scarf) ? Theme.text : Theme.text3)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                Text(won.contains(scarf) ? (worn == scarf && s.stage >= .grand ? "portée" : "gagnée") : Fmt.int(scarf.threshold))
                                    .font(.ui(9.5)).foregroundStyle(Theme.text3)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(s.stage != .gold || !won.contains(scarf))
                        .help(won.contains(scarf) ? "Écharpe \(scarf.title.lowercased())" : "À \(Fmt.int(scarf.threshold)) myrtilles mangées")
                        .position(x: w * f, y: sag + 34)
                    }
                }
            }
            .frame(height: 96)
        }
    }
}

/// A scarf hung by a peg, two tails and a fringe.
struct RefugeScarfIcon: View {
    var scarf: RefugeScarf
    var won: Bool
    var worn = false

    var body: some View {
        Canvas { ctx, _ in
            let p: CGFloat = 4
            let colors = Theme.mascot.scarves[scarf.rawValue]
            let rows = ["..k..k..", "SsSSsSSs", ".SsSSsS.", ".S....S.", ".s....s.", ".S....S."]
            for (y, line) in rows.enumerated() {
                for (x, ch) in line.enumerated() {
                    let color: Color? = switch ch {
                    case "k": Theme.mascot.wood
                    case "S": won ? colors.main : Theme.borderStrong
                    case "s": won ? (scarf == .laine ? Theme.mascot.goldThread : colors.light) : Theme.border
                    default: nil
                    }
                    if let color { ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: p, height: p)), with: .color(color)) }
                }
            }
            if worn { ctx.fill(Path(CGRect(x: 7 * p, y: 0, width: p, height: p)), with: .color(Theme.mascot.star)) }
        }
        .frame(width: 32, height: 24)
    }
}

// MARK: - Its path

/// The four paths, each chamois with its accessory: the one it took stands out.
private struct RefugePathCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.refuge
        let s = m.state
        let chosen = s.path.flatMap(RefugePath.init(rawValue:))
        let open = s.stage >= .beau
        let canChange = open && RefugeStyle.canChangePath(s, on: m.clock)
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(open ? "Sa voie : \(chosen?.title ?? "…")" : "Sa voie").font(.serif(17)).foregroundStyle(Theme.text)
                Text(open ? (canChange ? "Il peut en changer une fois cette saison : clique sur une autre." : "Il garde sa voie jusqu'à la saison prochaine.")
                     : "Au stade Beau Chamois, il choisira selon les outils que tu utilises le plus.")
                    .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(RefugePath.allCases, id: \.rawValue) { path in
                    let mine = path == chosen
                    Button { m.changePath(path) } label: {
                        VStack(spacing: 3) {
                            Canvas { ctx, _ in
                                var look = RefugeLook(stage: .beau, coat: m.look().coat, path: path)
                                look.head = nil
                                RefugeFigure.draw(in: ctx, pixel: 3.5, look: look, ink: open ? nil : Theme.text3.opacity(0.3))
                            }
                            .frame(width: 3.5 * CGFloat(RefugeFigure.cols), height: 3.5 * CGFloat(RefugeFigure.rows))
                            .opacity(open && !mine ? 0.55 : 1)
                            Text(path.title).font(.ui(10.5, mine ? .bold : .medium)).foregroundStyle(mine ? Theme.text : Theme.text3)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(mine ? RefugePage.tint.opacity(0.14) : .clear))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChange || mine)
                    .help("\(path.title) : \(path.accessory). \(path.who)")
                }
            }
        }
    }
}
