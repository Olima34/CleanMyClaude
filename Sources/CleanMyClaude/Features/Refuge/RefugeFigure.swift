import SwiftUI

/// The chamois of the Refuge at each of its six stages (the drawings of the universe's notebook), and what its moods do
/// to its face: closed eyes when it sleeps, screwed up when it sneezes, its tongue out when it is hot, its racing glasses
/// during the Boost, its eyes raised to the moth. Every stage fits in a 17 × 17 box, its feet on the bottom row.
enum RefugeFigure {
    static let cols = 17
    static let rows = 17

    enum Part {
        case horn, hornRing, fur, furShade, mask, face, collar, eye, nose, cheek, hoof, bell, bellShade
        case scarf, scarfLight, sparkle, glasses, glassShine, sweat, tongue
    }

    struct Pixel {
        var x: Int
        var y: Int
        var part: Part
        var alpha: Double = 1
    }

    // n = horn, N = its ring, f = fur, F = darker fur, m = mask, w = face, W = collar, e = eye, p = nose, c = cheek,
    // k = hoof, g / G = the bell.
    private static let codes: [Character: Part] = [
        "n": .horn, "N": .hornRing, "f": .fur, "F": .furShade, "m": .mask, "w": .face, "W": .collar, "e": .eye,
        "p": .nose, "c": .cheek, "k": .hoof, "g": .bell, "G": .bellShade,
    ]

    static func grid(_ stage: RefugeStage) -> [String] {
        switch stage {
        case .cabri:
            // A round baby: no horns yet, big ears, thin legs.
            return ["ff.......ff",
                    ".fFwwwwwFf.",
                    "..fmwwwmf..",
                    "..fewwwef..",
                    "..fewwwef..",
                    "..fcwpwcf..",
                    "...fwwwf...",
                    "...fffff...",
                    "...f...f...",
                    "...k...k..."]
        case .eterlou:
            // One year old: two little straight horns.
            return ["....n...n....",
                    "ff..n...n..ff",
                    ".fFfwwwwwfFf.",
                    "..fmwwwwwmf..",
                    "..fmewwwemf..",
                    "..fmewwwemf..",
                    "...fcwpwcf...",
                    "....fwwwf....",
                    "....fffff....",
                    "...ffwwwff...",
                    "...ff...ff...",
                    "...kk...kk..."]
        case .chamois:
            // The hooked horns of the grown-ups.
            return ["..nn.....nn..",
                    "....n...n....",
                    "ff..n...n..ff",
                    ".fFfwwwwwfFf.",
                    "..fmwwwwwmf..",
                    "..fmewwwemf..",
                    "..fmewwwemf..",
                    "...fcwpwcf...",
                    "....fwwwf....",
                    "....fffff....",
                    "...ffwwwff...",
                    "...ff...ff...",
                    "...kk...kk..."]
        case .beau:
            // A little taller, a bell at its neck.
            return [".nn.......nn.",
                    "...n.....n...",
                    "....n...n....",
                    "ff..n...n..ff",
                    ".fFfwwwwwfFf.",
                    "..fmwwwwwmf..",
                    "..fmewwwemf..",
                    "..fmewwwemf..",
                    "...fcwpwcf...",
                    "....fwwwf....",
                    "....ffgff....",
                    "...ffwGwff...",
                    "...ffwwwff...",
                    "...ff...ff...",
                    "...kk...kk..."]
        case .grand, .gold:
            // Long ringed horns, a tuft, a collar, broader; the scarf goes on top.
            return ["nn.........nn",
                    "..n.......n..",
                    "...N.....N...",
                    "...n.FFF.n...",
                    "fff.nFFFn.fff",
                    ".ffFwwwwwFff.",
                    ".ffmwwwwwmff.",
                    "..fmewwwemf..",
                    "..fmewwwemf..",
                    "..ffcwpwcff..",
                    "..WfwwwwwfW..",
                    ".WWWwwwwwWWW.",
                    "..ffwwwwwff..",
                    "..fff...fff..",
                    "..kkk...kkk.."]
        }
    }

