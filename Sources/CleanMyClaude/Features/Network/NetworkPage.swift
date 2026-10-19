import SwiftUI
import AppKit
import Charts

struct NetworkPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.network
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "network", title: "Réseau",
                     subtitle: "Ta connexion à la loupe : Wi-Fi, adresses, débit, latence et ports ouverts. Les mesures sur Internet ne partent que sur ton clic.",
                     tint: Theme.palette[1], seed: 61)
            PillPicker(options: NetworkTab.allCases, selection: $m.tab, label: { $0.title }, badge: { tab in
                tab == .ports && m.portsState.date != nil ? "\(m.ports.count)" : (tab == .speed && m.speedState.isRunning ? "…" : nil)
            })
            switch m.tab {
            case .connection: NetworkConnectionTab()
            case .speed: NetworkSpeedTab()
            case .ports: NetworkPortsTab()
            }
        }
    }
}

// MARK: - Connection

private struct NetworkConnectionTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.network
        let mon = app.monitor
        VStack(alignment: .leading, spacing: 14) {
            TileRow {
                StatTile(symbol: "arrow.down", value: Fmt.speed(mon.netIn), label: "Réception", detail: "En ce moment, toutes apps confondues",
                         tint: Theme.palette[1])
                StatTile(symbol: "arrow.up", value: Fmt.speed(mon.netOut), label: "Envoi", detail: "En ce moment, toutes apps confondues",
                         tint: Theme.palette[4])
                StatTile(symbol: "wifi", value: m.wifi?.connected == true ? "\(m.wifi!.rssi) dBm" : "—", label: "Signal Wi-Fi",
                         detail: m.wifi.map { $0.connected ? "\($0.signalLabel) · \(Fmt.int($0.txRate)) Mbit/s de liaison" : ($0.powerOn ? "Pas connecté" : "Wi-Fi éteint") } ?? "Pas de Wi-Fi",
                         tint: m.wifi.map { $0.rssi >= -67 ? Theme.good : Theme.warn } ?? Theme.text3)
                StatTile(symbol: "speedometer", value: m.lastSpeed.map { NetworkFormat.bits($0.download) } ?? "—", label: "Dernier test de débit",
                         detail: m.lastSpeed.map { "↑ \(NetworkFormat.bits($0.upload)) · \(Fmt.relative($0.date))" } ?? "Lance-le dans « Débit et latence »",
                         tint: Theme.accent)
            }
            TileRow {
                NetworkWiFiPanel()
                NetworkAddressesPanel()
            }
            if m.wifiNameHidden {
                PermissionCard(permission: .location,
                               reason: "macOS ne donne le nom du réseau Wi-Fi qu'aux apps autorisées à utiliser la localisation. Clean My Claude ne lit ni n'enregistre ta position.")
            }
            NetworkTrafficPanel()
        }
        .onAppear { m.startLive() }
        .onDisappear { m.stopLive() }
    }
}

