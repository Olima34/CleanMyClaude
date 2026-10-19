import SwiftUI

/// What the ad blocker gives the launcher: install, measure, remove, and "pub <domaine>" to check a domain.
@MainActor
enum AdBlockCommands {
    static let keywords = ["pub", "pubs", "publicité", "publicités", "bloqueur", "adblock", "pisteurs", "trackers", "dns", "bloquer"]

    static func list(_ m: AdBlockModel) -> [AppCommand] {
        let tint = AdBlockPage.tint
        return [
            AppCommand(id: "adblock_install", title: m.installed ? "Réinstaller le bloqueur de pub" : "Installer le bloqueur de pub",
                       subtitle: "Pubs et pisteurs bloqués pour tout le Mac · niveau \(m.settings.level.title)",
                       keywords: keywords + ["installer", "activer"], icon: .symbol("hand.raised", tint), group: .actions,
                       assistantSafe: true, hint: "Installer") { _ in
                m.openPage()
                m.install()
                return .done
            },
            AppCommand(id: "adblock_measure", title: "Mesurer le bloqueur de pub", subtitle: "Combien de pubs et de pisteurs ton Mac bloque vraiment",
                       keywords: keywords + ["mesurer", "tester", "vérifier"], icon: .symbol("gauge.with.needle", tint), group: .actions,
                       assistantSafe: true, urlSafe: true, hint: "Mesurer") { _ in
                m.openPage()
                m.runMeasure()
                return .done
            },
            AppCommand(id: "adblock_remove", title: "Désactiver le bloqueur de pub", subtitle: "Retire le profil DNS : tout redevient comme avant",
                       keywords: keywords + ["désactiver", "retirer", "supprimer"], icon: .symbol("hand.raised.slash", Theme.bad), group: .actions,
                       risk: .confirm("Le profil DNS du bloqueur sera retiré de ton Mac (mot de passe administrateur) : les pubs reviendront.")) { _ in
                m.remove()
                return .done
            }
        ]
    }

    /// "pub exemple.fr", "adblock exemple.fr": checks the domain on the page.
    static func results(_ raw: String, _ m: AdBlockModel) -> [AppCommand] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard let space = q.firstIndex(of: " "), ["pub", "adblock", "bloqué", "bloque"].contains(Fuzzy.fold(String(q[..<space]))),
              let domain = AdBlockDomain.normalize(String(q[space...]), keepWWW: true) else { return [] }
        return [AppCommand(id: "adblock_check", title: "Vérifier « \(domain) » dans le bloqueur de pub",
                           subtitle: m.isExcepted(domain) ? "Dans tes exceptions" : "Bloqué sur ce Mac ? Dans la liste \(m.settings.level.list) ?",
                           icon: .symbol("magnifyingglass", AdBlockPage.tint), group: .actions, hint: "Vérifier", boost: 1500) { _ in
            m.checkText = domain
            m.openPage()
            m.checkDomain()
            return .done
        }]
    }
}

