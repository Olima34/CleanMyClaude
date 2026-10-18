import Foundation

/// A thread-safe "stop" flag shared with background work.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

/// Where the app keeps its own data: ~/Library/Application Support/CleanMyClaude/
/// `Remover` never deletes anything inside it.
enum DataStore {
    static let folder = FS.home + "/Library/Application Support/CleanMyClaude"

    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: folder).appendingPathComponent(name)
    }

    /// Creates the folder (and a sub-folder) on demand. Does nothing in demo mode.
    @discardableResult
    static func ensureFolder(_ sub: String? = nil) -> URL? {
        guard !DemoData.isEnabled else { return nil }
        let url = sub.map { Self.url($0) } ?? URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A value saved as JSON in the app's data folder, written atomically and at most twice a second.
/// In demo mode it lives in memory only: nothing is read from or written to the disk.
@MainActor
final class JSONStore<T: Codable> {
    private let file: URL
    private var pendingSave: DispatchWorkItem?

    var value: T {
        didSet { scheduleSave() }
    }

    init(_ name: String, default fallback: T) {
        file = DataStore.url(name.hasSuffix(".json") ? name : name + ".json")
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
        try? data.write(to: file, options: .atomic)
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
