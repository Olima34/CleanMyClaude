import SwiftUI
import AppKit

/// The mascot: a little feather duster with a face, standing on its handle, 11 × 12 pixels.
/// One drawing for every place it appears: the mascot at rest (`PixelMascot`), the brand mark beside the app's name
/// (`BrandMark`), the menu bar icon and the waiting scenes (`BusyMascot`).
enum MascotFigure {
    static let width = 11
    static let height = 12

    enum Part { case tip, light, feather, shade, eye, mouth, cheek, ferrule, handle, shoe }

    /// How it holds itself in one frame.
    struct Pose: Equatable {
        /// -1 looks left, 0 ahead, 1 right.
        var look = 0
        /// Eyes raised (thinking).
        var up = false
        var blink = false
        /// Eyes screwed up with effort.
        var squint = false
        /// How far the feathers lean, -3 (left) to 3 (right): the whole head swings over what it dusts.
        var lean = 0
    }

    struct Pixel {
        let x: Int
        let y: Int
        let part: Part
    }

    // t = tip, l = light, f = feather, s = shade, m = ring, h = handle, k = sneaker. The face goes on top.
    private static let body = [
        "...tt.tt...",
        ".ttlltlltt.",
        "tllfflffllt",
        "lfffffffffl",
        "lfffffffffl",
        "tffffffffft",
        ".lfffffffl.",
        "..tssfsst..",
        "....mmm....",
        ".....h.....",
        "....h.h....",
        "...kk.kk...",
    ]
    private static let parts: [Character: Part] = ["t": .tip, "l": .light, "f": .feather, "s": .shade,
                                                   "m": .ferrule, "h": .handle, "k": .shoe]
    /// How far each row of the feathers moves for a lean of 1, 2 or 3: more at the top, none at the handle.
    private static let leans: [[Int]] = [[1, 1, 1, 1, 0, 0, 0, 0], [2, 2, 2, 2, 1, 1, 1, 0], [3, 3, 3, 2, 2, 2, 1, 1]]

    private static func shift(_ row: Int, _ lean: Int) -> Int {
        guard lean != 0, row < 8 else { return 0 }
        let step = leans[min(3, abs(lean)) - 1][row]
        return lean > 0 ? step : -step
    }

    /// Every pixel of the figure in `pose`, the face last (it covers the feathers).
    static func pixels(_ pose: Pose = Pose()) -> [Pixel] {
        var out: [Pixel] = []
        func add(_ x: Int, _ y: Int, _ part: Part) { out.append(Pixel(x: x + shift(y, pose.lean), y: y, part: part)) }
        for (y, line) in body.enumerated() {
            for (x, ch) in line.enumerated() { if let part = parts[ch] { add(x, y, part) } }
        }
        let look = max(-1, min(1, pose.look))
        let eyeY = pose.up ? 3 : 4
        for ex in [3 + look, 7 + look] {
            if pose.squint {
                let outward = ex < 5 + look ? -1 : 1
                add(ex, eyeY + 1, .eye)
                add(ex + outward, eyeY + 1, .eye)
            } else {
                if !pose.blink { add(ex, eyeY, .eye) }
                add(ex, eyeY + 1, .eye)
            }
        }
        add(3 + look, 6, .cheek)
        add(7 + look, 6, .cheek)
        add(5 + look, 6, .mouth)
        return out
    }

