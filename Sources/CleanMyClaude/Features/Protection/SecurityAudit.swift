import Foundation

struct SecurityCheck: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var status: Status
    var detail: String
    var advice: String? = nil
    var settingsURL: String? = nil
    /// Counted in the security score.
    var scored = true
}

enum SettingsPane {
    static let fileVault = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault"
    static let security = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security"
    static let firewall = "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
    static let updates = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    static let lockScreen = "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
    static let users = "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
    static let sharing = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
    static let loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    static func privacy(_ anchor: String) -> String { "x-apple.systempreferences:com.apple.preference.security?\(anchor)" }
}

/// Reads the state of macOS' own protections. Nothing here needs administrator rights.
enum SecurityAudit {
    static func run() -> [SecurityCheck] {
        let checks: [() -> SecurityCheck] = [fileVault, firewall, gatekeeper, sip, xprotect, updates, screenLock,
                                             autoLogin, guest, sharing]
        let slots = Slots<SecurityCheck>(count: checks.count)
        DispatchQueue.concurrentPerform(iterations: checks.count) { i in _ = slots.set(i, checks[i]()) }
        let byID = Dictionary(uniqueKeysWithValues: slots.all.map { ($0.id, $0) })
        let order = ["filevault", "firewall", "gatekeeper", "sip", "xprotect", "updates", "screenlock", "autologin", "guest", "sharing"]
        return order.compactMap { byID[$0] }
    }

    static func fileVault() -> SecurityCheck {
        let out = Shell.run("/usr/bin/fdesetup", ["status"]).all
        var c = SecurityCheck(id: "filevault", title: "Chiffrement FileVault", symbol: "lock.doc", status: .unknown,
                              detail: "État inconnu", settingsURL: SettingsPane.fileVault)
        if out.contains("FileVault is On") {
            c.status = .ok
            c.detail = "Ton disque est chiffré : sans ton mot de passe, ses données sont illisibles."
        } else if out.contains("in progress") {
            c.status = .info
            c.detail = "Chiffrement en cours."
        } else if out.contains("FileVault is Off") {
            c.status = .bad
            c.detail = "Le disque n'est pas chiffré."
            c.advice = "Si ton Mac est perdu ou volé, n'importe qui peut lire tes fichiers. Active FileVault dans Confidentialité et sécurité."
        }
        return c
    }

    static func firewall() -> SecurityCheck {
        let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"
        let state = Shell.run(tool, ["--getglobalstate"]).all
        let stealth = Shell.run(tool, ["--getstealthmode"]).all
        var c = SecurityCheck(id: "firewall", title: "Coupe-feu", symbol: "flame", status: .unknown,
                              detail: "État inconnu", settingsURL: SettingsPane.firewall)
        if state.contains("enabled") {
            c.status = .ok
            c.detail = "Les connexions entrantes non autorisées sont bloquées" + (stealth.contains("on") ? ", en mode furtif." : ".")
        } else if state.contains("disabled") {
            c.status = .warn
            c.detail = "Le coupe-feu est désactivé."
            c.advice = "Sur un Wi-Fi public, il empêche les autres appareils de se connecter à tes services. Active-le dans Réglages › Réseau › Coupe-feu."
        }
        return c
    }

    static func gatekeeper() -> SecurityCheck {
        let out = Shell.run("/usr/sbin/spctl", ["--status"]).all
        var c = SecurityCheck(id: "gatekeeper", title: "Gatekeeper", symbol: "checkmark.shield", status: .unknown,
                              detail: "État inconnu", settingsURL: SettingsPane.security)
        if out.contains("assessments enabled") {
            c.status = .ok
            c.detail = "Seules les apps signées et vérifiées par Apple s'ouvrent sans avertissement."
        } else if out.contains("disabled") {
            c.status = .bad
            c.detail = "Les apps s'ouvrent sans aucune vérification."
            c.advice = "Réactive-le avec « sudo spctl --master-enable » dans le Terminal."
        }
        return c
    }

