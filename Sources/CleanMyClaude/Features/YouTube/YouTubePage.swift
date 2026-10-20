import SwiftUI

struct YouTubePage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.youtube
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.youtube.symbol, title: "Vidéos YouTube",
                     subtitle: "Colle un lien : la vidéo en MP4 ou le son en MP3, en entier ou juste un extrait. Ça marche aussi depuis le lanceur : colle le lien dans ⌥Espace.",
                     tint: YouTubeStyle.tint, seed: 83) {
                YouTubeDestinationPicker()
            }
            if !model.tools.ready || model.install != nil {
                YouTubeToolsCard()
            }
            YouTubeLinkCard()
            if let link = model.current {
                TileRow(spacing: 16) {
                    YouTubePreviewCard(link: link)
                        .frame(width: 470)
                    YouTubeSettingsCard(link: link)
                }
            } else if model.jobs.isEmpty {
                YouTubeEmptyState()
            }
            if !model.jobs.isEmpty {
                YouTubeQueuePanel()
            }
        }
        .onAppear { model.refreshTools() }
    }
}

// MARK: - Bottom bar

struct YouTubeBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.youtube
        if let link = model.current, model.tools.ready, model.failures[link.id] == nil {
            let info = model.infos[link.id]
            let clip = model.effectiveClip(link.id)
            ActionBar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.title ?? "Vidéo \(link.shortURL)").font(.serif(17)).foregroundStyle(Theme.text).lineLimit(1)
                    Text([model.options.summary, clip.map { "extrait \($0.label)" }, model.estimate(link.id).map { "≈ " + Fmt.bytes($0) },
                          "dans \(model.destination.label)"].compactMap { $0 }.joined(separator: " · "))
                        .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer()
                if !model.activeJobs.isEmpty {
                    Text(Fmt.plural(model.activeJobs.count, "téléchargement en cours", "téléchargements en cours"))
                        .font(.ui(11.5)).foregroundStyle(Theme.text3)
                }
                Button {
                    model.download(link, from: .page)
                } label: {
                    Label(model.options.format.isAudio ? "Télécharger le son" : "Télécharger la vidéo", systemImage: "arrow.down.circle")
                }
                .buttonStyle(SoftButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(info?.isLive == true)
            }
        } else if !model.activeJobs.isEmpty {
            ActionBar {
                BusyMascot(.downloading, pixel: 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(Fmt.plural(model.activeJobs.count, "téléchargement en cours", "téléchargements en cours"))
                        .font(.serif(17)).foregroundStyle(Theme.text)
                    if let running = model.jobs.first(where: { $0.state == .running }) {
                        UsageBar(fraction: running.progress ?? 0, tint: YouTubeStyle.tint, height: 5).frame(width: 240)
                    }
                }
                Spacer()
                Button("Tout annuler") { model.cancelAll() }.buttonStyle(SoftButtonStyle())
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Destination

struct YouTubeDestinationPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.youtube
        HStack(spacing: 9) {
            Image(systemName: "arrow.down.circle").font(.ui(13, .medium)).foregroundStyle(YouTubeStyle.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Enregistrer dans").font(.ui(10.5)).foregroundStyle(Theme.text3)
                BorderlessMenu {
                    Button("Téléchargements") { model.destination = .downloads }
                    Divider()
                    Button("Choisir un dossier…") { model.chooseFolder() }
                } label: {
                    Text(model.destination.label).font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

// MARK: - Tools

/// yt-dlp (and ffmpeg) missing: what they are, and the button that installs them with Homebrew.
struct YouTubeToolsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.youtube
        if let install = model.install {
            Panel(title: install.title,
                  subtitle: install.running ? "Homebrew télécharge et installe : une à deux minutes." : (install.failed ? "Ça n'a pas marché : le détail est ci-dessous." : "Terminé."),
                  symbol: install.running ? "shippingbox" : (install.failed ? "exclamationmark.triangle" : "checkmark.circle"),
                  tint: install.running ? Theme.accent : (install.failed ? Theme.warn : Theme.good)) {
                if install.running {
                    Button("Annuler") { model.cancelInstall() }.buttonStyle(SoftButtonStyle(small: true))
                } else {
                    Button("Fermer") { model.dismissInstall() }.buttonStyle(SoftButtonStyle(small: true))
                }
            } content: {
                HStack(alignment: .top, spacing: 12) {
                    if install.running { BusyMascot(.unpacking, pixel: 2) }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(install.lines.suffix(9).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.mono(11)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            let missing = model.tools.missing.joined(separator: " et ")
            Card {
                HStack(alignment: .top, spacing: 14) {
                    IconBadge(symbol: "shippingbox", tint: Theme.warn)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Il manque \(missing) pour lire YouTube").font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                        Text("yt-dlp est l'outil libre de référence pour télécharger depuis YouTube ; ffmpeg assemble l'image et le son, coupe les extraits et fabrique les MP3. Homebrew les installe et les tient à jour.")
                            .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if model.tools.brew != nil {
                                Button("Installer \(missing)") { model.installTools() }
                                    .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                                Text("brew install \(model.tools.missing.joined(separator: " "))").font(.mono(11)).foregroundStyle(Theme.text3)
                            } else {
                                Button("Installer Homebrew d'abord (brew.sh)") { Finder.open("https://brew.sh/fr/") }
                                    .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                            }
                            Button("Vérifier à nouveau") { model.refreshTools() }.buttonStyle(SoftButtonStyle(small: true))
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Link

struct YouTubeLinkCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.youtube
        let text = model.link.trimmingCharacters(in: .whitespaces)
        Card(padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link").font(.ui(14, .medium)).foregroundStyle(model.current == nil ? Theme.text3 : YouTubeStyle.tint)
                Group {
                    if Snapshot.isActive {
                        Text(text.isEmpty ? "Colle un lien YouTube : youtube.com/watch?v=…, youtu.be/…, un Short…" : text)
                            .foregroundStyle(text.isEmpty ? Theme.text3 : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    } else {
                        TextField("Colle un lien YouTube : youtube.com/watch?v=…, youtu.be/…, un Short…", text: $model.link)
                            .textFieldStyle(.plain)
                    }
                }
                .font(.ui(14))
                if !text.isEmpty {
                    Button { model.link = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.ui(13)).foregroundStyle(Theme.text3)
                    }
                    .buttonStyle(.plain)
                    .help("Effacer le lien")
                }
                Button { model.pasteLink() } label: {
                    Label("Coller", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(SoftButtonStyle(small: true))
                .help("Colle le lien copié")
            }
            if let link = model.current {
                if let failure = model.failures[link.id] {
                    YouTubeFailureLine(id: link.id, failure: failure)
                } else if model.loading.contains(link.id) {
                    HStack(spacing: 8) {
                        BusyMascot(.downloading, pixel: 1)
                        Text("yt-dlp lit la vidéo : durée, qualités et tailles…").font(.ui(11.5)).foregroundStyle(Theme.text3)
                    }
                }
            } else if !text.isEmpty {
                Label("Ce n'est pas le lien d'une vidéo YouTube (une playlist ou une chaîne ne se télécharge pas ici).", systemImage: "questionmark.circle")
                    .font(.ui(11.5)).foregroundStyle(Theme.text3)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Video

struct YouTubePreviewCard: View {
    @Environment(AppModel.self) private var app
    var link: YouTubeLink

    var body: some View {
        let model = app.youtube
        let info = model.infos[link.id]
        Card(padding: 16) {
            // 16:9 over the card's width (470 − 2 × 16).
            YouTubeThumbnail(id: link.id, duration: info?.duration, corner: 12)
                .frame(maxWidth: .infinity)
                .frame(height: 246)
            VStack(alignment: .leading, spacing: 6) {
                Text(info?.title ?? "Lecture de la vidéo…").font(.serif(20)).foregroundStyle(Theme.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let channel = info?.channel, !channel.isEmpty {
                    Text(channel).font(.ui(12.5, .medium)).foregroundStyle(Theme.text2)
                }
            }
            FlowLayout(spacing: 6) {
                if let d = info?.duration { Tag(text: YouTubeTime.spoken(d), symbol: "clock") }
                if let h = info?.maxHeight { Tag(text: "Jusqu'à \(YouTubeStyle.heightName(h))", symbol: "sparkles.tv", tint: YouTubeStyle.tint, filled: true) }
                if let date = info?.uploaded { Tag(text: Fmt.day(date), symbol: "calendar") }
                if let v = info?.views { Tag(text: Fmt.plural(v, "vue", "vues"), symbol: "eye") }
                if link.isShort { Tag(text: "Short", symbol: "rectangle.portrait", tint: YouTubeStyle.tint, filled: true) }
                if info?.isLive == true { Tag(text: "Direct", symbol: "dot.radiowaves.left.and.right", tint: Theme.warn, filled: true) }
            }
            HStack(spacing: 8) {
                Button { Finder.open(link.watchURL) } label: { Label("Voir sur YouTube", systemImage: "play.rectangle") }
                    .buttonStyle(SoftButtonStyle(small: true))
                Text(link.shortURL).font(.mono(11)).foregroundStyle(Theme.text3).textSelection(.enabled)
            }
        }
    }
}

struct YouTubeSettingsCard: View {
    @Environment(AppModel.self) private var app
    var link: YouTubeLink

    var body: some View {
        let model = app.youtube
        Panel(title: "Réglages", subtitle: "Retenus pour la prochaine fois, ici comme dans le lanceur.", symbol: "slider.horizontal.3", tint: YouTubeStyle.tint) {
            if let v = model.ytdlpVersion {
                Text("yt-dlp \(v)").font(.mono(10.5)).foregroundStyle(Theme.text3)
                    .help("La version installée avec Homebrew")
            }
        } content: {
            if let info = model.infos[link.id], info.isLive {
                Callout(symbol: "dot.radiowaves.left.and.right", title: "Un direct en cours",
                        text: "Il se télécharge une fois terminé, quand YouTube l'a enregistré comme une vidéo.", tint: Theme.warn)
            } else {
                YouTubeSettings(link: link)
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive").font(.ui(12)).foregroundStyle(Theme.text3)
                    if let size = model.estimate(link.id) {
                        Text("Environ \(Fmt.bytes(size))").font(.ui(12.5, .medium)).foregroundStyle(Theme.text)
                    } else {
                        Text(model.loading.contains(link.id) ? "Taille calculée dès que yt-dlp a répondu" : "Taille inconnue")
                            .font(.ui(12)).foregroundStyle(Theme.text3)
                    }
                    Text("· dans \(model.destination.label)").font(.ui(12)).foregroundStyle(Theme.text3)
                    Spacer()
                    if model.tools.brew != nil, model.tools.ytdlp != nil {
                        Button("Mettre à jour yt-dlp") { model.updateYtdlp() }
                            .buttonStyle(SoftButtonStyle(small: true))
                            .disabled(model.install?.running == true)
                            .help("YouTube change souvent : la dernière version de yt-dlp suit")
                    }
                }
            }
        }
    }
}

struct YouTubeEmptyState: View {
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 22) {
                BusyMascot(.downloading, pixel: 4, frame: 2)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Copie un lien, colle-le, c'est prêt").font(.serif(22)).foregroundStyle(Theme.text)
                    step("1", "Sur YouTube, copie l'adresse de la vidéo (ou « Partager › Copier le lien »).")
                    step("2", "Colle-la ci-dessus, ou directement dans le lanceur (⌥Espace) : l'aperçu s'affiche à droite.")
                    step("3", "Choisis MP4 ou MP3, la qualité, un extrait si tu veux, puis ↩.")
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n).font(.ui(11, .bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 18, height: 18)
                .background(PillShape().fill(YouTubeStyle.tint))
            Text(text).font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Downloads

struct YouTubeQueuePanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.youtube
        let active = model.activeJobs.count
        let finished = model.finishedJobs.count
        Panel(title: "Téléchargements",
              subtitle: [active > 0 ? Fmt.plural(active, "en cours ou en attente", "en cours ou en attente") : nil,
                         finished > 0 ? Fmt.plural(finished, "terminé", "terminés") : nil].compactMap { $0 }.joined(separator: " · "),
              symbol: "arrow.down.circle", tint: YouTubeStyle.tint) {
            HStack(spacing: 6) {
                if active > 0 { Button("Tout annuler") { model.cancelAll() }.buttonStyle(SoftButtonStyle(small: true)) }
                if finished > 0 { Button("Effacer la liste") { model.clearFinished() }.buttonStyle(SoftButtonStyle(small: true)) }
            }
        } content: {
            VStack(spacing: 6) {
                ForEach(model.jobs) { job in
                    YouTubeJobRow(job: job)
                }
            }
        }
    }
}

struct YouTubeJobRow: View {
    @Environment(AppModel.self) private var app
    var job: YouTubeJob
    @State private var hovering = false

    var body: some View {
        let model = app.youtube
        HStack(alignment: .center, spacing: 12) {
            YouTubeThumbnail(id: job.videoID, duration: nil, corner: 6, badge: false)
                .frame(width: 96, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(job.title).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                    Tag(text: job.summary, symbol: job.options.format.symbol, tint: YouTubeStyle.tint, filled: true)
                }
                switch job.state {
                case .running, .waiting:
                    YouTubeJobProgress(job: job)
                case .done:
                    Text(job.output.map { "\(FS.pretty($0.path))\(size($0))" } ?? "Terminé")
                        .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                case .failed:
                    Text(job.error ?? "Échec").font(.ui(11)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                case .cancelled:
                    Text("Annulé").font(.ui(11)).foregroundStyle(Theme.text3)
                }
            }
            Spacer(minLength: 8)
            stateIcon
            HStack(spacing: 6) {
                switch job.state {
                case .running, .waiting:
                    Button("Annuler") { model.cancel(job) }.buttonStyle(SoftButtonStyle(small: true))
                case .done:
                    if let url = job.output {
                        Button("Ouvrir") { NSWorkspace.shared.open(url) }.buttonStyle(SoftButtonStyle(small: true))
                        Button("Afficher") { Finder.reveal(url.path) }.buttonStyle(SoftButtonStyle(small: true))
                            .help("Afficher dans le Finder")
                    }
                case .failed, .cancelled:
                    if job.suggestsUpdate, model.tools.brew != nil {
                        Button("Mettre à jour yt-dlp") { model.updateYtdlp() }.buttonStyle(SoftButtonStyle(prominent: true, small: true))
                            .disabled(model.install?.running == true)
                    }
                    Button("Réessayer") { model.retry(job) }.buttonStyle(SoftButtonStyle(small: true))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(hovering ? Theme.hover.opacity(0.45) : Theme.bg.opacity(0.5)))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch job.state {
        case .done: Image(systemName: "checkmark.circle.fill").font(.ui(15)).foregroundStyle(Theme.good)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.ui(15)).foregroundStyle(Theme.bad)
        case .cancelled: Image(systemName: "slash.circle").font(.ui(15)).foregroundStyle(Theme.text3)
        case .waiting: Image(systemName: "clock").font(.ui(15)).foregroundStyle(Theme.text3)
        case .running: EmptyView()
        }
    }

    private func size(_ url: URL) -> String {
        if DemoData.isEnabled { return "" }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return bytes > 0 ? " · \(Fmt.bytes(bytes))" : ""
    }
}