    /// The empty cells around the feathers: drawn on light backgrounds so their pale tips stay readable.
    static func contour(_ pose: Pose = Pose()) -> [(x: Int, y: Int)] {
        let all = pixels(pose)
        let taken = Set(all.map { $0.y * 100 + $0.x })
        var seen = Set<Int>()
        var out: [(x: Int, y: Int)] = []
        for p in all where ![.ferrule, .handle, .shoe].contains(p.part) {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let key = (p.y + dy) * 100 + p.x + dx
                if !taken.contains(key), seen.insert(key).inserted { out.append((p.x + dx, p.y + dy)) }
            }
        }
        return out
    }

    static func color(_ part: Part) -> Color {
        let c = Theme.mascot
        switch part {
        case .tip: return c.tip
        case .light: return c.light
        case .feather: return c.feather
        case .shade: return c.shade
        case .eye, .mouth: return c.eye
        case .cheek: return c.cheek
        case .ferrule: return c.ferrule
        case .handle: return c.handle
        case .shoe: return c.shoe
        }
    }

    /// Draws the figure from `origin`, one pixel of the figure being `pixel` points. With `ink`, everything is that
    /// single color and the eyes and mouth are cut out (on a filled button, in the menu bar).
    static func draw(in ctx: GraphicsContext, at origin: CGPoint = .zero, pixel: CGFloat, pose: Pose = Pose(),
                     ink: Color? = nil, contour withContour: Bool = false) {
        func cell(_ x: Int, _ y: Int) -> Path {
            Path(CGRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel, width: pixel, height: pixel))
        }
        if withContour, ink == nil {
            let line = Theme.mascot.contour
            for c in contour(pose) { ctx.fill(cell(c.x, c.y), with: .color(line)) }
        }
        var cut = ctx
        cut.blendMode = .destinationOut
        for p in pixels(pose) {
            if let ink {
                if p.part == .eye || p.part == .mouth {
                    cut.fill(cell(p.x, p.y), with: .color(.black))
                } else {
                    ctx.fill(cell(p.x, p.y), with: .color(ink))
                }
            } else {
                ctx.fill(cell(p.x, p.y), with: .color(color(p.part)))
            }
        }
    }

    /// The pixel size that fits the figure (and its contour) in `height` points, on whole half-points so the edges
    /// stay sharp on a Retina screen.
    static func pixel(fitting height: CGFloat) -> CGFloat {
        max(0.5, (height / CGFloat(Self.height + 1) * 2).rounded() / 2)
    }

    /// Pure checks for `--selftest`.
    static func selfTest() -> [String] {
        var failures: [String] = []
        if body.contains(where: { $0.count != width }) || body.count != height { failures.append("Mascotte : grille de travers") }
        for lean in -3...3 {
            for pose in [Pose(lean: lean), Pose(look: 1, up: true, lean: lean), Pose(look: -1, squint: true, lean: lean)] {
                let px = pixels(pose)
                if px.filter({ $0.part == .eye }).count != 4 { failures.append("Mascotte : yeux manquants") }
                if px.contains(where: { $0.x < -3 || $0.x > width + 2 || $0.y < 0 || $0.y >= height }) {
                    failures.append("Mascotte : pixel hors de la figure (penché de \(lean))")
                }
                // The contour never covers the figure itself.
                let taken = Set(px.map { $0.y * 100 + $0.x })
                if contour(pose).contains(where: { taken.contains($0.y * 100 + $0.x) }) { failures.append("Mascotte : contour sur la figure") }
            }
        }
        if pixels(Pose(blink: true)).filter({ $0.part == .eye }).count != 2 { failures.append("Mascotte : clin d'œil") }
        return failures
    }
}

/// The brand mark: the mascot, small, beside the app's name and wherever the app speaks for itself.
/// Themes without ornaments leave it out, unless it is content rather than decoration (the drawn app icon).
struct BrandMark: View {
    /// The side of the square it fits in, in points.
    var size: CGFloat = 28
    /// One color instead of the mascot's own, the eyes cut out.
    var ink: Color? = nil
    var ornament = true

