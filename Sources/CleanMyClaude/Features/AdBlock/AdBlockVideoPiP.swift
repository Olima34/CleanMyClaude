import SwiftUI
import AppKit
import WebKit
import JavaScriptCore

/// Why the last « Détacher la vidéo » did not go through, under the button.
struct AdBlockDetachIssue: Equatable {
    var text: String
    /// The « ? » whose steps settle it.
    var tip: HelpTip?
    /// The permission that settles it, behind a « Réglages… » button.
    var settings: AdBlockDetachSettings?
}

/// What the « Réglages… » button next to the line opens.
enum AdBlockDetachSettings: Equatable {
    /// System Settings' Automation pane: the app may drive the browser.
    case automation
    /// macOS' Accessibility prompt: the app may use Safari's own picture-in-picture command.
    case accessibility

    @MainActor
    func open() {
        switch self {
        case .automation: Finder.open(PermissionKind.safari.settingsURL)
        case .accessibility: AppPermission.accessibility.request()
        }
    }
}

/// Where « Détacher la vidéo » takes the browser's front tab.
enum AdBlockDetachRoute: Equatable {
    /// YouTube, Twitch, France.tv…: the page goes on in the ad-free player, video only.
    case player(URL)
    /// Any other page (Netflix, Prime Video, Disney+…): the browser's own picture in picture. `site`: its name, when known.
    case browser(site: String?)
    /// No web page in that tab (Safari's start page, a blank tab…).
    case nothing
}

/// What the page answered to `AdBlockVideoPiP.request`, then to `check`.
enum AdBlockPiPAnswer: Equatable {
    /// The browser was asked; `lifted`: the page had forbidden the picture in picture on that video.
    case asked(lifted: Bool)
    case entered
    case already
    /// Still in the page; `error`: why, when the browser said it.
    case inline(error: String)
    /// It went into picture in picture, and the page brought it straight back (TF1+'s player in Safari does).
    case kicked
    /// The player is in a frame of another origin (TF1+: prod-player.tf1.fr inside www.tf1.fr): the browser runs the
    /// app's script in the page only, never in such a frame. `site`: the frame's platform, when known.
    case inFrame(site: String?)
    case noVideo
    case unsupported
    case refused(error: String)
    case unreadable
}

/// What the user is told.
struct AdBlockPiPVerdict: Equatable {
    var success: Bool
    var hud: String
    var issue: AdBlockDetachIssue?
}

/// « Détacher la vidéo » on a page the player does not show: Netflix, Prime Video, Disney+ and the other platforms whose
/// videos are protected (DRM), or any page with a video. The browser keeps playing it (its session, its licence) and puts
/// it in its own picture in picture, a window above the others on every desktop. Nothing is bypassed: the script finds the
/// video being watched and asks the browser for the mode it offers by itself (Safari's audio button does the same).
enum AdBlockVideoPiP {
    /// The platforms named in the messages (any other page with a video works the same).
    static let platforms: [(name: String, domains: [String])] = [
        ("Netflix", ["netflix.com"]),
        ("Prime Video", ["primevideo.com"]),
        ("Disney+", ["disneyplus.com"]),
        ("Canal+", ["canalplus.com", "mycanal.fr"]),
        ("HBO Max", ["hbomax.com", "max.com"]),
        ("Apple TV", ["tv.apple.com"]),
        ("Paramount+", ["paramountplus.com"]),
        ("Crunchyroll", ["crunchyroll.com"]),
        ("ADN", ["animationdigitalnetwork.fr", "animationdigitalnetwork.com"]),
        ("MUBI", ["mubi.com"]),
        ("Molotov", ["molotov.tv"]),
        ("OCS", ["ocs.fr"]),
        ("TF1+", ["tf1.fr"]),
        ("Rakuten TV", ["rakuten.tv"]),
        ("Dailymotion", ["dailymotion.com"]),
        ("Vimeo", ["vimeo.com"])
    ]

    static func site(of url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if let name = site(host: host) { return name }
        if host.split(separator: ".").contains("amazon"), url.path.hasPrefix("/gp/video") { return "Prime Video" }
        return nil
    }

    static func site(host raw: String) -> String? {
        let host = raw.lowercased()
        return platforms.first(where: { p in p.domains.contains { host == $0 || host.hasSuffix("." + $0) } })?.name
    }

