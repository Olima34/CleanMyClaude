import Foundation
import AppKit

/// The Mac's own appearance (Réglages Système › Apparence).
enum DarkModeAppearance: Equatable, Sendable {
    case light, dark
    /// "Automatique": light by day, dark in the evening.
    case auto(dark: Bool)

    var isDark: Bool {
        switch self {
        case .dark: return true
        case .light: return false
        case .auto(let dark): return dark
        }
    }

    var title: String {
        switch self {
        case .dark: return "Mac en sombre"
        case .light: return "Mac en clair"
        case .auto(let dark): return dark ? "Automatique · sombre" : "Automatique · clair"
        }
    }
}

enum DarkModeSystem {
    private static func global(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static func appearance() -> DarkModeAppearance {
        if DemoData.isEnabled { return .dark }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let dark = (global("AppleInterfaceStyle") as? String) == "Dark"
        if DarkModeAppScan.isTrue(global("AppleInterfaceStyleSwitchesAutomatically")) { return .auto(dark: dark) }
        return dark ? .dark : .light
    }

    /// Asks System Events to switch the Mac to dark (or light): macOS asks once for the permission to drive it.
    static func setDark(_ dark: Bool) -> Shell.Output {
        Shell.appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
    }

    static let appearancePane = "x-apple.systempreferences:com.apple.Appearance-Settings.extension"
    static let automationPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    static let displayPane = "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"
}

/// macOS' "Inverser les couleurs" (Accessibilité › Écran), switched like its own shortcut does. The functions are
/// private to macOS: they are looked up when needed, and every change is read back to check that it happened.
enum DarkModeInvert {
    private typealias Getter = @convention(c) () -> UInt8
    private typealias Setter = @convention(c) (UInt8) -> Void

    private static let getter: Getter? = {
        guard let h = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LAZY), let s = dlsym(h, "_AXSInvertColorsEnabled") else { return nil }
        return unsafeBitCast(s, to: Getter.self)
    }()

    private static let setter: Setter? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_LAZY),
              let s = dlsym(h, "UAInvertColorsUserInitiatedSetEnabled") else { return nil }
        return unsafeBitCast(s, to: Setter.self)
    }()

    /// Both functions were found on this version of macOS.
    static var isAvailable: Bool { !DemoData.isEnabled && getter != nil && setter != nil }

    static var isOn: Bool {
        guard !DemoData.isEnabled, let getter else { return false }
        return getter() != 0
    }

    /// Switches the inversion; true when macOS reports the new state.
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard !DemoData.isEnabled, !Snapshot.isActive, let setter, getter != nil else { return false }
        if isOn == on { return true }
        setter(on ? 1 : 0)
        // The change goes through a daemon: a few tenths of a second.
        for _ in 0..<10 {
            if isOn == on { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return isOn == on
    }
}

/// Inverts the screen while an app chosen "Inversée" is in front, and puts it back when another one comes forward.
/// Nothing runs between two app switches: it only listens to macOS' notification.
@MainActor
final class DarkModeInvertWatcher {
    private var observer: NSObjectProtocol?
    /// The inversion was switched on here (an inversion the user put on by hand is never switched off).
    private(set) var invertedByUs = false
    var apps: Set<String> = []
    /// Called when macOS refused: the page says so.
    var onFailure: (() -> Void)?

    var isWatching: Bool { observer != nil }

    func update(apps: Set<String>) {
        self.apps = apps
        if apps.isEmpty {
            stop()
        } else if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                         object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { self?.activated(id) }
            }
        }
        activated(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func activated(_ id: String?) {
        let wanted = id.map(apps.contains) ?? false
        if wanted, !invertedByUs {
            guard !DarkModeInvert.isOn else { return }
            if DarkModeInvert.set(true) { invertedByUs = true } else { onFailure?() }
        } else if !wanted, invertedByUs {
            DarkModeInvert.set(false)
            invertedByUs = false
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        if invertedByUs {
            DarkModeInvert.set(false)
            invertedByUs = false
        }
    }
}
