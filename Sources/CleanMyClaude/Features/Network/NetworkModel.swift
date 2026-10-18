import SwiftUI
import AppKit

enum NetworkTab: String, CaseIterable, Identifiable {
    case connection, speed, ports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return "Connexion"
        case .speed: return "Débit et latence"
        case .ports: return "Ports ouverts"
        }
    }
}

enum NetworkState: Equatable {
    case idle, running, done(Date), failed(String)

    var isRunning: Bool { self == .running }
    var date: Date? {
        if case .done(let d) = self { return d }
        return nil
    }
}

@Observable
@MainActor
final class NetworkModel: AppModule {
    static let publicIPService = "api.ipify.org"
    static let internetHost = "1.1.1.1"

    var tab: NetworkTab = .connection

    // Connection (read locally)
    var addresses = NetworkAddresses()
    var wifi: NetworkWiFi?
    /// Connected, but macOS hides the network name until the location permission is given.
    var wifiNameHidden = false
    var publicIP: String?
    var publicIPState: NetworkState = .idle

    // Speed test
    var speedState: NetworkState = .idle
    var speedStarted: Date?
    var speedProgress: Double = 0
    var history: [NetworkSpeedResult] {
        didSet { store.value = history }
    }
    var lastSpeed: NetworkSpeedResult? { history.last }

    // Latency
    var pingInternet = NetworkPingStats()
    var pingRouter = NetworkPingStats()
    var pingRouterHost: String?
    var pingState: NetworkState = .idle

    // Ports
    var ports: [NetworkPort] = []
    var portsState: NetworkState = .idle
    var portsIncludeSystem = false

    @ObservationIgnored private let store = JSONStore<[NetworkSpeedResult]>("network-speedtests", default: [])
    @ObservationIgnored private var liveTimer: Timer?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var speedCancel: CancelFlag?
    @ObservationIgnored private var addressesRead = Date.distantPast

    init() {
        history = store.value
        // Real-data snapshots render before any onAppear: read the local state now.
        if Snapshot.isActive && !DemoData.isEnabled { refreshLocal() }
    }

    var sidebarBadge: String? { speedState.isRunning ? "test…" : nil }

    // MARK: Connection

    /// Reads Wi-Fi and addresses (local calls, no network).
    func refreshLocal() {
        guard !DemoData.isEnabled else { return }
        addresses = NetworkLocal.read()
        addressesRead = Date()
        wifi = NetworkWiFi.read()
        wifiNameHidden = wifi.map { $0.connected && $0.ssid == nil } == true && !AppPermission.location.isGranted
    }

    /// Refreshes the connection tab every 3 seconds while it is on screen.
    func startLive() {
        refreshLocal()
        guard !DemoData.isEnabled, !Snapshot.isActive, liveTimer == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLocal() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        liveTimer = t
    }

