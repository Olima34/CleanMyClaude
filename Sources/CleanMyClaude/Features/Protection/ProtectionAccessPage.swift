import SwiftUI

// MARK: - Access

struct AccessTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Callout(symbol: "hand.raised", title: "Qui t'observe",
                        text: "Ce qui peut lire ce que tu tapes, voir les pages que tu visites ou accepter des connexions du réseau. La plupart du temps ce sont des outils que tu as choisis ; ce qui ne l'est pas saute aux yeux.")
                Button {
                    Task { await model.checkAccess() }
                } label: {
                    HStack(spacing: 6) {
                        if model.isCheckingAccess { ProgressView().controlSize(.small).scaleEffect(0.7) }
                        Text(model.accessChecked == nil ? "Vérifier" : "Revérifier")
                    }
                }
                .buttonStyle(SoftButtonStyle(prominent: model.accessChecked == nil))
                .disabled(model.isCheckingAccess)
            }
            if model.accessChecked == nil && !model.isCheckingAccess {
                Card { EmptyHint(text: "Lance la vérification pour voir les espions du clavier, les extensions et les ports ouverts.", symbol: "eye") }
            } else {
                KeyboardTapsPanel()
                ExtensionsPanel()
                PortsPanel()
            }
            GrantsSection()
        }
    }
}

struct KeyboardTapsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let taps = app.protection.keyboardTaps
        let others = taps.filter { $0.risk != .ok }
        Panel(title: "Peut lire tout ce que tu tapes",
              subtitle: others.isEmpty ? "Seuls des composants d'Apple écoutent le clavier. Aucun enregistreur de frappe."
                                       : "Ces programmes reçoivent chaque touche, mots de passe compris. Normal pour un lanceur ou un utilitaire de raccourcis ; pas pour un programme inconnu.",
              symbol: "keyboard", tint: others.contains { $0.risk == .bad } ? Theme.bad : (others.isEmpty ? Theme.good : Theme.warn)) {
            VStack(spacing: 2) {
                ForEach(others) { t in
                    HoverRow {
                        HStack(spacing: 12) {
                            if let a = t.appPath { FileIcon(path: a, size: 26) } else { IconBadge(symbol: "keyboard", tint: t.risk.color, size: 26) }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(t.name).font(.ui(12.5, .medium)).foregroundStyle(Theme.text)
                                    Tag(text: t.signature.label, symbol: t.signature.isTrusted ? "checkmark.seal" : "seal",
                                        tint: t.signature.isTrusted ? Theme.good : Theme.bad, filled: true)
                                    if t.canModify { Tag(text: "Peut modifier les touches", tint: Theme.text3) }
                                }
                                Text(FS.pretty(t.path)).font(.mono(10.5)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if t.risk == .bad { StatusBadge(status: .bad, text: "Suspect") }
                            BorderlessMenu(indicator: false) {
                                Button("Afficher dans le Finder") { Finder.reveal(t.appPath ?? t.path) }
                                Button("Gérer la surveillance de la saisie") { Finder.open(SettingsPane.privacy("Privacy_ListenEvent")) }
                                Button("Gérer l'accessibilité") { Finder.open(SettingsPane.privacy("Privacy_Accessibility")) }
                                Button("Demander à Claude ce que c'est") {
                                    app.assistant.explain(t.name, details: ["Écoute le clavier", "Programme : \(t.path)", "Signature : \(t.signature.label)"])
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.ui(14)).foregroundStyle(Theme.text2)
                            }
                        }
                    }
                }
                let apple = taps.count - others.count
                if apple > 0 {
                    Text("Et \(Fmt.plural(apple, "composant", "composants")) d'Apple (accessibilité, saisie de texte).")
                        .font(.ui(11)).foregroundStyle(Theme.text3).padding(.horizontal, 10).padding(.top, 4)
                }
            }
        }
    }
}

