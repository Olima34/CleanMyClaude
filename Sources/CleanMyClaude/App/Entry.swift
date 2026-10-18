import Foundation
import SwiftUI
import AppKit

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }
        if let question = value(after: "--ask") {
            // Asks Claude through Claude Code (the user's subscription), exactly like the Assistant page.
            MainActor.assumeIsolated {
                let app = AppModel(liveMonitor: false)
                let ids = AssistantModel.catalog(app: app).map(\.id)
                let model = AssistantModelChoice(rawValue: value(after: "--model") ?? "") ?? .haiku
                let status = AssistantClaudeCode.status()
                print("Claude Code : \(status.binary ?? "introuvable") · connecté : \(status.loggedIn ? "oui (\(status.method ?? "?"))" : "non")")
                do {
                    let t = Date()
                    let a = try AssistantClaudeCode.ask(system: AssistantModel.systemPrompt(app: app, lookups: false, structured: true),
                                                        prompt: "QUESTION :\n" + question,
                                                        schema: AssistantClaudeCode.schema(commandIDs: ids), model: model)
                    print(String(format: "Réponse de %@ en %.1f s, %d jetons :", a.model ?? "?", Date().timeIntervalSince(t), a.tokens))
                    print(a.text)
                    for act in a.actions { print("→ action proposée : \(act.id) — \(act.reason)") }
                } catch {
                    print("✗ \(error.localizedDescription)")
                }
            }
            return
        }
        if args.contains("--languages") {
            // What Apple's on-device translation has on this Mac, from French (the same check as the app).
            final class Done: @unchecked Sendable { var value = false }
            let done = Done()
            Task.detached {
                for l in TranslatorLanguage.all where l.code != "fr" {
                    let s = await TranslatorAvailability.status(from: "fr", to: l.code)
                    print("fr → \(l.code) (\(l.name)) : \(s.label)")
                }
                done.value = true
            }
            // The framework answers on the main run loop: keep it turning while waiting.
            while !done.value { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            return
        }
        if let text = value(after: "--translate") {
            // The translator's Claude engine, from the command line (the on-device engine needs a window).
            let detected = TranslatorLanguage.detect(text)
            let target = TranslatorLanguage.effectiveTarget(value(after: "--to") ?? "en", detected: detected)
            let tone = TranslatorTone(rawValue: value(after: "--tone") ?? "") ?? .neutral
            let model = AssistantModelChoice(rawValue: value(after: "--model") ?? "") ?? .haiku
            let schema: [String: Any] = ["type": "object", "properties": ["reponse": ["type": "string"]],
                                         "required": ["reponse"], "additionalProperties": false]
            print("\(TranslatorLanguage.named(detected)) → \(TranslatorLanguage.named(target)), \(model.familyTitle), ton \(tone.title.lowercased())")
            do {
                let t = Date()
                let a = try AssistantClaudeCode.ask(system: TranslatorModel.claudeSystem(target: target, source: detected, tone: tone),
                                                    prompt: text, schema: schema, model: model, effort: "low", timeout: 180)
                print(String(format: "%.1f s : %@", Date().timeIntervalSince(t), a.text))
            } catch {
                print("✗ \(error.localizedDescription)")
            }
            return
        }
        if args.contains("--dump") {
            MainActor.assumeIsolated { Diagnostics.run() }
            return
        }
        if let i = args.firstIndex(of: "--snapshot") {
            let dir = args.count > i + 1 ? args[i + 1] : "snapshots"
            MainActor.assumeIsolated { Snapshot.run(dir: dir) }
            return
        }
        CleanMyClaudeApp.main()
    }

    static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.count > i + 1 else { return nil }
        return args[i + 1]
    }
}

/// `CleanMyClaude --dump` prints what every scanner finds, without deleting anything.
@MainActor
enum Diagnostics {
    static func timed<T>(_ label: String, _ f: () -> T) -> T {
        let t = Date()
        let r = f()
        print(String(format: "  ⏱ %@ : %.2f s", label, Date().timeIntervalSince(t)))
        return r
    }

