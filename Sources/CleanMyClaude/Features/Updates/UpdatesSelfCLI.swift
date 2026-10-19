import Foundation

/// `CleanMyClaude --update-check [--as-version 0.2.0] [--as-commit <sha>]` asks GitHub exactly like the app does and
/// prints the answer. `--update-install "<…/Clean My Claude.app>"` also downloads the new version, checks it and puts it
/// in place of that copy (the old one goes to the Trash), without opening anything: the update tested end to end
/// on a throwaway copy, never on the running app.
enum UpdatesSelfCLI {
    static func run() async {
        guard !DemoData.isEnabled else {
            print(HTTP.Failure.demo.localizedDescription)
            return
        }
        var build = UpdatesSelfBuild.current
        var target: URL?
        if let path = Entry.value(after: "--update-install") {
            let url = URL(fileURLWithPath: FS.expand(path)).standardizedFileURL
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == UpdatesSelfInstaller.bundleID else {
                print("✗ \(url.path) n'est pas une copie de Clean My Claude.")
                return
            }
            target = url
            build = UpdatesSelfBuild(version: info["CFBundleShortVersionString"] as? String,
                                     commit: (info["CMCCommit"] as? String).flatMap { UpdatesSelfGitHub.isCommit($0) ? $0 : nil },
                                     bundlePath: url.path)
        }
        if let v = Entry.value(after: "--as-version") {
            build.version = v
            build.commit = nil
        }
        if let c = Entry.value(after: "--as-commit") { build.commit = c }
        print("Copie comparée : \(build.label) · \(FS.pretty(build.bundlePath))")

        let result: (latest: UpdatesSelfRelease, isUpdate: Bool)
        do {
            result = try await UpdatesSelfGitHub.check(build)
        } catch {
            print("✗ \(UpdatesSelfGitHub.message(for: error))")
            return
        }
        let r = result.latest
        print("Dernière version publiée : \(r.version) (\(r.tag))" + (r.published.map { ", le \(Fmt.day($0))" } ?? ""))
        print("  Archive : \(r.downloadURL ?? "aucune") · \(Fmt.bytes(r.size)) · \(r.digest ?? "pas d'empreinte") · signature \(r.signatureURL == nil ? "absente" : "publiée")")
        guard result.isUpdate else {
            print("→ À jour : rien à installer.")
            return
        }
        print("→ Mise à jour disponible, \(Fmt.plural(r.changeCount, "changement", "changements")) :")
        for c in r.changes {
            print("  • \(c.title.topic.map { "[\($0)] " } ?? "")\(c.title.text)")
            for d in c.details { print("      - \(d.topic.map { "\($0) : " } ?? "")\(d.text)") }
        }
        if r.moreChanges > 0 { print("  … et \(r.moreChanges) de plus sur GitHub") }
        guard let target else { return }

        let readOnly = (try? target.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        let fm = FileManager.default
        if let blocker = UpdatesSelfInstaller.blocker(bundlePath: target.path, readOnly: readOnly,
                                                      writable: fm.isWritableFile(atPath: target.deletingLastPathComponent().path)
                                                          && fm.isWritableFile(atPath: target.path)) {
            print("✗ \(blocker)")
            return
        }
        guard let link = r.downloadURL else {
            print("✗ Cette version n'a pas d'archive à installer.")
            return
        }
        guard UpdatesSelfGitHub.isTrustedDownload(link), let url = URL(string: link) else {
            print("✗ \(UpdatesSelfInstaller.Failure.untrusted.localizedDescription)")
            return
        }
        guard r.digest != nil else {
            print("✗ \(UpdatesSelfInstaller.Failure.noDigest.localizedDescription)")
            return
        }
        guard let base = DataStore.ensureFolder(UpdatesSelfInstaller.folderName),
              let folder = try? FileOps.makeDirectory(base.appendingPathComponent("\(r.version) (essai)")) else {
            print("✗ Impossible de préparer le dossier de téléchargement.")
            return
        }
        defer { Remover.removeInternal(folder.path) }
        do {
            print("→ Téléchargement de \(link)")
            let zip = try await HTTP.download(url, into: folder, name: UpdatesSelfGitHub.assetName) { received, expected in
                print("   \(Fmt.bytes(received)) sur \(Fmt.bytes(expected))")
            }
            let signature = try await UpdatesSelfSignature.fetch(for: r)
            print("→ Vérification : empreinte comparée à celle de GitHub, "
                  + (UpdatesSelfSignature.publicKey == nil ? "signature Ed25519 pas encore exigée" : "signature Ed25519 vérifiée") + ", contenu, signature de l'app")
            let prepared = try UpdatesSelfInstaller.prepare(zip: zip, folder: folder, release: r, signature: signature, currentBundle: target.path,
                                                            isCancelled: { false })
            print("  " + (prepared.signedLocally ? "Re-signée avec le certificat local de la copie remplacée" : "Signature publiée gardée (ad hoc)"))
            print("→ Remplacement : l'ancienne copie part à la Corbeille")
            let installed = try UpdatesSelfInstaller.replace(target, with: prepared.app)
            let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
            print("✓ \(installed.path) est maintenant en version \(info?["CFBundleShortVersionString"] as? String ?? "?")")
        } catch {
            print("✗ \(UpdatesSelfGitHub.message(for: error))")
        }
    }
}
