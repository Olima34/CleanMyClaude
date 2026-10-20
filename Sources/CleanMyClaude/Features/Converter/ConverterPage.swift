import SwiftUI
import AppKit

struct ConverterPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.converter.symbol, title: "Convertisseur",
                     subtitle: "Images, vidéos, audio, PDF, documents et archives : dépose, choisis, c'est fait. Tes originaux ne bougent jamais.",
                     tint: Theme.palette[1], seed: 71) {
                ConverterDestinationPicker()
            }
            if let message = model.message {
                Callout(symbol: "info.circle", title: "À savoir", text: message, tint: Theme.accent)
            }
            if model.operation == .qrGenerate {
                ConverterQRPanel()
            } else if model.files.isEmpty {
                ConverterEmptyState()
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ConverterFilesPanel()
                        .frame(width: 430)
                    VStack(spacing: 16) {
                        ConverterOperationPicker()
                        ConverterOptionsPanel()
                    }
                }
                if model.operation == .rename {
                    ConverterRenamePreviewPanel()
                } else if let op = model.operation, ConverterPreviewer.previews(op) {
                    ConverterPreviewPanel()
                }
            }
            if !model.jobs.isEmpty {
                ConverterQueuePanel()
            }
        }
    }
}

// MARK: - Destination

/// Where the results go: Téléchargements (by default), next to the originals, or a chosen folder.
struct ConverterDestinationPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        HStack(spacing: 9) {
            Image(systemName: model.destination.symbol)
                .font(.ui(13, .medium))
                .foregroundStyle(Theme.palette[1])
            VStack(alignment: .leading, spacing: 1) {
                Text("Enregistrer").font(.ui(10.5)).foregroundStyle(Theme.text3)
                BorderlessMenu {
                    Button("Dans Téléchargements") { model.destination = .downloads }
                    Button("À côté des originaux") { model.destination = .beside }
                    Divider()
                    Button("Choisir un dossier…") { model.chooseFolder() }
                } label: {
                    Text(model.destinationLabel).font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            if let folder = model.outputFolder {
                Button { NSWorkspace.shared.open(folder) } label: {
                    Image(systemName: "arrow.up.forward.square").font(.ui(12)).foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
                .help("Ouvrir ce dossier dans le Finder")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous).strokeBorder(Theme.border, lineWidth: Theme.line))
        .fixedSize()
    }
}

// MARK: - Empty state

struct ConverterEmptyState: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        let op = model.operation
        VStack(alignment: .leading, spacing: 16) {
            ConverterDropZone(title: op.map { "Dépose \(dropNoun($0)) à traiter" } ?? "Dépose tes fichiers ici",
                              subtitle: op.map { "\($0.commandTitle) · ou clique pour les choisir" } ?? "ou clique pour les choisir · un dossier marche aussi",
                              symbol: op?.symbol ?? "square.and.arrow.down.on.square") { urls in
                model.add(urls)
            }
            SectionLabel(text: "Ce que je sais faire")
            let cards = ConverterFamily.allCases
            ForEach(0..<2, id: \.self) { row in
                TileRow {
                    ForEach(cards[(row * 4)..<min(cards.count, row * 4 + 4)]) { family in
                        ConverterFamilyCard(family: family)
                    }
                    if row == 1 { ConverterFinderTipCard() }
                }
            }
            if model.ffmpegPath == nil && !DemoData.isEnabled {
                Text("MP3, MKV, WebM et WebP arrivent si tu installes ffmpeg (brew install ffmpeg) : macOS ne sait pas les créer seul.")
                    .font(.ui(11.5)).foregroundStyle(Theme.text3)
            }
        }
        .onAppear { model.checkTools() }
    }

    private func dropNoun(_ op: ConverterOperation) -> String {
        switch op.family {
        case .images: return "des images"
        case .videos: return "des vidéos"
        case .audio: return "des fichiers audio"
        case .pdf: return op == .pdfMerge ? "les PDF" : "un PDF"
        case .documents: return "des documents"
        case .files: return op == .archiveExtract ? "des archives" : "des fichiers"
        case .vision: return "des images ou des PDF"
        }
    }
}

struct ConverterFamilyCard: View {
    @Environment(AppModel.self) private var app
    var family: ConverterFamily

