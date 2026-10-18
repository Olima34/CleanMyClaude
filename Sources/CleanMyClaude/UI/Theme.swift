import SwiftUI
import AppKit

// MARK: - Colors

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    /// A color that follows the light / dark appearance.
    static func adaptive(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: alpha)
                : NSColor(hex: light, alpha: alpha)
        })
    }
}

/// The colors, type and shapes of the active theme (see `ThemeStore`). Every view reads them here,
/// so switching themes in the settings redraws the whole app.
enum Theme {
    static var current: ThemeResolved { ThemeStore.shared.resolved }

    // Surfaces
    static var bg: Color { current.bg }
    static var sidebar: Color { current.sidebar }
    static var card: Color { current.card }
    static var cardRaised: Color { current.cardRaised }
    static var hover: Color { current.hover }
    static var selected: Color { current.selected }
    static var border: Color { current.border }
    static var borderStrong: Color { current.borderStrong }
    static var track: Color { current.track }

    // Text
    static var text: Color { current.text }
    static var text2: Color { current.text2 }
    static var text3: Color { current.text3 }

    // Accent, and what reads on top of it
    static var accent: Color { current.accent }
    static var onAccent: Color { current.onAccent }
    /// Claude's orange in Atelier: the logo, the mascot and a few keys.
    static var brand: Color { current.brand }
    static var onBrand: Color { current.onBrand }
    /// Claude's own orange, the default of the color picker.
    static let brandHex: UInt32 = 0xD97757
    static var matrix: Color { current.matrix }

    // Status
    static var good: Color { current.good }
    static var warn: Color { current.warn }
    static var bad: Color { current.bad }
    static var onBad: Color { current.onBad }

    /// Palette for categorical charts, led by the accent.
    static var palette: [Color] { current.palette }

    static func color(index: Int) -> Color { palette[abs(index) % palette.count] }

    /// Accent → ochre → red as a load goes up (0…1).
    static func load(_ v: Double) -> Color {
        if v < 0.6 { return accent }
        if v < 0.85 { return warn }
        return bad
    }

    // Shapes

    /// A corner radius of the original design, scaled by the theme (0 in the square themes).
    static func r(_ radius: CGFloat) -> CGFloat { radius * current.radiusScale }
    /// Width of card and control outlines.
    static var line: CGFloat { current.line }
    static var icons: ThemeIconStyle { current.spec.icons }

    /// White or near-black, whichever reads better on a fill of the current theme (chart colors, tints).
    @MainActor
    static func ink(on fill: Color) -> Color {
        var ink = ThemeColor.white
        (NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
            if let c = ThemeColor(fill) { ink = c.readableInk }
        }
        return ink.color
    }
}

/// A theme turned into ready-to-draw values, once per change (views read them hundreds of times per frame).
final class ThemeResolved: @unchecked Sendable {
    let spec: ThemeSpec
    let bg, sidebar, card, cardRaised, hover, selected, border, borderStrong, track: Color
    let text, text2, text3: Color
    let accent, onAccent, brand, onBrand, matrix: Color
    let good, warn, bad, onBad: Color
    let palette: [Color]
    let radiusScale: CGFloat
    let line: CGFloat
    let textScale: CGFloat
    let titleDesign: Font.Design
    let titleWeight: Font.Weight
    let bodyDesign: Font.Design

    init(_ spec: ThemeSpec) {
        self.spec = spec
        func make(_ l: ThemeColor, _ d: ThemeColor) -> Color {
            switch spec.appearance {
            case .system: return .adaptive(light: l.hex, dark: d.hex)
            case .light: return Color(hex: l.hex)
            case .dark: return Color(hex: d.hex)
            }
        }
        func c(_ k: ThemeColorKey) -> Color { make(spec.light[k], spec.dark[k]) }
        bg = c(.bg); sidebar = c(.sidebar); card = c(.card); cardRaised = c(.cardRaised); hover = c(.hover)
        selected = c(.selected); border = c(.border); borderStrong = c(.borderStrong); track = c(.track)
        text = c(.text); text2 = c(.text2); text3 = c(.text3)
        accent = c(.accent); onAccent = c(.onAccent); brand = c(.brand); matrix = c(.matrix)
        onBrand = make(spec.light[.brand].readableInk, spec.dark[.brand].readableInk)
        good = c(.good); warn = c(.warn); bad = c(.bad)
        onBad = make(spec.light[.bad].readableInk, spec.dark[.bad].readableInk)
        palette = (0..<ThemePalette.chartCount).map { make(spec.light.chart[$0], spec.dark.chart[$0]) }
        radiusScale = CGFloat(spec.radius)
        line = CGFloat(spec.borderWidth)
        textScale = CGFloat(spec.textScale)
        titleDesign = spec.titleFont.design
        titleWeight = spec.titleWeight.weight
        bodyDesign = spec.bodyFont.design
    }
}

