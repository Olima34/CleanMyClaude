import SwiftUI

/// A birth or a mue: the moment shown in the middle of the window.
enum RefugeCeremony: Equatable {
    case birth
    case mue(RefugeStage)
}

/// The Refuge: the chamois that lives in the Mac, grows with the blueberries earned by taking care of it, writes its
/// notebook and shows how the Mac is doing on its face. Everything stays on this Mac (refuge.json).
@Observable
@MainActor
final class RefugeModel: AppModule {
    private(set) var state: RefugeState
    /// `--snapshot --tab naissance`, `mue`, `humeur-…`: a ceremony or a mood shown whatever the state.
    var previewCeremony: RefugeCeremony?
    var previewMood: RefugeMood?
    /// The last reaction to a caress, shown in its bubble.
    var reaction: String?

    @ObservationIgnored private let store = JSONStore<RefugeState>("refuge", default: RefugeState())
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var pets: [Date] = []

    init() {
        state = store.value
    }

    private func update(_ s: RefugeState, now: Date = Date()) {
        var s = s
        // A new stage: it writes its mue in its notebook the day it happens; the ceremony waits for the user's eyes.
        if s.stage > state.stage, s.born != nil {
            RefugeRules.note(&s, kind: "mue", text: "J'ai mué : me voilà \(s.stage.title) ! \(s.stage.line)", now: now)
        }
        state = s
        store.value = s
    }

    // MARK: Reading

    var name: String { state.name }
    var stage: RefugeStage { state.stage }
    var isBorn: Bool { state.born != nil }
    var day: Int { RefugeRules.dayNumber(state, now: Date()) }

    /// What the moods read from the Mac now.
    func signals(now: Date = Date()) -> RefugeSignals {
        guard let app else { return RefugeSignals(hour: Calendar.current.component(.hour, from: now)) }
        let recent = app.monitor.cpuHistory.suffix(5)
        let busy = recent.count >= 3 && recent.reduce(0, +) / Double(recent.count) >= 0.8
        return RefugeSignals(hour: Calendar.current.component(.hour, from: now),
                             junk: app.cleanup.hasResults ? app.cleanup.recommendedSize : 0,
                             hot: app.monitor.thermal == .serious || app.monitor.thermal == .critical || busy,
                             boost: app.performance.boost.mode == .performance,
                             threats: app.protection.malware.count)
    }

    func mood(now: Date = Date()) -> RefugeMood {
        previewMood ?? RefugeRules.mood(signals(now: now))
    }

    /// What its room shows now; a mood forced for a snapshot brings its own setting.
    func scene(now: Date = Date()) -> (mood: RefugeMood, night: Bool, dust: Int, moths: Int) {
        let s = signals(now: now)
        guard let forced = previewMood else {
            return (RefugeRules.mood(s), RefugeRules.isNight(s.hour), RefugeRules.dust(s.junk), min(3, s.threats))
        }
        return (forced, forced == .sleepy, forced == .sneezy ? 4 : 1, forced == .worried ? 2 : 0)
    }

    /// The badges won, in the order of the list: the trophies on its shelf.
    var trophies: [RefugeMetal] { RefugeRules.badges.filter { state.badges[$0.id] != nil }.map(\.metal) }

    /// What it says in its bubble: its reaction to a caress, or how it feels.
    func line(now: Date = Date()) -> String {
        if let reaction { return reaction }
        let s = signals(now: now)
        return RefugeRules.moodLine(previewMood ?? RefugeRules.mood(s), signals: s)
    }

    /// The moment waiting to be shown: its birth, or its last mue.
    var ceremony: RefugeCeremony? {
        if let previewCeremony { return previewCeremony }
        guard state.born != nil else { return nil }
        if !state.welcomed { return .birth }
        return RefugeRules.pendingMue(state).map { .mue($0) }
    }

    /// The game shows itself: not in sober mode, not in the themes without the mascot.
    var playful: Bool { !state.sober && Theme.current.spec.mascot }

    /// The ceremony in the middle of the window: only on the dashboard or the Refuge, never in the middle of a task.
    var showsOverlay: Bool {
        guard let app, ceremony != nil, playful else { return false }
        return (app.page == .dashboard || app.page == .refuge)
            && !app.smartScanRunning && !app.cleanup.isCleaning && !app.cleanup.isScanning
    }

    // MARK: Birth and name

