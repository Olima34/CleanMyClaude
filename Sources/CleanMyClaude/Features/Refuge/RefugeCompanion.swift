import SwiftUI
import AppKit

/// What the desktop companion shows: its frame, its look and mood, a jump, a word.
@Observable
@MainActor
final class RefugeCompanionState {
    var frame = 0
    var look = RefugeLook(stage: .cabri)
    var mood: RefugeMood = .happy
    var lift = 0
    var word: String?
}

/// The desktop companion: it walks along the bottom of the screen, sits down, naps at night, now and then climbs on the
/// title bar of the front window for a rest, and jumps when blueberries come in. Off by default; four frames per second,
/// only while it is out. A click is a caress, a double click opens its Refuge.
@MainActor
final class RefugeCompanion {
    private var panel: NSPanel?
    private var timer: Timer?
    private weak var model: RefugeModel?
    private let state = RefugeCompanionState()
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var direction: CGFloat = 1
    private var mode: Mode = .walk
    private var ticksLeft = 40
    private var wordTicks = 0
    private var jumpTicks = 0

    private enum Mode { case walk, sit, perch, sleep }

    static let pixel: CGFloat = 3
    static let size = NSSize(width: CGFloat(RefugeFigure.cols) * pixel + 24, height: CGFloat(RefugeFigure.rows) * pixel + 26)

    var isOut: Bool { panel != nil }

    func start(_ model: RefugeModel) {
        self.model = model
        guard panel == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: RefugeCompanionView(state: state,
                                                                     pet: { [weak self] in self?.pet() },
                                                                     open: { [weak self] in self?.openRefuge() }))
        let f = screen.visibleFrame
        x = f.minX + f.width * 0.7
        y = f.minY
        p.setFrameOrigin(NSPoint(x: x, y: y))
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
        guard panel != nil else { return }
        say(word)
        jumpTicks = 3
        if mode == .sleep { mode = .sit; ticksLeft = 20 }
    }

    private func say(_ word: String) {
        state.word = word
        wordTicks = 10
    }

    private func pet() {
        model?.pet()
        say(model?.reaction ?? "Hi hi !")
        jumpTicks = 2
    }

    private func openRefuge() {
        AppContext.model?.page = .refuge
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    private func refreshLook() {
        guard let model else { return }
        state.look = model.look()
        state.mood = model.mood()
    }

    private func tick() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        state.frame += 1
        if state.frame % 20 == 0 { refreshLook() }
        if wordTicks > 0 { wordTicks -= 1; if wordTicks == 0 { state.word = nil } }
        state.lift = jumpTicks > 0 ? (jumpTicks % 2 == 1 ? 2 : 1) : 0
        if jumpTicks > 0 { jumpTicks -= 1 }

        let hour = Calendar.current.component(.hour, from: Date())
        if RefugeRules.isNight(hour), mode != .sleep, jumpTicks == 0 { mode = .sleep; y = f.minY }
        ticksLeft -= 1
        switch mode {
        case .walk:
            x += direction * 3
            if state.frame % 2 == 0, jumpTicks == 0 { state.lift = 1 }
            if x < f.minX { x = f.minX; direction = 1 }
            if x > f.maxX - Self.size.width { x = f.maxX - Self.size.width; direction = -1 }
            if ticksLeft <= 0 { next(f) }
        case .sit:
            if ticksLeft <= 0 { next(f) }
        case .perch:
            if ticksLeft <= 0 { y = f.minY; mode = .walk; ticksLeft = 60 }
        case .sleep:
            state.mood = .sleepy
            if !RefugeRules.isNight(hour) { mode = .walk; ticksLeft = 40; refreshLook() }
        }
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// What it does next: walk, sit, or climb on the front window for a rest.
    private func next(_ f: NSRect) {
        let roll = Int.random(in: 0..<10)
        if roll < 2, let top = Self.frontWindowTop(in: f) {
            mode = .perch
            x = min(max(top.minX + 40, CGFloat.random(in: top.minX...max(top.minX, top.maxX - Self.size.width))), f.maxX - Self.size.width)
            y = top.top - 8
            ticksLeft = Int.random(in: 60...120)
            say("Je fais une pause ici.")
        } else if roll < 5 {
            mode = .sit
            ticksLeft = Int.random(in: 24...56)
        } else {
            mode = .walk
            direction = Bool.random() ? 1 : -1
            ticksLeft = Int.random(in: 40...120)
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

/// The companion itself: its word above it, the chamois below.
private struct RefugeCompanionView: View {
    var state: RefugeCompanionState
    var pet: () -> Void
    var open: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let word = state.word {
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
                RefugeFigure.draw(in: ctx, pixel: RefugeCompanion.pixel,
                                  look: state.look, mood: state.mood, frame: state.frame, blink: state.frame % 18 == 17, lift: state.lift)
            }
            .frame(width: CGFloat(RefugeFigure.cols) * RefugeCompanion.pixel, height: CGFloat(RefugeFigure.rows) * RefugeCompanion.pixel)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: open)
            .onTapGesture(perform: pet)
        }
        .frame(width: RefugeCompanion.size.width, height: RefugeCompanion.size.height, alignment: .bottom)
    }
}
