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
                                          isCurrent: center.current == kind, center: center) {
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
    var center: PermissionCenter
    var ask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol).frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(kind.purpose).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                trailing
            }
            if isCurrent, center.waitingForSettings {
                // The switch may already be on for an older build of the app: macOS then ignores it.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let since = center.waitingSince, context.date.timeIntervalSince(since) > 5 {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Déjà activé dans Réglages Système ? macOS se souvient d'une ancienne version de l'app : réinitialise, puis réactive l'interrupteur.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Réinitialiser") { Task { await center.reset(kind) } }.controlSize(.small)
                            Button("Passer") { center.skip() }.controlSize(.small)
                        }
                        .padding(.leading, 30)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isCurrent {
            ProgressView().controlSize(.small)
        } else if state == .granted {
            Label("Accordée", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(Theme.good)
        } else if state == .denied {
            HStack(spacing: 6) {
                if kind.needsSettings || kind == .finder || kind == .systemEvents {
                    Button("Réinitialiser") { Task { await center.reset(kind) } }.controlSize(.small)
                        .help("macOS ne redemande plus : efface sa réponse pour cette app, puis redemande.")
                }
                Button("Réglages…") { Finder.open(kind.settingsURL) }.controlSize(.small)
                    .help("Refusée : à activer dans Réglages Système.")
            }
        } else if state == .asked {
            HStack(spacing: 6) {
                Text("Demandée").font(.caption).foregroundStyle(.secondary)
                Button("Réglages…") { Finder.open(kind.settingsURL) }.controlSize(.small)
            }
        } else if kind.needsSettings {
            HStack(spacing: 6) {
                Button("Réinitialiser") { Task { await center.reset(kind) } }.controlSize(.small)
                    .help("Interrupteur déjà activé mais sans effet ? macOS se souvient d'une ancienne version de l'app.")
                Button("Ouvrir…", action: ask).controlSize(.small)
            }
        } else {
            Button("Autoriser", action: ask).controlSize(.small)
        }
    }
}
