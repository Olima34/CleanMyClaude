import Foundation
import AppKit

/// What an app does with the Mac's dark mode, read from its bundle.
enum DarkModeAppKind: String, Codable, Sendable {
    /// Built for macOS 10.14 or later, no opt-out: it follows the Mac.
    case follows
    /// Opted out in its Info.plist, or built before dark mode existed: it stays light, and can be made to follow.
    case lightOnly
    /// Draws its own interface (Electron, Qt, Java, Wine…): its theme is chosen inside the app.
    case ownUI
}

/// What the user chose for one app.
enum DarkModeChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The app's own behaviour (its original setting is put back).
    case system
    /// Follows the Mac's dark mode even if it opted out (`NSRequiresAquaSystemAppearance` = NO).
    case dark
    /// Stays light even when the Mac is dark (`NSRequiresAquaSystemAppearance` = YES).
    case light
    /// The screen's colours are inverted while the app is in front: for apps that draw everything themselves.
    case invert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .dark: return "Sombre"
        case .light: return "Clair"
        case .invert: return "Inversée"
        }
    }

    var detail: String {
        switch self {
        case .system: return "Le réglage d'origine de l'app"
        case .dark: return "Suit le mode sombre du Mac, même si elle l'ignore"
        case .light: return "Reste claire, même quand le Mac est sombre"
        case .invert: return "L'écran s'inverse quand elle est au premier plan"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .invert: return "circle.righthalf.filled.inverse"
        }
    }

    /// The value of `NSRequiresAquaSystemAppearance` this choice writes, nil for "put the original back".
    var requiresAqua: Bool? {
        switch self {
        case .dark: return false
        case .light: return true
        case .system, .invert: return nil
        }
    }
}

/// An installed app and how it handles dark mode.
struct DarkModeApp: Identifiable, Equatable, Sendable {
    var path: String
    var name: String
    var bundleID: String
    var kind: DarkModeAppKind
    /// Why, in a few words ("Faite pour macOS 10.13, avant le mode sombre").
    var reason: String
    /// The toolkit that draws its interface, for `.ownUI` ("Electron", "Qt"…).
    var toolkit: String?
    /// Its preferences live in a sandbox container (macOS may ask before they are changed).
    var sandboxed: Bool
    /// The value of `NSRequiresAquaSystemAppearance` found in its preferences (outside a container), nil if absent.
    var override: Bool?

    var id: String { bundleID }
}

/// Reads the macOS SDK an executable was built with, from its Mach-O load commands.
enum DarkModeMachO {
    struct Version: Equatable, Comparable, Sendable {
        var major: Int
        var minor: Int

        static func < (a: Version, b: Version) -> Bool { (a.major, a.minor) < (b.major, b.minor) }
        var text: String { "\(major).\(minor)" }
    }

    /// The first version of macOS with dark mode: apps built with an older SDK stay light.
    static let darkMode = Version(major: 10, minor: 14)

    enum Platform: Equatable, Sendable { case macOS, other }

