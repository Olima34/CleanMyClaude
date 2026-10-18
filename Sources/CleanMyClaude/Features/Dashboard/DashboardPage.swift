import SwiftUI

struct DashboardPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            vitals
            SmartScanPanel()
            HStack(alignment: .top, spacing: 14) {
                Panel(title: "Activité en direct", subtitle: "Processeur et mémoire, deux dernières minutes", symbol: "waveform.path.ecg") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            LegendDot(color: Theme.accent, label: "Processeur", value: Fmt.pct(app.monitor.cpu))
                            LegendDot(color: Theme.palette[4], label: "Mémoire", value: Fmt.pct(app.monitor.memFraction))
                        }
                        ZStack {
                            HistoryChart(values: app.monitor.memHistory.map { $0 * 100 }, tint: Theme.palette[4], unit: "%", maxY: 100)
                            HistoryChart(values: app.monitor.cpuHistory.map { $0 * 100 }, tint: Theme.accent, unit: "%", maxY: 100)
                        }
                        .frame(height: 150)
                    }
                }
                Recommendations()
                    .frame(width: 430)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            MatrixBackdrop(seed: 11, opacity: 0.45)
                .frame(height: 170)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .offset(y: -10)
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ClaudeSpark(size: 34, animate: true)
                        Text(Fmt.greeting(name: Fmt.firstName))
                            .font(.serif(36))
                            .foregroundStyle(Theme.text)
                    }
                    Text(heroSentence)
                        .font(.ui(14))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Tag(text: SystemMonitor.chipName.isEmpty ? SystemMonitor.modelName : SystemMonitor.chipName, symbol: "cpu", tint: Theme.text2)
                        Tag(text: "macOS \(SystemMonitor.osVersion)", symbol: "apple.logo", tint: Theme.text2)
                        Tag(text: Fmt.bytes(app.monitor.memTotal) + " de mémoire", symbol: "memorychip", tint: Theme.text2)
                    }
                }
                Spacer()
                HealthRing()
                PixelMascot(pixel: 7, broom: true)
            }
            .padding(.top, 14)
        }
    }

    private var heroSentence: String {
        let m = app.monitor
        var s = "Ton Mac tourne depuis \(Fmt.duration(m.uptime)) et il te reste \(Fmt.bytes(m.diskFree)) de libre."
        if app.history.totalFreed > 0 {
            s += " Ensemble, on a déjà libéré \(Fmt.bytes(app.history.totalFreed))."
        } else {
            s += " Lance une analyse intelligente pour faire le point en une minute."
        }
        return s
    }

    // MARK: Vitals

    private var vitals: some View {
        let m = app.monitor
        return TileRow {
            StatTile(symbol: "internaldrive", value: Fmt.bytes(m.diskFree), label: "Stockage libre",
                     detail: "\(Fmt.pct(m.diskUsedFraction)) de \(Fmt.bytes(m.diskTotal)) utilisés", tint: Theme.load(m.diskUsedFraction))
            StatTile(symbol: "memorychip", value: Fmt.pct(m.memFraction), label: "Mémoire utilisée",
                     detail: "Pression \(m.pressure.label.lowercased()) · échange \(Fmt.bytes(m.swapUsed))",
                     tint: m.pressure == .normal ? Theme.palette[4] : Theme.warn)
            StatTile(symbol: "cpu", value: Fmt.pct(m.cpu), label: "Processeur",
                     detail: "\(m.coreCount) cœurs · température \(m.thermalLabel.lowercased())", tint: Theme.load(m.cpu))
            if let b = m.battery {
                StatTile(symbol: b.isCharging ? "battery.100.bolt" : "battery.75", value: Fmt.pct(b.level), label: "Batterie",
                         detail: batteryDetail(b), tint: b.health.map { $0 < 0.8 ? Theme.warn : Theme.good } ?? Theme.good)
            } else {
                StatTile(symbol: "arrow.up.arrow.down", value: Fmt.speed(m.netIn), label: "Réseau",
                         detail: "Envoi \(Fmt.speed(m.netOut))", tint: Theme.palette[1])
            }
        }
    }

    private func batteryDetail(_ b: BatteryInfo) -> String {
        var parts: [String] = []
        if let h = b.health { parts.append("Santé \(Fmt.pct(h))") }
        if let c = b.cycleCount { parts.append("\(c) cycles") }
        if let mins = b.minutesLeft { parts.append(b.isCharging ? "pleine dans \(Fmt.duration(Double(mins * 60)))" : "\(Fmt.duration(Double(mins * 60))) restantes") }
        return parts.joined(separator: " · ")
    }
}