    var body: some View {
        let model = app.converter
        Card(padding: 16) {
            HStack(spacing: 10) {
                IconBadge(symbol: family.symbol, tint: family.tint, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(family.title).font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                    Text(family.subtitle).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
            }
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(family.operations) { op in
                    Button { model.focus(op) } label: {
                        Text(op.title)
                            .font(.ui(11.5, model.operation == op ? .semibold : .regular))
                            .foregroundStyle(model.operation == op ? Theme.ink(on: family.tint) : Theme.text2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PillShape().fill(model.operation == op ? family.tint : Theme.track))
                            .contentShape(PillShape())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ConverterFinderTipCard: View {
    var body: some View {
        Card(padding: 16) {
            HStack(spacing: 10) {
                IconBadge(symbol: "cursorarrow.click.2", tint: Theme.text2, size: 30)
                Text("Depuis le Finder").font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
            }
            Text("Clic droit › Services › Convertir avec \(AppEdition.name), ou dépose sur l'icône du Dock. Et ⌥Espace › « compresser une vidéo ».")
                .font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Files

struct ConverterFilesPanel: View {
    @Environment(AppModel.self) private var app
    @State private var targeted = false

    var body: some View {
        let model = app.converter
        let op = model.operation
        Panel(title: Fmt.plural(model.files.count, "fichier", "fichiers"), subtitle: subtitle(model), symbol: "tray.full", tint: Theme.palette[1]) {
            HStack(spacing: 6) {
                Button("Ajouter…") { choose(model) }.buttonStyle(SoftButtonStyle(small: true))
                Button("Vider") { model.clearFiles() }.buttonStyle(SoftButtonStyle(small: true))
            }
        } content: {
            VStack(spacing: 8) {
                let rows = VStack(spacing: 1) {
                    ForEach(model.files) { file in
                        ConverterFileRow(file: file, ignored: op.map { !$0.accepts.contains(file.kind) } ?? false,
                                         ordered: op?.isOrdered ?? false)
                    }
                }
                if model.files.count > 9 {
                    ScrollArea { rows }.frame(height: 430)
                } else {
                    rows
                }
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle").font(.ui(11))
                    Text("Dépose d'autres fichiers ici").font(.ui(11.5))
                }
                .foregroundStyle(targeted ? Theme.accent : Theme.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: Theme.r(9)).strokeBorder(targeted ? Theme.accent : Theme.border,
                                                                             style: StrokeStyle(lineWidth: Theme.line, dash: [5, 4])))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(ConverterDropTarget(targeted: $targeted) { model.add($0) })
    }

    private func subtitle(_ model: ConverterModel) -> String {
        var counts: [ConverterKind: Int] = [:]
        for k in model.kinds { counts[k, default: 0] += 1 }
        let parts = ConverterKind.allCases.compactMap { k -> String? in
            guard let n = counts[k] else { return nil }
            return n == 1 ? "1 \(k.singular)" : "\(n) \(k.plural)"
        }
        return (parts + [Fmt.bytes(model.totalSize)]).joined(separator: " · ")
    }

    private func choose(_ model: ConverterModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Ajouter"
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

struct ConverterFileRow: View {
    @Environment(AppModel.self) private var app
    var file: ConverterFile
    var ignored: Bool
    var ordered: Bool
    @State private var hovering = false

    var body: some View {
        let model = app.converter
        HStack(spacing: 10) {
            FileIcon(path: file.url.path, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    Image(systemName: file.kind.symbol).font(.ui(9.5, .semibold)).foregroundStyle(file.kind.tint)
                    Text(details).font(.ui(10.5)).foregroundStyle(Theme.text3).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if ignored {
                Text("ignoré").font(.ui(10.5)).foregroundStyle(Theme.text3)
            }
            if ordered && !ignored && (hovering || Snapshot.isActive) {
                HStack(spacing: 2) {
                    arrow("chevron.up") { model.move(file, by: -1) }
                    arrow("chevron.down") { model.move(file, by: 1) }
                }
            }
            Button { model.remove(file) } label: {
                Image(systemName: "xmark").font(.ui(9.5, .bold)).foregroundStyle(Theme.text3)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .help("Retirer de la liste")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(hovering ? Theme.hover.opacity(0.6) : .clear))
        .opacity(ignored ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var details: String {
        var parts = [file.kind == .folder ? "Dossier" : (file.ext.isEmpty ? file.kind.title : file.ext)]
        if let d = file.detail { parts.append(d) }
        if file.size > 0 { parts.append(Fmt.bytes(file.size)) }
        return parts.joined(separator: " · ")
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(9.5, .bold)).foregroundStyle(Theme.text2)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: Theme.r(5)).fill(Theme.track))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Operation

struct ConverterOperationPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        var ops = model.availableOperations
        if let current = model.operation, current != .qrGenerate, !ops.contains(current) { ops.insert(current, at: 0) }
        let total = model.files.count
        return Panel(title: "Que veux-tu faire ?", symbol: "wand.and.stars", tint: Theme.palette[1]) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(ops) { op in
                    let n = model.targets(for: op).count
                    ConverterChip(title: op.title, symbol: op.symbol, selected: model.operation == op, tint: op.family.tint,
                                  badge: n < total && n > 0 ? "\(n)" : nil) {
                        model.focus(op)
                    }
                }
            }
        }
    }
}

// MARK: - Rename preview

struct ConverterRenamePreviewPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let preview = app.converter.renamePreview
        let changing = preview.filter { !$0.unchanged }.count
        let conflicts = preview.filter(\.conflict).count
        Panel(title: "Aperçu", subtitle: changing == 0 ? "Aucun nom ne change pour l'instant." :
                "\(Fmt.plural(changing, "fichier changera", "fichiers changeront")) de nom" +
                (conflicts > 0 ? " · \(Fmt.plural(conflicts, "nom déjà pris", "noms déjà pris")) : un numéro sera ajouté" : ""),
              symbol: "eye", tint: ConverterFamily.files.tint) {
            let rows = VStack(spacing: 1) {
                ForEach(preview.prefix(300)) { p in
                    HStack(spacing: 10) {
                        Text(p.url.lastPathComponent)
                            .font(.ui(12)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").font(.ui(10, .semibold)).foregroundStyle(p.unchanged ? Theme.text3 : Theme.accent)
                        HStack(spacing: 6) {
                            Text(p.newName)
                                .font(.ui(12, p.unchanged ? .regular : .medium))
                                .foregroundStyle(p.unchanged ? Theme.text3 : Theme.text)
                                .lineLimit(1).truncationMode(.middle)
                            if p.conflict { Tag(text: "nom pris", symbol: "exclamationmark.triangle", tint: Theme.warn, filled: true) }
                            if p.unchanged { Text("inchangé").font(.ui(10.5)).foregroundStyle(Theme.text3) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
            }
            if preview.count > 12 {
                ScrollArea { rows }.frame(height: 320)
            } else {
                rows
            }
        }
    }
}

// MARK: - Queue and results

struct ConverterQueuePanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        let active = model.activeJobs.count
        let finished = model.finishedJobs.count
        Panel(title: active > 0 ? "En cours" : "Terminé",
              subtitle: [active > 0 ? Fmt.plural(active, "tâche en attente ou en cours", "tâches en attente ou en cours") : nil,
                         finished > 0 ? Fmt.plural(finished, "résultat", "résultats") : nil].compactMap { $0 }.joined(separator: " · "),
              symbol: active > 0 ? "hourglass" : "checkmark.circle", tint: active > 0 ? Theme.accent : Theme.good) {
            HStack(spacing: 6) {
                if active > 0 {
                    Button("Tout annuler") { model.cancelAll() }.buttonStyle(SoftButtonStyle(small: true))
                }
                if finished > 0 {
                    Button("Effacer la liste") { model.clearFinished() }.buttonStyle(SoftButtonStyle(small: true))
                }
            }
        } content: {
            VStack(spacing: 6) {
                ForEach(model.jobs) { job in
                    ConverterJobRow(job: job)
                }
            }
        }
    }
}

struct ConverterJobRow: View {
    @Environment(AppModel.self) private var app
    var job: ConverterJob
    @State private var hovering = false

    var body: some View {
        let model = app.converter
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                stateIcon
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(job.title).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                        Tag(text: job.operation.title, symbol: job.operation.symbol, tint: job.operation.family.tint, filled: true)
                    }
                    Text(status).font(.ui(11)).foregroundStyle(statusColor).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing(model)
            }
            if job.state == .running {
                if let p = job.progress {
                    UsageBar(fraction: p, tint: job.operation.family.tint, height: 5)
                } else {
                    Text("Ce traitement ne donne pas d'avancement : patiente un instant…").font(.ui(10.5)).foregroundStyle(Theme.text3)
                }
            }
            if job.state == .done {
                if let text = job.output.text, !text.isEmpty { ConverterTextResult(job: job, text: text) }
                if !job.output.codes.isEmpty { ConverterCodesResult(codes: job.output.codes) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(hovering ? Theme.hover.opacity(0.45) : Theme.bg.opacity(0.5)))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var stateIcon: some View {
        Group {
            switch job.state {
            case .waiting:
                Image(systemName: "clock").foregroundStyle(Theme.text3)
            case .running:
                // The bar below tells how far along it is; the mascot shows that it works.
                ConverterSpinner()
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
            case .cancelled:
                Image(systemName: "slash.circle").foregroundStyle(Theme.text3)
            }
        }
        .font(.ui(16, .medium))
        .frame(width: 28, height: 28)
    }

    private var status: String {
        switch job.state {
        case .waiting: return "En attente · \(job.subtitle)"
        case .running:
            return job.progress.map { "\(Int(($0 * 100).rounded())) % · \(job.subtitle)" } ?? job.subtitle
        case .done:
            if job.operation == .rename {
                return job.undone ? "Renommage annulé : les anciens noms sont revenus." : "\(Fmt.plural(job.output.renamed.count, "fichier renommé", "fichiers renommés"))"
            }
            var parts: [String] = []
            if let first = job.output.files.first {
                parts.append(job.output.files.count > 1 ? "→ \(Fmt.plural(job.output.files.count, "fichier", "fichiers"))" : "→ \(first.lastPathComponent)")
            }
            if let note = job.output.note { parts.append(note) }
            if let d = job.duration, d >= 2 { parts.append("en \(Fmt.duration(d))") }
            return parts.isEmpty ? "Terminé" : parts.joined(separator: " · ")
        case .failed(let why): return why
        case .cancelled: return "Annulé : aucun fichier n'a été laissé à moitié écrit."
        }
    }

    private var statusColor: Color {
        if case .failed = job.state { return Theme.bad }
        return Theme.text3
    }

    @ViewBuilder
    private func trailing(_ model: ConverterModel) -> some View {
        switch job.state {
        case .waiting, .running:
            Button { model.cancel(job) } label: {
                Image(systemName: "xmark.circle.fill").font(.ui(15)).foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .help("Annuler")
        case .done:
            HStack(spacing: 8) {
                if job.output.size > 0 && job.inputSize > 0 && job.operation.showsSavings {
                    sizeChange
                } else if job.output.size > 0 && job.operation != .rename {
                    Text(Fmt.bytes(job.output.size)).font(.ui(11.5)).foregroundStyle(Theme.text2).monospacedDigit()
                }
                if job.operation == .rename && !job.undone && !job.output.renamed.isEmpty {
                    Button("Annuler le renommage") { model.undoRename(job) }.buttonStyle(SoftButtonStyle(small: true))
                }
                if !job.output.files.isEmpty {
                    Button("Afficher dans le Finder") { model.reveal(job.output.files) }.buttonStyle(SoftButtonStyle(small: true))
                    if job.output.files.count == 1, job.operation != .rename {
                        Button("Ouvrir") { model.open(job.output.files[0]) }.buttonStyle(SoftButtonStyle(small: true))
                    }
                }
                dismissButton(model)
            }
        case .failed, .cancelled:
            HStack(spacing: 8) {
                Button("Réessayer") { model.retry(job) }.buttonStyle(SoftButtonStyle(small: true))
                dismissButton(model)
            }
        }
    }

    private var sizeChange: some View {
        let before = job.inputSize, after = job.output.size
        let ratio = Double(after) / Double(max(1, before)) - 1
        return HStack(spacing: 6) {
            Text("\(Fmt.bytes(before)) → \(Fmt.bytes(after))").font(.ui(11.5)).foregroundStyle(Theme.text2).monospacedDigit()
            if abs(ratio) >= 0.01 {
                Tag(text: ratio < 0 ? "−\(Int((-ratio * 100).rounded())) %" : "+\(Int((ratio * 100).rounded())) %",
                    tint: ratio < 0 ? Theme.good : Theme.warn, filled: true)
            }
        }
    }

    private func dismissButton(_ model: ConverterModel) -> some View {
        Button { model.dismiss(job) } label: {
            Image(systemName: "xmark").font(.ui(9.5, .bold)).foregroundStyle(Theme.text3).frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.3)
        .help("Retirer de la liste")
    }
}

/// The text read by OCR, ready to copy or save.
struct ConverterTextResult: View {
    @Environment(AppModel.self) private var app
    var job: ConverterJob
    var text: String

    var body: some View {
        let model = app.converter
        VStack(alignment: .leading, spacing: 8) {
            ScrollArea {
                Group {
                    if Snapshot.isActive {
                        Text(text)
                    } else {
                        Text(text).textSelection(.enabled)
                    }
                }
                .font(.ui(12))
                .foregroundStyle(Theme.text)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(maxHeight: 190)
            .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(9)).strokeBorder(Theme.border, lineWidth: Theme.line))
            HStack(spacing: 8) {
                Button("Copier le texte") { model.copy(text) }.buttonStyle(SoftButtonStyle(prominent: true, small: true))
                Button("Enregistrer en .txt") { model.saveText(job) }.buttonStyle(SoftButtonStyle(small: true))
                Text("\(Fmt.plural(text.split(whereSeparator: { $0.isWhitespace }).count, "mot", "mots")) · \(Fmt.plural(text.count, "caractère", "caractères"))")
                    .font(.ui(11)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.leading, 40)
    }
}

struct ConverterCodesResult: View {
    @Environment(AppModel.self) private var app
    var codes: [String]

    var body: some View {
        let model = app.converter
        VStack(alignment: .leading, spacing: 6) {
            ForEach(codes, id: \.self) { code in
                HStack(spacing: 8) {
                    Image(systemName: "qrcode").font(.ui(11)).foregroundStyle(ConverterFamily.vision.tint)
                    Text(code).font(.mono(11.5)).foregroundStyle(Theme.text).lineLimit(2).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let url = URL(string: code), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        Button("Ouvrir le lien") { if !DemoData.isEnabled { NSWorkspace.shared.open(url) } }
                            .buttonStyle(SoftButtonStyle(small: true))
                    }
                    Button("Copier") { model.copy(code) }.buttonStyle(SoftButtonStyle(small: true))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Theme.card))
            }
        }
        .padding(.leading, 40)
    }
}

// MARK: - QR code

struct ConverterQRPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.converter
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "Créer un QR code", subtitle: ConverterOperation.qrGenerate.explanation, symbol: "qrcode", tint: ConverterFamily.vision.tint) {
                Button("Retour") { model.operation = model.files.isEmpty ? nil : ConverterOperation.suggested(for: model.kinds) }
                    .buttonStyle(SoftButtonStyle(small: true))
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    ConverterTextField(text: $model.qrText, prompt: "https://… ou n'importe quel texte", symbol: "text.cursor")
                    ConverterOptionRow(label: "Modèles") {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ConverterChip(title: "Lien", symbol: "link", selected: false) { model.qrText = "https://" }
                            ConverterChip(title: "Wi-Fi", symbol: "wifi", selected: false) { model.qrText = "WIFI:T:WPA;S:NomDuRéseau;P:MotDePasse;;" }
                            ConverterChip(title: "E-mail", symbol: "envelope", selected: false) { model.qrText = "mailto:prenom@exemple.fr" }
                            ConverterChip(title: "Téléphone", symbol: "phone", selected: false) { model.qrText = "tel:+33600000000" }
                            ConverterChip(title: "SMS", symbol: "message", selected: false) { model.qrText = "SMSTO:+33600000000:Bonjour !" }
                        }
                    }
                    let bytes = model.qrText.utf8.count
                    Text(bytes > ConverterVision.qrCapacity ? "Trop long pour un QR code : \(Fmt.int(bytes)) octets sur \(Fmt.int(ConverterVision.qrCapacity)) possibles."
                                                            : "\(Fmt.int(bytes)) octets sur \(Fmt.int(ConverterVision.qrCapacity)) possibles · correction d'erreur moyenne (15 %)")
                        .font(.ui(11)).foregroundStyle(bytes > ConverterVision.qrCapacity ? Theme.warn : Theme.text3)
                    Text("Pour lire un QR code, dépose une image ou un PDF puis choisis « Lire un QR code ».")
                        .font(.ui(11.5)).foregroundStyle(Theme.text3)
                }
            }
            Card(padding: 18) {
                VStack(spacing: 14) {
                    ZStack {
                        // A QR code needs a light margin to be scanned, whatever the theme: white under the code only.
                        RoundedRectangle(cornerRadius: Theme.r(12)).fill(model.qrImage == nil ? Theme.bg.opacity(0.6) : Color.white)
                        if let image = model.qrImage {
                            Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit().padding(6)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "qrcode").font(.ui(40, .light))
                                Text("Tape un texte").font(.ui(11.5))
                            }
                            .foregroundStyle(Theme.text3)
                        }
                    }
                    .frame(width: 220, height: 220)
                    HStack(spacing: 8) {
                        Button("Copier l'image") { model.copyQR() }.buttonStyle(SoftButtonStyle(small: true))
                        Button("Enregistrer en PNG…") { model.saveQR() }.buttonStyle(SoftButtonStyle(prominent: true, small: true))
                    }
                    .disabled(model.qrImage == nil)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 290)
        }
    }
}