    /// The SDK and platform of the executable at `path` (the first slice of a universal binary), nil if unreadable.
    static func sdk(ofExecutable path: String) -> (sdk: Version, platform: Platform)? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 4096), head.count >= 8 else { return nil }
        var offset: UInt64 = 0
        if let slice = fatSlice(head) {
            offset = slice
        }
        // The header and its load commands: a few kilobytes, rarely more than 64.
        try? h.seek(toOffset: offset)
        guard let data = try? h.read(upToCount: 256 * 1024) else { return nil }
        return sdk(thin: data)
    }

    /// The offset of the first slice when `head` starts a universal binary (big-endian header), else nil.
    static func fatSlice(_ head: Data) -> UInt64? {
        let magic = u32(head, 0, bigEndian: true)
        guard magic == 0xCAFE_BABE || magic == 0xCAFE_BABF, let count = u32(head, 4, bigEndian: true), count > 0, count < 32 else { return nil }
        if magic == 0xCAFE_BABE {
            return u32(head, 8 + 8, bigEndian: true).map(UInt64.init)
        }
        guard let hi = u32(head, 8 + 8, bigEndian: true), let lo = u32(head, 8 + 12, bigEndian: true) else { return nil }
        return UInt64(hi) << 32 | UInt64(lo)
    }

    /// LC_BUILD_VERSION (macOS 10.14 and later) or LC_VERSION_MIN_MACOSX (older) of a thin Mach-O.
    static func sdk(thin data: Data) -> (sdk: Version, platform: Platform)? {
        guard let magic = u32(data, 0) else { return nil }
        let header: Int
        switch magic {
        case 0xFEED_FACF: header = 32
        case 0xFEED_FACE: header = 28
        default: return nil
        }
        guard let ncmds = u32(data, 16), ncmds < 1024 else { return nil }
        var p = header
        for _ in 0..<ncmds {
            guard let cmd = u32(data, p), let size = u32(data, p + 4), size >= 8 else { return nil }
            switch cmd {
            case 0x32: // LC_BUILD_VERSION: platform, minos, sdk
                guard let platform = u32(data, p + 8), let sdk = u32(data, p + 16) else { return nil }
                return (version(sdk), platform == 1 ? .macOS : .other)
            case 0x24: // LC_VERSION_MIN_MACOSX: version, sdk
                guard let sdk = u32(data, p + 12) else { return nil }
                return (version(sdk), .macOS)
            default:
                p += Int(size)
            }
        }
        return nil
    }

    /// xxxx.yy.zz packed in nibbles.
    static func version(_ packed: UInt32) -> Version {
        Version(major: Int(packed >> 16), minor: Int((packed >> 8) & 0xFF))
    }

    /// "macosx10.13", "macosx26.4", "macosx27.2.internal" → the version; another platform → nil.
    static func sdk(name: String) -> Version? {
        guard name.hasPrefix("macosx") else { return nil }
        let parts = name.dropFirst("macosx".count).split(separator: ".")
        guard let major = parts.first.flatMap({ Int($0) }) else { return nil }
        return Version(major: major, minor: parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
    }

    private static func u32(_ d: Data, _ at: Int, bigEndian: Bool = false) -> UInt32? {
        guard at >= 0, at + 4 <= d.count else { return nil }
        let b = d.startIndex + at
        let v = UInt32(d[b]) | UInt32(d[b + 1]) << 8 | UInt32(d[b + 2]) << 16 | UInt32(d[b + 3]) << 24
        return bigEndian ? v.byteSwapped : v
    }
}

enum DarkModeAppScan {
    static let key = "NSRequiresAquaSystemAppearance"

    /// The toolkit that draws the app's interface, if it is not AppKit or SwiftUI.
    static func toolkit(at path: String) -> String? {
        let c = path + "/Contents/"
        let fw = c + "Frameworks/"
        if FS.exists(fw + "Electron Framework.framework") { return "Electron" }
        if FS.exists(fw + "Chromium Embedded Framework.framework") { return "Chromium" }
        if FS.exists(c + "SharedSupport/wine") || FS.exists(c + "Resources/wine") || FS.exists(c + "SharedSupport/CrossOver") { return "Windows (Wine)" }
        if FS.exists(c + "Java") || FS.exists(c + "Resources/Java") || FS.exists(c + "runtime/Contents/Home") || FS.exists(c + "jbr") { return "Java" }
        if ["QtCore.framework", "QtGui.framework", "QtWidgets.framework"].contains(where: { FS.exists(fw + $0) }) { return "Qt" }
        if FS.exists(fw + "FlutterMacOS.framework") { return "Flutter" }
        if FS.exists(fw + "UnityPlayer.dylib") { return "Unity" }
        return nil
    }

