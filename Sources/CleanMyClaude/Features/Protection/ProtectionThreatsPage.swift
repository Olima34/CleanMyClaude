import SwiftUI

struct ThreatsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        VStack(alignment: .leading, spacing: 14) {
            if model.isScanning {
                ThreatScanProgress()
            } else {
                ThreatScanChoice()
            }
            FileCheckCard()
            if let m = model.threatMessage {
                Callout(symbol: m.ok ? "checkmark.shield" : "exclamationmark.triangle", title: m.ok ? "C'est fait" : "Pas tout à fait",
                        text: m.text, tint: m.ok ? Theme.good : Theme.warn)
            }
            let list = model.visibleThreats
            if !list.isEmpty {
                let bad = list.filter { $0.status == .bad }
                if !bad.isEmpty {
                    Panel(title: Fmt.plural(bad.count, "menace", "menaces"),
                          subtitle: "Reconnues par les signatures d'Apple, des traces connues ou un comportement d'intrus. Coche-les puis mets-les à la Corbeille : je les arrête d'abord.",
                          symbol: "exclamationmark.octagon", tint: Theme.bad) {
                        VStack(spacing: 2) { ForEach(bad) { ThreatRow(threat: $0) } }
                    }
                }
                let look = list.filter { $0.status != .bad }
                if !look.isEmpty {
                    Panel(title: "À examiner", subtitle: "Pas forcément dangereux, mais inhabituel : une app modifiée après sa signature, un agent caché dans un dossier partagé…",
                          symbol: "exclamationmark.triangle", tint: Theme.warn) {
                        VStack(spacing: 2) { ForEach(look) { ThreatRow(threat: $0) } }
                    }
                }
            } else if let s = model.scanSummary, !model.isScanning {
                Card(padding: 22) {
                    HStack(alignment: .center, spacing: 18) {
                        IconBadge(symbol: "checkmark.shield.fill", tint: Theme.good, size: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Aucune menace trouvée").font(.serif(22)).foregroundStyle(Theme.text)
                            Text("\(Fmt.int(s.files)) programmes, scripts et installeurs analysés \(Fmt.relative(s.date)) (analyse \(s.deep ? "complète" : "rapide")), avec les signatures XProtect \(s.signaturesVersion) d'Apple, les traces des familles connues et les comportements d'intrus.")
                                .font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !model.ignored.isEmpty {
                HStack {
                    Text("\(Fmt.plural(model.ignored.count, "élément ignoré", "éléments ignorés")) à ta demande.").font(.ui(11.5)).foregroundStyle(Theme.text3)
                    Button("Les montrer à nouveau") { model.restoreIgnored() }.buttonStyle(SoftButtonStyle(small: true))
                }
            }
            ThreatsExplainer()
        }
    }
}

struct ThreatScanChoice: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        let sig = ProtectionSignatures.newest()
        TileRow {
            ScanModeCard(title: "Analyse rapide", symbol: "hare",
                         text: "Ce qui démarre tout seul, ce qui tourne, tes apps, Téléchargements, le Bureau et les cachettes habituelles. Moins d'une minute.",
                         prominent: true) { Task { await model.scan(deep: false) } }
            ScanModeCard(title: "Analyse complète", symbol: "tortoise",
                         text: "Tous les programmes, scripts et installeurs du Mac, jusqu'au fond de ton dossier personnel. Quelques minutes.",
                         prominent: false) { Task { await model.scan(deep: true) } }
            StatTile(symbol: "ant", value: sig.map { "\($0.version)" } ?? "—", label: "Signatures XProtect",
                     detail: sig?.date.map { "Mises à jour par Apple \(Fmt.relative($0))" } ?? "Introuvables", tint: Theme.good)
            StatTile(symbol: "clock", value: model.scanSummary.map { Fmt.relative($0.date) } ?? "Jamais", label: "Dernière analyse",
                     detail: model.scanSummary.map { "\(Fmt.int($0.files)) fichiers · \($0.threats == 0 ? "rien trouvé" : Fmt.plural($0.threats, "menace", "menaces"))" } ?? "Lance une première analyse")
        }
    }
}