private struct NetworkWiFiPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.network
        Panel(title: "Wi-Fi", subtitle: m.wifi.map { "Interface \($0.interface)\($0.country.map { " · pays \($0)" } ?? "")" },
              symbol: "wifi", tint: Theme.palette[1]) {
            if let w = m.wifi, w.connected {
                Tag(text: w.ssid ?? "nom masqué par macOS", symbol: w.ssid == nil ? "eye.slash" : "wifi", tint: Theme.palette[1], filled: true)
            }
        } content: {
            if let w = m.wifi, w.connected {
                HStack(alignment: .center, spacing: 16) {
                    Gauge(value: w.signalFraction, text: "\(w.rssi)", caption: "dBm", tint: w.rssi >= -67 ? Theme.good : Theme.warn, size: 76, lineWidth: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signal \(w.signalLabel.lowercased())").font(.serif(19)).foregroundStyle(Theme.text)
                        Text("Rapport signal/bruit : \(w.snr) dB\(w.snr >= 25 ? ", confortable" : ", un peu juste")")
                            .font(.ui(11.5)).foregroundStyle(Theme.text3)
                    }
                }
                VStack(spacing: 0) {
                    NetworkInfoRow(label: "Canal", value: [w.channel.map { "\($0)" }, w.band.map { "\($0) GHz" }, w.width.map { "\($0) MHz" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    NetworkInfoRow(label: "Débit de liaison", value: "\(Fmt.int(w.txRate)) Mbit/s")
                    NetworkInfoRow(label: "Bruit", value: "\(w.noise) dBm")
                    NetworkInfoRow(label: "Sécurité", value: w.security, warn: w.security.hasPrefix("Ouvert") || w.security.hasPrefix("WEP"))
                    NetworkInfoRow(label: "Norme", value: w.phy, last: true)
                }
            } else {
                EmptyHint(text: m.wifi == nil ? "Ce Mac n'a pas d'interface Wi-Fi." : (m.wifi!.powerOn ? "Le Wi-Fi n'est connecté à aucun réseau." : "Le Wi-Fi est éteint."),
                          symbol: "wifi.slash")
            }
        }
    }
}

private struct NetworkAddressesPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.network
        let a = m.addresses
        Panel(title: "Adresses", subtitle: "Ce que ce Mac montre au réseau local, et à Internet sur demande.", symbol: "point.3.connected.trianglepath.dotted",
              tint: Theme.palette[1]) {
            VStack(spacing: 0) {
                ForEach(a.interfaces) { i in
                    NetworkInfoRow(label: i.displayName, detail: i.bsdName + (i.isPrimary ? " · principale" : ""),
                                   value: i.ipv4.first ?? i.ipv6.first ?? "—", secondary: i.ipv4.isEmpty ? nil : i.ipv6.first, copyable: true)
                }
                if a.interfaces.isEmpty {
                    NetworkInfoRow(label: "Réseau", value: "Aucune connexion")
                }
                NetworkInfoRow(label: "Routeur", detail: "ta box", value: a.router ?? "—", copyable: a.router != nil)
                NetworkInfoRow(label: "DNS", value: a.dns.isEmpty ? "—" : a.dns.prefix(2).joined(separator: "\n"), copyable: !a.dns.isEmpty, last: true)
            }
            HStack(spacing: 10) {
                IconBadge(symbol: "globe", tint: Theme.palette[1], size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("IP publique").font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                    Text(publicCaption(m)).font(.ui(10.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let ip = m.publicIP {
                    NetworkCopyText(text: ip, font: .mono(13, .medium))
                }
                Button(m.publicIP == nil ? "Afficher" : "Redemander") { Task { await m.fetchPublicIP() } }
                    .buttonStyle(SoftButtonStyle(prominent: m.publicIP == nil, small: true))
                    .disabled(m.publicIPState.isRunning)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.r(10), style: .continuous).fill(Theme.track.opacity(0.5)))
        }
    }

    private func publicCaption(_ m: NetworkModel) -> String {
        switch m.publicIPState {
        case .running: return "Question posée à \(NetworkModel.publicIPService)…"
        case .failed(let why): return why
        case .done(let d): return "Vue par \(NetworkModel.publicIPService) \(Fmt.relative(d))"
        case .idle: return "Demandée à \(NetworkModel.publicIPService), seulement quand tu cliques."
        }
    }
}

private struct NetworkTrafficPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let mon = app.monitor
        Panel(title: "Trafic en direct", subtitle: "Les deux dernières minutes, mesurées par macOS sur toutes les interfaces.", symbol: "waveform.path.ecg",
              tint: Theme.palette[1]) {
            HStack(spacing: 14) {
                LegendDot(color: Theme.palette[1], label: "Réception", value: Fmt.speed(mon.netIn))
                LegendDot(color: Theme.palette[4], label: "Envoi", value: Fmt.speed(mon.netOut))
            }
        } content: {
            NetworkTrafficChart(down: mon.netInHistory, up: mon.netOutHistory)
                .frame(height: 130)
            HStack(spacing: 18) {
                Text("Depuis le démarrage : ↓ \(Fmt.bytes(mon.netTotalIn)) · ↑ \(Fmt.bytes(mon.netTotalOut))")
                    .font(.ui(11)).foregroundStyle(Theme.text3)
            }
        }
    }
}

private struct NetworkTrafficChart: View {
    var down: [Double]
    var up: [Double]

    var body: some View {
        let shift = max(0, SystemMonitor.historyLength - down.count)
        let top = max(1, (down + up).max() ?? 1) * 1.15
        Chart {
            ForEach(Array(down.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("t", i + shift), y: .value("o/s", v), series: .value("sens", "Réception"))
                    .foregroundStyle(LinearGradient(colors: [Theme.palette[1].opacity(0.3), Theme.palette[1].opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", i + shift), y: .value("o/s", v), series: .value("sens", "Réception"))
                    .foregroundStyle(Theme.palette[1])
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(up.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("t", i + shift), y: .value("o/s", v), series: .value("sens", "Envoi"))
                    .foregroundStyle(Theme.palette[4])
                    .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: 0...max(1, SystemMonitor.historyLength - 1))
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, top / 2, top]) { v in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel { Text(Fmt.speed(v.as(Double.self) ?? 0)).font(.ui(9.5)).foregroundStyle(Theme.text3) }
            }
        }
    }
}

// MARK: - Speed and latency

private struct NetworkSpeedTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NetworkSpeedPanel()
            TileRow {
                NetworkHistoryPanel()
                NetworkLatencyPanel()
            }
        }
    }
}

