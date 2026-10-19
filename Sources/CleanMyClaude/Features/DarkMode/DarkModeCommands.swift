import SwiftUI

/// What the page gives the launcher: the Mac in dark, the apps that stay light, Safari, and "sombre <app>".
@MainActor
enum DarkModeCommands {
    static let keywords = ["sombre", "dark", "noir", "nuit", "mode sombre", "dark mode", "thème sombre", "apparence"]

    static func list(_ m: DarkModeModel) -> [AppCommand] {
        let tint = DarkModePage.tint
        return [
            AppCommand(id: "darkmode_open", title: "Sombre partout", subtitle: "Forcer en sombre les apps et les pages web qui restent claires",
                       keywords: keywords + ["forcer", "pages", "sites"], icon: .symbol(Page.darkmode.symbol, tint), group: .actions,
                       assistantSafe: true, urlSafe: true, hint: "Ouvrir") { _ in
                m.openPage()
                return .done
            },
            AppCommand(id: "darkmode_mac", title: "Passer le Mac en sombre", subtitle: "Apparence sombre pour tout le Mac (pas une bascule)",
                       keywords: keywords + ["mac", "système"], icon: .symbol("moon.fill", tint), group: .actions,
                       assistantSafe: true, hint: "Passer") { _ in
                m.openPage()
                m.setMacDark()
                return .done
            },
            AppCommand(id: "darkmode_force_apps", title: "Forcer en sombre les apps qui restent claires",
                       subtitle: "Celles qui ignorent le mode sombre le suivent à leur prochaine ouverture",
                       keywords: keywords + ["apps", "forcer", "claires"], icon: .symbol("moon.stars", tint), group: .actions,
                       risk: .confirm("Les apps qui ignorent le mode sombre seront réglées pour le suivre (réglage réversible, « Auto » le défait). Les apps ouvertes le montrent une fois relancées."),
                       assistantSafe: true, hint: "Forcer") { _ in
                m.openPage()
                if m.apps == nil {
                    m.scanApps()
                    return .message("Je regarde d'abord tes apps : relance la commande dans un instant.")
                }
                guard !m.toForce.isEmpty else { return .message("Aucune app ne reste claire.") }
                let n = m.toForce.count
                m.forceAll()
                return .message("\(Fmt.plural(n, "app forcée", "apps forcées")) en sombre")
            },
            AppCommand(id: "darkmode_safari", title: "Pages de Safari en sombre", subtitle: "Prépare la feuille de style qui assombrit toutes les pages",
                       keywords: keywords + ["safari", "pages", "web", "sites", "feuille de style"], icon: .symbol("safari", tint), group: .actions,
                       assistantSafe: true, hint: "Préparer") { _ in
                m.openPage()
                m.prepareSafari()
                return .done
            },
            AppCommand(id: "darkmode_reset", title: "Remettre les apps dans leur apparence d'origine",
                       subtitle: "Défait les réglages Sombre, Clair et Inversée de Sombre partout",
                       keywords: keywords + ["annuler", "rétablir", "origine"], icon: .symbol("arrow.uturn.backward", Theme.bad), group: .actions,
                       risk: .confirm("Chaque app réglée dans Sombre partout retrouve son apparence d'origine.")) { _ in
                m.resetAll()
                return .done
            }
        ]
    }

    /// "sombre word", "dark slack": forces that app.
    static func results(_ raw: String, _ m: DarkModeModel) -> [AppCommand] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard let space = q.firstIndex(of: " "), ["sombre", "dark", "noir"].contains(Fuzzy.fold(String(q[..<space]))),
              let apps = m.apps else { return [] }
        let name = q[space...].trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else { return [] }
        let found = apps.compactMap { a in Fuzzy.score(name, in: a.name).map { (a, $0) } }.sorted { $0.1 > $1.1 }.prefix(3)
        return found.map { a, score in
            let c = m.choice(a)
            return AppCommand(id: "darkmode_app_" + String(a.bundleID.map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(50)),
                              title: "Forcer \(a.name) en sombre",
                              subtitle: c == .dark ? "Déjà forcée" : a.kind == .ownUI ? "Interface \(a.toolkit ?? "maison") : son thème se règle dans l'app" : a.reason,
                              icon: .file(a.path), group: .actions,
                              risk: .confirm("\(a.name) suivra le mode sombre du Mac (« Auto » le défait). Ouverte, elle le montre une fois relancée."),
                              hint: "Forcer", boost: 1200 + score) { _ in
                m.openPage()
                m.setChoice(a, .dark)
                return .done
            }
        }
    }
}

