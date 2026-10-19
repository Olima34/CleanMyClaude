import SwiftUI
import AppKit

struct TranslatorPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.translator
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "character.bubble", title: "Traducteur",
                     subtitle: "Sur ton Mac, hors ligne et instantané, avec les langues que tu télécharges. Ou avec Claude, pour les nuances et le ton. Aussi depuis le lanceur : « trad bonjour en espagnol ».",
                     tint: Theme.palette[1], seed: 71) {
                PillPicker(options: TranslatorEngine.allCases, selection: $model.engine, label: \.title)
            }
            Text(model.engine.detail).font(.ui(12)).foregroundStyle(Theme.text3)
                .padding(.top, -8)

            HStack(alignment: .top, spacing: 12) {
                TranslatorPane(title: sourceTitle, symbol: "text.alignleft") {
                    languageMenu(selection: model.sourceCode, includeAuto: true) { model.sourceCode = $0 }
                } content: {
                    TranslatorEditor(text: $model.sourceText, placeholder: "Tape ou colle ton texte…", editable: true)
                } footer: {
                    Text(Fmt.plural(model.sourceText.count, "caractère", "caractères")).font(.ui(11)).foregroundStyle(Theme.text3)
                    Spacer()
                    if !model.sourceText.isEmpty {
                        Button("Effacer") { model.sourceText = ""; model.resultText = "" }.buttonStyle(SoftButtonStyle(small: true))
                    }
                }
                Button { model.swapLanguages() } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.ui(13, .semibold)).foregroundStyle(Theme.text2)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().strokeBorder(Theme.border, lineWidth: Theme.line))
                }
                .buttonStyle(.plain)
                .help("Inverser les langues")
                .padding(.top, 70)
                TranslatorPane(title: TranslatorLanguage.named(model.effectiveTarget), symbol: "text.bubble") {
                    languageMenu(selection: model.targetCode, includeAuto: false) { model.targetCode = $0 ?? "en" }
                } content: {
                    ZStack {
                        TranslatorEditor(text: .constant(model.resultText), placeholder: placeholder, editable: false, tint: Theme.text)
                        if model.isTranslating {
                            BusyMascot(.reading, pixel: 4)
                        }
                    }
                } footer: {
                    statusLine
                    Spacer()
                    if model.engine == .claude {
                        Button("Traduire avec Claude") { model.translate() }
                            .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(model.sourceText.isEmpty || model.isTranslating)
                    }
                    if !model.resultText.isEmpty {
                        Button("Copier") { _ = CommandRunner.copy(model.resultText); HUD.show("Traduction copiée", symbol: "doc.on.clipboard.fill") }
                            .buttonStyle(SoftButtonStyle(small: true))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.ui(12)).foregroundStyle(Theme.warn)
            }
            if model.engine == .apple, model.pairStatus == .downloadable {
                downloadCard
            }
            if model.engine == .claude {
                claudeOptions
            }
            HStack(alignment: .top, spacing: 14) {
                if model.engine == .apple { languages } else { claudeNote }
                historyPanel.frame(width: 470)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(TranslatorHost(channel: .page))
        .task { await model.refreshLanguageStatuses(); model.refreshPairStatus() }
    }

    private var sourceTitle: String {
        if let code = app.translator.sourceCode { return TranslatorLanguage.named(code) }
        if let d = app.translator.detectedCode { return "\(TranslatorLanguage.named(d)) (détecté)" }
        return "Texte"
    }

    private var placeholder: String {
        switch app.translator.engine {
        case .apple: return "La traduction apparaît ici pendant que tu tapes."
        case .claude: return "Clique sur « Traduire avec Claude » (⌘↩)."
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let m = app.translator
        if m.engine == .apple {
            HStack(spacing: 5) {
                Circle().fill(m.pairStatus == .installed ? Theme.good : (m.pairStatus == .unsupported ? Theme.bad : Theme.text3)).frame(width: 6, height: 6)
                Text(m.effectiveSource == nil ? "Langue détectée en tapant" : m.pairStatus.label).font(.ui(11)).foregroundStyle(Theme.text3)
            }
        } else {
            Text("\(m.claudeModel.familyTitle) · \(m.tone.title)").font(.ui(11)).foregroundStyle(Theme.text3)
        }
    }

    private func languageMenu(selection: String?, includeAuto: Bool, set: @escaping (String?) -> Void) -> some View {
        BorderlessMenu {
            if includeAuto { Button("Détection automatique") { set(nil) } ; Divider() }
            ForEach(TranslatorLanguage.all) { l in
                Button(l.name + (app.translator.languageStatus[l.code] == .installed ? "  ✓" : "")) { set(l.code) }
            }
        } label: {
            Text(selection.map { TranslatorLanguage.named($0) } ?? "Détection automatique").font(.ui(12, .medium)).foregroundStyle(Theme.accent)
        }
    }

    private var downloadCard: some View {
        let m = app.translator
        return Card(padding: 16) {
            HStack(spacing: 12) {
                IconBadge(symbol: "arrow.down.circle", tint: Theme.accent, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Télécharger \(TranslatorLanguage.named(m.effectiveSource).lowercased()) ↔ \(TranslatorLanguage.named(m.effectiveTarget).lowercased())")
                        .font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                    Text("macOS télécharge le dictionnaire de cette paire une fois (quelques dizaines de Mo), puis traduit sans connexion, sans que rien ne quitte ton Mac.")
                        .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Télécharger") { m.downloadCurrentPair() }.buttonStyle(SoftButtonStyle(prominent: true, small: true))
                Button("Avec Claude") { m.engine = .claude; m.translate() }.buttonStyle(SoftButtonStyle(small: true))
            }
        }
    }

    private var claudeOptions: some View {
        @Bindable var model = app.translator
        return Card(padding: 14) {
            HStack(spacing: 18) {
                HStack(spacing: 8) {
                    Text("Ton").font(.ui(12)).foregroundStyle(Theme.text2)
                    PillPicker(options: TranslatorTone.allCases, selection: $model.tone, label: \.title)
                }
                HStack(spacing: 8) {
                    Text("Modèle").font(.ui(12)).foregroundStyle(Theme.text2)
                    PillPicker(options: [AssistantModelChoice.haiku, .sonnet, .opus], selection: $model.claudeModel, label: \.familyTitle)
                }
                Spacer()
                if !app.assistant.isReady {
                    Button("Connecter Claude") { app.page = .assistant }.buttonStyle(SoftButtonStyle(prominent: true, small: true))
                }
            }
        }
    }

    private var languages: some View {
        let m = app.translator
        let list = TranslatorLanguage.all.filter { $0.code != "fr" && (m.languageStatus[$0.code] ?? .unknown) != .unsupported }
        return Panel(title: "Langues sur ton Mac", subtitle: "Avec le français. Téléchargées une fois, elles traduisent hors ligne", symbol: "arrow.down.to.line.compact", tint: Theme.palette[1]) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 8) {
                    ForEach(list) { l in
                        HStack(spacing: 8) {
                            Text(l.name).font(.ui(12.5)).foregroundStyle(Theme.text)
                            Spacer()
                            switch m.languageStatus[l.code] ?? .unknown {
                            case .installed: StatusBadge(status: .ok, text: "Installée")
                            case .downloadable:
                                Button("Télécharger") { m.download(l.code) }.buttonStyle(SoftButtonStyle(small: true))
                            default: Text("…").font(.ui(11)).foregroundStyle(Theme.text3)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                Button("Gérer les langues dans Réglages Système") { Finder.open("x-apple.systempreferences:com.apple.Localization-Settings.extension") }
                    .buttonStyle(SoftButtonStyle(small: true))
            }
        }
    }

    private var claudeNote: some View {
        Panel(title: "Pourquoi Claude ?", symbol: "sparkle", tint: Theme.brand) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude traduit toutes les langues, garde le ton (formel ou familier), les expressions et la mise en forme. Ton texte part chez Anthropic avec ton abonnement Claude ou ta clé API, seulement quand tu cliques.")
                    .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                Text("Haiku répond le plus vite ; Sonnet et Opus soignent davantage les textes longs ou délicats.")
                    .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var historyPanel: some View {
        @Bindable var model = app.translator
        return Panel(title: "Historique", subtitle: "Gardé sur ton Mac", symbol: "clock.arrow.circlepath", tint: Theme.text2) {
            VStack(alignment: .leading, spacing: 8) {
                if model.history.isEmpty {
                    Text(model.keepHistory ? "Tes traductions apparaîtront ici." : "L'historique est désactivé.")
                        .font(.ui(12)).foregroundStyle(Theme.text3)
                }
                ForEach(model.history.prefix(6)) { e in
                    Button { model.restore(e) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("\(TranslatorLanguage.named(e.from)) → \(TranslatorLanguage.named(e.to))").font(.ui(10.5, .semibold)).foregroundStyle(Theme.text3)
                                if e.engine == .claude { ClaudeSpark(size: 9) }
                                Spacer()
                                Text(Fmt.relative(e.date)).font(.ui(10.5)).foregroundStyle(Theme.text3)
                            }
                            Text(e.source).font(.ui(12)).foregroundStyle(Theme.text2).lineLimit(1)
                            Text(e.result).font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Theme.cardRaised.opacity(0.5)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Toggle("Garder l'historique", isOn: $model.keepHistory).switchToggles().font(.ui(11.5))
                    Spacer()
                    if !model.history.isEmpty {
                        Button("Effacer") { model.clearHistory() }.buttonStyle(SoftButtonStyle(small: true))
                    }
                }
            }
        }
    }
}

/// One side of the translator: a header with the language, the text, a footer.
private struct TranslatorPane<Menu: View, Content: View, Footer: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var menu: Menu
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.ui(12)).foregroundStyle(Theme.text3)
                    Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    menu
                }
                content.frame(height: 210)
                HStack(spacing: 8) { footer }
            }
        }
    }
}

/// A text area that snapshots can draw.
struct TranslatorEditor: View {
    @Binding var text: String
    var placeholder: String
    var editable: Bool
    var tint: Color = Theme.text

    var body: some View {
        ZStack(alignment: .topLeading) {
            if editable && !Snapshot.isActive {
                TextEditor(text: $text)
                    .font(.ui(14))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 7)
                if text.isEmpty {
                    Text(placeholder).font(.ui(14)).foregroundStyle(Theme.text3)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
            } else {
                ScrollArea {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.ui(14))
                        .foregroundStyle(text.isEmpty ? Theme.text3 : tint)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.bg.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

struct TranslatorBottomBar: View {
    var body: some View { EmptyView() }
}