// MARK: - Typography

extension Font {
    /// Titles and big numbers: serif in Atelier, the theme's title font otherwise.
    /// A title left at the regular weight takes the theme's title weight.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let t = Theme.current
        return .system(size: size * t.textScale, weight: weight == .regular ? t.titleWeight : weight, design: t.titleDesign)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let t = Theme.current
        return .system(size: size * t.textScale, weight: weight, design: t.bodyDesign)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * Theme.current.textScale, weight: weight, design: .monospaced)
    }
}

// MARK: - Formatting

enum Fmt {
    static let fr = Locale(identifier: "fr_FR")

    private static let intF: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = fr
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let decF: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = fr
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    static func int(_ v: Int) -> String { intF.string(from: NSNumber(value: v)) ?? "\(v)" }
    static func int(_ v: Double) -> String { intF.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))" }
    static func dec(_ v: Double) -> String {
        if abs(v) >= 100 { return int(v) }
        return decF.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }

    /// Uppercases only the first letter.
    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func pct(_ v: Double) -> String {
        if v > 0 && v < 0.01 { return "< 1 %" }
        return int(v * 100) + " %"
    }

    /// Sizes in the decimal units Finder uses (1 Go = 10⁹ octets).
    static func bytes(_ b: Int64) -> String {
        let v = Double(max(0, b))
        if v < 1000 { return "\(Int(v)) o" }
        let units = ["Ko", "Mo", "Go", "To", "Po"]
        var x = v / 1000
        var i = 0
        while x >= 1000 && i < units.count - 1 { x /= 1000; i += 1 }
        return "\(dec(x)) \(units[i])"
    }

    static func bytes(_ b: UInt64) -> String { bytes(Int64(clamping: b)) }
    static func bytes(_ b: Int) -> String { bytes(Int64(b)) }

    static func speed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1000 { return "\(Int(bytesPerSecond)) o/s" }
        return bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func duration(_ s: Double) -> String {
        if s < 60 { return "\(Int(s)) s" }
        let m = Int(s / 60)
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        if h < 24 { return r == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", r))" }
        let d = h / 24, rh = h % 24
        return rh == 0 ? "\(d) j" : "\(d) j \(rh) h"
    }

    private static func df(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = fr
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }
    private static let dayMonthYear = df("d MMM yyyy")
    private static let time = df("HH:mm")

    static func day(_ d: Date) -> String { dayMonthYear.string(from: d) }
    static func clock(_ d: Date) -> String { time.string(from: d) }

    static func relative(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(Int(s / 60)) min" }
        if s < 86400 { return "il y a \(Int(s / 3600)) h" }
        let days = Int(s / 86400)
        if days < 60 { return "il y a \(days) j" }
        if days < 730 { return "il y a \(days / 30) mois" }
        return "il y a \(days / 365) ans"
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(int(n)) \(n > 1 ? many : one)"
    }

    static func greeting(name: String) -> String {
        let h = Calendar.current.component(.hour, from: Date())
        let who = name.isEmpty ? "" : ", \(name)"
        switch h {
        case 5..<12: return "Bonjour\(who)"
        case 12..<18: return "Bon après-midi\(who)"
        case 18..<23: return "Bonsoir\(who)"
        default: return "Belle nuit\(who)"
        }
    }

    /// The user's first name, from the macOS account.
    static var firstName: String {
        if DemoData.isEnabled { return DemoData.firstName }
        return NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
    }
}