/// Pure checks for `--selftest`.
enum DarkModeChecks {
    static func run() -> [String] {
        var f: [String] = []
        func expect(_ ok: Bool, _ message: String) { if !ok { f.append(message) } }

        // The SDK an app was built with.
        typealias V = DarkModeMachO.Version
        let names: [(String, V?)] = [("macosx10.13", V(major: 10, minor: 13)), ("macosx26.4", V(major: 26, minor: 4)),
                                     ("macosx27.2.internal", V(major: 27, minor: 2)), ("macosx11", V(major: 11, minor: 0)),
                                     ("iphoneos17.0", nil), ("", nil)]
        for (n, want) in names where DarkModeMachO.sdk(name: n) != want { f.append("SDK « \(n) » mal lu") }
        expect(DarkModeMachO.version(0x000A_0D00) == V(major: 10, minor: 13), "version Mach-O 10.13 mal décodée")

        // Mach-O headers: modern, old, universal, and junk.
        let modern = thin(cmd: 0x32, fields: [1, 0x000B_0000, 0x000A_0D00, 0])
        expect(DarkModeMachO.sdk(thin: modern).map { $0.sdk == V(major: 10, minor: 13) && $0.platform == .macOS } == true, "LC_BUILD_VERSION mal lu")
        let catalyst = thin(cmd: 0x32, fields: [6, 0x000D_0000, 0x000D_0000, 0])
        expect(DarkModeMachO.sdk(thin: catalyst)?.platform == .other, "une app Catalyst prise pour une app Mac")
        let old = thin(cmd: 0x24, fields: [0x000A_0900, 0x000A_0C00])
        expect(DarkModeMachO.sdk(thin: old)?.sdk == V(major: 10, minor: 12), "LC_VERSION_MIN_MACOSX mal lu")
        let fat = Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 1, 0x01, 0, 0, 0x0C, 0, 0, 0, 0, 0, 0, 0x10, 0])
        expect(DarkModeMachO.fatSlice(fat) == 0x1000, "binaire universel : tranche mal trouvée")
        let fat64 = Data([0xCA, 0xFE, 0xBA, 0xBF, 0, 0, 0, 1, 0x01, 0, 0, 0x0C, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x40, 0])
        expect(DarkModeMachO.fatSlice(fat64) == 0x4000, "binaire universel 64 bits mal lu")
        expect(DarkModeMachO.fatSlice(modern) == nil, "binaire simple pris pour un universel")
        expect(DarkModeMachO.sdk(thin: Data("pas un binaire".utf8)) == nil, "un fichier quelconque lu comme un binaire")

        // Which apps stay light.
        let v1013 = V(major: 10, minor: 13), v26 = V(major: 26, minor: 4)
        expect(DarkModeAppScan.classify(optsOut: true, sdk: v26, macOS: true, toolkit: nil).0 == .lightOnly, "app réglée claire non repérée")
        expect(DarkModeAppScan.classify(optsOut: false, sdk: v1013, macOS: true, toolkit: nil).0 == .lightOnly, "app d'avant 10.14 non repérée")
        expect(DarkModeAppScan.classify(optsOut: false, sdk: v26, macOS: true, toolkit: nil).0 == .follows, "app récente prise pour claire")
        expect(DarkModeAppScan.classify(optsOut: false, sdk: v26, macOS: true, toolkit: "Electron").0 == .ownUI, "app Electron mal classée")
        expect(DarkModeAppScan.classify(optsOut: false, sdk: V(major: 13, minor: 0), macOS: false, toolkit: nil).0 == .follows,
               "app Catalyst prise pour claire")
        expect(DarkModeAppScan.isTrue("YES") && DarkModeAppScan.isTrue(true) && DarkModeAppScan.isTrue(NSNumber(value: 1))
               && !DarkModeAppScan.isTrue("NO") && !DarkModeAppScan.isTrue(nil), "valeur booléenne d'Info.plist mal lue")

        // What each choice writes.
        expect(DarkModeChoice.dark.requiresAqua == false && DarkModeChoice.light.requiresAqua == true
               && DarkModeChoice.system.requiresAqua == nil && DarkModeChoice.invert.requiresAqua == nil, "valeur écrite par un choix fausse")
        let read = { (status: Int32, out: String, err: String) in DarkModeAppPrefs.parse(Shell.Output(status: status, out: out, err: err)) }
        expect(read(0, "1\n", "") == .value(true) && read(0, "0\n", "") == .value(false), "lecture de defaults fausse")
        expect(read(1, "", "The domain/default pair of (x, NSRequiresAquaSystemAppearance) does not exist") == .value(nil), "clé absente mal lue")
        if case .refused = read(1, "", "Could not write domain; exiting") {} else { f.append("refus de macOS pris pour une clé absente") }

        // Chromium's Local State.
        let state = Data(#"{"browser":{"enabled_labs_experiments":["smooth-scrolling@2","enable-force-dark@3"],"x":1},"user_experience_metrics":{"low_entropy_source3":1234}}"#.utf8)
        expect(DarkModeChromium.isForced(state) == true, "variante du mode sombre de Chrome non reconnue")
        if let on = DarkModeChromium.edit(state, enable: true),
           let root = (try? JSONSerialization.jsonObject(with: on)) as? [String: Any],
           let browser = root["browser"] as? [String: Any], let list = browser["enabled_labs_experiments"] as? [String] {
            expect(list == ["smooth-scrolling@2", DarkModeChromium.enabled], "Local State : mauvaise liste après activation (\(list))")
            expect(browser["x"] as? Int == 1 && root["user_experience_metrics"] != nil, "Local State : réglages voisins perdus")
        } else {
            f.append("Local State : activation impossible")
        }
        if let off = DarkModeChromium.edit(state, enable: false) {
            expect(DarkModeChromium.isForced(off) == false, "Local State : désactivation sans effet")
        } else {
            f.append("Local State : désactivation impossible")
        }
        expect(DarkModeChromium.edit(Data("{}".utf8), enable: true).flatMap(DarkModeChromium.isForced) == true, "Local State vide non complété")
        expect(DarkModeChromium.edit(Data("[1,2]".utf8), enable: true) == nil && DarkModeChromium.isForced(Data("oups".utf8)) == nil,
               "Local State illisible accepté")
        expect(DarkModeChromium.isForced(Data(#"{"browser":{"enabled_labs_experiments":["enable-force-dark@0"]}}"#.utf8)) == false,
               "« Default » du mode sombre de Chrome pris pour activé")

        // Safari's style sheet.
        for tone in DarkModeTone.allCases {
            let css = DarkModeStyleSheet.css(tone: tone)
            expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count, "feuille \(tone.title) : accolades déséquilibrées")
            expect(css.filter { $0 == "(" }.count == css.filter { $0 == ")" }.count, "feuille \(tone.title) : parenthèses déséquilibrées")
            expect(css.contains("prefers-color-scheme: light") && css.contains("prefers-color-scheme: dark"), "feuille \(tone.title) : un mode du Mac oublié")
            expect(css.components(separatedBy: "!important").count - 1 == 8, "feuille \(tone.title) : règle sans !important")
            expect(css.contains("filter: invert(100%) hue-rotate(180deg)\(tone.adjust) !important"), "feuille \(tone.title) : teinte absente")
        }
        expect(Set(DarkModeTone.allCases.map(\.adjust)).count == DarkModeTone.allCases.count, "deux teintes identiques")
        let dark = DarkModeStyleSheet.css(tone: .black).components(separatedBy: "prefers-color-scheme: dark").last ?? ""
        expect(dark.contains("meta[name=\"color-scheme\" i][content*=\"dark\" i]"), "page qui suit le Mac non épargnée en mode sombre")

        // Dark-mode extensions of Safari.
        let plugins = """
        +    net.raymondhill.uBlock-Origin-Lite.Extension(2026.1012)
                 Parent Name = uBlock Origin Lite
        +    com.kuiken.noir.Extension(2024.4)
                 Parent Name = Noir
                 Parent Bundle = /Applications/Noir.app
             org.darkreader.DarkReader.Extension(4.9)
                 Display Name = Dark Reader for Safari
        """
        let ext = DarkModeExtensions.parse(plugins)
        expect(ext.map(\.name) == ["Noir", "Dark Reader for Safari"], "extensions sombres mal reconnues : \(ext.map(\.name))")
        expect(ext.first?.appPath == "/Applications/Noir.app", "app de l'extension perdue")
        return f
    }

    /// A 64-bit Mach-O header with one load command made of `fields` (32-bit little-endian words).
    private static func thin(cmd: UInt32, fields: [UInt32]) -> Data {
        var words: [UInt32] = [0xFEED_FACF, 0x0100_000C, 0, 2, 1, UInt32(8 + 4 * fields.count), 0, 0]
        words += [cmd, UInt32(8 + 4 * fields.count)] + fields
        var d = Data()
        for w in words { withUnsafeBytes(of: w.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}

/// The fictional Mac of `--demo`: its apps come from DemoData's catalogue, their dark mode is made up here.
enum DarkModeDemo {
    private static let kinds: [String: (DarkModeAppKind, String, String?)] = [
        "com.fresque3d.Fresque": (.lightOnly, "Faite pour macOS 10.13, d'avant le mode sombre", nil),
        "fr.cartographe.desktop": (.lightOnly, "Son créateur l'a réglée pour rester claire", nil),
        "fr.sonar.podcasts": (.lightOnly, "Faite pour macOS 10.12, d'avant le mode sombre", nil),
        "com.lanterne.recorder": (.lightOnly, "Son créateur l'a réglée pour rester claire", nil),
        "com.helios.code": (.ownUI, "Dessine sa propre interface : son thème se choisit dans ses réglages", "Electron"),
        "com.ruche.desktop": (.ownUI, "Dessine sa propre interface : son thème se choisit dans ses réglages", "Electron"),
        "app.tisserand.mac": (.ownUI, "Dessine sa propre interface : son thème se choisit dans ses réglages", "Java"),
        "com.boussolevpn.client": (.ownUI, "Dessine sa propre interface : son thème se choisit dans ses réglages", "Qt"),
        "net.cadence.studio": (.ownUI, "Dessine sa propre interface : son thème se choisit dans ses réglages", "Windows (Wine)"),
        "com.retroarcade.app": (.ownUI, "Dessine sa propre interface : son thème se choisit dans ses réglages", "Unity")
    ]

    static func apps() -> [DarkModeApp] {
        DemoData.apps().compactMap { a in
            guard let id = a.bundleID, id != "io.github.olima34.cleanmyclaude" else { return nil }
            let (kind, reason, toolkit) = kinds[id] ?? (.follows, "Faite pour macOS 26.\(a.name.count % 5) : suit le Mac", nil)
            return DarkModeApp(path: a.path, name: a.name, bundleID: id, kind: kind, reason: reason, toolkit: toolkit,
                               sandboxed: a.fromAppStore, override: nil)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func settings() -> DarkModeSettings {
        var s = DarkModeSettings()
        s.choices = ["com.fresque3d.Fresque": .dark, "fr.cartographe.desktop": .dark, "net.cadence.studio": .invert, "com.pixelune.Pixelune": .light]
        s.names = ["com.fresque3d.Fresque": "Fresque 3D", "fr.cartographe.desktop": "Cartographe", "net.cadence.studio": "Cadence Studio",
                   "com.pixelune.Pixelune": "Pixelune"]
        s.originals = Dictionary(uniqueKeysWithValues: s.choices.keys.map { ($0, DarkModeOriginal(value: nil)) })
        s.tone = .charcoal
        s.safariWritten = Date().addingTimeInterval(-2 * 86_400)
        s.safariSelected = true
        return s
    }

    static func browsers() -> [DarkModeBrowser] {
        [DarkModeBrowser(bundleID: DarkModeBrowsers.safari, name: "Safari", appPath: "/Applications/Safari.app", engine: .safari, running: true),
         DarkModeBrowser(bundleID: "com.google.Chrome", name: "Google Chrome", appPath: "/Applications/Google Chrome.app", engine: .chromium,
                         localState: "/Users/exemple/Library/Application Support/Google/Chrome/Local State", forced: true, running: false),
         DarkModeBrowser(bundleID: DarkModeBrowsers.firefox, name: "Firefox", appPath: "/Applications/Firefox.app", engine: .firefox, running: false)]
    }
}

/// `--darkmode css <fichier> [noir|anthracite|tamise]`, `--darkmode apps`, `--darkmode navigateurs`.
enum DarkModeCLI {
    @MainActor
    static func run(_ args: [String]) {
        switch args.first {
        case "css":
            guard args.count >= 2 else { return print("Usage : --darkmode css <fichier.css> [noir|anthracite|tamise]") }
            let tone: DarkModeTone = ["noir": .black, "tamise": .dim, "tamisé": .dim][args.count > 2 ? args[2] : ""] ?? .charcoal
            let url = URL(fileURLWithPath: FS.expand(args[1]))
            do {
                let out = try FileOps.write(Data(DarkModeStyleSheet.css(tone: tone).utf8), to: url)
                print("Feuille de style \(tone.title) écrite : \(out.path)")
            } catch {
                print("✗ \(error.localizedDescription)")
            }
        case "apps":
            for a in DarkModeAppScan.scan() {
                let kind = a.kind == .lightOnly ? "CLAIRE " : a.kind == .ownUI ? "MAISON " : "suit   "
                print("\(kind) \(a.name) (\(a.bundleID)) — \(a.reason)\(a.override.map { " · réglage NSRequiresAquaSystemAppearance = \($0)" } ?? "")")
            }
        case "navigateurs":
            for b in DarkModeBrowsers.installed() {
                print("\(b.name) (\(b.bundleID)) : \(b.engine == .chromium ? (b.forced.map { $0 ? "pages sombres forcées" : "non forcé" } ?? "jamais ouvert") : "réglage guidé")\(b.running ? " · ouvert" : "")")
            }
            let ext = DarkModeExtensions.installed()
            print("Extensions sombres de Safari : \(ext.isEmpty ? "aucune" : ext.map(\.name).joined(separator: ", "))")
            print("Inversion des couleurs : \(DarkModeInvert.isAvailable ? (DarkModeInvert.isOn ? "active" : "disponible") : "indisponible")")
        default:
            print("Usage : --darkmode css <fichier.css> [noir|anthracite|tamise] | apps | navigateurs")
        }
    }
}
