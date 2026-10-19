import SwiftUI
import AppKit
import Quartz

/// « Aperçu du résultat » : the original and what the chosen operation really makes of it, side by side,
/// before anything is saved. Nothing is done blind.
struct ConverterPreviewPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        let preview = model.previewer
        let op = model.operation
        let targets = op.map { model.targets(for: $0) } ?? []
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconBadge(symbol: "eye", tint: Theme.palette[1], size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Aperçu du résultat").font(.ui(14, .semibold)).foregroundStyle(Theme.text)
                        Text(subtitle(preview, op: op)).font(.ui(11.5)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                    Spacer()
                    if let op, !op.isBatch, targets.count > 1 {
                        ConverterPager(label: "Fichier \(preview.fileIndex + 1) sur \(targets.count)",
                                       index: preview.fileIndex, count: targets.count) { i in
                            preview.fileIndex = i
                            preview.schedule(model)
                        }
                    }
                }
                content(preview)
                    .frame(height: 330)
                footer(preview)
            }
        }
    }

    private func subtitle(_ preview: ConverterPreviewer, op: ConverterOperation?) -> String {
        if preview.isWorking { return "Je prépare le rendu exact…" }
        guard let r = preview.result else { return "Le rendu exact de ce que tu vas obtenir, avant d'enregistrer quoi que ce soit" }
        let names = r.sources.map(\.lastPathComponent)
        let what = names.count > 1 ? "\(names.count) fichiers" : "« \(names.first ?? "") »"
        if let s = r.excerptSeconds { return "Calculé pour de vrai sur les \(Int(s)) premières secondes de \(what) · rien n'est encore enregistré" }
        return "Calculé pour de vrai sur \(what) · rien n'est encore enregistré"
    }

    @ViewBuilder
    private func content(_ preview: ConverterPreviewer) -> some View {
        switch preview.state {
        case .idle:
            placeholder(symbol: "eye.slash", text: "Choisis une opération : son rendu apparaît ici avant que tu lances quoi que ce soit.")
        case .working:
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text("Je prépare le rendu exact…").font(.ui(12)).foregroundStyle(Theme.text3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(Theme.bg.opacity(0.5)))
        case .failed(let message):
            placeholder(symbol: "exclamationmark.triangle", text: "Cette conversion échouerait : \(message)", tint: Theme.warn)
        case .ready(let r):
            HStack(spacing: 12) {
                pane(title: "Avant", detail: detailLine(size: r.sourceSize, detail: r.sourceDetail)) {
                    ConverterPreviewSurface(url: r.sources.first, demo: r.demo, demoAfter: false)
                }
                Image(systemName: "arrow.right").font(.ui(13, .semibold)).foregroundStyle(Theme.text3)
                pane(title: "Après", detail: afterDetail(r)) {
                    after(r, index: preview.outputIndex)
                }
            }
        }
    }

    @ViewBuilder
    private func after(_ r: ConverterPreviewResult, index: Int) -> some View {
        if let text = r.text {
            ScrollArea {
                Text(text.isEmpty ? "Aucun texte reconnu." : text)
                    .font(.ui(12.5)).foregroundStyle(text.isEmpty ? Theme.text3 : Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.bg.opacity(0.6)))
        } else if r.operation == .qrRead {
            listBox(r.codes.isEmpty ? ["Aucun code trouvé."] : r.codes)
        } else if let listing = r.listing {
            listBox(listing + (r.listingTotal > listing.count ? ["… et \(r.listingTotal - listing.count) autres"] : []))
        } else {
            let shown = ConverterPreviewFiles.expand(r.outputs)
            VStack(spacing: 6) {
                ConverterPreviewSurface(url: shown.isEmpty ? nil : shown[min(index, shown.count - 1)], demo: r.demo, demoAfter: true)
                if shown.count > 1 {
                    ConverterPager(label: "\(shown[min(index, shown.count - 1)].lastPathComponent) · \(min(index, shown.count - 1) + 1) sur \(shown.count)",
                                   index: min(index, shown.count - 1), count: shown.count) { app.converter.previewer.outputIndex = $0 }
                }
            }
        }
    }

    private func listBox(_ lines: [String]) -> some View {
        ScrollArea {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.mono(11.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.bg.opacity(0.6)))
    }

    private func pane<Content: View>(title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title.uppercased()).font(.ui(10, .semibold)).tracking(0.6).foregroundStyle(Theme.text3)
                Text(detail).font(.ui(11)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r(10)))
                .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
        }
        .frame(maxWidth: .infinity)
    }

    private func detailLine(size: Int64, detail: String?) -> String {
        ([size > 0 ? Fmt.bytes(size) : nil, detail].compactMap { $0 }).joined(separator: " · ")
    }

    private func afterDetail(_ r: ConverterPreviewResult) -> String {
        if r.text != nil { return "Texte reconnu" }
        if r.operation == .qrRead { return Fmt.plural(r.codes.count, "code", "codes") }
        if r.listing != nil { return Fmt.plural(r.listingTotal, "élément", "éléments") + " dans l'archive" }
        let shown = ConverterPreviewFiles.expand(r.outputs)
        var parts: [String] = []
        if let estimated = r.estimatedSize { parts.append("≈ \(Fmt.bytes(estimated)) pour tout le fichier") } else if r.outputSize > 0 { parts.append(Fmt.bytes(r.outputSize)) }
        if shown.count > 1 { parts.append(Fmt.plural(shown.count, "fichier", "fichiers")) }
        if let d = r.outputDetail { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func footer(_ preview: ConverterPreviewer) -> some View {
        if let r = preview.result {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if r.sourceSize > 0, (r.estimatedSize ?? r.outputSize) > 0, r.text == nil, r.listing == nil, r.operation != .qrRead {
                    Label(ConverterPreviewer.sizeLine(from: r.sourceSize, to: r.estimatedSize ?? r.outputSize), systemImage: "scalemass")
                        .font(.ui(11.5)).foregroundStyle(Theme.text2)
                }
                if let note = r.note {
                    Text(note).font(.ui(11.5)).foregroundStyle(Theme.text3).lineLimit(2)
                }
                Spacer()
                let shown = ConverterPreviewFiles.expand(r.outputs)
                if !r.demo, !shown.isEmpty {
                    Button("Ouvrir l'aperçu") {
                        NSWorkspace.shared.open(shown[min(preview.outputIndex, shown.count - 1)])
                    }
                    .buttonStyle(SoftButtonStyle(small: true))
                    .help("Ouvre le fichier d'aperçu (temporaire) dans son app, pour le regarder en grand")
                }
            }
        }
    }

    private func placeholder(symbol: String, text: String, tint: Color = Theme.text3) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(tint)
            Text(text).font(.ui(12)).foregroundStyle(tint == Theme.text3 ? Theme.text3 : tint)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(Theme.bg.opacity(0.5)))
    }
}

