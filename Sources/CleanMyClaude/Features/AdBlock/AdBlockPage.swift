import SwiftUI
import AppKit

struct AdBlockPage: View {
    @Environment(AppModel.self) private var app
    static var tint: Color { Theme.palette[6] }

    var body: some View {
        let m = app.adblock
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.adblock.symbol, title: "Bloqueur de pub",
                     subtitle: "Les pubs, les pisteurs et les sites piégés bloqués pour tout le Mac : tous les navigateurs, les apps et les jeux, sans extension à installer.",
                     tint: Self.tint, seed: 71) {
                AdBlockStatePill()
            }
            if m.waitingForInstall, !m.state.isOn {
                AdBlockInstallSteps()
            } else {
                AdBlockStatusCard()
            }
            AdBlockLevelPanel()
            TileRow {
                AdBlockExceptionsPanel()
                AdBlockCheckPanel()
            }
            if let measure = m.measure {
                AdBlockMeasurePanel(measure: measure)
            }
            TileRow {
                Callout(symbol: "play.rectangle", title: "Ce qu'un DNS ne bloque pas",
                        text: "Les pubs servies par le site lui-même : YouTube, Twitch, les posts sponsorisés d'Instagram ou de Facebook. Pour celles-là, ajoute une extension à ton navigateur : uBlock Origin Lite (Chrome, Edge, Brave), uBlock Origin (Firefox), AdGuard ou Wipr (Safari).",
                        tint: Self.tint)
                Callout(symbol: "lock", title: "Où partent tes requêtes",
                        text: resolverText(m), tint: Self.tint)
                Callout(symbol: "wrench.adjustable", title: "Un site ne marche plus ?",
                        text: "Ajoute son domaine aux exceptions (il passera par le DNS de ton réseau, sans filtre), ou passe en Équilibré, qui laisse passer les services dont certains sites ont besoin.",
                        tint: Self.tint)
            }
        }
        .onAppear { m.refreshState() }
    }

    private func resolverText(_ m: AdBlockModel) -> String {
        let network = m.resolvers.first.map { ip in SecurityAudit.isPrivate(ip) ? "à ta box (\(ip))" : "à \(ip)" } ?? "au DNS de ton réseau"
        return "Avec le bloqueur, ton Mac demande l'adresse des sites à Control D, chiffrée (DNS-over-HTTPS). Control D applique les listes HaGeZi, mises à jour plusieurs fois par jour, et dit ne garder aucun journal de ses DNS gratuits. Sans le bloqueur, ton Mac la demande en clair \(network)."
    }
}

/// Shown only when the profile's level or exceptions changed since it was installed.
struct AdBlockBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.adblock
        if m.needsReinstall, !m.waitingForInstall {
            ActionBar {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Changements à appliquer").font(.serif(17)).foregroundStyle(Theme.text)
                    Text("Niveau \(m.settings.level.title) · \(Fmt.plural(m.settings.exceptions.count, "exception", "exceptions")) : réinstalle le profil, macOS remplace l'ancien.")
                        .font(.ui(11)).foregroundStyle(Theme.text3)
                }
                Spacer()
                Button("Réinstaller le profil") { m.install() }
                    .buttonStyle(SoftButtonStyle(prominent: true))
            }
        }
    }
}

/// "Pubs bloquées · Maximal" in the page header.
private struct AdBlockStatePill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let state = app.adblock.state
        HStack(spacing: 7) {
            if state == .checking {
                BusyMascot(.inspecting, pixel: 1)
            } else {
                Circle().fill(color(state)).frame(width: 7, height: 7)
            }
            Text(label(state)).font(.ui(12, .semibold))
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(PillShape().fill(Theme.card))
        .overlay(PillShape().strokeBorder(Theme.border, lineWidth: Theme.line))
    }

    private func color(_ s: AdBlockState) -> Color {
        switch s {
        case .on: return Theme.good
        case .off: return Theme.warn
        default: return Theme.text3
        }
    }

    private func label(_ s: AdBlockState) -> String {
        switch s {
        case .on(let level): return "Pubs bloquées" + (level.map { " · \($0.title)" } ?? "")
        case .off: return "Pubs non bloquées"
        case .offline: return "Pas de réseau"
        case .checking: return "Vérification…"
        case .unknown: return "État inconnu"
        }
    }
}

// MARK: - State and main actions

