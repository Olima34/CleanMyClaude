import Foundation
import AppKit

enum RemovalMode: String {
    /// Deleted for good: only for files apps rebuild by themselves (caches, logs…).
    case delete
    /// Moved to the Trash: anything that might matter to the user.
    case trash
}

struct RemovalEntry {
    var path: String
    var size: Int64
}

struct RemovalReport {
    var removed = 0
    var freed: Int64 = 0
    var failures: [(path: String, reason: String)] = []

    mutating func merge(_ o: RemovalReport) {
        removed += o.removed
        freed += o.freed
        failures += o.failures
    }

    var summary: String {
        if DemoData.isEnabled { return "Mode démo : rien n'a été supprimé, ces fichiers sont fictifs." }
        var s = "\(Fmt.plural(removed, "élément traité", "éléments traités")), \(Fmt.bytes(freed)) libérés."
        if !failures.isEmpty {
            s += " \(Fmt.plural(failures.count, "élément n'a", "éléments n'ont")) pas pu être supprimé\(failures.count > 1 ? "s" : "") (fichiers en cours d'utilisation ou protégés)."
        }
        return s
    }
}

/// The only place where the app deletes anything. Every path goes through `isSafe` and is written to a log.
enum Remover {
    /// Files at the root of the home folder that may be cleared (shell histories).
    static let homeRootFiles: Set<String> = [
        ".zsh_history", ".bash_history", ".python_history", ".node_repl_history", ".lesshst",
        ".viminfo", ".sqlite_history", ".psql_history", ".mysql_history", ".wget-hsts"
    ]

    /// ~/Library folders that are never touched, whatever happens.
    static let protectedLibrary: Set<String> = [
        "Keychains", "Mail", "Messages", "Mobile Documents", "CloudStorage", "Photos", "Accounts",
        "Calendars", "Reminders", "Safari", "Sharing", "Biome", "IdentityServices", "Passes", "PersonalizationPortrait"
    ]

    static func isSafe(_ raw: String) -> Bool {
        let path = (raw as NSString).standardizingPath
        guard path.hasPrefix("/"), !path.contains("/../") else { return false }
        if Preferences.exclusions.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
        if path.hasPrefix(ActionLog.folder) { return false }

        let home = FS.home
        if path.hasPrefix(home + "/") {
            let rel = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
            if rel.count == 1 { return homeRootFiles.contains(rel[0]) }
            if rel[0] == "Library" {
                if rel.count < 3 { return false }
                if protectedLibrary.contains(rel[1]) { return false }
            }
            return true
        }
        // Whole app bundles only (uninstaller, old macOS installers).
        if path.hasPrefix("/Applications/") { return path.hasSuffix(".app") }
        if let tmp = FS.userTempDir.map({ ($0 as NSString).standardizingPath }), path.hasPrefix(tmp + "/") { return true }
        return false
    }

    static func remove(_ entries: [RemovalEntry], mode: RemovalMode) -> RemovalReport {
        // The demo shows fictional paths: nothing may ever be deleted, whatever they point to.
        if DemoData.isEnabled { return RemovalReport(failures: entries.map { ($0.path, DemoData.refusal) }) }
        let effective: RemovalMode = Preferences.alwaysTrash ? .trash : mode
        var report = RemovalReport()
        for e in entries {
            guard isSafe(e.path) else {
                report.failures.append((e.path, "Emplacement protégé"))
                ActionLog.write("REFUSÉ \(e.path)")
                continue
            }
            guard FS.exists(e.path) || FS.isSymlink(e.path) else { continue }
            do {
                switch effective {
                case .delete:
                    try FS.fm.removeItem(atPath: e.path)
                case .trash:
                    try FS.fm.trashItem(at: URL(fileURLWithPath: e.path), resultingItemURL: nil)
                }
                report.removed += 1
                report.freed += e.size
                ActionLog.write("\(effective == .delete ? "SUPPRIMÉ" : "CORBEILLE") \(Fmt.bytes(e.size)) \(e.path)")
            } catch {
                if effective == .trash, recycle(e.path) {
                    report.removed += 1
                    report.freed += e.size
                    ActionLog.write("CORBEILLE \(Fmt.bytes(e.size)) \(e.path)")
                    continue
                }
                // A folder may be partly deleted: count what really went away.
                let left = FS.exists(e.path) ? FileSizer.size(of: e.path) : 0
                report.freed += max(0, e.size - left)
                report.failures.append((e.path, error.localizedDescription))
                ActionLog.write("ÉCHEC \(e.path) : \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Asks Finder to move an item to the Trash (handles files owned by root with an admin prompt).
    /// Must not be called from the main thread.
    static func recycle(_ path: String) -> Bool {
        final class Flag: @unchecked Sendable { var ok = false }
        let flag = Flag()
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            NSWorkspace.shared.recycle([URL(fileURLWithPath: path)]) { _, error in
                flag.ok = error == nil
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + 120)
        return flag.ok
    }
}

/// A plain text journal of everything the app removed: ~/Library/Logs/CleanMyClaude/actions.log
enum ActionLog {
    static let folder = FS.home + "/Library/Logs/CleanMyClaude"
    static var file: String { folder + "/actions.log" }
    private static let queue = DispatchQueue(label: "cleanmyclaude.log")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        queue.async {
            try? FS.fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
            if let h = FileHandle(forWritingAtPath: file) {
                h.seekToEndOfFile()
                h.write(Data(text.utf8))
                try? h.close()
            } else {
                try? Data(text.utf8).write(to: URL(fileURLWithPath: file))
            }
        }
    }
}

/// User settings shared by the UI (@AppStorage) and the background code.
enum Preferences {
    static let alwaysTrashKey = "cleanup.alwaysTrash"
    static let exclusionsKey = "cleanup.exclusions"
    static let menuMetricKey = "menubar.metric"
    static let refreshKey = "monitor.refresh"
    static let onboardedKey = "app.onboarded"
    static let alertsKey = "monitor.alerts"

    static var alwaysTrash: Bool { UserDefaults.standard.bool(forKey: alwaysTrashKey) }

    static var exclusions: [String] {
        get { UserDefaults.standard.stringArray(forKey: exclusionsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: exclusionsKey) }
    }
}
