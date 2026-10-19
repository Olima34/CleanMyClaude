import Foundation
import CryptoKit

// Clean My Claude's own updates: the latest version published on GitHub (a `vX.Y.Z` tag with CleanMyClaude.zip, published
// by .github/workflows/build.yml after every green push on main, numbered by scripts/version.sh like a local build of the
// same commit), what changed since this copy (the commits in between), and the replacement of this copy by the new one.

/// This copy of Clean My Claude: the version and the commit that scripts/build_app.sh wrote in its Info.plist.
struct UpdatesSelfBuild: Equatable {
    /// nil when the app is not assembled (`swift run`, `.build/debug`): nothing to compare nor to replace.
    var version: String?
    var commit: String?
    var bundlePath: String

    var isBundle: Bool { bundlePath.hasSuffix(".app") }
    var shortCommit: String? { commit.map { String($0.prefix(7)) } }

    var label: String {
        guard let version else { return "version de développement" }
        return shortCommit.map { "\(version) (\($0))" } ?? version
    }

    static var current: UpdatesSelfBuild {
        if DemoData.isEnabled {
            return UpdatesSelfBuild(version: "0.3.0", commit: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678",
                                    bundlePath: "/Applications/Clean My Claude.app")
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let path = Bundle.main.bundlePath
        let commit = (info["CMCCommit"] as? String).flatMap { UpdatesSelfGitHub.isCommit($0) ? $0.lowercased() : nil }
        return UpdatesSelfBuild(version: path.hasSuffix(".app") ? info["CFBundleShortVersionString"] as? String : nil,
                                commit: commit, bundlePath: path)
    }
}

/// One line of "Ce qui change": a topic when the text starts with one ("Lanceur : …"), and the text.
struct UpdatesSelfLine: Codable, Equatable, Hashable {
    var topic: String?
    var text: String
}

/// One change brought by the new version: a commit's title and the points listed in its message.
struct UpdatesSelfChange: Codable, Equatable, Identifiable {
    var id: String
    var title: UpdatesSelfLine
    var details: [UpdatesSelfLine] = []
    var date: Date?
}

/// The latest version published on GitHub.
struct UpdatesSelfRelease: Codable, Equatable {
    var version: String
    var tag: String
    var title: String
    var pageURL: String
    var published: Date?
    /// The archive to install (nil: none attached yet).
    var downloadURL: String?
    var size: Int64 = 0
    /// "sha256:…", computed by GitHub when the archive was published. Without it nothing is installed.
    var digest: String?
    /// CleanMyClaude.zip.sig: the base64 of an Ed25519 signature of the archive (`UpdatesSelfSignature`), when published.
    var signatureURL: String?
    /// Most recent first, merges left out.
    var changes: [UpdatesSelfChange] = []
    /// Changes left out of `changes` (it keeps the most recent ones).
    var moreChanges = 0

    var changeCount: Int { changes.count + moreChanges }
}

/// What GitHub says between two points of the history.
struct UpdatesSelfCompare: Equatable {
    /// "ahead", "behind", "identical" or "diverged" (head compared to base).
    var status: String
    var aheadBy: Int
    /// Most recent first, merges left out.
    var changes: [UpdatesSelfChange]
    /// Every change, merges left out, including those beyond the 250 commits GitHub lists.
    var total: Int
}

enum UpdatesSelfGitHub {
    static let repo = "Olima34/CleanMyClaude"
    static let assetName = "CleanMyClaude.zip"
    static let signatureAssetName = "CleanMyClaude.zip.sig"
    static let releasesPage = "https://github.com/\(repo)/releases/latest"
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/\(repo)/main/scripts/install.sh | bash"
    static let maxChanges = 40

