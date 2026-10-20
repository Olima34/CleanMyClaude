// Renders the app icon (1024×1024 PNG): the mascot, a little chamois with hooked horns and a cream face, sorting
// leaves — the green one it keeps shines in one hoof, the dry one it puts away crumbles in the other — in a meadow
// under a deep mountain blue.
// The chamois is the drawing of `MascotFigure` in the app (UI/Components/Brand.swift), twice as fine. The scene is
// drawn on a small grid without antialiasing (pixel grids and vector shapes), then scaled up without blur.
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
// Top-left origin, like the pixel grid.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// A stable pseudo-random value in 0..<1 for a cell, so that every render is the same.
func noise(_ x: Int, _ y: Int, _ seed: Int) -> Double {
    var v = UInt64(bitPattern: Int64(x &* 73_856_093 ^ y &* 19_349_663 ^ seed &* 83_492_791))
    v ^= v >> 13
    v &*= 0x5BD1_E995
    v ^= v >> 15
    return Double(v % 10_000) / 10_000
}

// MARK: Background

let box = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: box, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
// Shadow offsets are not flipped with the context: a negative height falls downward.
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(shape)
ctx.setFillColor(rgb(0x14305A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x3C74B4), rgb(0x14305A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFF0D0, 0.24), rgb(0xFFF0D0, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 440), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 440), endRadius: 420, options: [])

// MARK: The pixel grid

// Cell (0, 0) sits at (ox, oy) in the icon, each cell u pixels wide; the grid starts at (cx0, cy0) to cover the icon.
let u = 22, ox = 226, oy = 184
let cx0 = -11, cy0 = -9, cols = 48, rows = 48
guard let low = CGContext(data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
low.setShouldAntialias(false)
low.translateBy(x: 0, y: CGFloat(rows))
low.scaleBy(x: 1, y: -1)
low.translateBy(x: CGFloat(-cx0), y: CGFloat(-cy0))

func cell(_ x: Int, _ y: Int, _ color: CGColor) {
    low.setFillColor(color)
    low.fill(CGRect(x: x, y: y, width: 1, height: 1))
}

func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: CGColor) {
    low.setFillColor(color)
    low.fill(CGRect(x: x, y: y, width: w, height: h))
}

func poly(_ pts: [(Double, Double)], _ color: CGColor) {
    low.setFillColor(color)
    low.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
    low.closePath()
    low.fillPath()
}

func line(_ pts: [(Double, Double)], _ width: Double, _ color: CGColor) {
    low.setStrokeColor(color)
    low.setLineWidth(width)
    low.setLineCap(.round)
    low.setLineJoin(.round)
    low.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
    low.strokePath()
}

// n = horn, N = horn glint, f = fur, F = darker fur, h = fur highlight, i = inside of the ear, m = mask, w = face,
// W = face shade, e = eye, o = glint, p = nose, P = nose shade, c = cheek, k = hoof, K = hoof glint, Q = sparkle.
let colors: [Character: CGColor] = [
    "n": 0x2B2420, "N": 0x54463A, "f": 0xC8925A, "F": 0x9E6B3C, "h": 0xE0AE76, "i": 0xF0B3A2, "m": 0xB07E55,
    "w": 0xF7E7D2, "W": 0xE3CDB2, "e": 0x16202B, "o": 0xFFFFFF, "p": 0xD9877F, "P": 0xB8655F, "c": 0xFF9BB0,
    "k": 0x3D3530, "K": 0x5A4E46, "Q": 0xFFF0A0,
].mapValues { rgb($0) }

func sprite(_ grid: [String], _ x: Int, _ y: Int) {
    for (r, row) in grid.enumerated() {
        for (c, ch) in row.enumerated() {
            if let color = colors[ch] { cell(x + c, y + r, color) }
        }
    }
}

/// Flat-shaded peaks: a lit left flank, a right flank in shade, a snow cap with a jagged edge.
func peaks(_ list: [(x: Double, y: Double, w: Double)], base by: Double, body: UInt32, shade: UInt32,
           snow: UInt32? = nil, snowShade: UInt32 = 0, cap: Double = 3) {
    for p in list {
        poly([(p.x - p.w, by), (p.x, p.y), (p.x, by)], rgb(body))
        poly([(p.x, p.y), (p.x + p.w, by), (p.x, by)], rgb(shade))
        guard let snow else { continue }
        let k = cap / (by - p.y)
        let lx = p.x - p.w * k, rx = p.x + p.w * k, cy = p.y + cap
        poly([(p.x, p.y), (lx, cy), (lx + (p.x - lx) * 0.35, cy - 1), (p.x - (p.x - lx) * 0.25, cy + 0.6), (p.x, cy - 0.4)], rgb(snow))
        poly([(p.x, p.y), (p.x, cy - 0.4), (p.x + (rx - p.x) * 0.3, cy + 0.5), (p.x + (rx - p.x) * 0.65, cy - 0.8), (rx, cy)], rgb(snowShade))
    }
}

/// An arm from the shoulder to a hoof, fur with a darker underside.
func arm(from a: (Double, Double), to b: (Double, Double)) {
    line([a, b], 2.6, colors["F"]!)
    line([(a.0, a.1 - 0.5), (b.0, b.1 - 0.5)], 1.6, colors["f"]!)
    low.setFillColor(colors["k"]!)
    low.fillEllipse(in: CGRect(x: b.0 - 1.25, y: b.1 - 1.25, width: 2.5, height: 2.5))
}

