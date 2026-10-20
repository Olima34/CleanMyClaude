import SwiftUI

struct CinemaPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.cinema
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.cinema.symbol, title: "Films et séries",
                     subtitle: "Cherche un film ou une série : sa fiche, sa bande-annonce sans pub et les plateformes où le regarder. Depuis le lanceur aussi : tape « film », « série » ou « regarder » puis le titre.",
                     tint: CinemaStyle.tint, seed: 61)
            if !model.hasKey {
                CinemaKeySetup()
            } else {
                CinemaSearchCard()
                if let results = model.pageResults {
                    TileRow(spacing: 16) {
                        CinemaResultsCard(state: results)
                            .frame(width: 320)
                        Card(padding: 20) {
                            if let hit = model.selected {
                                CinemaTitleCard(hit: hit)
                            } else {
                                Text("Choisis un titre dans la liste pour voir sa fiche et où le regarder.")
                                    .font(.ui(12.5)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                } else if let hit = model.selected {
                    Card(padding: 20) { CinemaTitleCard(hit: hit) }
                }
                if !model.recents.isEmpty {
                    CinemaRecentsRow()
                }
                CinemaPlatformsPanel()
                CinemaCredit()
            }
        }
    }
}

// MARK: - Search

struct CinemaSearchCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.cinema
        Card(padding: 14) {
            HStack(spacing: 10) {
                if Theme.icons != .hidden {
                    Image(systemName: "magnifyingglass").font(.ui(13, .medium)).foregroundStyle(Theme.text3)
                }
                if Snapshot.isActive {
                    Text(model.pageQuery.isEmpty ? "Un film, une série…" : model.pageQuery)
                        .font(.ui(14)).foregroundStyle(model.pageQuery.isEmpty ? Theme.text3 : Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Un film, une série…", text: $model.pageQuery)
                        .textFieldStyle(.plain).font(.ui(14))
                        .onSubmit { model.searchFromPage() }
                        .onChange(of: model.pageQuery) { _, text in
                            let q = text.trimmingCharacters(in: .whitespaces)
                            if q.count >= 2 { model.startSearch(q, kind: model.pageKind, delay: 0.45) }
                        }
                }
                CinemaKindPicker(kind: $model.pageKind)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.pageKind) { _, _ in model.searchFromPage() }
    }
}

/// Tout / Films / Séries, drawn by hand (it renders in snapshots).
struct CinemaKindPicker: View {
    @Binding var kind: CinemaKind?

    var body: some View {
        HStack(spacing: 2) {
            chip("Tout", nil)
            chip("Films", .movie)
            chip("Séries", .tv)
        }
        .padding(2)
        .background(PillShape().fill(Theme.track))
    }

    private func chip(_ label: String, _ value: CinemaKind?) -> some View {
        let on = kind == value
        return Button { kind = value } label: {
            Text(label).font(.ui(11.5, .medium))
                .foregroundStyle(on ? Theme.onAccent : Theme.text2)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(PillShape().fill(on ? Theme.accent : Color.clear))
                .contentShape(PillShape())
        }
        .buttonStyle(.plain)
    }
}

struct CinemaResultsCard: View {
    @Environment(AppModel.self) private var app
    var state: CinemaSearchState

    var body: some View {
        let model = app.cinema
        Card(padding: 10) {
            switch state {
            case .done(let hits, _) where !hits.isEmpty:
                ScrollArea(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(hits.prefix(14)) { hit in
                            row(hit, selected: model.selected?.id == hit.id)
                        }
                    }
                }
                .frame(maxHeight: 560)
            case .done:
                note("Aucun résultat : vérifie l'orthographe ou essaie le titre original.")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.ui(12)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            case .loading:
                HStack(spacing: 8) {
                    BusyMascot(.searching, pixel: 2)
                    Text("Recherche…").font(.ui(12)).foregroundStyle(Theme.text3)
                }
            }
        }
    }

    private func row(_ hit: CinemaHit, selected: Bool) -> some View {
        Button { app.cinema.select(hit) } label: {
            HStack(spacing: 10) {
                CinemaPoster(hit: hit, width: 92, corner: 4).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(hit.line).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(selected ? Theme.accent.opacity(0.13) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.ui(12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
    }
}

struct CinemaRecentsRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.cinema
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Récemment consultés")
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.recents.prefix(8)) { hit in
                    Button { model.select(hit) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            CinemaPoster(hit: hit, width: 185, corner: 6)
                            Text(hit.title).font(.ui(11, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        }
                        .frame(width: 84)
                    }
                    .buttonStyle(.plain)
                    .help(hit.line)
                }
            }
        }
    }
}

// MARK: - The user's platforms