    enum Failure: LocalizedError {
        case unreadable, noRelease

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Réponse de GitHub illisible."
            case .noRelease: return "Aucune version n'est encore publiée sur GitHub."
            }
        }
    }

    static func isCommit(_ s: String) -> Bool {
        (7...40).contains(s.count) && s.allSatisfy(\.isHexDigit)
    }

    /// "v0.3.1" → "0.3.1".
    static func version(fromTag tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = t.first, f == "v" || f == "V", t.dropFirst().first?.isNumber == true { t.removeFirst() }
        return t
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        UpdatesVersion.compare(version(fromTag: candidate), version(fromTag: installed)) == .orderedDescending
    }

    /// Whether `release` brings something to `build`. `compare` goes from the build to the release;
    /// `fromCommit`: it started at the build's own commit (not at its version's tag).
    static func isUpdate(_ release: UpdatesSelfRelease, for build: UpdatesSelfBuild,
                         compare: UpdatesSelfCompare?, fromCommit: Bool) -> Bool {
        guard let installed = build.version, isNewer(release.version, than: installed) else { return false }
        // Built from a later commit than the release (a local build whose number was not raised): nothing new for it.
        if fromCommit, let compare, compare.aheadBy == 0 { return false }
        return true
    }

    // MARK: Reading GitHub's answers

    private struct ReleaseJSON: Decodable {
        struct Asset: Decodable {
            var name: String
            var size: Int64
            var browser_download_url: String
            var digest: String?
            var state: String?
        }
        var tag_name: String
        var name: String?
        var html_url: String
        var published_at: Date?
        var draft: Bool?
        var prerelease: Bool?
        var assets: [Asset]
    }

    private struct CompareJSON: Decodable {
        struct Commit: Decodable {
            struct Inner: Decodable {
                struct Who: Decodable { var date: Date? }
                var message: String
                var author: Who?
                var committer: Who?
            }
            struct Parent: Decodable { var sha: String }
            var sha: String
            var commit: Inner
            var parents: [Parent]
        }
        var status: String
        var ahead_by: Int
        var total_commits: Int?
        var commits: [Commit]
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The answer of /releases/latest. Drafts, pre-releases and tags that are not version numbers are refused.
    static func parseRelease(_ data: Data) -> UpdatesSelfRelease? {
        guard let r = try? decoder.decode(ReleaseJSON.self, from: data), r.draft != true, r.prerelease != true else { return nil }
        let version = version(fromTag: r.tag_name)
        guard version.first?.isNumber == true, let page = URL(string: r.html_url), page.scheme == "https" else { return nil }
        let complete = r.assets.filter { ($0.state ?? "uploaded") == "uploaded" }
        let zip = complete.first { $0.name == assetName } ?? complete.first { $0.name.lowercased().hasSuffix(".zip") }
        // Only an archive that GitHub itself serves over HTTPS, from this repository.
        let download = zip.map(\.browser_download_url).flatMap { isTrustedDownload($0) ? $0 : nil }
        let digest = zip?.digest.map { $0.lowercased() }.flatMap { d -> String? in
            guard d.hasPrefix("sha256:"), d.dropFirst(7).count == 64, d.dropFirst(7).allSatisfy(\.isHexDigit) else { return nil }
            return d
        }
        let signature = complete.first { $0.name == signatureAssetName }.map(\.browser_download_url).flatMap { isTrustedDownload($0) ? $0 : nil }
        return UpdatesSelfRelease(version: version, tag: r.tag_name, title: r.name?.isEmpty == false ? r.name! : "Clean My Claude \(version)",
                                  pageURL: page.absoluteString, published: r.published_at,
                                  downloadURL: download, size: download == nil ? 0 : zip?.size ?? 0, digest: download == nil ? nil : digest,
                                  signatureURL: download == nil ? nil : signature)
    }

    /// A file of this repository's releases, served by GitHub over HTTPS: github.com/<repo>/releases/download/…
    /// (or the API's address of an asset). Checked when GitHub answers and again just before downloading:
    /// selfupdate.json, where the answer is kept, can be rewritten by any program of the user.
    static func isTrustedDownload(_ link: String) -> Bool {
        guard let url = URL(string: link), url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return false }
        let path = url.path.lowercased()
        let ownRepo = repo.lowercased()
        guard !path.contains("/../"), !path.hasSuffix("/..") else { return false }
        if host == "github.com" { return path.hasPrefix("/\(ownRepo)/releases/download/") }
        if host.hasSuffix(".github.com") { return path.hasPrefix("/repos/\(ownRepo)/releases/assets/") }
        return false
    }

    /// The answer of /compare/base...head.
    static func parseCompare(_ data: Data) -> UpdatesSelfCompare? {
        guard let c = try? decoder.decode(CompareJSON.self, from: data) else { return nil }
        let listed = c.commits.map { (sha: $0.sha, merge: $0.parents.count > 1, change: change(sha: $0.sha, message: $0.commit.message, parents: $0.parents.count,
                                                                                              date: $0.commit.committer?.date ?? $0.commit.author?.date)) }
        let changes = listed.compactMap(\.change)
        // Beyond the 250 commits listed, the merges cannot be told apart: they count as changes.
        let unlisted = max(0, (c.total_commits ?? c.commits.count) - c.commits.count)
        return UpdatesSelfCompare(status: c.status, aheadBy: c.ahead_by, changes: changes.reversed(), total: changes.count + unlisted)
    }

    /// A commit as a change: its first line is the title, its "- " lines the details. Merges and empty messages are left out,
    /// and so are the other lines (explanations, Co-Authored-By).
    static func change(sha: String, message: String, parents: Int, date: Date?) -> UpdatesSelfChange? {
        guard parents <= 1 else { return nil }
        let lines = message.components(separatedBy: .newlines)
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty,
              !first.hasPrefix("Merge "), !first.hasPrefix("Fusion ") else { return nil }
        var details: [UpdatesSelfLine] = []
        for raw in lines.dropFirst() {
            let l = raw.trimmingCharacters(in: .whitespaces)
            guard let mark = ["- ", "* ", "• "].first(where: { l.hasPrefix($0) }) else { continue }
            let text = l.dropFirst(mark.count).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { details.append(line(text, title: false)) }
        }
        return UpdatesSelfChange(id: sha, title: line(first), details: Array(details.prefix(16)), date: date)
    }

    /// "Lanceur : glisser un fichier" → topic "Lanceur", text "Glisser un fichier". A topic is short (five words at most)
    /// and is no sentence (no ";", brackets or ". "); a file name works ("build_app.sh : …"). Otherwise the whole text stays
    /// as it is. In a detail (`title` false), the text after a topic keeps its lower case: "Presse-papiers : le réglage…".
    static func line(_ raw: String, title: Bool = true) -> UpdatesSelfLine {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let colon = text.firstIndex(of: ":"), text.index(after: colon) < text.endIndex, text[text.index(after: colon)] == " " {
            let topic = text[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !topic.isEmpty, topic.count <= 40, !rest.isEmpty, topic.split(separator: " ").count <= 5,
               !topic.contains(where: { ";()[]`".contains($0) }), !topic.contains(". "), !topic.hasSuffix(".") {
                return UpdatesSelfLine(topic: topic, text: title ? capitalized(rest) : rest)
            }
        }
        return UpdatesSelfLine(topic: nil, text: capitalized(text))
    }

    /// An upper-case first letter, except for a text that starts with a file name, a path or code ("build_app.sh", "--zip").
    private static func capitalized(_ text: String) -> String {
        let first = text.prefix { $0 != " " }
        return first.contains(where: { "/._-@`".contains($0) || $0.isNumber }) ? text : Fmt.cap(text)
    }

    // MARK: Asking GitHub

    private static let headers = ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]

    private static func api(_ path: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repo)/\(path)")
    }

    private static func ref(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._"))) ?? s
    }

    /// The latest published version and whether it brings something to `build`, with what changed since it
    /// (the commits between the build's own commit, or its version's tag, and the release's tag).
    /// One request when the build is up to date, two or three otherwise.
    static func check(_ build: UpdatesSelfBuild) async throws -> (latest: UpdatesSelfRelease, isUpdate: Bool) {
        guard let url = api("releases/latest") else { throw Failure.unreadable }
        let data: Data
        do {
            data = try await HTTP.get(url, headers: headers).0
        } catch HTTP.Failure.status(404) {
            throw Failure.noRelease
        }
        guard var release = parseRelease(data) else { throw Failure.unreadable }
        guard let installed = build.version, isNewer(release.version, than: installed) else { return (release, false) }
        var compare: UpdatesSelfCompare?
        var fromCommit = false
        for base in [build.commit, "v" + version(fromTag: installed)].compactMap({ $0 }) {
            // A commit that never reached GitHub (a local build) or a tag that does not exist: 404, next one.
            guard let url = api("compare/\(ref(base))...\(ref(release.tag))"),
                  let d = try? await HTTP.get(url, headers: headers).0, let c = parseCompare(d) else { continue }
            compare = c
            fromCommit = base == build.commit
            break
        }
        guard isUpdate(release, for: build, compare: compare, fromCommit: fromCommit) else { return (release, false) }
        if let compare {
            release.changes = Array(compare.changes.prefix(maxChanges))
            release.moreChanges = max(0, compare.total - release.changes.count)
        }
        return (release, true)
    }

    /// A message for the user, in French, for a failed check or download.
    static func message(for error: Error) -> String {
        if let f = error as? HTTP.Failure, case .status(let code) = f {
            if code == 403 || code == 429 { return "GitHub limite les vérifications sans compte (60 par heure) : réessaie un peu plus tard." }
            if code >= 500 { return "GitHub ne répond pas correctement pour le moment (code \(code)) : réessaie plus tard." }
        }
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .timedOut, .dataNotAllowed, .internationalRoamingOff:
                return "Impossible de joindre GitHub : vérifie ta connexion à Internet."
            case .cancelled:
                return "Téléchargement annulé."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .clientCertificateRejected:
                return "La connexion sécurisée à GitHub a échoué : rien n'a été téléchargé."
            default: break
            }
        }
        return error.localizedDescription
    }
}

