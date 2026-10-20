import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

@Observable
@MainActor
final class ConverterModel: AppModule {
    /// Files handed over by the Finder service ("Convertir avec Clean My Claude"), a Dock drop or the launcher.
    var pendingFiles: [URL] = []
    var files: [ConverterFile] = [] {
        didSet { previewer.schedule(self) }
    }
    var operation: ConverterOperation? {
        didSet { if operation != oldValue { previewer.fileIndex = 0 }; previewer.schedule(self) }
    }
    var options = ConverterOptions() {
        didSet { previewer.schedule(self) }
    }
    /// The real result of the chosen operation, computed on one file before anything is saved.
    let previewer = ConverterPreviewer()
    /// Where results are saved: Téléchargements by default, next to the originals, or a chosen folder.
    var destination: ConverterDestination = ConverterDestination.saved() {
        didSet { if !DemoData.isEnabled { destination.save() } }
    }
    /// The folder handed to the engines (nil: next to each original).
    var outputFolder: URL? { destination.folder }
    var jobs: [ConverterJob] = []
    var message: String?
    var qrText = ""
    var ffmpegPath: String?
    /// Read once files are added (nil before).
    var ffmpegEncoders: Set<String>?
    @ObservationIgnored private var toolsChecked = false
    @ObservationIgnored private var readingEncoders = false
    @ObservationIgnored private var qrCache: (text: String, image: CGImage?) = ("", nil)
    @ObservationIgnored private var batchStart: Date?

    func receive(_ urls: [URL]) {
        pendingFiles = urls
        add(urls)
    }

