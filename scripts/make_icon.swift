// Renders the Clean My Claude app icon (1024×1024 PNG):
// Claude Code's pixel creature sweeping little files that fly away, on a near-black background.
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Vivid palette.
let orange: UInt32 = 0xFF7A4D   // the creature, a punchier Claude orange
let gold: UInt32 = 0xFFB01F     // broom handle
let red: UInt32 = 0xFF3D5A      // broom binding
let yellow: UInt32 = 0xFFE23D   // bristles
let fileColors: [UInt32] = [0x00D0FF, 0xFF2E97, 0xA8FF2E, 0xFFD60A, 0xA45BFF, 0xFF8A1F]

// MARK: Background

let box = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: box, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.45))
ctx.addPath(shape)
ctx.setFillColor(rgb(0x050505))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x121212), rgb(0x030303)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Colored glows: warm behind the creature, pink and cyan where the files fly.
func glow(_ c: CGPoint, _ r: CGFloat, _ hex: UInt32, _ a: CGFloat) {
    let g = CGGradient(colorsSpace: cs, colors: [rgb(hex, a), rgb(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
glow(CGPoint(x: 380, y: 380), 330, orange, 0.30)
glow(CGPoint(x: 780, y: 650), 280, 0xFF2E97, 0.20)
glow(CGPoint(x: 700, y: 820), 220, 0x00D0FF, 0.16)

// MARK: Floor shadow

ctx.setFillColor(rgb(0x000000, 0.55))
ctx.fillEllipse(in: CGRect(x: 150, y: 214, width: 560, height: 56))

// MARK: The creature (9×5 pixel grid, plus an arm reaching for the broom)

let p: CGFloat = 46
let x0: CGFloat = 140
let top: CGFloat = 480
let grid: [[Int]] = [
    [0, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 1, 2, 1, 1, 1, 2, 1, 0, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [0, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 1, 0, 1, 0, 1, 0, 1, 0, 0]
]
func pixelRect(_ col: Int, _ row: Int) -> CGRect {
    CGRect(x: x0 + CGFloat(col) * p, y: top - CGFloat(row + 1) * p, width: p, height: p)
}

// MARK: Broom (drawn before the arm so the hand holds it)

let handleTop = CGPoint(x: 430, y: 660)
let handleEnd = CGPoint(x: 600, y: 330)
let d = CGPoint(x: handleEnd.x - handleTop.x, y: handleEnd.y - handleTop.y)
let len = (d.x * d.x + d.y * d.y).squareRoot()
let dir = CGPoint(x: d.x / len, y: d.y / len)
let nrm = CGPoint(x: -dir.y, y: dir.x)
func along(_ o: CGPoint, _ t: CGFloat, _ s: CGFloat) -> CGPoint {
    CGPoint(x: o.x + dir.x * t + nrm.x * s, y: o.y + dir.y * t + nrm.y * s)
}
ctx.setLineCap(.round)
ctx.setLineWidth(26)
ctx.setStrokeColor(rgb(0xB86E00))
ctx.move(to: handleTop); ctx.addLine(to: handleEnd); ctx.strokePath()
ctx.setLineWidth(18)
ctx.setStrokeColor(rgb(gold))
ctx.move(to: handleTop); ctx.addLine(to: handleEnd); ctx.strokePath()

// Bristles: a fan continuing the handle.
let b0 = handleEnd
let bristleLen: CGFloat = 120
let bristles = CGMutablePath()
bristles.move(to: along(b0, 0, -36))
bristles.addLine(to: along(b0, 0, 36))
bristles.addLine(to: along(b0, bristleLen, 78))
bristles.addQuadCurve(to: along(b0, bristleLen, -78), control: along(b0, bristleLen + 22, 0))
bristles.closeSubpath()
ctx.addPath(bristles)
ctx.setFillColor(rgb(yellow))
ctx.fillPath()
ctx.setLineWidth(5)
ctx.setStrokeColor(rgb(0xE0A800))
for s in stride(from: -54.0, through: 54.0, by: 18.0) {
    ctx.move(to: along(b0, 16, CGFloat(s) * 0.45))
    ctx.addLine(to: along(b0, bristleLen - 4, CGFloat(s)))
}
ctx.strokePath()
// Binding band.
let band = CGMutablePath()
band.move(to: along(b0, -14, -40))
band.addLine(to: along(b0, -14, 40))
band.addLine(to: along(b0, 16, 44))
band.addLine(to: along(b0, 16, -44))
band.closeSubpath()
ctx.addPath(band)
ctx.setFillColor(rgb(red))
ctx.fillPath()

// MARK: Body

for (r, row) in grid.enumerated() {
    for (c, v) in row.enumerated() where v != 0 {
        let rect = pixelRect(c, r)
        ctx.setFillColor(v == 2 ? rgb(0x0A0A0A) : rgb(orange))
        ctx.fill(rect.insetBy(dx: -0.5, dy: -0.5))
    }
}
// A light edge on top of each body pixel row, for a bit of volume.
ctx.setFillColor(rgb(0xFFFFFF, 0.16))
for c in 1...7 { ctx.fill(CGRect(x: x0 + CGFloat(c) * p, y: top - 8, width: p, height: 8)) }
// Eye shine.
ctx.setFillColor(rgb(0xFFFFFF, 0.9))
for c in [2, 6] { ctx.fill(CGRect(x: x0 + CGFloat(c) * p + 8, y: top - 2 * p + 26, width: 12, height: 12)) }
// The hand on the handle.
let hand = along(handleTop, 0.84 * len, 0)
ctx.setFillColor(rgb(orange))
ctx.fill(CGRect(x: hand.x - 26, y: hand.y - 26, width: 52, height: 52))

// MARK: Flying files

func file(_ c: CGPoint, _ w: CGFloat, _ angle: CGFloat, _ hex: UInt32) {
    let h = w * 1.25
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle * .pi / 180)
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(hex, 0.55))
    let fold = w * 0.3
    let body = CGMutablePath()
    body.move(to: CGPoint(x: -w / 2, y: -h / 2))
    body.addLine(to: CGPoint(x: w / 2, y: -h / 2))
    body.addLine(to: CGPoint(x: w / 2, y: h / 2 - fold))
    body.addLine(to: CGPoint(x: w / 2 - fold, y: h / 2))
    body.addLine(to: CGPoint(x: -w / 2, y: h / 2))
    body.closeSubpath()
    ctx.addPath(body)
    ctx.setFillColor(rgb(hex))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // Folded corner.
    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: w / 2 - fold, y: h / 2))
    corner.addLine(to: CGPoint(x: w / 2 - fold, y: h / 2 - fold))
    corner.addLine(to: CGPoint(x: w / 2, y: h / 2 - fold))
    corner.closeSubpath()
    ctx.addPath(corner)
    ctx.setFillColor(rgb(0xFFFFFF, 0.55))
    ctx.fillPath()
    // Text lines.
    ctx.setFillColor(rgb(0xFFFFFF, 0.85))
    let lh = max(4, w * 0.08)
    for (i, frac) in [0.62, 0.78, 0.5].enumerated() {
        let y = h / 2 - fold - lh * 2.2 - CGFloat(i) * lh * 2.4
        ctx.fill(CGRect(x: -w / 2 + w * 0.16, y: y, width: (w * 0.68) * CGFloat(frac), height: lh))
    }
    ctx.restoreGState()
}

/// Speed lines behind a file, pointing back to the broom.
let sweepOrigin = CGPoint(x: 690, y: 290)
func speedLines(_ c: CGPoint, _ w: CGFloat, _ hex: UInt32) {
    let vx = c.x - sweepOrigin.x, vy = c.y - sweepOrigin.y
    let l = (vx * vx + vy * vy).squareRoot()
    let v = CGPoint(x: vx / l, y: vy / l)
    let n = CGPoint(x: -v.y, y: v.x)
    ctx.setLineCap(.round)
    for (offset, length, alpha) in [(-0.32, 0.55, 0.55), (0.0, 0.85, 0.75), (0.32, 0.45, 0.45)] as [(CGFloat, CGFloat, CGFloat)] {
        let back = w * 0.85
        let a = CGPoint(x: c.x - v.x * back + n.x * w * offset, y: c.y - v.y * back + n.y * w * offset)
        let b = CGPoint(x: a.x - v.x * w * length, y: a.y - v.y * w * length)
        ctx.setLineWidth(max(4, w * 0.09))
        ctx.setStrokeColor(rgb(hex, alpha))
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }
}

// A soft swoosh left by the broom.
ctx.setLineCap(.round)
ctx.setLineWidth(16)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.07))
ctx.move(to: CGPoint(x: 600, y: 210))
ctx.addQuadCurve(to: CGPoint(x: 905, y: 610), control: CGPoint(x: 880, y: 260))
ctx.strokePath()
ctx.setLineWidth(8)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.06))
ctx.move(to: CGPoint(x: 650, y: 200))
ctx.addQuadCurve(to: CGPoint(x: 905, y: 470), control: CGPoint(x: 860, y: 220))
ctx.strokePath()