/// Replacing this copy of the app by the downloaded one.
enum UpdatesSelfInstaller {
    static let bundleID = "io.github.olima34.cleanmyclaude"
    static let appName = "Clean My Claude.app"
    /// Inside the app's data folder: one sub-folder per download, removed once installed or abandoned.
    static let folderName = "Mise à jour"

    enum Failure: LocalizedError {
        case digest, noDigest, untrusted, unsigned, badSignature, unpack(String), invalid(String), signature(String), localSign(String),
             trash(String), move(String, String)

        var errorDescription: String? {
            switch self {
            case .digest:
                return "L'archive téléchargée ne correspond pas à celle publiée sur GitHub : je ne l'installe pas. Réessaie, ou télécharge-la depuis la page de la version."
            case .noDigest:
                return "GitHub ne donne pas l'empreinte de cette archive : sans elle, impossible de vérifier ce qui a été téléchargé. Rien n'a été installé."
            case .untrusted:
                return "L'adresse de l'archive ne mène pas aux versions de Clean My Claude sur GitHub : je ne la télécharge pas."
            case .unsigned:
                return "Cette version n'est pas accompagnée de sa signature (CleanMyClaude.zip.sig) : je ne l'installe pas."
            case .badSignature:
                return "La signature de l'archive ne correspond pas à la clé de Clean My Claude : je ne l'installe pas."
            case .unpack(let why):
                return "L'archive téléchargée ne s'ouvre pas\(why.isEmpty ? "" : " (\(why))") : rien n'a été installé."
            case .invalid(let why):
                return why + " Rien n'a été installé."
            case .signature(let why):
                return "La signature de l'app téléchargée est abîmée\(why.isEmpty ? "" : " (\(why))") : je ne l'installe pas."
            case .localSign(let why):
                return "Je n'ai pas pu signer la nouvelle version avec ton certificat local\(why.isEmpty ? "" : " (\(why))") : rien n'a été installé. Déverrouille ton trousseau puis réessaie, ou installe-la avec la commande du Terminal."
            case .trash(let why):
                return "Je n'ai pas pu mettre l'ancienne version à la Corbeille (\(why)) : rien n'a changé."
            case .move(let why, let folder):
                return "L'ancienne version est dans la Corbeille, mais la nouvelle n'a pas pu prendre sa place (\(why)). Remets l'ancienne depuis la Corbeille (clic droit › Remettre), ou glisse la nouvelle depuis « \(folder) »."
            }
        }
    }

