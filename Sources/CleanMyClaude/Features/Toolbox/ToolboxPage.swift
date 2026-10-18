import SwiftUI
import AppKit

struct ToolboxPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.toolbox
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "wrench.and.screwdriver", title: "Boîte à outils",
                     subtitle: "Les petits outils du quotidien : couleurs, mots de passe, empreintes, texte, dates et Caféine. Tout se calcule sur ton Mac, et presque tout répond aussi dans le lanceur.",
                     tint: Theme.palette[7], seed: 71) {
                ToolboxCaffeinePill()
            }
            PillPicker(options: ToolboxTab.allCases, selection: $model.tab, label: { $0.title }, badge: { tab in
                switch tab {
                case .caffeine: return model.caffeineActive ? "●" : nil
                case .hashes: return model.hashRunning ? "…" : (model.hashJobs.isEmpty ? nil : "\(model.hashJobs.count)")
                case .colors: return model.settings.colors.isEmpty ? nil : "\(model.settings.colors.count)"
                default: return nil
                }
            })
            switch model.tab {
            case .colors: ToolboxColorsTab()
            case .passwords: ToolboxPasswordsTab()
            case .hashes: ToolboxHashesTab()
            case .text: ToolboxTextTab()
            case .time: ToolboxTimeTab()
            case .caffeine: ToolboxCaffeineTab()
            }
        }
    }
}

/// The action bar pinned at the bottom of the page: Caféine's state while it runs.
struct ToolboxBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.toolbox
        if m.caffeineActive && m.tab != .caffeine {
            ActionBar {
                Image(systemName: "cup.and.saucer.fill").font(.ui(15)).foregroundStyle(Theme.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caféine active").font(.serif(17)).foregroundStyle(Theme.text)
                    Text(m.caffeineEnd.map { "Ton Mac reste éveillé jusqu'à \(Fmt.clock($0)) (encore \(m.caffeineShortRemaining(Date())))" }
                         ?? "Ton Mac reste éveillé jusqu'à ce que tu l'arrêtes")
                        .font(.ui(11)).foregroundStyle(Theme.text3)
                }
                Spacer()
                Button("Réglages") { m.tab = .caffeine }.buttonStyle(SoftButtonStyle())
                Button("Arrêter") { m.stopCaffeine() }.buttonStyle(SoftButtonStyle(prominent: true))
            }
        }
    }
}

/// Caféine in the page header: its state, and one click to switch it.
struct ToolboxCaffeinePill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.toolbox
        let _ = m.minuteTick
        Button { m.toggleCaffeine() } label: {
            HStack(spacing: 6) {
                Image(systemName: m.caffeineActive ? "cup.and.saucer.fill" : "cup.and.saucer").font(.ui(12, .semibold))
                Text(m.caffeineActive ? "Caféine · \(m.caffeineShortRemaining(Date()))" : "Caféine").font(.ui(12, .semibold))
            }
            .foregroundStyle(m.caffeineActive ? Theme.onBrand : Theme.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(PillShape().fill(m.caffeineActive ? Theme.brand : Theme.card))
            .overlay(PillShape().strokeBorder(m.caffeineActive ? Color.clear : Theme.border))
            .contentShape(PillShape())
        }
        .buttonStyle(.plain)
        .help(m.caffeineActive ? "Arrêter Caféine" : "Garder le Mac éveillé (\(m.settings.caffeineMinutes == 0 ? "sans limite" : ToolboxTime.durationLabel(m.settings.caffeineMinutes)))")
    }
}

// MARK: - Colors

struct ToolboxColorsTab: View {
    @Environment(AppModel.self) private var app
    @State private var picking = false

