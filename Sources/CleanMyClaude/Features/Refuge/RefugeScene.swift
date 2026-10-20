import SwiftUI

/// Its room, in pixels: a wooden wall, a window on the mountains (stars at night), the shelf of its badges, its bed of
/// straw, the lamp, and what the Mac puts in it: dust bunnies for the junk, moths for the threats.
struct RefugeScene {
    static let cols = 64
    static let rows = 24
    /// Where its box stands: its feet on the floor, in the middle of the room.
    static let figure = (x: 20, y: 3)

    var stage: RefugeStage
    var mood: RefugeMood
    var frame: Int
    var night: Bool
    var dust: Int
    var moths: Int
    var trophies: [RefugeMetal]
    var lift = 0

    private static let bunnies = [(1, 18), (11, 19), (36, 18), (56, 19), (46, 18)]
    private static let mothSpots = [(36, 11), (12, 14), (39, 1)]

    /// The pixel size that fits the room in `size`, on whole half-points.
    static func pixel(fitting size: CGSize) -> CGFloat {
        max(1, (min(size.width / CGFloat(cols), size.height / CGFloat(rows)) * 2).rounded(.down) / 2)
    }

    func draw(in ctx: GraphicsContext, size: CGSize) {
        let p = Self.pixel(fitting: size)
        let ox = ((size.width - p * CGFloat(Self.cols)) / 2).rounded()
        let oy = ((size.height - p * CGFloat(Self.rows)) / 2).rounded()
        func fill(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: Color) {
            ctx.fill(Path(CGRect(x: ox + CGFloat(x) * p, y: oy + CGFloat(y) * p, width: CGFloat(w) * p, height: CGFloat(h) * p)),
                     with: .color(color))
        }
        func sprite(_ rows: [String], _ x: Int, _ y: Int, _ colors: [Character: Color]) {
            for (dy, line) in rows.enumerated() {
                for (dx, ch) in line.enumerated() { if let c = colors[ch] { fill(x + dx, y + dy, 1, 1, c) } }
            }
        }
        let c = Theme.mascot

        // The wall of planks and the wooden floor.
        fill(0, 0, Self.cols, 18, Theme.track)
        for x in stride(from: 4, to: Self.cols, by: 8) { fill(x, 0, 1, 18, Theme.border) }
        fill(0, 18, Self.cols, 6, c.wood)
        fill(0, 18, Self.cols, 1, c.woodShade)
        for (i, y) in [20, 22].enumerated() {
            for x in stride(from: 3 + i * 6, to: Self.cols, by: 12) { fill(x, y, 2, 1, c.woodShade) }
        }

        // The window on the mountains.
        fill(5, 3, 14, 10, c.woodShade)
        fill(6, 4, 12, 8, night ? c.night : c.sky)
        if night {
            fill(15, 5, 2, 2, c.star)
            for (i, s) in [(7, 5), (10, 4), (12, 6), (8, 7)].enumerated() where (frame / 3 + i) % 4 != 0 {
                fill(s.0, s.1, 1, 1, c.star.opacity(0.85))
            }
        } else {
            fill(7, 5, 3, 1, c.snow)
            fill(8, 4, 1, 1, c.snow)
        }
        for x in 6...17 {
            let h = max(0, 4 - abs(x - 9), 5 - abs(x - 14))
            guard h > 0 else { continue }
            fill(x, 12 - h, 1, h, c.mountain)
            if h >= 3 { fill(x, 12 - h, 1, 1, c.snow) }
        }
        fill(11, 4, 1, 8, c.woodShade)
        fill(6, 7, 12, 1, c.woodShade)
        fill(4, 13, 16, 1, c.wood)

        // The shelf, its badges standing on it, an empty place for each one still to win.
        fill(38, 9, 25, 1, c.wood)
        fill(39, 10, 1, 1, c.woodShade)
        fill(61, 10, 1, 1, c.woodShade)
        for i in 0..<RefugeRules.badges.count {
            let x = 39 + i * 2
            guard i < trophies.count else { fill(x, 8, 1, 1, Theme.border); continue }
            let (main, light): (Color, Color) = switch trophies[i] {
            case .bronze: (c.bronze, c.bronzeLight)
            case .silver: (c.silver, c.silverLight)
            case .gold: (c.goldFurShade, c.goldRing)
            }
            fill(x, 7, 1, 1, light)
            fill(x, 8, 1, 1, main)
        }

        // Its bed of straw, a soft heap with a few strands sticking out.
        sprite(["....s...s.s....",
                "..SsssSsssssS..",
                ".sssSsssssSsss.",
                "SSSSSSSSSSSSSSS"], 44, 17, ["s": c.straw, "S": c.strawShade])

        // The dust bunnies under the furniture, wiggling a little.
        for (i, spot) in Self.bunnies.prefix(dust).enumerated() {
            let shift = ((frame + i * 3) / 4) % 2
            sprite(["..d.d..", ".ddddd.", "ddededd", "ddddddd", ".DDDDD."], spot.0 + shift, spot.1, ["d": c.dust, "D": c.dustShade, "e": c.eye])
        }

        // The night dims the room; the lamp stays lit.
        if night { fill(0, 0, Self.cols, Self.rows, Color.black.opacity(0.22)) }
        fill(47, 0, 1, 2, Theme.text3)
        fill(46, 2, 3, 1, c.woodShade)
        fill(47, 3, 1, 1, c.star)

        // The chamois.
        let blink = frame % 18 == 17
        RefugeFigure.draw(in: ctx, at: CGPoint(x: ox + CGFloat(Self.figure.x) * p, y: oy + CGFloat(Self.figure.y) * p), pixel: p,
                          stage: stage, mood: mood, frame: frame, blink: blink, lift: lift)

        // The moths, fluttering around.
        for (i, spot) in Self.mothSpots.prefix(moths).enumerated() {
            let orbit = [(0, 0), (1, -1), (2, 0), (1, 1)][(frame + i) % 4]
            let up = (frame + i) % 2 == 0
            sprite(up ? ["..b.b..", "ww.b.ww", "wwebeww", ".w.b.w."] : ["..b.b..", "...b...", "wwebeww", "ww.b.ww"],
                   spot.0 + orbit.0, spot.1 + orbit.1, ["w": c.mothWing, "b": c.moth, "e": c.sparkle])
        }

        // Its dreams.
        if mood == .sleepy {
            for k in 0..<2 {
                let phase = (frame + k * 6) % 12
                let alpha = 1 - Double(phase) / 12
                // Above its head, clear of the horns and the shelf.
                let x = k == 0 ? 34 + phase / 6 : 38 + phase / 6
                let y = k == 0 ? 4 - phase / 4 : 2 - phase / 6
                sprite(["####", "..#.", ".#..", "####"], x, y, ["#": Theme.text2.opacity(alpha)])
            }
        }
    }
}

