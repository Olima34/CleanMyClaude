import SwiftUI

// The counter of ads stopped. macOS' resolver (mDNSResponder) writes each lookup in the system log: the site's name is
// masked (<private>), but a blocked answer reads "type: A, rdata: 0.0.0.0" in clear, with the app that asked.
// Counting those lines tells how many ad and tracker requests the blocker stopped, app by app, without ever seeing
// which sites are visited. Read every half hour (about 3 s of work for an hour of log), and when the page opens.

/// What was counted, kept between launches.
struct AdBlockTally: Codable, Equatable {
    var total = 0
    /// "2026-10-20" → requests stopped that day (90 days kept).
    var days: [String: Int] = [:]
    /// App → requests stopped since the start.
    var apps: [String: Int] = [:]
    var since: Date?
    /// The log was read up to this moment.
    var readUntil: Date?

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func add(_ events: [AdBlockLog.Event], readUntil end: Date) {
        for e in events {
            total += 1
            days[Self.dayKey(e.date), default: 0] += 1
            apps[e.app, default: 0] += 1
            if since == nil || e.date < since! { since = e.date }
        }
        readUntil = end
        let oldest = Self.dayKey(end.addingTimeInterval(-90 * 86_400))
        days = days.filter { $0.key >= oldest }
    }

    /// One ad cut by the ad-free player (a YouTube video's ads, a Twitch ad break).
    mutating func addOne(app: String, at date: Date = Date()) {
        total += 1
        days[Self.dayKey(date), default: 0] += 1
        apps[app, default: 0] += 1
        if since == nil { since = date }
    }

    func count(lastDays n: Int, now: Date = Date()) -> Int {
        (0..<n).reduce(0) { $0 + (days[Self.dayKey(now.addingTimeInterval(-Double($1) * 86_400))] ?? 0) }
    }

    /// The last `n` days, oldest first (for the little curve).
    func series(_ n: Int, now: Date = Date()) -> [Double] {
        (0..<n).reversed().map { Double(days[Self.dayKey(now.addingTimeInterval(-Double($0) * 86_400))] ?? 0) }
    }
}

enum AdBlockLog {
    struct Event: Equatable {
        var date: Date
        var app: String
    }

    enum Failure: Error, Equatable {
        case unreadable(String)
    }

    /// mDNSResponder's lines between `start` and `end`: the lookups answered 0.0.0.0, with the app that asked.
    static func read(from start: Date, to end: Date) -> Result<[Event], Failure> {
        guard !DemoData.isEnabled else { return .success([]) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let predicate = "process == \"mDNSResponder\" AND (eventMessage CONTAINS \"getaddrinfo start\" OR eventMessage CONTAINS \"rdata: 0.0.0.0\")"
        let r = Shell.run("/usr/bin/log", ["show", "--start", f.string(from: start), "--end", f.string(from: end), "--style", "compact",
                                           "--predicate", predicate], timeout: 240)
        guard r.ok else {
            return .failure(.unreadable(r.err.isEmpty ? "macOS n'a pas laissé lire son journal." : r.err.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(parse(r.out))
    }

    /// One event per lookup (a request may get several answers: the cached one, then the fresh one).
    static func parse(_ text: String) -> [Event] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        var apps: [String: String] = [:]
        var seen = Set<String>()
        var out: [Event] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            if line.contains("] getaddrinfo start"), let r = request(in: line),
               let pid = line.range(of: "client pid: "), let open = line[pid.upperBound...].firstIndex(of: "("),
               let close = line[open...].firstIndex(of: ")") {
                apps[r] = String(line[line.index(after: open)..<close])
            } else if line.contains("getaddrinfo result"), line.contains("type: A, rdata: 0.0.0.0"), let r = request(in: line),
                      seen.insert(r).inserted, line.count > 23, let date = f.date(from: String(line.prefix(23))) {
                out.append(Event(date: date, app: appName(apps[r])))
            }
        }
        return out
    }

    /// "[R130252->Q9103]" or "[R130252]" → "R130252".
    private static func request(in line: String) -> String? {
        guard let start = line.range(of: "] [R") else { return nil }
        let rest = line[line.index(start.upperBound, offsetBy: -1)...]
        let id = rest.prefix { $0 == "R" || $0.isNumber }
        return id.count > 1 ? String(id) : nil
    }

    /// The log keeps 15 characters of a process name: a readable app name, or "Services de macOS" for its daemons.
    static func appName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Autres apps" }
        let known: [(String, String)] = [
            ("com.apple.WebKi", "Safari et pages web"), ("Safari", "Safari et pages web"), ("Google Chrome", "Google Chrome"),
            ("Microsoft Edge", "Microsoft Edge"), ("Brave Browser", "Brave"), ("firefox", "Firefox"), ("Arc", "Arc"),
            ("Opera", "Opera"), ("Vivaldi", "Vivaldi"), ("Mail", "Mail"), ("Spotify", "Spotify"), ("Discord", "Discord"),
            ("Slack", "Slack"), ("zoom.us", "Zoom"), ("Microsoft Teams", "Teams"), ("Code Helper", "Visual Studio Code")
        ]
        if let hit = known.first(where: { raw.hasPrefix($0.0) }) { return hit.1 }
        // Daemons: lowercase names, often ending in "d" (cloudd, nsurlsessiond, cloudtelemetryd).
        if raw.first?.isLowercase == true { return "Services de macOS" }
        return raw
    }
}

/// Playful orders of magnitude for a number of ads stopped.
struct AdBlockEquivalence: Identifiable, Equatable {
    var id: String
    var symbol: String
    var value: String
    var text: String
}

enum AdBlockFun {
    /// If each ad stopped were a 30-second TV spot, a 5 g flyer 0.1 mm thick, or about 50 KB of data.
    static func equivalences(_ n: Int) -> [AdBlockEquivalence] {
        let grams = Double(n) * 5, meters = Double(n) * 0.0001, megabytes = Double(n) * 0.05
        return [
            AdBlockEquivalence(id: "tv", symbol: "tv", value: duration(seconds: n * 30),
                               text: "de coupures pub à la télé, si chaque pub arrêtée était un spot de 30 secondes"),
            AdBlockEquivalence(id: "paper", symbol: "newspaper", value: mass(grams),
                               text: "de prospectus de 5 g, " + compare(grams / 1000, lead: "le poids", to: weights)),
            AdBlockEquivalence(id: "pile", symbol: "ruler", value: length(meters),
                               text: "de pile, un prospectus sur l'autre, " + compare(meters, lead: "la hauteur", to: heights)),
            AdBlockEquivalence(id: "data", symbol: "arrow.down.circle", value: Fmt.bytes(Int64(megabytes * 1_000_000)),
                               text: "de données en moins (≈ 50 Ko par pub ou pisteur), " + compare(megabytes, lead: "l'équivalent", to: data))
        ]
    }