    var body: some View {
        @Bindable var m = app.toolbox
        let c = m.color
        VStack(alignment: .leading, spacing: 14) {
            TileRow {
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous)
                            .fill(c.color)
                            .frame(height: 158)
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.hex).font(.mono(22, .semibold))
                                    Text(c.rgbString).font(.mono(11.5))
                                }
                                .foregroundStyle(c.isLight ? Color.black.opacity(0.72) : Color.white.opacity(0.95))
                                .padding(14)
                            }
                            .overlay(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous).strokeBorder(Theme.border, lineWidth: Theme.line))
                        HStack(spacing: 8) {
                            Button {
                                picking = true
                                Task {
                                    if DemoData.isEnabled { HUD.show(DemoData.refusal, symbol: "theatermasks") }
                                    _ = await m.pickColor()
                                    picking = false
                                }
                            } label: {
                                Label(picking ? "Clique sur la couleur…" : "Choisir à l'écran", systemImage: "eyedropper")
                            }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                            .help("Une loupe apparaît : clique sur n'importe quel pixel de l'écran. Échap pour annuler.")
                            ToolboxCopyButton(text: c.hex, label: "Copier le HEX")
                        }
                        ToolboxField(placeholder: "Colle une couleur : #D97757, rgb(…), hsl(…)", text: $m.colorInput, mono: true,
                                     symbol: "paintpalette") { m.applyColorInput() }
                            .onChange(of: m.colorInput) { _, new in
                                if let parsed = ToolboxRGB.parse(new) { m.setColor(parsed, remember: false) }
                            }
                        if !m.colorInput.isEmpty && ToolboxRGB.parse(m.colorInput) == nil {
                            Text("Format non reconnu : essaie #RRGGBB, rgb(r, g, b) ou hsl(t, s%, l%).")
                                .font(.ui(11)).foregroundStyle(Theme.warn)
                        }
                    }
                }
                .frame(width: 370)
                Panel(title: "Formats", subtitle: "Prêts à coller dans ton code ou ta feuille de style", symbol: "chevron.left.forwardslash.chevron.right",
                      tint: Theme.palette[7]) {
                    VStack(spacing: 2) {
                        ToolboxValueRow(label: "HEX", value: c.hex)
                        ToolboxValueRow(label: "RGB", value: c.rgbString)
                        ToolboxValueRow(label: "HSL", value: c.hslString)
                        ToolboxValueRow(label: "SwiftUI", value: c.swiftUI)
                        ToolboxValueRow(label: "AppKit", value: String(format: "NSColor(srgbRed: %.3f, green: %.3f, blue: %.3f, alpha: %.2f)", c.r, c.g, c.b, c.a))
                    }
                    SectionLabel(text: "Nuances")
                    HStack(spacing: 5) {
                        ForEach([0.92, 0.84, 0.74, 0.64, 0.54, 0.44, 0.34, 0.24, 0.14], id: \.self) { l in
                            let shade = c.withLightness(l)
                            RoundedRectangle(cornerRadius: Theme.r(6))
                                .fill(shade.color)
                                .frame(height: 30)
                                .overlay(RoundedRectangle(cornerRadius: Theme.r(6)).strokeBorder(Theme.border, lineWidth: Theme.line))
                                .contentShape(Rectangle())
                                .onTapGesture { m.setColor(shade) }
                                .help(shade.hex)
                        }
                    }
                    HStack(spacing: 14) {
                        contrast(c, ToolboxRGB(hex: 0xFFFFFF), "sur blanc")
                        contrast(c, ToolboxRGB(hex: 0x000000), "sur noir")
                        Spacer()
                    }
                }
            }
            Panel(title: "Historique", subtitle: "Les couleurs choisies à l'écran ou cliquées, gardées sur ce Mac", symbol: "clock.arrow.circlepath",
                  tint: Theme.palette[7]) {
                if !m.settings.colors.isEmpty {
                    Button("Effacer") { m.settings.colors.removeAll() }.buttonStyle(SoftButtonStyle(small: true))
                }
            } content: {
                if m.settings.colors.isEmpty {
                    EmptyHint(text: "Choisis une couleur à l'écran : elle s'ajoutera ici.", symbol: "eyedropper")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 12) {
                        ForEach(m.settings.colors, id: \.hex) { h in
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: Theme.r(9), style: .continuous)
                                    .fill(h.color)
                                    .frame(height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.r(9), style: .continuous)
                                        .strokeBorder(h.hex == c.hex ? Theme.accent : Theme.border, lineWidth: h.hex == c.hex ? 2 : 1))
                                Text(h.hex).font(.mono(10.5)).foregroundStyle(Theme.text2)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { m.setColor(h, remember: false) }
                            .contextMenu {
                                Button("Copier \(h.hex)") { m.copy(h.hex) }
                                Button("Copier \(h.rgbString)") { m.copy(h.rgbString) }
                                Button("Copier pour SwiftUI") { m.copy(h.swiftUI) }
                                Divider()
                                Button("Retirer de l'historique") { m.forget(h) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func contrast(_ a: ToolboxRGB, _ b: ToolboxRGB, _ label: String) -> some View {
        let l1 = a.luminance, l2 = b.luminance
        let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        let ok = ratio >= 4.5
        return HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle").font(.ui(10.5)).foregroundStyle(ok ? Theme.good : Theme.text3)
            Text("Contraste \(label) \(Fmt.dec(ratio)):1").font(.ui(11)).foregroundStyle(Theme.text2).monospacedDigit()
        }
        .help(ok ? "Lisible pour du texte (au moins 4,5:1, norme WCAG AA)" : "Trop faible pour du texte courant (moins de 4,5:1)")
    }
}

// MARK: - Passwords

struct ToolboxPasswordsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.toolbox
        VStack(alignment: .leading, spacing: 14) {
            TileRow {
                Panel(title: "Mot de passe", subtitle: "Aléatoire, tiré par le générateur sécurisé de macOS", symbol: "key.fill", tint: Theme.palette[7]) {
                    ToolboxSecretText(text: m.password)
                    ToolboxStrength(bits: ToolboxPassword.entropy(m.settings.password))
                    HStack(spacing: 8) {
                        Button { m.regeneratePassword() } label: { Label("Régénérer", systemImage: "arrow.clockwise") }
                            .buttonStyle(SoftButtonStyle(small: true))
                        Spacer()
                        ToolboxCopyButton(text: m.password, secret: true, label: "Copier", prominent: true)
                    }
                    Divider().overlay(Theme.border)
                    HStack {
                        Text("Longueur").font(.ui(12.5)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(m.settings.password.length) caractères").font(.ui(12.5, .semibold)).foregroundStyle(Theme.text).monospacedDigit()
                    }
                    ToolboxSlider(value: $m.settings.password.length, range: 8...64, tint: Theme.palette[7])
                    VStack(spacing: 9) {
                        ToolboxSwitch(title: "Majuscules (A–Z)", isOn: $m.settings.password.upper)
                        ToolboxSwitch(title: "Minuscules (a–z)", isOn: $m.settings.password.lower)
                        ToolboxSwitch(title: "Chiffres (0–9)", isOn: $m.settings.password.digits)
                        ToolboxSwitch(title: "Symboles (! # $ % & * + = ? @…)", isOn: $m.settings.password.symbols)
                        ToolboxSwitch(title: "Sans caractères ambigus", detail: "Ni 0 ni O, ni 1, l ou I, ni guillemets : plus simple à recopier à la main.",
                                      isOn: $m.settings.password.avoidAmbiguous)
                    }
                }
                Panel(title: "Phrase de passe", subtitle: "Des mots tirés au hasard : facile à retenir, difficile à deviner", symbol: "text.word.spacing",
                      tint: Theme.palette[7]) {
                    ToolboxSecretText(text: m.passphrase, words: true)
                    ToolboxStrength(bits: ToolboxPassword.passphraseEntropy(m.settings.passphrase))
                    HStack(spacing: 8) {
                        Button { m.regeneratePassphrase() } label: { Label("Régénérer", systemImage: "arrow.clockwise") }
                            .buttonStyle(SoftButtonStyle(small: true))
                        Spacer()
                        ToolboxCopyButton(text: m.passphrase, secret: true, label: "Copier", prominent: true)
                    }
                    Divider().overlay(Theme.border)
                    HStack {
                        Text("Nombre de mots").font(.ui(12.5)).foregroundStyle(Theme.text)
                        Spacer()
                        ToolboxStepper(value: $m.settings.passphrase.words, range: 3...10)
                    }
                    HStack {
                        Text("Séparateur").font(.ui(12.5)).foregroundStyle(Theme.text)
                        Spacer()
                        HStack(spacing: 5) {
                            ForEach([("-", "-"), (".", "."), ("_", "_"), (" ", "espace")], id: \.0) { sep, label in
                                ToolboxChip(title: label, selected: m.settings.passphrase.separator == sep, mono: sep != " ") {
                                    m.settings.passphrase.separator = sep
                                }
                            }
                        }
                    }
                    VStack(spacing: 9) {
                        ToolboxSwitch(title: "Une majuscule à chaque mot", isOn: $m.settings.passphrase.capitalize)
                        ToolboxSwitch(title: "Ajouter un chiffre", isOn: $m.settings.passphrase.addNumber)
                    }
                    Text("\(Fmt.int(ToolboxWords.list.count)) mots français sans accents, faciles à taper sur tous les claviers.")
                        .font(.ui(11)).foregroundStyle(Theme.text3)
                }
            }
            Card(padding: 16) {
                HStack(alignment: .top, spacing: 14) {
                    IconBadge(symbol: "lock.shield", tint: Theme.good, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rien ne quitte ton Mac").font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                        Text("Les mots de passe sont tirés par SecRandomCopyBytes et ne sont enregistrés nulle part. À la copie, ils sont marqués confidentiels : les historiques de presse-papiers, dont celui de Clean My Claude, les ignorent.")
                            .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 20)
                    ToolboxSwitch(title: "Effacer après 90 s", detail: "Si rien d'autre n'a été copié entre-temps", isOn: $m.settings.clearSecrets)
                        .frame(width: 250)
                }
            }
        }
        .onChange(of: m.settings.password) { _, _ in m.regeneratePassword() }
        .onChange(of: m.settings.passphrase) { _, _ in m.regeneratePassphrase() }
    }
}

