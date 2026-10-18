import AppKit
import ApplicationServices
import CoreLocation
import Security
import UserNotifications

/// Every macOS permission the app may use, with its state and a way to ask for all of them in one go
/// (Réglages › Autorisations › « Tout autoriser »). Nothing is asked without that click.
enum PermissionKind: String, CaseIterable, Identifiable {
    case notifications, location, finder, systemEvents, folders, localNetwork, accessibility, fullDiskAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .location: return "Localisation"
        case .finder: return "Piloter le Finder"
        case .systemEvents: return "Piloter Événements système"
        case .folders: return "Bureau, Documents et Téléchargements"
        case .localNetwork: return "Réseau local"
        case .accessibility: return "Accessibilité"
        case .fullDiskAccess: return "Accès complet au disque"
        }
    }

    var purpose: String {
        switch self {
        case .notifications: return "Alertes de disque ou de mémoire, bilan des automatisations"
        case .location: return "Afficher le nom du réseau Wi-Fi (ta position n'est jamais lue)"
        case .finder: return "Mettre à la Corbeille les apps installées par un administrateur, vider la Corbeille"
        case .systemEvents: return "Mode sombre, redémarrer, éteindre, masquer les autres apps depuis le lanceur"
        case .folders: return "Index des fichiers du lanceur, rangement de Téléchargements, conversions"
        case .localNetwork: return "Mesurer la latence de ta box et des appareils de ton réseau"
        case .accessibility: return "Ranger les fenêtres au clavier, coller depuis l'historique du presse-papiers"
        case .fullDiskAccess: return "Voir la Corbeille, Mail, Safari et les autorisations des autres apps"
        }
    }

    var symbol: String {
        switch self {
        case .notifications: return "bell"
        case .location: return "location"
        case .finder: return "face.smiling"
        case .systemEvents: return "gearshape.2"
        case .folders: return "folder"
        case .localNetwork: return "wifi"
        case .accessibility: return "accessibility"
        case .fullDiskAccess: return "externaldrive.badge.checkmark"
        }
    }

    /// Granted in System Settings by the user (macOS shows no prompt for these): the pane is opened for them.
    var needsSettings: Bool { self == .accessibility || self == .fullDiskAccess }

    var settingsURL: String {
        switch self {
        case .notifications: return "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .location: return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .finder, .systemEvents: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .folders: return "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .localNetwork: return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
        case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .fullDiskAccess: return Permissions.fullDiskAccessURL
        }
    }
}

enum PermissionState: Equatable {
    case granted, denied, notAsked, asked

    var label: String {
        switch self {
        case .granted: return "Accordée"
        case .denied: return "Refusée"
        case .notAsked: return "Pas encore demandée"
        case .asked: return "Demandée"
        }
    }
}

@Observable
@MainActor
final class PermissionCenter {
    static let shared = PermissionCenter()

    var states: [PermissionKind: PermissionState] = [:]
    /// The step of « Tout autoriser » in progress.
    var current: PermissionKind?
    var isRunning = false
    /// Waiting for the user to flip a switch in System Settings.
    var waitingForSettings = false
    @ObservationIgnored private var skipWait = false

    private static let askedKey = "permissions.asked"

    var grantedCount: Int { PermissionKind.allCases.filter { states[$0] == .granted }.count }

    // MARK: State