struct HealthRing: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressRing(progress: Double(app.healthScore) / 100, tint: app.healthColor, lineWidth: 9)
                VStack(spacing: 0) {
                    Text("\(app.healthScore)").font(.serif(34)).foregroundStyle(Theme.text).contentTransition(.numericText())
                    Text("sur 100").font(.ui(10.5)).foregroundStyle(Theme.text3)
                }
            }
            .frame(width: 104, height: 104)
            Text(app.healthLabel).font(.ui(12, .semibold)).foregroundStyle(app.healthColor)
        }
        .help("Score calculé avec l'espace libre, la pression mémoire, les protections de sécurité et les fichiers inutiles trouvés.")
    }
}

// MARK: - Smart scan

struct SmartScanPanel: View {
    @Environment(AppModel.self) private var app
    @State private var confirmClean = false

    var body: some View {
        Card(padding: 20) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Analyse intelligente").font(.serif(22)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if app.cleanup.hasResults && app.cleanup.recommendedSize > 0 && !app.smartScanRunning {
                    Button {
                        confirmClean = true
                    } label: {
                        Label("Nettoyer \(Fmt.bytes(app.cleanup.recommendedSize))", systemImage: "sparkles")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(app.cleanup.isCleaning)
                }
                ScanButton(title: app.smartScanDate == nil ? "Lancer l'analyse" : "Relancer", symbol: "wand.and.stars",
                           running: app.smartScanRunning, runningTitle: "J'analyse…") {
                    Task { await app.smartScan() }
                }
            }
            if app.smartScanRunning || app.smartScanDate != nil || app.cleanup.hasResults {
                Divider().padding(.vertical, 4)
                TileRow(spacing: 12) {
                    ScanResultTile(symbol: "sparkles", title: "Fichiers inutiles", tint: Theme.accent,
                                   running: app.cleanup.isScanning,
                                   value: app.cleanup.hasResults ? Fmt.bytes(app.cleanup.recommendedSize) : "—",
                                   detail: app.cleanup.hasResults ? "à nettoyer sans risque · \(Fmt.bytes(app.cleanup.totalSize)) trouvés en tout" : "Pas encore analysé",
                                   page: .cleanup)
                    ScanResultTile(symbol: "lock.shield", title: "Sécurité", tint: Theme.good,
                                   running: app.protection.isAuditing,
                                   value: app.protection.hasAudit ? "\(app.protection.passedCount)/\(app.protection.scoredCount)" : "—",
                                   detail: app.protection.hasAudit ? (app.protection.issues.isEmpty ? "Toutes les protections sont actives" : "\(Fmt.plural(app.protection.issues.count, "point", "points")) à vérifier") : "Pas encore analysé",
                                   page: .protection)
                    ScanResultTile(symbol: "square.grid.2x2", title: "Applications", tint: Theme.palette[4],
                                   running: app.apps.isScanning,
                                   value: app.apps.lastScan != nil ? "\(app.apps.unused.count)" : "—",
                                   detail: app.apps.lastScan != nil ? "inutilisées depuis 3 mois · \(app.apps.intel.count) en Intel" : "Pas encore analysé",
                                   page: .apps)
                    ScanResultTile(symbol: "power", title: "Démarrage", tint: Theme.warn,
                                   running: app.startup.isScanning,
                                   value: app.startup.lastScan != nil ? "\(app.startup.activeCount)" : "—",
                                   detail: app.startup.lastScan != nil ? "agents tiers actifs · \(app.startup.flagged.count) à examiner" : "Pas encore analysé",
                                   page: .performance)
                }
            }
        }
        .confirmAction("Nettoyer \(Fmt.bytes(app.cleanup.recommendedSize)) ?",
                       message: "Uniquement ce que je coche d'office : caches, journaux et fichiers que les apps recréent seules, plus la Corbeille si tu l'as autorisée. Tes fichiers personnels ne sont pas concernés.",
                       button: "Nettoyer", isPresented: $confirmClean) {
            app.cleanup.selectRecommended()
            Task { await app.cleanup.clean() }
        }
    }

    private var subtitle: String {
        if app.smartScanRunning { return "Fichiers inutiles, sécurité, applications et démarrage : j'examine tout en parallèle." }
        if let d = app.smartScanDate { return "Dernière analyse \(Fmt.relative(d)). Clique sur une carte pour voir le détail." }
        return "Un bilan complet en une minute : fichiers inutiles, protections de sécurité, apps oubliées et ce qui démarre en douce. Rien n'est supprimé sans ton accord."
    }
}

