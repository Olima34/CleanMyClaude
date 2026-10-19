import SwiftUI
import AppKit

struct AssistantPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.assistant
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "sparkle", title: "Assistant Claude",
                     subtitle: "Pose tes questions sur ton Mac en langage naturel. Claude t'explique ce que tu vois et te propose les bonnes actions ; rien ne s'exécute sans ton clic.",
                     tint: Theme.brand, seed: 105)
            if model.isReady {
                AssistantSettingsStrip()
                AssistantConversation()
            } else {
                AssistantProviderPicker()
                if model.provider == .subscription {
                    AssistantConnectCard()
                } else {
                    AssistantKeySetup()
                }
            }
        }
        .task { if app.assistant.provider == .subscription { await app.assistant.refreshStatus() } }
        // Back on the subscription (picker or "…" menu): check the Claude Code login again.
        .onChange(of: model.provider) { _, provider in
            if provider == .subscription { Task { await app.assistant.refreshStatus() } }
        }
    }
}

struct AssistantProviderPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.assistant
        HStack(spacing: 12) {
            Text("Connexion à Claude").font(.ui(12.5, .semibold)).foregroundStyle(Theme.text2)
            PillPicker(options: AssistantProvider.allCases, selection: $model.provider, label: { $0.title })
        }
    }
}

// MARK: - Claude subscription

/// Connects through Claude Code with the Claude subscription (no API key), like the Vigie app.
struct AssistantConnectCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.assistant
        let status = model.codeStatus
        TileRow {
            Card(padding: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Utilise ton abonnement Claude").font(.serif(22)).foregroundStyle(Theme.text)
                    Text("Pas besoin de clé API : l'assistant passe par Claude Code, livré avec l'app Claude, et consomme ton abonnement Claude comme une conversation normale.")
                        .font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    if model.isCheckingStatus && status == nil {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Je cherche Claude Code…").font(.ui(12)).foregroundStyle(Theme.text3) }
                    } else if let status, !status.available {
                        Label("Claude Code est introuvable sur ce Mac.", systemImage: "exclamationmark.triangle").font(.ui(12.5)).foregroundStyle(Theme.warn)
                        Button("Télécharger l'app Claude") { Finder.open("https://claude.ai/download") }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                    } else {
                        Text("Clique sur « Connecter Claude » : une fenêtre Terminal s'ouvre, puis une page dans ton navigateur où tu valides la connexion avec ton compte Claude. À faire une seule fois.")
                            .font(.ui(12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Connecter Claude") { app.assistant.connect() }
                                .buttonStyle(SoftButtonStyle(prominent: true))
                            Button("J'ai terminé la connexion") { Task { await app.assistant.refreshStatus() } }
                                .buttonStyle(SoftButtonStyle())
                            if model.isCheckingStatus { ProgressView().controlSize(.small) }
                        }
                        if let msg = model.connectMessage {
                            Text(msg).font(.ui(11.5)).foregroundStyle(Theme.text2)
                        }
                    }
                }
            }
            Card(padding: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    promise("hand.raised", "Rien ne part sans toi", "Seuls tes messages sont envoyés. L'état du Mac n'est joint que si tu l'autorises.")
                    promise("lock.shield", "Claude Code bridé", "Sans session gardée, sans outil, sans accès à tes fichiers : il ne fait que répondre.")
                    promise("checkmark.shield", "Tu gardes la main", "Les actions arrivent sous forme de boutons ; les plus sensibles demandent une confirmation.")
                }
            }
        }
    }

    private func promise(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.ui(13, .medium)).foregroundStyle(Theme.good).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Key setup

