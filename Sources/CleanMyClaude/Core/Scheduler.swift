import Foundation

/// Periodic background jobs while the app runs (it stays in the menu bar).
/// The last run of each job is saved, so a job missed while the Mac slept catches up at the next check.
/// Nothing runs in demo or snapshot mode.
@MainActor
final class Scheduler {
    static let shared = Scheduler()

    private struct Job {
        let interval: TimeInterval
        let run: @MainActor () async -> Void
    }

    private var jobs: [String: Job] = [:]
    private var running: Set<String> = []
    private var timer: Timer?
    private let lastRuns = JSONStore<[String: Date]>("scheduler", default: [:])

    private init() {}

    /// Registers (or replaces) a job. `interval` is the minimum time between two runs.
    func register(_ id: String, every interval: TimeInterval, run: @escaping @MainActor () async -> Void) {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        jobs[id] = Job(interval: interval, run: run)
        startTimer()
    }

    func unregister(_ id: String) {
        jobs[id] = nil
    }

    func lastRun(_ id: String) -> Date? { lastRuns.value[id] }

    /// Runs a job now, whatever its schedule.
    func runNow(_ id: String) async {
        guard let job = jobs[id], !running.contains(id) else { return }
        running.insert(id)
        await job.run()
        lastRuns.value[id] = Date()
        running.remove(id)
    }

    private func startTimer() {
        guard timer == nil else { return }
        // One check a minute is plenty for jobs counted in hours or days.
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 20
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        for (id, job) in jobs where !running.contains(id) {
            let last = lastRuns.value[id] ?? .distantPast
            if now.timeIntervalSince(last) >= job.interval {
                Task { await runNow(id) }
            }
        }
    }
}