    /// True for "YES", true, 1… as an Info.plist may spell it.
    static func isTrue(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["yes", "true", "1"].contains(s.lowercased()) }
        return false
    }

    /// The pure decision, for the self-tests: the Info.plist opt-out first, then the SDK, then the toolkit.
    static func classify(optsOut: Bool, sdk: DarkModeMachO.Version?, macOS: Bool, toolkit: String?) -> (DarkModeAppKind, String) {
        if optsOut {
            return (.lightOnly, "Son créateur l'a réglée pour rester claire")
        }
        if macOS, let sdk, sdk < DarkModeMachO.darkMode {
            return (.lightOnly, "Faite pour macOS \(sdk.text), d'avant le mode sombre")
        }
        if toolkit != nil {
            return (.ownUI, "Dessine sa propre interface : son thème se choisit dans ses réglages")
        }
        if !macOS {
            return (.follows, "App iPad ou Catalyst : suit le Mac")
        }
        return (.follows, sdk.map { "Faite pour macOS \($0.text) : suit le Mac" } ?? "Suit le Mac")
    }

    /// One app bundle; nil for what is not a regular Mac app (iPhone apps, broken bundles, Clean My Claude itself).
    static func inspect(_ path: String) -> DarkModeApp? {
        guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              id != "io.github.olima34.cleanmyclaude", !FS.exists(path + "/WrappedBundle") else { return nil }
        let info = bundle.infoDictionary ?? [:]
        var sdk = (info["DTSDKName"] as? String).flatMap(DarkModeMachO.sdk(name:))
        var macOS = true
        if let exe = bundle.executablePath, let read = DarkModeMachO.sdk(ofExecutable: exe) {
            macOS = read.platform == .macOS
            if sdk == nil || !macOS { sdk = read.sdk }
        }
        let tk = toolkit(at: path)
        let (kind, reason) = classify(optsOut: isTrue(info[key]), sdk: sdk, macOS: macOS, toolkit: tk)
        let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        let sandboxed = FS.exists(FS.home + "/Library/Containers/" + id)
        // Outside a container the preference is a plain read (no permission); inside, only on a click.
        var override: Bool?
        if !sandboxed, let v = CFPreferencesCopyAppValue(key as CFString, id as CFString) {
            override = isTrue(v)
        }
        return DarkModeApp(path: path, name: name, bundleID: id, kind: kind, reason: reason, toolkit: tk, sandboxed: sandboxed, override: override)
    }

    /// The apps of /Applications and ~/Applications (and their subfolders), by name.
    static func scan() -> [DarkModeApp] {
        if DemoData.isEnabled { return DarkModeDemo.apps() }
        var seen = Set<String>()
        let found = AppInventory.bundlePaths().compactMap(inspect)
        return found.filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Why something could not be done, in words for the user.
struct DarkModeFailure: Error, Equatable {
    var message: String
}

/// Reads and writes `NSRequiresAquaSystemAppearance` in an app's preferences through `defaults`, which finds the
/// sandbox container of App Store apps by itself.
enum DarkModeAppPrefs {
    enum Read: Equatable { case value(Bool?), refused(String) }

    /// `defaults read <id> NSRequiresAquaSystemAppearance`: "1", "0", or a message saying the key is absent.
    static func parse(_ out: Shell.Output) -> Read {
        if out.ok {
            let v = out.out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return .value(["1", "yes", "true"].contains(v))
        }
        let e = out.all.lowercased()
        if e.contains("does not exist") || e.contains("not found") { return .value(nil) }
        return .refused(out.all.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func read(_ id: String) -> Read {
        parse(Shell.run("/usr/bin/defaults", ["read", id, DarkModeAppScan.key], timeout: 8))
    }

    /// Writes the value, or removes it for nil. Returns the error to show, nil when it worked.
    static func write(_ id: String, _ value: Bool?) -> String? {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return DemoData.refusal }
        let args = value.map { ["write", id, DarkModeAppScan.key, "-bool", $0 ? "true" : "false"] } ?? ["delete", id, DarkModeAppScan.key]
        let r = Shell.run("/usr/bin/defaults", args, timeout: 8)
        if r.ok { return nil }
        let e = r.all.lowercased()
        // Removing a key that is not there is what was wanted.
        if value == nil, e.contains("does not exist") || e.contains("not found") { return nil }
        return r.all.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Quits an app the normal way (it may ask to save) and opens it again.
@MainActor
enum DarkModeRelaunch {
    /// False when the app did not quit within `timeout` seconds (a document left unsaved, a question on screen).
    static func relaunch(bundleID: String, path: String, arguments: [String] = [], timeout: TimeInterval = 20) async -> Bool {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return false }
        guard await quit(bundleID: bundleID, timeout: timeout) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        config.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
        return true
    }

    static func quit(bundleID: String, timeout: TimeInterval = 20) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return true }
        for app in running { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if running.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return running.allSatisfy(\.isTerminated)
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