/// Pure checks for `--selftest`: domains, the profile, DNS messages and the reading of answers.
enum AdBlockChecks {
    static func run() -> [String] {
        var f: [String] = []
        func expect(_ ok: Bool, _ message: String) { if !ok { f.append(message) } }

        // Domains typed or pasted.
        let names: [(String, String?)] = [
            ("https://www.Exemple.fr/page?x=1", "exemple.fr"), ("boutique.fr", "boutique.fr"), ("*.pub.exemple.com.", "pub.exemple.com"),
            ("sous.domaine.exemple.co.uk:443", "sous.domaine.exemple.co.uk"), ("192.168.1.1", nil), ("bonjour", nil), ("exa mple.fr", nil),
            ("-moins.fr", nil), ("a..b.fr", nil), ("www.fr", "www.fr"), ("", nil)
        ]
        for (raw, want) in names where AdBlockDomain.normalize(raw) != want {
            f.append("domaine « \(raw) » lu « \(AdBlockDomain.normalize(raw) ?? "rien") » au lieu de « \(want ?? "rien") »")
        }
        expect(AdBlockDomain.normalize("www.lemonde.fr", keepWWW: true) == "www.lemonde.fr", "vérifier un domaine garde www.")

        // The profile: an XML property list macOS can read, with the level's resolver and the exceptions.
        for level in AdBlockLevel.allCases {
            guard let data = AdBlockProfile.data(level: level, exceptions: ["boutique.fr"]),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let payload = (plist["PayloadContent"] as? [[String: Any]])?.first,
                  let dns = payload["DNSSettings"] as? [String: Any] else {
                f.append("profil \(level.title) illisible")
                continue
            }
            expect(plist["PayloadIdentifier"] as? String == AdBlockProfile.identifier, "profil : identifiant (sinon une réinstallation s'ajoute au lieu de remplacer)")
            expect(plist["PayloadType"] as? String == "Configuration" && payload["PayloadType"] as? String == "com.apple.dnsSettings.managed", "profil : types")
            expect(dns["DNSProtocol"] as? String == "HTTPS" && (dns["ServerURL"] as? String)?.hasPrefix("https://") == true, "profil : DNS chiffré en HTTPS")
            let rules = payload["OnDemandRules"] as? [[String: Any]] ?? []
            let domains = ((rules.first?["ActionParameters"] as? [[String: Any]])?.first?["Domains"] as? [String]) ?? []
            expect(domains.contains("boutique.fr") && domains.contains("*.boutique.fr"), "profil : exception et ses sous-domaines")
            expect(domains.contains("captive.apple.com") && domains.contains("home"), "profil : portails Wi-Fi et réseau local hors filtre")
            expect(rules.last?["Action"] as? String == "Connect", "profil : le filtre doit s'appliquer à tout le reste")
        }
        expect(AdBlockLevel.balanced.serverURL != AdBlockLevel.maximal.serverURL, "niveaux : même résolveur")

        // A DNS query, and answers as resolvers give them.
        guard let q = AdBlockDNS.query("pub.exemple.fr", type: 1, id: 0x1234) else { return f + ["requête DNS"] }
        expect(q.count == 12 + 16 + 4 && q[0] == 0x12 && q[1] == 0x34 && q[12] == 3, "requête DNS : en-tête ou nom")
        expect(AdBlockDNS.query(String(repeating: "a", count: 64) + ".fr") == nil, "requête DNS : étiquette trop longue acceptée")
        expect(!AdBlockDNS.base64url(Data([0xFB, 0xFF])).contains(where: { "+/=".contains($0) }), "requête DNS : base64url")
        func answer(_ rcode: UInt8, _ records: [(UInt16, [UInt8])]) -> Data {
            var d = Data(q)
            d[2] = 0x81; d[3] = 0x80 | rcode
            d[6] = 0; d[7] = UInt8(records.count)
            for (type, rdata) in records {
                d.append(contentsOf: [0xC0, 0x0C, UInt8(type >> 8), UInt8(type & 0xFF), 0, 1, 0, 0, 0, 60, 0, UInt8(rdata.count)])
                d.append(contentsOf: rdata)
            }
            return d
        }
        let sinkhole = AdBlockDNS.parse(answer(0, [(1, [0, 0, 0, 0])]))
        expect(sinkhole?.addresses == ["0.0.0.0"] && AdBlockDNS.verdict(rcode: 0, addresses: sinkhole?.addresses ?? []) == .blocked, "réponse 0.0.0.0 = bloqué")
        let real = AdBlockDNS.parse(answer(0, [(1, [93, 184, 216, 34]), (28, [0x26, 0x06] + Array(repeating: 0, count: 13) + [1])]))
        expect(real?.addresses == ["93.184.216.34", "2606:0:0:0:0:0:0:1"], "réponse : adresses lues \(real?.addresses ?? [])")
        expect(AdBlockDNS.verdict(rcode: 0, addresses: real?.addresses ?? []) == .open, "vraie adresse = ouvert")
        expect(AdBlockDNS.verdict(rcode: 3, addresses: []) == .missing && AdBlockDNS.verdict(rcode: 2, addresses: []) == .unknown
               && AdBlockDNS.verdict(rcode: 5, addresses: []) == .blocked, "NXDOMAIN / SERVFAIL / REFUSED")
        expect(AdBlockProbe(domain: "x.fr", shouldBlock: true, verdict: .missing).good, "une pub introuvable est bien bloquée")
        expect(AdBlockDNS.parse(Data([1, 2, 3])) == nil, "réponse tronquée acceptée")

        // The state from the three canaries.
        expect(AdBlockState.from(both: .blocked, maximalOnly: .blocked, reachable: .open) == .on(.maximal), "état : Maximal")
        expect(AdBlockState.from(both: .blocked, maximalOnly: .open, reachable: .open) == .on(.balanced), "état : Équilibré")
        expect(AdBlockState.from(both: .open, maximalOnly: .open, reachable: .open) == .off, "état : inactif")
        expect(AdBlockState.from(both: .unknown, maximalOnly: .unknown, reachable: .unknown) == .offline, "état : sans réseau")
        expect(Set(AdBlockCanary.ads).count == AdBlockCanary.ads.count && AdBlockCanary.ads.contains(AdBlockCanary.both)
               && AdBlockCanary.ads.contains(AdBlockCanary.maximalOnly) && AdBlockCanary.useful.contains(AdBlockCanary.reachable), "témoins")
        return f
    }
}
