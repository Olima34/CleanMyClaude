import SwiftUI
import AppKit
import WebKit
import JavaScriptCore

/// Why the last « Détacher la vidéo » did not go through, under the button.
struct AdBlockDetachIssue: Equatable {
    var text: String
    /// The « ? » whose steps settle it.
    var tip: HelpTip?
    /// System Settings' Automation pane settles it.
    var settings = false
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
        if let p = platforms.first(where: { p in p.domains.contains { host == $0 || host.hasSuffix("." + $0) } }) { return p.name }
        if host.split(separator: ".").contains("amazon"), url.path.hasPrefix("/gp/video") { return "Prime Video" }
        return nil
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
    static let request = #"""
    (() => {
      const videos = [];
      const look = (root, depth) => {
        let all = [];
        try { all = root.querySelectorAll('*'); } catch (e) { return; }
        for (const e of all) {
          if (e.tagName === 'VIDEO') videos.push(e);
          if (depth < 4 && e.shadowRoot) look(e.shadowRoot, depth + 1);
          if (depth < 4 && e.tagName === 'IFRAME') {
            let d = null;
            try { d = e.contentDocument; } catch (x) {}
            if (d) look(d, depth + 1);
          }
        }
      };
      look(document, 0);
      const inPip = (v) => {
        const root = v.getRootNode ? v.getRootNode() : null;
        return v.webkitPresentationMode === 'picture-in-picture' || !!(root && root.pictureInPictureElement === v);
      };
      if (videos.some(inPip)) return JSON.stringify({ state: 'already', videos: videos.length });
      const shown = (v) => {
        const r = v.getBoundingClientRect();
        const w = (v.ownerDocument && v.ownerDocument.defaultView) || window;
        const x = Math.min(r.right, w.innerWidth) - Math.max(r.left, 0);
        const y = Math.min(r.bottom, w.innerHeight) - Math.max(r.top, 0);
        return x > 0 && y > 0 ? x * y : 0;
      };
      const playing = (v) => !v.paused && !v.ended && v.readyState > 2;
      let best = null, tier = -1, most = -1;
      for (const v of videos) {
        const a = shown(v);
        const t = playing(v) && a > 0 ? 2 : v.readyState > 0 ? 1 : 0;
        if (t > tier || (t === tier && a > most)) { best = v; tier = t; most = a; }
      }
      if (!best || (tier === 0 && most === 0)) return JSON.stringify({ state: 'none', videos: videos.length });
      const lifted = best.disablePictureInPicture === true || best.hasAttribute('disablepictureinpicture');
      if (lifted) {
        best.removeAttribute('disablepictureinpicture');
        try { best.disablePictureInPicture = false; } catch (e) {}
      }
      const pip = window.__cmcPip = { video: best, error: '' };
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

    /// Run a moment after `request`: is its video in picture in picture now?
    static let check = #"""
    (() => {
      const pip = window.__cmcPip;
      if (!pip || !pip.video) return JSON.stringify({ state: 'lost' });
      const v = pip.video;
      const root = v.getRootNode ? v.getRootNode() : null;
      const on = v.webkitPresentationMode === 'picture-in-picture' || !!(root && root.pictureInPictureElement === v);
      return JSON.stringify({ state: on ? 'pip' : 'inline', error: pip.error || '' });
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
        case "inline": return .inline(error: error)
        case "none": return .noVideo
        case "unsupported": return .unsupported
        case "refused": return .refused(error: error)
        default: return .unreadable
        }
    }

    /// The browser refuses scripts sent by Apple Events (Safari's « Autoriser JavaScript à partir des évènements Apple »,
    /// Chrome's « Allow JavaScript from Apple Events »): both say so in their error.
    static func scriptsRefused(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("javascript")
    }

    // MARK: The messages

    @MainActor
    static func verdict(_ answer: AdBlockPiPAnswer, browser b: AdBlockVideoBrowser, site: String?) -> AdBlockPiPVerdict {
        switch answer {
        case .entered:
            return AdBlockPiPVerdict(success: true, hud: "\(site ?? "La vidéo") est dans l'image dans l'image de \(b.name)")
        case .already:
            return AdBlockPiPVerdict(success: true, hud: "\(site ?? "La vidéo") est déjà dans l'image dans l'image")
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

    /// The browser kept the video in the page: its own way to the picture in picture, in a line (`short` for the HUD).
    static func fallback(_ b: AdBlockVideoBrowser) -> (line: String, short: String) {
        switch b.bundleID {
        case "company.thebrowser.Browser":
            return ("Arc a refusé : change d'onglet, Arc garde la vidéo qui joue dans un coin de l'écran.",
                    "Arc a refusé : change d'onglet, la vidéo passe dans un coin")
        case "com.vivaldi.Vivaldi":
            return ("Vivaldi a refusé : survole la vidéo et clique sur son bouton Image dans l'image.",
                    "Vivaldi a refusé : bouton Image dans l'image au survol de la vidéo")
        default:
            if b.chromium {
                return ("\(b.name) a refusé : clique sur la note de musique de la barre d'outils › Image dans l'image.",
                        "\(b.name) a refusé : note de musique de la barre d'outils › Image dans l'image")
            }
            return ("\(b.name) a refusé : clic droit sur l'icône du son de la barre d'adresse › Image dans l'image.",
                    "\(b.name) a refusé : clic droit sur l'icône du son › Image dans l'image")
        }
    }

    /// `--snapshot --page media --tab safari --pip refus|scripts|aucune|chrome`: the card after a page outside the player.
    @MainActor
    static func snapshotIssue(_ state: String) -> AdBlockDetachIssue? {
        let safari = AdBlockVideoBrowser.all[0]
        switch state {
        case "scripts": return scriptsVerdict(safari, site: "Netflix").issue
        case "aucune": return verdict(.noVideo, browser: safari, site: "Disney+").issue
        case "chrome": return verdict(.inline(error: "NotAllowedError"), browser: AdBlockVideoBrowser.all[2], site: "Prime Video").issue
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

        // The messages: one line each, the right way out for each browser.
        let safari = AdBlockVideoBrowser.all[0], chrome = AdBlockVideoBrowser.all[2]
        let done = verdict(.entered, browser: safari, site: "Netflix")
        expect(done.success && done.issue == nil && done.hud == "Netflix est dans l'image dans l'image de Safari", "message de réussite : \(done.hud)")
        expect(verdict(.inline(error: ""), browser: safari, site: "Netflix").issue?.text.contains("icône du son") == true, "repli de Safari")
        let chromeLine = verdict(.inline(error: "NotAllowedError"), browser: chrome, site: nil).issue?.text ?? ""
        expect(chromeLine.hasPrefix("Chrome a refusé") && chromeLine.contains("note de musique"), "repli de Chrome : \(chromeLine)")
        expect(scriptsVerdict(safari, site: "Netflix").issue?.tip == AdBlockTips.safariPause, "le refus du JavaScript doit montrer les étapes")
        expect(verdict(.noVideo, browser: safari, site: "Disney+").issue?.text.hasPrefix("Aucune vidéo dans la page de Disney+") == true, "pas de vidéo")
        let all: [AdBlockPiPAnswer] = [.entered, .already, .noVideo, .inline(error: ""), .unsupported, .refused(error: "x"), .unreadable, .asked(lifted: false)]
        for b in AdBlockVideoBrowser.all {
            for v in all.map({ verdict($0, browser: b, site: "Netflix") }) + [scriptsVerdict(b, site: nil)] {
                expect(!v.hud.isEmpty && v.hud.count <= 90 && !v.hud.contains("\n"), "message trop long pour \(b.name) : \(v.hud)")
                expect((v.issue?.text.count ?? 0) <= 110 && v.success == (v.issue == nil), "ligne de \(b.name) : \(v.issue?.text ?? "")")
            }
        }

        // The scripts in a JavaScript engine, on pages made up for the test.
        f += sceneChecks()
        return f
    }

    /// Pages without a browser: elements reduced to what the scripts read.
    private static let mock = #"""
    var window = this, document = null;
    var view = { innerWidth: 1000, innerHeight: 600 };
    window.innerWidth = 1000; window.innerHeight = 600;
    function box(x, y, w, h) { return { left: x, top: y, right: x + w, bottom: y + h, width: w, height: h }; }
    function video(id, r, o) {
      var v = { id: id, tagName: 'VIDEO', paused: !o.playing, ended: false, readyState: o.ready === undefined ? 4 : o.ready,
                attrs: {}, disablePictureInPicture: !!o.disabled, webkitPresentationMode: o.pip ? 'picture-in-picture' : 'inline',
                asked: 0, ownerDocument: { defaultView: view } };
      if (o.disabled) v.attrs.disablepictureinpicture = '';
      v.getBoundingClientRect = function () { return r; };
      v.hasAttribute = function (n) { return Object.prototype.hasOwnProperty.call(v.attrs, n); };
      v.removeAttribute = function (n) { delete v.attrs[n]; };
      v.getRootNode = function () { return v.root; };
      if (o.standard) {
        v.webkitPresentationMode = undefined;
        v.requestPictureInPicture = function () { v.asked += 1; return Promise.reject({ name: 'NotAllowedError' }); };
      } else {
        v.webkitSupportsPresentationMode = function () { return !v.hasAttribute('disablepictureinpicture'); };
        v.webkitSetPresentationMode = function (m) { v.asked += 1; v.webkitPresentationMode = m; };
      }
      return v;
    }
    function tree(nodes) {
      var r = { pictureInPictureElement: null, querySelectorAll: function () { return nodes; } };
      nodes.forEach(function (n) { if (n.tagName === 'VIDEO') n.root = r; });
      return r;
    }
    function scene(name) {
      window.__cmcPip = null;
      if (name === 'mix') {
        document = tree([
          video('petite', box(10, 10, 160, 90), { playing: true }),
          video('grande-en-pause', box(180, 10, 400, 225), {}),
          { tagName: 'DIV', shadowRoot: tree([video('protegee', box(590, 10, 320, 180), { playing: true, disabled: true })]) },
          video('loin', box(0, 4000, 480, 270), { playing: true }),
          { tagName: 'IFRAME', get contentDocument() { throw new Error('autre origine'); } }
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
          { tagName: 'IFRAME', contentDocument: tree([video('dans-le-cadre', box(0, 0, 640, 360), { playing: true })]) }
        ]);
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
            case "mix", "pause", "cadre": expect(after == .entered, "page « \(s.name) » : \(after) après la demande")
            case "chrome": expect(after == .inline(error: "NotAllowedError"), "page « chrome » : le refus du navigateur n'est pas lu (\(after))")
            default: expect(after == .unreadable, "page « \(s.name) » : rien ne devait être suivi (\(after))")
            }
        }
        return f
    }
}

// MARK: - Bench

/// `--adblock pip [page.html]` : the scripts in a real WebKit view of the app (not the user's browser), in a window at
/// the bottom left of the screen for a few seconds. Without a page, a page of its own: four videos (a small one playing,
/// a larger one paused, one playing off screen, one in a shadow root that forbids the picture in picture), then all
/// paused, then the request sent without a user's gesture, then a page without video. Says which video was picked, if
/// the ban was lifted, and whether WebKit really went into picture in picture (it may refuse in a view of an app).
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
        _ = try? await web.evaluateJavaScript("window.__cmcPip = null; window.__cmcLater = ''; setTimeout(() => { window.__cmcLater = " + AdBlockVideoPiP.request + "; }, 1500); 1")
        await AdBlockVideoBench.pump(2)
        let later = (try? await web.evaluateJavaScript("window.__cmcLater || ''")) as? String ?? ""
        print("Sans geste de l'utilisateur (minuteur de 1,5 s)")
        print("  réponse : \(later)")
        print("  image dans l'image : \(await follow(web, AdBlockVideoPiP.answer(from: later)))")
        web.loadHTMLString("<!doctype html><p>Rien à voir</p>", baseURL: nil)
        await AdBlockVideoBench.pump(1)
        ok = await attempt(web, "Page sans vidéo", pick: nil, none: true) && ok
        print(ok ? "Bilan : vidéo choisie, interdiction levée et page sans vidéo conformes" : "Bilan : ÉCHEC")
        window.close()
    }

    /// Runs the request as the browser would, then follows the video for a few seconds. True when it went as expected.
    private static func attempt(_ web: WKWebView, _ title: String, pick: String?, lifted: Bool = false, none: Bool = false) async -> Bool {
        _ = try? await web.evaluateJavaScript("window.__cmcPip = null; 1")
        let text = (try? await web.evaluateJavaScript(AdBlockVideoPiP.request)) as? String ?? ""
        let answer = AdBlockVideoPiP.answer(from: text)
        let chosen = (try? await web.evaluateJavaScript(probe)) as? String ?? ""
        print(title)
        print("  réponse : \(text)")
        print("  vidéo choisie : \(chosen)")
        print("  image dans l'image : \(await follow(web, answer))")
        if none { return answer == .noVideo }
        guard let pick else { return true }
        let picked = chosen.contains("\"id\":\"\(pick)\"") && !chosen.contains("\"attribute\":true")
        let liftedOK = !lifted || answer == .asked(lifted: true)
        return picked && liftedOK && answer != .unreadable
    }

    /// The video a few seconds after the request; out of picture in picture again afterwards.
    private static func follow(_ web: WKWebView, _ answer: AdBlockPiPAnswer) async -> String {
        guard case .asked = answer else { return "rien de demandé (\(answer))" }
        var last = AdBlockPiPAnswer.unreadable
        for _ in 0..<8 {
            await AdBlockVideoBench.pump(0.35)
            last = AdBlockVideoPiP.answer(from: (try? await web.evaluateJavaScript(AdBlockVideoPiP.check)) as? String ?? "")
            if last == .entered { break }
            if case .inline(let e) = last, !e.isEmpty { break }
        }
        _ = try? await web.evaluateJavaScript(leave)
        await AdBlockVideoBench.pump(1)
        switch last {
        case .entered: return "entrée (puis ressortie)"
        case .inline(let e): return "refusée par WebKit" + (e.isEmpty ? "" : " (\(e))")
        default: return "\(last)"
        }
    }
}