/// A password shown large, digits and symbols tinted so each character reads clearly.
struct ToolboxSecretText: View {
    var text: String
    var words = false

    var body: some View {
        Text(attributed)
            .font(.mono(words ? 16 : 18, .medium))
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for ch in text {
            var piece = AttributedString(String(ch))
            if ch.isNumber {
                piece.foregroundColor = Theme.accent
            } else if !ch.isLetter {
                piece.foregroundColor = Theme.brand
            } else {
                piece.foregroundColor = Theme.text
            }
            out += piece
        }
        return out
    }
}

// MARK: - Digests

struct ToolboxHashesTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.toolbox
        let guess = ToolboxHash.guess(m.expectedHash)
        VStack(alignment: .leading, spacing: 14) {
            ToolboxDropZone(title: "Dépose des fichiers pour calculer leurs empreintes",
                     subtitle: "ou clique pour les choisir · SHA-256, SHA-384, SHA-512, SHA-1 et MD5 en une seule lecture",
                     symbol: "number.square") { m.hash($0) }
            VStack(alignment: .leading, spacing: 6) {
                ToolboxField(placeholder: "Empreinte attendue : colle celle du site de téléchargement pour vérifier le fichier", text: $m.expectedHash,
                             mono: true, symbol: "checkmark.seal")
                if !m.expectedHash.isEmpty {
                    Text(guess.map { "Ça ressemble à du \($0.title) : elle est comparée à chaque fichier ci-dessous." }
                         ?? "Ce n'est pas une empreinte hexadécimale (32, 40, 64, 96 ou 128 caractères 0-9 a-f).")
                        .font(.ui(11)).foregroundStyle(guess == nil ? Theme.warn : Theme.text3)
                }
            }
            if !m.hashJobs.isEmpty {
                HStack {
                    SectionLabel(text: Fmt.plural(m.hashJobs.count, "fichier", "fichiers"))
                    Spacer()
                    Button("Tout effacer") { m.clearHashes() }.buttonStyle(SoftButtonStyle(small: true))
                }
                let anyMatch = m.hashJobs.contains { $0.state == .done && ToolboxHash.match(m.expectedHash, in: $0.results) != nil }
                ForEach(m.hashJobs) { job in ToolboxHashCard(job: job, expected: m.expectedHash, anotherMatches: anyMatch) }
            }
            Panel(title: "Empreinte d'un texte", subtitle: "Calculée sur les octets UTF-8 du texte, sans retour à la ligne final", symbol: "text.cursor",
                  tint: Theme.palette[7]) {
                ToolboxField(placeholder: "Tape ou colle un texte", text: $m.hashText, mono: true)
                if !m.hashText.isEmpty {
                    let r = ToolboxHash.digests(of: Data(m.hashText.utf8))
                    let match = ToolboxHash.match(m.expectedHash, in: r)
                    VStack(spacing: 2) {
                        ForEach(ToolboxHashAlgo.allCases) { a in
                            ToolboxValueRow(label: a.title, value: r[a] ?? "", labelWidth: 70, highlight: match == a ? Theme.good : nil)
                        }
                    }
                }
            }
        }
    }
}