private struct NetworkSpeedPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.network
        Panel(title: "Test de débit", subtitle: "Mesuré par networkQuality, l'outil intégré à macOS, sur les serveurs de test d'Apple (environ 20 secondes).",
              symbol: "speedometer", tint: Theme.accent) {
            if m.speedState.isRunning {
                Button("Annuler") { m.cancelSpeedTest() }.buttonStyle(SoftButtonStyle(small: true))
            } else {
                ScanButton(title: m.lastSpeed == nil ? "Lancer le test" : "Relancer le test", symbol: "play.fill") { m.runSpeedTest() }
            }
        } content: {
            if m.speedState.isRunning {
                running(m)
            } else if let r = m.lastSpeed {
                NetworkSpeedResultView(result: r)
            } else {
                EmptyHint(text: "Aucun test pour l'instant. Pendant la mesure, ta connexion est saturée une vingtaine de secondes.", symbol: "speedometer")
            }
            if case .failed(let why) = m.speedState {
                Callout(symbol: "exclamationmark.triangle", title: "Le test n'a pas abouti", text: why, tint: Theme.warn)
            }
        }
    }

    private func running(_ m: NetworkModel) -> some View {
        let mon = app.monitor
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NetworkSpinner()
                Text("Mesure en cours…").font(.serif(19)).foregroundStyle(Theme.text)
                Spacer()
                Text("↓ \(Fmt.speed(mon.netIn))   ↑ \(Fmt.speed(mon.netOut))").font(.mono(12)).foregroundStyle(Theme.text2)
            }
            UsageBar(fraction: m.speedProgress, tint: Theme.accent, height: 8)
            Text("networkQuality envoie et reçoit en même temps pour remplir ta ligne. Les autres usages du réseau sont ralentis pendant le test.")
                .font(.ui(11.5)).foregroundStyle(Theme.text3)
        }
    }
}

private struct NetworkSpeedResultView: View {
    var result: NetworkSpeedResult

    var body: some View {
        let r = result
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                metric("arrow.down.circle.fill", "Réception", NetworkFormat.bits(r.download), Theme.palette[1])
                metric("arrow.up.circle.fill", "Envoi", NetworkFormat.bits(r.upload), Theme.palette[4])
                if let rpm = r.responsiveness {
                    metric("bolt.horizontal.circle.fill", "Réactivité sous charge", "\(Fmt.int(rpm)) RPM", ratingColor(r.rating),
                           detail: "\(ratingLabel(r.rating)) · \(NetworkFormat.ms(60_000 / max(1, rpm))) par aller-retour")
                }
                if let rtt = r.baseRTT {
                    metric("timer", "Latence au repos", NetworkFormat.ms(rtt), Theme.palette[2])
                }
            }
            HStack(spacing: 8) {
                ForEach(NetworkSpeed.uses(download: r.download), id: \.1) { symbol, label, ok in
                    Tag(text: label, symbol: ok ? "checkmark" : "xmark", tint: ok ? Theme.good : Theme.text3, filled: ok)
                }
                Spacer()
                Text("Testé \(Fmt.relative(r.date))\(r.interface.map { " via \($0)" } ?? "")")
                    .font(.ui(11)).foregroundStyle(Theme.text3)
            }
        }
    }

    private func metric(_ symbol: String, _ label: String, _ value: String, _ tint: Color, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(label).font(.ui(11.5)).foregroundStyle(Theme.text2)
            }
            Text(value).font(.serif(28)).foregroundStyle(Theme.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.ui(11)).foregroundStyle(Theme.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ratingLabel(_ r: NetworkSpeedResult.Rating?) -> String {
        switch r {
        case .high: return "Élevée"
        case .medium: return "Moyenne"
        case .low: return "Faible"
        case nil: return "—"
        }
    }

    private func ratingColor(_ r: NetworkSpeedResult.Rating?) -> Color {
        switch r {
        case .high: return Theme.good
        case .medium: return Theme.accent
        case .low, nil: return Theme.warn
        }
    }
}