    func stopLive() {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    /// Asks the public address to the service named in the interface, only after a click.
    func fetchPublicIP() async -> String? {
        guard !DemoData.isEnabled else { return publicIP }
        guard !publicIPState.isRunning, let url = URL(string: "https://\(Self.publicIPService)/?format=json") else { return publicIP }
        publicIPState = .running
        do {
            let (data, _) = try await HTTP.get(url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let ip = json?["ip"] as? String, !ip.isEmpty else { throw HTTP.Failure.empty }
            publicIP = ip
            publicIPState = .done(Date())
            return ip
        } catch {
            publicIPState = .failed("\(Self.publicIPService) n'a pas répondu.")
            return nil
        }
    }

    // MARK: Speed test

    func runSpeedTest() {
        guard !DemoData.isEnabled, !speedState.isRunning else { return }
        let cancel = CancelFlag()
        speedCancel = cancel
        speedState = .running
        speedStarted = Date()
        speedProgress = 0
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.speedStarted else { return }
                self.speedProgress = min(0.97, Date().timeIntervalSince(start) / NetworkSpeed.duration)
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        progressTimer = t
        ActionLog.write("RÉSEAU networkQuality (serveurs de test d'Apple)")
        Task {
            let out = await Task.detached(priority: .userInitiated) {
                Shell.stream("/usr/bin/networkQuality", ["-c"], isCancelled: { cancel.isCancelled }) { _ in }
            }.value
            progressTimer?.invalidate()
            progressTimer = nil
            speedCancel = nil
            speedStarted = nil
            if cancel.isCancelled {
                speedState = .idle
                return
            }
            switch NetworkSpeed.parse(out.out) {
            case .success(let r):
                history.append(r)
                if history.count > 60 { history.removeFirst(history.count - 60) }
                speedState = .done(r.date)
                if NSApp?.isActive != true {
                    Notifier.post(id: "network-speed", title: "Test de débit terminé",
                                  body: "↓ \(NetworkFormat.bits(r.download)) · ↑ \(NetworkFormat.bits(r.upload))", throttle: 0)
                }
            case .failure(let f):
                speedState = .failed(f.message)
            }
        }
    }

    /// networkQuality stays silent until it is done: it is stopped directly (only our own child of that name).
    func cancelSpeedTest() {
        guard let cancel = speedCancel else { return }
        cancel.cancel()
        let me = getpid()
        Task.detached {
            _ = Shell.run("/usr/bin/pkill", ["-TERM", "-P", "\(me)", "-x", "networkQuality"], timeout: 5)
        }
    }

    func clearHistory() {
        history = []
        if case .done = speedState { speedState = .idle }
    }

    // MARK: Latency

    func runPing() {
        guard !DemoData.isEnabled, !pingState.isRunning else { return }
        refreshLocal()
        let router = addresses.router
        pingRouterHost = router
        pingInternet = NetworkPingStats()
        pingRouter = NetworkPingStats()
        pingState = .running
        ActionLog.write("RÉSEAU ping \(Self.internetHost)\(router.map { " et \($0)" } ?? "")")
        Task {
            async let internet: Void = ping(Self.internetHost, router: false)
            if let router { await ping(router, router: true) }
            await internet
            pingState = .done(Date())
        }
    }

    /// Five pings, each shown as it comes back.
    private func ping(_ host: String, router: Bool) async {
        let buffer = NetworkLineBuffer { [weak self] lines in
            guard let self else { return }
            let samples = lines.compactMap(NetworkPing.sample)
            if router { self.pingRouter.samples += samples } else { self.pingInternet.samples += samples }
        }
        let out = await Task.detached(priority: .userInitiated) {
            Shell.stream("/sbin/ping", ["-c", "5", "-t", "12", host]) { buffer.append($0) }
        }.value
        buffer.flush()
        var stats = router ? pingRouter : pingInternet
        NetworkPing.summary(out.out, into: &stats)
        if router { pingRouter = stats } else { pingInternet = stats }
    }

    // MARK: Ports

    func scanPorts(admin: Bool = false) async {
        guard !DemoData.isEnabled, !portsState.isRunning else { return }
        let previous = portsState
        portsState = .running
        let result = await Task.detached(priority: .userInitiated) { NetworkPorts.scan(admin: admin) }.value
        switch result {
        case .success(let list):
            ports = list
            portsIncludeSystem = admin
            portsState = .done(Date())
        case .failure(let f):
            // Closing the password dialog keeps the list as it was.
            portsState = admin && f.message.contains("annulée") ? previous : .failed(f.message)
        }
    }

    /// Quits the app behind a port (or stops a command line process of this user).
    func quit(_ p: NetworkPort) {
        guard !DemoData.isEnabled else { return HUD.show(DemoData.refusal) }
        guard !p.isSystem else { return }
        var ok = false
        if let path = p.appPath,
           let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == path }) {
            ok = running.terminate()
        } else if !p.isSystem {
            ok = kill(p.pid, SIGTERM) == 0
        }
        ActionLog.write("PORT \(p.port) : arrêt de \(p.displayName) (pid \(p.pid)) \(ok ? "demandé" : "refusé")")
        HUD.show(ok ? "\(p.displayName) va se fermer" : "Impossible d'arrêter \(p.displayName)",
                 symbol: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
        guard ok else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if portsIncludeSystem {
                // Rescanning would ask for the password again: the closed ports are just taken off the list.
                ports.removeAll { $0.pid == p.pid || ($0.appPath != nil && $0.appPath == p.appPath) }
            } else {
                await scanPorts()
            }
        }
    }

