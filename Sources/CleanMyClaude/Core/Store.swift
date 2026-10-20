import Foundation

/// A thread-safe "stop" flag shared with background work.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

/// Where the app keeps its own data: ~/Library/Application Support/CleanMyClaude/ (CleanMyClaude Labo/ for the test copy).
/// `Remover` never deletes anything inside it. The folders are readable by this user alone (0700), and so are the files
/// written there (0600): the clipboard history, the settings and the journals are nobody else's business.
enum DataStore {
    static let folder = FS.home + "/Library/Application Support/" + (AppEdition.isLab ? "CleanMyClaude Labo" : "CleanMyClaude")

    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: folder).appendingPathComponent(name)
    }

    /// Creates the folder (and a sub-folder) on demand, private to this user. `excludeFromBackup`: Time Machine leaves
    /// the sub-folder out (copied images of the clipboard). Does nothing in demo mode.
    @discardableResult
    static func ensureFolder(_ sub: String? = nil, excludeFromBackup: Bool = false) -> URL? {
        guard !DemoData.isEnabled else { return nil }
        var url = sub.map { Self.url($0) } ?? URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Folders made by an earlier version kept the default rights (0755).
        chmod(folder, 0o700)
        if sub != nil { chmod(url.path, 0o700) }
        if excludeFromBackup { exclude(&url) }
        return url
    }

    /// Just written by the app: private to this user, and left out of backups when `excludeFromBackup`.
    static func protect(_ file: URL, excludeFromBackup: Bool = false) {
        guard !DemoData.isEnabled else { return }
        chmod(file.path, 0o600)
        var url = file
        if excludeFromBackup { exclude(&url) }
    }

    private static func exclude(_ url: inout URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

/// A value saved as JSON in the app's data folder, written atomically and at most twice a second, private to this user.
/// In demo mode it lives in memory only: nothing is read from or written to the disk.
@MainActor
final class JSONStore<T: Codable> {
    private let file: URL
    private let excludeFromBackup: Bool
    private var pendingSave: DispatchWorkItem?

    var value: T {
        didSet { scheduleSave() }
    }

    /// `excludeFromBackup`: Time Machine leaves the file out (the clipboard history).
    init(_ name: String, default fallback: T, excludeFromBackup: Bool = false) {
        file = DataStore.url(name.hasSuffix(".json") ? name : name + ".json")
        self.excludeFromBackup = excludeFromBackup
        if !DemoData.isEnabled, let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder.store.decode(T.self, from: data) {
            value = decoded
        } else {
            value = fallback
        }
    }

    /// Writes now (call before quitting if the last change matters).
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard !DemoData.isEnabled, DataStore.ensureFolder() != nil,
              let data = try? JSONEncoder.store.encode(value) else { return }
        // An atomic write is a new file each time: its rights and backup exclusion are set again.
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        DataStore.protect(file, excludeFromBackup: excludeFromBackup)
    }

    private func scheduleSave() {
        guard !DemoData.isEnabled else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

extension JSONEncoder {
    static let store: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let store: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
