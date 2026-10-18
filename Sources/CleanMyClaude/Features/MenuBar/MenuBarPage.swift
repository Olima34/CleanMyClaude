import SwiftUI
import ServiceManagement

/// The sidebar page that presents the menu bar panel and its settings.
struct MenuBarPage: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.menuMetricKey) private var metric: MenuMetric = .cpuMemory
    @AppStorage(Preferences.alertsKey) private var alerts = false
    @AppStorage(Preferences.refreshKey) private var refresh: Double = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "menubar.rectangle", title: "Menu d'état en temps réel",
                     subtitle: "Ton Mac en un coup d'œil depuis la barre des menus : processeur, mémoire, disque, réseau, batterie, les apps les plus gourmandes et quatre actions express.",
                     tint: Theme.brand, seed: 81)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aperçu en direct").font(.ui(12, .semibold)).foregroundStyle(Theme.text3)
                    MenuBarPanel(embedded: true)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: Theme.line))
                        .themedShadow(color: .black.opacity(0.25), radius: 18, y: 8)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Panel(title: "Dans la barre des menus", subtitle: "Ce qui s'affiche à côté de l'étincelle", symbol: "textformat") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(MenuMetric.allCases) { mm in
                                Button { metric = mm } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: metric == mm ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(metric == mm ? Theme.accent : Theme.text3)
                                        Text(mm.title).font(.ui(12.5)).foregroundStyle(Theme.text)
                                        Spacer()
                                        MenuBarLabelPreview(metric: mm)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Panel(title: "Réglages", symbol: "slider.horizontal.3") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("M'alerter si le disque est presque plein ou si la mémoire sature", isOn: $alerts)
                                .onChange(of: alerts) { _, on in if on { Alerts.requestPermission() } }
                                .disabled(!Alerts.available)
                            if !Alerts.available {
                                Text("Les alertes demandent l'app assemblée (scripts/build_app.sh).").font(.ui(11)).foregroundStyle(Theme.text3)
                            }
                            HStack {
                                Text("Rafraîchissement")
                                Spacer()
                                if Snapshot.isActive {
                                    refreshSegments.frame(width: 160)
                                } else {
                                    Picker("", selection: $refresh) {
                                        Text("1 s").tag(1.0)
                                        Text("2 s").tag(2.0)
                                        Text("5 s").tag(5.0)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 160)
                                    .onChange(of: refresh) { _, _ in app.monitor.start() }
                                }
                            }
                            LaunchAtLoginToggle()
                        }
                        .font(.ui(12.5))
                        .switchToggles()
                        .controlSize(.small)
                    }
                    Callout(symbol: "leaf", title: "Léger par conception",
                            text: "Les mesures viennent directement du noyau (quelques appels système toutes les \(Int(refresh)) s). La liste des processus n'est lue que lorsque le panneau est ouvert.",
                            tint: Theme.good)
                }
            }
        }
    }

    /// The refresh picker drawn by hand, for snapshots.
    private var refreshSegments: some View {
        HStack(spacing: 2) {
            ForEach([1.0, 2.0, 5.0], id: \.self) { v in
                Text("\(Int(v)) s")
                    .font(.ui(11.5, refresh == v ? .semibold : .regular))
                    .foregroundStyle(refresh == v ? Theme.text : Theme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: Theme.r(5)).fill(refresh == v ? Theme.selected : .clear))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Theme.r(7)).fill(Theme.track))
    }
}

struct MenuBarLabelPreview: View {
    var metric: MenuMetric
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.monitor
        HStack(spacing: 4) {
            ClaudeSpark(size: 12, color: Theme.text)
            switch metric {
            case .icon: EmptyView()
            case .cpu: Text("\(Int((m.cpu * 100).rounded())) %")
            case .memory: Text("\(Int((m.memFraction * 100).rounded())) %")
            case .cpuMemory: Text("\(Int((m.cpu * 100).rounded()))% · \(Int((m.memFraction * 100).rounded()))%")
            case .network: Text("↓\(Fmt.speed(m.netIn)) ↑\(Fmt.speed(m.netOut))")
            case .disk: Text(Fmt.bytes(m.diskFree))
            }
        }
        .font(.ui(11.5, .medium))
        .monospacedDigit()
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: Theme.r(5)).fill(Theme.track))
    }
}

struct LaunchAtLoginToggle: View {
    @State private var on = LoginItem.isEnabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Ouvrir à l'ouverture de session", isOn: Binding(get: { on }, set: { v in
                error = LoginItem.set(v)
                if error == nil { on = v }
            }))
            if let error { Text(error).font(.ui(11)).foregroundStyle(Theme.warn) }
        }
    }
}
