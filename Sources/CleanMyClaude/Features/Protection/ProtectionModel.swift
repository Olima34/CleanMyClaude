import Foundation
import Observation

enum ProtectionTab: String, CaseIterable, Identifiable {
    case security, persistence, permissions, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .security: return "Bilan de sécurité"
        case .persistence: return "Éléments persistants"
        case .permissions: return "Autorisations"
        case .privacy: return "Traces"
        }
    }
}

@Observable
@MainActor
final class ProtectionModel {
    var tab: ProtectionTab = .security
    var checks: [SecurityCheck] = []
    var pending: SecurityCheck?
    @ObservationIgnored private var pendingChecked = Date.distantPast
    var isCheckingUpdates = false
    var isAuditing = false
    var lastAudit: Date?
    /// nil when macOS refuses to show the privacy databases (no Full Disk Access).
    var grants: [PermissionGrant]?
    var traces: [PrivacyTrace] = []
    var traceSelection: Set<String> = []
    var isCleaningTraces = false
    var traceReport: RemovalReport?

    @ObservationIgnored var onFreed: (Int64) -> Void = { _ in }

    var hasAudit: Bool { !checks.isEmpty }

    var allChecks: [SecurityCheck] { checks + [pending].compactMap { $0 } }

    private var scored: [SecurityCheck] { allChecks.filter { $0.scored && $0.status != .unknown } }

    var securityRatio: Double {
        let s = scored
        guard !s.isEmpty else { return 1 }
        return Double(s.filter { $0.status == .ok || $0.status == .info }.count) / Double(s.count)
    }

    var passedCount: Int { scored.filter { $0.status == .ok || $0.status == .info }.count }
    var scoredCount: Int { scored.count }
    var issues: [SecurityCheck] { allChecks.filter { $0.status == .warn || $0.status == .bad } }

    func audit() async {
        guard !isAuditing else { return }
        isAuditing = true
        let running = RunningApps.snapshot()
        let (c, g, t) = await Task.detached(priority: .userInitiated) {
            (SecurityAudit.run(), TCCReader.read(), PrivacyScanner.scan(running: running))
        }.value
        checks = c
        grants = g
        traces = t
        traceSelection = Set(t.filter { $0.defaultOn && $0.blockedReason == nil && !$0.needsFullDiskAccess }.map(\.id))
        lastAudit = Date()
        isAuditing = false
        // Asked again when it failed, when updates were waiting (maybe installed since) or after an hour.
        if pending?.status != .ok || Date().timeIntervalSince(pendingChecked) > 3600 { await checkUpdates() }
    }

    func checkUpdates() async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        pending = await Task.detached(priority: .utility) { SecurityAudit.pendingUpdates() }.value
        pendingChecked = Date()
        isCheckingUpdates = false
    }

    // MARK: Traces

    var selectedTraces: [PrivacyTrace] {
        traces.filter { traceSelection.contains($0.id) && $0.blockedReason == nil && !$0.needsFullDiskAccess }
    }

    func toggle(_ t: PrivacyTrace) {
        guard t.blockedReason == nil, !t.needsFullDiskAccess else { return }
        if traceSelection.contains(t.id) { traceSelection.remove(t.id) } else { traceSelection.insert(t.id) }
    }

    func cleanTraces() async {
        let chosen = selectedTraces
        guard !chosen.isEmpty, !isCleaningTraces else { return }
        isCleaningTraces = true
        let report = await Task.detached(priority: .userInitiated) { PrivacyScanner.clean(chosen) }.value
        traceReport = report
        isCleaningTraces = false
        onFreed(report.freed)
        let running = RunningApps.snapshot()
        traces = await Task.detached { PrivacyScanner.scan(running: running) }.value
        traceSelection = []
    }
}