/// ◀ "2 sur 5" ▶
struct ConverterPager: View {
    var label: String
    var index: Int
    var count: Int
    var go: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { go((index - 1 + count) % count) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(label).font(.ui(11.5, .medium)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
            Button { go((index + 1) % count) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
        }
        .font(.ui(11, .semibold))
        .foregroundStyle(Theme.text2)
    }
}

/// A preview result made of folders (a PDF exported as images, pages cut one by one): the files inside, in order.
enum ConverterPreviewFiles {
    static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard FS.isDirectory(url.path) else { return [url] }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .prefix(200)
                .map { url.appendingPathComponent($0) }
        }
    }
}

/// Quick Look draws any file (image, PDF, video, sound, document): the same view as the space bar in the Finder.
/// Snapshots and the demo get a drawing instead.
struct ConverterPreviewSurface: View {
    var url: URL?
    var demo: Bool
    var demoAfter: Bool

    var body: some View {
        if demo || Snapshot.isActive {
            ConverterDemoArtwork(after: demoAfter, page: url.map { ["pdf", "docx", "txt", "md", "rtf", "html", "odt", "pages"].contains($0.pathExtension.lowercased()) } ?? false)
        } else if let url {
            ConverterQuickLook(url: url)
        } else {
            Color.clear
        }
    }
}

struct ConverterQuickLook: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}

/// The demo's photo, before and after: the same picture, the "after" a little softer (JPEG, smaller).
struct ConverterDemoArtwork: View {
    var after: Bool
    /// A document or a PDF: a sheet of paper instead of a photo.
    var page = false

    var body: some View {
        if page { sheet } else { photo }
    }

    private var sheet: some View {
        ZStack {
            Theme.bg.opacity(0.6)
            HStack(spacing: 14) {
                ForEach(0..<(after ? 2 : 3), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(Color.white)
                        .frame(width: 130, height: 180)
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xD97757)).frame(width: 50 + CGFloat(i) * 10, height: 7)
                                ForEach(0..<8, id: \.self) { l in
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.black.opacity(0.16)).frame(width: l % 3 == 2 ? 70 : 104, height: 4)
                                }
                            }
                            .padding(12)
                        }
                }
            }
        }
    }

    private var photo: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xF4B266), Color(hex: 0xE0705A), Color(hex: 0x6A4C93)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0xFFE2A8).opacity(0.95)).frame(width: 70).offset(y: 30)
            VStack(spacing: 0) {
                Spacer()
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 60))
                    p.addLine(to: CGPoint(x: 120, y: 10))
                    p.addLine(to: CGPoint(x: 200, y: 45))
                    p.addLine(to: CGPoint(x: 320, y: 0))
                    p.addLine(to: CGPoint(x: 520, y: 50))
                    p.addLine(to: CGPoint(x: 520, y: 120))
                    p.addLine(to: CGPoint(x: 0, y: 120))
                }
                .fill(Color(hex: 0x2C3A5A))
                .frame(height: 120)
            }
            if after {
                VStack {
                    HStack {
                        Spacer()
                        Text("JPEG · 82 %").font(.ui(10.5, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.45)))
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
        .saturation(after ? 0.92 : 1)
    }
}
