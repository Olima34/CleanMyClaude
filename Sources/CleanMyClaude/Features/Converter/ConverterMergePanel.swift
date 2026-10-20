import SwiftUI
import PDFKit
import ImageIO

/// The settings of a merge: the order (dragged by the handle, or the arrows), the pages kept from each PDF, the name,
/// a bookmark per document and the blank pages for double-sided printing.
struct ConverterMergeOptions: View {
    @Environment(AppModel.self) private var app
    @State private var dragged: UUID?
    @State private var dragOffset: CGFloat = 0

    /// Height of a row plus the space under it: what a drag has to cover to move a document by one place.
    static let step: CGFloat = 62

    var body: some View {
        @Bindable var model = app.converter
        let parts = model.targets(for: .pdfMerge)
        let first = parts.first?.url
        VStack(alignment: .leading, spacing: 16) {
            ConverterOptionRow(label: "Ordre et pages", hint: parts.count > 1 ? "glisse par la poignée pour changer l'ordre" : nil) {
                VStack(spacing: 6) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, file in
                        ConverterMergeRow(file: file, index: index, count: parts.count, dragging: dragged == file.id,
                                          drag: drag(file, index: index, count: parts.count))
                            .offset(y: dragged == file.id ? dragOffset : 0)
                            .zIndex(dragged == file.id ? 1 : 0)
                    }
                }
            }
            ConverterOptionRow(label: "Nom du PDF", hint: "enregistré " + model.destinationLabel.prefix(1).lowercased() + model.destinationLabel.dropFirst()) {
                ConverterTextField(text: $model.options.mergeName,
                                   prompt: first.map { ConverterPDFEngine.mergeName("", first: $0) } ?? "Document fusionné", symbol: "doc")
            }
            VStack(alignment: .leading, spacing: 9) {
                Toggle(isOn: $model.options.mergeBookmarks) {
                    label("Un signet par document", "Le nom de chaque fichier dans la barre latérale d'Aperçu, ses propres signets dessous.")
                }
                Toggle(isOn: $model.options.mergeDuplex) {
                    label("Chaque document commence sur une nouvelle feuille",
                          "Une page blanche après un document impair, pour l'imprimer en recto verso.")
                }
            }
            .switchToggles()
            if parts.contains(where: { $0.kind == .image }) {
                ConverterOptionRow(label: "Pages des images") {
                    HStack(spacing: 6) {
                        ConverterChip(title: "Taille de l'image", selected: model.options.pageSize == .image) { model.options.pageSize = .image }
                        ConverterChip(title: "A4 avec marges", selected: model.options.pageSize == .a4) { model.options.pageSize = .a4 }
                    }
                }
            }
            if let problem = model.mergeProblem {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.ui(11.5, .medium)).foregroundStyle(Theme.warn)
                    Text(problem).font(.ui(12)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                }
            } else if let total = model.mergePageCount {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc").font(.ui(11.5, .medium)).foregroundStyle(Theme.text3)
                    Text("\(Fmt.plural(total, "page", "pages")) au total"
                         + (model.options.mergeBookmarks ? " · \(Fmt.plural(parts.count, "signet", "signets"))" : ""))
                        .font(.ui(12)).foregroundStyle(Theme.text2)
                }
            }
        }
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.ui(12)).foregroundStyle(Theme.text)
            Text(detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The handle follows the pointer; let go, the document takes the place it is over.
    private func drag(_ file: ConverterFile, index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                dragged = file.id
                let top = -CGFloat(index) * Self.step, bottom = CGFloat(count - 1 - index) * Self.step
                dragOffset = min(bottom, max(top, value.translation.height))
            }
            .onEnded { value in
                let moved = Int((dragOffset / Self.step).rounded())
                withAnimation(.easeOut(duration: 0.18)) {
                    app.converter.move(file.id, to: index + moved, among: .pdfMerge)
                    dragged = nil
                    dragOffset = 0
                }
            }
    }
}

/// A document of the merge: its place, its first page, and for a PDF the pages it brings.
struct ConverterMergeRow<Drag: Gesture>: View {
    @Environment(AppModel.self) private var app
    var file: ConverterFile
    var index: Int
    var count: Int
    var dragging: Bool
    var drag: Drag

