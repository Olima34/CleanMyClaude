import SwiftUI

/// The settings of the selected operation.
struct ConverterOptionsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        if let op = model.operation {
            let count = model.targets(for: op).count
            Panel(title: op.commandTitle, subtitle: op.explanation, symbol: op.symbol, tint: op.family.tint) {
                VStack(alignment: .leading, spacing: 16) {
                    if count < op.minimumCount {
                        Callout(symbol: "tray", title: count == 0 ? "Aucun fichier pour cette opération" : "Il en faut au moins \(op.minimumCount)",
                                text: "Ajoute des \(acceptedText(op)) à la liste.", tint: Theme.warn)
                    }
                    options(op)
                    if count >= op.minimumCount && op != .rename {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right").font(.ui(10.5, .semibold)).foregroundStyle(Theme.text3)
                            Text("\(op.isBatch ? Fmt.plural(count, "fichier", "fichiers") + " → 1 résultat" : Fmt.plural(count, "fichier", "fichiers")) · \(ConverterModel.summary(op, model.options, qualityApplies: model.qualityApplies(op)))")
                                .font(.ui(11.5)).foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
        }
    }

    private func acceptedText(_ op: ConverterOperation) -> String {
        let kinds = ConverterKind.allCases.filter { op.accepts.contains($0) }
        return kinds.count > 4 ? "fichiers" : kinds.map(\.plural).joined(separator: " ou ")
    }

    @ViewBuilder
    private func options(_ op: ConverterOperation) -> some View {
        @Bindable var model = app.converter
        switch op {
        case .imageConvert:
            ConverterOptionRow(label: "Format") {
                formatChips(selection: $model.options.imageFormat, includeSame: false)
            }
            if model.options.imageFormat?.lossy ?? true { qualityRow($model.options.imageQuality) }
            Toggle(isOn: $model.options.stripOnConvert) {
                Text("Retirer aussi la localisation et les métadonnées").font(.ui(12)).foregroundStyle(Theme.text)
            }
            .switchToggles()
        case .imageResize:
            ConverterOptionRow(label: "Côté le plus long", hint: "les images plus petites ne sont pas agrandies") {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach([4096, 3000, 2048, 1600, 1280, 1024, 800, 512], id: \.self) { n in
                        ConverterChip(title: "\(Fmt.int(n)) px", selected: model.options.maxSide == n) { model.options.maxSide = n }
                    }
                }
            }
            ConverterOptionRow(label: "Format") { formatChips(selection: $model.options.resizeFormat, includeSame: true) }
            if model.qualityApplies(op) { qualityRow($model.options.imageQuality) }
        case .imageCompress:
            if model.qualityApplies(op) { qualityRow($model.options.imageQuality) }
            ConverterOptionRow(label: "Format", hint: "le HEIC est deux fois plus léger que le JPEG") {
                formatChips(selection: $model.options.compressFormat, includeSame: true, lossyOnly: true)
            }
            losslessNote(op)
            ConverterOptionRow(label: "Réduire aussi la taille") {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach([0, 3000, 2048, 1600, 1280], id: \.self) { n in
                        ConverterChip(title: n == 0 ? "Non" : "\(Fmt.int(n)) px", selected: model.options.compressMaxSide == n) {
                            model.options.compressMaxSide = n
                        }
                    }
                }
            }
        case .imageStrip:
            ConverterOptionRow(label: "Ce qui part") {
                HStack(spacing: 8) {
                    ConverterChoiceCard(title: ConverterStripMode.gps.title, subtitle: "La position GPS ; le reste (date, appareil) reste",
                                        selected: model.options.stripMode == .gps) { model.options.stripMode = .gps }
                    ConverterChoiceCard(title: ConverterStripMode.all.title, subtitle: "GPS, appareil, date, logiciel… seule l'orientation reste",
                                        selected: model.options.stripMode == .all) { model.options.stripMode = .all }
                }
            }
            note("checkmark.seal", "Sans recompression quand le format le permet (JPEG, PNG, TIFF, HEIC pour le GPS) : les pixels restent identiques. Sinon, réencodage en qualité maximale, et je vérifie toujours le résultat.")
        case .imagesToPDF:
            ConverterOptionRow(label: "Pages") {
                HStack(spacing: 6) {
                    ForEach(ConverterPageSize.allCases) { s in
                        ConverterChip(title: s.title, selected: model.options.pageSize == s) { model.options.pageSize = s }
                    }
                }
            }
            qualityRow($model.options.imageQuality, label: "Qualité des photos")
        case .videoCompress:
            ConverterOptionRow(label: "Réglage") {
                VStack(spacing: 8) {
                    ForEach(Array(stride(from: 0, to: ConverterVideoPreset.allCases.count, by: 2)), id: \.self) { i in
                        HStack(spacing: 8) {
                            ForEach(ConverterVideoPreset.allCases[i..<min(i + 2, ConverterVideoPreset.allCases.count)]) { p in
                                ConverterChoiceCard(title: p.title, subtitle: p.subtitle, selected: model.options.videoPreset == p,
                                                    tint: op.family.tint) { model.options.videoPreset = p }
                            }
                        }
                    }
                }
            }
            ConverterOptionRow(label: "Fichier") {
                HStack(spacing: 6) {
                    ForEach([ConverterVideoContainer.mp4, .mov]) { c in
                        ConverterChip(title: c.name, selected: model.options.compressContainer == c) { model.options.compressContainer = c }
                    }
                }
            }
        case .videoContainer:
            ConverterOptionRow(label: "Convertir en") {
                HStack(spacing: 6) {
                    ForEach(model.containers) { c in
                        ConverterChip(title: c.name + (c.viaFFmpeg ? " · ffmpeg" : ""), selected: model.options.container == c) {
                            model.options.container = c
                        }
                    }
                }
            }
            if model.ffmpegPath == nil && !DemoData.isEnabled {
                note("shippingbox", "MKV et WebM arrivent si tu installes ffmpeg (brew install ffmpeg).")
            }
        case .videoAudio:
            note("music.note", "La piste son est copiée en AAC (.m4a), lisible par Musique, iPhone et tous les lecteurs.")
        case .videoGIF:
            ConverterOptionRow(label: "Largeur") {
                HStack(spacing: 6) {
                    ForEach([320, 480, 640, 800], id: \.self) { w in
                        ConverterChip(title: "\(w) px", selected: model.options.gifWidth == w) { model.options.gifWidth = w }
                    }
                }
            }
            ConverterOptionRow(label: "Images par seconde") {
                HStack(spacing: 6) {
                    ForEach([8, 12, 15, 24], id: \.self) { f in
                        ConverterChip(title: "\(f)", selected: model.options.gifFPS == f) { model.options.gifFPS = f }
                    }
                }
            }
            ConverterOptionRow(label: "Durée", hint: "depuis le début de la vidéo") {
                HStack(spacing: 6) {
                    ForEach([5, 10, 30, 0], id: \.self) { s in
                        ConverterChip(title: s == 0 ? "Toute la vidéo" : "\(s) s", selected: model.options.gifSeconds == s) { model.options.gifSeconds = s }
                    }
                }
            }
        case .audioConvert:
            ConverterOptionRow(label: "Format") {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(model.audioFormats) { f in
                        ConverterChip(title: f.name, selected: model.options.audioFormat == f) { model.options.audioFormat = f }
                    }
                }
            }
            if model.options.audioFormat.lossy {
                ConverterOptionRow(label: "Débit") {
                    HStack(spacing: 6) {
                        ForEach([128, 192, 256, 320], id: \.self) { b in
                            ConverterChip(title: "\(b) kb/s", selected: model.options.audioBitrate == b) { model.options.audioBitrate = b }
                        }
                    }
                }
            }
            if model.ffmpegPath == nil && !DemoData.isEnabled {
                note("shippingbox", "Le MP3 arrive si tu installes ffmpeg (brew install ffmpeg) : macOS ne sait pas en créer seul.")
            }
        case .pdfMerge:
            ConverterMergeOptions()
        case .pdfSplit:
            pagesRow(required: true)
            ConverterOptionRow(label: "Résultat") {
                HStack(spacing: 6) {
                    ForEach(ConverterSplitMode.allCases) { m in
                        ConverterChip(title: m.title, selected: model.options.splitMode == m) { model.options.splitMode = m }
                    }
                }
            }
        case .pdfRotate:
            ConverterOptionRow(label: "Sens") {
                HStack(spacing: 6) {
                    ConverterChip(title: "90° à droite", symbol: "rotate.right", selected: model.options.rotation == 90) { model.options.rotation = 90 }
                    ConverterChip(title: "180°", symbol: "arrow.uturn.down", selected: model.options.rotation == 180) { model.options.rotation = 180 }
                    ConverterChip(title: "90° à gauche", symbol: "rotate.left", selected: model.options.rotation == 270) { model.options.rotation = 270 }
                }
            }
            pagesRow(required: false)
        case .pdfCompress:
            ConverterOptionRow(label: "Niveau") {
                HStack(spacing: 8) {
                    ForEach(ConverterPDFCompression.allCases) { c in
                        ConverterChoiceCard(title: c.title, subtitle: c.subtitle, selected: model.options.pdfCompression == c,
                                            tint: op.family.tint) { model.options.pdfCompression = c }
                    }
                }
            }
        case .pdfToImages:
            ConverterOptionRow(label: "Format") {
                HStack(spacing: 6) {
                    ForEach(ConverterRasterFormat.allCases) { f in
                        ConverterChip(title: f.name, selected: model.options.rasterFormat == f) { model.options.rasterFormat = f }
                    }
                }
            }
            ConverterOptionRow(label: "Résolution") {
                HStack(spacing: 6) {
                    ForEach([72, 150, 300], id: \.self) { d in
                        ConverterChip(title: "\(d) ppp", selected: model.options.rasterDPI == d) { model.options.rasterDPI = d }
                    }
                }
            }
            pagesRow(required: false)
        case .documentConvert:
            ConverterOptionRow(label: "Convertir en") {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(ConverterDocFormat.allCases) { f in
                        ConverterChip(title: f.name, selected: model.options.docFormat == f) { model.options.docFormat = f }
                    }
                }
            }
            if model.targets(for: op).contains(where: { $0.kind == .markdown }) {
                note("number", "Le Markdown devient une page HTML soignée (thème clair et sombre) ou un PDF A4 mis en page.")
            }
        case .archiveZip:
            ConverterOptionRow(label: "Archives") {
                HStack(spacing: 6) {
                    ForEach(ConverterZipMode.allCases) { m in
                        ConverterChip(title: m.title, selected: model.options.zipMode == m) { model.options.zipMode = m }
                    }
                }
            }
        case .archiveExtract:
            note("folder.badge.plus", "ZIP, TAR, GZ, BZ2, XZ, 7Z et RAR : chaque archive s'ouvre dans un nouveau dossier, rien n'est écrasé.")
        case .rename:
            ConverterRenameOptions()
        case .ocr:
            note("character.bubble", "Reconnaissance sur ton Mac (rien n'est envoyé), en français et en anglais. Les PDF qui contiennent déjà du texte le donnent directement.")
        case .qrRead:
            note("qrcode.viewfinder", "QR codes, codes-barres EAN, Aztec, PDF417… Le contenu s'affiche avec un bouton pour le copier.")
        case .qrGenerate:
            EmptyView()
        }
    }

    /// "Même format" on a PNG (or a TIFF, a GIF…): lossless, the quality changes nothing. Said instead of a useless slider.
    @ViewBuilder
    private func losslessNote(_ op: ConverterOperation) -> some View {
        let model = app.converter
        let formats = model.writtenFormats(op)
        let lossless = formats.filter { !$0.lossy }
        if model.chosenImageFormat(op) == nil, !lossless.isEmpty {
            let names = lossless.map(\.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", ")
            let n = lossless.count
            note("info.circle", n == formats.count
                 ? "\(names) : format sans perte, la qualité n'y change rien. Choisis JPEG ou HEIC pour vraiment alléger."
                 : "La qualité ne s'applique pas \(n == 1 ? "à l'image" : "aux \(n) images") en \(names), sans perte : choisis JPEG ou HEIC pour vraiment \(n == 1 ? "l'alléger" : "les alléger").")
        }
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.ui(11.5, .medium)).foregroundStyle(Theme.text3).frame(width: 16)
            Text(text).font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func qualityRow(_ value: Binding<Double>, label: String = "Qualité") -> some View {
        ConverterOptionRow(label: label, hint: "\(Int((value.wrappedValue * 100).rounded())) %") {
            HStack(spacing: 10) {
                Text("Léger").font(.ui(11)).foregroundStyle(Theme.text3)
                ConverterSlider(value: value, range: 0.3...1)
                Text("Fidèle").font(.ui(11)).foregroundStyle(Theme.text3)
            }
        }
    }

    private func formatChips(selection: Binding<ConverterImageFormat?>, includeSame: Bool, lossyOnly: Bool = false) -> some View {
        let formats = app.converter.imageFormats.filter { !lossyOnly || $0.lossy }
        return FlowLayout(spacing: 6, lineSpacing: 6) {
            if includeSame {
                ConverterChip(title: "Même format", selected: selection.wrappedValue == nil) { selection.wrappedValue = nil }
            }
            ForEach(formats) { f in
                ConverterChip(title: f.name + (f.viaFFmpeg ? " · ffmpeg" : ""), selected: selection.wrappedValue == f) { selection.wrappedValue = f }
            }
        }
    }

    private func pagesRow(required: Bool) -> some View {
        @Bindable var model = app.converter
        let files = model.targets(for: .pdfSplit)
        let counts = files.compactMap(\.pages)
        let smallest = counts.min()
        let parsed = smallest.flatMap { ConverterPDFEngine.parsePages(model.options.pdfPages, count: $0) }
        let empty = model.options.pdfPages.trimmingCharacters(in: .whitespaces).isEmpty
        return ConverterOptionRow(label: "Pages", hint: empty ? (required ? "toutes, ou par exemple 1-3, 5, 8-" : "toutes") : nil) {
            VStack(alignment: .leading, spacing: 5) {
                ConverterTextField(text: $model.options.pdfPages, prompt: "Toutes les pages · ex. 1-3, 5, 8-", symbol: "number", mono: true)
                if !empty {
                    if let parsed, !parsed.isEmpty {
                        Text("\(Fmt.plural(parsed.count, "page", "pages")) : \(ConverterPDFEngine.describePages(parsed))")
                            .font(.ui(11)).foregroundStyle(Theme.good)
                    } else if smallest != nil {
                        Text("Je ne comprends pas cette liste (le PDF le plus court a \(Fmt.plural(smallest!, "page", "pages"))).")
                            .font(.ui(11)).foregroundStyle(Theme.warn)
                    }
                }
            }
        }
    }
}

