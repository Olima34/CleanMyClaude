import Foundation

/// Watches the main thread while something outside the app depends on it: the pointer hidden for the whole system
/// (Toolbox), apps moved to the efficiency cores (Boost). If the app stops answering for a couple of seconds, those are
/// put back from a background thread, so a hang of Chamois never looks like a hang of the whole Mac.
/// Runs only while a rescue is armed: with nothing hidden nor slowed, it costs nothing at all.
final class MainWatchdog: @unchecked Sendable {
    static let shared = MainWatchdog()

    /// How long the main thread may stay silent before the rescues run.
    static let patience: TimeInterval = 2.5

    private let queue = DispatchQueue(label: "cleanmyclaude.watchdog", qos: .userInteractive)
    private var rescues: [String: @Sendable () -> Void] = [:]
    private var timer: DispatchSourceTimer?
    /// When the ping still waiting for the main thread was sent.
    private var pingSent: DispatchTime?

    private init() {}

    /// `rescue` runs once, on a background thread, if the main thread hangs while it is armed. Arming again replaces it.
    func arm(_ id: String, rescue: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            rescues[id] = rescue
            startIfNeeded()
        }
    }

    func disarm(_ id: String) {
        queue.async { [self] in
            rescues[id] = nil
            if rescues.isEmpty { stop() }
        }
    }

    private func startIfNeeded() {
        guard timer == nil else { return }
        pingSent = nil
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func stop() {
        timer?.cancel()
        timer = nil
        pingSent = nil
    }

    private func tick() {
        guard let sent = pingSent else {
            pingSent = .now()
            DispatchQueue.main.async { [self] in
                queue.async { self.pingSent = nil }
            }
            return
        }
        guard DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds > UInt64(Self.patience * 1e9) else { return }
        // The main thread is stuck: everything armed is put back now, once, away from this queue.
        let pending = Array(rescues.values)
        rescues.removeAll()
        stop()
        for rescue in pending { DispatchQueue.global(qos: .userInteractive).async(execute: rescue) }
    }
}
