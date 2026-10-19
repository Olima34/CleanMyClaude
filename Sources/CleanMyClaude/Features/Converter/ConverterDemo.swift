import Foundation

/// Fictional files and results for `--demo` (README screenshots). Nothing here exists on any Mac.
extension ConverterModel {
    func loadDemo() {
        ConverterDemo.fill(self, scene: .images)
        previewer.loadDemo(self)
    }

    /// `--snapshot --demo --page converter --tab <scene>`: images (default), video, pdf, documents, rename, ocr, qr, empty.
    func applySnapshotTab(_ tab: String) {
        guard DemoData.isEnabled else { return }
        if tab == "attente" {
            // A video being compressed, the preview of the next operation being rendered.
            ConverterDemo.fill(self, scene: .video)
            previewer.state = .working
            return
        }
        guard let scene = ConverterDemo.Scene(rawValue: tab) else { return }
        ConverterDemo.fill(self, scene: scene)
        previewer.loadDemo(self)
    }
}

@MainActor
enum ConverterDemo {
    enum Scene: String {
        case images, video, pdf, documents, rename, ocr, qr, empty
    }

    private static let mb: Int64 = 1_000_000
    private static let pictures = DemoData.home + "/Pictures/Week-end à Étretat"
    private static let movies = DemoData.home + "/Movies"
    private static let documents = DemoData.home + "/Documents"
    private static let now = Date()

    private static func file(_ path: String, _ kind: ConverterKind, _ size: Double, _ detail: String?, pages: Int? = nil,
                             daysAgo: Double = 3) -> ConverterFile {
        ConverterFile(url: URL(fileURLWithPath: path), kind: kind, size: Int64(size * Double(mb)), date: now.addingTimeInterval(-daysAgo * 86400),
                      detail: detail, pages: pages, inspected: true)
    }

    private static func job(_ model: ConverterModel, _ op: ConverterOperation, _ inputs: [String], kind: ConverterKind, title: String? = nil,
                            state: ConverterJob.State, progress: Double? = 1, inputSize: Double, output: [String] = [],
                            outputSize: Double = 0, note: String? = nil, text: String? = nil, codes: [String] = [],
                            seconds: Double = 0) -> ConverterJob {
        let urls = inputs.map { URL(fileURLWithPath: $0) }
        let j = ConverterJob(operation: op, inputs: urls, kinds: urls.map { _ in kind }, options: model.options, folder: nil,
                             title: title ?? urls[0].lastPathComponent, subtitle: ConverterModel.summary(op, model.options),
                             inputSize: Int64(inputSize * Double(mb)))
        j.state = state
        j.progress = progress
        j.output = ConverterOutput(files: output.map { URL(fileURLWithPath: $0) }, text: text, codes: codes, note: note,
                                   size: Int64(outputSize * Double(mb)))
        if seconds > 0 {
            j.started = now.addingTimeInterval(-seconds)
            j.finished = now
        }
        return j
    }