    static func sip() -> SecurityCheck {
        let out = Shell.run("/usr/bin/csrutil", ["status"]).all
        var c = SecurityCheck(id: "sip", title: "Protection de l'intégrité du système", symbol: "cpu", status: .unknown,
                              detail: "État inconnu")
        if out.contains("enabled.") {
            c.status = .ok
            c.detail = "Les fichiers de macOS ne peuvent pas être modifiés, même par un administrateur."
        } else if out.contains("disabled") {
            c.status = .bad
            c.detail = "SIP est désactivée : un logiciel malveillant pourrait modifier macOS."
            c.advice = "Réactive-la depuis le mode de récupération avec « csrutil enable »."
        }
        return c
    }

    static func xprotect() -> SecurityCheck {
        let bundles = ["/Library/Apple/System/Library/CoreServices/XProtect.bundle",
                       "/private/var/protected/xprotect/XProtect.bundle"]
        var best: (version: Int, date: Date?)?
        for b in bundles {
            guard let info = NSDictionary(contentsOfFile: b + "/Contents/Info.plist"),
                  let v = Int(info["CFBundleShortVersionString"] as? String ?? "") else { continue }
            if best == nil || v > best!.version { best = (v, FS.modified(b + "/Contents/Info.plist")) }
        }
        guard let best else {
            return SecurityCheck(id: "xprotect", title: "XProtect", symbol: "ant", status: .unknown,
                                 detail: "Version introuvable.", scored: false)
        }
        let when = best.date.map { ", installées \(Fmt.relative($0))" } ?? ""
        return SecurityCheck(id: "xprotect", title: "Antimalware intégré (XProtect)", symbol: "ant", status: .ok,
                             detail: "Actif. Définitions version \(best.version)\(when).", settingsURL: nil)
    }

    static func updates() -> SecurityCheck {
        let out = Shell.run("/usr/bin/defaults", ["export", "/Library/Preferences/com.apple.SoftwareUpdate", "-"]).out
        let plist = (try? PropertyListSerialization.propertyList(from: Data(out.utf8), format: nil)) as? [String: Any] ?? [:]
        func flag(_ k: String) -> Bool { (plist[k] as? Bool) ?? ((plist[k] as? Int).map { $0 != 0 } ?? true) }
        var c = SecurityCheck(id: "updates", title: "Mises à jour automatiques", symbol: "arrow.triangle.2.circlepath",
                              status: .ok, detail: "", settingsURL: SettingsPane.updates)
        let security = flag("CriticalUpdateInstall") && flag("ConfigDataInstall")
        let check = flag("AutomaticCheckEnabled")
        let download = flag("AutomaticDownload")
        let install = flag("AutomaticallyInstallMacOSUpdates")
        if !security {
            c.status = .bad
            c.detail = "Les réponses de sécurité et les fichiers de données système ne s'installent pas seuls."
            c.advice = "Active « Installer les réponses de sécurité et les fichiers système » dans Mise à jour de logiciels › Options."
        } else if !check || !download {
            c.status = .warn
            c.detail = "macOS ne recherche ou ne télécharge pas les mises à jour automatiquement."
            c.advice = "Active la recherche et le téléchargement automatiques dans Mise à jour de logiciels."
        } else {
            c.detail = install ? "macOS se tient à jour tout seul, correctifs de sécurité compris."
                               : "Correctifs de sécurité automatiques ; les mises à jour de macOS attendent ton feu vert."
        }
        return c
    }

