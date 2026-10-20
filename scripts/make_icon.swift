// Renders the app icon (1024×1024 PNG): the mascot, a little feather duster with a face, standing in a warm glow
// on a deep blue, the dust it has just raised flying off to the right.
// The figure is the same 11 × 12 pixel grid as `MascotFigure` in the app (UI/Components/Brand.swift).
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

// MARK: Background

let box = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: box, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
// Shadow offsets are not flipped with the context: a negative height falls downward.
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(shape)
ctx.setFillColor(rgb(0x26328A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x4C66DB), rgb(0x1E2970)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFD86B, 0.34), rgb(0xFFD86B, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 400, options: [])
// Its shadow on the floor.
ctx.setFillColor(rgb(0x0B1240, 0.4))
ctx.fillEllipse(in: CGRect(x: 312, y: 826, width: 400, height: 40))

// MARK: The mascot

// t = tip, l = light, f = feather, s = shade, m = ring, h = handle, k = sneaker, e = eye or mouth, c = cheek.
let figure = [
    "...tt.tt...",
    ".ttlltlltt.",
    "tllfflffllt",
    "lfffffffffl",
    "lffefffeffl",
    "tffefffefft",
    ".lfcfefcfl.",
    "..tssfsst..",
    "....mmm....",
    ".....h.....",
    "....h.h....",
    "...kk.kk...",
]
let colors: [Character: UInt32] = ["t": 0xFFE7A8, "l": 0xF8CC5F, "f": 0xF1B23A, "s": 0xCC8B1C, "m": 0xA9B3BE,
                                   "h": 0x9C6B47, "k": 0xE8577A, "e": 0x16202B, "c": 0xFF8A73]
let px: CGFloat = 44
let origin = CGPoint(x: 512 - 11 * px / 2, y: 846 - 12 * px)
for (y, line) in figure.enumerated() {
    for (x, ch) in line.enumerated() {
        guard let hex = colors[ch] else { continue }
        ctx.setFillColor(rgb(hex))
        ctx.fill(CGRect(x: origin.x + CGFloat(x) * px, y: origin.y + CGFloat(y) * px, width: px, height: px))
    }
}

// MARK: Dust flying off

for (x, y, a) in [(704.0, 262.0, 0.9), (772.0, 198.0, 0.7), (818.0, 284.0, 0.5), (650.0, 186.0, 0.6), (840.0, 160.0, 0.35)] {
    ctx.setFillColor(rgb(0xFFF4D6, CGFloat(a)))
    ctx.fill(CGRect(x: x, y: y, width: 30, height: 30))
}
ctx.restoreGState()

// Thin inner border.
ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.07))
ctx.setLineWidth(3)
ctx.strokePath()

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("icon written to \(out)")