    static func fill(_ model: ConverterModel, scene: Scene) {
        model.options = ConverterOptions()
        model.jobs = []
        model.message = nil
        model.qrText = ""
        model.destination = .downloads
        model.files = []
        switch scene {
        case .images:
            model.files = [
                file(pictures + "/IMG_4102.HEIC", .image, 3.42, "4 032 × 3 024"),
                file(pictures + "/IMG_4107.HEIC", .image, 2.87, "4 032 × 3 024"),
                file(pictures + "/IMG_4113.HEIC", .image, 3.18, "3 024 × 4 032"),
                file(pictures + "/IMG_4118.HEIC", .image, 2.64, "4 032 × 3 024"),
                file(pictures + "/IMG_4121.HEIC", .image, 3.05, "4 032 × 2 268"),
                file(pictures + "/Falaises au coucher du soleil.mov", .video, 412.6, "1:12 · 3 840 × 2 160")
            ]
            model.options.imageFormat = .jpeg
            model.options.imageQuality = 0.82
            model.options.stripOnConvert = true
            model.operation = .imageConvert
            model.jobs = [
                job(model, .imageConvert, [pictures + "/IMG_4096.HEIC"], kind: .image, state: .done, inputSize: 3.21,
                    output: [pictures + "/IMG_4096.jpg"], outputSize: 1.38),
                job(model, .imageConvert, [pictures + "/IMG_4099.HEIC"], kind: .image, state: .done, inputSize: 2.95,
                    output: [pictures + "/IMG_4099.jpg"], outputSize: 1.21),
                job(model, .videoCompress, [movies + "/Plongée à la Manneporte.mov"], kind: .video, state: .running, progress: 0.64,
                    inputSize: 1_840),
                job(model, .videoCompress, [movies + "/Pique-nique sur la plage.mov"], kind: .video, state: .waiting, progress: 0,
                    inputSize: 655)
            ]
        case .video:
            model.files = [
                file(movies + "/Plongée à la Manneporte.mov", .video, 1_840, "4:38 · 3 840 × 2 160"),
                file(movies + "/Pique-nique sur la plage.mov", .video, 655, "1:52 · 1 920 × 1 080"),
                file(movies + "/Anniversaire de Jules.mp4", .video, 312, "3:05 · 1 920 × 1 080")
            ]
            model.options.videoPreset = .hevc1080
            model.operation = .videoCompress
            model.jobs = [
                job(model, .videoCompress, [movies + "/Coucher de soleil timelapse.mov"], kind: .video, state: .done, inputSize: 968,
                    output: [movies + "/Coucher de soleil timelapse HEVC 1080p.mp4"], outputSize: 214, seconds: 96),
                job(model, .videoGIF, [movies + "/Mouette qui vole une frite.mov"], kind: .video, state: .done, inputSize: 48,
                    output: [movies + "/Mouette qui vole une frite.gif"], outputSize: 6.2, seconds: 8),
                job(model, .videoCompress, [movies + "/Plongée à la Manneporte.mov"], kind: .video, state: .running, progress: 0.38,
                    inputSize: 1_840)
            ]
        case .pdf:
            model.files = [
                file(documents + "/Maison/Devis cuisine.pdf", .pdf, 1.9, "4 pages", pages: 4),
                file(documents + "/Maison/Plan rez-de-chaussée.pdf", .pdf, 3.4, "2 pages", pages: 2),
                file(documents + "/Maison/Conditions générales.pdf", .pdf, 0.8, "12 pages", pages: 12)
            ]
            model.operation = .pdfMerge
            model.jobs = [
                job(model, .pdfCompress, [documents + "/Banque/Relevé annuel 2025.pdf"], kind: .pdf, state: .done, inputSize: 18.4,
                    output: [documents + "/Banque/Relevé annuel 2025 allégé.pdf"], outputSize: 2.7, seconds: 4),
                job(model, .pdfToImages, [documents + "/Maison/Plan étage.pdf"], kind: .pdf, state: .done, inputSize: 2.2,
                    output: [documents + "/Maison/Plan étage – images"], outputSize: 5.8)
            ]
        case .documents:
            model.files = [
                file(documents + "/Notes de réunion.md", .markdown, 0.012, nil),
                file(documents + "/Lettre de motivation.docx", .document, 0.046, nil),
                file(documents + "/Recette de la tarte Tatin.rtf", .document, 0.008, nil)
            ]
            model.options.docFormat = .pdf
            model.operation = .documentConvert
            model.jobs = [
                job(model, .archiveZip, [documents + "/Dossier location"], kind: .folder, title: "Dossier location", state: .done,
                    inputSize: 24.6, output: [documents + "/Dossier location.zip"], outputSize: 21.9)
            ]
        case .rename:
            let names = ["IMG_5501.JPG", "IMG_5502.JPG", "IMG_5503.JPG", "IMG_5507.JPG", "IMG_5510.JPG", "IMG_5512.JPG", "IMG_5515.JPG", "IMG_5518.JPG"]
            // One afternoon, a few minutes apart.
            let day = Calendar.current.startOfDay(for: now.addingTimeInterval(-160 * 86400)).addingTimeInterval(14 * 3600)
            model.files = names.enumerated().map { i, n in
                var f = file(pictures + "/" + n, .image, 2.4 + Double(i % 3) * 0.3, "4 032 × 3 024")
                f.date = day.addingTimeInterval(Double(i) * 420)
                return f
            }
            model.options.rename = ConverterRenameRule(pattern: "Étretat {date} {n:3}", start: 1, lowercaseExtension: true)
            model.operation = .rename
        case .ocr:
            model.files = [
                file(DemoData.home + "/Desktop/Ticket boulangerie.jpg", .image, 1.6, "3 024 × 4 032"),
                file(documents + "/Contrat scanné.pdf", .pdf, 6.8, "3 pages", pages: 3)
            ]
            model.operation = .ocr
            model.jobs = [
                job(model, .ocr, [DemoData.home + "/Desktop/Ticket boulangerie.jpg"], kind: .image, state: .done, inputSize: 1.6, text: """
                    BOULANGERIE DU PORT
                    12, quai des Galets · 76790 Étretat
                    Mardi 14 octobre 2026 · 08:42

                    2 croissants au beurre          2,60 €
                    1 baguette tradition            1,30 €
                    1 tarte normande (6 parts)     16,50 €

                    TOTAL TTC                      20,40 €
                    Carte bancaire sans contact
                    Merci et à bientôt !
                    """, seconds: 2),
                job(model, .qrRead, [DemoData.home + "/Desktop/Affiche concert.png"], kind: .image, state: .done, inputSize: 0.9,
                    codes: ["https://exemple.fr/billetterie/concert-plage"])
            ]
        case .qr:
            model.qrText = "https://github.com/Olima34/CleanMyClaude"
            model.operation = .qrGenerate
        case .empty:
            model.operation = nil
        }
    }
}
