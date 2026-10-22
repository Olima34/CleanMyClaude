import AppKit

/// The Windscribe app on this Mac and its `windscribe-cli`, which talks to the running app (and starts it when it is
/// not running: Chamois calls it only on a click, or when Windscribe is already open).
enum VPNWindscribe {
    /// `com.windscribe.client` in the current sources (cmake/integrations/gui.cmake), `com.windscribe.gui.macos` in the
    /// Homebrew cask's uninstall list (older builds).
    static let bundleIDs: Set<String> = ["com.windscribe.client", "com.windscribe.gui.macos"]
    static let appName = "Windscribe.app"
    /// Installed by the app beside itself, and linked into /usr/local/bin.
    static let cliInBundle = "Contents/MacOS/windscribe-cli"
    static let cliLink = "/usr/local/bin/windscribe-cli"

    /// The installed app, nil when there is none (an app in the Trash or on a disk image does not count).
    static func appURL() -> URL? {
        guard !DemoData.isEnabled else { return nil }
        var candidates: [URL] = []
        for id in bundleIDs.sorted() {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { candidates.append(url) }
        }
        candidates.append(URL(fileURLWithPath: "/Applications/" + appName))
        candidates.append(URL(fileURLWithPath: FS.home + "/Applications/" + appName))
        return candidates.first { url in
            let path = url.path
            return !path.contains("/.Trash/") && !path.hasPrefix("/Volumes/") && !path.contains("/Caskroom/")
                && Shell.exists(url.appendingPathComponent(cliInBundle).path)
        }
    }

    /// The CLI to run: the one inside the app, or the link the app installed.
    static func cliPath() -> String? {
        if let app = appURL() { return app.appendingPathComponent(cliInBundle).path }
        guard !DemoData.isEnabled else { return nil }
        let resolved = (cliLink as NSString).resolvingSymlinksInPath
        return resolved.hasSuffix("/" + appName + "/" + cliInBundle) && Shell.exists(resolved) ? resolved : nil
    }

    static var isRunning: Bool {
        guard !DemoData.isEnabled else { return false }
        return NSWorkspace.shared.runningApplications.contains { isWindscribe($0) }
    }

    static func isWindscribe(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier, bundleIDs.contains(id) { return true }
        return app.bundleURL?.lastPathComponent == appName
    }

    /// Opens Windscribe in front: to sign in, or for its own settings.
    static func open() {
        guard !DemoData.isEnabled, let url = appURL() else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    // MARK: The CLI

    /// One `windscribe-cli` at a time (it refuses to run beside another one): Chamois' calls wait for each other here.
    private static let queue = DispatchQueue(label: "cleanmyclaude.vpn.cli", qos: .userInitiated)

    /// Runs the CLI with fixed words (`status`, `disconnect`) or a validated location, off the main thread.
    static func run(_ cli: String, _ args: [String], timeout: TimeInterval = 20) async -> Shell.Output {
        await withCheckedContinuation { continuation in
            queue.async {
                var out = Shell.run(cli, args, timeout: timeout)
                // The user's own windscribe-cli in a terminal: one more try a moment later.
                if !out.ok, VPNStatusParser.failure(out.all) == .busy {
                    usleep(800_000)
                    out = Shell.run(cli, args, timeout: timeout)
                }
                continuation.resume(returning: out)
            }
        }
    }

    static func status(_ cli: String) async -> (VPNStatus?, Shell.Output) {
        let out = await run(cli, ["status"], timeout: 25)
        return (out.ok ? VPNStatusParser.parse(out.out) : nil, out)
    }

    /// `connect -n <location>`: returns once Windscribe took the order ("Connection is in progress…"); the tunnel is
    /// then followed with `status`. The location must be one of the country's known names.
    static func connect(_ cli: String, to location: String, in country: VPNCountry) async -> Shell.Output? {
        guard let safe = VPNCountry.validated(location, for: country) else { return nil }
        ActionLog.write("VPN windscribe-cli connect -n \(safe)")
        return await run(cli, ["connect", "-n", safe], timeout: 40)
    }

    /// `disconnect`: waits until the tunnel is down.
    static func disconnect(_ cli: String) async -> Shell.Output {
        ActionLog.write("VPN windscribe-cli disconnect")
        return await run(cli, ["disconnect"], timeout: 40)
    }
}
