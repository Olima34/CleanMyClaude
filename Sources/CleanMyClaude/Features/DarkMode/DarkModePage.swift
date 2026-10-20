import SwiftUI
import AppKit

struct DarkModePage: View {
    @Environment(AppModel.self) private var app
    static var tint: Color { Theme.palette[3] }

    var body: some View {
        let m = app.darkmode
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.darkmode.symbol, title: "Sombre partout",
                     subtitle: "Comme Noir, mais pour tout le Mac : les pages web et les apps qui restent claires passent en sombre de force.",
                     tint: Self.tint, seed: 83) {
                DarkModeStatePill()
            }
            DarkModeMacCard()
            DarkModeWebPanel()
            DarkModeAppsPanel()
            if !m.invertApps.isEmpty || m.invertFailed {
                DarkModeInvertPanel()
            }
            TileRow {
                Callout(symbol: "questionmark.circle", title: "Pourquoi une app reste claire",
                        text: "Faite avant le mode sombre (macOS 10.14, en 2018), ou réglée par son créateur pour rester claire, elle ignore l'apparence du Mac. « Sombre » lève cette exception : macOS dessine alors ses fenêtres, ses menus et ses boutons en sombre.",
                        tint: Self.tint)
                Callout(symbol: "circle.righthalf.filled.inverse", title: "« Inversée », le dernier recours",
                        text: "Une app qui dessine tout elle-même (Windows via Wine, Java…) ne suit aucun réglage. L'écran s'inverse alors quand elle passe devant et se rétablit quand tu changes d'app ; photos et vidéos restent à l'endroit dans les apps qui le permettent.",
                        tint: Self.tint)
                Callout(symbol: "arrow.uturn.backward", title: "Tout se défait",
                        text: "« Auto » remet le réglage d'origine de l'app. Dans Safari, Feuille de style : Aucune. Dans Chrome, coupe l'interrupteur. Rien n'est supprimé, et une copie des réglages de chaque navigateur est gardée.",
                        tint: Self.tint)
            }
        }
        .onAppear { m.refresh() }
    }
}

/// Apps to relaunch, or everything to put back.
struct DarkModeBottomBar: View {
    @Environment(AppModel.self) private var app
    @State private var confirmReset = false

    var body: some View {
        let m = app.darkmode
        if !m.pendingRelaunch.isEmpty {
            ActionBar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.plural(m.pendingRelaunch.count, "app à relancer", "apps à relancer")).font(.serif(17)).foregroundStyle(Theme.text)
                    Text(names(m)).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer()
                Button(m.relaunching.isEmpty ? "Relancer maintenant" : "Relance…") { m.relaunchAll() }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .disabled(!m.relaunching.isEmpty)
                    .help("Chaque app se ferme normalement (elle te demande d'enregistrer si besoin) puis se rouvre")
            }
        } else if !m.settings.choices.isEmpty {
            ActionBar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.plural(m.settings.choices.count, "app réglée", "apps réglées")).font(.serif(17)).foregroundStyle(Theme.text)
                    Text("Chacune garde son réglage d'origine de côté").font(.ui(11)).foregroundStyle(Theme.text3)
                }
                Spacer()
                Button("Tout remettre comme avant") { confirmReset = true }
                    .buttonStyle(SoftButtonStyle())
            }
            .confirmAction("Remettre toutes les apps comme avant ?", message: "Chaque app retrouve son réglage d'origine ; celles qui sont ouvertes le montrent une fois relancées.",
                           button: "Tout remettre", isPresented: $confirmReset, destructive: false) { m.resetAll() }
        }
    }

    private func names(_ m: DarkModeModel) -> String {
        m.pendingRelaunch.map { id in m.apps?.first { $0.bundleID == id }?.name ?? m.settings.names[id] ?? id }
            .sorted().joined(separator: ", ") + " : le changement se voit à la prochaine ouverture."
    }
}