    /// Why this copy cannot replace itself, or nil when it can.
    /// `readOnly`: on a disk image or a locked volume; `writable`: its folder and itself can be changed without a password.
    static func blocker(bundlePath: String, readOnly: Bool, writable: Bool) -> String? {
        guard bundlePath.hasSuffix(".app") else {
            return "Tu lances Clean My Claude depuis le code source : mets-le à jour avec git pull, puis ./scripts/build_app.sh."
        }
        if bundlePath.contains("/AppTranslocation/") {
            return "macOS fait tourner l'app depuis un emplacement provisoire en lecture seule. Glisse-la dans ton dossier Applications, rouvre-la, puis réessaie."
        }
        if readOnly {
            return "L'app tourne depuis une image disque ou un volume en lecture seule. Copie-la dans ton dossier Applications, rouvre-la, puis réessaie."
        }
        guard writable else {
            let folder = FS.pretty((bundlePath as NSString).deletingLastPathComponent)
            return "Le dossier « \(folder) » ne se modifie qu'avec un mot de passe administrateur : je ne peux pas y remplacer l'app moi-même. Lance la commande d'installation dans le Terminal, ou télécharge la version depuis GitHub."
        }
        return nil
    }

    static func currentBlocker() -> String? {
        let path = Bundle.main.bundlePath
        let url = URL(fileURLWithPath: path)
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        let fm = FileManager.default
        return blocker(bundlePath: path, readOnly: readOnly,
                       writable: fm.isWritableFile(atPath: url.deletingLastPathComponent().path) && fm.isWritableFile(atPath: path))
    }

