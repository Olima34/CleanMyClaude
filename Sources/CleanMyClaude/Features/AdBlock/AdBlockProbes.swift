import Foundation
import SystemConfiguration

/// Asks resolvers about the canary domains: this Mac's own resolver (`getaddrinfo`, the call every app makes, through
/// /etc/hosts and the DNS profile), or a level's resolver directly over HTTPS (to preview a level).
/// Only after a click: nothing is asked in the background.
enum AdBlockProbes {
    /// This Mac: blocked, reachable, or no answer at all (unknown until a useful site shows the network works).
    /// Blocks the calling thread for the lookup: never call it on the main thread.
    static func systemVerdict(_ domain: String) -> AdBlockVerdict {
        guard !DemoData.isEnabled else { return .unknown }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        let error = getaddrinfo(domain, nil, &hints, &list)
        defer { if let list { freeaddrinfo(list) } }
        // No such name: a dead domain, or a blocker answering NXDOMAIN; anything else is "no answer".
        guard error == 0 else { return error == EAI_NONAME ? .missing : .unknown }
        var addresses: [String] = []
        var node = list
        while let n = node {
            if let address = n.pointee.ai_addr {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, n.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    addresses.append(String(cString: host))
                }
            }
            node = n.pointee.ai_next
        }
        return AdBlockDNS.verdict(rcode: 0, addresses: addresses)
    }

    /// Several lookups at once, on threads of their own (each one waits for the network).
    static func systemVerdicts(_ domains: [String]) -> [AdBlockVerdict] {
        final class Results: @unchecked Sendable {
            let lock = NSLock()
            var values: [AdBlockVerdict]
            init(_ n: Int) { values = Array(repeating: .unknown, count: n) }
        }
        let results = Results(domains.count)
        DispatchQueue.concurrentPerform(iterations: domains.count) { i in
            let v = systemVerdict(domains[i])
            results.lock.lock()
            results.values[i] = v
            results.lock.unlock()
        }
        return results.values
    }

    /// The level's resolver, over DNS-over-HTTPS (RFC 8484, GET).
    static func resolverVerdict(_ domain: String, level: AdBlockLevel) async -> AdBlockVerdict {
        guard let q = AdBlockDNS.query(domain), let url = URL(string: level.serverURL + "?dns=" + AdBlockDNS.base64url(q)),
              let (data, _) = try? await HTTP.get(url, headers: ["Accept": "application/dns-message"]),
              let r = AdBlockDNS.parse(data) else { return .unknown }
        return AdBlockDNS.verdict(rcode: r.rcode, addresses: r.addresses)
    }

    /// What this Mac's resolver does now, from three canaries (three short lookups at once).
    static func state() -> AdBlockState {
        let v = systemVerdicts([AdBlockCanary.both, AdBlockCanary.maximalOnly, AdBlockCanary.reachable])
        return AdBlockState.from(both: v[0], maximalOnly: v[1], reachable: v[2])
    }

    /// All the canaries: on this Mac (`level` nil) or through a level's resolver.
    static func measure(level: AdBlockLevel?) async -> AdBlockMeasure {
        let domains = AdBlockCanary.ads.map { ($0, true) } + AdBlockCanary.useful.map { ($0, false) }
        var verdicts: [String: AdBlockVerdict] = [:]
        if let level {
            await withTaskGroup(of: (String, AdBlockVerdict).self) { group in
                for (domain, _) in domains { group.addTask { (domain, await resolverVerdict(domain, level: level)) } }
                for await (domain, verdict) in group { verdicts[domain] = verdict }
            }
        } else {
            let found = systemVerdicts(domains.map(\.0))
            for (i, d) in domains.enumerated() { verdicts[d.0] = found[i] }
        }
        let probes = domains.map { AdBlockProbe(domain: $0.0, shouldBlock: $0.1, verdict: verdicts[$0.0] ?? .unknown) }
        return AdBlockMeasure(date: Date(), level: level, probes: probes)
    }

    /// The DNS servers the network gives this Mac (the box, most of the time).
    static func networkResolvers() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "CleanMyClaude.adblock" as CFString, nil, nil),
              let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] else { return [] }
        return dns["ServerAddresses"] as? [String] ?? []
    }
}

/// `CleanMyClaude --adblock …`: the ad blocker from the command line, to measure it and check the profile it writes.
///   --adblock mesure [mac|equilibre|maximal]   what is blocked, on this Mac or through a level's resolver
///   --adblock etat                              what this Mac's resolver does now
///   --adblock verifier <domaine>                one domain, on this Mac and through both levels
///   --adblock profil <fichier.mobileconfig>     writes the profile (Maximal) for inspection, never over a file
enum AdBlockCLI {
    static func run(_ args: [String]) async {
        switch args.first ?? "" {
        case "mesure":
            let which = args.dropFirst().first ?? "mac"
            let level: AdBlockLevel? = which == "equilibre" ? .balanced : which == "maximal" ? .maximal : nil
            let start = Date()
            let m = await AdBlockProbes.measure(level: level)
            print("Mesure \(level.map { "du niveau \($0.title) (\($0.list))" } ?? "de ce Mac") en \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
            print("Pubs et pisteurs bloqués : \(m.blockedAds)/\(m.ads.count) (\(Int(m.share * 100)) %) · sites utiles bloqués : \(m.brokenUseful)/\(m.useful.count)\(m.offline ? " · pas de réseau ?" : "")")
            for p in m.probes where !p.good { print("  \(p.shouldBlock ? "passe" : "bloqué à tort") : \(p.domain) (\(p.verdict.rawValue))") }
        case "etat":
            print("État : \(describe(AdBlockProbes.state())) · DNS du réseau : \(AdBlockProbes.networkResolvers().joined(separator: ", "))")
        case "verifier":
            guard let d = args.dropFirst().first.flatMap({ AdBlockDomain.normalize($0, keepWWW: true) }) else { print("Domaine invalide"); return }
            print("\(d) sur ce Mac : \(AdBlockProbes.systemVerdict(d).rawValue)")
            for level in AdBlockLevel.allCases { print("\(d) avec \(level.title) : \(await AdBlockProbes.resolverVerdict(d, level: level).rawValue)") }
        case "profil":
            guard let path = args.dropFirst().first, let data = AdBlockProfile.data(level: .maximal, exceptions: []) else {
                print("Indique le fichier à écrire.")
                return
            }
            do { print("Écrit : \(try FileOps.write(data, to: URL(fileURLWithPath: path)).path)") } catch { print("Échec : \(error.localizedDescription)") }
        default:
            print("Usage : --adblock mesure [mac|equilibre|maximal] | etat | verifier <domaine> | profil <fichier>")
        }
    }

    static func describe(_ s: AdBlockState) -> String {
        switch s {
        case .unknown, .checking: return "inconnu"
        case .off: return "pubs non bloquées"
        case .offline: return "pas de réseau"
        case .on(let level): return "pubs bloquées" + (level.map { " (niveau \($0.title))" } ?? "")
        }
    }
}