    static func run() {
        print("Clean My Claude — diagnostic (lecture seule)" + (DemoData.isEnabled ? " · données de démonstration (fictives)" : ""))
        print("Accès complet au disque : \(Permissions.hasFullDiskAccess ? "oui" : "non")")
        let monitor = SystemMonitor(start: false)
        usleep(500_000)
        monitor.sample()
        print("\n== Système")
        print("  CPU \(Fmt.pct(monitor.cpu)) · RAM \(Fmt.bytes(monitor.memUsed))/\(Fmt.bytes(monitor.memTotal)) (\(monitor.pressure.label)) · swap \(Fmt.bytes(monitor.swapUsed))")
        print("  Disque \(Fmt.bytes(monitor.diskFree)) libres (\(Fmt.bytes(monitor.diskFreeStrict)) strict) sur \(Fmt.bytes(monitor.diskTotal))")
        print("  Réseau ↓\(Fmt.speed(monitor.netIn)) ↑\(Fmt.speed(monitor.netOut)) · uptime \(Fmt.duration(monitor.uptime)) · thermique \(monitor.thermalLabel)")
        if let b = monitor.battery {
            print("  Batterie \(Fmt.pct(b.level)) charge=\(b.isCharging) santé=\(b.health.map(Fmt.pct) ?? "?") cycles=\(b.cycleCount ?? -1)")
        }
        print("  \(SystemMonitor.chipName) · \(SystemMonitor.modelName)")

        let running = RunningApps.snapshot()
        let only = Entry.value(after: "--only")

        if only == nil || only == "cleanup" {
            print("\n== Nettoyage")
            let targets = timed("analyse") { CleanupScanner.scan(running: running) }
            for t in targets where !t.items.isEmpty || t.needsFullDiskAccess {
                let on = t.cleanable.filter(\.defaultOn).reduce(Int64(0)) { $0 + $1.size }
                let blocked = t.items.filter { $0.blockedReason != nil }.count
                print("  [\(t.group.title)] \(t.title) : \(Fmt.bytes(t.size)) en \(t.items.count) éléments" +
                      (t.needsFullDiskAccess ? " — ACCÈS COMPLET REQUIS" : "") +
                      " · coché \(Fmt.bytes(on))" + (blocked > 0 ? " · \(blocked) bloqués (app ouverte)" : ""))
                for i in t.items.prefix(3) { print("      \(Fmt.bytes(i.size))\t\(i.name)\(i.detail.map { " — \($0)" } ?? "")") }
            }
            let fp = CleanupScanner.claudeFootprint()
            print("  Claude gardé : transcripts \(Fmt.bytes(fp.transcripts)), VM \(Fmt.bytes(fp.vm)), versions \(Fmt.bytes(fp.codeVersions))")
        }

        if only == nil || only == "security" {
            print("\n== Sécurité")
            for c in timed("bilan", { SecurityAudit.run() }) {
                print("  \(c.status.label.padding(toLength: 11, withPad: " ", startingAt: 0)) \(c.title) — \(c.detail)")
            }
            print("\n== Éléments persistants")
            let items = timed("signatures") { LaunchItemScanner.scan() }
            for i in items {
                print("  [\(i.domain.rawValue)] \(i.label) · \(i.signature.label)\(i.disabled ? " · désactivé" : "")\(i.running ? " · en cours" : "")" +
                      (i.flags.isEmpty ? "" : " ⚠︎ " + i.flags.map(\.rawValue).joined(separator: ", ")))
            }
            print("\n== Autorisations")
            if let grants = TCCReader.read() {
                print("  \(grants.count) autorisations lues")
            } else {
                print("  Illisibles (accès complet au disque requis)")
            }
            print("\n== Traces")
            for t in PrivacyScanner.scan(running: running) {
                print("  [\(t.group)] \(t.title) · \(t.count.map { "\($0) entrées" } ?? "") \(Fmt.bytes(t.size))\(t.needsFullDiskAccess ? " — ACCÈS REQUIS" : "")\(t.blockedReason.map { " — \($0)" } ?? "")")
            }
        }

        if only == nil || only == "apps" {
            print("\n== Applications")
            let apps = timed("inventaire") { AppInventory.scan(running: running) }
            print("  \(apps.count) apps, \(Fmt.bytes(apps.reduce(0) { $0 + $1.size }))")
            for a in apps.prefix(8) {
                print("  \(Fmt.bytes(a.size))\t\(a.name) \(a.version ?? "") · \(a.architecture.label)\(a.fromAppStore ? " · App Store" : "") · \(a.lastUsed.map(Fmt.relative) ?? "jamais")")
            }
            print("  Inutilisées : \(apps.filter { $0.isUnused && !$0.isApple }.map(\.name).joined(separator: ", "))")
            print("  Intel : \(apps.filter { $0.architecture == .intel }.map(\.name).joined(separator: ", "))")
            if let slack = apps.first(where: { !$0.isApple && $0.bundleID != nil }) {
                let left = Leftovers.find(for: slack)
                print("  Restes de \(slack.name) : \(left.map { "\($0.detail ?? "") \(Fmt.bytes($0.size))" }.joined(separator: ", "))")
            }
            let orphans = timed("restes orphelins") { OrphanFinder.scan(installed: apps, includeContainers: Permissions.hasFullDiskAccess) }
            print("  \(orphans.count) restes orphelins, \(Fmt.bytes(orphans.reduce(0) { $0 + $1.size }))")
            for o in orphans.prefix(8) { print("      \(Fmt.bytes(o.size))\t\(o.name) — \(o.detail ?? "")") }
        }

        if only == nil || only == "processes" {
            print("\n== Processus (groupés par app)")
            for g in ProcessList.sample().sorted(by: { $0.memory > $1.memory }).prefix(8) {
                print("  \(Fmt.bytes(g.memory))\t\(Fmt.dec(g.cpu)) %\t\(g.name) (\(g.processCount))")
            }
        }

        // Modules: `--only <page>` (launcher, converter, toolbox…).
        let app = AppModel(liveMonitor: false)
        for (page, module) in ModuleRegistry.modules(app) where only == page.rawValue {
            print("\n== \(page.title)")
            for line in module.dump() { print("  \(line)") }
        }

        if let path = Entry.value(after: "--storage") {
            print("\n== Stockage : \(path)")
            let r = timed("carte") { StorageScanner.scan(FS.expand(path), isCancelled: { false }) { _, _ in } }
            print("  \(Fmt.bytes(r.root.size)) · \(r.scannedFiles) fichiers · \(r.unreadable) illisibles")
            for c in r.root.children.prefix(10) { print("      \(Fmt.bytes(c.size))\t\(c.name)\(c.complete ? "" : " (+)")") }
            print("  Gros fichiers : \(r.bigFiles.prefix(5).map { "\($0.name) \(Fmt.bytes($0.size))" }.joined(separator: ", "))")
        }
        if let path = Entry.value(after: "--duplicates") {
            print("\n== Doublons : \(path)")
            let groups = timed("doublons") { DuplicateFinder.find(in: [FS.expand(path)], isCancelled: { false }) { _ in } }
            print("  \(groups.count) groupes, \(Fmt.bytes(groups.reduce(0) { $0 + $1.wasted })) en trop")
        }
    }
}

