import Foundation

// The game of the Refuge, as pure functions: the blueberries, the stages, the badges, the rooms and the moods.
// `--selftest` checks them; the model only calls them and saves the result.

/// The six stages of the chamois. At each one it really changes: its size, its horns, what it wears.
enum RefugeStage: Int, CaseIterable, Codable, Comparable {
    case cabri, eterlou, chamois, beau, grand, gold

    static func < (a: RefugeStage, b: RefugeStage) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .cabri: return "Cabri"
        case .eterlou: return "Éterlou"
        case .chamois: return "Chamois"
        case .beau: return "Beau Chamois"
        case .grand: return "Grand Chamois"
        case .gold: return "Chamois d'or"
        }
    }

    /// The blueberries harvested since its birth that it takes.
    var threshold: Int {
        switch self {
        case .cabri: return 0
        case .eterlou: return 60
        case .chamois: return 300
        case .beau: return 1200
        case .grand: return 3500
        case .gold: return 12000
        }
    }

    /// What is new, in a few words (the stage strip).
    var change: String {
        switch self {
        case .cabri: return "pas encore de cornes"
        case .eterlou: return "ses premières cornes"
        case .chamois: return "les cornes en crochet"
        case .beau: return "sa clochette"
        case .grand: return "sa première écharpe"
        case .gold: return "le pelage doré"
        }
    }

    /// What it says at its mue (or at its birth, for the first stage).
    var line: String {
        switch self {
        case .cabri: return "Je suis né. Tout est nouveau ici. Tu me fais visiter ?"
        case .eterlou: return "Deux petites cornes ont poussé. Je me sens déjà plus grand !"
        case .chamois: return "Mes cornes font le crochet, comme celles des grands. Me voilà un vrai chamois."
        case .beau: return "Une clochette à mon cou ! Tu m'entendras arriver de loin."
        case .grand: return "Ma première écharpe, en bronze. Elle changera de matière à chaque palier."
        case .gold: return "Mon pelage est devenu doré. Je n'en reviens pas, merci de m'avoir fait grandir."
        }
    }

    var next: RefugeStage? { RefugeStage(rawValue: rawValue + 1) }

    static func at(_ harvested: Int) -> RefugeStage {
        allCases.last { harvested >= $0.threshold } ?? .cabri
    }
}

/// What earns blueberries. Never the amount deleted: nobody should erase files to make it grow.
enum RefugeSource: String, CaseIterable, Codable {
    case visit, scan, cleaning, fix, threat, update, tool, discovery, automation, week, welcome

    var amount: Int {
        switch self {
        case .visit: return 2
        case .scan, .cleaning: return 5
        case .fix, .automation: return 15
        case .threat, .week: return 20
        case .update: return 2
        case .tool: return 1
        case .discovery: return 10
        case .welcome: return 0
        }
    }

    /// How many times a day it pays, nil without a daily limit.
    var perDay: Int? {
        switch self {
        case .visit, .scan: return 1
        case .cleaning: return 2
        case .update, .tool, .threat: return 10
        case .fix, .discovery, .automation, .week, .welcome: return nil
        }
    }

    /// Paid once for each thing (a security point, a tool, an automation, a week): the call gives its key.
    var needsKey: Bool { [.fix, .threat, .discovery, .automation, .week].contains(self) }

    /// The table of the page: what to do, and its limit.
    var what: String {
        switch self {
        case .visit: return "Premier passage de la journée"
        case .scan: return "Lancer l'analyse intelligente"
        case .cleaning: return "Faire un nettoyage, quelle que soit sa taille"
        case .fix: return "Corriger un point du bilan de sécurité"
        case .threat: return "Neutraliser une menace (chasser une mite)"
        case .update: return "Mettre une app à jour"
        case .tool: return "Utiliser un outil depuis le lanceur"
        case .discovery: return "Découvrir une pièce de la maison"
        case .automation: return "Activer une automatisation"
        case .week: return "Semaine d'entretien : 4 jours sur 7"
        case .welcome: return "Ce que tu avais fait avant sa naissance"
        }
    }

    var limit: String {
        switch self {
        case .visit, .scan: return "1 par jour"
        case .cleaning: return "2 par jour"
        case .update, .tool: return "10 par jour"
        case .threat: return "chaque menace"
        case .fix: return "une fois par point"
        case .discovery: return "une fois par pièce"
        case .automation: return "une fois chacune"
        case .week: return "1 par semaine"
        case .welcome: return "à sa naissance"
        }
    }

