import SwiftUI

struct DashboardPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            if !app.profile.isChosen && !app.profile.settings.inviteDismissed {
                ProfileInvite()
            }
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
            ToolsOverview()
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            DustBackdrop(seed: 11, opacity: 0.45)
                .frame(height: 170)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .offset(y: -10)
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Fmt.greeting(name: Fmt.firstName))
                        .font(.serif(36))
                        .foregroundStyle(Theme.text)
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
                if app.smartScanRunning {
                    BusyMascot(.inspecting, pixel: 5)
                } else if app.refuge.isAdopted && app.refuge.playful {
                    // Its own chamois, at its stage and in its mood: a click opens its Refuge.
                    Button { app.page = .refuge } label: {
                        RefugeAvatar(look: app.refuge.look(), mood: app.refuge.mood(), pixel: 5)
                    }
                    .buttonStyle(.plain)
                    .help("\(app.refuge.name) · \(app.refuge.stage.title) : ouvrir son Refuge")
                } else {
                    PixelMascot(pixel: 5)
                }
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
                        ThemedLabel(title: "Nettoyer \(Fmt.bytes(app.cleanup.recommendedSize))", symbol: "sparkles")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(app.cleanup.isCleaning)
                }
                ScanButton(title: app.smartScanDate == nil ? "Lancer l'analyse" : "Relancer", symbol: "wand.and.stars",
                           running: app.smartScanRunning, runningTitle: "J'analyse…", activity: .inspecting) {
                    Task { await app.smartScan() }
                }
            }
            if app.smartScanRunning || app.smartScanDate != nil || app.cleanup.hasResults {
                Divider().padding(.vertical, 4)
                TileRow(spacing: 12) {
                    ScanResultTile(symbol: "sparkles", title: "Fichiers inutiles", tint: Theme.accent,
                                   running: app.cleanup.isScanning, activity: .sweeping,
                                   value: app.cleanup.hasResults ? Fmt.bytes(app.cleanup.recommendedSize) : "—",
                                   detail: app.cleanup.hasResults ? "à nettoyer sans risque · \(Fmt.bytes(app.cleanup.totalSize)) trouvés en tout" : "Pas encore analysé",
                                   page: .cleanup)
                    ScanResultTile(symbol: "lock.shield", title: "Sécurité", tint: app.protection.malware.isEmpty ? Theme.good : Theme.bad,
                                   running: app.protection.isAuditing || app.protection.isScanning, activity: .inspecting,
                                   value: app.protection.hasAudit ? "\(app.protection.securityScore)/100" : "—",
                                   detail: securityDetail,
                                   page: .protection, tab: { app.protection.tab = app.protection.malware.isEmpty ? .security : .threats })
                    ScanResultTile(symbol: "square.grid.2x2", title: "Applications", tint: Theme.palette[4],
                                   running: app.apps.isScanning, activity: .checking,
                                   value: app.apps.lastScan != nil ? "\(app.apps.unused.count)" : "—",
                                   detail: app.apps.lastScan != nil ? "inutilisées depuis 3 mois · \(app.apps.intel.count) en Intel" : "Pas encore analysé",
                                   page: .apps, tab: { app.apps.filter = .unused })
                    ScanResultTile(symbol: "power", title: "Démarrage", tint: Theme.warn,
                                   running: app.startup.isScanning, activity: .searching,
                                   value: app.startup.lastScan != nil ? "\(app.startup.activeCount)" : "—",
                                   detail: app.startup.lastScan != nil ? "agents tiers actifs · \(app.startup.flagged.count) à examiner" : "Pas encore analysé",
                                   page: .performance, tab: { app.performance.tab = .startup })
                }
                if app.smartScanRunning && app.refuge.isAdopted && app.refuge.playful {
                    // While it works, the dust bunny chase.
                    RefugeChase()
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

    private var securityDetail: String {
        let p = app.protection
        if !p.malware.isEmpty { return "\(Fmt.plural(p.malware.count, "menace trouvée", "menaces trouvées")) · note \(p.grade)" }
        guard p.hasAudit else { return "Pas encore analysé" }
        let threats = p.scanSummary.map { _ in " · aucune menace" } ?? ""
        return (p.issues.isEmpty ? "Note \(p.grade), toutes les protections actives" : "Note \(p.grade) · \(Fmt.plural(p.issues.count, "point", "points")) à vérifier") + threats
    }

    private var subtitle: String {
        if app.smartScanRunning { return "Fichiers inutiles, sécurité, logiciels malveillants, applications et démarrage : j'examine tout en parallèle." }
        if let d = app.smartScanDate { return "Dernière analyse \(Fmt.relative(d)). Clique sur une carte pour voir le détail." }
        return "Un bilan complet en une minute : fichiers inutiles, protections de sécurité, logiciels malveillants, apps oubliées et ce qui démarre en douce. Rien n'est supprimé sans ton accord."
    }
}

struct ScanResultTile: View {
    @Environment(AppModel.self) private var app
    var symbol: String
    var title: String
    var tint: Color
    var running: Bool
    /// What the mascot does in the corner while this part of the scan runs.
    var activity: MascotActivity
    var value: String
    var detail: String
    var page: Page
    /// Picks the right tab of the page before opening it.
    var tab: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        Button {
            tab?()
            app.page = page
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    IconBadge(symbol: symbol, tint: tint)
                    Text(title).font(.ui(12)).foregroundStyle(Theme.text2)
                    Spacer()
                    if running { BusyMascot(activity, pixel: 1) } else {
                        Image(systemName: "chevron.right").font(.ui(10, .semibold)).foregroundStyle(Theme.text3).opacity(hovering ? 1 : 0.4)
                    }
                }
                Text(value).font(.serif(26)).foregroundStyle(Theme.text).contentTransition(.numericText())
                Text(detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(hovering ? Theme.hover.opacity(0.6) : Theme.cardRaised.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(12)).strokeBorder(Theme.border, lineWidth: Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Tools

/// The tools of the sidebar beyond the analyses above, most used first, with their live state: one click opens them.
struct ToolsOverview: View {
    @Environment(AppModel.self) private var app

    /// Already behind the smart scan's cards.
    private static let scanned: Set<Page> = [.dashboard, .cleanup, .protection, .performance, .apps]

    var body: some View {
        let profile = app.profile
        let pages = profile.ranking.filter { !Self.scanned.contains($0) }
        let others = profile.others
        Panel(title: "Tes outils", subtitle: subtitle, symbol: "square.grid.3x3", tint: Theme.palette[1]) {
            Button(profile.isChosen ? "Modifier mon profil" : "Personnaliser") { app.showProfilePanel = true }
                .buttonStyle(SoftButtonStyle(small: true))
        } content: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4), spacing: 12) {
                ForEach(pages) { tile($0) }
                if !others.isEmpty {
                    DashboardMoreTile(pages: others)
                }
            }
        }
    }

    private var subtitle: String {
        let launcher = app.launcher.combo.map { " · tous aussi depuis le lanceur \($0.display)" } ?? ""
        guard app.profile.isChosen else { return "Tes outils du quotidien, les plus utilisés d'abord\(launcher)" }
        return "Pour ton profil \(app.profile.summary) et d'après ce dont tu te sers, les plus utilisés d'abord\(launcher)"
    }

    private var indexDetail: String {
        if case .ready(let n) = app.launcher.indexState { return "Apps, actions et \(Fmt.int(n)) fichiers trouvés en un éclair" }
        return "Apps, fichiers, calculs, traductions et toutes les actions"
    }

    @ViewBuilder
    private func tile(_ page: Page) -> some View {
        switch page {
        case .launcher:
            tile(page, tint: Theme.brand, value: app.launcher.combo?.display ?? "—", detail: indexDetail)
        case .hotkeys:
            tile(page, tint: Theme.brand, value: "\(app.hotkeys.bindings.filter { $0.combo != nil }.count)",
                 detail: app.hotkeys.bindings.isEmpty ? "Ouvre n'importe quelle app d'un raccourci" : "raccourcis pour tes apps, dossiers et sites")
        case .converter:
            tile(page, tint: Theme.accent, value: app.converter.isBusy ? "\(app.converter.activeJobs.count) en cours" : "Glisser-déposer",
                 detail: "Images, vidéos, audio, PDF, documents, OCR et QR codes")
        case .fillsign:
            tile(page, tint: Theme.accent, value: app.fillSign.document != nil ? "En cours" : "Un PDF",
                 detail: "Remplis un formulaire, écris où tu veux, signe et paraphe")
        case .youtube:
            let activity = app.youtube.activity
            tile(page, tint: Theme.bad, value: activity.map { $0.running ? $0.percent : "En attente" } ?? "Un lien",
                 detail: activity.map { "\($0.detail) · \($0.title)" } ?? "La vidéo en MP4 ou le son en MP3, en entier ou un extrait")
        case .cinema:
            tile(page, tint: CinemaStyle.tint, value: app.cinema.hasKey ? "Où regarder" : "Un titre",
                 detail: app.cinema.recents.first.map { "Dernier : \($0.title)" } ?? "Sa fiche, sa bande-annonce et les plateformes qui le proposent")
        case .translator:
            tile(page, tint: Theme.palette[1], value: app.translator.engine == .apple ? "Hors ligne" : "Claude",
                 detail: "Sur ton Mac ou avec Claude, aussi depuis le lanceur (« trad »)")
        case .updates:
            tile(page, tint: Theme.good,
                 value: app.updates.hasChecked ? "\(app.updates.totalAvailable)" : "—",
                 detail: app.updates.hasChecked
                    ? (app.updates.totalAvailable == 0 ? "Tout est à jour" : "mises à jour disponibles (Homebrew, apps, macOS)")
                    : "Homebrew, apps et macOS : pas encore vérifié")
        case .network:
            tile(page, tint: Theme.palette[4],
                 value: app.network.lastSpeed.map { NetworkFormat.bits($0.download) } ?? "—",
                 detail: app.network.lastSpeed.map { "reçus au dernier test, \(Fmt.relative($0.date))" } ?? "Débit, Wi-Fi, latence et ports ouverts")
        case .clipboard:
            tile(page, tint: Theme.palette[2],
                 value: app.clipboard.isActive ? Fmt.int(app.clipboard.items.count) : "En pause",
                 detail: app.clipboard.isActive ? "éléments dans l'historique, mots de passe ignorés" : "Historique désactivé tant que tu ne l'actives pas")
        case .toolbox:
            tile(page, tint: Theme.warn, value: app.toolbox.sidebarBadge ?? "Caféine",
                 detail: "Couleurs, mots de passe, JSON, Caféine, curseur caché et compagnie")
        case .battery:
            if let r = app.battery.reading {
                tile(page, tint: Theme.good, value: app.battery.activeLimit.map { $0 < 100 ? "Limite \($0) %" : "\(r.percent) %" } ?? "\(r.percent) %",
                     detail: "Limite de recharge, alerte de batterie faible et santé")
            }
        case .storage:
            tile(page, tint: Theme.palette[3], value: Fmt.bytes(app.monitor.diskFree),
                 detail: "libres · la carte du disque, les gros fichiers et les doublons")
        case .adblock:
            tile(page, tint: Theme.good, value: app.adblock.state.isOn ? "Actif" : (app.adblock.installed ? "Inactif" : "À installer"),
                 detail: "Pubs, pisteurs et sites piégés bloqués pour tout le Mac")
        case .darkmode:
            tile(page, tint: Theme.palette[4], value: app.darkmode.toForce.isEmpty ? "Sombre" : "\(app.darkmode.toForce.count) apps",
                 detail: app.darkmode.toForce.isEmpty ? "Les sites et les apps restés clairs passent en sombre" : "restées claires, à passer en sombre")
        case .windows:
            tile(page, tint: Theme.palette[1],
                 value: !app.windows.enabled ? "Inactif" : (app.windows.trusted ? "Actif" : "À autoriser"),
                 detail: "Moitiés, tiers et quarts d'écran au clavier (⌃⌥ + flèches)")
        case .automation:
            tile(page, tint: Theme.palette[3], value: "\(app.automation.activeCount)",
                 detail: app.automation.activeCount == 0 ? "Aucune automatisation active pour l'instant" : "automatisations actives")
        case .assistant:
            tile(page, tint: Theme.brand, value: app.assistant.isReady ? "Connecté" : "À connecter",
                 detail: "Pose une question sur ton Mac : Claude propose, tu décides")
        case .menubar:
            tile(page, tint: Theme.palette[2], value: "En direct",
                 detail: "Processeur, mémoire et actions express dans la barre des menus")
        case .refuge:
            tile(page, tint: Theme.warn, value: app.refuge.isAdopted ? app.refuge.stage.title : "À adopter",
                 detail: app.refuge.isAdopted ? "\(app.refuge.name) · \(Fmt.int(app.refuge.state.basket)) myrtilles dans le panier"
                    : "Un petit chamois t'attend dans son buisson de myrtilles")
        case .dashboard, .cleanup, .protection, .performance, .apps:
            EmptyView()
        }
    }

    private func tile(_ page: Page, tint: Color, value: String, detail: String) -> some View {
        ScanResultTile(symbol: page.symbol, title: page.title, tint: tint, running: false, activity: .inspecting, value: value, detail: detail, page: page)
    }
}

/// The last tile: the tools put away, and the way to bring them back.
struct DashboardMoreTile: View {
    var pages: [Page]
    @Environment(AppModel.self) private var app
    @State private var hovering = false

    var body: some View {
        Button { app.showProfilePanel = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    IconBadge(symbol: "ellipsis", tint: Theme.text3)
                    Text("Autres outils").font(.ui(12)).foregroundStyle(Theme.text2)
                    Spacer()
                    Image(systemName: "chevron.right").font(.ui(10, .semibold)).foregroundStyle(Theme.text3).opacity(hovering ? 1 : 0.4)
                }
                Text("+\(pages.count)").font(.serif(26)).foregroundStyle(Theme.text)
                Text(detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(hovering ? Theme.hover.opacity(0.6) : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(12)).strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: Theme.line, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Les outils hors de ton profil : choisis ceux à garder sous la main")
    }

    private var detail: String {
        let names = pages.prefix(2).map(\.title).joined(separator: ", ")
        return pages.count > 2 ? "\(names) et \(pages.count - 2) autres, rangés en bas de la barre latérale" : "\(names), rangés en bas de la barre latérale"
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
    /// Picks the right tab of the page before opening it.
    var tab: (() -> Void)? = nil
}

struct Recommendations: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let list = advices
        Panel(title: "Mes conseils", subtitle: list.isEmpty ? nil : "Classés du plus utile au moins urgent", symbol: "lightbulb", tint: Theme.brand) {
            VStack(alignment: .leading, spacing: 10) {
                if list.isEmpty {
                    HStack(spacing: 12) {
                        PixelMascot(pixel: 1.5)
                        Text(app.smartScanDate == nil ? "Lance une analyse intelligente : j'aurai sûrement quelques idées." : "Rien à signaler. Ton Mac est en pleine forme.")
                            .font(.ui(12)).foregroundStyle(Theme.text2)
                    }
                    .padding(.vertical, 8)
                }
                ForEach(list.prefix(5)) { a in
                    Button {
                        a.tab?()
                        if let p = a.page { app.page = p }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            IconBadge(symbol: a.symbol, tint: a.tint, size: 26)
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
        let p = app.protection
        if !p.malware.isEmpty {
            out.append(Advice(id: "malware", symbol: "ant.fill", title: "\(Fmt.plural(p.malware.count, "menace", "menaces")) sur ton Mac",
                              text: "Reconnues par les signatures d'Apple ou par leur comportement. Neutralise-les : je les arrête et je les mets à la Corbeille.",
                              tint: Theme.bad, page: .protection, tab: { app.protection.tab = .threats }))
        }
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
            out.append(Advice(id: c.id, symbol: c.symbol, title: c.title, text: c.detail, tint: c.status.color, page: .protection,
                              tab: { app.protection.tab = .security }))
        }
        if !p.realtime.anyOn {
            out.append(Advice(id: "realtime", symbol: "shield.lefthalf.filled.badge.checkmark", title: "Active la protection en temps réel",
                              text: "Une alerte dès qu'un programme s'ajoute au démarrage, qu'une menace arrive dans Téléchargements ou que la caméra s'allume.",
                              tint: Theme.good, page: .protection, tab: { app.protection.tab = .realtime }))
        }
        if p.scanSummary.map({ Date().timeIntervalSince($0.date) > 14 * 86400 }) ?? true {
            out.append(Advice(id: "scan", symbol: "ant", title: p.scanSummary == nil ? "Cherche les logiciels malveillants" : "Ta dernière analyse antimalware date",
                              text: "Les signatures d'Apple appliquées à tout ce qui est sur ton Mac, ouvert ou non : moins d'une minute.",
                              tint: Theme.accent, page: .protection, tab: {
                                  app.protection.tab = .threats
                                  Task { await app.protection.scan(deep: false) }
                              }))
        }
        if app.cleanup.hasResults && app.cleanup.recommendedSize > 1_000_000_000 {
            out.append(Advice(id: "junk", symbol: "sparkles", title: "\(Fmt.bytes(app.cleanup.recommendedSize)) à récupérer sans risque",
                              text: "Des caches et journaux que tes apps recréeront si besoin.", tint: Theme.accent, page: .cleanup))
        }
        if let trash = app.cleanup.targets.first(where: { $0.id == "trash" }), trash.size > 1_000_000_000 {
            out.append(Advice(id: "trash", symbol: "trash", title: "Ta Corbeille pèse \(Fmt.bytes(trash.size))",
                              text: "Ce que tu as jeté occupe toujours ton disque tant qu'elle n'est pas vidée.", tint: Theme.warn, page: .cleanup))
        }
        // macOS itself is already in the security checks above: only the apps and packages here.
        let appUpdates = app.updates.totalAvailable - app.updates.macOSLabels.count
        if app.updates.hasChecked && appUpdates > 0 {
            out.append(Advice(id: "updates", symbol: "arrow.down.circle", title: "\(Fmt.plural(appUpdates, "app attend sa mise à jour", "apps attendent leur mise à jour"))",
                              text: "Les correctifs de sécurité arrivent par là : un clic suffit pour Homebrew, les autres apps s'ouvrent sur leur mise à jour.",
                              tint: Theme.good, page: .updates))
        }
        if m.swapUsed > m.memTotal / 2 || m.pressure != .normal {
            out.append(Advice(id: "memory", symbol: "memorychip", title: "Ta mémoire est à l'étroit",
                              text: "macOS déborde sur le disque (\(Fmt.bytes(m.swapUsed)) d'échange). Ferme les apps gourmandes repérées dans Optimisation.",
                              tint: Theme.warn, page: .performance, tab: { app.performance.tab = .monitor }))
        }
        if app.performance.boost.mode == .off {
            out.append(Advice(id: "boost", symbol: "bolt", title: m.thermal == .nominal ? "Active le Boost" : "Ton Mac chauffe : active le Boost",
                              text: "Ce qui s'emballe en arrière-plan passe sur les cœurs économes de la puce : un Mac plus frais, et plus de puissance pour ce que tu fais.",
                              tint: Theme.warn, page: .performance, tab: { app.performance.tab = .boost }))
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
                              text: "Apple retire Rosetta après macOS 27 : cherche leurs versions Apple Silicon.", tint: Theme.warn, page: .apps,
                              tab: { app.apps.filter = .intel }))
        }
        if app.startup.flagged.count > 0 {
            out.append(Advice(id: "flagged", symbol: "exclamationmark.shield", title: "\(Fmt.plural(app.startup.flagged.count, "élément persistant", "éléments persistants")) à examiner",
                              text: "Non signés, orphelins ou scripts qui démarrent avec ton Mac.", tint: Theme.warn, page: .protection,
                              tab: { app.protection.tab = .persistence }))
        }
        if app.apps.unused.count >= 5 {
            out.append(Advice(id: "unused", symbol: "moon.zzz", title: "\(app.apps.unused.count) apps dorment",
                              text: "Pas ouvertes depuis trois mois : \(Fmt.bytes(app.apps.unused.reduce(0) { $0 + $1.size })) au total.", tint: Theme.palette[4], page: .apps,
                              tab: { app.apps.filter = .unused }))
        }
        // Last: a tool of the profile not tried yet.
        if let p = app.profile.discovery {
            out.append(Advice(id: "discover", symbol: p.symbol, title: "À essayer : \(p.title)",
                              text: "\(p.pitch) Il fait partie de ton profil \(app.profile.summary).", tint: Theme.brand, page: p))
        }
        return out
    }
}
