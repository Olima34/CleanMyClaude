import SwiftUI
import AppKit

enum YouTubeStyle {
    /// The red-pink of the theme's chart colors: YouTube's own red, toned to the theme.
    static var tint: Color { Theme.palette[5] }

    /// "4K", "1440p", "1080p".
    static func heightName(_ h: Int) -> String {
        h >= 2160 ? "4K" : "\(h)p"
    }
}

// MARK: - Picture

/// The video's picture, its duration in the corner like on YouTube.
struct YouTubeThumbnail: View {
    @Environment(AppModel.self) private var app
    var id: String
    var duration: Double?
    var corner: CGFloat = 10
    var badge = true

    var body: some View {
        Color.clear
            .overlay {
                if DemoData.isEnabled {
                    YouTubeDemoPicture(seed: id)
                } else if let cg = app.youtube.thumbnails[id] {
                    Image(decorative: cg, scale: 1).resizable().interpolation(.high).scaledToFill()
                } else {
                    ZStack {
                        Theme.track
                        Image(systemName: "play.rectangle").font(.ui(26)).foregroundStyle(Theme.text3)
                    }
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if badge, let duration, duration > 0 {
                    Text(YouTubeTime.format(duration))
                        .font(.ui(10.5, .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: Theme.r(4)).fill(Theme.bg.opacity(0.86)))
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.r(corner)))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(corner)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

// MARK: - Controls

/// A row of small choices drawn by hand (no AppKit control: they render in snapshots and in the launcher panel).
struct YouTubeChips<T: Hashable>: View {
    var options: [T]
    var selection: T
    var label: (T) -> String
    /// A second line under the label (the size of each quality on the page).
    var detail: (T) -> String? = { _ in nil }
    /// Offered, but not by this video (a 1080p choice for a 720p video gives 720p).
    var dimmed: (T) -> Bool = { _ in false }
    var help: (T) -> String? = { _ in nil }
    var compact = false
    var select: (T) -> Void

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                Button { select(o) } label: {
                    VStack(spacing: 1) {
                        Text(label(o)).font(.ui(compact ? 11 : 12, on ? .semibold : .regular)).lineLimit(1)
                        if let d = detail(o) {
                            Text(d).font(.ui(9.5)).monospacedDigit().foregroundStyle(on ? Theme.text2 : Theme.text3).lineLimit(1)
                        }
                    }
                    .foregroundStyle(on ? Theme.text : Theme.text2)
                    .padding(.horizontal, compact ? 7 : 10)
                    .padding(.vertical, compact ? 4 : 6)
                    .frame(minWidth: compact ? 0 : 54)
                    .background(RoundedRectangle(cornerRadius: Theme.r(7)).fill(on ? Theme.selected : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.r(7))
                        .strokeBorder(on ? YouTubeStyle.tint.opacity(0.6) : Theme.border, lineWidth: max(1, Theme.line)))
                    .opacity(dimmed(o) && !on ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help(o) ?? "")
            }
        }
    }
}

/// Two handles on the video's timeline: where the extract starts and ends, to the second.
struct YouTubeRangeSlider: View {
    var duration: Double
    var clip: YouTubeClip
    var onChange: (YouTubeClip) -> Void
    @State private var dragging: Edge?

