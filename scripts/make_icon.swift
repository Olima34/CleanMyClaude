// Renders the app icon (1024×1024 PNG): the head of the mascot, a little chamois with hooked horns and a cream face,
// in a warm glow on a mountain-sky blue, a few snowflakes around.
// The head is the same pixel drawing as `MascotFigure` in the app (UI/Components/Brand.swift), ears spread a little wider.
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
ctx.setFillColor(rgb(0x2E5A8A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x6FB6F0), rgb(0x2D5B9A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFF3D6, 0.35), rgb(0xFFF3D6, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 520), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 520), endRadius: 420, options: [])

// MARK: The chamois' head

// n = horn, f = fur, F = darker fur, m = mask, w = face, e = eye, p = nose, c = cheek.
let head = [
    "..nn.....nn..",
    "....n...n....",
    "ff..n...n..ff",
    ".fFfwwwwwfFf.",
    "..fmwwwwwmf..",
    "..fmewwwemf..",
    "..fmewwwemf..",
    "...fcwpwcf...",
    "....fwwwf....",
]
let colors: [Character: UInt32] = ["n": 0x2B2420, "f": 0xC8925A, "F": 0x9E6B3C, "m": 0xB07E55, "w": 0xF7E7D2,
                                   "e": 0x16202B, "p": 0xD9877F, "c": 0xFF9BB0]
let px: CGFloat = 56
let origin = CGPoint(x: 512 - 13 * px / 2, y: 250)
for (y, line) in head.enumerated() {
    for (x, ch) in line.enumerated() {
        guard let hex = colors[ch] else { continue }
        ctx.setFillColor(rgb(hex))
        ctx.fill(CGRect(x: origin.x + CGFloat(x) * px, y: origin.y + CGFloat(y) * px, width: px, height: px))
    }
}

// MARK: Snowflakes

for (x, y, a) in [(760.0, 250.0, 0.9), (812.0, 196.0, 0.6), (232.0, 320.0, 0.7), (700.0, 180.0, 0.5)] {
    ctx.setFillColor(rgb(0xFFFFFF, CGFloat(a)))
    ctx.fill(CGRect(x: x, y: y, width: 34, height: 34))
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