    // MARK: AppModule

    func applySnapshotTab(_ tab: String) {
        if let t = NetworkTab(rawValue: tab) { self.tab = t }
    }

    func loadDemo() {
        addresses = NetworkDemo.addresses
        wifi = NetworkDemo.wifi
        publicIP = "203.0.113.57"
        publicIPState = .done(Date().addingTimeInterval(-300))
        history = NetworkDemo.history
        speedState = .done(NetworkDemo.history.last?.date ?? Date())
        pingInternet = NetworkPingStats(samples: [14.2, 12.8, 13.5, 19.1, 13.0], sent: 5, received: 5, average: 14.5, jitter: 2.3)
        pingRouter = NetworkPingStats(samples: [3.1, 2.4, 2.9, 2.6, 4.8], sent: 5, received: 5, average: 3.2, jitter: 0.9)
        pingRouterHost = NetworkDemo.addresses.router
        pingState = .done(Date().addingTimeInterval(-120))
        ports = NetworkDemo.ports
        portsState = .done(Date().addingTimeInterval(-60))
    }

    func commands(app: AppModel) -> [AppCommand] {
        [
            AppCommand(id: "net_speedtest", title: "Tester mon débit", subtitle: "≈ 20 s avec l'outil networkQuality d'Apple",
                       keywords: ["speedtest", "débit", "vitesse", "internet", "connexion", "fibre"],
                       icon: .symbol("speedometer", Theme.palette[1]), group: .tools, assistantSafe: true) { ctx in
                ctx.app.page = .network
                ctx.app.network.tab = .speed
                AppContext.showMainWindow()
                ctx.app.network.runSpeedTest()
                return .done
            },
            AppCommand(id: "net_public_ip", title: "Mon adresse IP publique",
                       subtitle: publicIP.map { "Dernière vue : \($0) · Entrée pour la redemander à \(Self.publicIPService)" }
                           ?? "Demandée à \(Self.publicIPService), puis copiée",
                       keywords: ["ip", "adresse ip", "ip publique", "public ip", "what is my ip"],
                       icon: .symbol("globe", Theme.palette[1]), group: .tools, hint: "Copier") { ctx in
                guard let ip = await ctx.app.network.fetchPublicIP() else {
                    return .failed("\(Self.publicIPService) n'a pas répondu.")
                }
                return CommandRunner.copy(ip)
            },
            AppCommand(id: "net_local_ip", title: "Mon adresse IP locale", subtitle: "Sur le réseau de la maison ou du bureau",
                       keywords: ["ip", "ip locale", "local ip", "adresse"], icon: .symbol("network", Theme.palette[1]), group: .tools,
                       assistantSafe: true, hint: "Copier") { ctx in
                let a = DemoData.isEnabled ? NetworkDemo.addresses : NetworkLocal.read()
                guard let ip = a.localIP else { return .failed("Aucune adresse : ce Mac n'est relié à aucun réseau.") }
                return CommandRunner.copy(ip)
            },
            AppCommand(id: "net_ports", title: "Ports ouverts", subtitle: "Les programmes qui attendent des connexions",
                       keywords: ["ports", "lsof", "écoute", "listen", "serveur"], icon: .symbol("door.left.hand.open", Theme.palette[1]),
                       group: .tools, assistantSafe: true) { ctx in
                ctx.app.page = .network
                ctx.app.network.tab = .ports
                AppContext.showMainWindow()
                Task { await ctx.app.network.scanPorts() }
                return .done
            },
            AppCommand(id: "net_wifi", title: "Signal Wi-Fi", subtitle: "Force du signal, canal, débit de liaison",
                       keywords: ["wifi", "wi-fi", "signal", "réseau", "canal"], icon: .symbol("wifi", Theme.palette[1]), group: .tools,
                       assistantSafe: true) { ctx in
                ctx.app.page = .network
                ctx.app.network.tab = .connection
                AppContext.showMainWindow()
                return .done
            }
        ]
    }

