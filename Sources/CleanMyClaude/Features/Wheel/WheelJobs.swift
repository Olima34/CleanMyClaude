import Foundation

/// What an action gave back.
struct WheelResult: Sendable {
    var outputs: [URL] = []
    /// Shown under the result ("Sans réencodage", "Déjà léger"…).
    var note: String?
    /// Put on the clipboard instead of a file (the text of a picture).
    var copied: String?
}

/// The actions done at once, off the main thread. Most go through the converter's engines; each file gets its own copy,
/// next to it or in the folder given. Nothing is ever written over the original.
enum WheelJobs {
    struct Context: Sendable {
        /// nil: next to each original.
        var folder: URL?
        var ffmpeg: String?
    }

    /// `onStep`: the file being done (the toast shows "2 sur 5").
    static func perform(_ action: WheelAction, files: [WheelFile], context: Context, control: ConverterControl,
                        onStep: @escaping @Sendable (Int) -> Void) async throws -> WheelResult {
        let family = WheelFamily.of(files.map(\.kind))
        // One job for all of them.
        switch action {
        case .pdf where family == .image:
            return try await converter(.imagesToPDF, files, context, control) { $0.pageSize = .image }
        case .merge:
            return try await converter(.pdfMerge, files, context, control) { $0.mergeBookmarks = true }
        case .zip:
            return try await converter(.archiveZip, files, context, control) { $0.zipMode = .together }
        default:
            break
        }
        var result = WheelResult()
        var notes: [String] = []
        var texts: [String] = []
        for (i, file) in files.enumerated() {
            try control.check()
            onStep(i)
            let r = try await one(action, file, context: context, control: control)
            result.outputs += r.outputs
            if let n = r.note, !notes.contains(n) { notes.append(n) }
            if let t = r.copied { texts.append(t) }
        }
        result.note = notes.isEmpty ? nil : notes.joined(separator: " ")
        if !texts.isEmpty { result.copied = texts.joined(separator: "\n\n") }
        return result
    }

