import SwiftUI
import AppKit

/// The Claude "spark": irregular rounded rays around a center. Themes without ornaments leave it out.
/// While work is in progress, `BusyMascot` shows it instead.
struct ClaudeSpark: View {
    var size: CGFloat = 28
    var color: Color = Theme.brand
    /// A short turn when it appears.
    var animate = false
    /// False where the spark is content rather than decoration (the drawn app icons).
    var ornament = true
    @State private var turn = 0.0

    var body: some View {
        if !ornament || Theme.current.spec.mascot {
            spark
        }
    }

    static let rays: [(angle: Double, length: Double)] = [
        (0, 1.0), (31, 0.82), (64, 0.95), (95, 0.78), (128, 1.0), (160, 0.86),
        (193, 0.97), (224, 0.8), (257, 0.93), (290, 0.84), (322, 0.98)
    ]

    private var spark: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = min(sz.width, sz.height) / 2
            let w = r * 0.2
            for ray in Self.rays {
                let a = (ray.angle - 90) * .pi / 180
                let inner = r * 0.12
                let outer = r * ray.length
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a) * (outer - w / 2), y: c.y + sin(a) * (outer - w / 2)))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(turn))
        .onAppear {
            if animate {
                withAnimation(.easeOut(duration: 1.4)) { turn = 32 }
            }
        }
    }

    /// A template image of the spark, for the menu bar.
    static func templateImage(size: CGFloat = 16) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2
            let w = r * 0.22
            NSColor.black.setStroke()
            for ray in rays {
                let a = (90 - ray.angle) * .pi / 180
                let p = NSBezierPath()
                p.lineWidth = w
                p.lineCapStyle = .round
                p.move(to: CGPoint(x: c.x + cos(a) * r * 0.12, y: c.y + sin(a) * r * 0.12))
                p.line(to: CGPoint(x: c.x + cos(a) * (r * ray.length - w / 2), y: c.y + sin(a) * (r * ray.length - w / 2)))
                p.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The little pixel creature of Claude Code, here with its broom, at rest.
/// At work (scanning, cleaning, translating…), `BusyMascot` shows it busy with the task.
struct PixelMascot: View {
    var pixel: CGFloat = 4
    var color: Color = Theme.brand
    var broom = false
    @State private var blink = false

    // 1 = body, 2 = eye, 0 = empty
    private static let grid: [[Int]] = [
        [0, 1, 1, 1, 1, 1, 1, 1, 0],
        [0, 1, 2, 1, 1, 1, 2, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1, 1],
        [0, 1, 1, 1, 1, 1, 1, 1, 0],
        [0, 1, 0, 1, 0, 1, 0, 1, 0]
    ]

    // A broom held on the right side: handle (3) and bristles (4).
    private static let broomGrid: [(x: Int, y: Int, v: Int)] = [
        (11, -2, 3), (11, -1, 3), (11, 0, 3), (11, 1, 3), (11, 2, 3), (11, 3, 3),
        (10, 4, 4), (11, 4, 4), (12, 4, 4), (10, 5, 4), (11, 5, 4), (12, 5, 4)
    ]

    var body: some View {
        if Theme.current.spec.mascot { mascot }
    }

    @ViewBuilder
    private var mascot: some View {
        let cols: CGFloat = broom ? 13 : 9
        let rows: CGFloat = broom ? 8 : 5
        let yOff: CGFloat = broom ? 2 : 0
        Canvas { ctx, _ in
            for (y, row) in Self.grid.enumerated() {
                for (x, v) in row.enumerated() where v != 0 {
                    let rect = CGRect(x: CGFloat(x) * pixel, y: (CGFloat(y) + yOff) * pixel, width: pixel, height: pixel)
                    if v == 2 {
                        ctx.fill(Path(rect), with: .color(blink ? color : Theme.onBrand))
                    } else {
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
            if broom {
                for b in Self.broomGrid {
                    let rect = CGRect(x: CGFloat(b.x) * pixel, y: (CGFloat(b.y) + yOff) * pixel, width: pixel, height: pixel)
                    ctx.fill(Path(rect), with: .color(b.v == 3 ? Theme.text2 : Theme.warn))
                }
                // The arm reaching the handle.
                ctx.fill(Path(CGRect(x: 9 * pixel, y: (2 + yOff) * pixel, width: 2 * pixel, height: pixel)), with: .color(color))
            }
        }
        .frame(width: pixel * cols, height: pixel * rows)
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

/// Faint columns of random characters, like the Claude Code tab background.
struct MatrixBackdrop: View {
    var seed: UInt64 = 7
    var opacity: Double = 0.5

    var body: some View {
        // Equatable: SwiftUI skips redrawing hundreds of glyphs each time the page around it refreshes.
        if Theme.current.spec.backdrop {
            MatrixCanvas(seed: seed, opacity: opacity, color: Theme.matrix, font: .mono(10.5)).equatable()
        }
    }
}

private struct MatrixCanvas: View, Equatable {
    var seed: UInt64
    var opacity: Double
    var color: Color
    var font: Font

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: seed)
            let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            let colW: CGFloat = 8.2
            let rowH: CGFloat = 13
            let cols = Int(size.width / colW)
            let rows = Int(size.height / rowH)
            for c in 0..<max(0, cols) {
                let colStrength = Double(rng.next() % 100) / 100
                guard colStrength > 0.35 else { continue }
                let startRow = Int(rng.next() % UInt64(max(1, rows)))
                let len = 4 + Int(rng.next() % 14)
                for r in startRow..<max(startRow, min(rows, startRow + len)) {
                    let ch = chars[Int(rng.next() % UInt64(chars.count))]
                    let fade = 1 - Double(r - startRow) / Double(len)
                    let yFade = 1 - Double(r) / Double(max(rows, 1))
                    let text = Text(String(ch)).font(font).foregroundColor(color)
                    ctx.opacity = opacity * fade * yFade * colStrength
                    ctx.draw(text, at: CGPoint(x: CGFloat(c) * colW + colW / 2, y: CGFloat(r) * rowH + rowH / 2))
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
