import Foundation
import AppKit

// MARK: - Browsers

/// A browser and the way its pages are forced dark.
struct DarkModeBrowser: Identifiable, Equatable, Sendable {
    enum Engine: Equatable, Sendable { case safari, chromium, firefox }

    var bundleID: String
    var name: String
    var appPath: String
    var engine: Engine
    /// Chromium: its "Local State" file, where chrome://flags keeps the switches.
    var localState: String?
    /// Chromium: the "Auto Dark Mode for Web Contents" switch, nil when the browser was never opened.
    var forced: Bool?
    var running: Bool

    var id: String { bundleID }
}

enum DarkModeBrowsers {
    /// The Chromium browsers and where each keeps its Local State (in ~/Library/Application Support).
    static let chromium: [(id: String, name: String, state: String)] = [
        ("com.google.Chrome", "Google Chrome", "Google/Chrome/Local State"),
        ("com.microsoft.edgemac", "Microsoft Edge", "Microsoft Edge/Local State"),
        ("com.brave.Browser", "Brave", "BraveSoftware/Brave-Browser/Local State"),
        ("com.vivaldi.Vivaldi", "Vivaldi", "Vivaldi/Local State"),
        ("com.operasoftware.Opera", "Opera", "com.operasoftware.Opera/Local State"),
        ("company.thebrowser.Browser", "Arc", "Arc/User Data/Local State"),
        ("org.chromium.Chromium", "Chromium", "Chromium/Local State")
    ]
    static let firefox = "org.mozilla.firefox"
    static let safari = "com.apple.Safari"

    /// Dark Reader, free, for Chromium browsers and Firefox.
    static let darkReaderChrome = "https://chromewebstore.google.com/detail/eimadpbcbfnmbkopoojfekhnkhdbieeh"
    static let darkReaderFirefox = "https://addons.mozilla.org/firefox/addon/darkreader/"
    /// Noir, the Safari extension this page is modelled on (paid, on the Mac App Store).
    static let noirStore = "macappstore://apps.apple.com/app/id1592917505"

    /// Only a browser installed in an Applications folder: not the Chromium a developer tool keeps for itself.
    static func appPath(_ id: String) -> String? {
        guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path else { return nil }
        return AppInventory.roots.contains { path.hasPrefix($0 + "/") } ? path : nil
    }

    /// Safari always, then the Chromium browsers and Firefox that are installed.
    static func installed() -> [DarkModeBrowser] {
        if DemoData.isEnabled { return DarkModeDemo.browsers() }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var out = [DarkModeBrowser(bundleID: safari, name: "Safari", appPath: appPath(safari) ?? "/Applications/Safari.app",
                                   engine: .safari, running: running.contains(safari))]
        for c in chromium {
            guard let path = appPath(c.id) else { continue }
            let state = FS.home + "/Library/Application Support/" + c.state
            let forced = (try? Data(contentsOf: URL(fileURLWithPath: state))).flatMap(DarkModeChromium.isForced)
            out.append(DarkModeBrowser(bundleID: c.id, name: c.name, appPath: path, engine: .chromium, localState: state,
                                       forced: forced, running: running.contains(c.id)))
        }
        if let path = appPath(firefox) {
            out.append(DarkModeBrowser(bundleID: firefox, name: "Firefox", appPath: path, engine: .firefox, running: running.contains(firefox)))
        }
        return out
    }
}

// MARK: - Chromium's built-in dark mode for pages

/// chrome://flags/#enable-force-dark, "Auto Dark Mode for Web Contents": Blink darkens every light page itself and
/// leaves the photos alone. The switch lives in the browser's Local State, which it rewrites when it quits: it is
/// changed only while the browser is closed.
enum DarkModeChromium {
    static let flag = "enable-force-dark"
    /// "@1" is "Enabled" in chrome://flags (0 is "Default", the other numbers its variants, the last "Disabled").
    static let enabled = flag + "@1"

    private static func entries(_ root: [String: Any]) -> [String] {
        ((root["browser"] as? [String: Any])?["enabled_labs_experiments"] as? [String]) ?? []
    }