    /// The scarf of the Grand Chamois, in the coordinates of its grid: around the neck, the knot, the end that hangs.
    private static func scarf(sparkle: Bool) -> [Pixel] {
        var px: [Pixel] = []
        for x in 2...10 { px.append(Pixel(x: x, y: 11, part: x % 3 == 0 ? .scarfLight : .scarf)) }
        for x in 3...9 { px.append(Pixel(x: x, y: 12, part: .scarf)) }
        px += [Pixel(x: 8, y: 13, part: .scarf), Pixel(x: 9, y: 13, part: .scarfLight), Pixel(x: 9, y: 14, part: .scarf),
               Pixel(x: 10, y: 14, part: .scarfLight)]
        if sparkle { px.append(Pixel(x: 4, y: 11, part: .sparkle)) }
        return px
    }

    /// Where the grid of `stage` sits in the box: centred, its feet on the bottom row.
    static func offset(_ stage: RefugeStage) -> (x: Int, y: Int) {
        let g = grid(stage)
        return ((cols - (g.first?.count ?? cols)) / 2, rows - g.count)
    }

    /// Every pixel of the chamois at `stage` in `mood`, in its box. `frame` is the step of the animation (4 per second),
    /// `blink` closes its eyes for that frame.
    static func pixels(_ stage: RefugeStage, mood: RefugeMood = .happy, frame: Int = 0, blink: Bool = false) -> (body: [Pixel], glow: [Pixel]) {
        let (ox, oy) = offset(stage)
        var cells: [Int: Pixel] = [:]
        func put(_ p: Pixel) { cells[p.y * 100 + p.x] = p }
        func at(_ x: Int, _ y: Int) -> Pixel? { cells[y * 100 + x] }
        for (y, line) in grid(stage).enumerated() {
            for (x, ch) in line.enumerated() { if let part = codes[ch] { put(Pixel(x: x + ox, y: y + oy, part: part)) } }
        }
        var glow: [Pixel] = []
        if stage >= .grand {
            for p in scarf(sparkle: stage == .gold) { put(Pixel(x: p.x + ox, y: p.y + oy, part: p.part)) }
        }
        if stage == .gold {
            glow += [(0, 4, 0.8), (16, 3, 0.9), (1, 11, 0.5), (15, 10, 0.6), (8, 0, 0.6), (3, 1, 0.5), (13, 0, 0.5)]
                .map { Pixel(x: $0.0, y: $0.1, part: .sparkle, alpha: (frame / 2 + $0.0) % 4 == 0 ? 1 : $0.2) }
        }

        // The face: its eyes as columns of two pixels, its nose.
        let eyes = cells.values.filter { $0.part == .eye }
        let columns = Dictionary(grouping: eyes, by: \.x).map { (x: $0.key, top: $0.value.map(\.y).min() ?? 0, bottom: $0.value.map(\.y).max() ?? 0) }
            .sorted { $0.x < $1.x }
        let nose = cells.values.first { $0.part == .nose }
        let middle = columns.isEmpty ? cols / 2 : columns.map(\.x).reduce(0, +) / columns.count
        func face(_ x: Int, _ y: Int) { put(Pixel(x: x, y: y, part: .face)) }

        switch mood {
        case .happy:
            if blink { for c in columns { face(c.x, c.top) } }
        case .sleepy:
            // Closed: a little line, low on the face.
            for c in columns {
                face(c.x, c.top)
                put(Pixel(x: c.x + (c.x < middle ? 1 : -1), y: c.bottom, part: .eye))
            }
        case .sneezy:
            // Screwed up (\ /), and now and then the sneeze itself.
            let sneezing = frame % 10 < 2
            for c in columns {
                face(c.x, c.top)
                if !sneezing { put(Pixel(x: c.x + (c.x < middle ? -1 : 1), y: c.top, part: .eye)) }
            }
            if sneezing, let nose {
                glow += [(-2, 1), (2, 1), (-3, 2), (3, 2), (0, 2)].map { Pixel(x: nose.x + $0.0, y: nose.y + $0.1, part: .sparkle, alpha: 0.85) }
            }
        case .hot:
            if blink { for c in columns { face(c.x, c.top) } }
            if let nose, at(nose.x, nose.y + 1)?.part == .face { put(Pixel(x: nose.x, y: nose.y + 1, part: .tongue)) }
            if let right = columns.last {
                let drop = (frame / 3) % 3
                glow += [Pixel(x: right.x + 4, y: right.top - 1 + drop, part: .sweat), Pixel(x: right.x + 4, y: right.top + drop, part: .sweat)]
            }
        case .boosted:
            for c in columns {
                for x in (c.x - 1)...(c.x + 1) { for y in c.top...c.bottom { put(Pixel(x: x, y: y, part: .glasses)) } }
                put(Pixel(x: c.x - 1, y: c.top, part: .glassShine))
            }
            if columns.count == 2, columns[0].x + 2 < columns[1].x - 1 {
                for x in (columns[0].x + 2)..<(columns[1].x - 1) { put(Pixel(x: x, y: columns[0].top, part: .glasses)) }
            }
        case .worried:
            // Its eyes raised, following the moth.
            for c in columns {
                face(c.x, c.bottom)
                if !blink { put(Pixel(x: c.x, y: c.top - 1, part: .eye)) }
            }
        }
        return (Array(cells.values), glow)
    }