    var body: some View {
        if !ornament || Theme.current.spec.mascot {
            let pixel = MascotFigure.pixel(fitting: size)
            Canvas { ctx, _ in
                MascotFigure.draw(in: ctx, at: CGPoint(x: pixel, y: pixel), pixel: pixel, ink: ink, contour: true)
            }
            .frame(width: pixel * CGFloat(MascotFigure.width + 2), height: pixel * CGFloat(MascotFigure.height + 1))
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The mascot as a template image for the menu bar: one ink, the face cut out. Pixels of 1.5 points give
    /// 16.5 × 18 points, the height of the system's own icons, with sharp edges on a Retina screen.
    static func templateImage(pixel: CGFloat = 1.5) -> NSImage {
        let size = NSSize(width: CGFloat(MascotFigure.width) * pixel, height: CGFloat(MascotFigure.height) * pixel)
        let img = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for p in MascotFigure.pixels() where p.part != .eye && p.part != .mouth {
                NSRect(x: CGFloat(p.x) * pixel, y: CGFloat(p.y) * pixel, width: pixel, height: pixel).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The mascot at rest, blinking now and then. At work (scanning, cleaning, translating…), `BusyMascot` shows it busy.
struct PixelMascot: View {
    var pixel: CGFloat = 4
    @State private var blink = false

    var body: some View {
        if Theme.current.spec.mascot { figure }
    }

    private var figure: some View {
        Canvas { ctx, _ in
            MascotFigure.draw(in: ctx, at: CGPoint(x: pixel, y: pixel), pixel: pixel, pose: MascotFigure.Pose(blink: blink),
                              contour: true)
        }
        .frame(width: pixel * CGFloat(MascotFigure.width + 2), height: pixel * CGFloat(MascotFigure.height + 1))
        .allowsHitTesting(false)
        .task {
            // Blinks now and then: two tiny updates every few seconds, nothing per frame.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                blink = true
                try? await Task.sleep(nanoseconds: 140_000_000)
                blink = false
            }
        }
    }
}

/// Faint dust and a few small feathers in a header, as if the mascot had just been through: denser at the top,
/// fading downward. Drawn once, nothing moves.
struct DustBackdrop: View {
    var seed: UInt64 = 7
    var opacity: Double = 0.5

    var body: some View {
        // Equatable: SwiftUI skips redrawing the specks each time the page around it refreshes.
        if Theme.current.spec.backdrop {
            DustCanvas(seed: seed, opacity: opacity, color: Theme.matrix).equatable()
        }
    }
}

private struct DustCanvas: View, Equatable {
    var seed: UInt64
    var opacity: Double
    var color: Color

    /// A small feather in pixels, its quill pointing down to the left.
    private static let feather = [
        "...##",
        "..###",
        ".###.",
        "###..",
        "#....",
    ]

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: seed)
            let grid: CGFloat = 3
            let cols = max(1, Int(size.width / grid)), rows = max(1, Int(size.height / grid))
            func fade(_ y: CGFloat) -> Double { max(0, 1 - Double(y / max(size.height, 1))) }
            // Specks of dust, one or two pixels.
            for _ in 0..<(cols * rows / 60) {
                let x = CGFloat(rng.next() % UInt64(cols)) * grid
                let y = CGFloat(Double(rng.next() % 1000) / 1000 * Double(rng.next() % 1000) / 1000) * size.height
                let strength = Double(rng.next() % 100) / 100
                let side = strength > 0.85 ? grid * 2 : grid
                ctx.opacity = opacity * fade(y) * (0.25 + 0.75 * strength)
                ctx.fill(Path(CGRect(x: x, y: (y / grid).rounded(.down) * grid, width: side, height: side)), with: .color(color))
            }
            // A few feathers drifting down.
            for _ in 0..<max(1, cols / 70) {
                let x = CGFloat(rng.next() % UInt64(cols)) * grid
                let y = CGFloat(rng.next() % UInt64(max(1, rows / 2))) * grid
                ctx.opacity = opacity * fade(y) * 0.8
                for (r, line) in Self.feather.enumerated() {
                    for (c, ch) in line.enumerated() where ch == "#" {
                        ctx.fill(Path(CGRect(x: x + CGFloat(c) * grid, y: y + CGFloat(r) * grid, width: grid, height: grid)),
                                 with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