/// Drop a download (an app, an installer, a script) to check it before opening it.
struct FileCheckCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        HStack(alignment: .top, spacing: 14) {
            DropZone(title: "Vérifier avant d'ouvrir", subtitle: "Glisse ici une app, un installeur ou un script",
                     symbol: "checkmark.shield", allowsFolders: true) { urls in
                Task { await model.inspect(urls) }
            }
            .frame(width: 380, height: 150)
            Card(padding: 16) {
                if model.isInspecting {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("J'examine son code avec les signatures d'Apple…").font(.ui(12.5)).foregroundStyle(Theme.text2)
                    }
                } else if let v = model.verdict {
                    HStack(alignment: .top, spacing: 12) {
                        if v.path.hasSuffix(".app") { FileIcon(path: v.path, size: 36) } else { IconBadge(symbol: "doc", tint: v.status.color, size: 36) }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(v.name).font(.ui(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                                StatusBadge(status: v.status, text: v.status == .ok ? "Rien à signaler" : nil)
                            }
                            Text(v.title).font(.ui(12.5, .medium)).foregroundStyle(v.status == .ok ? Theme.text : v.status.color)
                            Text(v.detail).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Un doute sur un téléchargement ?").font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                        Text("Je passe tout son code aux signatures antimalware d'Apple, je regarde qui l'a signé, si Apple l'a notarisé, et d'où il vient. Rien n'est ouvert ni envoyé.")
                            .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(height: 150)
        }
    }
}

struct ScanModeCard: View {
    var title: String
    var symbol: String
    var text: String
    var prominent: Bool
    var action: () -> Void

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    IconBadge(symbol: symbol, tint: Theme.accent)
                    Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                }
                Text(text).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Lancer", action: action).buttonStyle(SoftButtonStyle(prominent: prominent))
            }
        }
    }
}

struct ThreatScanProgress: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        Card(padding: 22) {
            HStack(spacing: 18) {
                ClaudeSpark(size: 38, spin: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.scanTotal > 0 ? "\(model.scanPhase) \(Fmt.int(model.scanDone)) sur \(Fmt.int(model.scanTotal)) fichiers…" : model.scanPhase)
                        .font(.serif(20)).foregroundStyle(Theme.text)
                    Text(model.scanCurrent.isEmpty ? " " : FS.pretty(model.scanCurrent))
                        .font(.ui(12)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                    if model.scanTotal > 0 {
                        UsageBar(fraction: Double(model.scanDone) / Double(max(1, model.scanTotal)), tint: Theme.accent, height: 6)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                    }
                }
                Button("Annuler") { model.cancelScan() }.buttonStyle(SoftButtonStyle())
            }
        }
    }
}

struct ThreatRow: View {
    @Environment(AppModel.self) private var app
    var threat: ProtectionThreat
    @State private var confirm = false