struct CinemaPlatformsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.cinema
        Panel(title: "Tes plateformes", subtitle: "Coche celles où tu as un abonnement : elles passent en tête de chaque fiche et ↩ les ouvre en premier.",
              symbol: "checkmark.rectangle.stack", tint: CinemaStyle.tint) {
            BorderlessMenu {
                ForEach(CinemaRegion.choices, id: \.self) { code in
                    Button(CinemaRegion.name(code) + (code == model.region ? " ✓" : "")) { model.setRegion(code) }
                }
            } label: {
                Text("Offres \(CinemaRegion.inName(model.region))").font(.ui(12, .medium)).foregroundStyle(Theme.text2)
            }
            .help("Les catalogues changent d'un pays à l'autre : choisis celui où tu regardes.")
        } content: {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(CinemaPlatform.all.filter(\.common)) { p in
                    let on = model.mine.contains(p.key)
                    Button { model.toggleMine(p.key) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.ui(11)).foregroundStyle(on ? Theme.good : Theme.text3)
                            Text(p.name).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(PillShape().fill(on ? Theme.good.opacity(0.12) : Theme.card))
                        .overlay(PillShape().strokeBorder(on ? Theme.good.opacity(0.45) : Theme.border, lineWidth: Theme.line))
                        .contentShape(PillShape())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Where the data comes from (TMDB asks for this mention), and the key.
struct CinemaCredit: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.cinema
        VStack(alignment: .leading, spacing: 6) {
            Text("Fiches, affiches et disponibilités : The Movie Database (TMDB), avec les données de JustWatch. Cette app utilise l'API de TMDB sans être approuvée ni certifiée par TMDB. Liens directs vers les plateformes : Wikidata. Seules des offres légales sont listées : rien n'est lu ni téléchargé par l'app.")
                .font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "key").font(.ui(10.5)).foregroundStyle(Theme.text3)
                Text("Clé TMDB dans le Trousseau de ton Mac").font(.ui(11)).foregroundStyle(Theme.text3)
                Button("Retirer la clé") { model.removeKey() }
                    .buttonStyle(.plain).font(.ui(11, .medium)).foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - Key

struct CinemaKeySetup: View {
    @Environment(AppModel.self) private var app
    @State private var key = ""

    var body: some View {
        let model = app.cinema
        TileRow {
            Card(padding: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Branche The Movie Database").font(.serif(22)).foregroundStyle(Theme.text)
                    Text("TMDB est la grande base ouverte des films et des séries : fiches, affiches, bandes-annonces, et pour chaque pays les plateformes qui les proposent. Sa clé est gratuite pour un usage personnel.")
                        .font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 5) {
                        step(1, "Crée un compte gratuit sur themoviedb.org.")
                        step(2, "Dans Paramètres › API, demande une clé « Developer » (usage personnel).")
                        step(3, "Copie la « Clé d'API » ou le « Jeton d'accès en lecture » et colle-le ici.")
                    }
                    Button("Ouvrir la page des clés TMDB") { Finder.open(CinemaTMDB.signupURL) }
                        .buttonStyle(.plain).font(.ui(12.5, .medium)).foregroundStyle(Theme.accent)
                    HStack(spacing: 8) {
                        if Snapshot.isActive {
                            Text("Clé d'API ou jeton").font(.mono(12.5)).foregroundStyle(Theme.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8).background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(Theme.card))
                        } else {
                            SecureField("Clé d'API ou jeton", text: $key)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { model.saveKey(key) }
                        }
                        Button(model.keyChecking ? "Vérification…" : "Enregistrer") { model.saveKey(key) }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                            .disabled(model.keyChecking)
                    }
                    if let error = model.keyError {
                        Text(error).font(.ui(11.5)).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Card(padding: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    promise("hand.raised", "Rien ne part sans toi", "Seuls les titres que tu cherches sont envoyés à TMDB, quand tu les cherches. La clé reste dans le Trousseau.")
                    promise("checkmark.seal", "Que des offres légales", "Abonnements, gratuit, location et achat, pays par pays : un clic ouvre la plateforme.")
                    promise("play.rectangle", "Bandes-annonces sans pub", "Elles s'ouvrent dans le lecteur sans pub de l'app.")
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.ui(11, .bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
            Text(text).font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func promise(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.ui(13, .medium)).foregroundStyle(Theme.good).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.ui(11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Bottom bar

struct CinemaBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.cinema
        if model.hasKey, let hit = model.selected, let t = model.title(hit) {
            ActionBar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.hit.title).font(.serif(17)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(CinemaFormat.facts(t)).font(.ui(11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer()
                if t.trailer != nil {
                    Button { model.playTrailer(t) } label: { Label("Bande-annonce", systemImage: "play.rectangle") }
                        .buttonStyle(SoftButtonStyle())
                }
                if let offer = CinemaOffers.best(t, mine: model.mine) {
                    Button { model.open(offer, in: t) } label: {
                        Label("Regarder sur \(offer.displayName)", systemImage: "play.fill")
                    }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Voir sur TMDB") { Finder.open(t.hit.tmdbURL) }.buttonStyle(SoftButtonStyle())
                }
            }
        } else {
            EmptyView()
        }
    }
}
