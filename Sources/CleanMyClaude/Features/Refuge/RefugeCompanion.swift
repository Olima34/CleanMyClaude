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

/// Its view takes the first click even while the app is in the background: a caress needs no activation.
private final class RefugeCompanionHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless panel that may sit partly off the screen (leaning in from an edge).
private final class RefugeCompanionPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

/// The desktop companion: it wanders all over the screen as it likes. It walks along the bottom, trots to a spot at
/// random and sits, leans in from the left or right edge, hangs from the top of the screen to peek down, takes a rest on
/// the title bar of the front window, sleeps at night, and jumps when blueberries come in. Off by default; four frames
/// per second, only while it is out. A click is a caress; three quick ones send it away (the menu bar panel calls it
/// back). Clicks anywhere else go through to what is underneath.
@MainActor
final class RefugeCompanion {
    private var panel: RefugeCompanionPanel?
    private var timer: Timer?
    private weak var model: RefugeModel?
    private let state = RefugeCompanionState()
    private var origin = CGPoint.zero
    private var target: CGPoint?
    private var direction: CGFloat = 1
    private var mode: Mode = .walk
    private var ticksLeft = 40
    private var wordTicks = 0
    private var jumpTicks = 0
    private var taps: [Date] = []

    private enum Mode: Equatable {
        case walk, trot, sit, perch, sleep, leaving
        case lean(left: Bool)
        case hang
    }

    static let pixel: CGFloat = 3
    static let size = NSSize(width: 96, height: 86)
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
        // It comes in from the right, along the bottom.
        origin = CGPoint(x: f.maxX, y: f.minY)
        trot(to: CGPoint(x: f.maxX - Self.size.width - 160, y: f.minY))
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

    private func tick() {
        guard let panel, let f = Self.screenFrame else { return }
        state.frame += 1
        if state.frame % 20 == 0, mode != .sleep { refreshLook() }
        if wordTicks > 0 { wordTicks -= 1; if wordTicks == 0, mode != .leaving { state.word = nil } }
        state.lift = jumpTicks > 0 ? (jumpTicks % 2 == 1 ? 2 : 1) : 0
        if jumpTicks > 0 { jumpTicks -= 1 }
        ticksLeft -= 1

        let night = RefugeRules.isNight(Calendar.current.component(.hour, from: Date()))
        if night, ![.sleep, .leaving].contains(mode), jumpTicks == 0 {
            mode = .sleep
            state.rotation = 0
            origin = CGPoint(x: min(max(origin.x, f.minX), f.maxX - Self.size.width), y: f.minY)
        }

        switch mode {
        case .walk:
            origin.x += direction * 3
            origin.y = f.minY
            if state.frame % 2 == 0, jumpTicks == 0 { state.lift = 1 }
            if origin.x < f.minX { origin.x = f.minX; direction = 1 }
            if origin.x > f.maxX - Self.size.width { origin.x = f.maxX - Self.size.width; direction = -1 }
            if ticksLeft <= 0 { next(f) }
        case .trot:
            guard let target else { next(f); break }
            let dx = target.x - origin.x, dy = target.y - origin.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= 6 {
                origin = target
                self.target = nil
                mode = .sit
                ticksLeft = Int.random(in: 20...48)
            } else {
                origin.x += dx / distance * 6
                origin.y += dy / distance * 6
                if jumpTicks == 0 { state.lift = state.frame % 2 == 0 ? 2 : 0 }
            }
        case .sit, .perch:
            if ticksLeft <= 0 { next(f) }
        case .lean(let left):
            // A little in and out, as if it were looking around.
            let peek: CGFloat = state.frame % 8 < 4 ? 30 : 34
            origin.x = left ? f.minX - (Self.figure.maxX - peek) : f.maxX - Self.figure.minX - peek
            if ticksLeft <= 0 { trot(to: randomSpot(f)) }
        case .hang:
            let peek: CGFloat = state.frame % 8 < 4 ? 30 : 34
            origin.y = f.maxY - peek
            if ticksLeft <= 0 { trot(to: randomSpot(f)) }
        case .sleep:
            state.mood = .sleepy
            if !night { mode = .walk; ticksLeft = 40; refreshLook() }
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
        let figure = Self.figure.offsetBy(dx: origin.x, dy: origin.y)
        panel.ignoresMouseEvents = !figure.insetBy(dx: 4, dy: 4).contains(mouse)
    }

    private func trot(to spot: CGPoint) {
        state.rotation = 0
        target = spot
        mode = .trot
    }

    /// A spot somewhere on the screen, fully visible.
    private func randomSpot(_ f: NSRect) -> CGPoint {
        CGPoint(x: CGFloat.random(in: f.minX...(f.maxX - Self.size.width)), y: CGFloat.random(in: f.minY...(f.maxY - Self.size.height)))
    }

    /// What it does next, as it likes: walk, trot somewhere, sit, lean in from an edge, hang from the top, rest on a window.
    private func next(_ f: NSRect) {
        state.rotation = 0
        let roll = Int.random(in: 0..<100)
        switch roll {
        case ..<22:
            mode = .walk
            origin.y = f.minY
            direction = Bool.random() ? 1 : -1
            ticksLeft = Int.random(in: 40...100)
        case ..<52:
            trot(to: Bool.random() ? randomSpot(f) : CGPoint(x: CGFloat.random(in: f.minX...(f.maxX - Self.size.width)), y: f.minY))
        case ..<66:
            mode = .sit
            ticksLeft = Int.random(in: 24...56)
        case ..<80:
            let left = Bool.random()
            mode = .lean(left: left)
            state.rotation = left ? 90 : -90
            origin.y = CGFloat.random(in: (f.minY + 40)...(f.maxY - Self.size.height - 40))
            ticksLeft = Int.random(in: 24...48)
            say("Coucou !")
        case ..<92:
            mode = .hang
            state.rotation = 180
            origin.x = CGFloat.random(in: (f.minX + 40)...(f.maxX - Self.size.width - 40))
            ticksLeft = Int.random(in: 24...48)
        default:
            if let top = Self.frontWindowTop(in: f) {
                mode = .perch
                origin = CGPoint(x: min(max(CGFloat.random(in: top.minX...max(top.minX, top.maxX - Self.size.width)), f.minX), f.maxX - Self.size.width),
                                 y: top.top - 8)
                ticksLeft = Int.random(in: 60...120)
                say("Je fais une pause ici.")
            } else {
                mode = .sit
                ticksLeft = 30
            }
        }
    }

    /// The top edge of the front app's main window, in screen coordinates (window bounds need no permission).
    private static func frontWindowTop(in f: NSRect) -> (minX: CGFloat, maxX: CGFloat, top: CGFloat)? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary), b.width > 300, b.height > 200 else { continue }
            let top = mainHeight - b.minY
            guard top < f.maxY - size.height, top > f.minY + 100, b.minX >= f.minX, b.maxX <= f.maxX else { return nil }
            return (b.minX, b.maxX, top)
        }
        return nil
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