/// "Mac en sombre" in the page header.
private struct DarkModeStatePill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let a = app.darkmode.appearance
        HStack(spacing: 7) {
            Circle().fill(a.isDark ? Theme.good : Theme.warn).frame(width: 7, height: 7)
            Text(a.title).font(.ui(12, .semibold))
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(PillShape().fill(Theme.card))
        .overlay(PillShape().strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

private func darkModeLabel(_ text: String, _ symbol: String) -> some View {
    HStack(spacing: 6) {
        if Theme.icons != .hidden { Image(systemName: symbol).font(.ui(11.5, .semibold)) }
        Text(text)
    }
}

private func darkModeStep(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Text("\(n)").font(.ui(11, .bold)).foregroundStyle(Theme.onAccent)
            .frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
        Text(text).font(.ui(12)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The Mac

private struct DarkModeMacCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.darkmode
        Card(padding: 22) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(headline(m)).font(.serif(24)).foregroundStyle(Theme.text)
                    Text(detail(m)).font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    if let error = m.macError {
                        Text(error).font(.ui(11.5, .medium)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        if !m.appearance.isDark || isAuto(m) {
                            Button { m.setMacDark() } label: { darkModeLabel(m.switchingMac ? "Passage en sombre…" : "Passer le Mac en sombre", "moon.fill") }
                                .buttonStyle(SoftButtonStyle(prominent: true))
                                .disabled(m.switchingMac)
                        }
                        if !m.toForce.isEmpty {
                            Button { m.forceAll() } label: { darkModeLabel("Forcer \(Fmt.plural(m.toForce.count, "app claire", "apps claires"))", "moon.stars") }
                                .buttonStyle(SoftButtonStyle(prominent: m.appearance.isDark && !isAuto(m)))
                        }
                        if m.macError != nil {
                            Button("Ouvrir Automatisation") { m.openAutomationSettings() }
                                .buttonStyle(SoftButtonStyle())
                        } else {
                            Button("Réglages d'apparence") { m.openAppearanceSettings() }
                                .buttonStyle(SoftButtonStyle())
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                DarkModeSummary()
            }
        }
    }

    private func isAuto(_ m: DarkModeModel) -> Bool {
        if case .auto = m.appearance { return true }
        return false
    }

    private func headline(_ m: DarkModeModel) -> String {
        switch m.appearance {
        case .dark: return m.toForce.isEmpty ? "Ton Mac est en sombre" : "Ton Mac est en sombre, presque partout"
        case .light: return "Ton Mac est en clair"
        case .auto(let dark): return dark ? "Sombre pour ce soir" : "Ton Mac passe en sombre le soir"
        }
    }

    private func detail(_ m: DarkModeModel) -> String {
        let rest = m.toForce.isEmpty ? "" : " \(Fmt.plural(m.toForce.count, "app l'ignore", "apps l'ignorent")) encore : force-les ci-dessous."
        switch m.appearance {
        case .dark:
            return "Les apps qui suivent le Mac sont sombres." + rest + " Les pages web claires se règlent navigateur par navigateur."
        case .light:
            return "Tout part de là : passe le Mac en sombre, et les apps qui le suivent (presque toutes) basculent avec lui. Les autres se forcent ici, comme les pages web."
        case .auto:
            return "En automatique, le Mac est clair le jour : les apps forcées suivent ce rythme. Pour du sombre toute la journée, passe-le en sombre."
        }
    }
}

/// The three figures on the right of the Mac card.
private struct DarkModeSummary: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.darkmode
        VStack(alignment: .trailing, spacing: 12) {
            if m.scanning, m.apps == nil {
                BusyMascot(.inspecting, pixel: 3)
                Text("Je regarde tes apps…").font(.ui(11.5)).foregroundStyle(Theme.text3)
            } else {
                figure("\(m.toForce.count)", m.toForce.count == 1 ? "app reste claire" : "apps restent claires", m.toForce.isEmpty ? Theme.good : Theme.warn)
                figure("\(m.settings.choices.values.filter { $0 == .dark || $0 == .invert }.count)", "forcées en sombre", Theme.text)
                figure(webValue(m), "navigateurs en sombre", Theme.text)
            }
        }
        .frame(width: 190, alignment: .trailing)
    }

    private func webValue(_ m: DarkModeModel) -> String {
        let safari = (m.settings.safariWritten != nil && m.settings.safariSelected) || !(m.extensions ?? []).isEmpty
        let done = (safari ? 1 : 0) + m.chromiumForced.count
        let total = m.browsers.filter { $0.engine != .firefox }.count
        return "\(done)/\(max(total, 1))"
    }

    private func figure(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.serif(26)).foregroundStyle(tint).monospacedDigit()
            Text(label).font(.ui(11)).foregroundStyle(Theme.text3)
        }
    }
}

// MARK: - Web pages

private struct DarkModeWebPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.darkmode
        Panel(title: "Pages web", subtitle: "Pour chaque navigateur, la méthode qui marche le mieux, sans rien installer",
              symbol: "globe", tint: DarkModePage.tint) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(m.browsers) { b in
                    switch b.engine {
                    case .safari: DarkModeSafariBlock(browser: b)
                    case .chromium: DarkModeChromiumRow(browser: b)
                    case .firefox: DarkModeFirefoxBlock(browser: b)
                    }
                }
                if m.browsers.isEmpty {
                    EmptyHint(text: "Je cherche tes navigateurs…")
                }
            }
        }
    }
}

