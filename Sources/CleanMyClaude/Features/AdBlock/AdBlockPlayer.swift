import SwiftUI
import AppKit
import WebKit

/// What the player says over the video while it deals with an ad.
enum AdBlockPlayerNotice: Equatable {
    /// YouTube holds the video back as long as the ad it had planned would have lasted.
    case youtubeHeld
    /// A Twitch ad break: replaced by the same live in another stream, or cut (the picture waits).
    case twitchSwapped
    case twitchCut
}

/// The ad-free player: YouTube and Twitch in a window of Clean My Claude, the blocking engine built in
/// (`AdBlockPlayerScripts`). It browses these two sites itself, after the user opened it; links elsewhere open in the
/// default browser. Closing the window stops everything and frees the page.
@Observable
@MainActor
final class AdBlockPlayer: NSObject {
    static let youtube = URL(string: "https://www.youtube.com/")!
    static let twitch = URL(string: "https://www.twitch.tv/")!

    var isOpen = false
    var title = ""
    var address = ""
    var canGoBack = false
    var canGoForward = false
    var loading = false
    var notice: AdBlockPlayerNotice?
    /// Ads cut since the window opened.
    var cut = 0

    @ObservationIgnored weak var model: AdBlockModel?
    @ObservationIgnored private(set) var web: WKWebView?
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var watches: [NSKeyValueObservation] = []
    @ObservationIgnored private var noticeWork: DispatchWorkItem?

    // MARK: Opening

    func open(_ url: URL) {
        guard !DemoData.isEnabled, !Snapshot.isActive else {
            HUD.show(DemoData.refusal, symbol: "info.circle.fill")
            return
        }
        guard let app = AppContext.model else { return }
        if web == nil { makeWindow(app) }
        web?.load(URLRequest(url: url))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ActionLog.write("LECTEUR SANS PUB \(url.host ?? "")")
    }

    private func makeWindow(_ app: AppModel) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Like Safari: YouTube and Twitch serve their full sites, and remember the account the user signs in with.
        config.applicationNameForUserAgent = "Version/\(Self.safariVersion) Safari/605.1.15"
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        let content = WKUserContentController()
        for source in [AdBlockPlayerScripts.youtube, AdBlockPlayerScripts.twitch] {
            content.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        content.add(AdBlockScriptProxy(self), name: "cmc")
        config.userContentController = content
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1240, height: 780), configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "cleanmyclaude-adfree-1",
                                                                 encodedContentRuleList: AdBlockPlayerScripts.rules) { list, _ in
            if let list { content.add(list) }
        }
        watches = [
            web.observe(\.title) { [weak self] w, _ in MainActor.assumeIsolated { self?.title = w.title ?? "" } },
            web.observe(\.url) { [weak self] w, _ in MainActor.assumeIsolated { self?.address = w.url?.absoluteString ?? "" } },
            web.observe(\.canGoBack) { [weak self] w, _ in MainActor.assumeIsolated { self?.canGoBack = w.canGoBack } },
            web.observe(\.canGoForward) { [weak self] w, _ in MainActor.assumeIsolated { self?.canGoForward = w.canGoForward } },
            web.observe(\.isLoading) { [weak self] w, _ in MainActor.assumeIsolated { self?.loading = w.isLoading } }
        ]
        self.web = web

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Lecteur sans pub"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 420)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView = NSHostingView(rootView: AdBlockPlayerView(player: self).environment(app))
        window.delegate = self
        window.setFrameAutosaveName("CleanMyClaude.AdFreePlayer")
        if !window.setFrameUsingName("CleanMyClaude.AdFreePlayer") { window.center() }
        self.window = window
        isOpen = true
        cut = 0
    }

    /// Safari's own version, for the user agent (the sites serve their full pages to it).
    static var safariVersion: String {
        (NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")?["CFBundleShortVersionString"] as? String) ?? "18.0"
    }

    func close() {
        window?.close()
    }

    func goBack() { web?.goBack() }
    func goForward() { web?.goForward() }
    func reload() { web?.reload() }

    func openInSafari() {
        guard let url = web?.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Messages from the pages

    fileprivate func received(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        let site = body["site"] as? String ?? ""
        switch type {
        case "ad", "adbreak":
            cut += 1
            model?.countVideoAd(site: site)
        case "held":
            show(.youtubeHeld, for: 40)
        case "released", "adbreak-end":
            show(nil, for: 0)
        case "swap":
            show(.twitchSwapped, for: 8)
        case "strip":
            show(.twitchCut, for: 120)
        default:
            break
        }
    }

    /// A notice, gone by itself after `seconds` (in case its end is never reported).
    private func show(_ n: AdBlockPlayerNotice?, for seconds: Double) {
        noticeWork?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { notice = n }
        guard n != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { withAnimation(.easeOut(duration: 0.25)) { self?.notice = nil } }
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Links

    /// Hosts the player shows itself; any other page opens in the default browser.
    static func belongs(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" }
        let own = ["youtube.com", "youtu.be", "youtube-nocookie.com", "ytimg.com", "googlevideo.com", "twitch.tv", "twitchcdn.net",
                   "ttvnw.net", "jtvnw.net", "accounts.google.com", "google.com", "gstatic.com", "googleusercontent.com"]
        return own.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// A YouTube or Twitch address worth opening in the player (short links made whole), or nil.
    static func playable(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host?.lowercased(), url.scheme == "https" || url.scheme == "http" else { return nil }
        if host == "youtu.be" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
            var c = URLComponents(string: "https://www.youtube.com/watch")!
            c.queryItems = [URLQueryItem(name: "v", value: id)] + (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            return c.url
        }
        let youtube = host == "youtube.com" || host.hasSuffix(".youtube.com")
        let twitch = host == "twitch.tv" || host.hasSuffix(".twitch.tv")
        guard youtube || twitch else { return nil }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = "https"
        if youtube, host == "m.youtube.com" || host == "youtube.com" { c?.host = "www.youtube.com" }
        if twitch, host == "m.twitch.tv" || host == "twitch.tv" { c?.host = "www.twitch.tv" }
        return c?.url
    }

    /// The Safari bookmark that hands the page shown to the player (Safari asks once whether to open Clean My Claude).
    static let bookmarklet = "javascript:location.href='cleanmyclaude://regarder?url='+encodeURIComponent(location.href)"
}

extension AdBlockPlayer: WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // The pages of another site, opened by the user in a frame of its own: the default browser shows them.
        if action.targetFrame?.isMainFrame != false, let url = action.request.url, !Self.belongs(url), url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    /// A link that asks for a new window: in this one if it belongs to the sites, in the browser otherwise.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if Self.belongs(url) { webView.load(URLRequest(url: url)) } else { NSWorkspace.shared.open(url) }
        }
        return nil
    }

    func windowWillClose(_ notification: Notification) {
        // The page stops (sound and picture) and its memory is freed.
        watches = []
        web?.stopLoading()
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "cmc")
        web?.loadHTMLString("", baseURL: nil)
        web = nil
        window?.contentView = nil
        window = nil
        isOpen = false
        notice = nil
    }
}