    /// True when the switch is on (any of its "Enabled…" variants), nil when the file cannot be read.
    static func isForced(_ data: Data) -> Bool? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return entries(root).contains { e in
            guard e.hasPrefix(flag + "@"), let n = Int(e.dropFirst(flag.count + 1)) else { return false }
            return (1...8).contains(n)
        }
    }

    /// The same Local State with the switch on or off; everything else untouched. nil if it is not a JSON object.
    static func edit(_ data: Data, enable: Bool) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var browser = root["browser"] as? [String: Any] ?? [:]
        var list = entries(root).filter { $0 != flag && !$0.hasPrefix(flag + "@") }
        if enable { list.append(enabled) }
        browser["enabled_labs_experiments"] = list
        root["browser"] = browser
        return try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes])
    }

    enum Failure: Error { case unreadable, stillRunning, write(String) }

    /// Rewrites Local State with the switch on or off, after a copy of the original in the app's folder.
    /// The browser must be closed.
    static func apply(_ b: DarkModeBrowser, enable: Bool) -> Result<Void, Failure> {
        guard !DemoData.isEnabled, !Snapshot.isActive, let path = b.localState else { return .failure(.write(DemoData.refusal)) }
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == b.bundleID }) else {
            return .failure(.stillRunning)
        }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url), let edited = edit(data, enable: enable) else { return .failure(.unreadable) }
        // The copy: the original as it was before the first change, kept once per browser.
        if let folder = DataStore.ensureFolder("DarkMode/Copies") {
            let backup = folder.appendingPathComponent("\(b.bundleID) Local State.json")
            if !FS.exists(backup.path) {
                try? data.write(to: backup, options: .atomic)
                DataStore.protect(backup)
            }
        }
        do {
            try edited.write(to: url, options: .atomic)
        } catch {
            return .failure(.write(error.localizedDescription))
        }
        ActionLog.write("SOMBRE PARTOUT \(b.name) : pages sombres \(enable ? "forcées" : "rendues au site") · \(path)")
        return .success(())
    }
}

// MARK: - Safari's style sheet

/// How dark the pages turn in Safari.
enum DarkModeTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case black, charcoal, dim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return "Noir"
        case .charcoal: return "Anthracite"
        case .dim: return "Tamisé"
        }
    }

    var detail: String {
        switch self {
        case .black: return "Fond noir, texte blanc : le plus contrasté"
        case .charcoal: return "Fond gris très foncé, plus doux pour les yeux"
        case .dim: return "Texte un peu adouci, pour lire le soir"
        }
    }

    /// Applied after the inversion, to the whole page (photos included, a little).
    var adjust: String {
        switch self {
        case .black: return ""
        case .charcoal: return " contrast(86%)"
        case .dim: return " contrast(80%) brightness(92%)"
        }
    }
}

/// A user style sheet Safari applies to every page (Réglages › Avancées › Feuille de style). Without an extension,
/// CSS cannot read a page's colours: light pages are inverted, photos and videos turned back, and the pages that show
/// their own dark theme are recognised by what they declare and left alone.
enum DarkModeStyleSheet {
    static let fileName = "Sombre partout.css"

    /// Marks of a page already dark, whatever the Mac's appearance (on <html>, or <body> through `:has`).
    static let alwaysDark = [
        "[dark]", "[class*=\"dark\" i]", "[class*=\"night\" i]", "[data-theme*=\"dark\" i]", "[data-color-mode=\"dark\" i]",
        "[data-color-scheme*=\"dark\" i]", "[data-bs-theme=\"dark\" i]", "[data-mode=\"dark\" i]", "[theme*=\"dark\" i]",
        "[style*=\"color-scheme: dark\" i]", "[style*=\"color-scheme:dark\" i]", "[data-darkreader-scheme]", "[data-darkreader-mode]",
        ":has(> head > meta[name=\"color-scheme\" i]:is([content=\"dark\" i], [content=\"only dark\" i]))",
        ":has(> body:is([class*=\"dark\" i], [data-theme*=\"dark\" i], [dark]))"
    ]

    /// Marks of a page that follows the Mac: dark when the Mac is dark, so left alone then.
    static let followsSystem = [
        ":has(> head > meta[name=\"color-scheme\" i][content*=\"dark\" i])",
        ":has(> head > meta[name=\"supported-color-schemes\" i][content*=\"dark\" i])",
        ":has(> head > meta[name=\"theme-color\" i][media*=\"dark\" i])",
        ":has(> head > link[rel~=\"stylesheet\" i][media*=\"dark\" i])",
        "[data-color-mode=\"auto\" i]", "[data-color-mode=\"system\" i]", "[data-theme=\"auto\" i]", "[data-theme=\"system\" i]",
        "[data-theme=\"os\" i]", "[data-color-scheme=\"auto\" i]", "[data-appearance=\"auto\" i]",
        "[class*=\"clientpref-os\" i]", "[class*=\"theme-system\" i]", "[class*=\"theme-auto\" i]",
        "[style*=\"color-scheme: light dark\" i]", "[style*=\"color-scheme:light dark\" i]",
        ":has(> body:is([class*=\"theme-system\" i], [class*=\"theme-auto\" i], [data-theme=\"auto\" i], [data-theme=\"system\" i]))"
    ]

