import SwiftUI

/// The market stall: a striped awning, a mirror where it tries on what the mouse hovers, and the goods with their price
/// tags in blueberries. What is bought stays for good; the things of a season come back every year.
struct RefugeStall: View {
    @Environment(AppModel.self) private var app
    /// What it tries on: an item's id, or `coat:<name>`.
    @State private var trying: String?
    @State private var buying: (id: String, title: String, price: Int)?

    var body: some View {
        let m = app.refuge
        let s = m.state
        VStack(alignment: .leading, spacing: 12) {
            RefugeSectionTitle(title: "L'étal du Refuge",
                               subtitle: "Pelages, chapeaux et objets pour sa chambre, payés avec les myrtilles du panier. Survole pour lui faire essayer.") {
                HStack(spacing: 6) {
                    RefugeBerry(size: 14)
                    Text("\(Fmt.int(s.basket)) dans le panier").font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(PillShape().fill(Theme.track))
            }
            VStack(spacing: 0) {
                RefugeAwning()
                    .frame(height: 30)
                HStack(alignment: .top, spacing: 22) {
                    mirror(m)
                        .frame(width: 190)
                    VStack(alignment: .leading, spacing: 18) {
                        shelf("Pelages") {
                            ForEach([RefugeCoat.caramel, .chocolat, .roux, .grisPerle, .neige, .nuit], id: \.rawValue) { coat in coatGood(coat, m: m) }
                        }
                        shelf("À porter") {
                            ForEach(RefugeStyle.items.filter { $0.slot != .room }) { item in good(item, m: m) }
                        }
                        shelf("Pour sa chambre") {
                            ForEach(RefugeStyle.items.filter { $0.slot == .room }) { item in good(item, m: m) }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: Theme.r(14), bottomTrailingRadius: Theme.r(14), style: .continuous).fill(Theme.card))
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: Theme.r(14), bottomTrailingRadius: Theme.r(14), style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Theme.line))
            }
        }
        .confirmAction("Acheter « \(buying?.title ?? "") » ?",
                       message: "\(Fmt.int(buying?.price ?? 0)) myrtilles du panier. Ce qui est acheté reste à lui pour toujours.",
                       button: "Acheter", isPresented: Binding(get: { buying != nil }, set: { if !$0 { buying = nil } }), destructive: false) {
            if let b = buying { m.buy(b.id, price: b.price) }
            buying = nil
        }
    }

    // MARK: The mirror