/// Holds the player weakly: WebKit keeps its message handlers for as long as the page lives.
private final class AdBlockScriptProxy: NSObject, WKScriptMessageHandler {
    weak var player: AdBlockPlayer?

    init(_ player: AdBlockPlayer) {
        self.player = player
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { player?.received(body) }
    }
}

// MARK: - The window

struct AdBlockPlayerView: View {
    var player: AdBlockPlayer

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .bottom) {
                if let web = player.web {
                    AdBlockWebView(web: web)
                } else {
                    Theme.bg
                }
                if let notice = player.notice {
                    AdBlockNoticeView(notice: notice)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Theme.bg)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Room for the window's own buttons.
            Spacer().frame(width: 64)
            button("chevron.left", "Page précédente", enabled: player.canGoBack) { player.goBack() }
            button("chevron.right", "Page suivante", enabled: player.canGoForward) { player.goForward() }
            button(player.loading ? "xmark" : "arrow.clockwise", player.loading ? "Arrêter" : "Recharger", enabled: true) {
                if player.loading { player.web?.stopLoading() } else { player.reload() }
            }
            Button("YouTube") { player.open(AdBlockPlayer.youtube) }.buttonStyle(SoftButtonStyle(small: true))
            Button("Twitch") { player.open(AdBlockPlayer.twitch) }.buttonStyle(SoftButtonStyle(small: true))
            Text(player.title.isEmpty ? "Lecteur sans pub" : player.title)
                .font(.ui(12.5, .medium)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity)
            Tag(text: Fmt.plural(player.cut, "pub coupée", "pubs coupées"), symbol: "hand.raised.fill", tint: Theme.good, filled: true)
                .help("Depuis l'ouverture de cette fenêtre")
            button("safari", "Ouvrir cette page dans Safari", enabled: !player.address.isEmpty) { player.openInSafari() }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func button(_ symbol: String, _ help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(12.5, .semibold)).foregroundStyle(enabled ? Theme.text : Theme.text3)
                .frame(width: 26, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

/// What the player says over the video, with the mascot at work.
struct AdBlockNoticeView: View {
    var notice: AdBlockPlayerNotice

    var body: some View {
        HStack(spacing: 12) {
            BusyMascot(.sweeping, pixel: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).fill(Theme.cardRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: Theme.line))
        .themedShadow(color: .black.opacity(0.35), radius: 14, y: 4)
    }

    private var title: String {
        switch notice {
        case .youtubeHeld: return "Pub coupée"
        case .twitchSwapped: return "Coupure pub remplacée"
        case .twitchCut: return "Coupure pub retirée"
        }
    }

    private var detail: String {
        switch notice {
        case .youtubeHeld: return "YouTube retient la vidéo le temps qu'aurait duré sa pub : elle démarre dans quelques secondes, sans pub."
        case .twitchSwapped: return "Tu regardes le même direct par un autre flux, sans pub. La qualité peut baisser un instant."
        case .twitchCut: return "Twitch a remplacé le direct par sa pub : l'image attend la fin de la coupure, sans la pub."
        }
    }
}

/// The page itself, owned by the player (it outlives SwiftUI's redraws).
struct AdBlockWebView: NSViewRepresentable {
    var web: WKWebView

    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