    /// The empty cells around its head and body: drawn on light backgrounds so its cream face stays readable.
    static func contour(_ body: [Pixel]) -> [(x: Int, y: Int)] {
        let taken = Set(body.map { $0.y * 100 + $0.x })
        var seen = Set<Int>()
        var out: [(x: Int, y: Int)] = []
        for p in body where p.part != .horn && p.part != .hornRing && p.part != .hoof {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let key = (p.y + dy) * 100 + p.x + dx
                if !taken.contains(key), seen.insert(key).inserted { out.append((p.x + dx, p.y + dy)) }
            }
        }
        return out
    }

    static func color(_ part: Part, stage: RefugeStage) -> Color {
        let c = Theme.mascot
        let gold = stage == .gold
        switch part {
        case .horn: return gold ? c.goldHorn : c.horn
        case .hornRing: return gold ? c.goldRing : c.hornRing
        case .fur: return gold ? c.goldFur : c.fur
        case .furShade: return gold ? c.goldFurShade : c.furShade
        case .mask: return gold ? c.goldMask : c.mask
        case .face: return c.face
        case .collar: return gold ? c.goldCollar : c.collar
        case .eye: return c.eye
        case .nose: return c.nose
        case .cheek: return c.cheek
        case .hoof: return c.hoof
        case .bell: return c.bell
        case .bellShade: return c.bellShade
        case .scarf: return gold ? c.ruby : c.bronze
        case .scarfLight: return gold ? c.rubyLight : c.bronzeLight
        case .sparkle: return c.sparkle
        case .glasses: return c.glasses
        case .glassShine: return c.glassShine
        case .sweat: return c.sweat
        case .tongue: return c.tongue
        }
    }

    /// Draws the chamois from `origin` (the top left corner of its box), one cell being `pixel` points.
    static func draw(in ctx: GraphicsContext, at origin: CGPoint = .zero, pixel: CGFloat, stage: RefugeStage,
                     mood: RefugeMood = .happy, frame: Int = 0, blink: Bool = false, lift: Int = 0) {
        let (body, glow) = pixels(stage, mood: mood, frame: frame, blink: blink)
        func cell(_ x: Int, _ y: Int) -> Path {
            Path(CGRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y - lift) * pixel, width: pixel, height: pixel))
        }
        let line = Theme.mascot.contour
        for c in contour(body) { ctx.fill(cell(c.x, c.y), with: .color(line)) }
        for p in body { ctx.fill(cell(p.x, p.y), with: .color(color(p.part, stage: stage))) }
        for p in glow { ctx.fill(cell(p.x, p.y), with: .color(color(p.part, stage: stage).opacity(p.alpha))) }
    }

    // MARK: Self-test

    static func selfTest() -> [String] {
        var f: [String] = []
        for stage in RefugeStage.allCases {
            let g = grid(stage)
            if g.contains(where: { $0.count != g[0].count }) { f.append("Refuge : grille de \(stage.title) de travers") }
            if g.count > rows || g[0].count > cols { f.append("Refuge : \(stage.title) dépasse sa boîte") }
            for mood in RefugeMood.allCases {
                for frame in [0, 1, 5, 9] {
                    let (body, glow) = pixels(stage, mood: mood, frame: frame, blink: frame == 5)
                    if (body + glow).contains(where: { $0.x < 0 || $0.x >= cols || $0.y < 0 || $0.y >= rows }) {
                        f.append("Refuge : \(stage.title) \(mood.title) sort de sa boîte")
                    }
                    let keys = body.map { $0.y * 100 + $0.x }
                    if Set(keys).count != keys.count { f.append("Refuge : deux pixels au même endroit (\(stage.title))") }
                    let eyes = body.filter { $0.part == .eye }.count
                    switch mood {
                    case .boosted: if eyes != 0 { f.append("Refuge : des yeux derrière les lunettes de \(stage.title)") }
                    case .sleepy:
                        let rows = Set(body.filter { $0.part == .eye }.map(\.y))
                        if eyes != 4 || rows.count != 1 { f.append("Refuge : \(stage.title) dort les yeux ouverts") }
                    default: if eyes == 0 { f.append("Refuge : \(stage.title) \(mood.title) sans yeux") }
                    }
                    let feet = body.filter { $0.part == .hoof }
                    if feet.isEmpty || feet.contains(where: { $0.y != rows - 1 }) { f.append("Refuge : \(stage.title) ne touche pas le sol") }
                }
            }
        }
        if !pixels(.cabri).body.allSatisfy({ $0.part != .horn }) { f.append("Refuge : le cabri a des cornes") }
        if !pixels(.beau).body.contains(where: { $0.part == .bell }) { f.append("Refuge : le Beau Chamois sans clochette") }
        if pixels(.beau).body.contains(where: { $0.part == .scarf }) || !pixels(.grand).body.contains(where: { $0.part == .scarf }) {
            f.append("Refuge : l'écharpe arrive au Grand Chamois, pas avant")
        }
        if !pixels(.chamois, mood: .hot).body.contains(where: { $0.part == .tongue }) { f.append("Refuge : il a chaud sans tirer la langue") }
        return f
    }
}

/// The chamois alone, at its stage and in its mood, blinking now and then (the dashboard, the stage strip, the ceremonies).
struct RefugeAvatar: View {
    var stage: RefugeStage
    var mood: RefugeMood = .happy
    var pixel: CGFloat = 4
    var animated = true
    @State private var blink = false

    var body: some View {
        Canvas { ctx, _ in
            RefugeFigure.draw(in: ctx, pixel: pixel, stage: stage, mood: mood, blink: blink)
        }
        .frame(width: pixel * CGFloat(RefugeFigure.cols), height: pixel * CGFloat(RefugeFigure.rows))
        .accessibilityElement()
        .accessibilityLabel("\(stage.title), \(mood.title.lowercased())")
        .task(id: animated) {
            guard animated, !Snapshot.isActive else { return }
            // Two tiny updates every few seconds, nothing per frame.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000)
                blink = true
                try? await Task.sleep(nanoseconds: 150_000_000)
                blink = false
            }
        }
    }
}