/// A leaf whose stem starts at (x, y), pointing at `angle` degrees (0 = right, -90 = up): two tones split by the
/// midrib, the darker half away from the top-left light.
func leaf(_ x: Double, _ y: Double, angle: Double, length L: Double, width W: Double,
          main: UInt32, dark: UInt32, vein: UInt32, stem: UInt32) {
    let th = angle * .pi / 180
    var t = CGAffineTransform(translationX: x, y: y).rotated(by: th)
    let outline = CGMutablePath()
    outline.move(to: .zero)
    outline.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: L * 0.3, y: -W * 1.55), control2: CGPoint(x: L * 0.72, y: -W * 1.05))
    outline.addCurve(to: .zero, control1: CGPoint(x: L * 0.72, y: W * 1.05), control2: CGPoint(x: L * 0.3, y: W * 1.55))
    let path = outline.copy(using: &t)!
    let litUp = sin(th) - cos(th) < 0
    line([(x - cos(th) * 1.6, y - sin(th) * 1.6), (x + cos(th) * 1.6, y + sin(th) * 1.6)], 1, rgb(stem))
    low.addPath(path)
    low.setFillColor(rgb(main))
    low.fillPath()
    low.saveGState()
    low.addPath(path)
    low.clip()
    low.addPath(CGPath(rect: CGRect(x: -1, y: litUp ? 0 : -W * 3, width: L + 2, height: W * 3), transform: &t))
    low.setFillColor(rgb(dark))
    low.fillPath()
    low.restoreGState()
    line([(x + cos(th) * 0.8, y + sin(th) * 0.8), (x + cos(th) * L * 0.8, y + sin(th) * L * 0.8)], 1, rgb(vein))
}

// MARK: Stars, mountains, meadow

for (x, y, big) in [(-3, 0, false), (12, -2, true), (28, 2, false), (22, -3, false), (-1, -3, false)] {
    if big {
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { cell(x + dx, y + dy, rgb(0xFFF6D8, 0.4)) }
    }
    cell(x, y, rgb(0xFFF6D8, 0.8))
}
peaks([(-7, 14, 13), (33, 13, 13)], base: 34, body: 0x5283BD, shade: 0x3F6CA6, snow: 0xE6EFF9, snowShade: 0xBDD1E7)
peaks([(-4, 21, 13), (13, 23, 13), (30, 20.5, 13)], base: 34, body: 0x1F416F, shade: 0x1A385F)
rect(-7, 27, 40, 8, rgb(0x3E8546))
rect(-7, 27, 40, 1, rgb(0x6DBB63))
rect(-7, 28, 40, 1, rgb(0x4F9C52))
for x in -6...32 where noise(x, 26, 6) < 0.3 { cell(x, 26, rgb(0x6DBB63)) }

// MARK: The chamois

sprite([
    ".....nnnn........nnnn.....",
    "....nn..Nn......Nn..nn....",
    "....n...Nn......Nn...n....",
    "........Nn......Nn........",
    "hff.....nn......nn.....ffh",
    "fiif....nn......nn....fiif",
    ".fiiFFffwwwwwwwwwwffFFiif.",
    "..fFFfffwwwwwwwwwwfffFFf..",
    "....FfmmwwwwwwwwwwmmfF....",
    "....FfmmwwwwwwwwwwmmfF....",
    "....FfmmoewwwwwwoemmfF....",
    "....FfmmeewwwwwweemmfF....",
    "....FfmmeewwwwwweemmfF....",
    "....FfmmeewwwwwweemmfF....",
    ".....FfmccwwppwwccmfF.....",
    "......FfccwwPPwwccfF......",
    ".......FfwwwwwwwwfF.......",
    "........FfwwwwwwfF........",
    ".........FfwwwwfF.........",
    "........FfwwwwwwfF........",
    "......FfffwwwwwwfffF......",
    "......FfffwwwwwwfffF......",
    "......FfffWwwwwWfffF......",
    "......FFffffffffffFF......",
    "......FffF......FffF......",
    "......FffF......FffF......",
    "......kKkk......kKkk......",
    "......kkkk......kkkk......",
], 0, 0)
arm(from: (6.5, 21.5), to: (2.5, 17.5))
arm(from: (18.5, 21.5), to: (22.5, 17.5))

// MARK: The leaves it sorts

// The green one, kept, shines.
leaf(2, 17, angle: -145, length: 7.6, width: 1.9, main: 0x5DBE6B, dark: 0x3A8B4C, vein: 0x2A6A3A, stem: 0x2A6A3A)
sprite([".o.", "oQo", ".o."], -6, 9)
sprite(["...o...", "...o...", "..oQo..", "ooQQQoo", "..oQo..", "...o...", "...o..."], -2, 8)
// The dry one, put away, crumbles.
leaf(23, 17, angle: -35, length: 7.6, width: 1.9, main: 0xB38659, dark: 0x815B38, vein: 0x664629, stem: 0x5A3E26)
for (x, y, a) in [(27, 16, 0.9), (29, 18, 0.8), (26, 20, 0.7), (29, 22, 0.55), (27, 24, 0.4)] as [(Int, Int, CGFloat)] {
    cell(x, y, rgb(0x815B38, a))
}

// Scaled up without blur: every cell becomes a crisp u × u square.
ctx.saveGState()
ctx.interpolationQuality = .none
let dest = CGRect(x: ox + cx0 * u, y: oy + cy0 * u, width: cols * u, height: rows * u)
ctx.translateBy(x: dest.minX, y: dest.maxY)
ctx.scaleBy(x: 1, y: -1)
ctx.draw(low.makeImage()!, in: CGRect(origin: .zero, size: dest.size))
ctx.restoreGState()
ctx.restoreGState()

// Thin inner border.
ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08))
ctx.setLineWidth(3)
ctx.strokePath()

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("icon written to \(out)")