private struct AdBlockStatusCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.adblock
        Card(padding: 22) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(headline(m)).font(.serif(24)).foregroundStyle(Theme.text)
                    Text(detail(m)).font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) { buttons(m) }
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
                if m.measuring {
                    VStack(alignment: .trailing, spacing: 8) {
                        BusyMascot(.inspecting, pixel: 4)
                        Text(m.measuringLevel.map { "Je questionne le DNS du niveau \($0.title)…" } ?? "J'essaie \(AdBlockCanary.ads.count + AdBlockCanary.useful.count) domaines…")
                            .font(.ui(11.5)).foregroundStyle(Theme.text3)
                    }
                    .frame(width: 220, alignment: .trailing)
                } else if let measure = m.measure, !measure.offline {
                    AdBlockScore(measure: measure)
                }
            }
        }
    }

    private func headline(_ m: AdBlockModel) -> String {
        switch m.state {
        case .on: return "Les pubs sont bloquées sur tout le Mac"
        case .off: return m.installed && !m.waitingForInstall ? "Le bloqueur n'est plus actif" : "Les pubs passent encore"
        case .offline: return "Pas de réseau pour vérifier"
        case .checking, .unknown: return "Vérification du blocage…"
        }
    }

    private func detail(_ m: AdBlockModel) -> String {
        switch m.state {
        case .on(let level):
            let l = level ?? m.settings.level
            var text = "Niveau \(l.title) (\(l.list)), par un DNS chiffré : Safari, Chrome, Firefox, les apps et les jeux en profitent, sans rien installer d'autre."
            if m.settings.installedLevel == nil { text += " Un autre outil que Clean My Claude bloque déjà les pubs sur ce Mac." }
            return text
        case .off:
            if m.installed && !m.waitingForInstall {
                return "Le profil a été retiré, ou désactivé dans Réglages Système › Réseau › Filtres. Réinstalle-le en un clic."
            }
            return "Le bloqueur installe un profil DNS : macOS te demande ton accord dans Réglages Système, et tu peux le retirer quand tu veux. Choisis d'abord le niveau ci-dessous."
        case .offline:
            return "Aucun site ne répond. Reconnecte-toi, puis vérifie à nouveau."
        case .checking, .unknown:
            return "Quelques questions au DNS de ce Mac, une seconde."
        }
    }

    @ViewBuilder
    private func buttons(_ m: AdBlockModel) -> some View {
        switch m.state {
        case .on:
            Button { m.runMeasure() } label: { label("Mesurer sur ce Mac", "gauge.with.needle") }
                .buttonStyle(SoftButtonStyle(prominent: true))
                .disabled(m.measuring)
            if m.installed {
                Button { m.remove() } label: { label(m.removing ? "Retrait…" : "Désactiver", "hand.raised.slash") }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(m.removing)
            }
        case .off:
            Button { m.install() } label: { label(m.installed ? "Réinstaller le bloqueur" : "Installer le bloqueur", "hand.raised") }
                .buttonStyle(SoftButtonStyle(prominent: true))
            Button { m.runMeasure(level: m.settings.level) } label: { label("Mesurer avant d'installer", "gauge.with.needle") }
            .buttonStyle(SoftButtonStyle())
            .disabled(m.measuring)
            .help("Pose les mêmes questions au DNS du niveau \(m.settings.level.title), sans rien changer sur ton Mac")
        case .offline, .unknown:
            Button { m.refreshState() } label: { label("Vérifier", "arrow.clockwise") }
                .buttonStyle(SoftButtonStyle())
        case .checking:
            EmptyView()
        }
    }

    private func label(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            if Theme.icons != .hidden { Image(systemName: symbol).font(.ui(11.5, .semibold)) }
            Text(text)
        }
    }
}

/// The share of ads blocked by the last measurement, big.
private struct AdBlockScore: View {
    var measure: AdBlockMeasure

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("\(Int((measure.share * 100).rounded())) %").font(.serif(40)).foregroundStyle(Theme.text).monospacedDigit()
            Text("des pubs et pisteurs testés bloqués").font(.ui(11.5)).foregroundStyle(Theme.text3)
            UsageBar(fraction: measure.share, tint: measure.share >= 0.8 ? Theme.good : (measure.share >= 0.4 ? Theme.warn : Theme.bad), height: 7)
                .frame(width: 200)
            Text(measure.level.map { "Aperçu du niveau \($0.title) · \(Fmt.relative(measure.date))" } ?? "Sur ce Mac · \(Fmt.relative(measure.date))")
                .font(.ui(11)).foregroundStyle(Theme.text3)
        }
        .frame(width: 220, alignment: .trailing)
    }
}

