import SwiftUI
import AppKit

/// One domain checked by hand: on this Mac, in the chosen level's list, and among the exceptions.
struct AdBlockCheck: Equatable {
    var domain: String
    var onMac: AdBlockVerdict
    var level: AdBlockLevel
    var inList: AdBlockVerdict
    var excepted: Bool
}

/// The ad blocker: a filtering, encrypted DNS for the whole Mac (every browser and app), installed as a macOS profile
/// the user approves in System Settings. Clean My Claude writes the profile, measures what it blocks, keeps the
/// exceptions and removes it. Nothing runs in the background: the DNS does the work, the app only looks when asked.
@Observable
@MainActor
final class AdBlockModel: AppModule {
    static let profilesPane = "x-apple.systempreferences:com.apple.Profiles-Settings.extension"

    var settings = AdBlockSettings() {
        didSet { store.value = settings }
    }
    var state: AdBlockState = .unknown
    var measuring = false
    /// Measuring a level before installing it (its resolver, over HTTPS), rather than this Mac.
    var measuringLevel: AdBlockLevel?
    var checkText = ""
    var check: AdBlockCheck?
    var checking = false
    var exceptionDraft = ""
    var exceptionError: String?
    /// The profile was opened: System Settings waits for the user's approval.
    var waitingForInstall = false
    var removing = false
    /// The DNS servers the network gives this Mac (read with the state).
    var resolvers: [String] = []

    @ObservationIgnored private let store = JSONStore<AdBlockSettings>("adblock", default: AdBlockSettings())
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private weak var app: AppModel?

    init() {
        settings = store.value
    }

    var measure: AdBlockMeasure? { settings.lastMeasure }

    /// A profile was opened for installation by Clean My Claude.
    var installed: Bool { settings.installedLevel != nil }

    /// The level or the exceptions changed since the profile was installed: it must be installed again.
    var needsReinstall: Bool {
        guard let level = settings.installedLevel else { return false }
        return level != settings.level || Set(settings.installedExceptions ?? []) != Set(settings.exceptions)
    }

    // MARK: Module

    var sidebarBadge: String? {
        if case .on = state { return nil }
        return installed && state == .off ? "inactif" : nil
    }

    func start(app: AppModel) {
        self.app = app
    }

    func stop() {
        store.flush()
    }

    func loadDemo() {
        settings = AdBlockSettings()
        settings.level = .maximal
        settings.exceptions = ["boutique-exemple.fr", "suivi.colis-exemple.fr"]
        settings.installedLevel = .maximal
        settings.installedExceptions = settings.exceptions
        settings.installedAt = Date().addingTimeInterval(-3 * 86_400)
        settings.lastMeasure = Self.demoMeasure(level: nil)
        state = .on(.maximal)
        resolvers = ["192.168.1.1"]
        checkText = "securepubads.g.doubleclick.net"
        check = AdBlockCheck(domain: "securepubads.g.doubleclick.net", onMac: .blocked, level: .maximal, inList: .blocked, excepted: false)
    }

    /// What the demo measures: the ads all blocked but one, the useful sites all reachable.
    static func demoMeasure(level: AdBlockLevel?) -> AdBlockMeasure {
        let open: Set<String> = level == .balanced ? ["doubleclick.net", "www.googletagmanager.com", "boot.pbstck.com"] : ["boot.pbstck.com"]
        let probes = AdBlockCanary.ads.map { AdBlockProbe(domain: $0, shouldBlock: true, verdict: open.contains($0) ? .open : .blocked) }
            + AdBlockCanary.useful.map { AdBlockProbe(domain: $0, shouldBlock: false, verdict: .open) }
        return AdBlockMeasure(date: Date().addingTimeInterval(-600), level: level, probes: probes)
    }