    static let weights: [(String, String, Double)] = [
        ("une pomme", "pommes", 0.15), ("un chat", "chats", 4), ("une valise en soute", "valises en soute", 23),
        ("un adulte", "adultes", 70), ("un piano", "pianos", 300), ("une voiture", "voitures", 1_200),
        ("un éléphant", "éléphants", 6_000), ("une baleine bleue", "baleines bleues", 150_000)
    ]
    static let heights: [(String, String, Double)] = [
        ("une tasse", "tasses", 0.1), ("une table", "tables", 0.75), ("une porte", "portes", 2), ("une girafe", "girafes", 5.5),
        ("un immeuble de 10 étages", "immeubles de 10 étages", 30), ("la tour Eiffel", "tours Eiffel", 330),
        ("le mont Blanc", "monts Blanc", 4_806), ("l'Everest", "Everest", 8_849)
    ]
    static let data: [(String, String, Double)] = [
        ("une photo", "photos", 3), ("une chanson", "chansons", 4), ("un épisode de série", "épisodes de série", 700),
        ("un film en HD", "films en HD", 4_000)
    ]

    /// "le poids de 3 chats", "la hauteur de la tour Eiffel", "presque l'équivalent d'une chanson":
    /// the biggest reference not above `value` (the smallest one when `value` is below them all).
    static func compare(_ value: Double, lead: String, to refs: [(one: String, many: String, size: Double)]) -> String {
        guard let ref = refs.last(where: { $0.size <= value }) ?? refs.first else { return "" }
        let times = value / ref.size
        if times < 1 { return "presque \(lead) \(of(ref.one))" }
        if times < 1.5 { return "\(lead) \(of(ref.one))" }
        return "\(lead) de \(times < 10 ? Fmt.dec(times) : Fmt.int(times)) \(ref.many)"
    }

    /// "un chat" → "d'un chat", "le mont Blanc" → "du mont Blanc", "l'Everest" → "de l'Everest".
    static func of(_ s: String) -> String {
        if s.hasPrefix("un ") || s.hasPrefix("une ") { return "d'" + s }
        if s.hasPrefix("le ") { return "du " + s.dropFirst(3) }
        return "de " + s
    }

    static func duration(seconds s: Int) -> String {
        if s < 3_600 { return "\(max(1, s / 60)) min" }
        if s < 86_400 { return "\(s / 3_600) h \(String(format: "%02d", s % 3_600 / 60))" }
        return "\(s / 86_400) j \(s % 86_400 / 3_600) h"
    }