    /// The player for its platforms, the browser's picture in picture for any other web page.
    @MainActor
    static func route(_ raw: String) -> AdBlockDetachRoute {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return .nothing }
        let web = scheme == "http" || scheme == "https"
        if web, let page = AdBlockPlayer.playable(text) { return .player(page) }
        guard web || scheme == "file" else { return .nothing }
        return .browser(site: site(of: url))
    }

    // MARK: The scripts

    /// `text` as an AppleScript string: quotes and backslashes escaped, line breaks written as escapes.
    static func literal(_ text: String) -> String {
        var out = "\""
        for c in text.unicodeScalars {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }

    /// Run in the browser's tab. Finds the video being watched (the largest one playing on screen, else the largest one,
    /// in the page, its open shadow roots and its frames of the same origin), lets it go into picture in picture if the
    /// page forbade it, and asks the browser for it. The answer is JSON; the browser takes a moment: `check` tells after.
    /// A player in a frame of another origin is out of reach (the browser keeps the page's script out of it): when such
    /// a frame shows more than any video the page holds, it says so ("frame", with the frame's host) instead.
    static let request = #"""
    (() => {
      const videos = [], frames = [];
      const shown = (e) => {
        const r = e.getBoundingClientRect();
        const w = (e.ownerDocument && e.ownerDocument.defaultView) || window;
        const x = Math.min(r.right, w.innerWidth) - Math.max(r.left, 0);
        const y = Math.min(r.bottom, w.innerHeight) - Math.max(r.top, 0);
        return x > 0 && y > 0 ? x * y : 0;
      };
      // A frame made for a player (an embed, a live, the right to play full screen or encrypted media): not an ad box.
      const player = (e, src) => {
        try {
          return e.hasAttribute('allowfullscreen') || e.hasAttribute('webkitallowfullscreen')
            || /autoplay|encrypted-media|fullscreen|picture-in-picture/.test(e.getAttribute('allow') || '')
            || /player|embed|video|live|stream|watch/i.test(src);
        } catch (x) { return false; }
      };
      const look = (root, depth) => {
        let all = [];
        try { all = root.querySelectorAll('*'); } catch (e) { return; }
        for (const e of all) {
          if (e.tagName === 'VIDEO') videos.push(e);
          if (depth < 4 && e.shadowRoot) look(e.shadowRoot, depth + 1);
          if (e.tagName === 'IFRAME' || e.tagName === 'FRAME') {
            let d = null;
            try { d = e.contentDocument; } catch (x) {}
            if (d) {
              if (depth < 4) look(d, depth + 1);
            } else {
              const src = String(e.src || '');
              const m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(src);
              let area = 0;
              try { area = shown(e); } catch (x) {}
              if (area > 0 && player(e, src)) frames.push({ host: m ? m[1].toLowerCase() : '', area: area });
            }
          }
        }
      };
      look(document, 0);
      const inPip = (v) => {
        const root = v.getRootNode ? v.getRootNode() : null;
        return v.webkitPresentationMode === 'picture-in-picture' || !!(root && root.pictureInPictureElement === v);
      };
      if (videos.some(inPip)) return JSON.stringify({ state: 'already', videos: videos.length });
      const playing = (v) => !v.paused && !v.ended && v.readyState > 2;
      let best = null, tier = -1, most = -1;
      for (const v of videos) {
        const a = shown(v);
        const t = playing(v) && a > 0 ? 2 : v.readyState > 0 ? 1 : 0;
        if (t > tier || (t === tier && a > most)) { best = v; tier = t; most = a; }
      }
      // A video playing on screen wins; otherwise a player frame larger than any video of the page (a small paused
      // preview beside it, say) is where the user watches.
      let shut = null;
      for (const f of frames) if (f.area >= 240 * 135 && (!shut || f.area > shut.area)) shut = f;
      if (shut && tier < 2 && shut.area > Math.max(most, 0)) {
        return JSON.stringify({ state: 'frame', host: shut.host, videos: videos.length, frames: frames.length });
      }
      if (!best || (tier === 0 && most === 0)) return JSON.stringify({ state: 'none', videos: videos.length, frames: frames.length });
      const lifted = best.disablePictureInPicture === true || best.hasAttribute('disablepictureinpicture');
      if (lifted) {
        best.removeAttribute('disablepictureinpicture');
        try { best.disablePictureInPicture = false; } catch (e) {}
      }
      const pip = window.__cmcPip = { video: best, error: '', seen: false };
      // Did it go into picture in picture at all? Some pages bring it straight back (TF1+'s player does): heard first,
      // in the capture phase of the video's own tree, before the page's listeners on the video. Added once per page.
      if (!window.__cmcPipSeen) {
        window.__cmcPipSeen = (ev) => {
          const p = window.__cmcPip, v = p && p.video;
          if (!v || ev.target !== v) return;
          const r = v.getRootNode ? v.getRootNode() : null;
          if (v.webkitPresentationMode === 'picture-in-picture' || (r && r.pictureInPictureElement === v)) p.seen = true;
        };
      }
      try {
        const root = best.getRootNode ? best.getRootNode() : null;
        for (const name of ['webkitpresentationmodechanged', 'enterpictureinpicture']) {
          if (root && root.addEventListener) root.addEventListener(name, window.__cmcPipSeen, true);
          best.addEventListener(name, window.__cmcPipSeen);
        }
      } catch (e) {}
      let how = 'webkit';
      try {
        if (typeof best.webkitSetPresentationMode === 'function'
            && (typeof best.webkitSupportsPresentationMode !== 'function' || best.webkitSupportsPresentationMode('picture-in-picture'))) {
          best.webkitSetPresentationMode('picture-in-picture');
        } else if (typeof best.requestPictureInPicture === 'function') {
          how = 'standard';
          const p = best.requestPictureInPicture();
          if (p && p.catch) p.catch((e) => { pip.error = String((e && e.name) || e); });
        } else {
          return JSON.stringify({ state: 'unsupported', videos: videos.length });
        }
      } catch (e) {
        return JSON.stringify({ state: 'refused', error: String((e && e.name) || e), videos: videos.length });
      }
      return JSON.stringify({ state: 'asked', how: how, lifted: lifted, playing: playing(best), videos: videos.length });
    })()
    """#

    /// Run a moment after `request`: is its video in picture in picture now? (`seen`: it was, a moment.)
    static let check = #"""
    (() => {
      const pip = window.__cmcPip;
      if (!pip || !pip.video) return JSON.stringify({ state: 'lost' });
      const v = pip.video;
      const root = v.getRootNode ? v.getRootNode() : null;
      const on = v.webkitPresentationMode === 'picture-in-picture' || !!(root && root.pictureInPictureElement === v);
      return JSON.stringify({ state: on ? 'pip' : 'inline', error: pip.error || '', seen: !!pip.seen });
    })()
    """#

    static func answer(from text: String) -> AdBlockPiPAnswer {
        guard let data = text.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let state = o["state"] as? String else { return .unreadable }
        let error = (o["error"] as? String).map { String($0.prefix(80)) } ?? ""
        switch state {
        case "asked": return .asked(lifted: o["lifted"] as? Bool ?? false)
        case "pip": return .entered
        case "already": return .already
        case "inline": return o["seen"] as? Bool == true ? .kicked : .inline(error: error)
        case "frame": return .inFrame(site: (o["host"] as? String).flatMap { site(host: $0) })
        case "none": return .noVideo
        case "unsupported": return .unsupported
        case "refused": return .refused(error: error)
        default: return .unreadable
        }
    }

    /// No video yet: the page may still be building its player. Asked again twice, `retryDelay` apart.
    static func retry(after answer: AdBlockPiPAnswer, attempt: Int) -> Bool {
        answer == .noVideo && attempt < 2
    }

    static let retryDelay = Duration.milliseconds(700)

    /// The page's script could not do it (a frame of another origin, a video it cannot see, as in a closed shadow root,
    /// or the browser kept the video in the page): the browser's own command may (`AdBlockSafariMenu`), since the
    /// browser sees every video of the page. Not when the page brought the video back by itself.
    static func wantsBrowserCommand(_ answer: AdBlockPiPAnswer) -> Bool {
        switch answer {
        case .inFrame, .noVideo, .inline, .unsupported, .refused: return true
        case .asked, .entered, .already, .kicked, .unreadable: return false
        }
    }

    /// The browser refuses scripts sent by Apple Events (Safari's « Autoriser JavaScript à partir des évènements Apple »,
    /// Chrome's « Allow JavaScript from Apple Events »): both say so in their error.
    static func scriptsRefused(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("javascript")
    }

    // MARK: The messages

    /// `menu`: what Safari's own command did after the page's script, when it was tried (`AdBlockSafariMenu`).
    @MainActor
    static func verdict(_ answer: AdBlockPiPAnswer, browser b: AdBlockVideoBrowser, site pageSite: String?,
                        menu: AdBlockSafariMenuOutcome? = nil) -> AdBlockPiPVerdict {
        var site = pageSite
        if case .inFrame(let frameSite) = answer, site == nil { site = frameSite }
        switch menu {
        case .entered?: return verdict(.entered, browser: b, site: site)
        case .already?: return verdict(.already, browser: b, site: site)
        case .kicked?: return verdict(.kicked, browser: b, site: site)
        case .notOffered? where answer != .noVideo:
            let what = "\(b.name) ne propose pas l'image dans l'image pour \(site ?? "cette vidéo")"
            return AdBlockPiPVerdict(success: false, hud: what, issue: AdBlockDetachIssue(text: what + " : le site l'interdit sans doute."))
        case .noAccess?:
            let player = site.map { "Le lecteur de \($0)" } ?? "Le lecteur"
            return AdBlockPiPVerdict(success: false, hud: "\(site ?? "Vidéo dans un cadre") : \(way(b))",
                                     issue: AdBlockDetachIssue(text: "\(player) est dans un cadre fermé : autorise l'Accessibilité à \(AppEdition.name), il passera par \(b.name).",
                                                               settings: .accessibility))
        case .notOffered?, .failed?, nil:
            break // no video for Safari either, or its menu was not where expected: what the page said
        }
        switch answer {
        case .entered:
            return AdBlockPiPVerdict(success: true, hud: "\(site ?? "La vidéo") est dans l'image dans l'image de \(b.name)")
        case .already:
            return AdBlockPiPVerdict(success: true, hud: "\(site ?? "La vidéo") est déjà dans l'image dans l'image")
        case .kicked:
            return AdBlockPiPVerdict(success: false, hud: "\(site ?? "Le site") refuse l'image dans l'image",
                                     issue: AdBlockDetachIssue(text: "\(site ?? "Le site") ramène sa vidéo dans la page dès qu'elle en sort : il refuse l'image dans l'image."))
        case .inFrame:
            let player = site.map { "Le lecteur de \($0)" } ?? "Le lecteur"
            return AdBlockPiPVerdict(success: false, hud: "\(site ?? "Vidéo dans un cadre") : \(way(b))",
                                     issue: AdBlockDetachIssue(text: "\(player) est dans un cadre fermé à \(AppEdition.name) : \(way(b))."))
        case .noVideo:
            let line = site.map { "Aucune vidéo dans la page de \($0) : lance-la, puis recommence." }
                ?? "Aucune vidéo dans l'onglet affiché de \(b.name) : lance-la, puis recommence."
            return AdBlockPiPVerdict(success: false, hud: site.map { "Aucune vidéo dans la page de \($0)" } ?? "Aucune vidéo dans l'onglet de \(b.name)",
                                     issue: AdBlockDetachIssue(text: line))
        case .asked, .inline, .unsupported, .refused, .unreadable:
            let f = fallback(b)
            return AdBlockPiPVerdict(success: false, hud: f.short, issue: AdBlockDetachIssue(text: f.line))
        }
    }

    /// The browser does not take scripts from the app yet: the steps are in the « ? ».
    @MainActor
    static func scriptsVerdict(_ b: AdBlockVideoBrowser, site: String?) -> AdBlockPiPVerdict {
        AdBlockPiPVerdict(success: false, hud: "\(b.name) doit d'abord écouter \(AppEdition.name) : Multimédia › Vidéo seule",
                          issue: AdBlockDetachIssue(text: "Pour \(site ?? "cette vidéo"), \(b.name) doit accepter le JavaScript des évènements Apple",
                                                    tip: AdBlockTips.safariPause))
    }

    /// The browser's own way to its picture in picture, in a few words.
    static func way(_ b: AdBlockVideoBrowser) -> String {
        switch b.bundleID {
        case "company.thebrowser.Browser": return "change d'onglet, la vidéo passe dans un coin"
        case "com.vivaldi.Vivaldi": return "bouton Image dans l'image au survol de la vidéo"
        default: return b.chromium ? "note de musique de la barre d'outils › Image dans l'image" : "clic droit sur l'icône du son › Image dans l'image"
        }
    }

    /// The browser kept the video in the page: its own way to the picture in picture, in a line (`short` for the HUD).
    static func fallback(_ b: AdBlockVideoBrowser) -> (line: String, short: String) {
        let short = "\(b.name) a refusé : " + way(b)
        switch b.bundleID {
        case "company.thebrowser.Browser":
            return ("Arc a refusé : change d'onglet, Arc garde la vidéo qui joue dans un coin de l'écran.", short)
        case "com.vivaldi.Vivaldi":
            return ("Vivaldi a refusé : survole la vidéo et clique sur son bouton Image dans l'image.", short)
        default:
            if b.chromium {
                return ("\(b.name) a refusé : clique sur la note de musique de la barre d'outils › Image dans l'image.", short)
            }
            return ("\(b.name) a refusé : clic droit sur l'icône du son de la barre d'adresse › Image dans l'image.", short)
        }
    }

    /// `--snapshot --page media --tab safari --pip refus|scripts|aucune|chrome|cadre|accessibilite|renvoyee`: the card
    /// after a page outside the player.
    @MainActor
    static func snapshotIssue(_ state: String) -> AdBlockDetachIssue? {
        let safari = AdBlockVideoBrowser.all[0]
        switch state {
        case "scripts": return scriptsVerdict(safari, site: "Netflix").issue
        case "aucune": return verdict(.noVideo, browser: safari, site: "Disney+").issue
        case "chrome": return verdict(.inline(error: "NotAllowedError"), browser: AdBlockVideoBrowser.all[2], site: "Prime Video").issue
        case "cadre": return verdict(.inFrame(site: "TF1+"), browser: safari, site: "TF1+").issue
        case "accessibilite": return verdict(.inFrame(site: "TF1+"), browser: safari, site: "TF1+", menu: .noAccess).issue
        case "renvoyee": return verdict(.kicked, browser: safari, site: "TF1+").issue
        default: return verdict(.inline(error: ""), browser: safari, site: "Netflix").issue
        }
    }

    // MARK: Checks

    @MainActor
    static func checks() -> [String] {
        var f: [String] = []
        func expect(_ ok: Bool, _ message: String) { if !ok { f.append("image dans l'image : " + message) } }

        // The player for its platforms, the browser's picture in picture elsewhere.
        let routes: [(String, AdBlockDetachRoute)] = [
            ("https://www.netflix.com/watch/81181818?trackId=1", .browser(site: "Netflix")),
            ("https://www.primevideo.com/detail/0ABC", .browser(site: "Prime Video")),
            ("https://www.amazon.fr/gp/video/detail/B0ABC", .browser(site: "Prime Video")),
            ("https://www.amazon.fr/dp/B0ABC", .browser(site: nil)),
            ("https://www.disneyplus.com/fr-fr/play/abc", .browser(site: "Disney+")),
            ("https://tv.apple.com/fr/episode/abc", .browser(site: "Apple TV")),
            ("https://www.apple.com/fr/", .browser(site: nil)),
            ("https://pasnetflix.com/watch", .browser(site: nil)),
            ("https://play.max.com/video/watch/abc", .browser(site: "HBO Max")),
            ("https://www.canalplus.com/live/", .browser(site: "Canal+")),
            ("https://exemple.fr/film.html", .browser(site: nil)),
            ("file:///Users/exemple/Movies/film.mp4", .browser(site: nil)),
            ("favorites://", .nothing),
            ("about:blank", .nothing),
            ("", .nothing)
        ]
        for (raw, want) in routes {
            let got = route(raw)
            expect(got == want, "« \(raw) » va vers \(got) au lieu de \(want)")
        }
        for raw in ["https://www.youtube.com/watch?v=abc", "https://www.twitch.tv/chamois_des_cimes", "https://www.france.tv/series/abc",
                    "https://www.arte.tv/fr/videos/123/"] {
            if case .player = route(raw) {} else { expect(false, "« \(raw) » doit rester dans le lecteur sans pub") }
        }
        expect(Set(platforms.map(\.name)).count == platforms.count, "deux plateformes portent le même nom")
        expect(platforms.allSatisfy { $0.domains.allSatisfy { d in d == d.lowercased() && !d.contains("/") && d.contains(".") } },
               "domaine de plateforme mal écrit")

        // The scripts reach the browser unchanged through an AppleScript string.
        let tricky = "a\"b\\c\nd\te\r'f' « g » $h"
        for (name, text) in [("piège", tricky), ("demande", request), ("contrôle", check), ("pause", AdBlockVideoOnly.pause)] {
            var error: NSDictionary?
            let back = NSAppleScript(source: "return " + literal(text))?.executeAndReturnError(&error).stringValue
            expect(error == nil && back == text, "le script « \(name) » ne passe pas intact par AppleScript")
        }
        for b in AdBlockVideoBrowser.all {
            let script = b.javaScript(request)
            let target = "tell application id \"\(b.bundleID)\" to "
            expect(script.hasPrefix(target) && script.contains(literal(request)), "script d'image dans l'image de \(b.name)")
            expect(script.contains(b.chromium ? "execute active tab of front window javascript" : "do JavaScript"), "commande de \(b.name)")
        }

        // The page's answers.
        let answers: [(String, AdBlockPiPAnswer)] = [
            (#"{"state":"asked","how":"webkit","lifted":true,"playing":true,"videos":3}"#, .asked(lifted: true)),
            (#"{"state":"asked","how":"standard","lifted":false}"#, .asked(lifted: false)),
            (#"{"state":"pip","error":""}"#, .entered),
            (#"{"state":"already","videos":1}"#, .already),
            (#"{"state":"inline","error":"NotAllowedError"}"#, .inline(error: "NotAllowedError")),
            (#"{"state":"inline","error":"","seen":false}"#, .inline(error: "")),
            (#"{"state":"inline","error":"","seen":true}"#, .kicked),
            (#"{"state":"frame","host":"prod-player.tf1.fr","videos":0,"frames":1}"#, .inFrame(site: "TF1+")),
            (#"{"state":"frame","host":"player.exemple.net"}"#, .inFrame(site: nil)),
            (#"{"state":"frame","host":""}"#, .inFrame(site: nil)),
            (#"{"state":"none","videos":0}"#, .noVideo),
            (#"{"state":"unsupported"}"#, .unsupported),
            (#"{"state":"refused","error":"TypeError"}"#, .refused(error: "TypeError")),
            (#"{"state":"lost"}"#, .unreadable),
            ("missing value", .unreadable),
            ("", .unreadable)
        ]
        for (text, want) in answers { expect(answer(from: text) == want, "réponse « \(text) » mal lue") }
        expect(scriptsRefused("Vous devez activer l’option « Autoriser JavaScript à partir des évènements Apple » dans le menu Développement")
               && scriptsRefused("Executing JavaScript through AppleScript is turned off.")
               && !scriptsRefused("Safari got an error: Can’t get document 1."), "refus du JavaScript des évènements Apple mal reconnu")

        // No video yet: twice more, then the answer stands. Safari's own command only where the script could not.
        expect(retry(after: .noVideo, attempt: 0) && retry(after: .noVideo, attempt: 1) && !retry(after: .noVideo, attempt: 2),
               "une page sans vidéo doit être relue deux fois, pas plus")
        expect(!retry(after: .inFrame(site: nil), attempt: 0) && !retry(after: .asked(lifted: false), attempt: 0), "seule l'absence de vidéo se relit")
        let byMenu: [AdBlockPiPAnswer] = [.inFrame(site: "TF1+"), .noVideo, .inline(error: ""), .unsupported, .refused(error: "x")]
        let notByMenu: [AdBlockPiPAnswer] = [.entered, .already, .kicked, .unreadable, .asked(lifted: true)]
        expect(byMenu.allSatisfy(wantsBrowserCommand) && !notByMenu.contains(where: wantsBrowserCommand), "quand passer par le menu de Safari")
        expect(AdBlockVideoBrowser.all.filter(AdBlockSafariMenu.serves).map(\.name) == ["Safari", "Safari Technology Preview"],
               "seul Safari a un menu de la page")

        // The messages: one line each, the right way out for each browser.
        let safari = AdBlockVideoBrowser.all[0], chrome = AdBlockVideoBrowser.all[2]
        let done = verdict(.entered, browser: safari, site: "Netflix")
        expect(done.success && done.issue == nil && done.hud == "Netflix est dans l'image dans l'image de Safari", "message de réussite : \(done.hud)")
        expect(verdict(.inline(error: ""), browser: safari, site: "Netflix").issue?.text.contains("icône du son") == true, "repli de Safari")
        let chromeLine = verdict(.inline(error: "NotAllowedError"), browser: chrome, site: nil).issue?.text ?? ""
        expect(chromeLine.hasPrefix("Chrome a refusé") && chromeLine.contains("note de musique"), "repli de Chrome : \(chromeLine)")
        expect(scriptsVerdict(safari, site: "Netflix").issue?.tip == AdBlockTips.safariPause, "le refus du JavaScript doit montrer les étapes")
        expect(verdict(.noVideo, browser: safari, site: "Disney+").issue?.text.hasPrefix("Aucune vidéo dans la page de Disney+") == true, "pas de vidéo")
        let frame = verdict(.inFrame(site: "TF1+"), browser: safari, site: nil)
        expect(frame.issue?.text.hasPrefix("Le lecteur de TF1+ est dans un cadre") == true && frame.issue?.text.contains("icône du son") == true
               && frame.issue?.settings == nil, "cadre d'une autre origine : \(frame.issue?.text ?? "")")
        let access = verdict(.inFrame(site: nil), browser: safari, site: "TF1+", menu: .noAccess)
        expect(access.issue?.settings == .accessibility && access.issue?.text.contains("Accessibilité") == true && access.hud.contains("icône du son"),
               "sans l'Accessibilité : la ligne la demande, le message donne le geste à faire")
        expect(verdict(.inline(error: ""), browser: safari, site: "Netflix", menu: .entered).success
               && verdict(.inFrame(site: nil), browser: safari, site: "TF1+", menu: .failed("x")) == verdict(.inFrame(site: nil), browser: safari, site: "TF1+"),
               "le menu de Safari l'emporte quand il a réussi, la page sinon")
        expect(verdict(.kicked, browser: safari, site: "TF1+").issue?.text.hasPrefix("TF1+ ramène sa vidéo") == true
               && verdict(.inFrame(site: nil), browser: safari, site: "TF1+", menu: .kicked) == verdict(.kicked, browser: safari, site: "TF1+"),
               "vidéo ramenée dans la page")
        expect(verdict(.inFrame(site: nil), browser: safari, site: "TF1+", menu: .notOffered).issue?.text.hasPrefix("Safari ne propose pas") == true,
               "menu sans image dans l'image")
        expect(verdict(.noVideo, browser: safari, site: "Disney+", menu: .notOffered) == verdict(.noVideo, browser: safari, site: "Disney+")
               && verdict(.noVideo, browser: safari, site: nil, menu: .entered).success, "pas de vidéo pour la page : Safari en a trouvé une, ou pas")
        let all: [AdBlockPiPAnswer] = [.entered, .already, .noVideo, .inline(error: ""), .unsupported, .refused(error: "x"), .unreadable,
                                       .asked(lifted: false), .kicked, .inFrame(site: nil), .inFrame(site: "TF1+")]
        let menus: [AdBlockSafariMenuOutcome] = [.entered, .already, .kicked, .notOffered, .noAccess, .failed("x")]
        for b in AdBlockVideoBrowser.all {
            let verdicts = all.flatMap { a in [nil, "Netflix"].map { verdict(a, browser: b, site: $0) } }
                + menus.map { verdict(.inFrame(site: nil), browser: b, site: nil, menu: $0) } + [scriptsVerdict(b, site: nil)]
            for v in verdicts {
                expect(!v.hud.isEmpty && v.hud.count <= 90 && !v.hud.contains("\n"), "message trop long pour \(b.name) : \(v.hud)")
                expect((v.issue?.text.count ?? 0) <= 120 && v.success == (v.issue == nil), "ligne de \(b.name) : \(v.issue?.text ?? "")")
            }
        }

        f += AdBlockSafariMenu.checks()
        // The scripts in a JavaScript engine, on pages made up for the test.
        f += sceneChecks()
        return f
    }

    /// Pages without a browser: elements reduced to what the scripts read. A change of presentation is heard as in a
    /// browser: first in the capture phase of the video's tree, then on the video, in the order the listeners came.
    private static let mock = #"""
    var window = this, document = null;
    var view = { innerWidth: 1000, innerHeight: 600 };
    window.innerWidth = 1000; window.innerHeight = 600;
    function box(x, y, w, h) { return { left: x, top: y, right: x + w, bottom: y + h, width: w, height: h }; }
    function on(list, n, f) {
      for (var i = 0; i < list.length; i++) if (list[i].name === n && list[i].f === f) return;
      list.push({ name: n, f: f });
    }
    function fire(v, n) {
      var ev = { target: v, type: n };
      if (v.root) v.root.listeners.slice().forEach(function (l) { if (l.name === n) l.f(ev); });
      v.listeners.slice().forEach(function (l) { if (l.name === n) l.f(ev); });
    }
    function video(id, r, o) {
      var v = { id: id, tagName: 'VIDEO', paused: !o.playing, ended: false, readyState: o.ready === undefined ? 4 : o.ready,
                attrs: {}, disablePictureInPicture: !!o.disabled, webkitPresentationMode: o.pip ? 'picture-in-picture' : 'inline',
                asked: 0, listeners: [], ownerDocument: { defaultView: view } };
      if (o.disabled) v.attrs.disablepictureinpicture = '';
      v.getBoundingClientRect = function () { return r; };
      v.hasAttribute = function (n) { return Object.prototype.hasOwnProperty.call(v.attrs, n); };
      v.removeAttribute = function (n) { delete v.attrs[n]; };
      v.getRootNode = function () { return v.root; };
      v.addEventListener = function (n, f) { on(v.listeners, n, f); };
      if (o.standard) {
        v.webkitPresentationMode = undefined;
        v.requestPictureInPicture = function () { v.asked += 1; return Promise.reject({ name: 'NotAllowedError' }); };
      } else {
        v.webkitSupportsPresentationMode = function () { return !v.hasAttribute('disablepictureinpicture'); };
        v.webkitSetPresentationMode = function (m) {
          if (m === 'picture-in-picture') v.asked += 1;
          if (m === v.webkitPresentationMode) return;
          v.webkitPresentationMode = m;
          fire(v, 'webkitpresentationmodechanged');
        };
      }
      // TF1+'s player in Safari, word for word: back in the page as soon as it leaves it.
      if (o.kick) v.addEventListener('webkitpresentationmodechanged', function () { 'picture-in-picture' === v.webkitPresentationMode && v.webkitSetPresentationMode('inline'); });
      return v;
    }
    function frame(src, r, attrs, doc) {
      var f = { tagName: 'IFRAME', src: src, attrs: attrs, ownerDocument: { defaultView: view } };
      f.getBoundingClientRect = function () { return r; };
      f.hasAttribute = function (n) { return Object.prototype.hasOwnProperty.call(f.attrs, n); };
      f.getAttribute = function (n) { return f.hasAttribute(n) ? f.attrs[n] : null; };
      Object.defineProperty(f, 'contentDocument', { get: function () { if (doc === 'throw') throw new Error('autre origine'); return doc; } });
      return f;
    }
    function tree(nodes) {
      var r = { pictureInPictureElement: null, listeners: [], querySelectorAll: function () { return nodes; } };
      r.addEventListener = function (n, f, capture) { if (capture) on(r.listeners, n, f); };
      nodes.forEach(function (n) { if (n.tagName === 'VIDEO') n.root = r; });
      return r;
    }
    var tf1 = 'https://prod-player.tf1.fr/8.4.2/player/index.html?&config=%7B%7D';
    function scene(name) {
      window.__cmcPip = null;
      if (name === 'mix') {
        document = tree([
          video('petite', box(10, 10, 160, 90), { playing: true }),
          video('grande-en-pause', box(180, 10, 400, 225), {}),
          { tagName: 'DIV', shadowRoot: tree([video('protegee', box(590, 10, 320, 180), { playing: true, disabled: true })]) },
          video('loin', box(0, 4000, 480, 270), { playing: true }),
          frame(tf1, box(0, 240, 960, 540), { allowfullscreen: '' }, 'throw')
        ]);
      } else if (name === 'pause') {
        document = tree([
          video('petite', box(10, 10, 160, 90), {}),
          video('grande-en-pause', box(180, 10, 400, 225), {}),
          video('loin', box(0, 4000, 480, 270), {})
        ]);
      } else if (name === 'cadre') {
        document = tree([
          video('petite', box(10, 10, 160, 90), { playing: true }),
          frame('https://www.exemple.fr/lecteur', box(0, 100, 640, 360), { allowfullscreen: '' },
                tree([video('dans-le-cadre', box(0, 0, 640, 360), { playing: true })]))
        ]);
      } else if (name === 'autre-origine') {
        document = tree([frame(tf1, box(0, 60, 960, 540), { allow: 'autoplay; encrypted-media', allowfullscreen: '' }, null)]);
      } else if (name === 'apercu-et-cadre') {
        document = tree([
          video('apercu', box(10, 10, 320, 180), {}),
          frame('https://player.exemple.net/embed/abc', box(0, 200, 960, 400), {}, null)
        ]);
      } else if (name === 'lecture-et-cadre') {
        document = tree([
          video('film', box(0, 0, 640, 360), { playing: true }),
          frame('https://player.exemple.net/embed/abc', box(0, 0, 1000, 600), { allow: 'autoplay' }, null)
        ]);
      } else if (name === 'pub') {
        document = tree([
          frame('https://pub.exemple.net/annonce', box(600, 300, 300, 250), {}, null),
          frame('https://player.exemple.net/embed/abc', box(0, 4000, 960, 540), { allowfullscreen: '' }, null)
        ]);
      } else if (name === 'renvoyee') {
        document = tree([video('direct', box(0, 0, 640, 360), { playing: true, disabled: true, kick: true })]);
      } else if (name === 'vide') {
        document = tree([{ tagName: 'DIV' }]);
      } else if (name === 'rien-de-charge') {
        document = tree([video('vide', box(0, 4000, 480, 270), { ready: 0 })]);
      } else if (name === 'deja') {
        document = tree([video('film', box(0, 0, 640, 360), { playing: true, pip: true })]);
      } else if (name === 'chrome') {
        document = tree([video('film', box(0, 0, 640, 360), { playing: true, standard: true })]);
      }
      return 1;
    }
    function probe() {
      var p = window.__cmcPip;
      return JSON.stringify(p ? { id: p.video.id, attribute: p.video.hasAttribute('disablepictureinpicture'), asked: p.video.asked } : null);
    }
    """#

    private static func sceneChecks() -> [String] {
        var f: [String] = []
        func expect(_ ok: Bool, _ message: String) { if !ok { f.append("image dans l'image : " + message) } }
        guard let ctx = JSContext() else { return ["image dans l'image : pas de moteur JavaScript"] }
        func run(_ source: String) -> String {
            ctx.exception = nil
            let value = ctx.evaluateScript(source)?.toString() ?? ""
            if let e = ctx.exception { f.append("image dans l'image : erreur JavaScript « \(e) »"); ctx.exception = nil }
            return value
        }
        // Every script the browsers get parses (without running).
        ctx.setObject(request, forKeyedSubscript: "srcRequest" as NSString)
        ctx.setObject(check, forKeyedSubscript: "srcCheck" as NSString)
        ctx.setObject(AdBlockVideoOnly.pause, forKeyedSubscript: "srcPause" as NSString)
        ctx.setObject(AdBlockVideoOnly.script, forKeyedSubscript: "srcVideoOnly" as NSString)
        for name in ["srcRequest", "srcCheck", "srcPause", "srcVideoOnly"] {
            let r = run("(function () { try { new Function(\(name)); return 'ok'; } catch (e) { return String(e); } })()")
            expect(r == "ok", "\(name) ne se lit pas : \(r)")
        }
        _ = run(mock)
        struct Scene { var name: String; var want: AdBlockPiPAnswer; var pick: String? }
        let scenes = [
            // The largest video playing on screen, even in a shadow root and forbidden: before a larger one paused, a smaller
            // one, one playing off screen, and a frame of another origin that cannot be read.
            Scene(name: "mix", want: .asked(lifted: true), pick: "protegee"),
            Scene(name: "pause", want: .asked(lifted: false), pick: "grande-en-pause"),
            Scene(name: "cadre", want: .asked(lifted: false), pick: "dans-le-cadre"),
            // TF1+: its player alone, in a frame of another origin; a paused preview beside a larger player frame; a
            // video playing beside a frame; an ad box and a player frame off screen are no player.
            Scene(name: "autre-origine", want: .inFrame(site: "TF1+"), pick: nil),
            Scene(name: "apercu-et-cadre", want: .inFrame(site: nil), pick: nil),
            Scene(name: "lecture-et-cadre", want: .asked(lifted: false), pick: "film"),
            Scene(name: "pub", want: .noVideo, pick: nil),
            // Into picture in picture, and straight back (TF1+'s player in Safari).
            Scene(name: "renvoyee", want: .asked(lifted: true), pick: "direct"),
            Scene(name: "vide", want: .noVideo, pick: nil),
            Scene(name: "rien-de-charge", want: .noVideo, pick: nil),
            Scene(name: "deja", want: .already, pick: nil),
            Scene(name: "chrome", want: .asked(lifted: false), pick: "film")
        ]
        for s in scenes {
            _ = run("scene('\(s.name)')")
            let got = answer(from: run(request))
            expect(got == s.want, "page « \(s.name) » : \(got) au lieu de \(s.want)")
            let p = run("probe()")
            if let pick = s.pick {
                expect(p.contains("\"id\":\"\(pick)\"") && p.contains("\"attribute\":false") && p.contains("\"asked\":1"),
                       "page « \(s.name) » : vidéo choisie \(p) au lieu de \(pick), demandée une fois, sans interdiction")
            } else {
                expect(p == "null", "page « \(s.name) » : aucune vidéo ne devait être demandée (\(p))")
            }
            let after = answer(from: run(check))
            switch s.name {
            case "mix", "pause", "cadre", "lecture-et-cadre": expect(after == .entered, "page « \(s.name) » : \(after) après la demande")
            case "renvoyee": expect(after == .kicked, "page « renvoyee » : la vidéo ramenée dans la page n'est pas vue (\(after))")
            case "chrome": expect(after == .inline(error: "NotAllowedError"), "page « chrome » : le refus du navigateur n'est pas lu (\(after))")
            default: expect(after == .unreadable, "page « \(s.name) » : rien ne devait être suivi (\(after))")
            }
        }
        return f
    }
}

// MARK: - Safari's own command

/// What Safari's own picture-in-picture command did (`AdBlockSafariMenu`).
enum AdBlockSafariMenuOutcome: Equatable, Sendable {
    case entered
    case already
    /// A picture-in-picture window came and went at once: the page brought its video back.
    case kicked
    /// Safari's page menu opened without a picture-in-picture item.
    case notOffered
    /// The app does not have the Accessibility permission (asked only after a click on « Réglages… »).
    case noAccess
    /// Something on the way was not where it should be (`why`: for the bench and the log).
    case failed(String)
}

/// An element of an accessibility tree, reduced to what the searches read; a tree is a flat list, breadth first.
struct AdBlockAXNode: Equatable, Sendable {
    var role = ""
    var title = ""
    var label = ""
    var identifier = ""
    var pressable = false
    var parent: Int?
}

/// Safari's words for what the searches look for, in the language it shows them.
struct AdBlockSafariLabels: Equatable, Sendable {
    var enter: [String]
    var exit: [String]
    var pageMenu: [String]
}

/// Safari's own picture in picture, for a video the page's script cannot reach (a player in a frame of another origin,
/// as TF1+'s): the page menu of the address field (« Menu de la page ») offers « Activer le mode Image dans l'image »
/// while a video plays. Through the Accessibility only, and only once the user granted it: its button, then its item,
/// get an AXPress, as VoiceOver would give them; never a key nor a click. The page menu shows for a moment, then the
/// video leaves for its window, drawn by macOS' picture-in-picture agent: that window tells whether it stayed.
enum AdBlockSafariMenu {
    static let pipAgent = "com.apple.PIPAgent"
    /// Safari's strings (its binary is in the system's shared cache, its resources on disk).
    static let safariFramework = "/System/Library/PrivateFrameworks/Safari.framework"

    /// Safari and its Technology Preview: the other browsers have no such menu.
    static func serves(_ b: AdBlockVideoBrowser) -> Bool { !b.chromium }

    // MARK: Pure parts

    /// Safari's words from its strings (`table`, in the user's language), with the French and English ones anyway.
    static func labels(table: [String: String]?) -> AdBlockSafariLabels {
        let t = table ?? [:]
        func words(_ keys: [String], _ fixed: [String]) -> [String] {
            var out: [String] = []
            for w in keys.compactMap({ t[$0] }) + fixed where !w.isEmpty && !out.contains(w) { out.append(w) }
            return out
        }
        return AdBlockSafariLabels(
            enter: words(["Enter Picture in Picture"], ["Activer le mode Image dans l’image", "Enter Picture in Picture"]),
            exit: words(["Exit Picture in Picture"], ["Quitter le mode Image dans l’image", "Exit Picture in Picture"]),
            pageMenu: words(["Page Menu (Accessibility Label)", "Page Menu with translate (Accessibility Label)"], ["Menu de la page", "Page Menu"]))
    }

    /// Compared without case, curly apostrophes, odd spaces nor a closing ellipsis.
    static func normalized(_ s: String) -> String {
        var t = s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        for space in ["\u{00A0}", "\u{202F}"] { t = t.replacingOccurrences(of: space, with: " ") }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        for tail in ["…", "..."] where t.hasSuffix(tail) {
            t = String(t.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    /// The page menu's button among the toolbar's elements (« Menu de la page, traduction disponible » too).
    static func pageMenuButton(_ nodes: [AdBlockAXNode], labels: AdBlockSafariLabels) -> Int? {
        if let i = nodes.firstIndex(where: { $0.identifier == "AssistantButton" && $0.pressable }) { return i }
        let names = labels.pageMenu.map(normalized).filter { !$0.isEmpty }
        return nodes.firstIndex { n in
            n.pressable && ["AXButton", "AXMenuButton", "AXPopUpButton"].contains(n.role)
                && [n.title, n.label].map(normalized).contains { text in names.contains { text.hasPrefix($0) } }
        }
    }

    /// The command to press in the open menu, and whether it leaves the picture in picture (the video is already in
    /// it). Safari's exact words first, else a command speaking of picture in picture; text that cannot be pressed,
    /// nor be part of something that can, is not a command (the page's title, say).
    static func item(_ nodes: [AdBlockAXNode], labels: AdBlockSafariLabels) -> (index: Int, exit: Bool)? {
        let enter = Set(labels.enter.map(normalized)), exit = Set(labels.exit.map(normalized))
        func pressable(_ i: Int) -> Int? {
            var j: Int? = i
            for _ in 0..<3 {
                guard let k = j else { return nil }
                if nodes[k].pressable { return k }
                j = nodes[k].parent
            }
            return nil
        }
        func texts(_ n: AdBlockAXNode) -> [String] { [n.title, n.label].map(normalized).filter { !$0.isEmpty } }
        for (i, n) in nodes.enumerated() {
            let t = texts(n)
            if t.contains(where: exit.contains), let k = pressable(i) { return (k, true) }
            if t.contains(where: enter.contains), let k = pressable(i) { return (k, false) }
        }
        let loose = ["image dans l'image", "picture in picture", "pictureinpicture"]
        let leaving = ["quitter", "exit", "sortir"]
        for (i, n) in nodes.enumerated() where n.pressable || ["AXMenuItem", "AXButton"].contains(n.role) {
            let t = (texts(n) + [n.identifier.lowercased()]).joined(separator: " ")
            guard loose.contains(where: t.contains), let k = pressable(i) else { continue }
            return (k, leaving.contains(where: t.contains))
        }
        return nil
    }

    /// Enough watching: a window of the agent that was not there before the press has been there for `steady` samples.
    static func settled(before: Set<Int>, samples: [Set<Int>], steady: Int = 5) -> Bool {
        samples.count >= steady && samples.suffix(steady).allSatisfy { !$0.subtracting(before).isEmpty }
    }

    /// The agent's windows sampled after the press: one that came and stayed is the video; one that came and went, the
    /// page bringing it back; none, nothing happened.
    static func outcome(before: Set<Int>, samples: [Set<Int>]) -> AdBlockSafariMenuOutcome {
        let came = samples.reduce(Set<Int>()) { $0.union($1) }.subtracting(before)
        guard !came.isEmpty else { return .failed("aucune fenêtre d'image dans l'image") }
        return samples.last.map { !$0.isDisjoint(with: came) } == true ? .entered : .kicked
    }

    // MARK: The real thing

    /// Safari's strings in the language it shows (the user's first one it has).
    static func safariTable() -> [String: String]? {
        guard let bundle = Bundle(path: safariFramework) else { return nil }
        let language = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: Locale.preferredLanguages).first
        guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language) else { return nil }
        return NSDictionary(contentsOfFile: path) as? [String: String]
    }

    /// The windows macOS' picture-in-picture agent shows now (their numbers). No screen recording needed: their owner
    /// is all it reads.
    static func pipWindows() -> Set<Int> {
        let agents = Set(NSRunningApplication.runningApplications(withBundleIdentifier: pipAgent).map { Int($0.processIdentifier) })
        guard !agents.isEmpty else { return [] }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var out = Set<Int>()
        for w in list where agents.contains(w[kCGWindowOwnerPID as String] as? Int ?? -1) {
            if let n = w[kCGWindowNumber as String] as? Int { out.insert(n) }
        }
        return out
    }

    /// Opens the page menu of the browser's front window, presses its picture-in-picture command and watches its
    /// window. Blocking (about three seconds at most): off the main thread.
    static func enterPictureInPicture(bundleID: String) -> AdBlockSafariMenuOutcome {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
            return .failed("navigateur fermé")
        }
        return enterPictureInPicture(pid: pid)
    }

    /// The same in the process `pid` (the bench gives its own, with a page menu of its own).
    static func enterPictureInPicture(pid: pid_t) -> AdBlockSafariMenuOutcome {
        guard AXIsProcessTrusted() else { return .noAccess }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let window = element(app, kAXMainWindowAttribute) ?? children(app, kAXWindowsAttribute).first else {
            return .failed("aucune fenêtre")
        }
        let labels = labels(table: safariTable())
        let toolbar = children(window).first { string($0, kAXRoleAttribute) == "AXToolbar" }
        let bar = flatten(toolbar ?? window, depth: 6, limit: 300)
        guard let b = pageMenuButton(bar.nodes, labels: labels) else { return .failed("bouton du menu de la page introuvable") }
        let button = bar.elements[b]
        let before = pipWindows()
        // An open menu keeps the press waiting for its answer until it closes: the press does not wait for it.
        AXUIElementSetMessagingTimeout(button, 0.3)
        let pressed = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard pressed == .success || pressed == .cannotComplete else { return .failed("menu de la page refusé (\(pressed.rawValue))") }
        AXUIElementSetMessagingTimeout(button, 1)
        var menu: AXUIElement?
        for _ in 0..<15 where menu == nil {
            usleep(100_000)
            menu = openMenu(app: app, window: window, toolbar: toolbar, button: button)
        }
        guard let menu else { return .failed("le menu de la page ne s'est pas ouvert") }
        let content = flatten(menu, depth: 8, limit: 300)
        guard let hit = item(content.nodes, labels: labels) else {
            close(menu, button)
            return .notOffered
        }
        if hit.exit {
            close(menu, button)
            return .already
        }
        let command = content.elements[hit.index]
        AXUIElementSetMessagingTimeout(command, 1)
        let done = AXUIElementPerformAction(command, kAXPressAction as CFString)
        guard done == .success || done == .cannotComplete else {
            close(menu, button)
            return .failed("commande refusée (\(done.rawValue))")
        }
        var samples: [Set<Int>] = []
        for _ in 0..<12 where !settled(before: before, samples: samples) {
            usleep(200_000)
            samples.append(pipWindows())
        }
        return outcome(before: before, samples: samples)
    }

    /// The menu (or popover) the press opened: under the button, beside the windows, in the window or its toolbar, or
    /// around what has the focus now.
    private static func openMenu(app: AXUIElement, window: AXUIElement, toolbar: AXUIElement?, button: AXUIElement) -> AXUIElement? {
        let kinds: Set<String> = ["AXMenu", "AXPopover"]
        var near = children(button) + children(app) + children(app, kAXWindowsAttribute) + children(window)
        if let toolbar { near += children(toolbar) }
        if let found = near.first(where: { kinds.contains(string($0, kAXRoleAttribute)) }) { return found }
        var e = element(app, kAXFocusedUIElementAttribute)
        for _ in 0..<8 {
            guard let current = e else { break }
            if kinds.contains(string(current, kAXRoleAttribute)) { return current }
            e = element(current, kAXParentAttribute)
        }
        return nil
    }

    /// Closes the menu left open (nothing to press in it).
    private static func close(_ menu: AXUIElement, _ button: AXUIElement) {
        if actions(menu).contains(kAXCancelAction) {
            _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        } else {
            AXUIElementSetMessagingTimeout(button, 0.3)
            _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    /// Breadth first under `root`, without the page itself (Safari's web area holds the whole page).
    private static func flatten(_ root: AXUIElement, depth: Int, limit: Int) -> (elements: [AXUIElement], nodes: [AdBlockAXNode]) {
        var elements: [AXUIElement] = [], nodes: [AdBlockAXNode] = []
        var queue: [(element: AXUIElement, parent: Int?, level: Int)] = children(root).map { ($0, nil, 1) }
        var head = 0
        while head < queue.count && elements.count < limit {
            let next = queue[head]
            head += 1
            let role = string(next.element, kAXRoleAttribute)
            if role == "AXWebArea" { continue }
            nodes.append(AdBlockAXNode(role: role, title: string(next.element, kAXTitleAttribute), label: string(next.element, kAXDescriptionAttribute),
                                       identifier: string(next.element, "AXIdentifier"), pressable: actions(next.element).contains(kAXPressAction),
                                       parent: next.parent))
            elements.append(next.element)
            if next.level < depth {
                let index = elements.count - 1
                queue += children(next.element).map { ($0, index, next.level + 1) }
            }
        }
        return (elements, nodes)
    }

    private static func element(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &ref) == .success, let ref,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func children(_ e: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &ref) == .success else { return [] }
        return ref as? [AXUIElement] ?? []
    }

    private static func string(_ e: AXUIElement, _ attribute: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &ref) == .success else { return "" }
        return ref as? String ?? ""
    }

    private static func actions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    // MARK: Checks

    /// The searches on trees written after Safari's own (its toolbar as read on macOS 27.2), nothing pressed.
    static func checks() -> [String] {
        var f: [String] = []
        func expect(_ ok: Bool, _ message: String) { if !ok { f.append("menu de Safari : " + message) } }
        let fixed = labels(table: nil)
        expect(fixed.enter.contains("Activer le mode Image dans l’image") && fixed.exit.contains("Exit Picture in Picture")
               && fixed.pageMenu.contains("Menu de la page"), "mots de Safari par défaut")
        let german = labels(table: ["Enter Picture in Picture": "Bild-in-Bild starten", "Page Menu (Accessibility Label)": "Seitenmenü"])
        expect(german.enter.first == "Bild-in-Bild starten" && german.enter.contains("Enter Picture in Picture") && german.pageMenu.first == "Seitenmenü",
               "les mots de Safari dans la langue de l'utilisateur passent d'abord")
        expect(normalized("  Activer le mode Image dans l’image… ") == "activer le mode image dans l'image"
               && normalized("Quitter\u{00A0}le mode Image dans l’image") == "quitter le mode image dans l'image", "comparaison des mots")

        // Safari's toolbar as read (nothing pressed): the page menu's button by its identifier, else by its name.
        func node(_ role: String, _ title: String = "", label: String = "", id: String = "", press: Bool = true, parent: Int? = nil) -> AdBlockAXNode {
            AdBlockAXNode(role: role, title: title, label: label, identifier: id, pressable: press, parent: parent)
        }
        var toolbar = [
            node("AXGroup", press: false),
            node("AXButton", label: "afficher la barre latérale", id: "SidebarButton", parent: 0),
            node("AXMenuButton", label: "Sélecteur de groupe d’onglets", id: "TabGroupPickerButton?TabGroup=", parent: 0),
            node("AXGroup", press: false),
            node("AXButton", "Menu de la page", label: "Menu de la page", id: "AssistantButton", parent: 3),
            node("AXButton", "Ajouter la page à la liste de lecture", label: "Ajouter la page à la liste de lecture", id: "OneStepBookmarkingButton", parent: 3),
            node("AXTextField", press: false, parent: 3),
            node("AXButton", "Recharger cette page", label: "Recharger cette page", id: "ReloadButton", parent: 3)
        ]
        expect(pageMenuButton(toolbar, labels: fixed) == 4, "bouton du menu de la page")
        toolbar[4].identifier = ""
        toolbar[4].title = "Menu de la page, traduction disponible"
        expect(pageMenuButton(toolbar, labels: fixed) == 4, "bouton du menu de la page reconnu à son nom")
        toolbar[4].pressable = false
        expect(pageMenuButton(toolbar, labels: fixed) == nil, "un bouton qu'on ne peut presser n'est pas le bon")

        // The open menu: Safari's command, the one that leaves, none, or text that is no command.
        let menu = [
            node("AXMenuItem", "Réduire/agrandir"),
            node("AXMenuItem", "Visualiseur de vidéos"),
            node("AXMenuItem", "Activer le mode Image dans l’image"),
            node("AXMenuItem", "Masquer les éléments gênants…")
        ]
        expect(item(menu, labels: fixed).map { [$0.index, $0.exit ? 1 : 0] } == [2, 0], "commande d'image dans l'image")
        var leaving = menu
        leaving[2].title = "Quitter le mode Image dans l’image"
        expect(item(leaving, labels: fixed).map { [$0.index, $0.exit ? 1 : 0] } == [2, 1], "la vidéo y est déjà")
        let popover = [
            node("AXGroup", press: false),
            node("AXCell", press: true, parent: 0),
            node("AXStaticText", "Activer le mode Image dans l’image", press: false, parent: 1),
            node("AXStaticText", "Comment passer en image dans l'image sur Mac", press: false, parent: 0)
        ]
        expect(item(popover, labels: fixed)?.index == 1, "un texte dans une case qu'on peut presser")
        expect(item(Array(menu.prefix(2)) + [menu[3]], labels: fixed) == nil, "un menu sans image dans l'image")
        expect(item([node("AXStaticText", "Comment passer en image dans l'image sur Mac", press: false)], labels: fixed) == nil,
               "un titre de page n'est pas une commande")
        expect(item([node("AXMenuItem", "Enter Picture in Picture")], labels: german)?.exit == false
               && item([node("AXButton", id: "ExitPictureInPictureButton")], labels: german)?.exit == true, "mots anglais et identifiants")

        // The agent's windows after the press.
        let before: Set<Int> = [7]
        expect(outcome(before: before, samples: [[7], [7, 42], [7, 42], [7, 42], [7, 42], [7, 42]]) == .entered, "fenêtre venue et restée")
        expect(outcome(before: before, samples: [[7], [7, 42], [7], [7], [7]]) == .kicked, "fenêtre venue puis repartie")
        expect(outcome(before: [], samples: [[], [], []]) == .failed("aucune fenêtre d'image dans l'image"), "aucune fenêtre")
        expect(outcome(before: [3], samples: [[], [51]]) == .entered, "une autre image dans l'image remplacée")
        expect(settled(before: before, samples: [[7, 42], [7, 42], [7, 42], [7, 42], [7, 42]])
               && !settled(before: before, samples: [[7, 42], [7, 42], [7], [7, 42], [7, 42]]), "assez regardé")
        return f
    }
}

// MARK: - Bench

/// `--adblock pip [page.html|lien]` : the scripts in a real WebKit view of the app (not the user's browser), in a window
/// at the bottom left of the screen for a few seconds. Without a page, a page of its own: four videos (a small one
/// playing, a larger one paused, one playing off screen, one in a shadow root that forbids the picture in picture), then
/// all paused, then the request sent without a user's gesture, then a page without video, a player in a frame of another
/// origin, and a video the page brings back from the picture in picture (at once, as TF1+'s player; a moment later).
/// Says which video was picked, if the ban was lifted, whether WebKit really went into picture in picture (it may refuse
/// in a view of an app) and what macOS' picture-in-picture agent showed meanwhile. With a link: the page as Safari gets
/// it, cookies refused, then each of its frames' videos, frames and shadow roots (`survey`). With `menu:<pid>`: Safari's
/// own command through the Accessibility, in a process that imitates its page menu (never Safari itself).
@MainActor
enum AdBlockPiPBench {
    private static let page = #"""
    <!doctype html><html><head><meta charset='utf-8'><style>
    body { margin: 0; background: #111; }
    video, #hote { display: inline-block; vertical-align: top; margin: 4px; background: #333; }
    </style></head><body>
    <video id='petite' width='160' height='90' muted playsinline></video>
    <video id='grande-en-pause' width='400' height='225' muted playsinline></video>
    <div id='hote'></div>
    <video id='loin' width='480' height='270' muted playsinline style='position: absolute; left: 0; top: 4000px'></video>
    <script>
    const feed = (v, color, play) => {
      const c = document.createElement('canvas');
      c.width = 320; c.height = 180;
      const g = c.getContext('2d');
      let n = 0;
      const draw = () => { g.fillStyle = color; g.fillRect(0, 0, 320, 180); g.fillStyle = '#fff'; g.font = '40px sans-serif'; g.fillText(String(n++), 20, 60); };
      draw();
      setInterval(draw, 50);
      v.srcObject = c.captureStream(20);
      v.muted = true;
      v.play().then(() => { if (!play) v.pause(); }).catch(() => {});
    };
    const host = document.getElementById('hote').attachShadow({ mode: 'open' });
    host.innerHTML = "<video id='protegee' width='320' height='180' muted playsinline disablepictureinpicture></video>";
    feed(document.getElementById('petite'), '#a33', true);
    feed(document.getElementById('grande-en-pause'), '#3a3', false);
    feed(host.getElementById('protegee'), '#33a', true);
    feed(document.getElementById('loin'), '#aa3', true);
    </script></body></html>
    """#

    private static let probe = """
    (() => { const p = window.__cmcPip, v = p && p.video;
      return JSON.stringify(v ? { id: v.id, attribute: v.hasAttribute('disablepictureinpicture'), property: v.disablePictureInPicture,
        supports: v.webkitSupportsPresentationMode ? v.webkitSupportsPresentationMode('picture-in-picture') : null,
        playing: !v.paused, size: [v.videoWidth, v.videoHeight] } : null); })()
    """

    private static let leave = """
    (() => { const p = window.__cmcPip, v = p && p.video;
      if (v && v.webkitPresentationMode === 'picture-in-picture') v.webkitSetPresentationMode('inline');
      else if (document.pictureInPictureElement) document.exitPictureInPicture();
      return 1; })()
    """

    static func run(_ path: String?) async {
        setvbuf(stdout, nil, _IOLBF, 0)
        // `menu:<pid>`: the accessibility path against another process that imitates Safari's page menu (never Safari).
        if let path, path.hasPrefix("menu:"), let pid = pid_t(path.dropFirst(5)) {
            let name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            guard !name.hasPrefix("com.apple.Safari") else { print("Pas sur Safari lui-même : seulement une imitation."); return }
            let start = Date()
            let outcome = await Task.detached { AdBlockSafariMenu.enterPictureInPicture(pid: pid) }.value
            print(String(format: "Menu de la page du processus %d : %@ en %.1f s", pid, "\(outcome)", Date().timeIntervalSince(start)))
            return
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        // WebKit's own switch for the picture in picture of a view (Safari's is on): read, and turned on for the bench.
        let key = "allowsPictureInPictureMediaPlayback"
        if config.preferences.responds(to: NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")) {
            print("Image dans l'image de la vue : \(config.preferences.value(forKey: key) as? Bool == true ? "permise" : "non permise"), mise à permise pour l'essai")
            config.preferences.setValue(true, forKey: key)
        }
        let size = NSSize(width: 960, height: 360)
        // Really on screen: WebKit holds back the videos of a page it cannot see. Clicks go through it.
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.ignoresMouseEvents = true
        window.level = .floating
        if let path, let url = URL(string: path), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            await survey(url, config: config, window: window)
            window.close()
            return
        }
        let web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        window.contentView = web
        window.orderFrontRegardless()
        if let path {
            let url = URL(fileURLWithPath: FS.expand(path))
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            await AdBlockVideoBench.pump(4)
            _ = await attempt(web, url.lastPathComponent, pick: nil)
            window.close()
            return
        }
        web.loadHTMLString(page, baseURL: nil)
        await AdBlockVideoBench.pump(3)
        var ok = await attempt(web, "Quatre vidéos", pick: "protegee", lifted: true)
        _ = try? await web.evaluateJavaScript("document.querySelectorAll('video').forEach(v => v.pause()); document.getElementById('hote').shadowRoot.querySelector('video').pause(); 1")
        await AdBlockVideoBench.pump(0.5)
        ok = await attempt(web, "Toutes en pause", pick: "grande-en-pause") && ok
        // The same request from a timer, long after any gesture: what a browser sees when nothing marks it as the user's.
        _ = try? await web.evaluateJavaScript("document.querySelectorAll('video').forEach(v => v.play()); 1")
        let before = AdBlockSafariMenu.pipWindows()
        _ = try? await web.evaluateJavaScript("window.__cmcPip = null; window.__cmcLater = ''; setTimeout(() => { window.__cmcLater = " + AdBlockVideoPiP.request + "; }, 1500); 1")
        await AdBlockVideoBench.pump(2)
        let later = (try? await web.evaluateJavaScript("window.__cmcLater || ''")) as? String ?? ""
        print("Sans geste de l'utilisateur (minuteur de 1,5 s)")
        print("  réponse : \(later)")
        print("  image dans l'image : \(await follow(web, AdBlockVideoPiP.answer(from: later), before: before).text)")
        web.loadHTMLString("<!doctype html><p>Rien à voir</p>", baseURL: nil)
        await AdBlockVideoBench.pump(1)
        ok = await attempt(web, "Page sans vidéo", pick: nil, want: .noVideo) && ok
        // TF1+'s player: in a frame the page's script cannot enter (here an opaque origin, as prod-player.tf1.fr is to
        // www.tf1.fr), then, reachable, a video that the page brings straight back into it.
        web.loadHTMLString(framed, baseURL: nil)
        await AdBlockVideoBench.pump(3)
        ok = await attempt(web, "Lecteur dans un cadre d'une autre origine", pick: nil, want: .inFrame(site: nil)) && ok
        // TF1+'s code calls for the page while WebKit is still moving the video: WebKit lets it go, the video stays.
        let heard = "JSON.stringify(window.__cmcKick)"
        web.loadHTMLString(kicking(delay: nil), baseURL: nil)
        await AdBlockVideoBench.pump(3)
        ok = await attempt(web, "Vidéo ramenée aussitôt, mot pour mot comme le lecteur de TF1+ dans Safari", pick: "direct", lifted: true,
                           want: .asked(lifted: true), after: .entered) && ok
        print("  la page a entendu : \((try? await web.evaluateJavaScript(heard)) as? String ?? "")")
        web.loadHTMLString(kicking(delay: 1000), baseURL: nil)
        await AdBlockVideoBench.pump(3)
        ok = await attempt(web, "Vidéo ramenée un peu plus tard", pick: "direct", lifted: true, want: .asked(lifted: true), after: .kicked) && ok
        print("  la page a entendu : \((try? await web.evaluateJavaScript(heard)) as? String ?? "")")
        print(ok ? "Bilan : vidéo choisie, interdiction levée, cadre fermé, vidéo ramenée et page sans vidéo conformes" : "Bilan : ÉCHEC")
        window.close()
    }

    /// A canvas filmed into `video` (no file, no network), playing.
    private static let feeder = """
    const feed = (v, color) => {
      const c = document.createElement('canvas');
      c.width = 320; c.height = 180;
      const g = c.getContext('2d');
      let n = 0;
      const draw = () => { g.fillStyle = color; g.fillRect(0, 0, 320, 180); g.fillStyle = '#fff'; g.font = '40px sans-serif'; g.fillText(String(n++), 20, 60); };
      draw();
      setInterval(draw, 50);
      v.srcObject = c.captureStream(20);
      v.muted = true;
      v.play().catch(() => {});
    };
    """

    /// The player in a sandboxed frame: an opaque origin, which the page's script cannot enter.
    private static var framed: String {
        let inner = "<!doctype html><body style='margin:0;background:#000'><video id='dans-le-cadre' width='640' height='360' muted playsinline></video><script>"
            + feeder + "feed(document.getElementById('dans-le-cadre'), '#a3a');</script></body>"
        let escaped = inner.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        return "<!doctype html><html><body style='margin:0;background:#111'><iframe sandbox='allow-scripts' allow='autoplay; encrypted-media' allowfullscreen "
            + "width='640' height='360' style='border:0' srcdoc=\"" + escaped + "\"></iframe></body></html>"
    }

    /// A video that forbids the picture in picture and brings itself back into the page: as TF1+'s player does in
    /// Safari, word for word, as soon as it hears the change (`delay` nil), or a moment later.
    private static func kicking(delay: Int?) -> String {
        let back = delay.map { "setTimeout(() => v.webkitSetPresentationMode('inline'), \($0))" } ?? "v.webkitSetPresentationMode('inline')"
        return "<!doctype html><html><body style='margin:0;background:#111'><video id='direct' width='640' height='360' muted playsinline></video><script>"
            + feeder + """
            const v = document.getElementById('direct');
            v.disablePictureInPicture = true;
            window.__cmcKick = [];
            v.addEventListener('webkitpresentationmodechanged', () => {
              window.__cmcKick.push(Math.round(performance.now()) + ' ' + v.webkitPresentationMode);
              'picture-in-picture' === v.webkitPresentationMode && \(back);
            });
            feed(v, '#3aa');
            </script></body></html>
            """
    }

    // MARK: A real page

    /// Every frame's report, by frame (its origin and address): the last one wins.
    private final class FrameListener: NSObject, WKScriptMessageHandler {
        var frames: [String: String] = [:]
        var order: [String] = []

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            let o = message.frameInfo.securityOrigin
            let origin = o.protocol + "://" + o.host + (o.port > 0 ? ":\(o.port)" : "")
            let key = (message.frameInfo.isMainFrame ? "document principal " : "cadre ") + origin
            if frames[key] == nil { order.append(key) }
            frames[key] = body
        }
    }

    /// In every frame of the page (this bench's view only): counts the shadow roots as the page attaches them (closed
    /// ones cannot be found afterwards), mutes the videos, and reports what the frame holds every two seconds.
    private static let surveyor = #"""
    (() => {
      if (window.__cmcSurvey) return;
      window.__cmcSurvey = 1;
      let closed = 0, open = 0;
      const closedHosts = [];
      const attach = Element.prototype.attachShadow;
      Element.prototype.attachShadow = function (init) {
        if (init && init.mode === 'closed') { closed += 1; closedHosts.push(this.tagName.toLowerCase()); } else { open += 1; }
        return attach.apply(this, arguments);
      };
      const p = HTMLMediaElement.prototype, play = p.play;
      p.play = function () { this.muted = true; return play.apply(this, arguments); };
      document.addEventListener('volumechange', (e) => { if (e.target.muted === false) e.target.muted = true; }, true);
      const rect = (e) => { const b = e.getBoundingClientRect(); return [Math.round(b.x), Math.round(b.y), Math.round(b.width), Math.round(b.height)]; };
      // The cookie banner, refused (this view's store is thrown away): the player only comes after it.
      let refused = false;
      const refuse = () => {
        if (refused || !document.body) return;
        const words = /^\s*(continuer sans accepter|tout refuser|refuser tout|refuser|je refuse)\s*$/i;
        for (const b of document.querySelectorAll('button, a[role=button], [role=button]')) {
          if (words.test(b.textContent || '') && b.getBoundingClientRect().width > 0) { refused = true; b.click(); return; }
        }
      };
      const report = () => {
        refuse();
        const videos = [], frames = [], customs = {};
        let canvases = 0;
        const look = (root, depth, shadow) => {
          let all = [];
          try { all = root.querySelectorAll('*'); } catch (e) { return; }
          for (const e of all) {
            const t = e.tagName;
            if (t === 'VIDEO') {
              videos.push({ rect: rect(e), paused: e.paused, ready: e.readyState, src: (e.currentSrc || e.src || '').slice(0, 48),
                            size: [e.videoWidth, e.videoHeight], noPip: e.disablePictureInPicture, shadow: shadow, mode: e.webkitPresentationMode });
            } else if (t === 'CANVAS') {
              const r = rect(e);
              if (r[2] * r[3] > 40000) canvases += 1;
            } else if (t === 'IFRAME' || t === 'FRAME' || t === 'EMBED' || t === 'OBJECT') {
              let doc = null;
              try { doc = e.contentDocument; } catch (x) {}
              frames.push({ tag: t, src: (e.src || e.data || '').slice(0, 140), rect: rect(e), allow: e.getAttribute('allow') || '', readable: !!doc });
            }
            if (t.includes('-') && !e.shadowRoot) customs[t.toLowerCase()] = rect(e);
            if (e.shadowRoot && depth < 6) look(e.shadowRoot, depth + 1, true);
          }
        };
        look(document, 0, false);
        const big = Object.entries(customs).filter(([k, r]) => r[2] * r[3] > 40000).slice(0, 12);
        const text = window === window.top && document.body ? document.body.innerText.replace(/\s+/g, ' ').slice(0, 280) : '';
        const msg = JSON.stringify({ href: location.href.slice(0, 160), title: document.title.slice(0, 80), videos: videos, frames: frames,
                                     closed: closed, closedHosts: [...new Set(closedHosts)].slice(0, 10), open: open, canvases: canvases,
                                     customs: big, text: text });
        try { window.webkit.messageHandlers.cmcSurvey.postMessage(msg); } catch (e) {}
      };
      setInterval(report, 2000);
    })();
    """#

    /// `--adblock pip <lien>`: the page as Safari would show it (its user agent, no blocking), each of its frames' videos,
    /// frames and shadow roots, then the request as Safari's `do JavaScript` sends it, in the main frame only.
    private static func survey(_ url: URL, config: WKWebViewConfiguration, window: NSWindow) async {
        let listener = FrameListener()
        config.applicationNameForUserAgent = "Version/\(AdBlockPlayer.safariVersion) Safari/605.1.15"
        config.userContentController.addUserScript(WKUserScript(source: surveyor, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        config.userContentController.add(listener, name: "cmcSurvey")
        let size = NSSize(width: 960, height: 540)
        window.setContentSize(size)
        let web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        window.contentView = web
        window.orderFrontRegardless()
        web.load(URLRequest(url: url))
        print("Page : \(url.absoluteString)")
        for second in stride(from: 6, through: 30, by: 6) {
            await AdBlockVideoBench.pump(6)
            let before = AdBlockSafariMenu.pipWindows()
            let request = (try? await web.evaluateJavaScript("window.__cmcPip = null; " + AdBlockVideoPiP.request)) as? String ?? ""
            print("  \(second) s : \(listener.frames.count) cadre(s) · demande dans le document principal : \(request)")
            if case .asked = AdBlockVideoPiP.answer(from: request) {
                print("  image dans l'image : \(await follow(web, .asked(lifted: false), before: before).text)")
                break
            }
        }
        for key in listener.order { print("\(key)\n  \(listener.frames[key] ?? "")") }
    }

    /// Runs the request as the browser would, then follows the video for a few seconds. True when it went as expected:
    /// `want` answered, `pick` chosen (its ban lifted when `lifted`), and `after` seen once it was asked.
    private static func attempt(_ web: WKWebView, _ title: String, pick: String?, lifted: Bool = false,
                                want: AdBlockPiPAnswer? = nil, after: AdBlockPiPAnswer = .entered) async -> Bool {
        _ = try? await web.evaluateJavaScript("window.__cmcPip = null; 1")
        let before = AdBlockSafariMenu.pipWindows()
        let text = (try? await web.evaluateJavaScript(AdBlockVideoPiP.request)) as? String ?? ""
        let answer = AdBlockVideoPiP.answer(from: text)
        let chosen = (try? await web.evaluateJavaScript(probe)) as? String ?? ""
        print(title)
        print("  réponse : \(text)")
        print("  vidéo choisie : \(chosen)")
        let followed = await follow(web, answer, before: before)
        print("  image dans l'image : \(followed.text)")
        if let want, answer != want { return false }
        guard let pick else { return answer != .unreadable }
        let picked = chosen.contains("\"id\":\"\(pick)\"") && !chosen.contains("\"attribute\":true")
        let liftedOK = !lifted || answer == .asked(lifted: true)
        return picked && liftedOK && followed.last == after
    }

    /// The video a few seconds after the request, and the windows of macOS' picture-in-picture agent meanwhile (what
    /// tells Safari's own command whether it worked); out of picture in picture again afterwards.
    private static func follow(_ web: WKWebView, _ answer: AdBlockPiPAnswer, before: Set<Int>) async -> (text: String, last: AdBlockPiPAnswer) {
        guard case .asked = answer else { return ("rien de demandé (\(answer))", answer) }
        var last = AdBlockPiPAnswer.unreadable
        var samples: [Set<Int>] = []
        for _ in 0..<8 {
            await AdBlockVideoBench.pump(0.35)
            samples.append(AdBlockSafariMenu.pipWindows())
            last = AdBlockVideoPiP.answer(from: (try? await web.evaluateJavaScript(AdBlockVideoPiP.check)) as? String ?? "")
            if last == .entered && AdBlockSafariMenu.settled(before: before, samples: samples, steady: 5) { break }
            if last == .kicked && samples.count >= 4 { break }
            if case .inline(let e) = last, !e.isEmpty { break }
        }
        _ = try? await web.evaluateJavaScript(leave)
        await AdBlockVideoBench.pump(1)
        let windows: String
        switch AdBlockSafariMenu.outcome(before: before, samples: samples) {
        case .entered: windows = "restée"
        case .kicked: windows = "venue puis repartie"
        default: windows = "aucune"
        }
        let text: String
        switch last {
        case .entered: text = "entrée (puis ressortie)"
        case .kicked: text = "entrée, puis ramenée dans la page par le site"
        case .inline(let e): text = "refusée par WebKit" + (e.isEmpty ? "" : " (\(e))")
        default: text = "\(last)"
        }
        return (text + " · fenêtre de l'agent : " + windows, last)
    }
}