    var symbol: String {
        switch self {
        case .visit: return "sun.max"
        case .scan: return "sparkle.magnifyingglass"
        case .cleaning: return "sparkles"
        case .fix: return "lock.shield"
        case .threat: return "ant"
        case .update: return "arrow.down.circle"
        case .tool: return "command"
        case .discovery: return "door.left.hand.open"
        case .automation: return "leaf"
        case .week: return "calendar"
        case .welcome: return "gift"
        }
    }
}

/// A line of its notebook, written in its own voice.
struct RefugeEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var kind: String
    var text: String
    var amount = 0
    /// Events of the same kind on the same day, merged into one line.
    var count = 1
}

/// Everything the Refuge keeps (refuge.json). Every field may be missing from an older file.
struct RefugeState: Codable, Equatable {
    var name = RefugeRules.defaultName
    /// Its first day at the Refuge, nil until it is born.
    var born: Date?
    /// The birth was celebrated and the name chosen.
    var welcomed = false
    /// Every blueberry earned since its birth: never goes down, sets its stage.
    var harvested = 0
    /// What is left to spend at the shop. Every blueberry earned falls into both.
    var basket = 0
    /// The stage the user last saw: a higher one waits for its mue.
    var shownStage = 0
    /// Rewards paid once (`fix:…`, `page:…`, `auto:…`, `threat:…`, `week:…`) and things seen once (`seen:…`).
    var claimed: Set<String> = []
    /// Today, and what paid today, per source.
    var day = ""
    var paidToday: [String: Int] = [:]
    /// The days the app was used lately (the last 28), and how many since its birth.
    var recentDays: [String] = []
    var daysTogether = 0
    /// Everything paid since its birth, per source (the badges count them).
    var totals: [String: Int] = [:]
    var badges: [String: Date] = [:]
    var journal: [RefugeEntry] = []
    /// The app without the game: no ceremony, no message, the Refuge out of the sidebar.
    var sober = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? RefugeRules.defaultName
        born = try c.decodeIfPresent(Date.self, forKey: .born)
        welcomed = try c.decodeIfPresent(Bool.self, forKey: .welcomed) ?? false
        harvested = max(0, try c.decodeIfPresent(Int.self, forKey: .harvested) ?? 0)
        basket = max(0, try c.decodeIfPresent(Int.self, forKey: .basket) ?? 0)
        shownStage = try c.decodeIfPresent(Int.self, forKey: .shownStage) ?? 0
        claimed = try c.decodeIfPresent(Set<String>.self, forKey: .claimed) ?? []
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        paidToday = try c.decodeIfPresent([String: Int].self, forKey: .paidToday) ?? [:]
        recentDays = try c.decodeIfPresent([String].self, forKey: .recentDays) ?? []
        daysTogether = try c.decodeIfPresent(Int.self, forKey: .daysTogether) ?? 0
        totals = try c.decodeIfPresent([String: Int].self, forKey: .totals) ?? [:]
        badges = try c.decodeIfPresent([String: Date].self, forKey: .badges) ?? [:]
        journal = try c.decodeIfPresent([RefugeEntry].self, forKey: .journal) ?? []
        sober = try c.decodeIfPresent(Bool.self, forKey: .sober) ?? false
    }

    var stage: RefugeStage { RefugeStage.at(harvested) }
    func total(_ source: RefugeSource) -> Int { totals[source.rawValue] ?? 0 }
}

/// The badges: good habits, regularity and curiosity, in bronze, silver and gold. Two are secret.
enum RefugeMetal { case bronze, silver, gold }

struct RefugeBadge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let metal: RefugeMetal
    var secret = false
}

/// A room of its house: every tool of the app. It lights up the first time the user goes in.
struct RefugeRoom: Identifiable {
    let page: Page
    let name: String
    var id: String { page.rawValue }
}

/// How it feels: a glance at its face says how the Mac is doing.
enum RefugeMood: String, CaseIterable {
    case happy, sleepy, sneezy, hot, boosted, worried

    var title: String {
        switch self {
        case .happy: return "Content"
        case .sleepy: return "Il dort"
        case .sneezy: return "Atchoum !"
        case .hot: return "Il a chaud"
        case .boosted: return "Boosté"
        case .worried: return "Une mite rôde"
        }
    }
}