private struct NetworkHistoryPanel: View {
    @Environment(AppModel.self) private var app
    @State private var confirmClear = false

    var body: some View {
        let m = app.network
        let tests = Array(m.history.suffix(20))
        Panel(title: "Historique", subtitle: tests.isEmpty ? "Tes tests s'afficheront ici." : "\(Fmt.plural(m.history.count, "test gardé", "tests gardés")) sur ce Mac.",
              symbol: "chart.xyaxis.line", tint: Theme.accent) {
            if !m.history.isEmpty {
                Button("Effacer") { confirmClear = true }.buttonStyle(SoftButtonStyle(small: true))
            }
        } content: {
            if tests.count < 2 {
                EmptyHint(text: "Lance au moins deux tests pour voir l'évolution de ta connexion.", symbol: "chart.xyaxis.line")
            } else {
                Chart {
                    ForEach(tests) { t in
                        LineMark(x: .value("Date", t.date), y: .value("Mbit/s", t.download / 1e6), series: .value("Sens", "Réception"))
                            .foregroundStyle(Theme.palette[1])
                            .symbol(Circle().strokeBorder(lineWidth: 1.5))
                            .symbolSize(22)
                        LineMark(x: .value("Date", t.date), y: .value("Mbit/s", t.upload / 1e6), series: .value("Sens", "Envoi"))
                            .foregroundStyle(Theme.palette[4])
                            .symbol(Circle().strokeBorder(lineWidth: 1.5))
                            .symbolSize(22)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Theme.border)
                        AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))").font(.ui(9.5)).foregroundStyle(Theme.text3) }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisValueLabel { Text(v.as(Date.self).map { Fmt.day($0) } ?? "").font(.ui(9.5)).foregroundStyle(Theme.text3) }
                    }
                }
                .frame(height: 150)
                HStack(spacing: 14) {
                    LegendDot(color: Theme.palette[1], label: "Réception", value: "Mbit/s")
                    LegendDot(color: Theme.palette[4], label: "Envoi", value: "Mbit/s")
                    Spacer()
                    if let best = m.history.max(by: { $0.download < $1.download }) {
                        Text("Record : \(NetworkFormat.bits(best.download))").font(.ui(11)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
        .confirmAction("Effacer l'historique des tests ?",
                       message: m.history.count == 1 ? "La mesure gardée sur ce Mac sera oubliée."
                           : "Les \(Fmt.int(m.history.count)) mesures gardées sur ce Mac seront oubliées.",
                       button: "Effacer", isPresented: $confirmClear) {
            m.clearHistory()
        }
    }
}

private struct NetworkLatencyPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.network
        Panel(title: "Latence", subtitle: "Cinq pings vers Internet (\(NetworkModel.internetHost), Cloudflare) et vers ta box.", symbol: "timer",
              tint: Theme.palette[2]) {
            if m.pingState.isRunning {
                HStack(spacing: 6) {
                    NetworkSpinner()
                    Text("Mesure…").font(.ui(11.5)).foregroundStyle(Theme.text2)
                }
            } else {
                Button(m.pingState.date == nil ? "Mesurer" : "Remesurer") { m.runPing() }
                    .buttonStyle(SoftButtonStyle(prominent: m.pingState.date == nil, small: true))
            }
        } content: {
            HStack(alignment: .top, spacing: 12) {
                NetworkPingCard(title: "Internet", host: NetworkModel.internetHost, stats: m.pingInternet, state: m.pingState)
                NetworkPingCard(title: "Ta box", host: m.pingRouterHost ?? m.addresses.router ?? "—", stats: m.pingRouter, state: m.pingState,
                                unreachable: m.pingState.date != nil && (m.pingRouterHost == nil || m.pingRouter.received == 0))
            }
            Text("La première mesure vers ta box peut faire apparaître la demande « réseau local » de macOS : accepte-la, sinon la box reste injoignable (Réglages Système › Confidentialité et sécurité › Réseau local).")
                .font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NetworkPingCard: View {
    var title: String
    var host: String
    var stats: NetworkPingStats
    var state: NetworkState
    var unreachable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(host).font(.mono(10.5)).foregroundStyle(Theme.text3)
            }
            if let avg = stats.average ?? (stats.samples.isEmpty ? nil : stats.samples.reduce(0, +) / Double(stats.samples.count)) {
                Text(NetworkFormat.ms(avg)).font(.serif(26)).foregroundStyle(Theme.text).monospacedDigit()
                Sparkline(values: stats.samples, maxValue: (stats.samples.max() ?? 1) * 1.3, tint: color(avg))
                    .frame(height: 26)
                Text([stats.jitter.map { "gigue \(NetworkFormat.ms($0))" }, stats.sent > 0 ? "perte \(Fmt.pct(stats.loss))" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.ui(10.5)).foregroundStyle(stats.loss > 0 ? Theme.warn : Theme.text3)
            } else if unreachable {
                Text("Injoignable").font(.serif(20)).foregroundStyle(Theme.warn)
                Text("Pas de réponse : autorise le réseau local, ou ta box ignore les pings.").font(.ui(10.5)).foregroundStyle(Theme.text3)
            } else {
                Text(state.isRunning ? "…" : "—").font(.serif(26)).foregroundStyle(Theme.text3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.r(10), style: .continuous).fill(Theme.track.opacity(0.5)))
    }

    private func color(_ ms: Double) -> Color {
        ms < 30 ? Theme.good : (ms < 80 ? Theme.accent : Theme.warn)
    }
}

// MARK: - Ports

private struct NetworkPortsTab: View {
    @Environment(AppModel.self) private var app
    @State private var quitting: NetworkPort?

    var body: some View {
        let m = app.network
        let exposed = m.ports.filter(\.isExposed)
        VStack(alignment: .leading, spacing: 14) {
            Panel(title: "Ports ouverts", subtitle: subtitle(m), symbol: "door.left.hand.open", tint: Theme.palette[1]) {
                HStack(spacing: 8) {
                    if m.portsState.isRunning {
                        NetworkSpinner()
                    }
                    Button("Actualiser") { Task { await m.scanPorts() } }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .disabled(m.portsState.isRunning)
                    Button("Voir aussi les services système") { Task { await m.scanPorts(admin: true) } }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .disabled(m.portsState.isRunning)
                        .help("lsof avec les droits d'administrateur : macOS te demande ton mot de passe, l'app ne le voit pas.")
                }
            } content: {
                if case .failed(let why) = m.portsState {
                    Callout(symbol: "exclamationmark.triangle", title: "Lecture impossible", text: why, tint: Theme.warn)
                }
                if m.ports.isEmpty {
                    EmptyHint(text: m.portsState.date == nil ? "Lecture des ports…" : "Aucun programme n'attend de connexion.", symbol: "door.left.hand.closed")
                } else {
                    VStack(spacing: 2) {
                        ForEach(m.ports) { p in
                            NetworkPortRow(port: p) { quitting = p }
                        }
                    }
                }
            }
            TileRow {
                Callout(symbol: "lock.shield", title: "Ce Mac seulement ou tout le réseau ?",
                        text: exposed.isEmpty
                            ? "Tous ces ports n'écoutent que ce Mac (127.0.0.1) : personne d'autre ne peut s'y connecter."
                            : "\(Fmt.plural(exposed.count, "port accepte", "ports acceptent")) les connexions des autres appareils du réseau. Le pare-feu de macOS (Réglages Système › Réseau) peut les filtrer.",
                        tint: exposed.isEmpty ? Theme.good : Theme.warn)
                Callout(symbol: "person.badge.key", title: "Et les services système ?",
                        text: m.portsIncludeSystem
                            ? "La liste inclut les services de macOS lancés en administrateur (root) : ils sont gérés par le système, rien à faire ici."
                            : "Sans mot de passe, macOS ne montre que tes propres programmes. « Voir aussi les services système » relance la lecture en administrateur.",
                        tint: Theme.accent)
            }
        }
        .task { if m.portsState == .idle { await m.scanPorts() } }
        .confirmAction(confirmTitle, message: confirmMessage, button: quitting?.appPath != nil ? "Quitter" : "Arrêter",
                       isPresented: Binding(get: { quitting != nil }, set: { if !$0 { quitting = nil } })) {
            if let p = quitting { m.quit(p) }
        }
    }

    private func subtitle(_ m: NetworkModel) -> String {
        guard let d = m.portsState.date else { return "Les programmes de ce Mac qui attendent des connexions (TCP)." }
        return "\(Fmt.plural(m.ports.count, "port", "ports")) à l'écoute · lu \(Fmt.relative(d))\(m.portsIncludeSystem ? ", services système compris" : "")."
    }

    private var confirmTitle: String {
        guard let p = quitting else { return "" }
        return p.appPath != nil ? "Quitter \(p.displayName) ?" : "Arrêter \(p.process) ?"
    }

    private var confirmMessage: String {
        guard let p = quitting else { return "" }
        if p.appPath != nil {
            return "Le port \(p.port) se fermera avec l'app. Si un document n'est pas enregistré, l'app te le demandera."
        }
        return "Le processus \(p.process) (PID \(p.pid)) écoute sur le port \(p.port). Il recevra une demande d'arrêt : ce qu'il n'a pas enregistré peut être perdu."
    }
}

private struct NetworkPortRow: View {
    var port: NetworkPort
    var onQuit: () -> Void

    var body: some View {
        let p = port
        HoverRow {
            HStack(spacing: 12) {
                Text(verbatim: String(p.port))
                    .font(.mono(15, .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 64, alignment: .leading)
                Group {
                    if let path = p.appPath {
                        FileIcon(path: path, size: 26)
                    } else {
                        IconBadge(symbol: p.isSystem ? "gearshape.2" : "terminal", tint: p.isSystem ? Theme.text3 : Theme.text2, size: 26)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.displayName).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if p.appName != nil && p.appName != p.process {
                            Text(p.process).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                        }
                        if !p.isMine, let u = p.user { Tag(text: u, symbol: "lock.fill") }
                    }
                    Text([NetworkPorts.describe(p), "PID \(p.pid)", p.addresses.map(NetworkPorts.describe(address:)).joined(separator: ", ")]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 10)
                if p.isExposed {
                    Tag(text: "Visible sur le réseau", symbol: "dot.radiowaves.left.and.right", tint: Theme.warn, filled: true)
                } else {
                    Tag(text: "Ce Mac seulement", symbol: "lock", tint: Theme.good, filled: true)
                }
                if !p.isSystem {
                    Button(p.appPath != nil ? "Quitter l'app" : "Arrêter", action: onQuit)
                        .buttonStyle(SoftButtonStyle(small: true))
                        .frame(minWidth: 92, alignment: .trailing)
                } else {
                    Text("Géré par macOS").font(.ui(11)).foregroundStyle(Theme.text3).frame(minWidth: 92, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Bottom bar

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct NetworkBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.network
        if m.speedState.isRunning && m.tab != .speed {
            ActionBar {
                NetworkSpinner()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Test de débit en cours").font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                    Text("↓ \(Fmt.speed(app.monitor.netIn))   ↑ \(Fmt.speed(app.monitor.netOut))").font(.mono(10.5)).foregroundStyle(Theme.text3)
                }
                UsageBar(fraction: m.speedProgress, tint: Theme.accent, height: 6).frame(maxWidth: 260)
                Spacer()
                Button("Voir") { m.tab = .speed }.buttonStyle(SoftButtonStyle())
                Button("Annuler") { m.cancelSpeedTest() }.buttonStyle(SoftButtonStyle())
            }
        }
    }
}

// MARK: - Small pieces

/// A label / value line of the Wi-Fi and address panels.
private struct NetworkInfoRow: View {
    var label: String
    var detail: String? = nil
    var value: String
    var secondary: String? = nil
    var copyable = false
    var warn = false
    var last = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.ui(12)).foregroundStyle(Theme.text2)
            if let detail { Text(detail).font(.ui(10.5)).foregroundStyle(Theme.text3) }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if copyable {
                    NetworkCopyText(text: value, font: .mono(12, .medium))
                } else {
                    Text(value).font(.ui(12, .medium)).foregroundStyle(warn ? Theme.warn : Theme.text).multilineTextAlignment(.trailing)
                }
                if let secondary {
                    NetworkCopyText(text: secondary, font: .mono(10))
                        .opacity(0.75)
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }
}

/// Text that copies itself on click.
private struct NetworkCopyText: View {
    var text: String
    var font: Font

    var body: some View {
        Button {
            guard !DemoData.isEnabled else { return HUD.show(DemoData.refusal, symbol: "theatermasks") }
            _ = NetworkModel.copy(text)
            HUD.show("Copié : \(text)", symbol: "doc.on.clipboard.fill")
        } label: {
            Text(text).font(font).foregroundStyle(Theme.text).multilineTextAlignment(.trailing).lineLimit(2).truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .help("Cliquer pour copier")
    }
}

/// A small spinner (a still arc in snapshots, where AppKit controls do not render).
private struct NetworkSpinner: View {
    var body: some View {
        if Snapshot.isActive {
            Circle().trim(from: 0, to: 0.7)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 13, height: 13)
        } else {
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
        }
    }
}
