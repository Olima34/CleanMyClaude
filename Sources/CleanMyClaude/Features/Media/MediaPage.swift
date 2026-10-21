import SwiftUI

/// One header, three tabs: Films et séries, the ad-free player, the ad blocker of the whole Mac.
struct MediaPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var media = app.media
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.media.symbol, title: Page.media.title,
                     subtitle: "Où regarder un film, YouTube et Twitch sans pub, et les pubs bloquées sur tout le Mac.",
                     tint: CinemaStyle.tint, seed: 61)
            PillPicker(options: MediaTab.allCases, selection: $media.tab, label: { $0.title },
                       badge: { $0 == .blocker ? app.adblock.sidebarBadge : nil })
            switch media.tab {
            case .watch: CinemaTab()
            case .player: AdBlockPlayerTab()
            case .blocker: AdBlockBlockerTab()
            }
        }
    }
}

struct MediaBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.media.tab {
        case .watch: CinemaBottomBar()
        case .player: EmptyView()
        case .blocker: AdBlockBottomBar()
        }
    }
}

/// `--snapshot --page media --tab bulles`: every « ? » of the page opened, as the popovers show them (they do not render
/// in snapshots).
struct MediaTipsGallery: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tips = [CinemaTips.search, CinemaTips.key, AdBlockTips.player, AdBlockTips.videoOnly, AdBlockTips.safariPause,
                    AdBlockTips.handoff, AdBlockTips.accounts, AdBlockTips.safariExtension(AdBlockBrowser.recommendedName),
                    AdBlockTips.blocker(app.adblock)]
        FlowLayout(spacing: 16, lineSpacing: 16) {
            ForEach(tips, id: \.id) { tip in
                HelpTipCard(tip: tip)
                    .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }
}