    private enum Edge { case start, end }
    private let knob: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width - knob)
            let x0 = CGFloat(clip.start / duration) * w
            let x1 = CGFloat(clip.end / duration) * w
            ZStack(alignment: .leading) {
                PillShape().fill(Theme.track).frame(height: 4).padding(.horizontal, knob / 2)
                PillShape().fill(YouTubeStyle.tint).frame(width: max(2, x1 - x0), height: 4).offset(x: x0 + knob / 2)
                handle.offset(x: x0)
                handle.offset(x: x1)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let t = min(duration, max(0, Double((v.location.x - knob / 2) / w) * duration)).rounded()
                let edge = dragging ?? (abs(t - clip.start) < abs(t - clip.end) || (t < clip.start) ? .start : .end)
                dragging = edge
                var c = clip
                if edge == .start { c.start = min(t, c.end - 1) } else { c.end = max(t, c.start + 1) }
                if c != clip { onChange(c) }
            }.onEnded { _ in dragging = nil })
        }
        .frame(height: knob + 4)
        .help("Fais glisser les poignées pour choisir le début et la fin")
        .modifier(YouTubeKeepsWindowStill())
    }

    private var handle: some View {
        PillShape()
            .fill(Theme.cardRaised)
            .overlay(PillShape().strokeBorder(YouTubeStyle.tint, lineWidth: 2))
            .frame(width: knob, height: knob)
            .themedShadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// The launcher's panel moves when dragged anywhere: over the slider, the drag belongs to the handles.
private struct YouTubeKeepsWindowStill: ViewModifier {
    @State private var held: NSWindow?
    @State private var wasMovable = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside, held == nil, let w = NSApp.keyWindow {
                held = w
                wasMovable = w.isMovableByWindowBackground
                w.isMovableByWindowBackground = false
            } else if !inside, let w = held {
                w.isMovableByWindowBackground = wasMovable
                held = nil
            }
        }
        .onDisappear {
            held?.isMovableByWindowBackground = wasMovable
            held = nil
        }
    }
}

// MARK: - Settings

/// Format, quality and extract: the same settings in the launcher's pane (compact) and on the page.
struct YouTubeSettings: View {
    @Environment(AppModel.self) private var app
    var link: YouTubeLink
    var compact = false

