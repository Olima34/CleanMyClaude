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
        }
    }
}

/// The menu bar item, built with AppKit. Changing its text is a cheap property update,
/// whereas a SwiftUI `MenuBarExtra` label rebuilds the whole app menu at every refresh (measured: ~2 % of CPU).
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let app: AppModel
    private var timer: Timer?
    private static let icon = ClaudeSpark.templateImage(size: 15)
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
    private var lastText = "-"

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
        update()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func update() {
        let raw = UserDefaults.standard.string(forKey: Preferences.menuMetricKey) ?? ""
        let metric = MenuMetric(rawValue: raw) ?? .cpuMemory
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}