/// What the moods read from the Mac.
struct RefugeSignals: Equatable {
    var hour = 12
    /// Junk found by the last cleanup scan, in bytes.
    var junk: Int64 = 0
    var hot = false
    var boost = false
    var threats = 0
}

enum RefugeRules {
    static let defaultName = "Chamois"
    static let nameLimit = 24
    static let journalLimit = 80
    /// The welcome gift of those who used the app before its birth stays below the adult stage.
    static let welcomeLimit = RefugeStage.chamois.threshold - 1

    // MARK: Days

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Its day number since its birth, 1 on the first day.
    static func dayNumber(_ s: RefugeState, now: Date, calendar: Calendar = .current) -> Int {
        guard let born = s.born else { return 0 }
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: born), to: calendar.startOfDay(for: now)).day ?? 0
        return max(1, d + 1)
    }

    // MARK: Earning

    /// A new day: today's limits start again, and the day counts as one more together.
    static func roll(_ s: inout RefugeState, now: Date, calendar: Calendar = .current) {
        let today = dayKey(now, calendar: calendar)
        guard s.day != today else { return }
        s.day = today
        s.paidToday = [:]
        if !s.recentDays.contains(today) {
            s.recentDays.append(today)
            if s.recentDays.count > 28 { s.recentDays.removeFirst(s.recentDays.count - 28) }
            s.daysTogether += 1
        }
    }

    /// Pays `source` if its limits allow it; the blueberries fall into both counters. Returns what was paid.
    @discardableResult
    static func earn(_ s: inout RefugeState, _ source: RefugeSource, key: String? = nil, now: Date,
                     calendar: Calendar = .current) -> Int {
        guard s.born != nil, source != .welcome else { return 0 }
        roll(&s, now: now, calendar: calendar)
        if source.needsKey {
            guard let key, !key.isEmpty, !s.claimed.contains(key) else { return 0 }
        }
        if let cap = source.perDay, s.paidToday[source.rawValue, default: 0] >= cap { return 0 }
        if source.needsKey, let key { s.claimed.insert(key) }
        s.paidToday[source.rawValue, default: 0] += 1
        s.totals[source.rawValue, default: 0] += 1
        s.harvested += source.amount
        s.basket += source.amount
        return source.amount
    }

    /// The week's reward is due: the app opened on 4 of the last 7 days, and not yet paid this week.
    static func weekDue(_ s: RefugeState, now: Date, calendar: Calendar = .current) -> Bool {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }.map { dayKey($0, calendar: calendar) }
        return days.filter(s.recentDays.contains).count >= 4 && !s.claimed.contains("week:" + weekKey(now, calendar: calendar))
    }

    /// The gift of those who already took care of this Mac: cleanups, days of use and tools already known.
    static func welcome(runs: Int, days: Int, pages: Int) -> Int {
        min(welcomeLimit, max(0, runs) * 5 + max(0, days) * 2 + max(0, pages) * 10)
    }

    /// Born today, with the tools already known lit (they paid in the welcome gift).
    static func birth(_ s: inout RefugeState, known: [Page], now: Date, calendar: Calendar = .current) {
        guard s.born == nil else { return }
        s.born = now
        for p in known where rooms.contains(where: { $0.page == p }) { s.claimed.insert("page:" + p.rawValue) }
        roll(&s, now: now, calendar: calendar)
        note(&s, kind: "birth", text: RefugeStage.cabri.line, now: now)
    }

    /// The name the user typed, tidied: no line break, not too long, never empty.
    static func cleanName(_ raw: String) -> String {
        let one = raw.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let short = String(one.prefix(nameLimit)).trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? defaultName : short
    }

    /// The stage waiting for its mue, if it grew since the user last looked.
    static func pendingMue(_ s: RefugeState) -> RefugeStage? {
        guard s.welcomed else { return nil }
        let now = s.stage
        return now.rawValue > s.shownStage ? now : nil
    }

    /// Where it stands: the next stage, how far along, how many blueberries are left.
    static func progress(_ harvested: Int) -> (next: RefugeStage?, fraction: Double, left: Int) {
        let stage = RefugeStage.at(harvested)
        guard let next = stage.next else { return (nil, 1, 0) }
        let span = Double(next.threshold - stage.threshold)
        return (next, min(1, max(0, Double(harvested - stage.threshold) / span)), next.threshold - harvested)
    }

    // MARK: Notebook

    /// Writes a line of its notebook. `merge`: the same kind on the same day adds up on one line.
    static func note(_ s: inout RefugeState, kind: String, text: String, amount: Int = 0, merge: Bool = false, now: Date,
                     calendar: Calendar = .current) {
        if merge, let last = s.journal.last, last.kind == kind, calendar.isDate(last.date, inSameDayAs: now) {
            s.journal[s.journal.count - 1].count += 1
            s.journal[s.journal.count - 1].amount += amount
            s.journal[s.journal.count - 1].text = text
            s.journal[s.journal.count - 1].date = now
            return
        }
        s.journal.append(RefugeEntry(date: now, kind: kind, text: text, amount: amount))
        if s.journal.count > journalLimit { s.journal.removeFirst(s.journal.count - journalLimit) }
    }

    // MARK: Badges

    static let badges: [RefugeBadge] = [
        RefugeBadge(id: "chiffon", title: "Premier coup de chiffon", detail: "Ton premier nettoyage avec lui", symbol: "sparkles", metal: .bronze),
        RefugeBadge(id: "moutons", title: "Chasseur de moutons", detail: "20 nettoyages", symbol: "wind", metal: .silver),
        RefugeBadge(id: "lynx", title: "Œil de lynx", detail: "Ta première analyse intelligente", symbol: "eye", metal: .bronze),
        RefugeBadge(id: "mites", title: "Chasseur de mites", detail: "Une menace neutralisée", symbol: "ant", metal: .silver),
        RefugeBadge(id: "forteresse", title: "Forteresse", detail: "Une note de sécurité d'au moins 90", symbol: "shield.lefthalf.filled", metal: .gold),
        RefugeBadge(id: "ajour", title: "Toujours à jour", detail: "10 mises à jour d'apps", symbol: "arrow.down.circle", metal: .silver),
        RefugeBadge(id: "explorateur", title: "Explorateur", detail: "5 pièces de la maison découvertes", symbol: "map", metal: .bronze),
        RefugeBadge(id: "proprietaire", title: "Tour du propriétaire", detail: "Toutes les pièces découvertes", symbol: "house", metal: .gold),
        RefugeBadge(id: "mainverte", title: "Main verte", detail: "Ta première automatisation", symbol: "leaf", metal: .bronze),
        RefugeBadge(id: "fidele", title: "Fidèle", detail: "30 jours ensemble", symbol: "heart", metal: .gold),
        RefugeBadge(id: "noctambule", title: "Noctambule", detail: "Une analyse entre minuit et 5 h", symbol: "moon.stars", metal: .silver, secret: true),
        RefugeBadge(id: "atchoum", title: "Atchoum !", detail: "Dix caresses très vite", symbol: "nose", metal: .bronze, secret: true),
    ]

    /// The badges the state now deserves.
    static func deserved(_ s: RefugeState) -> [String] {
        let rooms = discovered(s).count
        var out: [String] = []
        if s.total(.cleaning) >= 1 { out.append("chiffon") }
        if s.total(.cleaning) >= 20 { out.append("moutons") }
        if s.total(.scan) >= 1 { out.append("lynx") }
        if s.total(.threat) >= 1 { out.append("mites") }
        if s.claimed.contains("seen:forteresse") { out.append("forteresse") }
        if s.total(.update) >= 10 { out.append("ajour") }
        if rooms >= 5 { out.append("explorateur") }
        if rooms >= self.rooms.count { out.append("proprietaire") }
        if s.total(.automation) >= 1 { out.append("mainverte") }
        if s.daysTogether >= 30 { out.append("fidele") }
        if s.claimed.contains("seen:noctambule") { out.append("noctambule") }
        if s.claimed.contains("seen:atchoum") { out.append("atchoum") }
        return out
    }

    /// Gives the badges newly deserved, writes them in the notebook, and returns them.
    @discardableResult
    static func award(_ s: inout RefugeState, now: Date) -> [RefugeBadge] {
        guard s.born != nil else { return [] }
        let fresh = deserved(s).filter { s.badges[$0] == nil }
        var out: [RefugeBadge] = []
        for id in fresh {
            guard let b = badges.first(where: { $0.id == id }) else { continue }
            s.badges[id] = now
            note(&s, kind: "badge", text: "Nouvel insigne : « \(b.title) ». Je le pose sur l'étagère.", now: now)
            out.append(b)
        }
        return out
    }

    // MARK: The house

    static let rooms: [RefugeRoom] = [
        RefugeRoom(page: .dashboard, name: "La Grande salle"),
        RefugeRoom(page: .cleanup, name: "La Buanderie"),
        RefugeRoom(page: .protection, name: "La Salle de garde"),
        RefugeRoom(page: .performance, name: "La Salle de sport"),
        RefugeRoom(page: .battery, name: "La Chaufferie"),
        RefugeRoom(page: .updates, name: "La Boîte aux lettres"),
        RefugeRoom(page: .apps, name: "La Cave"),
        RefugeRoom(page: .storage, name: "Le Grenier"),
        RefugeRoom(page: .converter, name: "L'Atelier"),
        RefugeRoom(page: .fillsign, name: "Le Secrétaire"),
        RefugeRoom(page: .youtube, name: "La Salle de projection"),
        RefugeRoom(page: .cinema, name: "Le Ciné-club"),
        RefugeRoom(page: .translator, name: "La Bibliothèque"),
        RefugeRoom(page: .toolbox, name: "L'Établi"),
        RefugeRoom(page: .clipboard, name: "Le Tiroir à souvenirs"),
        RefugeRoom(page: .network, name: "La Tour radio"),
        RefugeRoom(page: .adblock, name: "Le Toit"),
        RefugeRoom(page: .darkmode, name: "La Chambre noire"),
        RefugeRoom(page: .launcher, name: "Le Bureau"),
        RefugeRoom(page: .hotkeys, name: "Le Tableau des clés"),
        RefugeRoom(page: .windows, name: "La Véranda"),
        RefugeRoom(page: .automation, name: "Le Jardin"),
        RefugeRoom(page: .assistant, name: "Le Salon"),
        RefugeRoom(page: .menubar, name: "La Lucarne"),
    ]

    static func room(_ page: Page) -> RefugeRoom? { rooms.first { $0.page == page } }

    static func discovered(_ s: RefugeState) -> [RefugeRoom] {
        rooms.filter { s.claimed.contains("page:" + $0.page.rawValue) }
    }

    // MARK: Moods

    /// The dust bunnies under the furniture: the junk on a gentle scale, never more than five.
    static func dust(_ junk: Int64) -> Int {
        let gb = Double(max(0, junk)) / 1_000_000_000
        switch gb {
        case ..<0.5: return 0
        case ..<2: return 1
        case ..<5: return 2
        case ..<10: return 3
        case ..<20: return 4
        default: return 5
        }
    }

    static func isNight(_ hour: Int) -> Bool { hour >= 23 || hour < 6 }

    /// One mood at a time, the most useful first: a threat, heat, the Boost, the dust, then the night.
    static func mood(_ s: RefugeSignals) -> RefugeMood {
        if s.threats > 0 { return .worried }
        if s.hot { return .hot }
        if s.boost { return .boosted }
        if dust(s.junk) >= 3 { return .sneezy }
        if isNight(s.hour) { return .sleepy }
        return .happy
    }

    /// What it says about it, in its own voice.
    static func moodLine(_ mood: RefugeMood, signals: RefugeSignals) -> String {
        switch mood {
        case .happy: return "Ton Mac va bien. Je profite de la vue."
        case .sleepy: return "Il est tard, je fais un somme. Ton Mac veille."
        case .sneezy: return "Atchoum ! Il y a \(Fmt.bytes(signals.junk)) de moutons sous les meubles. On fait le ménage ?"
        case .hot: return "Ton processeur chauffe un peu. J'ai chaud, moi aussi."
        case .boosted: return "Boost activé : j'ai mis mes lunettes de course."
        case .worried:
            return signals.threats > 1 ? "\(signals.threats) mites rôdent dans ton Mac. On les chasse ensemble ?"
                : "Une mite rôde dans ton Mac. On la chasse ensemble ?"
        }
    }

    // MARK: Self-test

    static func selfTest() -> [String] {
        var f: [String] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10)) ?? Date()
        func day(_ n: Int, hour: Int = 10) -> Date {
            cal.date(byAdding: DateComponents(day: n, hour: hour - 10), to: start) ?? start
        }

        // Stages.
        let stages = RefugeStage.allCases
        if zip(stages, stages.dropFirst()).contains(where: { $0.threshold >= $1.threshold }) { f.append("Refuge : seuils des stades dans le désordre") }
        if RefugeStage.at(0) != .cabri || RefugeStage.at(59) != .cabri || RefugeStage.at(60) != .eterlou
            || RefugeStage.at(11_999) != .grand || RefugeStage.at(50_000) != .gold {
            f.append("Refuge : stade mal calculé aux seuils")
        }
        if progress(30).next != .eterlou || abs(progress(30).fraction - 0.5) > 0.001 || progress(30).left != 30 { f.append("Refuge : progression fausse") }
        if progress(12_000).next != nil { f.append("Refuge : un stade après le Chamois d'or") }

        // Nothing is paid before its birth.
        var s = RefugeState()
        if earn(&s, .cleaning, now: start) != 0 { f.append("Refuge : des myrtilles avant la naissance") }
        birth(&s, known: [.converter, .refuge], now: start, calendar: cal)
        if s.born == nil || s.journal.count != 1 { f.append("Refuge : naissance mal enregistrée") }
        if !s.claimed.contains("page:converter") || s.claimed.contains("page:refuge") { f.append("Refuge : pièces déjà connues mal allumées") }
        if s.daysTogether != 1 { f.append("Refuge : le jour de naissance ne compte pas") }

        // Daily limits.
        _ = earn(&s, .visit, now: start, calendar: cal)
        _ = earn(&s, .visit, now: day(0, hour: 18), calendar: cal)
        if s.harvested != 2 || s.basket != 2 { f.append("Refuge : premier passage payé \(s.harvested) au lieu de 2") }
        for _ in 0..<3 { _ = earn(&s, .cleaning, now: start, calendar: cal) }
        if s.total(.cleaning) != 2 { f.append("Refuge : plus de 2 nettoyages payés par jour") }
        _ = earn(&s, .visit, now: day(1), calendar: cal)
        if s.total(.visit) != 2 || s.daysTogether != 2 { f.append("Refuge : le lendemain ne repart pas de zéro") }
        // Once per thing.
        if earn(&s, .fix, now: start, calendar: cal) != 0 { f.append("Refuge : un point de sécurité payé sans clé") }
        _ = earn(&s, .fix, key: "fix:firewall", now: day(1), calendar: cal)
        if earn(&s, .fix, key: "fix:firewall", now: day(2), calendar: cal) != 0 { f.append("Refuge : un point de sécurité payé deux fois") }
        if earn(&s, .discovery, key: "page:converter", now: day(1), calendar: cal) != 0 { f.append("Refuge : une pièce déjà connue repayée") }
        if earn(&s, .discovery, key: "page:toolbox", now: day(1), calendar: cal) != 10 { f.append("Refuge : découverte non payée") }
        for _ in 0..<12 { _ = earn(&s, .tool, now: day(1), calendar: cal) }
        if s.total(.tool) != 10 { f.append("Refuge : plus de 10 outils payés par jour") }
        // The basket can go down (the shop), the harvest never does: the stage follows the harvest.
        var spent = s
        spent.basket = 0
        if spent.stage != s.stage { f.append("Refuge : dépenser le panier change le stade") }

        // The week: 4 days out of 7.
        var w = RefugeState()
        birth(&w, known: [], now: day(0), calendar: cal)
        for n in 1...2 { roll(&w, now: day(n), calendar: cal) }
        if weekDue(w, now: day(2), calendar: cal) { f.append("Refuge : semaine payée après 3 jours") }
        roll(&w, now: day(4), calendar: cal)
        if !weekDue(w, now: day(4), calendar: cal) { f.append("Refuge : semaine non payée après 4 jours sur 7") }
        _ = earn(&w, .week, key: "week:" + weekKey(day(4), calendar: cal), now: day(4), calendar: cal)
        if weekDue(w, now: day(4), calendar: cal) { f.append("Refuge : semaine payée deux fois") }

        // The welcome gift stays below the adult stage.
        if RefugeStage.at(welcome(runs: 400, days: 900, pages: 24)) >= .chamois { f.append("Refuge : le cadeau de bienvenue saute jusqu'à l'adulte") }
        if welcome(runs: 0, days: 0, pages: 0) != 0 || welcome(runs: 2, days: 3, pages: 1) != 26 { f.append("Refuge : cadeau de bienvenue mal compté") }

        // The mue waits for the welcome, then for the user's eyes.
        var m = RefugeState()
        m.harvested = 400
        if pendingMue(m) != nil { f.append("Refuge : mue avant la naissance") }
        m.welcomed = true
        if pendingMue(m) != .chamois { f.append("Refuge : mue attendue non signalée") }
        m.shownStage = RefugeStage.chamois.rawValue
        if pendingMue(m) != nil { f.append("Refuge : mue déjà vue reproposée") }

        // Names.
        if cleanName("  \n ") != defaultName || cleanName("Pom\npon") != "Pom pon" || cleanName(String(repeating: "a", count: 60)).count != nameLimit {
            f.append("Refuge : prénom mal nettoyé")
        }

        // The notebook merges and stays short.
        var j = RefugeState()
        note(&j, kind: "update", text: "1", amount: 2, merge: true, now: start, calendar: cal)
        note(&j, kind: "update", text: "2", amount: 2, merge: true, now: day(0, hour: 15), calendar: cal)
        note(&j, kind: "update", text: "3", amount: 2, merge: true, now: day(1), calendar: cal)
        if j.journal.count != 2 || j.journal[0].count != 2 || j.journal[0].amount != 4 { f.append("Refuge : carnet mal regroupé") }
        for i in 0..<100 { note(&j, kind: "x\(i)", text: "", now: start, calendar: cal) }
        if j.journal.count != journalLimit { f.append("Refuge : carnet trop long") }

        // Badges.
        var b = RefugeState()
        birth(&b, known: Array(rooms.prefix(4).map(\.page)), now: start, calendar: cal)
        if !award(&b, now: start).isEmpty { f.append("Refuge : insigne sans raison") }
        b.totals["cleaning"] = 1
        b.claimed.insert("page:" + rooms[10].page.rawValue)
        let got = award(&b, now: start).map(\.id)
        if Set(got) != ["chiffon", "explorateur"] { f.append("Refuge : insignes attendus chiffon et explorateur, obtenus \(got)") }
        if !award(&b, now: start).isEmpty { f.append("Refuge : insigne donné deux fois") }
        for room in rooms { b.claimed.insert("page:" + room.page.rawValue) }
        if award(&b, now: start).map(\.id) != ["proprietaire"] { f.append("Refuge : tour du propriétaire non donné") }
        if Set(badges.map(\.id)).count != badges.count || badges.count != 12 { f.append("Refuge : 12 insignes distincts attendus") }

        // Every page but the Refuge is a room, once.
        let roomPages = rooms.map(\.page)
        if Set(roomPages).count != roomPages.count { f.append("Refuge : une pièce en double") }
        for p in Page.allCases where p != .refuge && !roomPages.contains(p) { f.append("Refuge : \(p.title) n'a pas de pièce") }
        if roomPages.contains(.refuge) { f.append("Refuge : le Refuge est une pièce de lui-même") }

        // Moods.
        if mood(RefugeSignals(hour: 2, junk: 30_000_000_000, hot: true, boost: true, threats: 1)) != .worried { f.append("Refuge : la mite doit passer avant tout") }
        if mood(RefugeSignals(hour: 2, junk: 30_000_000_000, hot: true, boost: true)) != .hot { f.append("Refuge : la chaleur avant le Boost") }
        if mood(RefugeSignals(hour: 2, junk: 30_000_000_000, boost: true)) != .boosted { f.append("Refuge : le Boost avant la poussière") }
        if mood(RefugeSignals(hour: 2, junk: 6_000_000_000)) != .sneezy { f.append("Refuge : la poussière avant la nuit") }
        if mood(RefugeSignals(hour: 23)) != .sleepy || mood(RefugeSignals(hour: 6)) != .happy { f.append("Refuge : nuit mal bornée") }
        if dust(0) != 0 || dust(1_000_000_000) != 1 || dust(500_000_000_000) != 5 { f.append("Refuge : moutons mal comptés") }

        // An older or partial file still opens.
        if let old = try? JSONDecoder.store.decode(RefugeState.self, from: Data(#"{"name":"Pompon","harvested":120}"#.utf8)) {
            if old.name != "Pompon" || old.harvested != 120 || old.basket != 0 || old.welcomed { f.append("Refuge : fichier partiel mal relu") }
        } else {
            f.append("Refuge : un fichier partiel ne s'ouvre pas")
        }
        if let data = try? JSONEncoder.store.encode(s), let back = try? JSONDecoder.store.decode(RefugeState.self, from: data) {
            if back.harvested != s.harvested || back.claimed != s.claimed || back.journal.count != s.journal.count { f.append("Refuge : l'état ne se relit pas à l'identique") }
        } else {
            f.append("Refuge : l'état ne s'enregistre pas")
        }
        return f
    }
}
