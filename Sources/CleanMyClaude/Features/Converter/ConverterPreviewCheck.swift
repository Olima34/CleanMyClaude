import Foundation
import AppKit
import CoreGraphics

/// `--preview-check`: makes one small file of each kind in a temporary folder and runs the preview of every operation
/// on it, for real (what the preview shows is what the conversion makes). Nothing outside that folder is touched.
enum ConverterPreviewCheck {
    static func run() async -> [String] {
        guard let tmp = FS.userTempDir else { return ["✗ pas de dossier temporaire"] }
        let dir = URL(fileURLWithPath: tmp).appendingPathComponent("CleanMyClaude-banc-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var lines: [String] = []

        // Sample files.
        let png = dir.appendingPathComponent("photo.png")
        let text = dir.appendingPathComponent("note.txt")
        let md = dir.appendingPathComponent("lisez-moi.md")
        let pdf = dir.appendingPathComponent("rapport.pdf")
        let ocrImage = dir.appendingPathComponent("texte.png")
        let audio = dir.appendingPathComponent("voix.aiff")
        let video = dir.appendingPathComponent("film.mp4")
        let zip = dir.appendingPathComponent("archive.zip")
        writePNG(png, text: nil)
        writePNG(ocrImage, text: "Bonjour Clean My Claude")
        try? "Bonjour,\nceci est une note de test.".write(to: text, atomically: true, encoding: .utf8)
        try? "# Titre\n\nUn paragraphe avec **du gras**.\n\n- un\n- deux\n".write(to: md, atomically: true, encoding: .utf8)
        writePDF(pdf, pages: 3)
        _ = Shell.run("/usr/bin/say", ["-o", audio.path, "Bonjour, ceci est un essai."], timeout: 30)
        if let ffmpeg = Shell.which("ffmpeg") {
            _ = Shell.run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc=duration=8:size=640x360:rate=25", "-pix_fmt", "yuv420p", video.path], timeout: 60)
        }
        _ = Shell.run("/usr/bin/zip", ["-j", "-q", zip.path, text.path, md.path], timeout: 30)

        var options = ConverterOptions()
        options.pdfPages = "1-2"
        let ffmpeg = Shell.which("ffmpeg")
        let cases: [(ConverterOperation, [URL], ConverterKind)] = [
            (.imageConvert, [png], .image), (.imageResize, [png], .image), (.imageCompress, [png], .image), (.imageStrip, [png], .image),
            (.imagesToPDF, [png, ocrImage], .image),
            (.pdfSplit, [pdf], .pdf), (.pdfRotate, [pdf], .pdf), (.pdfCompress, [pdf], .pdf), (.pdfToImages, [pdf], .pdf), (.pdfMerge, [pdf, pdf], .pdf),
            (.documentConvert, [text], .document), (.documentConvert, [md], .markdown),
            (.audioConvert, [audio], .audio),
            (.videoCompress, [video], .video), (.videoGIF, [video], .video), (.videoAudio, [video], .video), (.videoContainer, [video], .video),
            (.archiveZip, [text, md], .document), (.archiveExtract, [zip], .archive),
            (.ocr, [ocrImage], .image), (.qrRead, [png], .image)
        ]
        for (op, inputs, kind) in cases {
            guard inputs.allSatisfy({ FS.exists($0.path) }) else {
                lines.append("– \(op.title) : fichier d'essai absent (outil manquant)")
                continue
            }
            let folder = dir.appendingPathComponent("apercu-\(op.rawValue)-\(UUID().uuidString.prefix(4))")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let spec = ConverterEngine.Spec(operation: op, inputs: inputs, kinds: inputs.map { _ in kind }, names: [],
                                            options: options, folder: nil, ffmpeg: ffmpeg)
            let t = Date()
            do {
                let r = try await ConverterPreviewer.make(spec, folder: folder, control: ConverterControl(report: { _ in }))
                let shown = ConverterPreviewFiles.expand(r.outputs)
                // Everything the preview made must sit in its own scratch folder.
                let outside = shown.filter { !$0.path.hasPrefix(folder.path) && !$0.path.hasPrefix(dir.path) }
                var what: String
                if let t = r.text { what = "texte « \(t.prefix(40)) »" }
                else if r.operation == .qrRead { what = "\(r.codes.count) code(s)" }
                else if let l = r.listing { what = "\(l.count) élément(s) listés" }
                else { what = "\(shown.count) fichier(s), \(Fmt.bytes(r.outputSize))" + (r.estimatedSize.map { ", ≈ \(Fmt.bytes($0)) en entier" } ?? "") }
                if let d = r.outputDetail { what += " · \(d)" }
                lines.append("\(outside.isEmpty ? "✓" : "✗ écrit hors du dossier d'aperçu !") \(op.title) (\(inputs.first!.pathExtension)) : \(what) en \(String(format: "%.1f", Date().timeIntervalSince(t))) s")
            } catch {
                lines.append("✗ \(op.title) (\(inputs.first!.pathExtension)) : \(error.localizedDescription)")
            }
        }
        // The originals must be untouched.
        let untouched = [png, text, md, pdf].allSatisfy { FS.exists($0.path) }
        lines.append(untouched ? "✓ originaux intacts" : "✗ un original a disparu")
        return lines
    }

    private static func writePNG(_ url: URL, text: String?) {
        let w = 800, h = 500
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 0.95, green: 0.6, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.25, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: 160))
        if let text {
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            (text as NSString).draw(at: NSPoint(x: 40, y: 220), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    private static func writePDF(_ url: URL, pages: Int) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        for i in 1...pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 0.85, green: 0.45, blue: 0.35, alpha: 1))
            ctx.fill(CGRect(x: 60, y: 600, width: 200 + CGFloat(i) * 40, height: 60))
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}