/// `CleanMyClaude --snapshot <dir> [--page cleanup] [--light] [--theme graphite] [--scale 2] [--demo]` renders pages to PNG,
/// with real scan data or, with `--demo`, the fictional Mac of `DemoData`.
/// `--page appearance` renders the theme settings (`--tab edit` shows the editor, on a copy of the theme).
@MainActor
enum Snapshot {
    /// True while rendering: AppKit controls (menus, fields, switches) come out as yellow boxes in `ImageRenderer`
    /// and scroll views come out empty, so views swap them for drawn equivalents.
    nonisolated static let isActive = CommandLine.arguments.contains("--snapshot")

    static func run(dir: String) {
        _ = NSApplication.shared
        let themes = ThemeStore.shared
        if let id = Entry.value(after: "--theme") {
            guard themes.all.contains(where: { $0.id == id }) else {
                print("thème inconnu : \(id) (\(themes.all.map(\.id).joined(separator: ", ")))")
                return
            }
            themes.select(id)
        }
        // A theme that is always light or always dark decides on its own.
        let light = themes.active.appearance == .system ? CommandLine.arguments.contains("--light") : themes.active.appearance == .light
        let appearance = NSAppearance(named: light ? .aqua : .darkAqua)!
        NSApp.appearance = appearance
        let scale = Entry.value(after: "--scale").flatMap(Double.init) ?? 1
        let pageName = Entry.value(after: "--page")
        let only = pageName.flatMap(Page.init(rawValue:))

        // In demo mode the model fills itself with the fictional Mac.
        let model = AppModel(liveMonitor: false)
        model.showOnboarding = false
        if !DemoData.isEnabled { scan(model) }

        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var shots: [(String, AnyView)] = []
        let everything = only == nil && pageName != "appearance"
        if pageName == "appearance" {
            if Entry.value(after: "--tab") == "edit" { themes.duplicate(themes.active) }
            shots.append(("appearance-panel", AnyView(AppearanceSettings())))
        }
        for page in Page.allCases where everything || only == page {
            shots.append((page.rawValue, AnyView(PageView(page: page))))
        }
        if everything || only == .menubar {
            shots.append(("menubar-panel", AnyView(MenuBarPanel())))
        }
        if everything || only == .dashboard {
            shots.append(("onboarding-panel", AnyView(OnboardingView())))
        }
        if everything || only == .launcher {
            // The floating panel, as if the user had typed `--query` (default: a calculation).
            model.launcher.preview(Entry.value(after: "--query") ?? "1250*1,2", app: model)
            shots.append(("launcher-panel", AnyView(LauncherView())))
        }
        if let tab = Entry.value(after: "--tab") {
            model.protection.tab = ProtectionTab(rawValue: tab) ?? model.protection.tab
            model.performance.tab = PerformanceTab(rawValue: tab) ?? model.performance.tab
            model.storage.tab = StorageTab(rawValue: tab) ?? model.storage.tab
            model.apps.filter = AppFilter(rawValue: tab) ?? model.apps.filter
            ModuleRegistry.applySnapshotTab(tab, only: only, app: model)
        }
        for (name, view) in shots {
            if let p = Page(rawValue: name) { model.page = p }
            let content = view
                .environment(model)
                .frame(width: ["menubar-panel": 340, "launcher-panel": LauncherView.width, "onboarding-panel": 520,
                               "appearance-panel": AppearanceSettings.width][name] ?? 1180)
                .padding(name.hasSuffix("-panel") ? 0 : 32)
                .background(Theme.bg)
                .environment(\.colorScheme, light ? .light : .dark)
            appearance.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(content: content)
                renderer.scale = scale
                guard let cg = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                    print("échec \(name)")
                    return
                }
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
                try? png.write(to: url)
                print("écrit \(url.path) \(cg.width)x\(cg.height)")
            }
        }
    }

    /// Runs every scanner on this Mac (`--storage` picks the folder to map, ~/Developer by default).
    private static func scan(_ model: AppModel) {
        for _ in 0..<12 {
            usleep(150_000)
            model.monitor.sample()
        }
        let running = RunningApps.snapshot()
        model.cleanup.apply(CleanupScanner.scan(running: running))
        model.cleanup.claude = CleanupScanner.claudeFootprint()
        model.cleanup.lastScan = Date()
        model.protection.checks = SecurityAudit.run()
        model.protection.grants = TCCReader.read()
        model.protection.traces = PrivacyScanner.scan(running: running)
        model.protection.lastAudit = Date()
        model.startup.items = LaunchItemScanner.scan()
        model.startup.lastScan = Date()
        model.apps.apps = AppInventory.scan(running: running)
        model.apps.lastScan = Date()
        model.performance.processes = ProcessList.sample()
        model.smartScanDate = Date()
        let storagePath = FS.expand(Entry.value(after: "--storage") ?? "~/Developer")
        let r = StorageScanner.scan(storagePath, isCancelled: { false }) { _, _ in }
        model.storage.root = r.root
        model.storage.current = r.root
        model.storage.bigFiles = r.bigFiles
        model.storage.rootPath = storagePath
    }
}