    var body: some View {
        @Bindable var model = app.youtube
        let info = model.infos[link.id]
        let clip = model.clips[link.id]
        VStack(alignment: .leading, spacing: compact ? 7 : 14) {
            row("Format") {
                YouTubeChips(options: YouTubeFormat.allCases, selection: model.options.format,
                             label: { compact ? $0.label : $0.title }, compact: compact) { model.options.format = $0 }
            }
            if model.options.format == .mp4 {
                row("Qualité") {
                    YouTubeChips(options: YouTubeQuality.allCases, selection: model.options.quality,
                                 label: { qualityLabel($0, info) },
                                 detail: { q in compact ? nil : model.infos[link.id].flatMap { _ in
                                     model.estimate(link.id, options: YouTubeOptions(format: .mp4, quality: q)).map { "≈ " + Fmt.bytes($0) } } },
                                 dimmed: { q in (info?.maxHeight).map { max in (q.height ?? 0) > max } ?? false },
                                 help: { q in qualityHelp(q, info) }, compact: compact) { model.options.quality = $0 }
                }
            } else if !compact {
                row("Qualité") {
                    Text(model.options.format == .mp3 ? "MP3 à débit variable, le meilleur (V0), avec la miniature en pochette."
                                                       : "Le son d'origine en AAC, sans perte supplémentaire, avec la pochette.")
                        .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            row("Durée") {
                YouTubeChips(options: [false, true], selection: clip != nil,
                             label: { $0 ? "Un extrait" : (compact ? "En entier" : "La vidéo entière") },
                             dimmed: { $0 && info?.duration == nil },
                             help: { $0 && info?.duration == nil ? "Disponible dès que la durée est connue" : nil },
                             compact: compact) { model.setClip($0, for: link) }
            }
            if let clip, let duration = info?.duration {
                VStack(alignment: .leading, spacing: compact ? 3 : 8) {
                    YouTubeRangeSlider(duration: duration, clip: clip) { model.clips[link.id] = $0 }
                    if compact {
                        HStack {
                            Text(YouTubeTime.format(clip.start))
                            Spacer()
                            Text(YouTubeTime.spoken(clip.length)).foregroundStyle(Theme.text2)
                            Spacer()
                            Text(YouTubeTime.format(clip.end))
                        }
                        .font(.ui(10.5)).monospacedDigit().foregroundStyle(Theme.text3)
                    } else {
                        YouTubeClipFields(id: link.id, clip: clip, duration: duration)
                    }
                }
                .padding(.leading, compact ? 0 : 76)
            }
            if model.options.format == .mp4, let note = codecNote(info) {
                Text(note).font(.ui(compact ? 10.5 : 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, compact ? 0 : 76)
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.ui(compact ? 11 : 12)).foregroundStyle(Theme.text3).frame(width: compact ? 48 : 66, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func qualityLabel(_ q: YouTubeQuality, _ info: YouTubeInfo?) -> String {
        guard q == .best else { return compact ? "\(q.rawValue)" : q.label }
        if let max = info?.maxHeight, max > 1080 { return YouTubeStyle.heightName(max) }
        return "Max"
    }

    private func qualityHelp(_ q: YouTubeQuality, _ info: YouTubeInfo?) -> String? {
        guard let max = info?.maxHeight else { return nil }
        if q == .best { return "La meilleure image de cette vidéo : \(YouTubeStyle.heightName(max))" }
        if let h = q.height, h > max { return "Cette vidéo s'arrête à \(YouTubeStyle.heightName(max)) : tu auras \(YouTubeStyle.heightName(max))" }
        return nil
    }

    /// Above 1080p YouTube only sends VP9 or AV1, which QuickTime may not read: said before, not discovered after.
    private func codecNote(_ info: YouTubeInfo?) -> String? {
        guard let info, let video = YouTubeEngine.videoStream(info, quality: app.youtube.options.quality),
              let codec = video.codecName, !video.isH264 else { return nil }
        return compact ? "En \(YouTubeStyle.heightName(video.height ?? 0)), l'image est en \(codec) : IINA, VLC ou un navigateur la lisent, QuickTime pas toujours."
                       : "En \(YouTubeStyle.heightName(video.height ?? 0)), YouTube n'envoie l'image qu'en \(codec) : IINA, VLC ou un navigateur la lisent, QuickTime et iMovie pas toujours. Choisis 1080p pour du H.264 lisible partout."
    }
}

/// The extract to the second, typed: "1:05" and "2:30".
struct YouTubeClipFields: View {
    @Environment(AppModel.self) private var app
    var id: String
    var clip: YouTubeClip
    var duration: Double

    var body: some View {
        HStack(spacing: 10) {
            field("Début", clip.start) { t in
                var c = clip
                c.start = min(max(0, t), clip.end - 1)
                app.youtube.clips[id] = c
            }
            Image(systemName: "arrow.right").font(.ui(10)).foregroundStyle(Theme.text3)
            field("Fin", clip.end) { t in
                var c = clip
                c.end = max(min(duration, t), clip.start + 1)
                app.youtube.clips[id] = c
            }
            Text("· \(YouTubeTime.spoken(clip.length)) sur \(YouTubeTime.spoken(duration))")
                .font(.ui(11.5)).foregroundStyle(Theme.text3)
        }
    }

    private func field(_ title: String, _ value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.ui(11)).foregroundStyle(Theme.text3)
            YouTubeTimeField(value: value, set: set)
        }
    }
}

/// A time typed by hand ("1:05"); what does not read as a time goes back to the previous value.
struct YouTubeTimeField: View {
    var value: Double
    var set: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if Snapshot.isActive {
                Text(YouTubeTime.format(value)).foregroundStyle(Theme.text)
            } else {
                TextField("0:00", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, f in if !f { commit() } }
            }
        }
        .font(.mono(12, .medium)).monospacedDigit()
        .frame(width: 62)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Theme.r(6)).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(6)).strokeBorder(focused ? YouTubeStyle.tint.opacity(0.7) : Theme.border, lineWidth: max(1, Theme.line)))
        .onAppear { text = YouTubeTime.format(value) }
        .onChange(of: value) { _, v in if !focused { text = YouTubeTime.format(v) } }
    }

    private func commit() {
        if let t = YouTubeTime.parse(text) { set(t) }
        text = YouTubeTime.format(value)
    }
}

// MARK: - Launcher pane

/// At the right of the launcher, like the preview of a file: the video, then how to download it. ↩ downloads.
struct YouTubeLauncherPane: View {
    @Environment(AppModel.self) private var app
    var link: YouTubeLink

