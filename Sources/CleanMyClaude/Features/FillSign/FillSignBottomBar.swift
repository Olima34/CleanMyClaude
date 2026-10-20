import SwiftUI

/// Pinned at the bottom of the page while a document is open: what changed and the button that saves the copy,
/// then where it went.
struct FillSignBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.fillSign
        if let doc = model.document {
            ActionBar {
                if model.saving {
                    BusyMascot(.checking, pixel: 2)
                    Text("J'enregistre la copie…").font(.serif(17)).foregroundStyle(Theme.text)
                    Spacer()
                } else if let saved = model.saved {
                    Image(systemName: "checkmark.seal.fill").font(.ui(20)).foregroundStyle(Theme.good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enregistré : \(saved.lastPathComponent)").font(.serif(17)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                        Text("Dans \(FS.pretty(saved.deletingLastPathComponent().path)) · l'original n'a pas changé")
                            .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                    Spacer()
                    Button("Afficher dans le Finder") { model.revealSaved() }.buttonStyle(SoftButtonStyle())
                    Button("Ouvrir") { model.openSaved() }.buttonStyle(SoftButtonStyle())
                    Button {
                        model.mailSaved()
                    } label: {
                        Label("Envoyer par e-mail…", systemImage: "envelope")
                    }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .help("Un nouveau message dans Mail, le PDF en pièce jointe : rien ne part sans toi")
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(model)).font(.serif(18)).foregroundStyle(Theme.text)
                        Text("Copie « \(FillSignExport.outputName(doc.name, signed: model.signatureCount > 0)).pdf »"
                             + (model.keepForm && model.canKeepForm ? " · formulaire modifiable" : " · version finale")
                             + " · l'original ne change pas")
                            .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        model.save()
                    } label: {
                        Label("Enregistrer le PDF", systemImage: model.signatureCount > 0 ? "signature" : "square.and.arrow.down")
                    }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .disabled(!model.hasChanges)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
    }

    private func title(_ model: FillSignModel) -> String {
        guard model.hasChanges else { return "Rien n'a encore changé" }
        var parts: [String] = []
        if model.signatureCount > 0 { parts.append(Fmt.plural(model.signatureCount, "signature", "signatures")) }
        let others = model.items.count - model.signatureCount
        if others > 0 { parts.append(Fmt.plural(others, "ajout", "ajouts")) }
        if model.fieldCount > 0 { parts.append("\(model.filledCount)/\(model.fieldCount) champs") }
        return parts.joined(separator: " · ")
    }
}
