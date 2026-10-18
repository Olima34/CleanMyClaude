import SwiftUI
import AppKit
import UserNotifications

enum MenuMetric: String, CaseIterable, Identifiable {
    case icon, cpu, memory, cpuMemory, network, disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: return "Icône seule"
        case .cpu: return "Processeur"
        case .memory: return "Mémoire"
        case .cpuMemory: return "Processeur et mémoire"
        case .network: return "Débit réseau"
        case .disk: return "Espace libre"
        }
    }
}

/// What sits in the menu bar: the spark, plus the chosen live metric.
struct MenuBarLabel: View {
    var app: AppModel
    @AppStorage(Preferences.menuMetricKey) private var metric: MenuMetric = .cpuMemory
    /// Built once: a new image on every update makes the status item redraw in a loop.
    private static let icon = ClaudeSpark.templateImage(size: 15)
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let m = app.monitor
        HStack(spacing: 4) {
            Image(nsImage: Self.icon)
            switch metric {
            case .icon:
                EmptyView()
            case .cpu:
                Text("\(Int((m.cpu * 100).rounded())) %").monospacedDigit()
            case .memory:
                Text("\(Int((m.memFraction * 100).rounded())) %").monospacedDigit()
            case .cpuMemory:
                Text("\(Int((m.cpu * 100).rounded()))% · \(Int((m.memFraction * 100).rounded()))%").monospacedDigit()
            case .network:
                Text("↓\(Fmt.speed(m.netIn)) ↑\(Fmt.speed(m.netOut))").monospacedDigit()
            case .disk:
                Text(Fmt.bytes(m.diskFree)).monospacedDigit()
            }
        }
        // This label lives as long as the app: it reopens the main window when asked.
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// The panel that opens from the menu bar.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    var embedded = false
    @State private var status: String?
    @State private var busy: String?