    /// Born today. Those who already took care of this Mac get a gift, and the tools they know are already lit.
    private func bear(_ app: AppModel) {
        guard state.born == nil, !DemoData.isEnabled else { return }
        let now = Date()
        let log = app.profile.usageLog
        let known = Page.allCases.filter { $0 != .refuge && !(log.days[$0.rawValue] ?? []).isEmpty }
        var s = state
        RefugeRules.birth(&s, known: known, now: now)
        let gift = RefugeRules.welcome(runs: app.history.runs, days: log.active.count, pages: known.count)
        if gift > 0 {
            s.harvested += gift
            s.basket += gift
            s.totals[RefugeSource.welcome.rawValue] = gift
            RefugeRules.note(&s, kind: "welcome", text: "Tu prenais déjà soin de ce Mac avant mon arrivée : voilà de quoi remplir mon panier.",
                             amount: gift, now: now)
        }
        update(s, now: now)
    }

    /// The end of the birth: its name chosen (« Chamois » if left as is).
    func welcome(name raw: String) {
        if previewCeremony != nil { previewCeremony = nil; return }
        guard state.born != nil, !state.welcomed else { return }
        var s = state
        s.name = RefugeRules.cleanName(raw)
        s.welcomed = true
        RefugeRules.note(&s, kind: "name", text: "Je m'appelle \(s.name). Enchanté !", now: Date())
        update(s)
    }

    func rename(_ raw: String) {
        let clean = RefugeRules.cleanName(raw)
        guard clean != state.name else { return }
        var s = state
        s.name = clean
        RefugeRules.note(&s, kind: "name", text: "Je m'appelle désormais \(clean). Ça me plaît !", merge: true, now: Date())
        update(s)
    }

    /// The mue was seen.
    func acknowledge() {
        if previewCeremony != nil { previewCeremony = nil; return }
        var s = state
        s.shownStage = s.stage.rawValue
        update(s)
    }

    func setSober(_ on: Bool) {
        var s = state
        s.sober = on
        update(s)
        // The Refuge leaves the sidebar with the game, and comes back with it.
        app?.profile.setFeatured(.refuge, !on)
    }

    // MARK: Earning

    /// Pays `source`, writes `text` in its notebook (nil: counted without a line), gives the badges it now deserves.
    @discardableResult
    private func earn(_ source: RefugeSource, key: String? = nil, text: String?, merge: Bool = false, announce: String? = nil) -> Int {
        // The demo's chamois is invented and stays as it is.
        guard state.born != nil, !DemoData.isEnabled else { return 0 }
        let now = Date()
        var s = state
        let paid = RefugeRules.earn(&s, source, key: key, now: now)
        guard paid > 0 else { return 0 }
        if let text { RefugeRules.note(&s, kind: source.rawValue, text: text, amount: paid, merge: merge, now: now) }
        let badges = RefugeRules.award(&s, now: now)
        update(s, now: now)
        if let announce { tell("+\(paid) myrtilles · \(announce)") }
        for b in badges { tell("Nouvel insigne : \(b.title)") }
        return paid
    }

    /// A discreet word, only while the user is in the app and wants the game.
    private func tell(_ text: String) {
        guard playful, state.welcomed, NSApp?.isActive == true else { return }
        HUD.show(text, symbol: "leaf.fill")
    }

    /// Something only seen once (a badge condition).
    private func see(_ key: String) {
        guard state.born != nil, !DemoData.isEnabled, !state.claimed.contains(key) else { return }
        var s = state
        s.claimed.insert(key)
        let badges = RefugeRules.award(&s, now: Date())
        update(s)
        for b in badges { tell("Nouvel insigne : \(b.title)") }
    }

    /// The app opened or came back to the front: the first visit of the day, and the week's reward.
    func arrived() {
        guard state.born != nil else { return }
        earn(.visit, text: nil)
        let now = Date()
        if RefugeRules.weekDue(state, now: now) {
            earn(.week, key: "week:" + RefugeRules.weekKey(now), text: "Quatre jours sur sept ensemble cette semaine. On fait une belle équipe.",
                 announce: "semaine d'entretien")
        }
        observe()
    }

    /// A page opened: a room of the house lights up the first time.
    func visited(_ page: Page) {
        guard state.born != nil else { return }
        if let room = RefugeRules.room(page) {
            earn(.discovery, key: "page:" + page.rawValue, text: "J'ai découvert une nouvelle pièce : \(room.name).", announce: room.name)
        }
        observe()
    }

    /// What it notices on its own: the automations switched on, a strong security score.
    func observe() {
        guard let app, state.born != nil else { return }
        for k in AutomationKind.allCases where app.automation.isEnabled(k) {
            earn(.automation, key: "auto:" + k.rawValue, text: "Le jardin pousse tout seul : une automatisation de plus.", announce: "automatisation")
        }
        if app.protection.hasAudit && app.protection.securityScore >= 90 { see("seen:forteresse") }
    }

