import SwiftUI
import AppKit
import Observation

enum Page: String, CaseIterable, Identifiable {
    // Declared in sidebar order: the first nine get ⌘1…⌘9.
    case dashboard, cleanup, protection, performance, updates, apps, storage
    case converter, translator, toolbox, clipboard, network
    case launcher, hotkeys, windows, automation
    case assistant, menubar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Tableau de bord"
        case .cleanup: return "Nettoyage du système"
        case .protection: return "Protection et confidentialité"
        case .performance: return "Optimisation"
        case .updates: return "Mises à jour"
        case .apps: return "Applications"
        case .storage: return "Espace de stockage"
        case .converter: return "Convertisseur"
        case .translator: return "Traducteur"
        case .hotkeys: return "Raccourcis"
        case .toolbox: return "Boîte à outils"
        case .clipboard: return "Presse-papiers"
        case .network: return "Réseau"
        case .launcher: return "Lanceur"
        case .windows: return "Fenêtres"
        case .automation: return "Automatisations"
        case .assistant: return "Assistant Claude"
        case .menubar: return "Menu d'état"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .cleanup: return "sparkles"
        case .protection: return "lock.shield"
        case .performance: return "bolt"
        case .updates: return "arrow.down.circle"
        case .apps: return "square.grid.2x2"
        case .storage: return "chart.pie"
        case .converter: return "arrow.left.arrow.right.square"
        case .translator: return "character.bubble"
        case .hotkeys: return "keyboard"
        case .toolbox: return "wrench.and.screwdriver"
        case .clipboard: return "doc.on.clipboard"
        case .network: return "network"
        case .launcher: return "command"
        case .windows: return "rectangle.split.2x1"
        case .automation: return "clock.arrow.2.circlepath"
        case .assistant: return "sparkle"
        case .menubar: return "menubar.rectangle"
        }
    }

    static let groups: [(String, [Page])] = [
        ("Accueil", [.dashboard]),
        ("Entretien", [.cleanup, .protection, .performance, .updates]),
        ("Espace", [.apps, .storage]),
        ("Outils", [.converter, .translator, .toolbox, .clipboard, .network]),
        ("Contrôle", [.launcher, .hotkeys, .windows, .automation]),
        ("Claude", [.assistant]),
        ("En continu", [.menubar])
    ]
}

/// Running totals of what the app freed, kept between launches.
struct CleanupHistory {
    var totalFreed: Int64
    var runs: Int
    var last: Date?

    static func load() -> CleanupHistory {
        let d = UserDefaults.standard
        return CleanupHistory(totalFreed: Int64(d.double(forKey: "history.freed")), runs: d.integer(forKey: "history.runs"),
                              last: d.object(forKey: "history.last") as? Date)
    }

    mutating func record(_ bytes: Int64) {
        guard bytes > 0 else { return }
        totalFreed += bytes
        runs += 1
        last = Date()
        let d = UserDefaults.standard
        d.set(Double(totalFreed), forKey: "history.freed")
        d.set(runs, forKey: "history.runs")
        d.set(last, forKey: "history.last")
    }
}

@Observable
@MainActor
final class AppModel {
    var page: Page = .dashboard
    let monitor: SystemMonitor
    let cleanup = CleanupModel()
    let protection = ProtectionModel()
    let performance = PerformanceModel()
    let apps = AppsModel()
    let storage = StorageModel()
    let startup = StartupModel()
    // Modules (Features/<Module>/), listed in ModuleRegistry.
    let launcher = LauncherModel()
    let converter = ConverterModel()
    let toolbox = ToolboxModel()
    let clipboard = ClipboardModel()
    let updates = UpdatesModel()
    let network = NetworkModel()
    let windows = WindowsModel()
    let automation = AutomationModel()
    let assistant = AssistantModel()
    let translator = TranslatorModel()
    let hotkeys = HotkeysModel()
    var history = DemoData.isEnabled ? DemoData.history : CleanupHistory.load()
    var fullDiskAccess = Permissions.hasFullDiskAccess
    var showOnboarding = !DemoData.isEnabled && !UserDefaults.standard.bool(forKey: Preferences.onboardedKey)
    var smartScanRunning = false
    var smartScanDate: Date?

    init(liveMonitor: Bool = true) {
        monitor = SystemMonitor(start: liveMonitor)
        let freed: (Int64) -> Void = { [weak self] bytes in
            self?.history.record(bytes)
            self?.monitor.sampleDisk()
        }
        cleanup.onFreed = freed
        protection.onFreed = freed
        if DemoData.isEnabled {
            DemoData.populate(self)
            ModuleRegistry.loadDemo(self)
        } else if liveMonitor {
            let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Alerts.check(self.monitor)
                }
            }
            t.tolerance = 10
            RunLoop.main.add(t, forMode: .common)
        }
    }

    func refreshPermissions() {
        fullDiskAccess = Permissions.hasFullDiskAccess
    }

    /// The one-click checkup: junk, security, apps and startup items, all at once.
    func smartScan() async {
        guard !smartScanRunning else { return }
        smartScanRunning = true
        refreshPermissions()
        async let a: Void = cleanup.scan()
        async let b: Void = protection.audit()
        async let c: Void = apps.scan()
        async let d: Void = startup.scan()
        _ = await (a, b, c, d)
        smartScanDate = Date()
        smartScanRunning = false
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Preferences.onboardedKey)
        showOnboarding = false
    }

    // MARK: Health

    /// 0…100, from free space, memory pressure, security and junk.
    var healthScore: Int {
        var score = 0.0
        let freeFrac = monitor.diskTotal > 0 ? Double(monitor.diskFree) / Double(monitor.diskTotal) : 0.3
        score += 30 * min(1, freeFrac / 0.25)
        switch monitor.pressure {
        case .normal: score += 20
        case .warning: score += 10
        case .critical: score += 0
        }
        if protection.hasAudit {
            score += 30 * protection.securityRatio
        } else {
            score += 22
        }
        if cleanup.hasResults {
            let junkGB = Double(cleanup.recommendedSize) / 1e9
            score += 20 * (1 - min(1, junkGB / 20))
        } else {
            score += 15
        }
        return Int(score.rounded())
    }

    var healthLabel: String {
        switch healthScore {
        case 85...: return "Excellente forme"
        case 70..<85: return "Bonne forme"
        case 50..<70: return "Peut mieux faire"
        default: return "À surveiller"
        }
    }

    var healthColor: Color {
        switch healthScore {
        case 85...: return Theme.good
        case 70..<85: return Theme.accent
        case 50..<70: return Theme.warn
        default: return Theme.bad
        }
    }
}
