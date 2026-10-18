import SwiftUI

/// The translator inside the launcher panel (⌥Espace › Traducteur, "trad …", or its own shortcut):
/// type, the translation follows; ↩ copies it, ⇥ changes the language, ⌘↩ asks Claude.
struct TranslatorPanelView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = app.translator
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "character.bubble").font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.palette[1]).frame(width: 24).padding(.top, 2)
                if Snapshot.isActive {
                    Text(model.sourceText.isEmpty ? "Texte à traduire…" : model.sourceText)
                        .font(.system(size: 19)).foregroundStyle(model.sourceText.isEmpty ? Theme.text3 : Theme.text)
                        .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Texte à traduire…", text: $model.sourceText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1...4)
                        .focused($focused)
                }
                Button { app.launcher.backToSearch() } label: {
                    Image(systemName: "chevron.backward.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
                .help("Revenir à la recherche (⎋)")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Rectangle().fill(Theme.border).frame(height: 1)

            HStack(spacing: 8) {
                Text(sourceLabel).font(.ui(12, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
                Image(systemName: "arrow.right").font(.ui(10, .semibold)).foregroundStyle(Theme.text3)
                ForEach(model.panelTargets.filter { $0 != model.effectiveSource }, id: \.self) { code in
                    chip(code)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            result
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            status
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 14) {
                LauncherKeyHint(key: "↩", label: "Copier")
                LauncherKeyHint(key: "⌘↩", label: "Claude")
                LauncherKeyHint(key: "⇥", label: "Langue")
                LauncherKeyHint(key: "⎋", label: "Retour")
                Spacer()
                Button("Ouvrir le Traducteur") {
                    app.page = .translator
                    NotificationCenter.default.post(name: .openMainWindow, object: nil)
                }
                .buttonStyle(.plain)
                .font(.ui(11.5, .medium))
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Theme.sidebar.opacity(0.6))
        }
        .background(TranslatorHost(channel: .panel))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var sourceLabel: String {
        let m = app.translator
        if let code = m.sourceCode { return TranslatorLanguage.named(code) }
        if let d = m.detectedCode { return TranslatorLanguage.named(d) }
        return "Langue détectée"
    }

    private func chip(_ code: String) -> some View {
        let m = app.translator
        let selected = m.effectiveTarget == code
        let installed = m.languageStatus[code] == .installed || code == "fr"
        return Button { m.targetCode = code } label: {
            HStack(spacing: 4) {
                Text(TranslatorLanguage.named(code)).font(.ui(11.5, selected ? .semibold : .regular))
                if !installed, m.engine == .apple { Image(systemName: "arrow.down.circle").font(.ui(9)) }
            }
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(selected ? Theme.accent.opacity(0.22) : Theme.track.opacity(0.6)))
            .overlay(Capsule().strokeBorder(selected ? Theme.accent.opacity(0.7) : .clear))
        }
        .buttonStyle(.plain)
        .help(installed ? "Sur ton Mac" : "À télécharger dans le Traducteur (ou ⌘↩ pour Claude)")
    }

    @ViewBuilder
    private var result: some View {
        let m = app.translator
        let text = Text(m.resultText.isEmpty ? placeholder : m.resultText)
            .font(.system(size: 21))
            .foregroundStyle(m.resultText.isEmpty ? Theme.text3 : Theme.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        if Snapshot.isActive {
            ScrollArea { text }
        } else {
            ScrollView { text }
        }
    }

    private var placeholder: String {
        let m = app.translator
        if m.isTranslating { return "Traduction…" }
        if m.sourceText.isEmpty { return "Tape ou colle un texte : la traduction s'affiche ici." }
        if m.engine == .claude { return "↩ pour traduire avec Claude." }
        return ""
    }

    @ViewBuilder
    private var status: some View {
        let m = app.translator
        HStack(spacing: 8) {
            if m.isTranslating {
                ProgressView().controlSize(.small)
            }
            if let error = m.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.ui(11.5)).foregroundStyle(Theme.warn).lineLimit(2)
            } else if m.engine == .apple, m.pairStatus == .downloadable, m.resultText.isEmpty, !m.sourceText.isEmpty {
                Label("Le \(TranslatorLanguage.named(m.effectiveTarget).lowercased()) n'est pas encore sur ton Mac : ⌘↩ pour Claude, ou télécharge-le dans le Traducteur.",
                      systemImage: "arrow.down.circle")
                    .font(.ui(11.5)).foregroundStyle(Theme.text2).lineLimit(2)
            } else if let by = m.resultEngine, !m.resultText.isEmpty {
                HStack(spacing: 5) {
                    if by == .claude { ClaudeSpark(size: 10) } else { Image(systemName: "lock.laptopcomputer").font(.ui(10)) }
                    Text(by == .claude ? "Claude · \(m.claudeModel.familyTitle)" : "Sur ton Mac, hors ligne").font(.ui(11))
                }
                .foregroundStyle(Theme.text3)
            }
            Spacer()
        }
        .frame(height: 22)
    }
}