struct ToolboxHashCard: View {
    var job: ToolboxHashJob
    var expected: String
    /// Another file of the list matches the pasted digest: this one is just a different file, not a damaged one.
    var anotherMatches = false
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.toolbox
        let match = job.state == .done ? ToolboxHash.match(expected, in: job.results) : nil
        Card(padding: 16) {
            HStack(spacing: 12) {
                FileIcon(path: job.path, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name).font(.ui(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                    Text("\(Fmt.bytes(job.size)) · \(FS.pretty((job.path as NSString).deletingLastPathComponent))")
                        .font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                switch job.state {
                case .waiting:
                    Tag(text: "En attente", symbol: "hourglass")
                case .running:
                    Text(Fmt.pct(job.fraction)).font(.ui(12, .medium)).foregroundStyle(Theme.text2).monospacedDigit()
                    Button("Annuler") { m.cancelHash(job.id) }.buttonStyle(SoftButtonStyle(small: true))
                case .done:
                    if !expected.isEmpty && (match != nil || !anotherMatches) {
                        StatusBadge(status: match != nil ? .ok : .bad, text: match != nil ? "Correspond" : "Ne correspond pas")
                    } else if !expected.isEmpty {
                        Tag(text: "Autre fichier", symbol: "equal.circle")
                    } else {
                        Tag(text: job.seconds.map { $0 < 1 ? "Lu en moins d'1 s" : "Lu en \(Fmt.duration($0))" } ?? "Terminé", symbol: "checkmark")
                    }
                case .failed:
                    StatusBadge(status: .bad, text: "Échec")
                case .cancelled:
                    Tag(text: "Annulé", symbol: "xmark")
                }
                Button { m.removeHash(job.id) } label: {
                    Image(systemName: "xmark").font(.ui(10.5, .semibold)).foregroundStyle(Theme.text3).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Retirer de la liste")
            }
            if job.state == .running {
                UsageBar(fraction: job.fraction, tint: Theme.palette[7])
                Text("\(Fmt.bytes(job.done)) lus sur \(Fmt.bytes(job.size))").font(.ui(11)).foregroundStyle(Theme.text3).monospacedDigit()
            }
            if let error = job.error {
                Text(error).font(.ui(12)).foregroundStyle(Theme.bad)
            }
            if job.state == .done {
                VStack(spacing: 2) {
                    ForEach(ToolboxHashAlgo.allCases) { a in
                        ToolboxValueRow(label: a.title, value: job.results[a] ?? "", labelWidth: 70, highlight: match == a ? Theme.good : nil,
                                        note: a.isWeak ? "intégrité seulement" : nil)
                    }
                }
                if !expected.isEmpty && (match != nil || !anotherMatches) {
                    Text(match.map { "L'empreinte \($0.title) correspond : le fichier est bien celui annoncé." + ($0.isWeak ? " (\($0.title) détecte une corruption, pas une falsification : préfère SHA-256 quand il est proposé.)" : "") }
                         ?? "Aucune empreinte ne correspond : le fichier est différent, incomplet ou corrompu. Ne l'ouvre pas s'il vient d'Internet.")
                        .font(.ui(11.5)).foregroundStyle(match != nil ? Theme.good : Theme.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Text

struct ToolboxTextTab: View {
    @Environment(AppModel.self) private var app
    /// Huge texts are shown cut (SwiftUI lays out long strings slowly); the copy keeps everything.
    private let previewLimit = 20_000

    var body: some View {
        @Bindable var m = app.toolbox
        let result = m.textOp.apply(m.textInput)
        let output: String = (try? result.get()) ?? ""
        let failure: String? = { if case .failure(let e) = result { return e.message }; return nil }()
        let counts = ToolboxText.counts(m.textInput)
        VStack(alignment: .leading, spacing: 14) {
            Panel(title: "Transformer du texte", subtitle: m.textOp.help, symbol: "textformat", tint: Theme.palette[7]) {
                HStack(alignment: .top, spacing: 22) {
                    chips("Encoder", ToolboxTextOp.encoders, m)
                    chips("JSON", ToolboxTextOp.json, m)
                    Spacer(minLength: 0)
                }
                chips("Casse", ToolboxTextOp.cases, m)
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Entrée").font(.ui(11.5, .semibold)).foregroundStyle(Theme.text3).frame(height: 20)
                        ToolboxEditor(text: $m.textInput, placeholder: "Colle ou tape ton texte ici…", height: 230)
                        Text("\(Fmt.plural(counts.words, "mot", "mots")) · \(Fmt.plural(counts.characters, "caractère", "caractères")) · \(Fmt.plural(counts.lines, "ligne", "lignes"))")
                            .font(.ui(11)).foregroundStyle(Theme.text3).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Résultat").font(.ui(11.5, .semibold)).foregroundStyle(Theme.text3).frame(height: 20)
                            if failure != nil { StatusBadge(status: .bad, text: "Invalide") } else if !output.isEmpty && (m.textOp == .jsonPretty || m.textOp == .jsonCompact) {
                                StatusBadge(status: .ok, text: "JSON valide")
                            }
                        }
                        ToolboxEditor(text: .constant(failure ?? (output.count > previewLimit ? String(output.prefix(previewLimit)) + "\n…" : output)),
                                      placeholder: "Le résultat s'affiche ici.", height: 230, mono: failure == nil, editable: false,
                                      tint: failure == nil ? nil : Theme.bad)
                        HStack(spacing: 8) {
                            ToolboxCopyButton(text: failure == nil ? output : "", label: "Copier le résultat", prominent: true)
                            Button { m.textInput = output } label: { Label("Utiliser comme entrée", systemImage: "arrow.uturn.left") }
                                .buttonStyle(SoftButtonStyle(small: true))
                                .disabled(failure != nil || output.isEmpty || output == m.textInput)
                            Spacer()
                        }
                    }
                }
            }
            TileRow {
                Panel(title: "Compteur", subtitle: "Le texte de l'entrée, à la loupe", symbol: "textformat.123", tint: Theme.palette[7]) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        stat("Mots", Fmt.int(counts.words))
                        stat("Caractères", Fmt.int(counts.characters))
                        stat("Sans espaces", Fmt.int(counts.charactersNoSpaces))
                        stat("Lignes", Fmt.int(counts.lines))
                        stat("Paragraphes", Fmt.int(counts.paragraphs))
                        stat("Lecture", counts.readingTime)
                    }
                    Text("\(Fmt.bytes(counts.bytes)) en UTF-8").font(.ui(11)).foregroundStyle(Theme.text3)
                }
                ToolboxLoremPanel()
            }
        }
    }

    private func chips(_ title: String, _ ops: [ToolboxTextOp], _ m: ToolboxModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.ui(10, .semibold)).tracking(0.7).foregroundStyle(Theme.text3)
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(ops) { op in
                    ToolboxChip(title: op.title, selected: m.textOp == op, mono: op.isCase) { m.textOp = op }
                        .help(op.help)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.serif(22)).foregroundStyle(Theme.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.ui(11)).foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(Theme.bg))
    }
}

extension ToolboxTextOp {
    fileprivate var isCase: Bool {
        if case .textCase(let c) = self { return c != .title && c != .sentence && c != .upper && c != .lower }
        return false
    }
}

struct ToolboxLoremPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.toolbox
        let text = ToolboxText.lorem(m.loremCount, unit: m.loremUnit, seed: m.loremSeed)
        Panel(title: "Lorem ipsum", subtitle: "Du faux texte pour remplir une maquette", symbol: "text.alignleft", tint: Theme.palette[7]) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(ToolboxText.LoremUnit.allCases) { u in
                        ToolboxChip(title: u.title, selected: m.loremUnit == u) {
                            m.loremUnit = u
                            m.loremCount = u == .words ? 50 : (u == .sentences ? 5 : 2)
                        }
                    }
                }
                Spacer()
                ToolboxStepper(value: $m.loremCount, range: 1...(m.loremUnit == .words ? 500 : 20))
            }
            ToolboxEditor(text: .constant(text), height: 128, mono: false, editable: false)
            HStack(spacing: 8) {
                Button { m.loremSeed &+= 1 } label: { Label("Varier", systemImage: "shuffle") }
                    .buttonStyle(SoftButtonStyle(small: true))
                Spacer()
                ToolboxCopyButton(text: text, label: "Copier", prominent: true)
            }
        }
    }
}

