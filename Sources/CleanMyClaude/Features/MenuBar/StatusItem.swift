import AppKit
import SwiftUI
import Observation

extension MenuMetric {
    /// The text next to the mascot in the menu bar ("" for the icon alone).
    @MainActor
    func text(_ m: SystemMonitor) -> String {
        switch self {
        case .icon: return ""
        case .cpu: return "\(Int((m.cpu * 100).rounded())) %"
        case .memory: return "\(Int((m.memFraction * 100).rounded())) %"
        case .cpuMemory: return "\(Int((m.cpu * 100).rounded()))% · \(Int((m.memFraction * 100).rounded()))%"
        case .network: return "↓\(Fmt.speed(m.netIn)) ↑\(Fmt.speed(m.netOut))"
        case .disk: return Fmt.bytes(m.diskFree)
        case .temperature: return PerformanceSensorReader.shared.quickTemperature().map { "\(Int($0.rounded()))°" } ?? "—"
        }
    }
}

/// The menu bar item, built with AppKit. Changing its text is a cheap property update,
/// whereas a SwiftUI `MenuBarExtra` label rebuilds the whole app menu at every refresh (measured: ~2 % of CPU).
/// The text follows the monitor's samples; with the icon alone, the item keeps the monitor running only while its
/// panel is open.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let app: AppModel
    private var metric = StatusItemController.savedMetric
    private static let icon = BrandMark.templateImage()
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
    private var lastText = "-"
    private var shownMood: RefugeMood?
    /// The download shown in the item: its whole percent (-1 before the first figure, -2 while it waits), nil when none.
    private var shownDownload: Int?

    nonisolated private static var savedMetric: MenuMetric {
        MenuMetric(rawValue: UserDefaults.standard.string(forKey: Preferences.menuMetricKey) ?? "") ?? .cpuMemory
    }

    init(app: AppModel) {
        self.app = app
        super.init()
        if let button = item.button {
            button.image = Self.icon
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle(_:))
            button.toolTip = "Chamois"
        }
        popover.behavior = .transient
        popover.delegate = self
        app.monitor.onSample = { [weak self] in self?.update() }
        app.monitor.show(.menuBar, metric != .icon)
        update()
        watchDownloads()
        // The metric is picked in the settings and on the Menu d'état page.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.metricMayHaveChanged() }
        }
    }

    private func metricMayHaveChanged() {
        let saved = Self.savedMetric
        guard saved != metric else { return }
        metric = saved
        app.monitor.show(.menuBar, metric != .icon)
        update()
    }

    private func update() {
        // A download in progress takes the item's place until it ends.
        guard shownDownload == nil else { return }
        // The chamois' head follows its mood (asleep at night, glasses during the Boost…), drawn only when it changes.
        if let button = item.button, app.refuge.menuMood != shownMood {
            shownMood = app.refuge.menuMood
            button.image = shownMood.map { RefugeFigure.menuImage($0) } ?? Self.icon
        }
        let text = metric.text(app.monitor)
        guard text != lastText, let button = item.button else { return }
        lastText = text
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [.font: font])
    }

    // MARK: Downloads

    /// Follows the YouTube downloads: called again after each change (at most four a second while one runs), never
    /// in between, so nothing runs while there is nothing to download.
    private func watchDownloads() {
        withObservationTracking {
            _ = app.youtube.activity
        } onChange: { [weak self] in
            // Called before the change: the new values are read once it is done.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.showDownload()
                    self?.watchDownloads()
                }
            }
        }
        showDownload()
    }

    private func showDownload() {
        guard let button = item.button else { return }
        guard let a = app.youtube.activity else {
            guard shownDownload != nil else { return }
            // Over: back to the mascot and the chosen figure.
            shownDownload = nil
            button.image = Self.icon
            button.toolTip = "Chamois"
            lastText = "-"
            update()
            return
        }
        let key = a.running ? (a.progress.map { Int(($0 * 100).rounded(.down)) } ?? -1) : -2
        if key != shownDownload {
            shownDownload = key
            button.image = Self.downloadImage(progress: a.running ? a.progress : nil)
            button.attributedTitle = NSAttributedString(string: " " + (a.running ? a.percent : "en attente"), attributes: [.font: font])
        }
        button.toolTip = a.tooltip
    }

    /// The mascot and a ring that fills as the download goes. A template image: the menu bar colors it, light or dark.
    /// `progress` nil: the ring's track alone (the first figure has not come, or the download waits its turn).
    static func downloadImage(progress: Double?) -> NSImage {
        let mascot = icon.size
        let ring: CGFloat = 13
        let gap: CGFloat = 4
        let size = NSSize(width: mascot.width + gap + ring, height: max(mascot.height, ring))
        let img = NSImage(size: size, flipped: true) { _ in
            icon.draw(in: NSRect(x: 0, y: (size.height - mascot.height) / 2, width: mascot.width, height: mascot.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let line: CGFloat = 2
            let r = NSRect(x: mascot.width + gap, y: (size.height - ring) / 2, width: ring, height: ring).insetBy(dx: line / 2, dy: line / 2)
            let track = NSBezierPath(ovalIn: r)
            track.lineWidth = line
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            if let p = progress, p > 0 {
                // From the top, clockwise (the drawing is flipped: y goes down).
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: -90,
                              endAngle: -90 + 360 * min(1, p), clockwise: false)
                arc.lineWidth = line
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            show()
        }
    }

    private func show() {
        guard let button = item.button else { return }
        // A fresh view each time, so the panel starts and stops reading processes with its own lifetime.
        let host = NSHostingController(rootView: MenuBarPanel().environment(app))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        app.monitor.show(.panel, true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        app.monitor.show(.panel, false)
    }
}

/// `--snapshot --page menubar`: the menu bar item while a video downloads, as it looks over a light and a dark bar.
struct StatusItemPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array([(0.08, "8 %"), (0.62, "62 %"), (0.97, "97 %")].enumerated()), id: \.offset) { _, s in
                HStack(spacing: 14) {
                    item(s.0, s.1, dark: false)
                    item(s.0, s.1, dark: true)
                }
            }
            HStack(spacing: 14) {
                item(nil, "en attente", dark: false)
                item(nil, "en attente", dark: true)
            }
        }
        .padding(16)
    }

    private func item(_ progress: Double?, _ text: String, dark: Bool) -> some View {
        // The menu bar's own colors, fixed on purpose: the item is drawn by macOS, not by the theme.
        let ink: Color = dark ? .white : .black
        return HStack(spacing: 3) {
            Image(nsImage: StatusItemController.downloadImage(progress: progress))
                .renderingMode(.template)
            Text(text).font(.system(size: NSFont.systemFontSize - 1).monospacedDigit())
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Rectangle().fill(dark ? Color(white: 0.16) : Color(white: 0.93)))
    }
}