let files: [(CGPoint, CGFloat, CGFloat, UInt32)] = [
    (CGPoint(x: 762, y: 418), 78, -16, fileColors[0]),
    (CGPoint(x: 828, y: 566), 66, 18, fileColors[1]),
    (CGPoint(x: 668, y: 628), 56, -28, fileColors[2]),
    (CGPoint(x: 852, y: 720), 50, 30, fileColors[3]),
    (CGPoint(x: 750, y: 800), 44, -10, fileColors[4]),
    (CGPoint(x: 858, y: 850), 32, 24, fileColors[5])
]
for (c, w, _, hex) in files { speedLines(c, w, hex) }
for (c, w, a, hex) in files { file(c, w, a, hex) }

// Dust pixels kicked up by the broom.
let dust: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
    (706, 262, 14, 0xFFE23D), (744, 300, 10, 0x00D0FF), (690, 330, 9, 0xFF2E97), (770, 268, 8, 0xA8FF2E),
    (640, 520, 10, 0xFFD60A), (880, 600, 9, 0x00D0FF), (720, 880, 8, 0xFF2E97), (610, 720, 8, 0xA45BFF)
]
for (x, y, s, hex) in dust {
    ctx.setFillColor(rgb(hex, 0.9))
    ctx.fill(CGRect(x: x, y: y, width: s, height: s))
}

// Four-pointed glints.
func glint(_ c: CGPoint, _ r: CGFloat, _ alpha: CGFloat) {
    let path = CGMutablePath()
    let k = r * 0.22
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xFFFFFF, alpha))
    ctx.fillPath()
}
glint(CGPoint(x: 250, y: 760), 46, 0.95)
glint(CGPoint(x: 320, y: 830), 20, 0.7)
glint(CGPoint(x: 190, y: 660), 16, 0.5)
ctx.restoreGState()

// Thin inner border.
ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.07))
ctx.setLineWidth(3)
ctx.strokePath()

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("icon written to \(out)")
