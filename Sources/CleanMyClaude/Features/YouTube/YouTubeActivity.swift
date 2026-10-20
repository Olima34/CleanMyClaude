import SwiftUI

/// The download under way, as the app shows it from anywhere: the sidebar, the menu bar icon and its panel.
struct YouTubeActivity: Equatable {
    var jobID: UUID
    var videoID: String
    var title: String
    /// "Image", "Son", "Découpe de l'extrait"…, or "En attente" before it starts.
    var phase: String
    /// 0…1, nil before the first figure.
    var progress: Double?
    var speed: Double?
    var eta: Double?
    var running: Bool
    /// The downloads waiting behind it.
    var queued: Int

    /// The running download, or else the next one to start (the list is newest first, the oldest goes first).
    static func from(_ jobs: [YouTubeJob]) -> YouTubeActivity? {
        guard let job = jobs.first(where: { $0.state == .running }) ?? jobs.last(where: { $0.state == .waiting }) else { return nil }
        let running = job.state == .running
        return YouTubeActivity(jobID: job.id, videoID: job.videoID, title: job.title,
                               phase: running ? (job.phase.isEmpty ? "Téléchargement" : job.phase) : "En attente",
                               progress: running ? job.progress : nil, speed: running ? job.speed : nil, eta: running ? job.eta : nil,
                               running: running, queued: jobs.filter { $0.state == .waiting && $0.id != job.id }.count)
    }

    /// "62 %", or "…" while no figure is known yet.
    var percent: String {
        guard let progress else { return "…" }
        // Rounded down: 99,6 % is not done yet.
        return "\(Int((min(1, max(0, progress)) * 100).rounded(.down))) %"
    }

    /// "Image · 8,4 Mo/s · encore 9 s · 2 en attente".
    var detail: String {
        var parts = [phase]
        if let speed, speed > 0 { parts.append(Fmt.speed(speed)) }
        if let eta, eta >= 1 { parts.append("encore " + YouTubeTime.spoken(eta)) }
        if queued > 0 { parts.append("\(queued) en attente") }
        return parts.joined(separator: " · ")
    }

    /// The menu bar icon's tooltip.
    var tooltip: String {
        "Téléchargement de « \(title) » : \(progress == nil ? phase.lowercased() : percent)\n\(detail)"
    }
}

/// The download under way in a small card. In the sidebar a click opens Vidéos YouTube; in the menu bar panel it
/// also offers to cancel.
struct YouTubeActivityCard: View {
    enum Style { case sidebar, menu }

    @Environment(AppModel.self) private var app
    var activity: YouTubeActivity
    var style: Style = .sidebar
    @State private var hovering = false

    var body: some View {
        switch style {
        case .sidebar:
            Button(action: open) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(activity.tooltip + "\nClique pour voir les téléchargements.")
        case .menu:
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if style == .sidebar { sidebarContent } else { menuContent }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(hovering ? Theme.hover : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
        .contentShape(Rectangle())
    }

    /// The sidebar is narrow: the title and the figure, the bar, then the step and the time left.
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(activity.title)
                    .font(.ui(11.5, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 2)
                figure(size: 12)
            }
            bar(height: 4)
            Text(shortDetail)
                .font(.ui(10.5))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
        }
        .padding(10)
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                YouTubeThumbnail(id: activity.videoID, duration: nil, corner: 4, badge: false)
                    .frame(width: 64, height: 36)
                Text(activity.title)
                    .font(.ui(12.5, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                figure(size: 14)
            }
            bar(height: 5)
            Text(activity.detail)
                .font(.ui(11))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Voir les téléchargements", action: open)
                    .buttonStyle(SoftButtonStyle(small: true))
                Spacer()
                Button(activity.queued > 0 ? "Annuler celui-ci" : "Annuler") { cancel() }
                    .buttonStyle(SoftButtonStyle(small: true))
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func figure(size: CGFloat) -> some View {
        if activity.running {
            Text(activity.percent)
                .font(.ui(size, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        } else {
            Image(systemName: "clock").font(.ui(size - 1)).foregroundStyle(Theme.text3)
        }
    }

    private func bar(height: CGFloat) -> some View {
        UsageBar(fraction: activity.progress ?? 0, tint: YouTubeStyle.tint, height: height)
            .opacity(activity.progress == nil ? 0.35 : 1)
    }

    /// The step and the time left; the speed stays in the tooltip.
    private var shortDetail: String {
        var parts = [activity.phase]
        if let eta = activity.eta, eta >= 1 { parts.append("encore " + YouTubeTime.spoken(eta)) }
        if activity.queued > 0 { parts.append("+\(activity.queued)") }
        return parts.joined(separator: " · ")
    }

    private func open() {
        LauncherAppActions.openMain(app, .youtube)
    }

    private func cancel() {
        guard let job = app.youtube.jobs.first(where: { $0.id == activity.jobID }) else { return }
        app.youtube.cancel(job)
    }
}