// MARK: - Dates and UUID

struct ToolboxTimeTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.toolbox
        let shown = m.settings.uuidLowercase ? m.uuid.lowercased() : m.uuid
        VStack(alignment: .leading, spacing: 14) {
            TileRow {
                Panel(title: "UUID", subtitle: "Un identifiant unique et aléatoire (version 4)", symbol: "number", tint: Theme.palette[7]) {
                    Text(shown)
                        .font(.mono(16, .medium))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.border, lineWidth: Theme.line))
                    HStack(spacing: 8) {
                        Button { m.uuid = UUID().uuidString } label: { Label("Nouveau", systemImage: "arrow.clockwise") }
                            .buttonStyle(SoftButtonStyle(small: true))
                        Button {
                            let list = (0..<10).map { _ in m.settings.uuidLowercase ? UUID().uuidString.lowercased() : UUID().uuidString }
                            m.copy(list.joined(separator: "\n"))
                        } label: { Label("Copier 10 UUID", systemImage: "list.number") }
                            .buttonStyle(SoftButtonStyle(small: true))
                        Spacer()
                        ToolboxCopyButton(text: shown, label: "Copier", prominent: true)
                    }
                    ToolboxSwitch(title: "En minuscules", isOn: $m.settings.uuidLowercase)
                }
                Panel(title: "Maintenant", subtitle: "L'heure Unix, seconde après seconde", symbol: "clock", tint: Theme.palette[7]) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(ToolboxTime.unix(ctx.date)).font(.serif(30)).foregroundStyle(Theme.text).monospacedDigit()
                                Spacer()
                                ToolboxCopyButton(text: ToolboxTime.unix(ctx.date), label: "Copier", prominent: true)
                            }
                            VStack(spacing: 2) {
                                ToolboxValueRow(label: "Millisecondes", value: ToolboxTime.unixMillis(ctx.date), labelWidth: 100)
                                ToolboxValueRow(label: "ISO 8601", value: ToolboxTime.isoString(ctx.date), labelWidth: 100)
                            }
                        }
                    }
                }
            }
            Panel(title: "Convertir une date", subtitle: "Un horodatage (secondes, millisecondes, microsecondes) ou une date ISO 8601, 2026-10-18 14:30, 18/10/2026…",
                  symbol: "calendar", tint: Theme.palette[7]) {
                ToolboxField(placeholder: "1792326600, 2026-10-18T14:30:00Z, 18/10/2026 14:30…", text: $m.dateInput, mono: true, symbol: "calendar")
                if let p = ToolboxTime.parse(m.dateInput) {
                    Tag(text: p.source, symbol: "checkmark", tint: Theme.good, filled: true)
                    VStack(spacing: 2) {
                        ForEach(Array(ToolboxTime.describe(p.date).enumerated()), id: \.offset) { _, row in
                            ToolboxValueRow(label: row.label, value: row.value, labelWidth: 170)
                        }
                    }
                } else if !m.dateInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Je ne reconnais pas cette date. Essaie un nombre (1792326600) ou 2026-10-18 14:30.")
                        .font(.ui(11.5)).foregroundStyle(Theme.warn)
                }
            }
        }
    }
}