    func scanned() {
        if Calendar.current.component(.hour, from: Date()) < 5 { see("seen:noctambule") }
        earn(.scan, text: "On a fait le tour du Mac ensemble. Rien ne m'échappe !")
    }

    func cleaned() {
        earn(.cleaning, text: "Hop, des myrtilles de plus dans mon panier. Merci pour le ménage !")
    }

    func fixed(_ id: String, title: String) {
        earn(.fix, key: "fix:" + id, text: "« \(title) » : la porte du Mac ferme mieux maintenant.", announce: "point de sécurité corrigé")
    }

    func neutralized(_ ids: [String]) {
        for id in ids {
            earn(.threat, key: "threat:" + id, text: "J'ai chassé une mite. Elle est dans la Corbeille, tu peux la récupérer si c'était une erreur.",
                 announce: "une mite chassée")
        }
    }

    func upgraded(_ count: Int) {
        for _ in 0..<max(0, count) { earn(.update, text: "Le courrier est arrivé : des apps toutes neuves.", merge: true) }
    }

    func usedTool(_ id: String) {
        guard !id.hasPrefix("refuge_") else { return }
        earn(.tool, text: nil)
    }

    /// A caress: it laughs, and ten very fast make it sneeze.
    func pet() {
        let now = Date()
        pets = pets.filter { now.timeIntervalSince($0) < 4 } + [now]
        if pets.count >= 10 {
            pets = []
            reaction = "Atchoum ! Ça chatouille !"
            see("seen:atchoum")
        } else {
            reaction = ["Hi hi !", "Encore !", "Ça chatouille.", "Merci, ça fait du bien.", "Tu prends bien soin de moi."][pets.count % 5]
        }
    }

    // MARK: AppModule

    var sidebarBadge: String? {
        guard playful, ceremony != nil else { return nil }
        return "Nouveau"
    }

    func start(app: AppModel) {
        self.app = app
        if state.born == nil { bear(app) }
        arrived()
    }

    /// Without `start` (demo, snapshots, self-tests), the moods still read the app.
    func attach(_ app: AppModel) {
        if self.app == nil { self.app = app }
    }

    func stop() {
        store.flush()
    }

    func loadDemo() {
        let now = Date()
        func ago(_ days: Int, _ hour: Int = 10) -> Date {
            let d = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
            return Calendar.current.date(bySettingHour: hour, minute: 12, second: 0, of: d) ?? d
        }
        var s = RefugeState()
        s.name = "Pompon"
        s.born = ago(63)
        s.welcomed = true
        s.harvested = 2140
        s.basket = 380
        s.shownStage = RefugeStage.at(2140).rawValue
        s.daysTogether = 41
        s.day = RefugeRules.dayKey(now)
        s.paidToday = ["visit": 1, "cleaning": 1, "tool": 4]
        s.recentDays = (0..<7).filter { $0 != 2 && $0 != 5 }.map { RefugeRules.dayKey(ago($0)) }
        s.totals = ["visit": 41, "scan": 22, "cleaning": 34, "fix": 3, "threat": 1, "update": 46, "tool": 182, "discovery": 14, "automation": 1]
        let visited: [Page] = [.dashboard, .cleanup, .protection, .performance, .updates, .apps, .storage, .converter, .youtube,
                               .translator, .clipboard, .launcher, .windows, .automation]
        s.claimed = Set(visited.map { "page:" + $0.rawValue } + ["fix:firewall", "fix:filevault", "fix:gatekeeper", "auto:trash"])
        let badges = ["chiffon", "moutons", "lynx", "mites", "ajour", "explorateur", "mainverte", "fidele"]
        for (i, b) in badges.enumerated() { s.badges[b] = ago(60 - i * 7) }
        s.journal = [
            RefugeEntry(date: ago(63, 9), kind: "birth", text: RefugeStage.cabri.line),
            RefugeEntry(date: ago(63, 9), kind: "name", text: "Je m'appelle Pompon. Enchanté !"),
            RefugeEntry(date: ago(61), kind: "mue", text: "J'ai mué : me voilà Éterlou ! \(RefugeStage.eterlou.line)"),
            RefugeEntry(date: ago(49), kind: "mue", text: "J'ai mué : me voilà Chamois ! \(RefugeStage.chamois.line)"),
            RefugeEntry(date: ago(23, 16), kind: "threat", text: "J'ai chassé une mite cachée dans les Téléchargements. Elle est dans la Corbeille, tu peux la récupérer si c'était une erreur.", amount: 20),
            RefugeEntry(date: ago(9), kind: "mue", text: "J'ai mué : me voilà Beau Chamois ! \(RefugeStage.beau.line)"),
            RefugeEntry(date: ago(4, 18), kind: "discovery", text: "J'ai découvert une nouvelle pièce : La Véranda.", amount: 10),
            RefugeEntry(date: ago(2, 11), kind: "week", text: "Quatre jours sur sept ensemble cette semaine. On fait une belle équipe.", amount: 20),
            RefugeEntry(date: ago(1, 20), kind: "update", text: "Le courrier est arrivé : des apps toutes neuves.", amount: 6, count: 3),
            RefugeEntry(date: ago(0, 9), kind: "cleaning", text: "Hop, des myrtilles de plus dans mon panier. Merci pour le ménage !", amount: 5),
        ]
        state = s
        previewMood = .happy
    }

