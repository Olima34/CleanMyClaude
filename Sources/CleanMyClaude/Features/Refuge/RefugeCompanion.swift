import SwiftUI
import AppKit

/// What the desktop companion shows: its frame, its look and mood, a jump, a word, how it leans.
@Observable
@MainActor
final class RefugeCompanionState {
    var frame = 0
    var look = RefugeLook(stage: .cabri)
    var mood: RefugeMood = .happy
    var lift = 0
    var word: String?
    /// 0 standing, 90 leaning in from the left edge, -90 from the right, 180 hanging from the top.
    var rotation: Double = 0
}

/// Somewhere it can stand: the bottom of the screen, or the top edge of a window, where no other window covers it.
/// `minX`…`maxX` is where the middle of its feet may go; `left` follows the window when it is dragged.
struct RefugeSurface: Equatable {
    /// The window's number, 0 for the bottom of the screen.
    var id: Int
    var y: CGFloat
    var minX: CGFloat
    var maxX: CGFloat
    var left: CGFloat

    func contains(_ x: CGFloat) -> Bool { x >= minX - 1 && x <= maxX + 1 }
}

/// Its view takes the first click even while the app is in the background: a caress needs no activation.
private final class RefugeCompanionHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless panel that may sit partly off the screen (leaning in from an edge).
private final class RefugeCompanionPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

/// The desktop companion: it always stands on something. It walks along the bottom of the screen and along the top
/// edges of the windows, jumps from one to another, follows a window that is dragged and falls to the next place to
/// stand if its window closes or slides away. Now and then it leans in from the left or right edge of the screen or
/// hangs from the top to peek down, sleeps at night, and jumps when blueberries come in. Off by default; four frames per
/// second, only while it is out. A click is a caress; three quick ones send it away (the menu bar panel calls it back).
/// Clicks anywhere else go through to what is underneath.
@MainActor
final class RefugeCompanion {
    private var panel: RefugeCompanionPanel?
    private var timer: Timer?
    private weak var model: RefugeModel?
    private let state = RefugeCompanionState()
    /// Where the middle of its feet is.
    private var feet = CGPoint.zero
    private var surface: RefugeSurface?
    private var surfaces: [RefugeSurface] = []
    private var direction: CGFloat = 1
    private var mode: Mode = .walk
    private var ticksLeft = 40
    private var wordTicks = 0
    private var jumpTicks = 0
    private var fallSpeed: CGFloat = 0
    private var jump: Jump?
    private var taps: [Date] = []
    /// Walking in from off the screen.
    private var entering = false

    private enum Mode: Equatable {
        case walk, sit, sleep, jumping, falling, leaving
        case lean(left: Bool)
        case hang
    }

    /// A jump in progress: from where, to where, what it does on landing.
    private struct Jump {
        enum Landing { case surface(RefugeSurface), lean(left: Bool), hang }
        var from: CGPoint
        var to: CGPoint
        var step = 0
        var steps: Int
        var height: CGFloat
        var landing: Landing
    }

    static let pixel: CGFloat = 3
    static let size = NSSize(width: 96, height: 86)
    /// Half the width of its feet: how close to the end of an edge it may walk.
    static let reach: CGFloat = 16
    /// The chamois' square in the panel: centred, at the bottom.
    private static var figure: CGRect {
        let side = CGFloat(RefugeFigure.cols) * pixel
        return CGRect(x: (size.width - side) / 2, y: 0, width: side, height: side)
    }

    var isOut: Bool { panel != nil }

    func start(_ model: RefugeModel) {
        self.model = model
        guard panel == nil, let f = Self.screenFrame else { return }
        let p = RefugeCompanionPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.contentView = RefugeCompanionHost(rootView: RefugeCompanionView(state: state, tap: { [weak self] in self?.tapped() }))
        // It comes in from the right, walking along the bottom of the screen.
        surfaces = Self.currentSurfaces(in: f)
        surface = surfaces.first { $0.id == 0 }
        feet = CGPoint(x: f.maxX + Self.size.width / 2, y: f.minY)
        direction = -1
        mode = .walk
        entering = true
        ticksLeft = 70
        p.setFrameOrigin(origin)
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        refreshLook()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Blueberries came in, or it ate: a little jump and a word.
    func react(_ word: String) {
        guard panel != nil, mode != .leaving else { return }
        say(word)
        jumpTicks = 3
        if mode == .sleep { mode = .sit; ticksLeft = 20 }
    }

    private static var screenFrame: NSRect? { (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame }

    /// The panel's corner for where its feet are.
    private var origin: CGPoint { CGPoint(x: feet.x - Self.size.width / 2, y: feet.y) }

    private func say(_ word: String) {
        state.word = word
        wordTicks = 10
    }

    /// A caress; three quick ones and it leaves.
    private func tapped() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 0.9 } + [now]
        if taps.count >= 3 {
            taps = []
            leave()
            return
        }
        model?.pet()
        say(model?.reaction ?? "Hi hi !")
        jumpTicks = 2
    }