    // MARK: - Files

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard !DemoData.isEnabled else {
            message = DemoData.refusal
            return
        }
        checkTools()
        readEncoders()
        var known = Set(files.map { $0.url.standardizedFileURL.path })
        var fresh: [ConverterFile] = []
        for url in urls.map(\.standardizedFileURL) where url.isFileURL && known.insert(url.path).inserted {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            fresh.append(ConverterFile(url: url, kind: ConverterKind.detect(name: url.lastPathComponent, isDirectory: FS.isDirectory(url.path))))
        }
        guard !fresh.isEmpty else { return }
        files += fresh
        message = nil
        if let op = operation, op != .qrGenerate, targets(for: op).count >= op.minimumCount {
            // The operation chosen beforehand (launcher, gallery) still applies.
        } else {
            operation = ConverterOperation.suggested(for: kinds)
        }
        inspect(fresh)
    }

    /// Size, dimensions or duration, and dates, read in the background.
    private func inspect(_ entries: [ConverterFile]) {
        let items = entries.map { (id: $0.id, url: $0.url, kind: $0.kind) }
        Task { [weak self] in
            for item in items {
                let info = await ConverterInspector.inspect(item.url, kind: item.kind)
                guard let self, let i = self.files.firstIndex(where: { $0.id == item.id }) else { continue }
                self.files[i].size = info.size
                self.files[i].detail = info.detail
                self.files[i].date = info.date
                self.files[i].pages = info.pages
                self.files[i].inspected = true
            }
        }
    }

    func remove(_ file: ConverterFile) {
        files.removeAll { $0.id == file.id }
        if options.mergePages[file.url.path] != nil { options.mergePages[file.url.path] = nil }
    }

    /// The scratch files of the previews go when the app quits.
    func stop() {
        previewer.cleanUp()
    }

    func clearFiles() {
        previewer.cleanUp()
        files.removeAll()
        pendingFiles.removeAll()
        if !options.mergePages.isEmpty { options.mergePages = [:] }
        message = nil
    }

    /// Moves a file up (-1) or down (+1) in the list (merge order).
    func move(_ file: ConverterFile, by offset: Int) {
        guard let i = files.firstIndex(where: { $0.id == file.id }) else { return }
        let j = i + offset
        guard files.indices.contains(j) else { return }
        files.swapAt(i, j)
    }

    /// Drag and drop in the merge order: the file goes to `index` among the files of `op`; the others keep their places.
    func move(_ id: UUID, to index: Int, among op: ConverterOperation) {
        var order = targets(for: op)
        guard let from = order.firstIndex(where: { $0.id == id }) else { return }
        let file = order.remove(at: from)
        order.insert(file, at: min(max(0, index), order.count))
        guard order.map(\.id) != targets(for: op).map(\.id) else { return }
        var next = order.makeIterator()
        files = files.map { op.accepts.contains($0.kind) ? (next.next() ?? $0) : $0 }
    }

    // MARK: - Merge

    /// The pages kept from a PDF of the merge ("" : all of them).
    func mergePages(_ file: ConverterFile) -> String {
        options.mergePages[file.url.path] ?? ""
    }

    func setMergePages(_ file: ConverterFile, _ spec: String) {
        options.mergePages[file.url.path] = spec.isEmpty ? nil : spec
    }

    /// The pages each document brings to the merge (nil while a PDF's page count is unknown or its list is not understood),
    /// blank pages for double-sided printing included.
    var mergePageCount: Int? {
        var total = 0
        let parts = targets(for: .pdfMerge)
        for (n, file) in parts.enumerated() {
            if file.kind == .image {
                total += 1
            } else {
                guard let count = file.pages, let pages = ConverterPDFEngine.parsePages(mergePages(file), count: count), !pages.isEmpty else { return nil }
                total += pages.count
            }
            if options.mergeDuplex, n < parts.count - 1, total % 2 == 1 { total += 1 }
        }
        return total
    }

    /// Why the merge cannot start yet: no PDF, or a list of pages not understood.
    var mergeProblem: String? {
        let parts = targets(for: .pdfMerge)
        guard parts.contains(where: { $0.kind == .pdf }) else { return "Il faut au moins un PDF." }
        for file in parts where file.kind == .pdf {
            guard let count = file.pages else { continue }
            let spec = mergePages(file)
            if ConverterPDFEngine.parsePages(spec, count: count)?.isEmpty != false {
                return "Pages de « \(file.name) » : « \(spec) » ne va pas (\(Fmt.plural(count, "page", "pages")))."
            }
        }
        return nil
    }

    var kinds: [ConverterKind] { files.map(\.kind) }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var availableOperations: [ConverterOperation] { ConverterOperation.available(for: kinds) }

    func targets(for op: ConverterOperation) -> [ConverterFile] {
        files.filter { op.accepts.contains($0.kind) }
    }

    var renamePreview: [ConverterRenamePreview] {
        ConverterRename.preview(targets(for: .rename), rule: options.rename)
    }

    /// False while {date} or {heure} wait for the files' own dates (read just after they were added).
    var renameDatesReady: Bool {
        !ConverterRename.needsDates(options.rename) || targets(for: .rename).allSatisfy(\.inspected)
    }

    /// The format chosen for an image operation (nil: "même format", each image keeps its own).
    func chosenImageFormat(_ op: ConverterOperation) -> ConverterImageFormat? {
        switch op {
        case .imageConvert: return options.imageFormat
        case .imageResize: return options.resizeFormat
        case .imageCompress: return options.compressFormat
        default: return nil
        }
    }

    /// The format each image of `op` is written in ("même format" keeps a PNG in PNG, without loss).
    func writtenFormats(_ op: ConverterOperation) -> [ConverterImageFormat] {
        let chosen = chosenImageFormat(op)
        return targets(for: op).map { chosen ?? ConverterImageEngine.sameFormat(for: $0.url) }
    }

    /// False when every image would be written without loss (a PNG kept in PNG): the quality changes nothing then.
    func qualityApplies(_ op: ConverterOperation) -> Bool {
        if let chosen = chosenImageFormat(op) { return chosen.lossy }
        let formats = writtenFormats(op)
        return formats.isEmpty || formats.contains(where: \.lossy)
    }

    /// Selects an operation (launcher, gallery, chips).
    func focus(_ op: ConverterOperation) {
        operation = op
        message = nil
        if op != .qrGenerate { checkTools() }
    }

    var canStart: Bool {
        guard let op = operation, op != .qrGenerate else { return false }
        let count = targets(for: op).count
        guard count >= op.minimumCount else { return false }
        switch op {
        case .rename: return renamePreview.contains { !$0.unchanged } && renameDatesReady
        case .pdfMerge:
            return mergeProblem == nil
        case .pdfSplit, .pdfRotate, .pdfToImages:
            return targets(for: op).allSatisfy { file in
                guard let pages = file.pages else { return false }
                return ConverterPDFEngine.parsePages(options.pdfPages, count: pages)?.isEmpty == false
            }
        default: return true
        }
    }

    // MARK: - Tools

    /// Looks for ffmpeg once, without starting it: showing the page runs nothing. Its encoders are read once files are added
    /// (a conversion is coming), or by the conversion itself (`ConverterMediaEngine.ffmpegEncoders`, kept for the session);
    /// ffmpeg then runs without the app's permissions (`Shell`).
    func checkTools() {
        guard !toolsChecked, !DemoData.isEnabled else { return }
        toolsChecked = true
        ffmpegPath = Shell.which("ffmpeg")
    }

    private func readEncoders() {
        guard let path = ffmpegPath, ffmpegEncoders == nil, !readingEncoders else { return }
        readingEncoders = true
        Task { [weak self] in
            let encoders = await Task.detached(priority: .utility) { ConverterMediaEngine.ffmpegEncoders(path) }.value
            self?.ffmpegEncoders = encoders
            self?.readingEncoders = false
        }
    }

    /// WebP needs ffmpeg built with libwebp; until its encoders are read, ffmpeg's presence decides
    /// (the conversion checks again and says so).
    var imageFormats: [ConverterImageFormat] {
        ConverterImageEngine.formats(webp: ffmpegEncoders.map { $0.contains("libwebp") } ?? (ffmpegPath != nil))
    }
    var audioFormats: [ConverterAudioFormat] { ConverterAudioFormat.available(ffmpeg: ffmpegPath != nil) }
    var containers: [ConverterVideoContainer] {
        ConverterVideoContainer.allCases.filter { !$0.viaFFmpeg || ffmpegPath != nil }
    }

    // MARK: - Output folder

    var destinationLabel: String { destination.label }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"
        panel.message = "Où ranger les fichiers convertis ?"
        panel.directoryURL = outputFolder ?? ConverterDestination.downloadsURL
        if panel.runModal() == .OK, let url = panel.url { destination = .folder(url) }
    }

    // MARK: - Queue

    var isBusy: Bool { jobs.contains { $0.isActive } }
    var activeJobs: [ConverterJob] { jobs.filter(\.isActive) }
    var finishedJobs: [ConverterJob] { jobs.filter(\.isFinished) }

    /// Overall progress of what is queued (finished jobs count as 1).
    var overallProgress: Double {
        let batch = jobs.filter { $0.isActive || ($0.finished ?? .distantPast) >= (batchStart ?? .distantFuture) }
        guard !batch.isEmpty else { return 0 }
        let sum = batch.reduce(0.0) { acc, job in
            switch job.state {
            case .waiting: return acc
            case .running: return acc + (job.progress ?? 0.5)
            default: return acc + 1
            }
        }
        return sum / Double(batch.count)
    }

    func startConversion() {
        guard let op = operation, op != .qrGenerate else { return }
        guard !DemoData.isEnabled else {
            message = DemoData.refusal
            return
        }
        let targets = targets(for: op)
        guard targets.count >= op.minimumCount else { return }
        let options = options
        let summary = Self.summary(op, options, qualityApplies: qualityApplies(op))
        var new: [ConverterJob] = []
        if op == .rename {
            guard renameDatesReady else {
                message = "Je lis encore les dates des fichiers : un instant."
                return
            }
            let preview = renamePreview.filter { !$0.unchanged }
            guard !preview.isEmpty else {
                message = "Les noms ne changent pas : rien à renommer."
                return
            }
            new.append(ConverterJob(operation: op, inputs: preview.map(\.url), kinds: preview.map { _ in .other },
                                    names: preview.map(\.newName), options: options, folder: nil,
                                    title: "Renommage de \(Fmt.plural(preview.count, "fichier", "fichiers"))", subtitle: summary,
                                    inputSize: 0))
        } else if op.isBatch {
            new.append(ConverterJob(operation: op, inputs: targets.map(\.url), kinds: targets.map(\.kind), options: options,
                                    folder: outputFolder, title: Self.batchTitle(op, count: targets.count), subtitle: summary,
                                    inputSize: targets.reduce(0) { $0 + $1.size }))
        } else {
            for f in targets {
                new.append(ConverterJob(operation: op, inputs: [f.url], kinds: [f.kind], options: options, folder: outputFolder,
                                        title: f.name, subtitle: summary, inputSize: f.size))
            }
        }
        if !isBusy { batchStart = Date() }
        jobs += new
        message = nil
        pump()
    }

    /// Starts the next waiting job (one at a time: predictable and gentle with the battery).
    private func pump() {
        guard !jobs.contains(where: { $0.state == .running }) else { return }
        guard let job = jobs.first(where: { $0.state == .waiting }) else {
            batchFinished()
            return
        }
        job.state = .running
        job.started = Date()
        job.progress = 0
        let spec = ConverterEngine.Spec(operation: job.operation, inputs: job.inputs, kinds: job.kinds, names: job.names,
                                        options: job.options, folder: job.folder, ffmpeg: ffmpegPath)
        let control = job.control!
        Task { [weak self] in
            let result: Result<ConverterOutput, Error> = await Task.detached(priority: .userInitiated) {
                do { return .success(try await ConverterEngine.run(spec, control: control)) } catch { return .failure(error) }
            }.value
            self?.finish(job, result)
        }
    }

    private func finish(_ job: ConverterJob, _ result: Result<ConverterOutput, Error>) {
        job.finished = Date()
        switch result {
        case .success(let output):
            job.output = output
            job.progress = 1
            job.state = .done
            for pair in output.renamed {
                if let i = files.firstIndex(where: { $0.url == pair.from }) { files[i].url = pair.to }
            }
        case .failure(let error):
            if case ConverterError.cancelled = error {
                job.state = .cancelled
            } else {
                job.state = .failed(error.localizedDescription)
            }
        }
        pump()
    }

    /// A notification when a long batch ends while the app is in the background.
    private func batchFinished() {
        guard let start = batchStart else { return }
        batchStart = nil
        let batch = jobs.filter { ($0.finished ?? .distantPast) >= start }
        guard Date().timeIntervalSince(start) > 15, !NSApp.isActive, !batch.isEmpty else { return }
        let done = batch.filter { $0.state == .done }.count
        let failed = batch.filter { if case .failed = $0.state { return true } else { return false } }.count
        var body = Fmt.plural(done, "conversion réussie", "conversions réussies")
        if failed > 0 { body += ", \(Fmt.plural(failed, "échec", "échecs"))" }
        Notifier.post(id: "converter.done", title: "Conversions terminées", body: body + ".", throttle: 0)
    }

    func cancel(_ job: ConverterJob) {
        switch job.state {
        case .waiting:
            job.state = .cancelled
            job.finished = Date()
        case .running:
            job.control.cancel()
        default:
            break
        }
    }

    func cancelAll() {
        for job in jobs where job.isActive { cancel(job) }
    }

    func clearFinished() {
        jobs.removeAll { $0.isFinished }
    }

    func dismiss(_ job: ConverterJob) {
        guard job.isFinished else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func retry(_ job: ConverterJob) {
        let copy = ConverterJob(operation: job.operation, inputs: job.inputs, kinds: job.kinds, names: job.names, options: job.options,
                                folder: job.folder, title: job.title, subtitle: job.subtitle, inputSize: job.inputSize)
        jobs.removeAll { $0.id == job.id }
        if !isBusy { batchStart = Date() }
        jobs.append(copy)
        pump()
    }

    /// Puts the old names back after a batch rename.
    func undoRename(_ job: ConverterJob) {
        guard job.operation == .rename, !job.undone, !DemoData.isEnabled else { return }
        let items = job.output.renamed.map { (url: $0.to, newName: $0.from.lastPathComponent) }
        let control = ConverterControl { _ in }
        do {
            let pairs = try ConverterRename.apply(items, control: control)
            for pair in pairs {
                if let i = files.firstIndex(where: { $0.url == pair.from }) { files[i].url = pair.to }
            }
            job.undone = true
            message = "Les anciens noms sont revenus."
        } catch {
            message = "Les anciens noms n'ont pas pu revenir (rien n'a changé) : \(error.localizedDescription)"
        }
    }

    // MARK: - Results

    func reveal(_ urls: [URL]) {
        guard !DemoData.isEnabled, !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func open(_ url: URL) {
        guard !DemoData.isEnabled else { return }
        NSWorkspace.shared.open(url)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        HUD.show("Texte copié", symbol: "doc.on.clipboard.fill")
    }

    /// The OCR text as a .txt file next to the image (or in the chosen folder).
    func saveText(_ job: ConverterJob) {
        guard let text = job.output.text, let input = job.inputs.first, !DemoData.isEnabled else { return }
        let out = FileOps.outputURL(for: input, extension: "txt", suffix: "texte", folder: job.folder)
        do {
            let url = try FileOps.write(Data(text.utf8), to: out)
            job.output.files.append(url)
            HUD.show("Enregistré : \(url.lastPathComponent)")
        } catch {
            HUD.show(error.localizedDescription, symbol: "xmark.octagon.fill")
        }
    }

    // MARK: - QR codes

    var qrImage: CGImage? {
        let text = qrText
        if qrCache.text == text { return qrCache.image }
        let image = text.utf8.count <= ConverterVision.qrCapacity ? ConverterVision.qrImage(text) : nil
        qrCache = (text, image)
        return image
    }

    func copyQR(_ text: String? = nil) {
        guard let image = text.map({ ConverterVision.qrImage($0) }) ?? qrImage, let png = ConverterImageEngine.pngData(image) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        HUD.show("QR code copié", symbol: "qrcode")
    }

    func saveQR() {
        guard !DemoData.isEnabled, let image = qrImage, let png = ConverterImageEngine.pngData(image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "QR code.png"
        panel.directoryURL = outputFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let saved = try FileOps.write(png, to: url)
            HUD.show("Enregistré : \(saved.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([saved])
        } catch {
            HUD.show(error.localizedDescription, symbol: "xmark.octagon.fill")
        }
    }

    // MARK: - Texts

    static func batchTitle(_ op: ConverterOperation, count: Int) -> String {
        switch op {
        case .imagesToPDF: return "\(Fmt.plural(count, "image", "images")) → PDF"
        case .pdfMerge: return "Fusion de \(Fmt.plural(count, "document", "documents"))"
        case .archiveZip: return "Archive de \(Fmt.plural(count, "élément", "éléments"))"
        default: return op.title
        }
    }

    /// What the job will do, in a few words: "→ JPEG · qualité 82 %". `qualityApplies` false: every image is written
    /// without loss (a PNG kept in PNG), the quality is not mentioned.
    static func summary(_ op: ConverterOperation, _ o: ConverterOptions, qualityApplies: Bool = true) -> String {
        let quality = "qualité \(Int((o.imageQuality * 100).rounded())) %"
        switch op {
        case .imageConvert:
            let f = o.imageFormat
            return "→ \(f?.name ?? "même format")" + (f?.lossy ?? true ? " · \(quality)" : "") + (o.stripOnConvert ? " · sans GPS" : "")
        case .imageResize:
            return "→ \(Fmt.int(o.maxSide)) px max · \(o.resizeFormat?.name ?? "même format")"
        case .imageCompress:
            return "→ " + [qualityApplies ? quality : nil, o.compressFormat?.name ?? "même format",
                           o.compressMaxSide > 0 ? "\(Fmt.int(o.compressMaxSide)) px" : nil].compactMap { $0 }.joined(separator: " · ")
        case .imageStrip:
            return o.stripMode == .gps ? "→ sans localisation" : "→ sans métadonnées"
        case .imagesToPDF:
            return "→ PDF · \(o.pageSize.title.lowercased())"
        case .videoCompress:
            return "→ \(o.videoPreset.title) · \(o.compressContainer.name)"
        case .videoContainer:
            return "→ \(o.container.name)"
        case .videoAudio:
            return "→ AAC (.m4a)"
        case .videoGIF:
            return "→ GIF \(o.gifWidth) px · \(o.gifFPS) i/s" + (o.gifSeconds > 0 ? " · \(o.gifSeconds) s max" : "")
        case .audioConvert:
            return "→ \(o.audioFormat.name)" + (o.audioFormat.lossy ? " · \(o.audioBitrate) kb/s" : "")
        case .pdfMerge:
            return "→ un seul PDF" + (o.mergeBookmarks ? " · un signet par document" : "") + (o.mergeDuplex ? " · prêt pour le recto verso" : "")
        case .pdfSplit:
            let pages = o.pdfPages.trimmingCharacters(in: .whitespaces)
            return "→ pages \(pages.isEmpty ? "toutes" : pages) · \(o.splitMode.title.lowercased())"
        case .pdfRotate:
            return "→ \(o.rotation == 90 ? "90° à droite" : (o.rotation == 180 ? "180°" : "90° à gauche"))"
                + (o.pdfPages.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " · pages \(o.pdfPages)")
        case .pdfCompress:
            return "→ \(o.pdfCompression.title.lowercased())"
        case .pdfToImages:
            return "→ \(o.rasterFormat.name) · \(o.rasterDPI) ppp"
        case .documentConvert:
            return "→ \(o.docFormat.name)"
        case .archiveZip:
            return "→ ZIP · \(o.zipMode.title.lowercased())"
        case .archiveExtract:
            return "→ nouveau dossier"
        case .rename:
            return "Motif « \(o.rename.pattern) »"
        case .ocr:
            return "→ texte (français, anglais)"
        case .qrRead:
            return "→ contenu des codes"
        case .qrGenerate:
            return "→ PNG"
        }
    }

    // MARK: - AppModule

    var sidebarBadge: String? {
        let active = jobs.filter(\.isActive).count
        return active > 0 ? "\(active)" : nil
    }

    func commands(app: AppModel) -> [AppCommand] {
        ConverterOperation.allCases.map { op in
            AppCommand(id: op.commandID, title: op.commandTitle, subtitle: op.explanation, keywords: op.keywords + ["convertir", "convertisseur"],
                       icon: .symbol(op.symbol, op.family.tint), group: .convert, assistantSafe: true, urlSafe: true, hint: "Ouvrir") { ctx in
                ctx.app.converter.focus(op)
                ctx.app.page = .converter
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
                return .done
            }
        }
    }

    /// "qr bonjour" → the QR code of "bonjour" (⌘ copies the image straight away).
    func results(for query: String, app: AppModel) -> [AppCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count > 3, q.lowercased().hasPrefix("qr ") else { return [] }
        let text = String(q.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.utf8.count <= ConverterVision.qrCapacity else { return [] }
        let shown = text.count > 40 ? String(text.prefix(40)) + "…" : text
        return [AppCommand(id: "conv_qr_result", title: "QR code : « \(shown) »", subtitle: "Ouvre le QR code · ⌘ pour copier l'image",
                           icon: .symbol("qrcode", ConverterFamily.vision.tint), group: .convert, hint: "Créer", boost: 1500) { ctx in
            if ctx.alternate {
                ctx.app.converter.copyQR(text)
                return .done
            }
            ctx.app.converter.qrText = text
            ctx.app.converter.focus(.qrGenerate)
            ctx.app.page = .converter
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
            return .done
        }]
    }

    func dump() -> [String] {
        checkTools()
        var lines: [String] = []
        lines.append("Fichiers dans la liste : \(files.count) · tâches : \(jobs.count)")
        lines.append("Formats d'image écrivables : " + ConverterImageEngine.formats(webp: false).map(\.name).joined(separator: ", "))
        let presets = Set(AVAssetExportSession.allExportPresets())
        lines.append("Préréglages vidéo : " + ConverterVideoPreset.allCases.map { "\($0.short) \(presets.contains($0.rawValue) ? "✓" : "✗")" }.joined(separator: ", "))
        lines.append("ffmpeg : \(ffmpegPath ?? "absent (MP3, MKV, WebM et WebP indisponibles)")")
        if let path = ffmpegPath {
            let enc = ConverterMediaEngine.ffmpegEncoders(path)
            lines.append("Encodeurs ffmpeg utiles : " + ["libx264", "libmp3lame", "libwebp", "libvpx-vp9", "libopus"].map { "\($0) \(enc.contains($0) ? "✓" : "✗")" }.joined(separator: ", "))
        }
        for tool in [ConverterDocumentEngine.textutil, ConverterMediaEngine.afconvert, "/usr/bin/ditto", "/usr/bin/zip", "/usr/bin/tar"] {
            lines.append("\(tool) : \(Shell.exists(tool) ? "présent" : "ABSENT")")
        }
        lines.append("Filtre Quartz « Reduce File Size » : \(FileManager.default.fileExists(atPath: ConverterPDFEngine.reduceFilter) ? "présent" : "absent")")
        lines.append("Opérations : \(ConverterOperation.allCases.count) · commandes du lanceur : \(ConverterOperation.allCases.map(\.commandID).joined(separator: " "))")
        for f in files.prefix(20) {
            lines.append("  \(f.kind.title)\t\(Fmt.bytes(f.size))\t\(f.name)\(f.detail.map { " · \($0)" } ?? "")")
        }
        return lines
    }
}

/// Reads what the file list shows, off the main actor.
enum ConverterInspector {
    struct Info: Sendable {
        var size: Int64
        var detail: String?
        var date: Date?
        var pages: Int?
    }

    static func inspect(_ url: URL, kind: ConverterKind) async -> Info {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        var info = Info(size: ConverterOutputs.size(url), detail: nil, date: values?.creationDate ?? values?.contentModificationDate)
        switch kind {
        case .image:
            let d = ConverterImageEngine.describe(url)
            info.detail = d.detail
            if let date = d.date { info.date = date }
        case .video, .audio:
            info.detail = await ConverterMediaEngine.describe(url, kind: kind)
        case .pdf:
            info.pages = ConverterPDFEngine.pageCount(url)
            info.detail = info.pages.map { Fmt.plural($0, "page", "pages") }
        case .folder:
            let n = (try? FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.count) ?? 0
            info.detail = Fmt.plural(n, "élément", "éléments")
        default:
            break
        }
        return info
    }
}