/// After the profile was opened: what to do in System Settings.
private struct AdBlockInstallSteps: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.adblock
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BusyMascot(.checking, pixel: 2)
                    Text("Encore une étape dans Réglages Système").font(.ui(15, .semibold)).foregroundStyle(Theme.text)
                }
                step(1, "Réglages Système s'est ouvert sur les profils (Général › Gestion des appareils, ou Profils). Sinon, clique sur « Ouvrir les profils ».")
                step(2, "Double-clique « \(AdBlockProfile.displayName) », puis Installer, et confirme avec ton mot de passe.")
                step(3, "Reviens ici : la vérification se lance toute seule.")
                HStack(spacing: 10) {
                    Button("Ouvrir les profils") { m.openProfiles() }
                        .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                    Button("Vérifier maintenant") { m.refreshState() }
                        .buttonStyle(SoftButtonStyle(small: true))
                    Button("Annuler") { m.waitingForInstall = false }
                        .buttonStyle(SoftButtonStyle(small: true))
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.ui(11.5, .bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20).background(Circle().fill(Theme.accent))
            Text(text).font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Level

private struct AdBlockLevelPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.adblock
        Panel(title: "Niveau de blocage", subtitle: "Les listes HaGeZi, appliquées par le DNS chiffré de Control D", symbol: "slider.horizontal.3", tint: AdBlockPage.tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(AdBlockLevel.allCases) { level in choice(level, m) }
                }
                if m.needsReinstall, m.settings.installedLevel != m.settings.level {
                    Text("Le profil installé est en \(m.settings.installedLevel?.title ?? "") : réinstalle-le pour passer en \(m.settings.level.title).")
                        .font(.ui(11.5, .medium)).foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func choice(_ level: AdBlockLevel, _ m: AdBlockModel) -> some View {
        let selected = m.settings.level == level
        return Button { m.settings.level = level } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.ui(13)).foregroundStyle(selected ? Theme.accent : Theme.text3)
                    Text(level.title).font(.ui(13.5, .semibold)).foregroundStyle(Theme.text)
                    Text(level.list).font(.ui(11)).foregroundStyle(Theme.text3)
                    Spacer(minLength: 0)
                    if level == .maximal { Tag(text: "Recommandé", tint: Theme.good, filled: true) }
                    if case .on(let active) = m.state, active == level { Tag(text: "Actif", symbol: "checkmark", tint: Theme.good, filled: true) }
                }
                Text(level.detail).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(selected ? Theme.accent.opacity(0.1) : Theme.cardRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(12)).strokeBorder(selected ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Exceptions

private struct AdBlockExceptionsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.adblock
        Panel(title: "Exceptions", subtitle: "Ces domaines passent par le DNS de ton réseau, sans filtre", symbol: "checkmark.shield", tint: AdBlockPage.tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AdBlockField(placeholder: "boutique.fr ou l'adresse d'une page", text: $m.exceptionDraft) { m.addException(m.exceptionDraft) }
                    Button("Ajouter") { m.addException(m.exceptionDraft) }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .disabled(m.exceptionDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = m.exceptionError {
                    Text(error).font(.ui(11.5, .medium)).foregroundStyle(Theme.warn)
                }
                if m.settings.exceptions.isEmpty {
                    Text("Aucune pour l'instant. Les pages de connexion des Wi-Fi publics et les noms de ton réseau local passent déjà sans filtre.")
                        .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(m.settings.exceptions, id: \.self) { d in
                            HStack(spacing: 5) {
                                Text(d).font(.ui(11.5, .medium)).foregroundStyle(Theme.text)
                                Button { m.removeException(d) } label: {
                                    Image(systemName: "xmark").font(.ui(9, .bold)).foregroundStyle(Theme.text3)
                                }
                                .buttonStyle(.plain)
                                .help("Retirer l'exception")
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(PillShape().fill(Theme.track))
                        }
                    }
                }
                if m.needsReinstall, Set(m.settings.installedExceptions ?? []) != Set(m.settings.exceptions) {
                    Button("Réinstaller le profil pour les appliquer") { m.install() }
                        .buttonStyle(SoftButtonStyle(prominent: true, small: true))
                }
            }
        }
    }
}

// MARK: - Checking a domain