    private static func one(_ action: WheelAction, _ file: WheelFile, context: Context, control: ConverterControl) async throws -> WheelResult {
        let url = file.url
        let folder = context.folder
        switch action {
        case .jpeg, .png, .heic, .webp:
            if file.kind == .pdf {
                let out = try WheelDocEngine.toImages(url, format: action == .png ? .png : .jpeg, folder: folder, control: control)
                return WheelResult(outputs: [out])
            }
            let format: ConverterImageFormat = action == .jpeg ? .jpeg : (action == .png ? .png : (action == .heic ? .heic : .webp))
            return try await converter(.imageConvert, [file], context, control) { $0.imageFormat = format; $0.imageQuality = 0.9 }
        case .pdf:
            return try await converter(.documentConvert, [file], context, control) { $0.docFormat = .pdf }
        case .word:
            if file.kind == .pdf { return WheelResult(outputs: [try WheelDocEngine.toWord(url, folder: folder, control: control)]) }
            return try await converter(.documentConvert, [file], context, control) { $0.docFormat = .docx }
        case .text:
            switch file.kind {
            case .pdf:
                return WheelResult(outputs: [try WheelDocEngine.toText(url, folder: folder, control: control)])
            case .image:
                let text = try ConverterVision.ocr(url, kind: .image, control: control)
                guard !text.isEmpty else { throw ConverterError.failed("Aucun texte reconnu sur « \(file.name) ».") }
                return WheelResult(outputs: [try FileOps.write(Data(text.utf8), to: FileOps.outputURL(for: url, extension: "txt", folder: folder))])
            default:
                return try await converter(.documentConvert, [file], context, control) { $0.docFormat = .txt }
            }
        case .html:
            return try await converter(.documentConvert, [file], context, control) { $0.docFormat = .html }
        case .mp4, .mov:
            return try await converter(.videoContainer, [file], context, control) { $0.container = action == .mp4 ? .mp4 : .mov }
        case .gif:
            var r = try await converter(.videoGIF, [file], context, control) { _ in }
            r.note = r.note ?? "Les \(ConverterOptions().gifSeconds) premières secondes, en boucle."
            return r
        case .sound:
            return try await converter(.videoAudio, [file], context, control) { _ in }
        case .aac, .mp3, .wav, .flac, .alac:
            let format: ConverterAudioFormat
            switch action {
            case .mp3: format = .mp3
            case .wav: format = .wav
            case .flac: format = .flac
            case .alac: format = .alac
            default: format = .aac
            }
            return try await converter(.audioConvert, [file], context, control) { $0.audioFormat = format }
        case .cutout:
            return WheelResult(outputs: [try WheelImageEngine.cutout(url, folder: folder, control: control)])
        case .rotate:
            control.progress(nil)
            return WheelResult(outputs: [try WheelImageEngine.rotate(url, folder: folder)])
        case .copyText:
            control.progress(nil)
            let text: String
            switch file.kind {
            case .pdf: text = try WheelDocEngine.text(of: url, control: control)
            case .image: text = try ConverterVision.ocr(url, kind: .image, control: control)
            default: text = try documentText(url)
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConverterError.failed("Aucun texte trouvé dans « \(file.name) ».")
            }
            return WheelResult(copied: text)
        case .pdfCompress:
            return try await converter(.pdfCompress, [file], context, control) { $0.pdfCompression = .balanced }
        case .pdfRotate:
            return try await converter(.pdfRotate, [file], context, control) { $0.rotation = 90; $0.pdfPages = "" }
        case .pdfImages:
            return try await converter(.pdfToImages, [file], context, control) { $0.rasterFormat = .png; $0.rasterDPI = 150 }
        case .mute:
            return WheelResult(outputs: [try await WheelMediaEngine.mute(url, folder: folder, control: control)])
        case .extract:
            return try await converter(.archiveExtract, [file], context, control) { _ in }
        case .zip:
            return try await converter(.archiveZip, [file], context, control) { $0.zipMode = .together }
        case .crop, .backdrop, .annotate, .redact, .compress, .resize, .metadata, .pdfPages, .trim, .frame, .videoCompress,
             .merge, .airdrop, .copyPath:
            throw ConverterError.unsupported("« \(action.title) » ne se fait pas ainsi.")
        }
    }

    /// One of the converter's operations, with its default options changed by `adjust`.
    static func converter(_ op: ConverterOperation, _ files: [WheelFile], _ context: Context, _ control: ConverterControl,
                          adjust: (inout ConverterOptions) -> Void) async throws -> WheelResult {
        var options = ConverterOptions()
        adjust(&options)
        let spec = ConverterEngine.Spec(operation: op, inputs: files.map(\.url), kinds: files.map(\.kind), names: [], options: options,
                                        folder: context.folder, ffmpeg: context.ffmpeg)
        let out = try await ConverterEngine.run(spec, control: control)
        if out.files.isEmpty && out.note == nil { throw ConverterError.failed("Rien n'a été créé.") }
        return WheelResult(outputs: out.files, note: out.note)
    }

    /// The text of a Word, RTF, HTML or Markdown document (textutil, out of process).
    private static func documentText(_ url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "txt" || ext == "text" || ConverterKind.markdownExtensions.contains(ext) {
            return try ConverterDocumentEngine.readText(url)
        }
        let r = Shell.run(ConverterDocumentEngine.textutil, ["-convert", "txt", "-stdout", url.path], timeout: 60)
        guard r.ok else { throw ConverterError.failed(r.err.isEmpty ? "Je n'arrive pas à lire « \(url.lastPathComponent) »." : r.err) }
        return r.out
    }

    /// Where the copies of `input` go: next to it when its folder can be written in, else Téléchargements (and says so).
    static func folder(for input: URL, destination: WheelDestination) -> (folder: URL?, note: String?) {
        if destination == .downloads { return (ConverterDestination.downloadsURL, nil) }
        let dir = input.deletingLastPathComponent().path
        if FileManager.default.isWritableFile(atPath: dir) { return (nil, nil) }
        return (ConverterDestination.downloadsURL, "Rangée dans Téléchargements : le dossier d'origine est en lecture seule.")
    }
}