struct AssistantKeySetup: View {
    @Environment(AppModel.self) private var app
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        TileRow {
            Card(padding: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connecte Claude").font(.serif(22)).foregroundStyle(Theme.text)
                    Text("L'assistant utilise l'API d'Anthropic avec ta propre clé. Elle reste dans le Trousseau de ton Mac, jamais dans un fichier.")
                        .font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    Button("Obtenir une clé sur console.anthropic.com") { Finder.open("https://console.anthropic.com/settings/keys") }
                        .buttonStyle(.plain).font(.ui(12.5, .medium)).foregroundStyle(Theme.accent)
                    HStack(spacing: 8) {
                        if Snapshot.isActive {
                            Text("sk-ant-…").font(.mono(12.5)).foregroundStyle(Theme.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8).background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Theme.card))
                        } else {
                            SecureField("sk-ant-…", text: $key)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(save)
                        }
                        Button("Enregistrer", action: save).buttonStyle(SoftButtonStyle(prominent: true))
                    }
                    if let error { Text(error).font(.ui(11.5)).foregroundStyle(Theme.bad) }
                }
            }
            Card(padding: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    promise("hand.raised", "Rien ne part sans toi", "Seuls tes messages sont envoyés. L'état du Mac n'est partagé que si tu l'autorises.")
                    promise("checkmark.shield", "Tu gardes la main", "Claude propose des actions sous forme de boutons ; les plus sensibles demandent une confirmation.")
                    promise("eurosign.circle", "Tu paies à l'usage", "Quelques centimes par conversation avec Opus 5.5 ; Haiku 5.5 coûte 40 fois moins.")
                }
            }
        }
    }

    private func promise(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.ui(13, .medium)).foregroundStyle(Theme.good).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() {
        if app.assistant.saveKey(key) {
            key = ""
            error = nil
        } else {
            error = "Ça ne ressemble pas à une clé API Anthropic (elle commence par « sk-ant- »)."
        }
    }
}

// MARK: - Settings strip

struct AssistantSettingsStrip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.assistant
        let subscription = model.provider == .subscription
        HStack(spacing: 14) {
            if subscription {
                Label(model.codeStatus?.email.map { "Abonnement Claude · \($0)" } ?? "Abonnement Claude", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.ui(12)).foregroundStyle(Theme.good)
            }
            BorderlessMenu {
                ForEach(AssistantModelChoice.allCases) { m in
                    Button { model.modelChoice = m } label: {
                        Text(subscription ? "\(m.familyTitle) — \(m.subscriptionDetail)" : "\(m.title) — \(m.detail)")
                    }
                }
            } label: {
                Label(subscription ? model.modelChoice.familyTitle : model.modelChoice.title, systemImage: "cpu")
                    .font(.ui(12)).foregroundStyle(Theme.text2)
            }
            Toggle("Consulter l'état du Mac", isOn: $model.allowLookups)
                .switchToggles()
                .font(.ui(12))
                .fixedSize()
                .help("Autorise Claude à lire la charge, l'espace disque, les apps gourmandes et les résumés d'analyse")
            Spacer()
            if model.totalTokens > 0 {
                Text(subscription ? "\(Fmt.int(model.totalTokens)) jetons · inclus dans ton abonnement"
                                  : "≈ \(String(format: "%.3f", model.spentDollars).replacingOccurrences(of: ".", with: ",")) $ · \(Fmt.int(model.totalTokens)) jetons")
                    .font(.ui(11)).foregroundStyle(Theme.text3).monospacedDigit()
                    .help(subscription ? "Décompté de ton quota d'abonnement Claude" : "Estimation au tarif public, pour cette session")
            }
            Button("Nouvelle conversation") { model.reset() }
                .buttonStyle(SoftButtonStyle(small: true))
                .disabled(model.entries.isEmpty || model.isThinking)
            BorderlessMenu(indicator: false) {
                Button(subscription ? "Utiliser plutôt une clé API" : "Utiliser plutôt mon abonnement Claude") {
                    model.provider = subscription ? .apiKey : .subscription
                }
                if model.hasKey {
                    Button("Supprimer ma clé API", role: .destructive) { model.deleteKey() }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.ui(13)).foregroundStyle(Theme.text2)
            }
        }
    }
}

// MARK: - Conversation

struct AssistantConversation: View {
    @Environment(AppModel.self) private var app