    /// Typing "ip" shows the local addresses and the router at once (no network). The public one is the "net_public_ip" command.
    func results(for query: String, app: AppModel) -> [AppCommand] {
        let words = Fuzzy.fold(query).split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard words.contains(where: { ["ip", "ipv4", "ipv6", "ips"].contains($0) }) else { return [] }
        if !DemoData.isEnabled, Date().timeIntervalSince(addressesRead) > 5 {
            addresses = NetworkLocal.read()
            addressesRead = Date()
        }
        var out: [AppCommand] = []
        for (n, i) in addresses.interfaces.prefix(3).enumerated() {
            guard let ip = i.ipv4.first ?? i.ipv6.first else { continue }
            out.append(AppCommand(id: "net_ip_\(n)", title: ip, subtitle: "IP locale · \(i.displayName) (\(i.bsdName))",
                                  icon: .symbol("network", Theme.palette[1]), group: .tools, hint: "Copier", boost: 420 - Double(n)) { _ in
                CommandRunner.copy(ip)
            })
        }
        if let r = addresses.router {
            out.append(AppCommand(id: "net_ip_router", title: r, subtitle: "Routeur (ta box)", icon: .symbol("wifi.router", Theme.palette[1]),
                                  group: .tools, hint: "Copier", boost: 380) { _ in CommandRunner.copy(r) })
        }
        return out
    }