    var body: some View {
        let model = app.converter
        let spec = model.mergePages(file)
        let kept = file.pages.flatMap { ConverterPDFEngine.parsePages(spec, count: $0) }
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.ui(11, .semibold)).foregroundStyle(Theme.text3)
                .frame(width: 18, height: 40)
                .contentShape(Rectangle())
                .gesture(drag)
                .help("Glisse pour changer l'ordre")
            Text("\(index + 1)")
                .font(.ui(10.5, .semibold)).monospacedDigit().foregroundStyle(Theme.text2)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.track))
            ConverterPageThumb(url: file.url, kind: file.kind)
                .frame(width: 30, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                Group {
                    if file.kind == .image {
                        Text("Image · devient une page")
                    } else if let pages = file.pages {
                        if spec.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(pages == 1 ? "1 page" : "\(pages) pages, toutes gardées")
                        } else if let kept, !kept.isEmpty {
                            Text("\(Fmt.plural(kept.count, "page gardée", "pages gardées")) sur \(pages)").foregroundStyle(Theme.good)
                        } else {
                            Text("Liste non comprise (\(Fmt.plural(pages, "page", "pages")))").foregroundStyle(Theme.warn)
                        }
                    } else {
                        Text("Lecture des pages…")
                    }
                }
                .font(.ui(10.5)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            Spacer(minLength: 6)
            if file.kind == .pdf {
                ConverterTextField(text: Binding(get: { model.mergePages(file) }, set: { model.setMergePages(file, $0) }),
                                   prompt: "Toutes", symbol: "number", mono: true)
                    .frame(width: 128)
                    .help("Les pages à garder, par exemple 1-3, 5, 8-")
            }
            HStack(spacing: 2) {
                arrow("chevron.up", enabled: index > 0) { model.move(file.id, to: index - 1, among: .pdfMerge) }
                arrow("chevron.down", enabled: index < count - 1) { model.move(file.id, to: index + 1, among: .pdfMerge) }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: ConverterMergeOptions.step - 6)
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(dragging ? Theme.cardRaised : Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(dragging ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: Theme.line))
        .themedShadow(color: .black.opacity(dragging ? 0.18 : 0), radius: 8, y: 3)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(9.5, .bold)).foregroundStyle(Theme.text2)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: Theme.r(5)).fill(Theme.track))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// The first page of a PDF or the image itself, small, read in the background. The demo draws a sheet instead.
struct ConverterPageThumb: View {
    var url: URL
    var kind: ConverterKind
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFit()
            } else if DemoData.isEnabled || Snapshot.isActive {
                ConverterDemoSheet(kind: kind, seed: url.lastPathComponent.count)
            } else {
                RoundedRectangle(cornerRadius: Theme.r(3)).fill(Theme.track)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(3)))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(3)).strokeBorder(Theme.border, lineWidth: Theme.line))
        .task(id: url) {
            guard !DemoData.isEnabled, !Snapshot.isActive else { return }
            let target = url, isImage = kind == .image
            image = await Task.detached(priority: .utility) { Self.thumbnail(target, isImage: isImage) }.value
        }
    }

    nonisolated static func thumbnail(_ url: URL, isImage: Bool) -> CGImage? {
        if isImage {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 120,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        }
        guard let doc = PDFDocument(url: url), !doc.isLocked, let page = doc.page(at: 0) else { return nil }
        return ConverterPDFEngine.render(page, dpi: 30, maxSide: 120)
    }
}

/// A sheet drawn for the demo: a page of text, or a photo.
struct ConverterDemoSheet: View {
    var kind: ConverterKind
    var seed: Int

    var body: some View {
        // Document content, not interface: a white sheet whatever the theme.
        ZStack(alignment: .topLeading) {
            if kind == .image {
                LinearGradient(colors: [Color(hex: 0xF2A65A), Color(hex: 0xD9576B), Color(hex: 0x5B4B8A)], startPoint: .top, endPoint: .bottom)
            } else {
                Color.white
                VStack(alignment: .leading, spacing: 2.5) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0xD97757)).frame(width: 12, height: 2.5)
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.18))
                            .frame(width: (i + seed) % 3 == 2 ? 14 : 22, height: 1.5)
                    }
                }
                .padding(4)
            }
        }
    }
}