/// `CleanMyClaude --selftest` checks the deletion guard rails without touching any file.
/// With `--demo`, it also checks that the demo mode deletes and runs nothing, on a throwaway file of its own.
enum SelfTest {
    static func run() -> Bool {
        let h = FS.home
        let refused = [
            "/", "/System", "/Library/Caches/x", "/usr/bin/zsh", "/Applications", "/Applications/Utilities",
            h, h + "/Documents", h + "/Desktop", h + "/Library", h + "/Library/Caches", h + "/Library/Application Support",
            h + "/Library/Keychains/login.keychain-db", h + "/Library/Mail/V10", h + "/Library/Mobile Documents/x",
            h + "/Library/Messages/chat.db", h + "/.ssh", h + "/.zshrc", h + "/Library/Caches/../Keychains/x",
            h + "/Library/Logs/CleanMyClaude/actions.log", "/Users/someoneelse/Library/Caches/x"
        ]
        let allowed = [
            h + "/Library/Caches/com.spotify.client", h + "/Library/Logs/DiagnosticReports",
            h + "/Library/Developer/Xcode/DerivedData/App-abc", h + "/.npm/_cacache", h + "/.Trash/old.zip",
            h + "/Downloads/setup.dmg", h + "/.zsh_history", "/Applications/Install macOS Tahoe.app",
            h + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/x", h + "/Developer/app/node_modules"
        ]
        var ok = true
        for p in refused where Remover.isSafe(p) {
            print("✗ accepté à tort : \(p)")
            ok = false
        }
        for p in allowed where !Remover.isSafe(p) {
            print("✗ refusé à tort : \(p)")
            ok = false
        }
        // The scan must never offer anything outside the safe zone.
        for t in CleanupScanner.scan(running: RunningApps()) {
            for i in t.items where !Remover.isSafe(i.path) {
                print("✗ proposé mais protégé : \(i.path)")
                ok = false
            }
        }
        // Module checks (calculator, conversions, command ids…).
        let moduleFailures = MainActor.assumeIsolated { ModuleRegistry.selfTest(AppModel(liveMonitor: false)) }
        for f in moduleFailures + ThemeChecks.run() {
            print("✗ \(f)")
            ok = false
        }
        if !DemoData.isEnabled {
            // A silent tool must stop soon after a cancel (networkQuality, a brew download).
            let flag = CancelFlag()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { flag.cancel() }
            let start = Date()
            _ = Shell.stream("/bin/sleep", ["20"], isCancelled: { flag.isCancelled }) { _ in }
            if Date().timeIntervalSince(start) > 3 {
                print("✗ l'annulation d'un outil silencieux n'a pas abouti")
                ok = false
            }
        }
        if DemoData.isEnabled {
            let probe = NSTemporaryDirectory() + "cleanmyclaude-demo-probe-\(getpid())"
            FileManager.default.createFile(atPath: probe, contents: Data("démo".utf8))
            let report = Remover.remove([RemovalEntry(path: probe, size: 5)], mode: .delete)
            if report.removed > 0 || !FS.exists(probe) {
                print("✗ le mode démo a supprimé un fichier")
                ok = false
            }
            if Shell.run("/usr/bin/true").ok {
                print("✗ le mode démo a lancé une commande")
                ok = false
            }
            try? FileManager.default.removeItem(atPath: probe)
        }
        print(ok ? "✓ garde-fous OK (\(refused.count) refus, \(allowed.count) autorisations, catalogue vérifié\(DemoData.isEnabled ? ", mode démo inerte" : ""))" : "✗ échec")
        return ok
    }
}