    func applySnapshotTab(_ tab: String) {
        switch tab {
        case "intro":
            // Before anything: the blocker never installed, a preview of the Maximal level measured.
            settings.installedLevel = nil
            settings.installedExceptions = nil
            settings.exceptions = []
            settings.lastMeasure = Self.demoMeasure(level: .maximal)
            state = .off
            check = nil
            checkText = ""
        case "installation":
            state = .off
            waitingForInstall = true
        case "reinstaller":
            settings.level = .balanced
        case "attente":
            // At work: a measurement on this Mac and a domain being checked.
            measuring = true
            checking = true
        default:
            break
        }
    }

    func commands(app: AppModel) -> [AppCommand] { AdBlockCommands.list(self) }

    func results(for query: String, app: AppModel) -> [AppCommand] { AdBlockCommands.results(query, self) }

    func selfTest() -> [String] { AdBlockChecks.run() }

    func dump() -> [String] {
        let data = AdBlockProfile.data(level: settings.level, exceptions: settings.exceptions)
        var lines = [
            "Niveau choisi : \(settings.level.title) (\(settings.level.list), \(settings.level.serverURL))",
            "Profil installé par l'app : \(settings.installedLevel.map { "\($0.title), le \(Fmt.relative(settings.installedAt ?? Date()))" } ?? "non")",
            "Exceptions : \(settings.exceptions.isEmpty ? "aucune" : settings.exceptions.joined(separator: ", "))",
            "Profil généré : \(data.map { Fmt.bytes(Int64($0.count)) } ?? "échec") · \(AdBlockProfile.neverConnect(exceptions: settings.exceptions).count) domaines hors filtre"
        ]
        if !DemoData.isEnabled {
            lines.append("État de ce Mac : \(AdBlockCLI.describe(AdBlockProbes.state())) · DNS du réseau : \(AdBlockProbes.networkResolvers().joined(separator: ", "))")
        }
        if let m = measure {
            lines.append("Dernière mesure (\(m.level.map { "niveau \($0.title)" } ?? "ce Mac"), \(Fmt.relative(m.date))) : \(m.blockedAds)/\(m.ads.count) pubs bloquées")
        }
        return lines
    }

    // MARK: State

    /// Three short lookups through this Mac's resolver: is the filter on, and at which level?
    func refreshState() {
        guard !DemoData.isEnabled, !Snapshot.isActive, state != .checking else { return }
        state = .checking
        Task {
            let found = await Task.detached(priority: .userInitiated) { AdBlockProbes.state() }.value
            resolvers = await Task.detached(priority: .utility) { AdBlockProbes.networkResolvers() }.value
            state = found
            if found.isOn { waitingForInstall = false }
        }
    }

    // MARK: Measuring

    /// Every canary domain, on this Mac (`level` nil) or through a level's resolver before installing it.
    func runMeasure(level: AdBlockLevel? = nil) {
        guard !measuring else { return }
        guard !DemoData.isEnabled, !Snapshot.isActive else {
            HUD.show(DemoData.refusal, symbol: "info.circle.fill")
            return
        }
        measuring = true
        measuringLevel = level
        Task {
            let m = await AdBlockProbes.measure(level: level)
            settings.lastMeasure = m
            measuring = false
            measuringLevel = nil
            if level == nil {
                // The measurement tells the state as well.
                let verdict = { (d: String) in m.probes.first { $0.domain == d }?.verdict ?? .unknown }
                state = m.offline ? .offline : AdBlockState.from(both: verdict(AdBlockCanary.both), maximalOnly: verdict(AdBlockCanary.maximalOnly),
                                                                 reachable: m.useful.contains { $0.verdict == .open } ? .open : .unknown)
                if state.isOn { waitingForInstall = false }
            }
            if m.offline { HUD.show("Pas de réponse du réseau : vérifie ta connexion", symbol: "wifi.exclamationmark") }
        }
    }

    // MARK: Checking a domain

    func checkDomain() {
        guard !checking, let domain = AdBlockDomain.normalize(checkText, keepWWW: true) else {
            if !checkText.isEmpty { check = nil; HUD.show("Ce n'est pas un nom de domaine (exemple : pub.exemple.fr)", symbol: "exclamationmark.circle.fill") }
            return
        }
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        checking = true
        let level = settings.level
        Task {
            async let mac = Task.detached(priority: .userInitiated) { AdBlockProbes.systemVerdict(domain) }.value
            async let list = AdBlockProbes.resolverVerdict(domain, level: level)
            let (onMac, inList) = await (mac, list)
            check = AdBlockCheck(domain: domain, onMac: onMac, level: level, inList: inList, excepted: isExcepted(domain))
            checking = false
        }
    }