/// The room on the page, alive a few times a second while it is on screen; a click is a caress.
struct RefugeRoomView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true
    @State private var lift = 0

    private static let epoch = Date(timeIntervalSinceReferenceDate: 0)
    private static let step = 0.25

    var body: some View {
        Group {
            if Snapshot.isActive || reduceMotion || !onScreen {
                room(frame: 4, date: Date())
            } else {
                TimelineView(.periodic(from: Self.epoch, by: Self.step)) { context in
                    room(frame: Int(context.date.timeIntervalSince(Self.epoch) / Self.step), date: context.date)
                }
            }
        }
        .background { if !Snapshot.isActive { MascotWindowProbe(onScreen: $onScreen) } }
        .contentShape(Rectangle())
        .onTapGesture {
            app.refuge.pet()
            lift = 1
            Task {
                try? await Task.sleep(nanoseconds: 180_000_000)
                lift = 0
            }
        }
        .accessibilityElement()
        .accessibilityLabel("La pièce de \(app.refuge.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Une caresse")
    }

    private func room(frame: Int, date: Date) -> some View {
        let m = app.refuge
        let look = m.scene(now: date)
        let scene = RefugeScene(stage: m.stage, mood: look.mood, frame: frame, night: look.night, dust: look.dust, moths: look.moths,
                                trophies: m.trophies, lift: lift)
        return Canvas { ctx, size in scene.draw(in: ctx, size: size) }
    }
}
