import Foundation
import AVFoundation

/// `--selftest`: pure checks (names, matrix, page ranges, rename patterns, presets, Markdown, QR round trip). Writes nothing.
extension ConverterModel {
    func selfTest() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ what: @autoclosure () -> String) {
            if !condition { failures.append(what()) }
        }

        // Kinds
        let kinds: [(String, Bool, ConverterKind)] = [
            ("IMG_1.HEIC", false, .image), ("a.jpeg", false, .image), ("b.webp", false, .image), ("c.mov", false, .video),
            ("d.MP4", false, .video), ("e.mkv", false, .video), ("f.m4a", false, .audio), ("g.flac", false, .audio),
            ("h.ogg", false, .audio), ("i.pdf", false, .pdf), ("j.md", false, .markdown), ("k.docx", false, .document),
            ("l.rtfd", true, .document), ("m.zip", false, .archive), ("n.tar.gz", false, .archive), ("Photos", true, .folder),
            ("o.xyz123", false, .other)
        ]
        for (name, dir, kind) in kinds {
            let got = ConverterKind.detect(name: name, isDirectory: dir)
            expect(got == kind, "Type de « \(name) » : \(got.rawValue) au lieu de \(kind.rawValue)")
        }

        // Operation matrix
        let images = ConverterOperation.available(for: [.image, .image])
        expect(images.contains(.imageConvert) && images.contains(.imagesToPDF) && images.contains(.ocr), "Opérations des images incomplètes")
        expect(!images.contains(.pdfMerge) && !images.contains(.videoCompress), "Opérations des images en trop")
        expect(!ConverterOperation.available(for: [.pdf]).contains(.pdfMerge), "Fusion proposée pour un seul PDF")
        expect(ConverterOperation.available(for: [.pdf, .pdf]).contains(.pdfMerge), "Fusion absente pour deux PDF")
        let folder = ConverterOperation.available(for: [.folder])
        expect(Set(folder) == [.archiveZip, .rename], "Opérations d'un dossier : \(folder.map(\.rawValue))")
        expect(ConverterOperation.available(for: [.markdown]).contains(.documentConvert), "Markdown sans conversion")
        expect(!ConverterOperation.available(for: [.image]).contains(.qrGenerate), "La création de QR ne dépend pas des fichiers")
        expect(ConverterOperation.suggested(for: [.video, .image, .video]) == .videoCompress, "Suggestion vidéo")
        expect(ConverterOperation.suggested(for: [.pdf, .pdf]) == .pdfMerge, "Suggestion fusion")
        expect(ConverterOperation.suggested(for: []) == nil, "Suggestion sans fichier")
        for op in ConverterOperation.allCases {
            expect(!op.title.isEmpty && !op.explanation.isEmpty && !op.actionTitle.isEmpty, "Textes manquants : \(op.rawValue)")
            expect(op == .qrGenerate || !op.accepts.isEmpty, "\(op.rawValue) n'accepte aucun fichier")
            expect(!ConverterModel.summary(op, ConverterOptions()).isEmpty, "Résumé vide : \(op.rawValue)")
            expect(op.commandID.hasPrefix("conv_") && AppCommand.isValidID(op.commandID), "Identifiant invalide : \(op.commandID)")
        }
        expect(Set(ConverterOperation.allCases.map(\.commandID)).count == ConverterOperation.allCases.count, "Identifiants en double")

        // Output names (FileOps never overwrites; these folders do not exist)
        let photo = URL(fileURLWithPath: "/nonexistent-cmc/Vacances/IMG_4102.HEIC")
        expect(FileOps.outputURL(for: photo, extension: "jpg").lastPathComponent == "IMG_4102.jpg", "Nom de sortie simple")
        expect(FileOps.outputURL(for: photo, extension: "jpg", suffix: "2048 px").lastPathComponent == "IMG_4102 2048 px.jpg", "Nom avec suffixe")
        expect(FileOps.outputURL(for: photo, extension: "pdf", folder: URL(fileURLWithPath: "/nonexistent-cmc/Sortie")).path
               == "/nonexistent-cmc/Sortie/IMG_4102.pdf", "Nom dans un dossier choisi")
        expect(ConverterArchiveEngine.baseName("photos.tar.gz") == "photos", "Nom de base d'un .tar.gz")
        expect(ConverterArchiveEngine.baseName("rapport.zip") == "rapport", "Nom de base d'un .zip")
        let parent = ConverterArchiveEngine.commonParent([URL(fileURLWithPath: "/a/b/c/x.txt"), URL(fileURLWithPath: "/a/b/d/y.txt")])
        expect(parent.path == "/a/b", "Dossier commun : \(parent.path)")

        // Page ranges
        expect(ConverterPDFEngine.parsePages("1-3, 5, 8-", count: 10) == [0, 1, 2, 4, 7, 8, 9], "Pages « 1-3, 5, 8- »")
        expect(ConverterPDFEngine.parsePages("", count: 3) == [0, 1, 2], "Pages vides = toutes")
        expect(ConverterPDFEngine.parsePages("3–1", count: 5) == nil, "Plage à l'envers acceptée")
        expect(ConverterPDFEngine.parsePages("0", count: 5) == nil, "Page 0 acceptée")
        expect(ConverterPDFEngine.parsePages("12", count: 5) == nil, "Page hors du PDF acceptée")
        expect(ConverterPDFEngine.parsePages("deux", count: 5) == nil, "Texte accepté comme page")
        expect(ConverterPDFEngine.parsePages("2 à 4; 2", count: 5) == [1, 2, 3], "Pages « 2 à 4; 2 »")
        expect(ConverterPDFEngine.describePages([0, 1, 2, 4, 7, 8]) == "1-3, 5, 8-9", "Description des pages")

        // Batch renaming
        var rule = ConverterRenameRule(pattern: "Vacances {n:3}", start: 1)
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 7, day: 14, hour: 9, minute: 5, second: 3).date
        func name(_ n: String, _ i: Int = 0, dir: Bool = false) -> String {
            ConverterRename.newName(name: n, isDirectory: dir, folderName: "Été", index: i, date: date, rule: rule)
        }
        expect(name("IMG_1.JPG", 4) == "Vacances 005.JPG", "Motif numéroté : \(name("IMG_1.JPG", 4))")
        rule.lowercaseExtension = true
        expect(name("IMG_1.JPG") == "Vacances 001.jpg", "Extension en minuscules")
        rule = ConverterRenameRule(pattern: "{date} {heure} {nom} ({dossier})")
        expect(name("photo.png") == "2026-07-14 09-05-03 photo (Été).png", "Date et heure : \(name("photo.png"))")
        rule = ConverterRenameRule(pattern: "{nom}", find: "img_", replace: "Plage ", caseMode: .unchanged)
        expect(name("IMG_42.heic") == "Plage 42.heic", "Rechercher et remplacer : \(name("IMG_42.heic"))")
        rule = ConverterRenameRule(pattern: "{nom}", caseMode: .upper)
        expect(name("été.txt") == "ÉTÉ.txt", "Majuscules")
        rule = ConverterRenameRule(pattern: "{nom}", caseMode: .capitalized)
        expect(name("MON FICHIER.txt") == "Mon fichier.txt", "Première lettre")
        rule = ConverterRenameRule(pattern: "a/b:c {inconnu}")
        expect(name("x.txt") == "a-b-c {inconnu}.txt", "Caractères interdits : \(name("x.txt"))")
        rule = ConverterRenameRule(pattern: "   ")
        expect(name("x.txt") == "Sans titre.txt", "Nom vide")
        rule = ConverterRenameRule(pattern: "{nom} v2")
        expect(name("Projet.final", dir: true) == "Projet.final v2", "Dossier avec un point")
        let batch = ["a.jpg", "b.jpg"].map { ConverterFile(url: URL(fileURLWithPath: "/nonexistent-cmc/\($0)"), kind: .image) }
        let preview = ConverterRename.preview(batch, rule: ConverterRenameRule(pattern: "photo"))
        expect(preview.count == 2 && !preview[0].conflict && preview[1].conflict, "Doublon de nom non signalé")

        // Video presets: all known to this macOS, and never the macOS 26 one.
        let presets = Set(AVAssetExportSession.allExportPresets())
        for p in ConverterVideoPreset.allCases {
            expect(presets.contains(p.rawValue), "Préréglage inconnu : \(p.rawValue)")
            expect(!p.rawValue.contains("4320"), "Préréglage réservé à macOS 26 : \(p.rawValue)")
        }

        // Formats
        let writable = ConverterImageEngine.formats(webp: false).map(\.uti)
        expect(writable.contains("public.jpeg") && writable.contains("public.png"), "ImageIO n'écrit ni JPEG ni PNG ?")
        expect(!writable.contains("org.webmproject.webp") || ConverterImageEngine.writable.contains("org.webmproject.webp"), "WebP sans ffmpeg")
        expect(ConverterImageFormat.matching(uti: "public.heif") == .heic, "HEIF → HEIC")
        expect(!ConverterAudioFormat.available(ffmpeg: false).contains(.mp3), "MP3 proposé sans ffmpeg")
        expect(ConverterAudioFormat.available(ffmpeg: true).contains(.mp3), "MP3 absent avec ffmpeg")
        let encoders = ConverterMediaEngine.ffmpegEncodersParse(" V....D libx264              libx264 H.264\n A....D libmp3lame   MP3\n ------\n")
        expect(encoders == ["libx264", "libmp3lame"], "Lecture des encodeurs ffmpeg : \(encoders)")
        expect(ConverterMediaEngine.clock(134) == "2:14" && ConverterMediaEngine.clock(3725) == "1:02:05", "Durées")

        // Markdown
        let blocks = ConverterMarkdown.parse("# Titre\n\nDu **gras**, de l'*italique* et `du code`.\n\n- un\n- deux\n\n1. premier\n\n> cité\n\n```\nlet x = 1\n```\n\n[lien](https://exemple.fr)")
        let html = ConverterMarkdown.body(blocks)
        for piece in ["<h1>Titre</h1>", "<strong>gras</strong>", "<em>italique</em>", "<code>du code</code>", "<ul>", "<li>un</li>",
                      "<ol>", "<blockquote>", "<pre><code>let x = 1</code></pre>", "<a href=\"https://exemple.fr\">lien</a>"] {
            expect(html.contains(piece), "Markdown → HTML sans \(piece)")
        }
        expect(ConverterMarkdown.escape("<a & \"b\">") == "&lt;a &amp; &quot;b&quot;&gt;", "Échappement HTML")
        expect(ConverterMarkdown.attributed(blocks).string.contains("•\tun"), "Puces du Markdown → PDF")

        // Launcher
        let app = AppModel(liveMonitor: false)
        expect(results(for: "qr bonjour", app: app).count == 1, "« qr bonjour » ne propose pas de QR code")
        expect(results(for: "qr", app: app).isEmpty && results(for: "quitter", app: app).isEmpty, "QR proposé à tort")
        expect(commands(app: app).count == ConverterOperation.allCases.count, "Commandes du lanceur")

        // QR round trip, in memory: drawn by Core Image, read back by Vision.
        if let qr = ConverterVision.qrImage("Clean My Claude 🧹") {
            let read = (try? ConverterVision.barcodes(qr)) ?? []
            expect(read.contains("Clean My Claude 🧹"), "QR code illisible après création : \(read)")
        } else {
            failures.append("QR code non créé")
        }
        expect(ConverterVision.qrImage("") == nil, "QR code d'un texte vide")
        return failures
    }
}