    func isExcepted(_ domain: String) -> Bool {
        settings.exceptions.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    // MARK: Exceptions

    @discardableResult
    func addException(_ raw: String) -> Bool {
        guard let d = AdBlockDomain.normalize(raw) else {
            exceptionError = "« \(raw.trimmingCharacters(in: .whitespaces)) » n'est pas un nom de domaine (exemple : boutique.fr)."
            return false
        }
        guard !settings.exceptions.contains(d) else {
            exceptionError = "\(d) est déjà dans les exceptions."
            return false
        }
        settings.exceptions.append(d)
        settings.exceptions.sort()
        exceptionError = nil
        exceptionDraft = ""
        if check?.domain == d || check.map({ $0.domain.hasSuffix("." + d) }) == true { check?.excepted = true }
        return true
    }

    func removeException(_ d: String) {
        settings.exceptions.removeAll { $0 == d }
        if let c = check { check?.excepted = isExcepted(c.domain) }
    }

    // MARK: Installing and removing

    /// Writes the profile, hands it to macOS and opens System Settings on the profiles, where the user approves it.
    func install() {
        guard !DemoData.isEnabled, !Snapshot.isActive else {
            HUD.show(DemoData.refusal, symbol: "info.circle.fill")
            return
        }
        guard let data = AdBlockProfile.data(level: settings.level, exceptions: settings.exceptions),
              let folder = DataStore.ensureFolder("AdBlock") else {
            HUD.show("Impossible de préparer le profil", symbol: "xmark.octagon.fill")
            return
        }
        let url = folder.appendingPathComponent(AdBlockProfile.fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            HUD.show("Impossible d'écrire le profil : \(error.localizedDescription)", symbol: "xmark.octagon.fill")
            return
        }
        DataStore.protect(url)
        ActionLog.write("BLOQUEUR DE PUB profil \(settings.level.title) préparé · \(url.path)")
        NSWorkspace.shared.open(url)
        // macOS keeps the profile aside until the user approves it in System Settings: open it there.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { Finder.open(Self.profilesPane) }
        settings.installedLevel = settings.level
        settings.installedExceptions = settings.exceptions
        settings.installedAt = Date()
        waitingForInstall = true
        watchReturn()
    }

    /// Back from System Settings: is the filter on now?
    private func watchReturn() {
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.waitingForInstall else { return }
                // System Settings has just let go of the DNS: a moment for it to apply.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshState() }
            }
        }
    }

    /// Removes the profile (administrator password). If macOS refuses, System Settings opens on the profiles.
    func remove() {
        guard !removing else { return }
        guard !DemoData.isEnabled, !Snapshot.isActive else {
            HUD.show(DemoData.refusal, symbol: "info.circle.fill")
            return
        }
        removing = true
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                Shell.runAsAdmin("/usr/bin/profiles remove -identifier fr.cleanmyclaude.adblock")
            }.value
            removing = false
            if r.ok {
                ActionLog.write("BLOQUEUR DE PUB profil retiré")
                settings.installedLevel = nil
                settings.installedExceptions = nil
                settings.installedAt = nil
                waitingForInstall = false
                HUD.show("Bloqueur de pub retiré : tout est comme avant", symbol: "hand.raised.slash.fill")
                refreshState()
            } else if r.all.contains("-128") {
                return // the password window was cancelled
            } else {
                Finder.open(Self.profilesPane)
                HUD.show("Retire « \(AdBlockProfile.displayName) » dans Réglages Système › Profils", symbol: "info.circle.fill")
            }
        }
    }

    func openProfiles() {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        Finder.open(Self.profilesPane)
    }

    func openPage() {
        guard let app = app ?? AppContext.model else { return }
        app.page = .adblock
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }
}