/// A browser's block: icon, name, state on the right, then its content.
private struct DarkModeBrowserBlock<Trailing: View, Content: View>: View {
    var browser: DarkModeBrowser
    var subtitle: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                FileIcon(path: browser.appPath, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.name).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.r(12)).fill(Theme.cardRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(12)).strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

private struct DarkModeSafariBlock: View {
    @Environment(AppModel.self) private var app
    var browser: DarkModeBrowser

    var body: some View {
        let m = app.darkmode
        let ext = m.extensions?.first
        DarkModeBrowserBlock(browser: browser, subtitle: ext == nil ? "Une feuille de style que Safari applique à chaque page" : "Une extension s'en charge") {
            if let ext {
                Tag(text: "\(ext.name) installé", symbol: "checkmark", tint: Theme.good, filled: true)
            } else if m.settings.safariWritten != nil && m.settings.safariSelected {
                Tag(text: "En sombre", symbol: "moon.fill", tint: Theme.good, filled: true)
            } else if m.settings.safariWritten != nil {
                Tag(text: "Encore une étape", tint: Theme.warn, filled: true)
            } else {
                Tag(text: "À préparer", tint: Theme.text2)
            }
        } content: {
            if let ext {
                Text("\(ext.name) assombrit les pages mieux qu'une feuille de style : il lit les couleurs de chaque site. Vérifie dans Safari › Réglages… › Extensions qu'il est coché, et autorisé sur tous les sites (« Modifier les sites web… »).")
                    .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                Button("Ouvrir Safari") { m.open(browser.appPath) }
                    .buttonStyle(SoftButtonStyle(small: true))
            } else {
                styleSheet(m)
            }
        }
    }

    @ViewBuilder
    private func styleSheet(_ m: DarkModeModel) -> some View {
        @Bindable var m = m
        HStack(alignment: .top, spacing: 8) {
            ForEach(DarkModeTone.allCases) { t in toneChoice(t, m) }
        }
        VStack(alignment: .leading, spacing: 8) {
            darkModeStep(1, m.settings.safariWritten == nil ? "Prépare la feuille de style (un petit fichier de Chamois)."
                         : "Feuille de style prête, teinte \(m.settings.tone.title) : un changement de teinte la met à jour.")
            darkModeStep(2, "Dans Safari › Réglages… › Avancées, menu « Feuille de style » : choisis « Autre… ».")
            darkModeStep(3, "Dans la fenêtre qui s'ouvre, tape ⌘⇧G, colle le chemin (bouton « Copier le chemin ») puis Retour, et choisis « \(DarkModeStyleSheet.fileName) ».")
        }
        HStack(spacing: 8) {
            Button { m.prepareSafari() } label: { darkModeLabel(m.settings.safariWritten == nil ? "Préparer la feuille de style" : "Réécrire", "doc.badge.plus") }
                .buttonStyle(SoftButtonStyle(prominent: m.settings.safariWritten == nil, small: true))
            Button("Copier le chemin") { m.copyStyleSheetPath() }
                .buttonStyle(SoftButtonStyle(prominent: m.settings.safariWritten != nil && !m.settings.safariSelected, small: true))
                .disabled(m.settings.safariWritten == nil)
            Button("Ouvrir Safari") { m.open(browser.appPath) }
                .buttonStyle(SoftButtonStyle(small: true))
            Button("Afficher le fichier") { m.revealStyleSheet() }
                .buttonStyle(SoftButtonStyle(small: true))
                .disabled(m.settings.safariWritten == nil)
            Spacer(minLength: 8)
            Toggle("C'est fait", isOn: $m.settings.safariSelected)
                .font(.ui(11.5)).foregroundStyle(Theme.text2)
                .switchToggles()
                .fixedSize()
                .disabled(m.settings.safariWritten == nil)
        }
        Text("Les pages qui annoncent un thème sombre sont laissées telles quelles ; photos et vidéos retrouvent leurs couleurs (les plus vives un peu ternies). Un site sombre qui ne l'annonce pas repasse en clair : une feuille de style ne voit pas les couleurs. Noir (payant, App Store) les lit, site par site. Après un changement de teinte, recharge tes pages.")
            .font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
        Button("Voir Noir sur l'App Store") { m.openLink(DarkModeBrowsers.noirStore) }
            .buttonStyle(.plain).font(.ui(11, .medium)).foregroundStyle(Theme.accent)
    }