    var body: some View {
        let m = app.monitor
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ClaudeSpark(size: 18)
                Text("Clean My Claude").font(.serif(16)).foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(app.healthColor).frame(width: 7, height: 7)
                    Text("Santé \(app.healthScore)").font(.ui(11, .medium)).foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.card))
            }

            HStack(spacing: 0) {
                mini("Processeur", m.cpu, Fmt.pct(m.cpu), Theme.load(m.cpu))
                mini("Mémoire", m.memFraction, Fmt.pct(m.memFraction), m.pressure == .normal ? Theme.palette[4] : Theme.warn)
                mini("Disque", m.diskUsedFraction, Fmt.bytes(m.diskFree), Theme.load(m.diskUsedFraction), caption: "libres")
                if let b = m.battery {
                    mini(b.isCharging ? "En charge" : "Batterie", b.level, Fmt.pct(b.level), b.level < 0.2 ? Theme.bad : Theme.good)
                } else {
                    mini("Échange", m.swapTotal > 0 ? Double(m.swapUsed) / Double(m.swapTotal) : 0, Fmt.bytes(m.swapUsed), Theme.palette[1])
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(Fmt.speed(m.netIn), systemImage: "arrow.down").foregroundStyle(Theme.accent)
                    Label(Fmt.speed(m.netOut), systemImage: "arrow.up").foregroundStyle(Theme.brand)
                    Spacer()
                    Text("Allumé depuis \(Fmt.duration(m.uptime))").foregroundStyle(Theme.text3)
                }
                .font(.ui(11, .medium))
                .monospacedDigit()
                ZStack {
                    Sparkline(values: m.netInHistory, maxValue: max(m.netInHistory.max() ?? 1, m.netOutHistory.max() ?? 1, 50_000), tint: Theme.accent)
                    Sparkline(values: m.netOutHistory, maxValue: max(m.netInHistory.max() ?? 1, m.netOutHistory.max() ?? 1, 50_000), tint: Theme.brand, fill: false)
                }
                .frame(height: 34)
                Sparkline(values: m.cpuHistory, maxValue: 1, tint: Theme.palette[4])
                    .frame(height: 28)
                    .overlay(alignment: .topLeading) {
                        Text("Processeur").font(.ui(9.5)).foregroundStyle(Theme.text3)
                    }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))

            VStack(alignment: .leading, spacing: 6) {
                Text("Les plus gourmands").font(.ui(11, .semibold)).foregroundStyle(Theme.text3)
                ForEach(app.performance.topByCPU.prefix(4)) { g in
                    HStack(spacing: 8) {
                        if let a = g.appPath { FileIcon(path: a, size: 16) } else {
                            Image(systemName: "gearshape").font(.ui(10)).foregroundStyle(Theme.text3).frame(width: 16, height: 16)
                        }
                        Text(g.name).font(.ui(11.5)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        Text(Fmt.bytes(g.memory)).font(.ui(10.5)).foregroundStyle(Theme.text3).monospacedDigit()
                        Text("\(Fmt.dec(g.cpu)) %").font(.ui(11, .medium)).foregroundStyle(Theme.text2).monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                if app.performance.processes.isEmpty {
                    Text("Lecture…").font(.ui(11)).foregroundStyle(Theme.text3)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                quick("memorychip", "Libérer la RAM", id: "ram") { QuickActions.freeMemory() }
                quick("trash", "Vider la Corbeille", id: "trash") { QuickActions.emptyTrash() }
                quick("network", "Purger le DNS", id: "dns") { QuickActions.flushDNS() }
                Button {
                    openMain(page: .dashboard)
                    Task { await app.smartScan() }
                } label: {
                    quickLabel("wand.and.stars", "Tout analyser", running: app.smartScanRunning)
                }
                .buttonStyle(.plain)
            }
            if let status {
                Text(status).font(.ui(11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }

            if !embedded {
                Divider()
                HStack {
                    Button("Ouvrir Clean My Claude") { openMain(page: nil) }
                        .buttonStyle(SoftButtonStyle(prominent: true))
                    Spacer()
                    Button("Quitter") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.text3)
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.bg)
        .onAppear { app.performance.startSampling() }
        .onDisappear { app.performance.stopSampling() }
    }

    private func mini(_ title: String, _ value: Double, _ text: String, _ tint: Color, caption: String? = nil) -> some View {
        VStack(spacing: 5) {
            ZStack {
                ProgressRing(progress: value, tint: tint, lineWidth: 4.5)
                Text(text).font(.ui(text.count > 5 ? 9 : 11, .semibold)).foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6).lineLimit(1).padding(6).monospacedDigit()
            }
            .frame(width: 54, height: 54)
            Text(caption.map { "\(title) · \($0)" } ?? title).font(.ui(10)).foregroundStyle(Theme.text3).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func quick(_ symbol: String, _ title: String, id: String, action: @escaping () -> String?) -> some View {
        Button {
            guard busy == nil else { return }
            busy = id
            Task.detached {
                let result = action()
                await MainActor.run {
                    busy = nil
                    if let result { status = result }
                    app.monitor.sampleDisk()
                }
            }
        } label: {
            quickLabel(symbol, title, running: busy == id)
        }
        .buttonStyle(.plain)
    }

    private func quickLabel(_ symbol: String, _ title: String, running: Bool) -> some View {
        HStack(spacing: 7) {
            if running { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14) } else {
                Image(systemName: symbol).font(.ui(11.5)).foregroundStyle(Theme.accent).frame(width: 14)
            }
            Text(title).font(.ui(11.5)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .contentShape(Rectangle())
    }

    private func openMain(page: Page?) {
        if let page { app.page = page }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// One-click actions from the menu bar. They return a message to show, or nil when cancelled.
enum QuickActions {
    static func freeMemory() -> String? {
        let r = Shell.runAsAdmin("/usr/sbin/purge")
        if r.ok {
            ActionLog.write("MAINTENANCE purge")
            return "Mémoire inactive libérée."
        }
        return r.err == "Opération annulée." ? nil : "La mémoire n'a pas pu être libérée : \(r.err)"
    }

    static func flushDNS() -> String? {
        let r = Shell.runAsAdmin("dscacheutil -flushcache; killall -HUP mDNSResponder")
        return r.ok ? "Cache DNS vidé." : (r.err == "Opération annulée." ? nil : r.err)
    }

    static func emptyTrash() -> String? {
        let confirmed = DispatchQueue.main.sync { () -> Bool in
            let alert = NSAlert()
            alert.messageText = "Vider la Corbeille ?"
            alert.informativeText = "Les éléments de la Corbeille seront supprimés définitivement."
            alert.addButton(withTitle: "Vider")
            alert.addButton(withTitle: "Annuler")
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn
        }
        guard confirmed else { return nil }
        let trash = FS.home + "/.Trash"
        if FS.canList(trash) {
            let entries = FS.children(trash, hidden: true).filter { $0 != ".DS_Store" }
                .map { RemovalEntry(path: trash + "/" + $0, size: FileSizer.size(of: trash + "/" + $0)) }
            let freed = Remover.remove(entries, mode: .delete).freed
            return freed > 0 ? "Corbeille vidée : \(Fmt.bytes(freed)) libérés." : "La Corbeille était déjà vide."
        }
        // Without Full Disk Access, Finder does it (macOS asks once to allow automation).
        let r = Shell.appleScript("tell application \"Finder\" to empty trash")
        return r.ok ? "Corbeille vidée." : "Impossible de vider la Corbeille : \(r.err)"
    }
}

/// Low disk / memory notifications, at most once every 6 hours each.
@MainActor
enum Alerts {
    private static var last: [String: Date] = [:]

    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func check(_ m: SystemMonitor) {
        guard available, UserDefaults.standard.bool(forKey: Preferences.alertsKey) else { return }
        if m.diskTotal > 0, m.diskUsedFraction > 0.92 {
            post("disk", "Ton disque est presque plein", "Il ne reste que \(Fmt.bytes(m.diskFree)). Un petit nettoyage ?")
        }
        if m.pressure == .critical {
            post("memory", "Mémoire saturée", "macOS manque de mémoire : ferme une app gourmande pour retrouver de la fluidité.")
        }
        if m.thermal == .critical {
            post("thermal", "Ton Mac chauffe", "La température est critique : le processeur est ralenti pour se protéger.")
        }
    }

    private static func post(_ id: String, _ title: String, _ body: String) {
        if let d = last[id], Date().timeIntervalSince(d) < 6 * 3600 { return }
        last[id] = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id + UUID().uuidString, content: content, trigger: nil))
    }
}