    var body: some View {
        let model = app.youtube
        let info = model.infos[link.id]
        let job = model.jobs.first { $0.videoID == link.id && $0.state.isActive }
        VStack(alignment: .leading, spacing: 8) {
            YouTubeThumbnail(id: link.id, duration: info?.duration)
                .frame(maxWidth: .infinity)
                .frame(height: 128)
            VStack(alignment: .leading, spacing: 3) {
                Text(info?.title ?? (model.failures[link.id] == nil ? "Lecture de la vidéo…" : "Vidéo YouTube"))
                    .font(.ui(13.5, .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta(info)).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            if let failure = model.failures[link.id] {
                YouTubeFailureLine(id: link.id, failure: failure, compact: true)
            } else if !model.tools.ready {
                Label("Il manque \(model.tools.missing.joined(separator: " et ")) : ↩ ouvre la page pour l'installer", systemImage: "shippingbox")
                    .font(.ui(11)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            } else {
                YouTubeSettings(link: link, compact: true)
            }
            Spacer(minLength: 0)
            if let job {
                YouTubeJobProgress(job: job, compact: true)
            } else {
                HStack(spacing: 6) {
                    if model.loading.contains(link.id) {
                        BusyMascot(.downloading, pixel: 1)
                        Text("yt-dlp lit la vidéo…").foregroundStyle(Theme.text3)
                    } else if let size = model.estimate(link.id) {
                        Text("≈ \(Fmt.bytes(size))").foregroundStyle(Theme.text2)
                        Text("·").foregroundStyle(Theme.text3)
                    }
                    if !model.loading.contains(link.id) {
                        Image(systemName: "arrow.down.circle").foregroundStyle(Theme.text3)
                        Text(model.destination.label).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                }
                .font(.ui(11))
            }
            Text("↩ Télécharger · ⌘↩ Voir sur YouTube · ⌘K Actions")
                .lineLimit(1)
                .font(.ui(10.5)).foregroundStyle(Theme.text3)
        }
        .padding(14)
        .task(id: link.id) {
            // A link being typed by hand is read once it stays still.
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            model.refreshToolsIfNeeded()
            model.load(link.id)
        }
    }

    private func meta(_ info: YouTubeInfo?) -> String {
        var parts: [String] = []
        if let c = info?.channel, !c.isEmpty { parts.append(c) }
        if let d = info?.duration { parts.append(YouTubeTime.spoken(d)) }
        if let h = info?.maxHeight { parts.append("jusqu'à \(YouTubeStyle.heightName(h))") }
        if link.isShort { parts.append("Short") }
        return parts.isEmpty ? link.shortURL : parts.joined(separator: " · ")
    }
}

/// Why the video cannot be read, with what to do about it.
struct YouTubeFailureLine: View {
    @Environment(AppModel.self) private var app
    var id: String
    var failure: YouTubeFailure
    var compact = false

    var body: some View {
        let model = app.youtube
        VStack(alignment: .leading, spacing: 6) {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                .font(.ui(compact ? 11 : 12)).foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Réessayer") { model.load(id, retry: true) }.buttonStyle(SoftButtonStyle(small: true))
                if failure.suggestsUpdate, model.tools.brew != nil {
                    Button("Mettre à jour yt-dlp") { model.updateYtdlp() }
                        .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                        .disabled(model.install?.running == true)
                }
            }
        }
    }
}

// MARK: - Progress

/// Where a download is: its step, its bar, its speed and what is left.
struct YouTubeJobProgress: View {
    var job: YouTubeJob
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if job.state == .running {
                    BusyMascot(.downloading, pixel: 1)
                }
                Text(status).font(.ui(compact ? 11 : 11.5, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer(minLength: 4)
                if let p = job.progress, job.state == .running {
                    Text(Fmt.pct(p)).font(.ui(compact ? 11 : 11.5)).monospacedDigit().foregroundStyle(Theme.text3)
                }
            }
            if job.state == .running {
                UsageBar(fraction: job.progress ?? 0, tint: YouTubeStyle.tint, height: compact ? 4 : 5)
                    .opacity(job.progress == nil ? 0.35 : 1)
            }
        }
    }

    private var status: String {
        switch job.state {
        case .waiting: return "En attente de la fin du téléchargement en cours"
        case .running:
            var s = job.phase.isEmpty ? "Téléchargement" : job.phase
            if let speed = job.speed, speed > 0 { s += " · " + Fmt.speed(speed) }
            if let eta = job.eta, eta >= 1 { s += " · encore " + YouTubeTime.spoken(eta) }
            if job.progress == nil, let started = job.started { s += " · " + YouTubeTime.spoken(Date().timeIntervalSince(started)) }
            return s
        case .done: return "Terminé"
        case .failed: return job.error ?? "Échec"
        case .cancelled: return "Annulé"
        }
    }
}
