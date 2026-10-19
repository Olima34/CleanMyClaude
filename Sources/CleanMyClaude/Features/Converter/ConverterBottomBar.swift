import SwiftUI

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct ConverterBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.converter
        if model.operation == .qrGenerate {
            if model.qrImage != nil {
                ActionBar {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QR code prêt").font(.serif(18)).foregroundStyle(Theme.text)
                        Text("PNG de 1 024 pixels, net à toutes les tailles").font(.ui(11)).foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    Button("Copier l'image") { model.copyQR() }.buttonStyle(SoftButtonStyle())
                    Button("Enregistrer en PNG…") { model.saveQR() }
                        .buttonStyle(SoftButtonStyle(prominent: true))
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        } else if let op = model.operation, !model.files.isEmpty || model.isBusy {
            ActionBar {
                if model.isBusy {
                    let active = model.activeJobs.count
                    VStack(alignment: .leading, spacing: 5) {
                        Text(active == 1 ? "Une conversion en cours…" : "\(active) conversions en attente ou en cours…")
                            .font(.serif(17)).foregroundStyle(Theme.text)
                        UsageBar(fraction: model.overallProgress, tint: Theme.palette[1], height: 5).frame(width: 240)
                    }
                    Spacer()
                    Button("Tout annuler") { model.cancelAll() }.buttonStyle(SoftButtonStyle())
                } else {
                    let count = model.targets(for: op).count
                    VStack(alignment: .leading, spacing: 2) {
                        Text(count == 0 ? "Aucun fichier pour « \(op.title) »" : "\(Fmt.plural(count, "fichier prêt", "fichiers prêts"))")
                            .font(.serif(18)).foregroundStyle(Theme.text)
                        Text("\(op.title) · \(ConverterModel.summary(op, model.options, qualityApplies: model.qualityApplies(op))) · \(op == .rename ? "sur place" : model.destinationLabel.lowercased())")
                            .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                    Spacer()
                }
                if !model.files.isEmpty {
                    Button {
                        model.startConversion()
                    } label: {
                        Label(op.actionTitle, systemImage: op.symbol)
                    }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .disabled(!model.canStart)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        } else {
            EmptyView()
        }
    }
}