    private func leave() {
        mode = .leaving
        state.rotation = 0
        say("À plus tard !")
        jumpTicks = 3
        ticksLeft = 6
    }

    private func refreshLook() {
        guard let model else { return }
        state.look = model.look()
        state.mood = model.mood()
    }

    // MARK: Each frame

    private func tick() {
        guard let panel, let f = Self.screenFrame else { return }
        state.frame += 1
        if state.frame % 20 == 0, mode != .sleep { refreshLook() }
        if wordTicks > 0 { wordTicks -= 1; if wordTicks == 0, mode != .leaving { state.word = nil } }
        state.lift = jumpTicks > 0 ? (jumpTicks % 2 == 1 ? 2 : 1) : 0
        if jumpTicks > 0 { jumpTicks -= 1 }
        ticksLeft -= 1

        // Twice a second, where it can stand: it follows its window, or falls when the window is gone.
        if state.frame % 2 == 0 {
            surfaces = Self.currentSurfaces(in: f)
            if [.walk, .sit, .sleep].contains(mode) { holdOn(f) }
        }

        let night = RefugeRules.isNight(Calendar.current.component(.hour, from: Date()))
        switch mode {
        case .walk:
            guard let s = surface else { startFalling(); break }
            feet.x += direction * 3
            if state.frame % 2 == 0, jumpTicks == 0 { state.lift = 1 }
            // Coming in from off the screen, it keeps walking in; then it turns at the ends of its edge.
            if entering, s.contains(feet.x) { entering = false }
            if !entering, feet.x < s.minX { feet.x = s.minX; direction = 1; if Bool.random() { next(f) } }
            if !entering, feet.x > s.maxX { feet.x = s.maxX; direction = -1; if Bool.random() { next(f) } }
            if night { mode = .sleep; break }
            if ticksLeft <= 0 { next(f) }
        case .sit:
            if night { mode = .sleep; break }
            if ticksLeft <= 0 { next(f) }
        case .sleep:
            state.mood = .sleepy
            if !night { mode = .walk; ticksLeft = 40; refreshLook() }
        case .jumping:
            guard var j = jump else { startFalling(); break }
            j.step += 1
            let t = CGFloat(j.step) / CGFloat(j.steps)
            feet.x = j.from.x + (j.to.x - j.from.x) * t
            feet.y = j.from.y + (j.to.y - j.from.y) * t + j.height * sin(t * .pi)
            jump = j
            if j.step >= j.steps { land(j.landing, f: f) }
        case .falling:
            fallSpeed = min(fallSpeed + 3, 36)
            let below = landing(under: feet, maxY: feet.y)
            feet.y -= fallSpeed
            if let below, feet.y <= below.y {
                feet.y = below.y
                surface = below
                mode = .sit
                ticksLeft = Int.random(in: 8...16)
                jumpTicks = 2
                say("Ouf !")
            } else if feet.y < f.minY - 200 {
                // Off the screen somehow: back on its feet at the bottom.
                surface = surfaces.first { $0.id == 0 }
                feet = CGPoint(x: min(max(feet.x, f.minX + Self.reach), f.maxX - Self.reach), y: f.minY)
                mode = .sit
            }
        case .lean(let left):
            // Clinging to the edge, a little in and out, as if it were looking around.
            let peek: CGFloat = state.frame % 8 < 4 ? 30 : 34
            feet.x = left ? f.minX - (Self.figure.maxX - peek) + Self.size.width / 2 : f.maxX - Self.figure.minX - peek + Self.size.width / 2
            if ticksLeft <= 0 {
                // It lets go of the edge, back on the screen, and drops to what is below.
                feet.x = left ? f.minX + Self.reach + 4 : f.maxX - Self.reach - 4
                startFalling()
            }
        case .hang:
            let peek: CGFloat = state.frame % 8 < 4 ? 30 : 34
            feet.y = f.maxY - peek
            if ticksLeft <= 0 { startFalling() }
        case .leaving:
            if ticksLeft <= 0 {
                panel.alphaValue = max(0, panel.alphaValue - 0.25)
                if panel.alphaValue <= 0 {
                    stop()
                    model?.companionLeft()
                    return
                }
            }
        }
        panel.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
        // Clicks go through, except on the chamois itself.
        let mouse = NSEvent.mouseLocation
        let body = Self.figure.offsetBy(dx: origin.x, dy: origin.y)
        panel.ignoresMouseEvents = !body.insetBy(dx: 4, dy: 4).contains(mouse)
    }