    func refresh() async {
        if DemoData.isEnabled {
            for k in PermissionKind.allCases { states[k] = .granted }
            return
        }
        var s: [PermissionKind: PermissionState] = [:]
        let notif = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        s[.notifications] = !Notifier.available ? .notAsked
            : (notif == .authorized || notif == .provisional ? .granted : (notif == .denied ? .denied : .notAsked))
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorized: s[.location] = .granted
        case .denied, .restricted: s[.location] = .denied
        default: s[.location] = .notAsked
        }
        let asked = Set(UserDefaults.standard.stringArray(forKey: Self.askedKey) ?? [])
        s[.finder] = await Self.automation("com.apple.finder")
        // System Events only answers while it runs: not running and already asked means "asked".
        let events = await Self.automation("com.apple.systemevents")
        s[.systemEvents] = events == .notAsked && asked.contains(PermissionKind.systemEvents.rawValue) ? .asked : events
        let fda = Permissions.hasFullDiskAccess
        s[.fullDiskAccess] = fda ? .granted : .notAsked
        s[.accessibility] = AXIsProcessTrusted() ? .granted : .notAsked
        // macOS gives no way to read these two without asking: what was asked is remembered. The folders are read
        // off the main thread, and not while macOS may still be showing its question.
        if fda {
            s[.folders] = .granted
        } else if !asked.contains(PermissionKind.folders.rawValue) {
            s[.folders] = .notAsked
        } else if isRunning && current == .folders {
            s[.folders] = states[.folders] ?? .asked
        } else {
            s[.folders] = await Task.detached { Self.foldersReadable() }.value ? .granted : .denied
        }
        s[.localNetwork] = asked.contains(PermissionKind.localNetwork.rawValue) ? .asked : .notAsked
        states = s
    }

    /// Asks macOS whether the app may send Apple events to an app, without showing anything.
    nonisolated static func automation(_ bundleID: String, ask: Bool = false) async -> PermissionState {
        await Task.detached(priority: .userInitiated) {
            var target = AEAddressDesc()
            let created = bundleID.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &target) }
            guard created == noErr else { return PermissionState.notAsked }
            defer { AEDisposeDesc(&target) }
            let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
            switch status {
            case noErr: return .granted
            case OSStatus(errAEEventNotPermitted): return .denied
            default: return .notAsked // not decided yet, or the app is not running
            }
        }.value
    }

    nonisolated private static func foldersReadable() -> Bool {
        ["Desktop", "Documents", "Downloads"].allSatisfy { (try? FileManager.default.contentsOfDirectory(atPath: FS.home + "/" + $0)) != nil }
    }

    // MARK: Asking

    /// Asks for everything still missing, one after the other: macOS' own prompts first, then the two
    /// System Settings switches (the pane opens and the app waits until the switch is on, or « Passer »).
    func requestAll() async {
        guard !isRunning, !DemoData.isEnabled else { return }
        isRunning = true
        defer {
            isRunning = false
            current = nil
            waitingForSettings = false
        }
        await refresh()
        for kind in PermissionKind.allCases where states[kind] != .granted {
            current = kind
            await request(kind)
            await refresh()
        }
    }

    func request(_ kind: PermissionKind) async {
        guard !DemoData.isEnabled else { return }
        switch kind {
        case .notifications:
            guard Notifier.available else { return }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .location:
            LocationAsker.shared.ask()
            await wait(seconds: 30) { CLLocationManager().authorizationStatus != .notDetermined }
        case .finder:
            _ = await Self.automation("com.apple.finder", ask: true)
        case .systemEvents:
            remember(.systemEvents)
            // System Events only answers once launched: a harmless question launches it and shows the prompt.
            _ = await Task.detached { Shell.appleScript("tell application \"System Events\" to get name") }.value
        case .folders:
            remember(.folders)
            // Reading each folder makes macOS ask (without Full Disk Access).
            _ = await Task.detached(priority: .userInitiated) { Self.foldersReadable() }.value
        case .localNetwork:
            remember(.localNetwork)
            _ = await Task.detached(priority: .userInitiated) { () -> Bool in
                let route = Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 5).out
                guard let gateway = route.split(separator: "\n").first(where: { $0.contains("gateway:") })?
                    .split(separator: ":").last?.trimmingCharacters(in: .whitespaces) else { return false }
                return Shell.run("/sbin/ping", ["-c", "1", "-t", "2", gateway], timeout: 5).ok
            }.value
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                Finder.open(kind.settingsURL)
                await waitForSettings { AXIsProcessTrusted() }
            }
        case .fullDiskAccess:
            Finder.open(kind.settingsURL)
            await waitForSettings { Permissions.hasFullDiskAccess }
        }
    }

    /// Lets « Tout autoriser » go on without waiting for a System Settings switch.
    func skip() {
        skipWait = true
    }

    private func waitForSettings(_ done: @escaping @MainActor () -> Bool) async {
        waitingForSettings = true
        skipWait = false
        await wait(seconds: 180) { done() || self.skipWait }
        waitingForSettings = false
    }

    private func wait(seconds: Double, until done: @escaping @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !done() {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func remember(_ kind: PermissionKind) {
        var asked = Set(UserDefaults.standard.stringArray(forKey: Self.askedKey) ?? [])
        asked.insert(kind.rawValue)
        UserDefaults.standard.set(Array(asked), forKey: Self.askedKey)
    }

    // MARK: Signature

    /// True when the app is signed with a real (even local) certificate: macOS then keeps its permissions
    /// from one build to the next. Ad hoc signatures (and `swift build`) change at every build.
    nonisolated static var hasStableSignature: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let certificates = dict[kSecCodeInfoCertificates as String] as? [Any] ?? []
        return !certificates.isEmpty && flags & 0x2 == 0 // 0x2: kSecCodeSignatureAdhoc
    }
}