    private func mirror(_ m: RefugeModel) -> some View {
        var look = m.look()
        var caption = "Survole un article pour le lui faire essayer."
        if let trying {
            if trying.hasPrefix("coat:"), let coat = RefugeCoat(rawValue: String(trying.dropFirst(5))) {
                look.coat = coat
                caption = coat.title
            } else if let item = RefugeStyle.item(trying) {
                switch item.slot {
                case .head: look.head = item.id
                case .face: look.face = item.id
                case .room: break
                }
                caption = item.title
            }
        }
        return VStack(spacing: 10) {
            ZStack {
                Ellipse().fill(Theme.track)
                Ellipse().strokeBorder(Theme.mascot.wood, lineWidth: 6)
                if let trying, let item = RefugeStyle.item(trying), item.slot == .room {
                    RefugeItemIcon(id: item.id, pixel: 7)
                } else {
                    RefugeAvatar(look: look, pixel: 6, animated: false)
                }
            }
            .frame(width: 150, height: 170)
            Text(caption).font(.ui(11.5, trying == nil ? .regular : .semibold)).foregroundStyle(trying == nil ? Theme.text3 : Theme.text)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The goods

    private func shelf<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.ui(10, .semibold)).tracking(0.8).foregroundStyle(Theme.text3)
            FlowLayout(spacing: 12) { content() }
            Rectangle().fill(Theme.mascot.wood.opacity(0.6)).frame(height: 3)
        }
    }

    private func coatGood(_ coat: RefugeCoat, m: RefugeModel) -> some View {
        let s = m.state
        let owned = coat == .caramel || s.owned.contains(coat.shopID)
        let wearing = coat == .caramel ? s.coat == nil : s.coat == coat.rawValue
        var look = RefugeLook(stage: m.stage == .gold ? .grand : m.stage, coat: coat)
        look.scarf = nil
        return goodView(icon: AnyView(RefugeAvatar(look: look, pixel: 2.6, animated: false)), title: coat.title,
                        price: coat.price, owned: owned, active: wearing, season: nil, available: true,
                        actionTitle: wearing ? "Porté" : "Porter", basket: s.basket) {
            if owned { m.wearCoat(coat == .caramel ? nil : coat) } else if let price = coat.price { buying = (coat.shopID, coat.title, price) }
        }
        .onHover { trying = $0 ? coat.shopID : (trying == coat.shopID ? nil : trying) }
    }

    private func good(_ item: RefugeItem, m: RefugeModel) -> some View {
        let s = m.state
        let owned = s.owned.contains(item.id)
        let worn = s.worn.contains(item.id)
        let available = RefugeStyle.available(item, on: m.clock, owned: s.owned)
        let action = item.slot == .room ? (worn ? "Ranger" : "Installer") : (worn ? "Retirer" : "Porter")
        return goodView(icon: AnyView(RefugeItemIcon(id: item.id, pixel: 4)), title: item.title, price: item.price, owned: owned, active: worn,
                        season: item.season, available: available, actionTitle: action, basket: s.basket) {
            if owned { m.toggleWorn(item.id) } else { buying = (item.id, item.title, item.price) }
        }
        .help("\(item.title) : \(item.detail)")
        .onHover { trying = $0 ? item.id : (trying == item.id ? nil : trying) }
    }

    private func goodView(icon: AnyView, title: String, price: Int?, owned: Bool, active: Bool, season: RefugeSeason?, available: Bool,
                          actionTitle: String, basket: Int, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                icon.frame(width: 56, height: 52)
                if let season, !owned {
                    Text(season.title).font(.ui(8.5, .bold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(PillShape().fill(RefugePage.tint))
                        .offset(x: 10, y: -4)
                }
            }
            Text(title).font(.ui(10.5, .medium)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 84, height: 28, alignment: .top)
            if owned {
                Button(actionTitle, action: action)
                    .buttonStyle(SoftButtonStyle(prominent: !active, small: true))
                    .disabled(active && actionTitle == "Porté")
            } else if !available {
                Text("revient en \(season?.title ?? "saison")").font(.ui(10)).foregroundStyle(Theme.text3)
            } else if let price {
                Button(action: action) { RefugePriceTag(price: price) }
                    .buttonStyle(.plain)
                    .disabled(basket < price)
                    .opacity(basket < price ? 0.5 : 1)
                    .help(basket < price ? "Encore \(Fmt.int(price - basket)) myrtilles à cueillir" : "Acheter")
            }
        }
        .opacity(available || owned ? 1 : 0.55)
    }
}

/// A price tag with its hole and its string, in blueberries.
struct RefugePriceTag: View {
    var price: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle().strokeBorder(Theme.text3, lineWidth: 1).frame(width: 5, height: 5)
            RefugeBerry(size: 10)
            Text(Fmt.int(price)).font(.ui(11, .bold)).foregroundStyle(Theme.text)
        }
        .padding(.leading, 6).padding(.trailing, 9).padding(.vertical, 3)
        .background(RefugeTagShape().fill(Theme.track))
        .overlay(RefugeTagShape().stroke(Theme.borderStrong, lineWidth: max(1, Theme.line)))
    }
}

/// A tag: a box with its left end cut to a point.
struct RefugeTagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cut = min(8, rect.height / 2)
        p.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 3), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 3, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// The striped awning of the stall, scalloped at the bottom.
private struct RefugeAwning: View {
    var body: some View {
        Canvas { ctx, size in
            let stripe: CGFloat = 26
            let body = size.height - 9
            var x: CGFloat = 0
            var i = 0
            while x < size.width {
                let color = i % 2 == 0 ? Theme.mascot.prop("rose") : Theme.mascot.prop("creme")
                ctx.fill(Path(CGRect(x: x, y: 0, width: stripe, height: body)), with: .color(color))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: body - 9, width: stripe, height: 18)), with: .color(color))
                x += stripe
                i += 1
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.r(14), topTrailingRadius: Theme.r(14), style: .continuous))
    }
}

/// The things of the shop, in pixels.
struct RefugeItemIcon: View {
    var id: String
    var pixel: CGFloat = 4