    /// Standing on something: it follows its window when dragged, and falls when the window closes, is covered or moves
    /// away from under it.
    private func holdOn(_ f: NSRect) {
        guard let current = surface else { startFalling(); return }
        if current.id == 0 {
            // The bottom of the screen is always there (it moves only with the Dock).
            surface = surfaces.first { $0.id == 0 }
            feet.y = surface?.y ?? f.minY
            return
        }
        // Its window, where it is now: dragged, it carries the chamois along.
        let moved = surfaces.filter { $0.id == current.id }.map { (surface: $0, x: feet.x + ($0.left - current.left)) }
        if let m = moved.first(where: { $0.surface.contains($0.x) }) {
            feet.x = m.x
            feet.y = m.surface.y
            surface = m.surface
        } else {
            say("Oups !")
            startFalling()
        }
    }

    private func startFalling() {
        state.rotation = 0
        surface = nil
        jump = nil
        fallSpeed = 0
        mode = .falling
    }

    /// The highest place to stand under a point.
    private func landing(under p: CGPoint, maxY: CGFloat) -> RefugeSurface? {
        surfaces.filter { $0.contains(p.x) && $0.y <= maxY + 1 }.max { $0.y < $1.y }
    }

    private func land(_ landing: Jump.Landing, f: NSRect) {
        jump = nil
        switch landing {
        case .surface(let s):
            // The window may have moved meanwhile: it lands where it still is, or falls.
            if let now = surfaces.first(where: { $0.id == s.id && $0.contains(feet.x) && abs($0.y - feet.y) < 12 }) {
                feet.y = now.y
                surface = now
                mode = .sit
                ticksLeft = Int.random(in: 16...40)
                jumpTicks = 2
            } else {
                startFalling()
            }
        case .lean(let left):
            mode = .lean(left: left)
            state.rotation = left ? 90 : -90
            ticksLeft = Int.random(in: 24...48)
            say("Coucou !")
        case .hang:
            mode = .hang
            state.rotation = 180
            ticksLeft = Int.random(in: 24...48)
        }
    }

    private func leap(to point: CGPoint, landing: Jump.Landing) {
        state.rotation = 0
        let distance = hypot(point.x - feet.x, point.y - feet.y)
        jump = Jump(from: feet, to: point, steps: max(5, min(14, Int(distance / 22))), height: 24 + min(90, distance * 0.18), landing: landing)
        surface = nil
        mode = .jumping
    }

    /// What it does next, as it likes: walk, sit, jump to another edge, lean in from a side, hang from the top.
    private func next(_ f: NSRect) {
        state.rotation = 0
        let roll = Int.random(in: 0..<100)
        let others = surfaces.filter { $0.id != surface?.id && abs($0.y - feet.y) < 520 }
        switch roll {
        case ..<30:
            mode = .walk
            direction = Bool.random() ? 1 : -1
            ticksLeft = Int.random(in: 40...110)
        case ..<52:
            mode = .sit
            ticksLeft = Int.random(in: 24...60)
        case ..<84:
            // Onto another edge: the top of a window, or down to the bottom of the screen.
            if let s = others.randomElement() {
                let x = CGFloat.random(in: s.minX...max(s.minX, s.maxX))
                leap(to: CGPoint(x: x, y: s.y), landing: .surface(s))
            } else {
                mode = .walk
                ticksLeft = 60
            }
        case ..<93:
            // Onto the side of the screen, if it is not far.
            let left = feet.x < f.midX
            let x = left ? f.minX - (Self.figure.maxX - 32) + Self.size.width / 2 : f.maxX - Self.figure.minX - 32 + Self.size.width / 2
            if abs(x - feet.x) < 420 {
                leap(to: CGPoint(x: x, y: min(f.maxY - 140, feet.y + CGFloat.random(in: 40...160))), landing: .lean(left: left))
            } else {
                mode = .sit
                ticksLeft = 30
            }
        default:
            // Up to the top of the screen, if it stands high enough.
            if f.maxY - feet.y < 420 {
                leap(to: CGPoint(x: feet.x, y: f.maxY - 32), landing: .hang)
            } else {
                mode = .sit
                ticksLeft = 30
            }
        }
    }