/// Pattern, numbering, find and replace, case.
struct ConverterRenameOptions: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.converter
        VStack(alignment: .leading, spacing: 16) {
            ConverterOptionRow(label: "Nouveau nom", hint: "l'extension est gardée") {
                VStack(alignment: .leading, spacing: 7) {
                    ConverterTextField(text: $model.options.rename.pattern, prompt: "{nom}", symbol: "character.cursor.ibeam", mono: true)
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(ConverterRename.tokens, id: \.token) { t in
                            Button { model.options.rename.pattern += t.token } label: {
                                HStack(spacing: 4) {
                                    Text(t.token).font(.mono(11, .medium)).foregroundStyle(Theme.accent)
                                    Text(t.label).font(.ui(10.5)).foregroundStyle(Theme.text3)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: Theme.r(6)).fill(Theme.accent.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ConverterOptionRow(label: "Remplacer") {
                    ConverterTextField(text: $model.options.rename.find, prompt: "ce texte…")
                }
                ConverterOptionRow(label: "Par") {
                    ConverterTextField(text: $model.options.rename.replace, prompt: "(rien)")
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ConverterOptionRow(label: "Premier numéro") {
                    ConverterStepper(value: $model.options.rename.start, range: 0...9999)
                }
                .fixedSize()
                ConverterOptionRow(label: "Casse") {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(ConverterCase.allCases) { c in
                            ConverterChip(title: c.title, selected: model.options.rename.caseMode == c) { model.options.rename.caseMode = c }
                        }
                    }
                }
            }
            Toggle(isOn: $model.options.rename.lowercaseExtension) {
                Text("Extension en minuscules (.JPG → .jpg)").font(.ui(12)).foregroundStyle(Theme.text)
            }
            .switchToggles()
        }
    }
}