    private func toneChoice(_ t: DarkModeTone, _ m: DarkModeModel) -> some View {
        let selected = m.settings.tone == t
        return Button { m.setTone(t) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.ui(12)).foregroundStyle(selected ? Theme.accent : Theme.text3)
                    Text(t.title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                }
                Text(t.detail).font(.ui(11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(selected ? Theme.accent.opacity(0.1) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(selected ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DarkModeChromiumRow: View {
    @Environment(AppModel.self) private var app
    var browser: DarkModeBrowser

    var body: some View {
        let m = app.darkmode
        let busy = m.browserBusy == browser.bundleID
        DarkModeBrowserBlock(browser: browser, subtitle: subtitle(busy)) {
            if busy {
                BusyMascot(.typing, pixel: 1)
            } else if browser.forced == nil {
                Button("Ouvrir \(browser.name)") { m.open(browser.appPath) }
                    .buttonStyle(SoftButtonStyle(small: true))
            } else {
                Toggle("Pages en sombre", isOn: Binding(get: { browser.forced == true }, set: { m.setChromium(browser, $0) }))
                    .font(.ui(11.5)).foregroundStyle(Theme.text2)
                    .switchToggles()
                    .fixedSize()
                    .disabled(m.browserBusy != nil)
            }
        } content: {
            EmptyView()
        }
    }

    private func subtitle(_ busy: Bool) -> String {
        if busy { return "Fermeture, réglage, réouverture sur tes onglets…" }
        guard let forced = browser.forced else { return "Ouvre-le une première fois : il crée alors le fichier où ce réglage se range." }
        let base = forced ? "Son mode sombre intégré assombrit chaque page claire et laisse les photos intactes."
            : "Son mode sombre intégré (Auto Dark Mode) peut assombrir toutes les pages claires."
        return base + (browser.running ? " Il se fermera puis se rouvrira sur tes onglets." : "")
    }
}

private struct DarkModeFirefoxBlock: View {
    @Environment(AppModel.self) private var app
    var browser: DarkModeBrowser

    var body: some View {
        let m = app.darkmode
        DarkModeBrowserBlock(browser: browser, subtitle: "Deux réglages de Firefox, ou l'extension Dark Reader") {
            Tag(text: "Guidé", tint: Theme.text2)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                darkModeStep(1, "Firefox › Réglages › Général › Apparence des sites web : « Sombre ». Les sites qui ont un thème sombre le prennent.")
                darkModeStep(2, "Pour toutes les autres pages : l'extension gratuite Dark Reader, ou dans « Gérer les couleurs… », remplacer les couleurs des pages : « Toujours » (plus radical).")
            }
            HStack(spacing: 8) {
                Button("Ouvrir Firefox") { m.open(browser.appPath) }
                    .buttonStyle(SoftButtonStyle(small: true))
                Button("Dark Reader pour Firefox") { m.openLink(DarkModeBrowsers.darkReaderFirefox) }
                    .buttonStyle(SoftButtonStyle(small: true))
            }
        }
    }
}

// MARK: - Apps

private struct DarkModeAppsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var m = app.darkmode
        Panel(title: "Apps", subtitle: "Choisis, app par app : Auto, Sombre, Clair ou Inversée", symbol: "macwindow", tint: DarkModePage.tint) {
            if m.apps != nil {
                PillPicker(options: DarkModeAppFilter.allCases, selection: $m.filter, label: \.title) { f in
                    let n = m.list(f).count
                    return n > 0 ? "\(n)" : nil
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if m.needsDiskAccess {
                    PermissionCard(permission: .fullDiskAccess,
                                   reason: "Les apps de l'App Store rangent leurs réglages dans un dossier protégé : macOS ne laisse \(AppEdition.name) y écrire qu'avec l'accès complet au disque.")
                }
                if let apps = m.apps {
                    let list = m.list(m.filter)
                    Text(hint(m.filter, m)).font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    if list.isEmpty {
                        EmptyHint(text: empty(m.filter, total: apps.count))
                    } else {
                        VStack(spacing: 2) {
                            ForEach(list) { a in DarkModeAppRow(item: a) }
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        BusyMascot(.inspecting, pixel: 2)
                        Text("Je regarde comment chaque app gère le mode sombre…").font(.ui(12)).foregroundStyle(Theme.text2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                }
            }
        }
    }

    private func hint(_ f: DarkModeAppFilter, _ m: DarkModeModel) -> String {
        switch f {
        case .lightOnly: return "Elles ignorent le mode sombre du Mac. « Sombre » les fait suivre, à la prochaine ouverture."
        case .ownUI: return "Elles dessinent leur propre interface : leur thème se choisit dans leurs réglages, et la plupart suivent déjà le Mac. Si l'une reste claire, choisis « Inversée »."
        case .follows: return "Elles suivent déjà le Mac. « Clair » en garde une claire si tu préfères."
        case .chosen: return "Ce que tu as réglé. « Auto » remet le réglage d'origine."
        }
    }

    private func empty(_ f: DarkModeAppFilter, total: Int) -> String {
        switch f {
        case .lightOnly: return "Aucune app ne reste claire : les \(total) suivent le mode sombre."
        case .ownUI: return "Aucune app à l'interface maison."
        case .follows: return "Aucune."
        case .chosen: return "Aucune app réglée pour l'instant."
        }
    }
}

private struct DarkModeAppRow: View {
    @Environment(AppModel.self) private var app
    var item: DarkModeApp

    var body: some View {
        let m = app.darkmode
        let c = m.choice(item)
        HoverRow {
            HStack(spacing: 10) {
                FileIcon(path: item.path, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        if let tk = item.toolkit { Tag(text: tk) }
                        if c == .dark, item.kind == .lightOnly { Tag(text: "Forcée", symbol: "moon.fill", tint: Theme.good, filled: true) }
                    }
                    Text(item.reason).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 8)
                if m.pendingRelaunch.contains(item.bundleID) {
                    Button(m.relaunching.contains(item.bundleID) ? "Relance…" : "Relancer") { m.relaunch(item.bundleID) }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .disabled(m.relaunching.contains(item.bundleID))
                        .help("Elle se ferme normalement, puis se rouvre en \(c == .light ? "clair" : "sombre")")
                }
                if m.applying.contains(item.bundleID) {
                    BusyMascot(.typing, pixel: 1)
                }
                DarkModeChoiceMenu(item: item, choice: c)
            }
        }
    }
}

private struct DarkModeChoiceMenu: View {
    @Environment(AppModel.self) private var app
    var item: DarkModeApp
    var choice: DarkModeChoice

    var body: some View {
        let m = app.darkmode
        BorderlessMenu {
            ForEach(DarkModeChoice.allCases) { c in
                Button {
                    m.setChoice(item, c)
                } label: {
                    if c == choice {
                        Label("\(c.title) · \(c.detail)", systemImage: "checkmark")
                    } else {
                        Text("\(c.title) · \(c.detail)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if Theme.icons != .hidden { Image(systemName: choice.symbol).font(.ui(10.5, .semibold)) }
                Text(choice.title).font(.ui(11.5, .medium))
            }
            .foregroundStyle(choice == .system ? Theme.text2 : Theme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PillShape().fill(choice == .system ? Theme.track : Theme.accent.opacity(0.14)))
        .frame(width: 118, alignment: .trailing)
    }
}

// MARK: - Inversion

private struct DarkModeInvertPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.darkmode
        let names = m.invertApps.map { id in m.apps?.first { $0.bundleID == id }?.name ?? m.settings.names[id] ?? id }.sorted()
        Panel(title: "Inversion automatique", subtitle: names.isEmpty ? nil : "Quand \(names.joined(separator: ", ")) passe devant, l'écran s'inverse",
              symbol: "circle.righthalf.filled.inverse", tint: DarkModePage.tint) {
            VStack(alignment: .leading, spacing: 10) {
                if m.invertFailed {
                    Text("macOS n'a pas répondu à l'inversion sur ce Mac. Active-la toi-même dans Réglages Système › Accessibilité › Écran › Inverser les couleurs, ou avec son raccourci si tu l'as activé.")
                        .font(.ui(12, .medium)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("C'est l'inversion des couleurs de macOS (Accessibilité › Écran) : Chamois l'allume en arrivant sur l'app et l'éteint en la quittant. Une inversion que tu as allumée toi-même n'est jamais éteinte.")
                        .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button { m.testInvert() } label: { darkModeLabel(m.testingInvert ? "Trois secondes…" : "Essayer 3 secondes", "circle.righthalf.filled.inverse") }
                        .buttonStyle(SoftButtonStyle(small: true))
                        .disabled(m.testingInvert)
                    Button("Réglages d'accessibilité") { m.openDisplaySettings() }
                        .buttonStyle(SoftButtonStyle(small: true))
                }
            }
        }
    }
}
