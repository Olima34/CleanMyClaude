import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FillSignPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.fillSign
        Group {
            if let doc = model.document {
                FillSignWorkspace(document: doc)
            } else {
                FillSignHome()
            }
        }
        .overlay(alignment: .top) {
            if model.pad != nil {
                FillSignPadOverlay()
            }
        }
    }
}

// MARK: - Home

/// No document yet: where to drop one, what the module does, the signatures kept.
struct FillSignHome: View {
    @Environment(AppModel.self) private var app

    static let types: [UTType] = [.pdf, .image, .rtf, .plainText] + ["docx", "doc", "pages", "odt", "md"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        let model = app.fillSign
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.fillsign.symbol, title: "Remplir et signer",
                     subtitle: "Un PDF, un formulaire ou la photo d'un document : remplis ses champs, écris où tu veux, signe et paraphe, puis enregistre une copie. L'original ne bouge pas.",
                     tint: FillSignStyle.tint, seed: 29)
            if let message = model.message {
                Callout(symbol: "exclamationmark.triangle", title: "Impossible d'ouvrir ce document", text: message, tint: Theme.warn)
            }
            if let name = model.opening {
                Card(padding: 18) {
                    HStack(spacing: 14) {
                        BusyMascot(.reading, pixel: 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("J'ouvre « \(name) »…").font(.serif(18)).foregroundStyle(Theme.text)
                            Text("Je lis ses pages et cherche ses champs de formulaire.").font(.ui(12)).foregroundStyle(Theme.text3)
                        }
                        Spacer()
                    }
                }
            }
            if let url = model.passwordFor {
                FillSignPasswordCard(url: url)
            }
            if let url = model.conversionFor {
                Card(padding: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        IconBadge(symbol: "doc.text", tint: Theme.accent, size: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("« \(url.lastPathComponent) » doit d'abord devenir un PDF").font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                            Text("Le Convertisseur en fait un PDF fidèle en un clic ; ouvre-le ensuite ici pour le remplir et le signer.")
                                .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Button("Convertir en PDF") { model.convertFirst() }.buttonStyle(SoftButtonStyle(prominent: true, small: true))
                                Button("Annuler") { model.conversionFor = nil }.buttonStyle(SoftButtonStyle(small: true))
                            }
                            .padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            DropZone(title: "Dépose le document à remplir ou à signer", subtitle: "ou clique pour le choisir · PDF, photo ou scan (JPEG, PNG, HEIC)",
                     symbol: "doc.badge.plus", allowedTypes: Self.types) { urls in
                if let url = urls.first { model.open(url) }
            }
            TileRow {
                feature("rectangle.and.pencil.and.ellipsis", "Remplir un formulaire",
                        "Les champs du PDF deviennent des cases où écrire, cocher ou choisir. ⇥ passe au suivant.")
                feature("character.cursor.ibeam", "Écrire n'importe où",
                        "Un PDF sans champs ou un scan : texte, coches, croix et date, là où tu cliques.")
                feature("signature", "Signer et parapher",
                        "Dessine, tape ou importe ta signature une fois ; elle reste sur ce Mac pour la prochaine fois.")
            }
            FillSignSignaturesPanel()
            Callout(symbol: "checkmark.seal", title: "Ce que vaut cette signature",
                    text: "C'est une signature simple, comme une signature manuscrite scannée : elle suffit pour un devis, un bail, un bon de commande ou une autorisation. Un acte qui exige une signature électronique qualifiée (notaire, certains marchés publics) passe par un service certifié.",
                    tint: FillSignStyle.tint)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconBadge(symbol: symbol, tint: FillSignStyle.tint, size: 26)
                    Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                }
                Text(text).font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A PDF protected by a password: asked here, kept only while it is open (the saved copy keeps the same password).
struct FillSignPasswordCard: View {
    @Environment(AppModel.self) private var app
    var url: URL
    @State private var password = ""

    var body: some View {
        let model = app.fillSign
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(symbol: "lock.doc", tint: Theme.warn, size: 34)
                VStack(alignment: .leading, spacing: 8) {
                    Text("« \(url.lastPathComponent) » est protégé par un mot de passe").font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                    Text(model.passwordWrong ? "Ce n'est pas le bon mot de passe : réessaie." : "Tape-le pour l'ouvrir. La copie enregistrée gardera le même mot de passe.")
                        .font(.ui(12)).foregroundStyle(model.passwordWrong ? Theme.warn : Theme.text2)
                    HStack(spacing: 8) {
                        Group {
                            if Snapshot.isActive {
                                Text(password.isEmpty ? "Mot de passe" : String(repeating: "•", count: password.count))
                                    .foregroundStyle(Theme.text3).frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                SecureField("Mot de passe", text: $password)
                                    .textFieldStyle(.plain)
                                    .onSubmit { model.open(url, password: password) }
                            }
                        }
                        .font(.ui(12.5))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(8)).strokeBorder(Theme.border, lineWidth: Theme.line))
                        .frame(width: 260)
                        Button("Ouvrir") { model.open(url, password: password) }
                            .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                            .disabled(password.isEmpty)
                        Button("Annuler") { model.passwordFor = nil }.buttonStyle(SoftButtonStyle(small: true))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The signatures and initials kept on this Mac: new ones, a click to put one on the document, the bin to forget one.
struct FillSignSignaturesPanel: View {
    @Environment(AppModel.self) private var app
    var compact = false

    var body: some View {
        let model = app.fillSign
        let signatures = model.signatures.filter { $0.kind == .signature }
        let initials = model.signatures.filter { $0.kind == .initials }
        if compact {
            VStack(alignment: .leading, spacing: 12) {
                group("Signatures", signatures, kind: .signature)
                group("Paraphes", initials, kind: .initials)
            }
        } else {
            Panel(title: "Tes signatures", subtitle: "Gardées sur ce Mac seulement, dans le dossier privé de Clean My Claude", symbol: "signature",
                  tint: FillSignStyle.tint) {
                HStack(alignment: .top, spacing: 24) {
                    group("Signatures", signatures, kind: .signature)
                    group("Paraphes", initials, kind: .initials)
                }
            }
        }
    }

    private func group(_ title: String, _ list: [FillSignSignature], kind: FillSignSignature.Kind) -> some View {
        let model = app.fillSign
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(.ui(10, .semibold)).tracking(0.6).foregroundStyle(Theme.text3)
                Spacer()
                Button {
                    model.newSignature(kind)
                } label: {
                    Label(kind == .signature ? "Nouvelle" : "Nouveau", systemImage: "plus").font(.ui(11, .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            if list.isEmpty {
                Text(kind == .signature ? "Aucune pour l'instant." : "Tes initiales, pour chaque page d'un contrat.")
                    .font(.ui(11.5)).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, minHeight: compact ? 30 : 54, alignment: .leading)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(list) { sig in
                    FillSignSignatureTile(signature: sig, armed: model.armed?.id == sig.id, height: compact ? 44 : 54)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A kept signature: a click puts it on the document (the next click on the page places it).
struct FillSignSignatureTile: View {
    @Environment(AppModel.self) private var app
    var signature: FillSignSignature
    var armed: Bool
    var height: CGFloat = 54
    @State private var hovering = false

    var body: some View {
        let model = app.fillSign
        let aspect = signature.size.width / max(1, signature.size.height)
        let w = min(signature.kind == .initials ? 90 : 210, max(48, (height - 12) * aspect))
        Button {
            if model.document != nil { model.arm(signature) }
        } label: {
            FillSignSignatureView(signature: signature)
                .frame(width: w, height: min(max(w / aspect, 10), height - 12))
                .frame(width: w + 20, height: height)
                // The signature is shown on paper, as it will be on the document.
                .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: Theme.r(8)).strokeBorder(armed ? Theme.accent : Theme.border, lineWidth: armed ? 2 : Theme.line))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering && !Snapshot.isActive {
                Button { model.deleteSignature(signature) } label: {
                    Image(systemName: "trash").font(.ui(9.5, .semibold)).foregroundStyle(Theme.onBad)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.bad))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .help("Supprimer")
            }
        }
        .onHover { hovering = $0 }
        .help(model.document != nil ? "Clique, puis clique sur la page pour la placer" : signature.kind.title)
    }
}

/// A signature drawn at the size it is given (strokes, script text or picture).
struct FillSignSignatureView: View {
    var signature: FillSignSignature

    var body: some View {
        GeometryReader { g in
            let rect = CGRect(origin: .zero, size: g.size)
            switch signature.style {
            case .drawn(let strokes, let width):
                Path(FillSignDraw.strokesPath(strokes, natural: signature.size, in: rect))
                    .stroke(signature.ink.color, style: StrokeStyle(lineWidth: FillSignDraw.penWidth(width, natural: signature.size, in: rect),
                                                                    lineCap: .round, lineJoin: .round))
            case .typed(let text, let font):
                let layout = FillSignDraw.typedLayout(text, font: font)
                let k = g.size.width / max(1, layout.size.width)
                Text(text)
                    .font(.custom(font, size: FillSignDraw.typedSize * k))
                    .foregroundStyle(signature.ink.color)
                    .fixedSize()
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            case .image(let png):
                if let image = NSImage(data: png) {
                    Image(nsImage: image).resizable().interpolation(.high)
                }
            }
        }
    }
}