private struct AdBlockCheckPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.adblock
        Panel(title: "Vérifier un domaine", subtitle: "Bloqué sur ce Mac ? Dans la liste du niveau choisi ?", symbol: "magnifyingglass", tint: AdBlockPage.tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AdBlockField(placeholder: "pub.exemple.fr", text: $m.checkText) { m.checkDomain() }
                    Button("Vérifier") { m.checkDomain() }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .disabled(m.checking || m.checkText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if m.checking {
                    HStack(spacing: 10) {
                        BusyMascot(.searching, pixel: 1.5)
                        Text("Je regarde sur ce Mac et dans la liste \(m.settings.level.list)…").font(.ui(12)).foregroundStyle(Theme.text3)
                    }
                } else if let c = m.check {
                    VStack(alignment: .leading, spacing: 6) {
                        if c.onMac == .missing, c.inList == .missing {
                            line("Ce domaine n'existe pas : vérifie son orthographe", ok: false)
                        } else {
                            line(macText(c.onMac), ok: c.onMac.stopped)
                            line(listText(c), ok: c.inList == .blocked)
                        }
                        if c.excepted {
                            line("Dans tes exceptions : il passe toujours", ok: false)
                        }
                    }
                    HStack(spacing: 8) {
                        if c.excepted {
                            Button("Retirer des exceptions") {
                                for e in m.settings.exceptions where c.domain == e || c.domain.hasSuffix("." + e) { m.removeException(e) }
                            }
                            .buttonStyle(SoftButtonStyle(small: true))
                        } else if c.onMac.stopped || c.inList == .blocked {
                            Button("Ajouter aux exceptions") { m.addException(c.domain) }
                                .buttonStyle(SoftButtonStyle(small: true))
                        }
                    }
                } else {
                    Text("Un site affiche une erreur ? Vérifie ses domaines ici, puis ajoute-les aux exceptions si besoin.")
                        .font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func macText(_ v: AdBlockVerdict) -> String {
        switch v {
        case .blocked: return "Bloqué sur ce Mac"
        case .missing: return "Introuvable sur ce Mac (bloqué par un autre outil ?)"
        case .open: return "Passe sur ce Mac"
        case .unknown: return "Pas de réponse sur ce Mac"
        }
    }

    private func listText(_ c: AdBlockCheck) -> String {
        switch c.inList {
        case .blocked: return "Dans la liste \(c.level.list)"
        case .open, .missing: return "Pas dans la liste \(c.level.list)"
        case .unknown: return "Liste \(c.level.list) injoignable"
        }
    }

    private func line(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed").font(.ui(12)).foregroundStyle(ok ? Theme.good : Theme.text3)
            Text(text).font(.ui(12.5)).foregroundStyle(Theme.text)
        }
    }
}

/// A plain text field (a drawn one in snapshots).
private struct AdBlockField: View {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        Group {
            if Snapshot.isActive {
                Text(text.isEmpty ? placeholder : text).font(.ui(12.5)).foregroundStyle(text.isEmpty ? Theme.text3 : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.ui(12.5))
                    .onSubmit(onSubmit)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(8)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

// MARK: - Measurement

private struct AdBlockMeasurePanel: View {
    var measure: AdBlockMeasure
    @State private var all = false

    var body: some View {
        let missed = measure.ads.filter { !$0.verdict.stopped }
        let broken = measure.useful.filter { $0.verdict != .open }
        Panel(title: "Dernière mesure", subtitle: subtitle, symbol: "gauge.with.needle", tint: AdBlockPage.tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    figure("\(measure.blockedAds)/\(measure.ads.count)", "pubs et pisteurs bloqués")
                    figure("\(measure.useful.count - broken.count)/\(measure.useful.count)", "sites utiles joignables")
                }
                if !missed.isEmpty {
                    Text("Passent encore : " + missed.map(\.domain).joined(separator: ", "))
                        .font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
                if !broken.isEmpty {
                    Text("Sites utiles sans réponse : " + broken.map(\.domain).joined(separator: ", "))
                        .font(.ui(11.5, .medium)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                }
                Button(all ? "Masquer le détail" : "Voir les \(measure.probes.count) domaines testés") { all.toggle() }
                    .buttonStyle(SoftButtonStyle(small: true))
                if all || Snapshot.isActive {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 5) {
                        ForEach(measure.probes) { p in
                            HStack(spacing: 6) {
                                Image(systemName: p.good ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.ui(11)).foregroundStyle(p.good ? Theme.good : (p.shouldBlock ? Theme.warn : Theme.bad))
                                Text(p.domain).font(.mono(11)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                Text(p.shouldBlock ? (p.verdict.stopped ? "bloqué" : "passe") : (p.verdict == .open ? "joignable" : "bloqué"))
                                    .font(.ui(10.5)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        (measure.level.map { "Aperçu du niveau \($0.title), avant installation" } ?? "Sur ce Mac") + " · " + Fmt.relative(measure.date)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.serif(22)).foregroundStyle(Theme.text).monospacedDigit()
            Text(label).font(.ui(11)).foregroundStyle(Theme.text3)
        }
    }
}