    func selfTest() -> [String] {
        var f: [String] = []
        // networkQuality -c, trimmed (the real output also has long latency arrays).
        let nq = """
        {"base_rtt" : 28.745285034179688, "dl_flows" : 6, "dl_throughput" : 398943040, "interface_name" : "en0",
         "il_h2_req_resp" : [19.2, 26.3], "responsiveness" : 421.6928405761719, "test_endpoint" : "exemple.aaplimg.com",
         "ul_throughput" : 377616768, "other" : {"interface-type" : {"wifi" : 447}}}
        """
        switch NetworkSpeed.parse("networkQuality: avertissement\n" + nq) {
        case .success(let r):
            if Int(r.download) != 398_943_040 || Int(r.upload) != 377_616_768 { f.append("Débit : valeurs mal lues") }
            if r.rating != .medium { f.append("Débit : réactivité de 421 RPM mal classée") }
            if NetworkFormat.bits(r.download) != "399 Mbit/s" { f.append("Débit : affichage \(NetworkFormat.bits(r.download))") }
        case .failure(let e): f.append("Débit : sortie de networkQuality illisible (\(e.message))")
        }
        if case .success = NetworkSpeed.parse(#"{"error_code" : -1009, "error_domain" : "NSURLErrorDomain"}"#) {
            f.append("Débit : une erreur passe pour un résultat")
        }
        if NetworkFormat.bits(1.25e9) != "1,2 Gbit/s" && NetworkFormat.bits(1.25e9) != "1,3 Gbit/s" { f.append("Débit : affichage en Gbit/s") }

        let lsof = "p991\ncrapportd\nLcamille\nf17\nn*:57495\nf18\nn*:57495\np67624\ncmysqld\nLcamille\nf17\nn127.0.0.1:3306\n" +
            "p500\ncnode\nLcamille\nf20\nn[::1]:5173\nf21\nn127.0.0.1:5173\np88\ncsshd\nLroot\nf3\nn[::]:22\n"
        let ports = NetworkPorts.parse(lsof)
        if ports.count != 4 { f.append("Ports : \(ports.count) lus au lieu de 4 (IPv4 et IPv6 fusionnés)") }
        if ports.first?.port != 22 || ports.first?.user != "root" { f.append("Ports : tri ou utilisateur") }
        if let node = ports.first(where: { $0.port == 5173 }) {
            if node.isExposed || node.addresses.count != 2 { f.append("Ports : 5173 n'écoute que ce Mac") }
        } else {
            f.append("Ports : 5173 manquant")
        }
        if ports.first(where: { $0.port == 57495 })?.isExposed != true { f.append("Ports : « * » est visible sur le réseau") }
        if NetworkPorts.appBundle(inPath: "/Applications/Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper") != "/Applications/Code.app" {
            f.append("Ports : app propriétaire d'un processus d'aide")
        }
        if NetworkPorts.appBundle(inPath: "/usr/libexec/rapportd") != nil { f.append("Ports : un outil système pris pour une app") }
        var rapportd = NetworkPort(port: 57495, pid: 991, process: "rapportd", user: nil, addresses: ["*"], executable: "/usr/libexec/rapportd")
        var brewServer = NetworkPort(port: 5432, pid: 812, process: "postgres", user: nil, addresses: ["127.0.0.1"],
                                     executable: "/usr/local/opt/postgresql@17/bin/postgres")
        if !rapportd.isSystem || brewServer.isSystem { f.append("Ports : services de macOS mal reconnus") }
        rapportd.user = "root"
        brewServer.user = "root"
        if !brewServer.isSystem { f.append("Ports : un service d'un autre utilisateur proposé à l'arrêt") }

        if NetworkPing.sample("64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.345 ms") != 12.345 { f.append("Latence : ligne de ping") }
        if NetworkPing.sample("Request timeout for icmp_seq 1") != nil { f.append("Latence : délai dépassé compté comme mesure") }
        var stats = NetworkPingStats(samples: [12, 14])
        NetworkPing.summary("""
        --- 1.1.1.1 ping statistics ---
        5 packets transmitted, 4 packets received, 20.0% packet loss
        round-trip min/avg/max/stddev = 11.100/12.250/13.300/0.800 ms
        """, into: &stats)
        if stats.sent != 5 || stats.received != 4 || stats.average != 12.25 || stats.jitter != 0.8 || abs(stats.loss - 0.2) > 0.001 {
            f.append("Latence : résumé de ping mal lu")
        }

        if NetworkWiFi.label(rssi: -45) != "Excellent" || NetworkWiFi.label(rssi: -66) != "Bon" || NetworkWiFi.label(rssi: -80) != "Faible" {
            f.append("Wi-Fi : qualité du signal")
        }
        if !NetworkPorts.isLoopback("[::1]") || NetworkPorts.isLoopback("*") || NetworkPorts.isLoopback("192.168.1.4") {
            f.append("Ports : adresses locales")
        }
        return f
    }