    /// Turned back after the page's inversion: they keep their real colours.
    static let media = [
        "img", "video", "canvas", "iframe", "embed", "object", "svg image",
        "[style*=\"background-image\" i]", "[style*=\"background: url\" i]", "[style*=\"background:url\" i]"
    ]
    /// Inside these, the media are already turned back by their container.
    static let mediaContainers = ["[style*=\"background-image\" i]", "[style*=\"background: url\" i]", "[style*=\"background:url\" i]"]

    static func css(tone: DarkModeTone) -> String {
        let invert = "invert(100%) hue-rotate(180deg)"
        func block(_ skip: [String]) -> String {
            let root = "html:not(\(skip.joined(separator: ", ")))"
            return """
              \(root) {
                filter: \(invert)\(tone.adjust) !important;
                background-color: #fff !important;
              }
              \(root) :is(\(media.joined(separator: ", "))) {
                filter: \(invert) !important;
              }
              \(root) :is(\(mediaContainers.joined(separator: ", "))) *,
              \(root) :is(:fullscreen, :-webkit-full-screen),
              \(root) :is(:fullscreen, :-webkit-full-screen) * {
                filter: none !important;
              }
            """
        }
        return """
        /* Sombre partout · Clean My Claude · teinte \(tone.title)
           Feuille de style pour Safari › Réglages › Avancées › Feuille de style.
           Les pages claires passent en sombre, les photos et les vidéos gardent leurs couleurs,
           les pages qui ont déjà un thème sombre restent telles quelles.
           Pour l'arrêter : Feuille de style « Aucune ». */

        @media screen and (prefers-color-scheme: light) {
        \(block(alwaysDark))
        }

        @media screen and (prefers-color-scheme: dark) {
        \(block(alwaysDark + followsSystem))
        }

        """
    }

    static var url: URL? {
        DataStore.ensureFolder("DarkMode").map { $0.appendingPathComponent(fileName) }
    }

    /// Writes the style sheet in the app's folder (replacing the previous one: it is the app's own file).
    static func write(tone: DarkModeTone) -> Result<URL, DarkModeFailure> {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return .failure(DarkModeFailure(message: DemoData.refusal)) }
        guard let url else { return .failure(DarkModeFailure(message: "Impossible de créer le dossier de Clean My Claude")) }
        do {
            try Data(css(tone: tone).utf8).write(to: url, options: .atomic)
            return .success(url)
        } catch {
            return .failure(DarkModeFailure(message: error.localizedDescription))
        }
    }
}

// MARK: - Safari extensions

/// A Safari extension that darkens pages (Noir, Dark Reader…): better than the style sheet, which it replaces.
struct DarkModeExtension: Equatable, Identifiable, Sendable {
    var identifier: String
    var name: String
    var appPath: String?
    var id: String { identifier }
}

enum DarkModeExtensions {
    static let known = ["noir", "dark reader", "darkreader", "night eye", "nighteye", "dark mode", "darkmode", "midnight", "nightshift for safari"]

    static func matches(_ name: String, _ identifier: String) -> Bool {
        let hay = Fuzzy.fold(name + " " + identifier)
        return known.contains { hay.contains($0) }
    }

    static func installed() -> [DarkModeExtension] {
        if DemoData.isEnabled { return [] }
        let r = Shell.run("/usr/bin/pluginkit", ["-mAvvv", "-p", "com.apple.Safari.web-extension"], timeout: 8)
        return parse(r.out)
    }

    /// `pluginkit -mAvvv` blocks: "identifier(version)" then "Key = value" lines. Only the dark-mode extensions are kept.
    static func parse(_ text: String) -> [DarkModeExtension] {
        var out: [DarkModeExtension] = []
        var current: (id: String, fields: [String: String])?
        func flush() {
            guard let c = current else { return }
            let name = c.fields["Parent Name"] ?? c.fields["Display Name"] ?? c.id
            if matches(name, c.id), !out.contains(where: { $0.identifier == c.id }) {
                out.append(DarkModeExtension(identifier: c.id, name: name, appPath: c.fields["Parent Bundle"]))
            }
            current = nil
        }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let eq = line.range(of: " = ") {
                current?.fields[String(line[..<eq.lowerBound])] = String(line[eq.upperBound...])
                continue
            }
            var head = line
            if let mark = head.first, "+-!=".contains(mark) { head = head.dropFirst().trimmingCharacters(in: .whitespaces) }
            if let paren = head.firstIndex(of: "("), head.hasSuffix(")"), !head.contains(" ") {
                flush()
                current = (String(head[..<paren]), [:])
            }
        }
        flush()
        return out
    }
}
