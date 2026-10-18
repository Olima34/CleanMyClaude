import SwiftUI
import Translation

/// What Apple's on-device translation is asked to do.
struct TranslatorRequest: Equatable {
    var text: String
    var source: String?
    var target: String
    /// Ask macOS to download the languages first (it shows its own confirmation).
    var download = false
}

/// The two places that translate on the device: the page and the launcher panel.
enum TranslatorChannel {
    case page, launcher
}

/// Apple's translation only runs inside a view (`translationTask`): this invisible view does it for a channel.
/// Nothing before macOS 15.
struct TranslatorHost: View {
    var channel: TranslatorChannel

    var body: some View {
        if #available(macOS 15.0, *), !Snapshot.isActive, !DemoData.isEnabled {
            TranslatorAppleHost(channel: channel)
        }
    }
}

@available(macOS 15.0, *)
private struct TranslatorAppleHost: View {
    @Environment(AppModel.self) private var app
    var channel: TranslatorChannel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        let ticket = channel == .page ? app.translator.pageTicket : app.translator.launcherTicket
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                let request = await MainActor.run { app.translator.request(for: channel) }
                guard let request else { return }
                do {
                    if request.download { try await session.prepareTranslation() }
                    let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let result = text.isEmpty ? nil : try await session.translate(request.text).targetText
                    await MainActor.run { app.translator.appleFinished(request, result: result, channel: channel) }
                } catch {
                    await MainActor.run { app.translator.appleFailed(request, error: error, channel: channel) }
                }
            }
            .onChange(of: ticket) { _, _ in
                guard let request = app.translator.request(for: channel) else { return }
                let fresh = TranslationSession.Configuration(source: request.source.map { Locale.Language(identifier: $0) },
                                                             target: Locale.Language(identifier: request.target))
                if configuration?.source == fresh.source, configuration?.target == fresh.target {
                    configuration?.invalidate()
                } else {
                    configuration = fresh
                }
            }
    }
}

/// Which languages macOS has, can download, or does not offer (asked without downloading anything).
enum TranslatorAvailability {
    static func status(from source: String, to target: String) async -> TranslatorPairStatus {
        guard #available(macOS 15.0, *), !DemoData.isEnabled else { return .unsupported }
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
        switch status {
        case .installed: return .installed
        case .supported: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    static var isAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    static func message(_ error: Error) -> String {
        if #available(macOS 15.0, *) {
            if TranslationError.unsupportedLanguagePairing ~= error { return "Apple ne traduit pas cette paire de langues : essaie avec Claude." }
            if TranslationError.unableToIdentifyLanguage ~= error { return "Je n'arrive pas à reconnaître la langue : choisis-la à gauche." }
            if TranslationError.nothingToTranslate ~= error { return "Rien à traduire." }
        }
        if (error as? CancellationError) != nil { return "Téléchargement annulé." }
        return error.localizedDescription
    }
}