    func dump() -> [String] {
        var lines: [String] = []
        let a = DemoData.isEnabled ? NetworkDemo.addresses : NetworkLocal.read()
        for i in a.interfaces {
            lines.append("\(i.displayName) (\(i.bsdName))\(i.isPrimary ? " · principale" : "") : \((i.ipv4 + i.ipv6).joined(separator: ", "))")
        }
        lines.append("Routeur : \(a.router ?? "—") · DNS : \(a.dns.joined(separator: ", "))")
        if let w = DemoData.isEnabled ? NetworkDemo.wifi : NetworkWiFi.read() {
            lines.append("Wi-Fi \(w.interface) : \(w.ssid ?? "nom masqué par macOS") · \(w.rssi) dBm (\(w.signalLabel)) · bruit \(w.noise) dBm · canal \(w.channel.map(String.init) ?? "?") \(w.band ?? "?") GHz \(w.width.map { "\($0) MHz" } ?? "") · \(Fmt.int(w.txRate)) Mbit/s · \(w.security) · \(w.phy)")
        } else {
            lines.append("Wi-Fi : aucune interface")
        }
        let ports = DemoData.isEnabled ? NetworkDemo.ports : ((try? NetworkPorts.scan().get()) ?? [])
        lines.append("Ports ouverts (\(ports.count), services système exclus) :")
        for p in ports {
            lines.append("    \(p.port)\t\(p.displayName) (pid \(p.pid))\t\(p.addresses.joined(separator: " "))\(p.isExposed ? " · visible sur le réseau" : "")")
        }
        if let last = history.last {
            lines.append("Dernier test : ↓ \(NetworkFormat.bits(last.download)) ↑ \(NetworkFormat.bits(last.upload)) · \(Int(last.responsiveness ?? 0)) RPM · \(Fmt.day(last.date))")
        }
        lines.append("(débit, latence et IP publique ne sont mesurés que sur un clic dans l'app)")
        return lines
    }
}

// MARK: - Demo

/// A made-up home network for `--demo` (documentation addresses, invented apps and ports).
enum NetworkDemo {
    static let addresses = NetworkAddresses(
        interfaces: [
            NetworkInterface(bsdName: "en0", displayName: "Wi-Fi", ipv4: ["10.0.1.42"], ipv6: ["2001:db8:4c1a::42"], isPrimary: true),
            NetworkInterface(bsdName: "utun4", displayName: "VPN", ipv4: ["10.8.0.3"])
        ],
        router: "10.0.1.1", dns: ["10.0.1.1", "2001:db8:4c1a::1"], searchDomains: ["maison"])

    static let wifi = NetworkWiFi(interface: "en0", powerOn: true, ssid: "Maison Camille", connected: true, rssi: -54, noise: -92,
                                  channel: 36, band: "5", width: 80, txRate: 864, security: "WPA3 Personnel",
                                  phy: "Wi-Fi 6 (802.11ax)", country: "FR")

    static let history: [NetworkSpeedResult] = {
        let downs: [Double] = [312, 344, 298, 401, 377, 365, 152, 389, 412, 356, 398, 421, 386, 405]
        let ups: [Double] = [281, 290, 265, 330, 318, 301, 120, 322, 340, 297, 335, 351, 329, 344]
        let rpm: [Double] = [610, 702, 540, 880, 790, 760, 210, 840, 910, 700, 860, 1040, 820, 930]
        let now = Date()
        return downs.indices.map { i in
            NetworkSpeedResult(date: now.addingTimeInterval(-Double(downs.count - 1 - i) * 2.3 * 86400 - 3600),
                               download: downs[i] * 1e6, upload: ups[i] * 1e6, responsiveness: rpm[i], baseRTT: 12 + Double(i % 4) * 2.5,
                               interface: "en0", server: "test.exemple")
        }
    }()

    static let ports: [NetworkPort] = [
        NetworkPort(port: 5173, pid: 4211, process: "node", user: "camille", addresses: ["127.0.0.1", "[::1]"],
                    appPath: "/Applications/Hélios Code.app"),
        NetworkPort(port: 5432, pid: 812, process: "postgres", user: "camille", addresses: ["127.0.0.1"]),
        NetworkPort(port: 8000, pid: 5120, process: "python3", user: "camille", addresses: ["*"]),
        NetworkPort(port: 17600, pid: 1377, process: "Nuage Drive", user: "camille", addresses: ["127.0.0.1"],
                    appPath: "/Applications/Nuage Drive.app"),
        NetworkPort(port: 31415, pid: 2290, process: "Cadence Studio", user: "camille", addresses: ["*"],
                    appPath: "/Applications/Cadence Studio.app"),
        NetworkPort(port: 45112, pid: 1502, process: "Ruche Helper", user: "camille", addresses: ["127.0.0.1"],
                    appPath: "/Applications/Ruche.app")
    ]
}
