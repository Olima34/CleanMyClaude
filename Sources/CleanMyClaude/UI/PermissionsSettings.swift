import SwiftUI
import AppKit
import Combine

/// Réglages › Autorisations: every permission at a glance, and one button to ask for all of them.
struct PermissionsSettings: View {
    @Environment(AppModel.self) private var app
    @State private var center = PermissionCenter.shared
    private let stable = PermissionCenter.hasStableSignature
    private let tick = Timer.publish(every: 1.5, tolerance: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(center.grantedCount) sur \(PermissionKind.allCases.count) accordées").font(.headline)
                        Text(statusLine).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if center.isRunning {
                        if center.waitingForSettings {
                            Button("Passer") { center.skip() }
                        }
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Tout autoriser") {
                            Task {
                                await center.requestAll()
                                // The folders are readable now: the launcher can index them.
                                if center.states[.folders] == .granted { app.launcher.enableIndex() }
                                app.fullDiskAccess = Permissions.hasFullDiskAccess
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(center.grantedCount == PermissionKind.allCases.count)
                    }
                }
                if !stable {
                    Label("Cette copie de l'app est signée « ad hoc » : macOS oubliera ces autorisations à la prochaine compilation. Lance une fois ./scripts/setup_signing.sh, puis recompile.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionSettingsRow(kind: kind, state: center.states[kind] ?? .notAsked,
                                          isCurrent: center.current == kind) {
                        Task { await center.request(kind); await center.refresh() }
                    }
                }
            } footer: {
                Text("Chaque autorisation ne sert qu'à ce qui est indiqué. L'accès complet au disque et l'accessibilité se donnent dans Réglages Système : la fenêtre s'ouvre au bon endroit, active Clean My Claude puis reviens ici.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await center.refresh() }
        .onReceive(tick) { _ in
            guard !center.isRunning || center.waitingForSettings else { return }
            Task { await center.refresh() }
        }
    }

    private var statusLine: String {
        if center.isRunning, let k = center.current {
            return center.waitingForSettings
                ? "Active Clean My Claude dans la fenêtre Réglages Système qui vient de s'ouvrir (\(k.title))."
                : "Je demande : \(k.title)…"
        }
        return stable
            ? "Signature stable : une fois accordées, elles restent acquises après chaque mise à jour de l'app."
            : "Un clic, et macOS pose ses questions l'une après l'autre."
    }
}

private struct PermissionSettingsRow: View {
    var kind: PermissionKind
    var state: PermissionState
    var isCurrent: Bool
    var ask: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.purpose).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if isCurrent {
                ProgressView().controlSize(.small)
            } else if state == .granted {
                Label("Accordée", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(Theme.good)
            } else if state == .denied {
                Button("Réglages…") { Finder.open(kind.settingsURL) }.controlSize(.small)
                    .help("Refusée : macOS ne redemande pas, il faut l'activer dans Réglages Système.")
            } else {
                Button(kind.needsSettings ? "Ouvrir…" : "Autoriser", action: ask).controlSize(.small)
            }
        }
    }
}