// MARK: - Caffeine

struct ToolboxCaffeineTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.toolbox
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 24) {
                HStack(alignment: .center, spacing: 28) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        ZStack {
                            // The ring moves every 15 s (its animation would otherwise run every second).
                            let step = Date(timeIntervalSince1970: (ctx.date.timeIntervalSince1970 / 15).rounded(.down) * 15)
                            ProgressRing(progress: m.caffeineActive ? m.caffeineFraction(step) : 0, tint: Theme.brand, lineWidth: 9)
                            VStack(spacing: 4) {
                                Image(systemName: m.caffeineActive ? "cup.and.saucer.fill" : "moon.zzz")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(m.caffeineActive ? Theme.brand : Theme.text3)
                                Text(countdown(m, ctx.date))
                                    .font(.serif(m.caffeineActive && m.caffeineEnd == nil ? 30 : 22))
                                    .foregroundStyle(Theme.text)
                                    .monospacedDigit()
                            }
                        }
                        .frame(width: 140, height: 140)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(m.caffeineActive ? "Ton Mac reste éveillé" : "Ton Mac peut se mettre en veille")
                            .font(.serif(26)).foregroundStyle(Theme.text)
                        Text(subtitle(m))
                            .font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            ForEach([(15, "15 min"), (60, "1 h"), (120, "2 h"), (0, "Indéfiniment")], id: \.0) { minutes, label in
                                let on = m.caffeineActive && m.settings.caffeineMinutes == minutes
                                Button {
                                    m.startCaffeine(minutes: minutes == 0 ? nil : minutes)
                                } label: {
                                    Text(label)
                                        .font(.ui(12.5, .semibold))
                                        .foregroundStyle(on ? Theme.onBrand : Theme.text)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(on ? Theme.brand : Theme.bg))
                                        .overlay(RoundedRectangle(cornerRadius: Theme.r(9)).strokeBorder(on ? Color.clear : Theme.border))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            if m.caffeineActive {
                                Button("Arrêter") { m.stopCaffeine() }
                                    .buttonStyle(SoftButtonStyle(destructive: true))
                                    .padding(.leading, 6)
                            }
                        }
                        ToolboxSwitch(title: "Garder aussi l'écran allumé",
                                      detail: "Sinon l'écran peut s'éteindre, mais ton Mac continue ses tâches : téléchargements, rendus, sauvegardes.",
                                      isOn: Binding(get: { m.settings.caffeineDisplay }, set: { m.setCaffeineDisplay($0) }))
                            .frame(maxWidth: 520)
                    }
                    Spacer(minLength: 0)
                }
            }
            TileRow {
                Callout(symbol: "menubar.rectangle", title: "Dans la barre des menus",
                        text: "Le bouton « Caféine » du menu d'état l'allume pour ta dernière durée (\(m.settings.caffeineMinutes == 0 ? "sans limite" : ToolboxTime.durationLabel(m.settings.caffeineMinutes))) et l'éteint d'un clic.",
                        tint: Theme.brand)
                Callout(symbol: "command", title: "Depuis le lanceur",
                        text: "Tape « caféine 1h », « caféine 45 min », « caféine indéfiniment » ou « caféine off ».", tint: Theme.brand)
                Callout(symbol: "laptopcomputer", title: "Bon à savoir",
                        text: "Rabattre l'écran d'un portable le met quand même en veille, sauf avec un écran externe et sur secteur.", tint: Theme.brand)
            }
        }
    }

    private func countdown(_ m: ToolboxModel, _ now: Date) -> String {
        guard m.caffeineActive else { return "—" }
        guard let r = m.caffeineRemaining(now) else { return "∞" }
        let s = Int(r.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func subtitle(_ m: ToolboxModel) -> String {
        guard m.caffeineActive else {
            return "Choisis une durée : pendant ce temps, ton Mac ne s'endormira pas tout seul, même sans toucher au clavier ni à la souris."
        }
        let what = m.settings.caffeineDisplay ? "Ni le Mac ni l'écran ne se mettront en veille" : "Le Mac ne se mettra pas en veille (l'écran peut s'éteindre)"
        if let end = m.caffeineEnd { return "\(what) jusqu'à \(Fmt.clock(end)), puis tout reprendra son cours." }
        return "\(what) tant que tu n'arrêtes pas Caféine."
    }
}