    /// SHA-256 of a file, read by chunks.
    static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// What the unpacked app must be: Clean My Claude, the version announced, and a macOS this Mac has.
    static func validate(info: [String: Any], expectedVersion: String, macOS: String) -> String? {
        guard info["CFBundleIdentifier"] as? String == bundleID else { return "L'archive ne contient pas Clean My Claude." }
        guard let v = info["CFBundleShortVersionString"] as? String,
              UpdatesVersion.compare(v, UpdatesSelfGitHub.version(fromTag: expectedVersion)) == .orderedSame else {
            return "L'archive annonce une autre version que celle publiée."
        }
        if let min = info["LSMinimumSystemVersion"] as? String, UpdatesVersion.compare(macOS, min) == .orderedAscending {
            return "Cette version demande macOS \(min) ou plus récent."
        }
        return nil
    }

    /// "designated => identifier "…" and certificate leaf = H"fd51…"" → "FD51…": the certificate of a local identity.
    /// nil for an ad hoc signature or a developer certificate from Apple.
    static func leafHash(fromRequirement text: String) -> String? {
        let prefix = "certificate leaf = H\""
        guard let r = text.range(of: prefix + "[0-9A-Fa-f]{40}\"", options: .regularExpression) else { return nil }
        return String(text[r].dropFirst(prefix.count).dropLast()).uppercased()
    }

    /// The identity that signed `bundle` when it is a local certificate this Mac still has ("Clean My Claude Dev",
    /// made by scripts/setup_signing.sh): signed the same way, the update keeps the permissions macOS gave the app.
    static func localSigningIdentity(of bundle: String) -> String? {
        guard let leaf = leafHash(fromRequirement: Shell.run("/usr/bin/codesign", ["-d", "-r-", bundle]).all) else { return nil }
        let identities = Shell.run("/usr/bin/security", ["find-identity", "-p", "codesigning"]).out.uppercased()
        return identities.contains(leaf) ? leaf : nil
    }

