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
    /// The Safari extensions that read each site's colours (paid, on the Mac App Store): Noir, which this page is
    /// modelled on, and Dark Reader's own (beware of its clones).
    static let noirStore = "macappstore://apps.apple.com/app/id1592917505"
    static let darkReaderSafari = "macappstore://apps.apple.com/app/id1438243180"

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

// MARK: - Safari's old style sheet

/// Safari cannot darken a page by itself, and a user style sheet cannot read a page's colours: the one Chamois wrote
/// until v0.3.62 inverted every light page, so a site's dark bars and buttons came out light and its white logos faded.
/// Safari is now left to an extension that reads each site's colours. That style sheet, which Safari may still point to
/// (Réglages › Avancées › Feuille de style), is emptied so that nothing is inverted any more, then can be thrown away.
enum DarkModeStyleSheet {
    static let fileName = "Sombre partout.css"

    /// What the file keeps once retired: no rule at all, and how to unselect it in Safari.
    static let retired = """
    /* Sombre partout · Chamois
       Cette feuille de style n'est plus utilisée : elle retournait les pages comme un négatif,
       et les bandeaux sombres des sites ressortaient en clair. Safari n'en applique plus rien.
       Dans Safari › Réglages… › Avancées, choisis Feuille de style : « Aucune ».
       Pour des pages vraiment sombres : une extension comme Noir ou Dark Reader (App Store). */

    """

    static var path: String { DataStore.folder + "/DarkMode/" + fileName }

    /// Empties the old style sheet if it still has its rules. True when the file is (still) there.
    static func retire() -> Bool {
        guard !DemoData.isEnabled, !Snapshot.isActive, FS.exists(path) else { return false }
        let url = URL(fileURLWithPath: path)
        guard (try? String(contentsOf: url, encoding: .utf8)) != retired else { return true }
        // The app's own file, already replaced in place by every change of tone: replaced once more.
        do {
            try Data(retired.utf8).write(to: url, options: .atomic)
            ActionLog.write("SOMBRE PARTOUT ancienne feuille de style Safari vidée · \(path)")
        } catch {
            ActionLog.write("SOMBRE PARTOUT ancienne feuille de style Safari : échec · \(error.localizedDescription)")
        }
        return true
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