    var body: some View {
        let model = app.protection
        HoverRow {
            HStack(alignment: .top, spacing: 12) {
                CheckBox(state: model.threatSelection.contains(threat.id) ? .on : .off, disabled: threat.removable.isEmpty) { model.toggle(threat) }
                    .padding(.top, 4)
                if threat.path.hasSuffix(".app") {
                    FileIcon(path: threat.path, size: 28)
                } else {
                    IconBadge(symbol: threat.kind.symbol, tint: threat.status.color, size: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(threat.name).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                        Tag(text: threat.title, symbol: threat.kind.symbol, tint: threat.status.color, filled: true)
                    }
                    Text(threat.detail).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    Text(FS.pretty(threat.path)).font(.mono(10.5)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                    let linked = threat.removable.dropFirst().map { ($0 as NSString).lastPathComponent }
                        + threat.services.map { "service " + ($0.split(separator: "/").last.map(String.init) ?? $0) }
                    if !linked.isEmpty {
                        Text("Avec : " + linked.joined(separator: ", "))
                            .font(.ui(10.5)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if model.removing.contains(threat.id) {
                    ProgressView().controlSize(.small)
                } else {
                    BorderlessMenu(indicator: false) {
                        if !threat.removable.isEmpty {
                            Button("Arrêter et mettre à la Corbeille…") { confirm = true }
                        }
                        if FS.exists(threat.path) { Button("Afficher dans le Finder") { Finder.reveal(threat.path) } }
                        Button("Demander à Claude ce que c'est") {
                            app.assistant.explain(threat.name, details: [threat.title, threat.detail, "Emplacement : \(FS.pretty(threat.path))"])
                        }
                        Divider()
                        Button("Ignorer : je sais ce que c'est") { model.ignore(threat) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.ui(14)).foregroundStyle(Theme.text2)
                    }
                }
            }
        }
        .confirmAction("Neutraliser « \(threat.name) » ?",
                       message: ThreatActionBar.message(for: [threat]), button: "Mettre à la Corbeille", isPresented: $confirm) {
            Task { await model.remove([threat]) }
        }
    }
}

struct ThreatActionBar: View {
    @Environment(AppModel.self) private var app
    @State private var confirm = false

    static func message(for list: [ProtectionThreat]) -> String {
        let files = list.flatMap(\.removable)
        let services = list.flatMap(\.services)
        var text = files.prefix(8).map { "• " + FS.pretty($0) }.joined(separator: "\n")
        if files.count > 8 { text += "\n• et \(files.count - 8) autres" }
        if !services.isEmpty { text += "\n\n\(Fmt.plural(services.count, "service est arrêté", "services sont arrêtés")) d'abord." }
        text += "\n\nTout va dans la Corbeille : tu peux le remettre en place tant que tu ne l'as pas vidée. Un élément du système demande ton mot de passe d'administrateur."
        return text
    }

    var body: some View {
        let model = app.protection
        let selected = model.selectedThreats
        ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.plural(selected.count, "menace sélectionnée", "menaces sélectionnées"))
                    .font(.serif(18)).foregroundStyle(Theme.text)
                Text("Arrêtées, puis mises à la Corbeille.").font(.ui(11)).foregroundStyle(Theme.text3)
            }
            Spacer()
            Button {
                confirm = true
            } label: {
                HStack(spacing: 6) {
                    if !model.removing.isEmpty { ProgressView().controlSize(.small).scaleEffect(0.7).tint(Theme.onBad) }
                    Text("Neutraliser")
                }
            }
            .buttonStyle(SoftButtonStyle(destructive: true))
            .disabled(selected.isEmpty || !model.removing.isEmpty)
        }
        .confirmAction("Neutraliser \(Fmt.plural(selected.count, "menace", "menaces")) ?", message: Self.message(for: selected),
                       button: "Mettre à la Corbeille", isPresented: $confirm) {
            Task { await model.remove(selected) }
        }
    }
}

/// How the scan works, in a few honest lines.
struct ThreatsExplainer: View {
    var body: some View {
        Panel(title: "Comment je cherche", symbol: "magnifyingglass", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 10) {
                ExplainerLine(symbol: "ant", title: "Les signatures d'Apple",
                              text: "XProtect, l'antimalware intégré à macOS, ne vérifie un fichier qu'au moment où tu l'ouvres. J'applique ses propres signatures (plus de 500 familles : Atomic Stealer, Adload, Shlayer…) à tout ce qui est déjà sur ton Mac, ouvert ou non.")
                ExplainerLine(symbol: "exclamationmark.octagon", title: "Les traces connues",
                              text: "Les fichiers exacts que laissent des logiciels malveillants documentés (EvilQuest, Silver Sparrow, AppleJeus…).")
                ExplainerLine(symbol: "theatermasks", title: "Les comportements d'intrus",
                              text: "Un programme qui se fait passer pour Apple, télécharge puis exécute du code, se cache dans un dossier partagé, ou une app modifiée après sa signature.")
                ExplainerLine(symbol: "lock.shield", title: "Rien ne quitte ton Mac",
                              text: "Aucun fichier n'est envoyé nulle part, et rien n'est supprimé : ce que tu neutralises part à la Corbeille.")
            }
        }
    }
}

struct ExplainerLine: View {
    var symbol: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconBadge(symbol: symbol, tint: Theme.accent, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