    /// Checks the downloaded archive, unpacks it next to itself and checks the app inside. Runs tools: not on the main thread.
    /// Returns the app, ready to take the place of `currentBundle`, and whether it was signed with the local identity.
    /// `signature`: the archive's Ed25519 signature (`UpdatesSelfSignature.fetch`), required once the public key is set.
    static func prepare(zip: URL, folder: URL, release: UpdatesSelfRelease, signature: Data?, currentBundle: String,
                        isCancelled: () -> Bool) throws -> (app: URL, signedLocally: Bool) {
        // The fingerprint GitHub computed when the archive was published: never optional.
        guard let expected = release.digest else { throw Failure.noDigest }
        guard sha256(of: zip) == expected else { throw Failure.digest }
        try UpdatesSelfSignature.check(zip: zip, signature: signature)
        if isCancelled() { throw CancellationError() }
        let out = try FileOps.makeDirectory(folder.appendingPathComponent("app", isDirectory: true))
        let unzip = Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path], timeout: 180)
        guard unzip.ok else { throw Failure.unpack(unzip.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let app = out.appendingPathComponent(appName)
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw Failure.invalid("L'archive ne contient pas Clean My Claude.")
        }
        if let problem = validate(info: info, expectedVersion: release.version, macOS: UpdatesVersion.macOS) { throw Failure.invalid(problem) }
        let executable = app.appendingPathComponent("Contents/MacOS").appendingPathComponent(info["CFBundleExecutable"] as? String ?? "?")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.invalid("L'app de l'archive est incomplète.") }
        if isCancelled() { throw CancellationError() }
        // Downloaded by the app itself, the archive carries no quarantine; this only matters if it did (like scripts/install.sh).
        _ = Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path], timeout: 60)
        let intact = Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 120)
        guard intact.ok else { throw Failure.signature(intact.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
        // The published app is signed ad hoc: re-signed with the local identity of this copy, if any, macOS keeps its permissions.
        var signedLocally = false
        if let identity = localSigningIdentity(of: currentBundle) {
            // The hardened runtime and the entitlements of the published app are kept.
            let sign = Shell.run("/usr/bin/codesign", ["--force", "--deep", "--preserve-metadata=entitlements,flags,runtime",
                                                       "--sign", identity, app.path], timeout: 120)
            signedLocally = sign.ok && Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 120).ok
            // A half-signed app is never installed.
            if !signedLocally { throw Failure.localSign(sign.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return (app, signedLocally)
    }

    /// Puts the running app in the Trash and the new one at its place. Not on the main thread (the Trash may go through the Finder).
    static func replace(_ current: URL, with staged: URL) throws -> URL {
        let report = Remover.remove([RemovalEntry(path: current.path, size: FileSizer.size(of: current.path))], mode: .trash)
        guard report.removed == 1, !FileManager.default.fileExists(atPath: current.path) else {
            throw Failure.trash(report.failures.first?.reason ?? "élément introuvable")
        }
        let installed: URL
        do {
            installed = try FileOps.move(staged, to: current)
        } catch {
            throw Failure.move(error.localizedDescription, FS.pretty(staged.deletingLastPathComponent().path))
        }
        // The Finder service and the cleanmyclaude:// links of the new version, right away (like build_app.sh).
        _ = Shell.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                      ["-f", installed.path], timeout: 30)
        return installed
    }

    /// Opens `app` once this process has quit (a small shell script outlives it). False if it could not start.
    static func relaunch(_ app: URL) -> Bool {
        let script = "pid=$1; i=0; while kill -0 \"$pid\" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done; /usr/bin/open \"$2\""
        return Shell.launchDetached("/bin/sh", ["-c", script, "sh", "\(getpid())", app.path])
    }
}

/// Ed25519 signature of the published archives, in preparation: the CI will publish CleanMyClaude.zip.sig (the base64
/// of a signature of CleanMyClaude.zip by a private key kept out of the repository) next to the archive. While
/// `publicKey` is nil nothing is checked; once it is set, an archive without a valid signature is never installed.
/// GitHub's SHA-256 only proves the archive is the one published; the signature proves who published it.
enum UpdatesSelfSignature {
    /// Base64 of the raw 32-byte Ed25519 public key (`Curve25519.Signing.PublicKey.rawRepresentation`). Not set yet.
    static let publicKey: String? = nil

    /// The signature published with `release`, or nil while no public key is set (nothing is downloaded then).
    static func fetch(for release: UpdatesSelfRelease, publicKey: String? = publicKey) async throws -> Data? {
        guard publicKey != nil else { return nil }
        guard let link = release.signatureURL else { throw UpdatesSelfInstaller.Failure.unsigned }
        guard UpdatesSelfGitHub.isTrustedDownload(link), let url = URL(string: link) else { throw UpdatesSelfInstaller.Failure.untrusted }
        let text = String(decoding: try await HTTP.get(url).0.prefix(1024), as: UTF8.self)
        guard let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), signature.count == 64 else {
            throw UpdatesSelfInstaller.Failure.badSignature
        }
        return signature
    }

    static func isValid(_ signature: Data, of archive: Data, publicKey: String) -> Bool {
        guard let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: archive)
    }

    /// Nothing while no public key is set; afterwards a missing or wrong signature stops the installation.
    static func check(zip: URL, signature: Data?, publicKey: String? = publicKey) throws {
        guard let publicKey else { return }
        guard let signature else { throw UpdatesSelfInstaller.Failure.unsigned }
        guard let archive = try? Data(contentsOf: zip, options: .mappedIfSafe), isValid(signature, of: archive, publicKey: publicKey) else {
            throw UpdatesSelfInstaller.Failure.badSignature
        }
    }

    /// With a key pair made for the test: a good signature passes; a changed archive, another key or no signature do not;
    /// without a public key, nothing is required.
    static func selfTest() -> [String] {
        var f: [String] = []
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let archive = Data("PK archive de Clean My Claude".utf8)
        guard let signature = try? key.signature(for: archive) else { return ["Signature Ed25519 : impossible de signer"] }
        if !isValid(signature, of: archive, publicKey: publicKey) { f.append("Signature Ed25519 valide refusée") }
        if isValid(signature, of: archive + Data([0]), publicKey: publicKey) { f.append("Archive modifiée acceptée par la signature") }
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        if isValid(signature, of: archive, publicKey: other) { f.append("Signature acceptée avec une autre clé") }
        if isValid(Data(repeating: 0, count: 64), of: archive, publicKey: publicKey) || isValid(signature, of: archive, publicKey: "pas une clé") {
            f.append("Signature vide ou clé illisible acceptée")
        }
        // The installation check reads a file: not in demo mode.
        guard !DemoData.isEnabled else { return f }
        let zip = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cleanmyclaude-signature-\(getpid()).zip")
        guard (try? archive.write(to: zip)) != nil else { return f + ["Signature Ed25519 : archive d'essai impossible à écrire"] }
        defer { try? FileManager.default.removeItem(at: zip) }
        if (try? check(zip: zip, signature: signature, publicKey: publicKey)) == nil { f.append("Archive signée refusée à l'installation") }
        if (try? check(zip: zip, signature: nil, publicKey: publicKey)) != nil { f.append("Archive sans signature acceptée alors que la clé est fixée") }
        if (try? check(zip: zip, signature: Data(repeating: 1, count: 64), publicKey: publicKey)) != nil { f.append("Archive mal signée acceptée") }
        if (try? check(zip: zip, signature: nil, publicKey: nil)) == nil { f.append("Signature exigée alors qu'aucune clé n'est fixée") }
        return f
    }
}