    func applySnapshotTab(_ tab: String) {
        switch tab {
        case "naissance":
            previewCeremony = .birth
        case "mue":
            previewCeremony = .mue(.beau)
        case "sobre":
            var s = state
            s.sober = true
            state = s
        case "nouveau":
            // The first day: a cabri, nothing visited yet.
            var s = RefugeState()
            s.born = Date()
            s.welcomed = true
            s.harvested = 12
            s.basket = 12
            s.daysTogether = 1
            s.claimed = ["page:dashboard"]
            s.journal = [RefugeEntry(date: Date(), kind: "birth", text: RefugeStage.cabri.line),
                         RefugeEntry(date: Date(), kind: "name", text: "Je m'appelle Chamois. Enchanté !")]
            state = s
        default:
            if tab.hasPrefix("humeur-"), let mood = RefugeMood.allCases.first(where: { "humeur-" + $0.rawValue == tab }) {
                previewMood = mood
            } else if tab.hasPrefix("stade-"), let stage = RefugeStage.allCases.first(where: { "stade-" + String(describing: $0) == tab }) {
                var s = state
                s.harvested = stage.threshold + 40
                s.shownStage = stage.rawValue
                state = s
            }
        }
    }

    func commands(app: AppModel) -> [AppCommand] {
        [AppCommand(id: "refuge_open", title: "Le Refuge de \(state.name)",
                    subtitle: "\(state.stage.title) · \(Fmt.int(state.harvested)) myrtilles récoltées",
                    keywords: ["refuge", "chamois", "mascotte", "myrtilles", "insignes", "carnet", "maison", state.name],
                    icon: .symbol(Page.refuge.symbol, Theme.warn), group: .actions,
                    assistantSafe: true, urlSafe: true, hint: "Ouvrir") { ctx in
            ctx.app.page = .refuge
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
            return .done
        }]
    }

    func selfTest() -> [String] { RefugeRules.selfTest() + RefugeFigure.selfTest() }

    func dump() -> [String] {
        let s = state
        var lines = ["Prénom : \(s.name)\(s.welcomed ? "" : " (naissance pas encore fêtée)")",
                     "Né le : \(s.born.map(Fmt.day) ?? "pas encore né") · jour \(day) · \(s.daysTogether) jours ensemble",
                     "Stade : \(s.stage.title) · \(Fmt.int(s.harvested)) récoltées · panier \(Fmt.int(s.basket))"]
        let p = RefugeRules.progress(s.harvested)
        if let next = p.next { lines.append("Prochain stade : \(next.title) dans \(Fmt.int(p.left)) myrtilles") }
        let sig = signals()
        lines.append("Humeur : \(mood().title) (heure \(sig.hour), moutons \(RefugeRules.dust(sig.junk)), chaud \(sig.hot), Boost \(sig.boost), mites \(sig.threats))")
        lines.append("Pièces : \(RefugeRules.discovered(s).count) sur \(RefugeRules.rooms.count)")
        lines.append("Insignes : " + RefugeRules.badges.filter { s.badges[$0.id] != nil }.map(\.title).joined(separator: ", "))
        lines.append("Aujourd'hui : " + RefugeSource.allCases.compactMap { src in s.paidToday[src.rawValue].map { "\(src.rawValue) \($0)" } }.joined(separator: ", "))
        for e in s.journal.suffix(6) { lines.append("  \(Fmt.day(e.date)) · \(e.text)\(e.amount > 0 ? " (+\(e.amount))" : "")") }
        return lines
    }
}