struct ExtensionsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let list = app.protection.extensions
        let forced = list.filter(\.forced)
        Panel(title: "Extensions de navigateur",
              subtitle: list.isEmpty ? "Aucune extension installée." :
                (forced.isEmpty ? "\(Fmt.plural(list.count, "extension", "extensions")), dont \(list.filter(\.readsEverything).count) qui lisent toutes les pages que tu visites."
                                : "\(Fmt.plural(forced.count, "extension imposée", "extensions imposées")) par un réglage : tu ne peux pas la retirer toi-même. Hors entreprise, c'est la marque d'un logiciel publicitaire."),
              symbol: "puzzlepiece.extension", tint: forced.isEmpty ? Theme.accent : Theme.bad) {
            VStack(spacing: 2) {
                ForEach(list.prefix(14)) { e in
                    HoverRow {
                        HStack(spacing: 10) {
                            IconBadge(symbol: e.browser == "Safari" ? "safari" : "globe", tint: e.forced ? Theme.bad : (e.readsEverything ? Theme.warn : Theme.accent), size: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(e.name).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                    Tag(text: e.browser, tint: Theme.text3)
                                    if !e.enabled { Tag(text: "Désactivée", tint: Theme.text3) }
                                }
                                Text(e.forced ? "Imposée par un réglage (politique ou profil)" : (e.readsEverything ? "Peut lire et modifier toutes les pages" : "Accès limité à certains sites"))
                                    .font(.ui(11)).foregroundStyle(e.forced ? Theme.bad : Theme.text3)
                            }
                            Spacer()
                            BorderlessMenu(indicator: false) {
                                if FS.exists(e.container) { Button("Afficher dans le Finder") { Finder.reveal(e.container) } }
                                if e.browser == "Safari" { Button("Gérer dans Safari") { Finder.open(SettingsPane.extensions) } }
                                if e.forced { Button("Voir les profils installés") { Finder.open(SettingsPane.profiles) } }
                                Button("Demander à Claude ce que c'est") {
                                    app.assistant.explain(e.name, details: ["Extension \(e.browser)", "Identifiant : \(e.identifier)",
                                                                            e.readsEverything ? "Lit toutes les pages" : "Accès limité"])
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.ui(14)).foregroundStyle(Theme.text2)
                            }
                        }
                    }
                }
                if list.count > 14 {
                    Text("et \(list.count - 14) autres").font(.ui(11)).foregroundStyle(Theme.text3).padding(.horizontal, 10)
                }
            }
        }
    }
}

struct PortsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let ports = app.protection.exposedPorts
        Panel(title: "Ouvert sur le réseau",
              subtitle: ports.isEmpty ? "Aucun de tes programmes n'accepte de connexion venue d'un autre appareil."
                                      : "Ces programmes acceptent des connexions des autres appareils du réseau (un Wi-Fi public aussi). Le coupe-feu filtre ceux que tu n'as pas autorisés.",
              symbol: "network", tint: ports.contains { !$0.isSystem } ? Theme.warn : Theme.good) {
            Button("Détails") {
                app.page = .network
            }
            .buttonStyle(SoftButtonStyle(small: true))
        } content: {
            VStack(spacing: 2) {
                ForEach(ports.prefix(10)) { p in
                    HoverRow {
                        HStack(spacing: 10) {
                            if let a = p.appPath { FileIcon(path: a, size: 22) } else { IconBadge(symbol: "server.rack", tint: Theme.text2, size: 22) }
                            Text(p.displayName).font(.ui(12.5, .medium)).foregroundStyle(Theme.text)
                            if let d = NetworkPorts.describe(p) { Text(d).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1) }
                            Spacer()
                            Text(verbatim: "port \(p.port)").font(.mono(11)).foregroundStyle(Theme.text2)
                        }
                    }
                }
            }
        }
    }
}