struct ScanResultTile: View {
    @Environment(AppModel.self) private var app
    var symbol: String
    var title: String
    var tint: Color
    var running: Bool
    var value: String
    var detail: String
    var page: Page
    @State private var hovering = false

    var body: some View {
        Button { app.page = page } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    IconBadge(symbol: symbol, tint: tint)
                    Text(title).font(.ui(12)).foregroundStyle(Theme.text2)
                    Spacer()
                    if running { ProgressView().controlSize(.small).scaleEffect(0.7) } else {
                        Image(systemName: "chevron.right").font(.ui(10, .semibold)).foregroundStyle(Theme.text3).opacity(hovering ? 1 : 0.4)
                    }
                }
                Text(value).font(.serif(26)).foregroundStyle(Theme.text).contentTransition(.numericText())
                Text(detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(hovering ? Theme.hover.opacity(0.6) : Theme.cardRaised.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Recommendations

struct Advice: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let text: String
    let tint: Color
    var page: Page? = nil
}

struct Recommendations: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let list = advices
        Panel(title: "Mes conseils", subtitle: list.isEmpty ? nil : "Classés du plus utile au moins urgent", symbol: "lightbulb", tint: Theme.brand) {
            VStack(alignment: .leading, spacing: 10) {
                if list.isEmpty {
                    HStack(spacing: 12) {
                        PixelMascot(pixel: 4)
                        Text(app.smartScanDate == nil ? "Lance une analyse intelligente : j'aurai sûrement quelques idées." : "Rien à signaler. Ton Mac est en pleine forme.")
                            .font(.ui(12)).foregroundStyle(Theme.text2)
                    }
                    .padding(.vertical, 8)
                }
                ForEach(list.prefix(5)) { a in
                    Button { if let p = a.page { app.page = p } } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: a.symbol).font(.ui(12, .medium)).foregroundStyle(a.tint)
                                .frame(width: 26, height: 26)
                                .background(RoundedRectangle(cornerRadius: 7).fill(a.tint.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                                Text(a.text).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var advices: [Advice] {
        let m = app.monitor
        var out: [Advice] = []
        if !app.fullDiskAccess {
            out.append(Advice(id: "fda", symbol: "externaldrive.badge.checkmark", title: "Donne-moi l'accès complet au disque",
                              text: "Sans lui, je ne peux voir ni la Corbeille, ni Mail, ni les autorisations de tes apps.", tint: Theme.accent))
        }
        if m.diskUsedFraction > 0.9 {
            out.append(Advice(id: "disk", symbol: "externaldrive.trianglebadge.exclamationmark", title: "Ton disque est presque plein",
                              text: "Au-delà de 90 %, macOS ralentit et ne peut plus installer ses mises à jour. Explore le stockage pour repérer les mastodontes.",
                              tint: Theme.bad, page: .storage))
        } else if m.diskUsedFraction > 0.8 {
            out.append(Advice(id: "disk", symbol: "externaldrive", title: "Le stockage se remplit",
                              text: "Il reste \(Fmt.bytes(m.diskFree)). Garde idéalement 15 à 20 % de libre.", tint: Theme.warn, page: .storage))
        }
        for c in app.protection.issues.prefix(3) {
            out.append(Advice(id: c.id, symbol: c.symbol, title: c.title, text: c.detail, tint: c.status.color, page: .protection))
        }
        if app.cleanup.hasResults && app.cleanup.recommendedSize > 1_000_000_000 {
            out.append(Advice(id: "junk", symbol: "sparkles", title: "\(Fmt.bytes(app.cleanup.recommendedSize)) à récupérer sans risque",
                              text: "Des caches et journaux que tes apps recréeront si besoin.", tint: Theme.accent, page: .cleanup))
        }
        if let trash = app.cleanup.targets.first(where: { $0.id == "trash" }), trash.size > 1_000_000_000 {
            out.append(Advice(id: "trash", symbol: "trash", title: "Ta Corbeille pèse \(Fmt.bytes(trash.size))",
                              text: "Ce que tu as jeté occupe toujours ton disque tant qu'elle n'est pas vidée.", tint: Theme.warn, page: .cleanup))
        }
        if m.swapUsed > m.memTotal / 2 || m.pressure != .normal {
            out.append(Advice(id: "memory", symbol: "memorychip", title: "Ta mémoire est à l'étroit",
                              text: "macOS déborde sur le disque (\(Fmt.bytes(m.swapUsed)) d'échange). Ferme les apps gourmandes repérées dans Optimisation.",
                              tint: Theme.warn, page: .performance))
        }
        if m.uptime > 14 * 86400 {
            out.append(Advice(id: "uptime", symbol: "arrow.clockwise", title: "Pense à redémarrer",
                              text: "Ton Mac tourne depuis \(Fmt.duration(m.uptime)). Un redémarrage applique les correctifs en attente et remet la mémoire à plat.",
                              tint: Theme.palette[1]))
        }
        if let b = m.battery, let h = b.health, h < 0.8 {
            out.append(Advice(id: "battery", symbol: "battery.25", title: "Batterie fatiguée (\(Fmt.pct(h)))",
                              text: "Sous 80 % de sa capacité d'origine, Apple recommande un remplacement.", tint: Theme.warn))
        }
        if !app.apps.intel.isEmpty {
            out.append(Advice(id: "intel", symbol: "cpu", title: "\(Fmt.plural(app.apps.intel.count, "app tourne", "apps tournent")) encore via Rosetta",
                              text: "Apple retire Rosetta après macOS 27 : cherche leurs versions Apple Silicon.", tint: Theme.warn, page: .apps))
        }
        if app.startup.flagged.count > 0 {
            out.append(Advice(id: "flagged", symbol: "exclamationmark.shield", title: "\(Fmt.plural(app.startup.flagged.count, "élément persistant", "éléments persistants")) à examiner",
                              text: "Non signés, orphelins ou scripts qui démarrent avec ton Mac.", tint: Theme.warn, page: .protection))
        }
        if app.apps.unused.count >= 5 {
            out.append(Advice(id: "unused", symbol: "moon.zzz", title: "\(app.apps.unused.count) apps dorment",
                              text: "Pas ouvertes depuis trois mois : \(Fmt.bytes(app.apps.unused.reduce(0) { $0 + $1.size })) au total.", tint: Theme.palette[4], page: .apps))
        }
        return out
    }
}