    static func mass(_ grams: Double) -> String {
        if grams < 1_000 { return "\(Int(grams)) g" }
        if grams < 1_000_000 { return Fmt.dec(grams / 1_000) + " kg" }
        return Fmt.dec(grams / 1_000_000) + " t"
    }

    static func length(_ meters: Double) -> String {
        if meters < 1 { return "\(Int((meters * 100).rounded())) cm" }
        if meters < 1_000 { return Fmt.dec(meters) + " m" }
        return Fmt.dec(meters / 1_000) + " km"
    }

    /// Steps worth celebrating, with their names.
    static let milestones: [(Int, String)] = [
        (10, "Premières pubs à la poubelle"), (100, "Cent de moins"), (1_000, "Mille pubs balayées"),
        (5_000, "Cinq mille, la mascotte s'échauffe"), (10_000, "Dix mille !"), (50_000, "Cinquante mille, un mur de pubs tombé"),
        (100_000, "Cent mille, la mascotte n'en revient pas"), (1_000_000, "Le million")
    ]

    /// The last step reached (if any) and the next one, with the progress towards it.
    static func milestone(_ n: Int) -> (reached: (Int, String)?, next: (Int, String)?, progress: Double) {
        let reached = milestones.last { $0.0 <= n }
        let next = milestones.first { $0.0 > n }
        let from = Double(reached?.0 ?? 0), to = Double(next?.0 ?? n)
        return (reached, next, to > from ? (Double(n) - from) / (to - from) : 1)
    }
}

/// The counter on the page: the number, the curve of the last two weeks, the orders of magnitude and the apps.
struct AdBlockCounterPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.adblock
        let t = m.tally
        let step = AdBlockFun.milestone(t.total)
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(Fmt.int(t.total))
                                .font(.serif(52)).foregroundStyle(Theme.text).monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.6), value: t.total)
                            if m.counting { BusyMascot(.sweeping, pixel: 2) } else { PixelMascot(pixel: 3, broom: true) }
                        }
                        Text("pubs et pisteurs arrêtés" + (t.since.map { " depuis le \($0.formatted(.dateTime.day().month(.wide).locale(Fmt.fr)))" } ?? ""))
                            .font(.ui(13)).foregroundStyle(Theme.text2)
                        HStack(spacing: 14) {
                            figure(Fmt.int(t.count(lastDays: 1)), "aujourd'hui")
                            figure(Fmt.int(t.count(lastDays: 7)), "sur 7 jours")
                            if let next = step.next {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prochain palier : \(Fmt.int(next.0)) · « \(next.1) »").font(.ui(11)).foregroundStyle(Theme.text3)
                                    UsageBar(fraction: step.progress, tint: AdBlockPage.tint, height: 5).frame(width: 180)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        Sparkline(values: t.series(14), tint: AdBlockPage.tint).frame(width: 220, height: 56)
                        Text("14 derniers jours").font(.ui(10.5)).foregroundStyle(Theme.text3)
                        if let reached = step.reached {
                            Tag(text: reached.1, symbol: "trophy", tint: Theme.good, filled: true)
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), alignment: .leading, spacing: 12) {
                    ForEach(AdBlockFun.equivalences(t.total)) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            IconBadge(symbol: e.symbol, tint: AdBlockPage.tint, size: 26)
                            Text(e.value).font(.serif(22)).foregroundStyle(Theme.text).monospacedDigit()
                            Text(e.text).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(Theme.cardRaised))
                    }
                }
                let apps = t.apps.sorted { $0.value > $1.value }.prefix(5)
                if !apps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Qui essayait de joindre des régies").font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                        ForEach(Array(apps), id: \.key) { name, n in
                            RankRow(name: name, value: Fmt.int(n), fraction: Double(n) / Double(max(1, apps.first?.value ?? 1)), tint: AdBlockPage.tint)
                        }
                    }
                }
                Text(m.countError.map { "Compteur en pause : \($0)" }
                     ?? "Compté sur ce Mac, dans le journal de macOS : les noms des sites y sont masqués, Clean My Claude voit seulement qu'une réponse a été « bloquée ». Les pubs vidéo coupées par le lecteur sans pub sont comptées aussi ; celles qu'une extension de Safari coupe ne le sont pas.")
                    .font(.ui(11)).foregroundStyle(m.countError == nil ? Theme.text3 : Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.ui(15, .semibold)).foregroundStyle(Theme.text).monospacedDigit()
            Text(label).font(.ui(11)).foregroundStyle(Theme.text3)
        }
    }
}
