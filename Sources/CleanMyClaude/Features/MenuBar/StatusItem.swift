import AppKit
import SwiftUI

extension MenuMetric {
    /// The text next to the spark in the menu bar ("" for the icon alone).
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
    private static let icon = ClaudeSpark.templateImage(size: 15)
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
    private var lastText = "-"

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
            button.toolTip = "Clean My Claude"
        }
        popover.behavior = .transient
        popover.delegate = self
        app.monitor.onSample = { [weak self] in self?.update() }
        app.monitor.show(.menuBar, metric != .icon)
        update()
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
        let text = metric.text(app.monitor)
        guard text != lastText, let button = item.button else { return }
        lastText = text
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [.font: font])
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