    var body: some View {
        let sprite = Self.sprite(id)
        Canvas { ctx, size in
            let w = CGFloat(sprite.rows.map(\.count).max() ?? 0), h = CGFloat(sprite.rows.count)
            let ox = ((size.width - w * pixel) / 2).rounded(), oy = ((size.height - h * pixel) / 2).rounded()
            for (y, line) in sprite.rows.enumerated() {
                for (x, ch) in line.enumerated() {
                    guard let c = sprite.colors[ch] else { continue }
                    ctx.fill(Path(CGRect(x: ox + CGFloat(x) * pixel, y: oy + CGFloat(y) * pixel, width: pixel, height: pixel)), with: .color(c))
                }
            }
        }
        .frame(width: pixel * 12, height: pixel * 12)
        .accessibilityHidden(true)
    }

    static func sprite(_ id: String) -> (rows: [String], colors: [Character: Color]) {
        let c = Theme.mascot
        func p(_ name: String) -> Color { c.prop(name) }
        switch id {
        case "confiture":
            return (["..rwrwr..", "..wrwrw..", ".LLLLLLL.", ".LbbbbbL.", ".LbBbbbL.", ".LbbbbbL.", ".LbbbBbL.", ".LbbbbbL.", "..LLLLL.."],
                    ["r": p("rose"), "w": p("creme"), "L": p("verre"), "b": p("violet"), "B": p("violet-clair")])
        case "coucou":
            return (["....hh....", "...hHHh...", "..hHHHHh..", ".hhhhhhhh.", "..hwwwwh..", "..hweewh..", "..hwwewh..", "..hhhhhh..",
                     "....g.....", "....g.....", "...ggg...."],
                    ["h": c.woodShade, "H": c.wood, "w": p("creme"), "e": c.eye, "g": p("jaune")])
        case "luge":
            return ([".rrrrrrr..", ".rRRRRRr..", ".rrrrrrr..", "..h...h...", "hhhhhhhhh.", "h........."],
                    ["r": p("rose"), "R": p("rose-clair"), "h": p("monture")])
        case "bonnet":
            return (["....ww....", "...wwww...", "....ww....", "..rrrrrr..", ".rrRrrRrr.", ".rrrrrrrr.", ".wwwwwwww.", ".wWwwWwww."],
                    ["w": p("creme"), "W": p("creme-ombre"), "r": p("bleu"), "R": p("bleu-clair")])
        case "lunettes":
            return ([".eee..eee.", "ejjjeejjje", "ejjjeejjje", ".eee..eee."], ["e": p("monture"), "j": p("verre-bleu")])
        case "poele":
            return (["...kk....", "...kk....", ".kkkkkkk.", ".kyyyyyk.", ".kyoooyk.", ".koOOOok.", ".kkkkkkk.", ".k.....k."],
                    ["k": p("fonte"), "y": p("fonte-claire"), "o": p("flamme"), "O": p("jaune")])
        case "plante":
            return (["..vv.v..", ".vVvvVv.", "vvVvvvVv", ".vvVvvv.", "..vvvv..", "..tttt..", "..tttt..", "...tt..."],
                    ["v": p("vert"), "V": p("vert-fonce"), "t": p("terre")])
        case "tapis":
            return (["c.c.c.c.c.c", "rrrrrrrrrrr", "ccccccccccc", "rrrrrrrrrrr", "c.c.c.c.c.c"], ["c": p("creme"), "r": p("rose")])
        case "tableau":
            return (["fffffffff", "fssswsssf", "fsswwwssf", "fsmmmmmsf", "fmmmmmmmf", "fffffffff"],
                    ["f": p("monture"), "s": c.sky, "w": c.snow, "m": c.mountain])
        case "fleurs":
            return ([".r.j.r.", "rjrvrjr", ".v.v.v."], ["r": p("rose"), "j": p("jaune"), "v": p("vert")])
        case "paille":
            return (["...ppp...", "..ppppp..", "..rrrrr..", "PPPPPPPPP"], ["p": p("paille"), "r": p("rouge"), "P": p("paille-ombre")])
        case "citrouille":
            return (["...v...", ".oOoOo.", "oOoooOo", "oOoooOo", ".oOoOo."], ["o": p("orange"), "O": p("orange-fonce"), "v": p("vert-fonce")])
        case "guirlande":
            return (["kkkkkkkkkkk", "r..j..b..v.", "r..j..b..v."], ["k": Theme.text3, "r": p("rose"), "j": p("jaune"), "b": p("bleu"), "v": p("vert")])
        default:
            return (["?"], [:])
        }
    }
}