    /// Slow (it asks Apple's servers), so it runs on its own.
    static func pendingUpdates() -> SecurityCheck {
        let r = Shell.run("/usr/sbin/softwareupdate", ["-l"], timeout: 90)
        let text = r.all
        var c = SecurityCheck(id: "pending", title: "Mises à jour en attente", symbol: "square.and.arrow.down",
                              status: .unknown, detail: "Impossible de joindre le serveur de mises à jour.",
                              settingsURL: SettingsPane.updates)
        let labels = text.split(separator: "\n").filter { $0.contains("* Label:") }
            .map { $0.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces) }
        if !labels.isEmpty {
            c.status = .warn
            c.detail = labels.prefix(3).joined(separator: ", ")
            c.advice = "Installe-les : la plupart corrigent des failles de sécurité."
        } else if text.contains("No new software available") {
            c.status = .ok
            c.detail = "Ton Mac est à jour."
        }
        return c
    }

    static func screenLock() -> SecurityCheck {
        let out = Shell.run("/usr/sbin/sysadminctl", ["-screenLock", "status"]).all
        var c = SecurityCheck(id: "screenlock", title: "Mot de passe au réveil", symbol: "lock.display", status: .unknown,
                              detail: "État inconnu", settingsURL: SettingsPane.lockScreen)
        if out.contains("is off") {
            c.status = .bad
            c.detail = "Ton Mac se réveille sans demander de mot de passe."
            c.advice = "Règle « Exiger le mot de passe » sur « Immédiatement » dans Écran verrouillé."
        } else if out.contains("immediate") {
            c.status = .ok
            c.detail = "Le mot de passe est demandé immédiatement après la veille."
        } else if let r = out.range(of: #"delay is (\d+) seconds"#, options: .regularExpression) {
            let n = Int(out[r].filter(\.isNumber)) ?? 0
            c.status = n <= 300 ? .ok : .warn
            c.detail = "Le mot de passe est demandé \(Fmt.duration(Double(n))) après la veille."
            if n > 300 { c.advice = "Raccourcis ce délai dans Écran verrouillé." }
        }
        return c
    }

    static func autoLogin() -> SecurityCheck {
        let r = Shell.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.loginwindow", "autoLoginUser"])
        if r.ok, !r.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SecurityCheck(id: "autologin", title: "Ouverture de session automatique", symbol: "person.badge.key",
                                 status: .bad, detail: "Le Mac ouvre la session de \(r.out.trimmingCharacters(in: .whitespacesAndNewlines)) sans mot de passe.",
                                 advice: "Désactive l'ouverture de session automatique dans Utilisateurs et groupes.",
                                 settingsURL: SettingsPane.users)
        }
        return SecurityCheck(id: "autologin", title: "Ouverture de session automatique", symbol: "person.badge.key",
                             status: .ok, detail: "Désactivée : il faut un mot de passe au démarrage.", settingsURL: SettingsPane.users)
    }

    static func guest() -> SecurityCheck {
        let r = Shell.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.loginwindow", "GuestEnabled"])
        let on = r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        return SecurityCheck(id: "guest", title: "Compte invité", symbol: "person.crop.circle.badge.questionmark",
                             status: on ? .warn : .ok,
                             detail: on ? "N'importe qui peut ouvrir une session invité sur ce Mac." : "Désactivé.",
                             advice: on ? "Désactive-le dans Utilisateurs et groupes si tu ne t'en sers pas." : nil,
                             settingsURL: SettingsPane.users)
    }

    static func sharing() -> SecurityCheck {
        let out = Shell.run("/bin/launchctl", ["print-disabled", "system"]).out
        let services: [(String, String, Bool)] = [
            ("com.openssh.sshd", "Connexion à distance (SSH)", true),
            ("com.apple.screensharing", "Partage d'écran", true),
            ("com.apple.AEServer", "Événements Apple à distance", true),
            ("com.apple.smbd", "Partage de fichiers", false)
        ]
        var on: [(String, Bool)] = []
        for (label, name, risky) in services {
            for line in out.split(separator: "\n") where line.contains("\"\(label)\"") {
                if line.contains("=> enabled") || line.contains("=> false") { on.append((name, risky)) }
            }
        }
        var c = SecurityCheck(id: "sharing", title: "Accès à distance", symbol: "network", status: .ok,
                              detail: "Aucun service de partage ou d'accès à distance n'est ouvert.", settingsURL: SettingsPane.sharing)
        if !on.isEmpty {
            c.status = on.contains { $0.1 } ? .warn : .info
            c.detail = "Actifs : " + on.map(\.0).joined(separator: ", ") + "."
            c.advice = "Désactive dans Réglages › Général › Partage ce dont tu ne te sers pas."
        }
        return c
    }
}