struct GrantsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        if let grants = model.grants {
            let services = TCCService.all.filter { s in grants.contains { $0.service == s } }
            if !services.isEmpty {
                SectionLabel(text: "Autorisations accordées")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(services, id: \.key) { s in
                        let list = grants.filter { $0.service == s }
                        Panel(title: s.title, subtitle: Fmt.plural(list.count, "app autorisée", "apps autorisées"), symbol: s.symbol,
                              tint: s.sensitive ? Theme.warn : Theme.accent) {
                            Button("Gérer") { Finder.open(SettingsPane.privacy(s.anchor)) }
                                .buttonStyle(SoftButtonStyle(small: true))
                        } content: {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(list.prefix(8)) { g in
                                    HStack(spacing: 9) {
                                        if let p = g.path { FileIcon(path: p, size: 20) } else { IconBadge(symbol: "app.dashed", tint: Theme.text3, size: 20) }
                                        Text(g.name).font(.ui(12)).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer()
                                        if let d = g.lastModified {
                                            Text(Fmt.relative(d)).font(.ui(10.5)).foregroundStyle(Theme.text3)
                                        }
                                    }
                                }
                                if list.count > 8 {
                                    Text("et \(list.count - 8) autres").font(.ui(11)).foregroundStyle(Theme.text3)
                                }
                            }
                        }
                    }
                }
            }
        } else if model.hasAudit || model.accessChecked != nil {
            FullDiskAccessCard(reason: "macOS cache la liste des autorisations (caméra, micro, écran, accessibilité…) aux apps qui n'ont pas l'accès complet au disque.")
        }
    }
}

// MARK: - Real time

struct RealtimeTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.protection
        VStack(alignment: .leading, spacing: 14) {
            if !model.realtime.anyOn {
                Card(padding: 22) {
                    HStack(alignment: .center, spacing: 18) {
                        IconBadge(symbol: "shield.lefthalf.filled.badge.checkmark", tint: Theme.good, size: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Une protection qui veille pendant que tu travailles").font(.serif(22)).foregroundStyle(Theme.text)
                            Text("Je te préviens dès qu'un programme s'ajoute au démarrage, qu'une menace arrive dans Téléchargements, que la caméra ou le micro s'allume, ou que tes réglages réseau changent. Tout réagit aux événements de macOS : aucune analyse permanente, ton Mac ne ralentit pas.")
                                .font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Tout activer") { model.enableRealtime() }.buttonStyle(SoftButtonStyle(prominent: true))
                    }
                }
            }
            Panel(title: "Surveillance", subtitle: "Chaque alerte arrive en notification et s'inscrit dans le journal ci-dessous.",
                  symbol: "dot.radiowaves.left.and.right", tint: model.realtime.anyOn ? Theme.good : Theme.text3) {
                VStack(spacing: 10) {
                    RealtimeToggle(title: "Nouveaux éléments de démarrage", symbol: "arrow.clockwise.circle",
                                   text: "Un agent ou un service qui s'installe : je vérifie sa signature et son comportement aussitôt.",
                                   isOn: $model.realtime.persistence)
                    RealtimeToggle(title: "Fichiers téléchargés", symbol: "arrow.down.circle",
                                   text: "Chaque app, script ou installeur qui arrive dans Téléchargements passe aux signatures d'Apple avant que tu l'ouvres.",
                                   isOn: $model.realtime.downloads)
                    RealtimeToggle(title: "Caméra et micro", symbol: "camera",
                                   text: "Une alerte quand l'un d'eux s'allume, même pour une seconde.",
                                   isOn: $model.realtime.devices)
                    RealtimeToggle(title: "Réglages réseau", symbol: "network",
                                   text: "Un serveur DNS inconnu ou un proxy qui apparaît : la signature des pirates de navigation.",
                                   isOn: $model.realtime.network)
                }
                .switchToggles()
            }
            Panel(title: "Journal", subtitle: model.events.isEmpty ? "Rien à signaler pour l'instant." : "Les 200 derniers événements.",
                  symbol: "list.bullet.rectangle", tint: Theme.accent) {
                if !model.events.isEmpty {
                    Button("Effacer") { model.clearEvents() }.buttonStyle(SoftButtonStyle(small: true))
                }
            } content: {
                VStack(spacing: 2) {
                    ForEach(model.events.prefix(40)) { e in
                        HoverRow {
                            HStack(alignment: .top, spacing: 10) {
                                IconBadge(symbol: e.kind.symbol, tint: e.status.color, size: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                                    Text(e.detail).font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Text(Fmt.relative(e.date)).font(.ui(10.5)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RealtimeToggle: View {
    var title: String
    var symbol: String
    var text: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 10) {
                IconBadge(symbol: symbol, tint: isOn ? Theme.good : Theme.text3, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                    Text(text).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
            }
        }
    }
}