    // MARK: Where it can stand

    /// The bottom of the screen and the visible top edges of the windows on it, front to back.
    private static func currentSurfaces(in f: NSRect) -> [RefugeSurface] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first?.frame.height else { return surfaces(windows: [], screen: f) }
        var windows: [(id: Int, rect: CGRect)] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            windows.append((w[kCGWindowNumber as String] as? Int ?? 0, CGRect(x: b.minX, y: primary - b.maxY, width: b.width, height: b.height)))
        }
        return surfaces(windows: windows, screen: f)
    }

    /// Where it can stand, from the windows (front to back, in screen coordinates) and the visible screen: the bottom of
    /// the screen, and each window's top edge minus the parts covered by windows in front, below the menu bar.
    static func surfaces(windows: [(id: Int, rect: CGRect)], screen f: CGRect) -> [RefugeSurface] {
        var out = [RefugeSurface(id: 0, y: f.minY, minX: f.minX + reach, maxX: f.maxX - reach, left: f.minX)]
        var front: [CGRect] = []
        for w in windows {
            defer { front.append(w.rect) }
            let top = w.rect.maxY
            guard w.rect.width >= 160, w.rect.height >= 80, top >= f.minY + 60, top <= f.maxY - 56 else { continue }
            var segments: [(CGFloat, CGFloat)] = [(max(w.rect.minX, f.minX), min(w.rect.maxX, f.maxX))]
            for r in front where r.minY <= top + 2 && r.maxY >= top - 2 {
                segments = segments.flatMap { s -> [(CGFloat, CGFloat)] in
                    guard r.maxX > s.0, r.minX < s.1 else { return [s] }
                    return [(s.0, r.minX), (r.maxX, s.1)].filter { $0.1 - $0.0 > 0 }
                }
            }
            for s in segments where s.1 - s.0 >= 2 * reach + 30 {
                out.append(RefugeSurface(id: w.id, y: top, minX: s.0 + reach, maxX: s.1 - reach, left: w.rect.minX))
            }
        }
        return out
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let screen = CGRect(x: 0, y: 80, width: 1440, height: 800)
        // A window in front, another behind it whose top edge it half covers, a tiny one, one under the menu bar.
        let windows: [(id: Int, rect: CGRect)] = [
            (1, CGRect(x: 600, y: 200, width: 500, height: 500)),
            (2, CGRect(x: 100, y: 150, width: 800, height: 400)),
            (3, CGRect(x: 1200, y: 300, width: 100, height: 60)),
            (4, CGRect(x: 0, y: 90, width: 1440, height: 790)),
        ]
        let s = surfaces(windows: windows, screen: screen)
        if s.first?.id != 0 || s.first?.y != 80 { f.append("Compagnon : le bas de l'écran n'est pas une surface") }
        if !s.contains(where: { $0.id == 1 && $0.y == 700 && $0.minX == 600 + reach }) { f.append("Compagnon : le haut de la fenêtre devant manque") }
        let back = s.filter { $0.id == 2 }
        if back.count != 1 || back.first?.maxX != 600 - reach { f.append("Compagnon : la partie cachée d'une fenêtre derrière reste une surface") }
        if s.contains(where: { $0.id == 3 || $0.id == 4 }) { f.append("Compagnon : une fenêtre minuscule ou sous la barre des menus est une surface") }
        if s.contains(where: { $0.minX > $0.maxX }) { f.append("Compagnon : surface à l'envers") }
        return f
    }
}

/// The companion itself: its word above it (when it stands), the chamois below, leaning as it does.
private struct RefugeCompanionView: View {
    var state: RefugeCompanionState
    var tap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let word = state.word, state.rotation == 0 {
                    Text(word).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.card))
                        .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 1))
                } else {
                    Color.clear
                }
            }
            .frame(height: 18)
            Canvas { ctx, _ in
                RefugeFigure.draw(in: ctx, pixel: RefugeCompanion.pixel, look: state.look, mood: state.mood, frame: state.frame,
                                  blink: state.frame % 18 == 17, lift: state.lift)
            }
            .frame(width: CGFloat(RefugeFigure.cols) * RefugeCompanion.pixel, height: CGFloat(RefugeFigure.rows) * RefugeCompanion.pixel)
            .rotationEffect(.degrees(state.rotation))
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
        }
        .frame(width: RefugeCompanion.size.width, height: RefugeCompanion.size.height, alignment: .bottom)
    }
}