    private let suggestions = [
        "Pourquoi mon Mac rame en ce moment ?",
        "Qu'est-ce qui prend le plus de place et que je peux supprimer sans risque ?",
        "Mon Mac est-il bien protégé ?",
        "Range mes téléchargements et fais un nettoyage sans risque."
    ]

    var body: some View {
        let model = app.assistant
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                if model.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ClaudeSpark(size: 28)
                            Text("Que veux-tu savoir sur ton Mac ?").font(.serif(21)).foregroundStyle(Theme.text)
                        }
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(suggestions, id: \.self) { s in
                                Button { model.ask(s) } label: {
                                    Text(s).font(.ui(12)).foregroundStyle(Theme.text)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(PillShape().fill(Theme.track))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Astuce : tape « ? » suivi de ta question dans le lanceur, ou clique sur « Demander à Claude » à côté d'un processus ou d'un agent de démarrage.")
                            .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(model.entries) { entry in
                    AssistantEntryView(entry: entry)
                }
                if model.isThinking {
                    HStack(spacing: 10) {
                        ClaudeSpark(size: 18, spin: true)
                        Text("Claude réfléchit…").font(.ui(12.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
    }
}

struct AssistantEntryView: View {
    @Environment(AppModel.self) private var app
    var entry: AssistantEntry

    var body: some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 120)
                Text(text).font(.ui(13)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).fill(Theme.accent.opacity(0.16)))
                    .textSelection(.enabled)
            }
        case .assistant(let text):
            HStack(alignment: .top, spacing: 10) {
                ClaudeSpark(size: 18).padding(.top, 2)
                Text(Self.markdown(text)).font(.ui(13)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 40)
            }
        case .proposal(let id, let title, let reason):
            let done = app.assistant.executed.contains(entry.id)
            let command = ModuleRegistry.commands(app).first { $0.id == id }
            HStack(spacing: 12) {
                CommandIconView(icon: command?.icon ?? .symbol("command"), size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                    Text(reason).font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if done {
                    Label("Lancé", systemImage: "checkmark.circle.fill").font(.ui(12)).foregroundStyle(Theme.good)
                } else {
                    Button(command.map { if case .confirm = $0.risk { return "Exécuter…" } else { return "Exécuter" } } ?? "Exécuter") {
                        app.assistant.execute(entry)
                    }
                    .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(Theme.cardRaised.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(12)).strokeBorder(Theme.border, lineWidth: Theme.line))
            .padding(.leading, 28)
        case .lookup(let text):
            Label(text, systemImage: "eye")
                .font(.ui(11)).foregroundStyle(Theme.text3)
                .padding(.leading, 28)
        case .notice(let text, let isError):
            Callout(symbol: isError ? "exclamationmark.triangle" : "info.circle", title: isError ? "Oups" : "À noter", text: text,
                    tint: isError ? Theme.warn : Theme.accent)
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Composer

/// The message field, pinned at the bottom of the page.
struct AssistantBottomBar: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = app.assistant
        if model.isReady {
            ActionBar {
                if Snapshot.isActive {
                    Text("Écris à Claude…").font(.ui(13)).foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Écris à Claude… (↩ pour envoyer, ⌥↩ pour aller à la ligne)", text: $model.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.ui(13))
                        .lineLimit(1...6)
                        .focused($focused)
                        .onSubmit { model.sendDraft() }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(10))
                            .strokeBorder(focused ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: Theme.line))
                }
                Button {
                    model.sendDraft()
                } label: {
                    Image(systemName: "arrow.up").font(.ui(13, .bold)).foregroundStyle(model.draft.isEmpty || model.isThinking ? Theme.text3 : Theme.onBrand)
                        .frame(width: 32, height: 32)
                        .background(PillShape().fill(model.draft.isEmpty || model.isThinking ? Theme.track : Theme.brand))
                }
                .buttonStyle(.plain)
                .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isThinking)
                .help("Envoyer à Claude")
            }
        }
    }
}
