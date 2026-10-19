import SwiftUI
import AppKit

struct WindowsPage: View {
    @Environment(AppModel.self) private var app
    static let tint = Theme.palette[6]

    var body: some View {
        let model = app.windows
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: Page.windows.symbol, title: "Fenêtres",
                     subtitle: "Range la fenêtre au premier plan d'un raccourci : moitiés, quarts, tiers, plein écran, écran suivant. Tout se règle ici, rien d'autre à installer.",
                     tint: Self.tint, seed: 61) {
                Toggle(isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) })) {
                    Text("Raccourcis actifs").font(.ui(12.5, .medium)).foregroundStyle(Theme.text)
                }
                .switchToggles()
                .fixedSize()
            }
            PermissionCard(permission: .accessibility,
                           reason: "macOS ne laisse une app déplacer les fenêtres des autres qu'avec l'autorisation Accessibilité. Clean My Claude s'en sert seulement pour lire la position et la taille de la fenêtre au premier plan, et les changer quand tu le demandes.")
            if !model.trusted {
                Callout(symbol: "keyboard.badge.ellipsis", title: "Aucun raccourci n'est enregistré pour l'instant",
                        text: "Ils s'activent tout seuls dès que l'autorisation est accordée. Tu peux déjà les personnaliser ci-dessous.",
                        tint: Theme.warn)
            } else if !model.enabled {
                Callout(symbol: "pause.circle", title: "Raccourcis en pause",
                        text: "Ils sont libérés pour les autres apps. Les commandes « Fenêtre : … » du lanceur marchent toujours.",
                        tint: Theme.text3)
            }
            if let note = model.note {
                Callout(symbol: "arrow.triangle.swap", title: "Raccourci déplacé", text: note, tint: Self.tint)
            }
            if let refusal = model.refusal {
                Callout(symbol: "exclamationmark.triangle", title: "Raccourci déjà pris", text: refusal, tint: Theme.warn)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    WindowsGroupPanel(group: .halves)
                    WindowsGroupPanel(group: .quarters)
                    WindowsGroupPanel(group: .displays)
                }
                VStack(spacing: 14) {
                    WindowsGroupPanel(group: .thirds)
                    WindowsGroupPanel(group: .size)
                    WindowsSettingsPanel()
                }
            }
            Callout(symbol: "command", title: "Aussi depuis le lanceur",
                    text: "Tape « gauche », « plein écran » ou « écran suivant » dans le lanceur : la fenêtre que tu utilisais se range, même sans raccourci.",
                    tint: Theme.brand)
        }
        .onAppear { model.refreshTrust() }
    }
}

/// One family of actions, each with its drawing, its shortcut and a button to try it.
private struct WindowsGroupPanel: View {
    @Environment(AppModel.self) private var app
    var group: WindowsGroup

    var body: some View {
        Panel(title: group.title, subtitle: group.subtitle, symbol: group.symbol, tint: WindowsPage.tint) {
            VStack(spacing: 4) {
                ForEach(group.actions) { a in
                    WindowsActionRow(action: a)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WindowsActionRow: View {
    @Environment(AppModel.self) private var app
    var action: WindowsAction

    var body: some View {
        let model = app.windows
        HoverRow {
            HStack(spacing: 12) {
                WindowsMiniScreen(action: action)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    let cycling = action == .leftHalf || action == .rightHalf
                    if let d = cycling && !model.cycles ? nil : action.detail {
                        Text(d).font(.ui(10.5)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if model.isRefused(action) {
                    StatusBadge(status: .bad, text: "Refusé")
                        .help("macOS ou une autre app utilise déjà ce raccourci : choisis-en un autre.")
                }
                ShortcutRecorder(combo: model.combos[action]) { model.setCombo($0, for: action) }
                Button {
                    if let m = model.perform(action, pid: ProcessInfo.processInfo.processIdentifier).message {
                        HUD.show(m, symbol: "exclamationmark.triangle.fill")
                    }
                } label: {
                    Image(systemName: "play.circle").font(.ui(15)).foregroundStyle(model.trusted ? Theme.text2 : Theme.text3)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.trusted)
                .help("Essayer sur la fenêtre de Clean My Claude (« Taille précédente » la remet en place)")
            }
        }
    }
}

/// A tiny screen with the area the action fills.
struct WindowsMiniScreen: View {
    var action: WindowsAction
    var width: CGFloat = 40

    var body: some View {
        let h = width * 0.64
        Group {
            if action == .nextDisplay || action == .previousDisplay {
                displays(h)
            } else {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Theme.r(3.5)).fill(Theme.track)
                    RoundedRectangle(cornerRadius: Theme.r(3.5)).strokeBorder(Theme.borderStrong, lineWidth: Theme.line)
                    if let r = WindowsGeometry.preview(action) {
                        let inset: CGFloat = 2.5
                        let w = width - inset * 2, hh = h - inset * 2
                        RoundedRectangle(cornerRadius: Theme.r(2))
                            .fill(action == .restore ? Color.clear : WindowsPage.tint)
                            .overlay(RoundedRectangle(cornerRadius: Theme.r(2))
                                .strokeBorder(WindowsPage.tint, style: StrokeStyle(lineWidth: 1, dash: action == .restore ? [2, 1.5] : [])))
                            .frame(width: max(2, r.width * w - 1), height: max(2, r.height * hh - 1))
                            .offset(x: inset + r.minX * w + 0.5, y: inset + r.minY * hh + 0.5)
                    }
                    if action == .restore {
                        Image(systemName: "arrow.uturn.backward").font(.ui(8, .bold)).foregroundStyle(WindowsPage.tint)
                            .frame(width: width, height: h)
                    }
                }
                .frame(width: width, height: h)
            }
        }
    }

    private func displays(_ h: CGFloat) -> some View {
        let small = width * 0.42
        return HStack(spacing: 0) {
            screen(filled: action == .previousDisplay, side: small)
            Image(systemName: action == .nextDisplay ? "arrow.right" : "arrow.left")
                .font(.ui(7, .bold)).foregroundStyle(Theme.text3)
                .frame(width: width - small * 2)
            screen(filled: action == .nextDisplay, side: small)
        }
        .frame(width: width, height: h)
    }

    private func screen(filled: Bool, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.r(2.5))
            .fill(filled ? WindowsPage.tint : Theme.track)
            .overlay(RoundedRectangle(cornerRadius: Theme.r(2.5)).strokeBorder(filled ? WindowsPage.tint : Theme.borderStrong, lineWidth: 1))
            .frame(width: side, height: side * 0.7)
    }
}

private struct WindowsSettingsPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.windows
        Panel(title: "Réglages", symbol: "slider.horizontal.3", tint: WindowsPage.tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Marge entre les fenêtres").font(.ui(12.5)).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    PillPicker(options: WindowsGap.allCases,
                               selection: Binding(get: { model.gap }, set: { model.setGap($0) }),
                               label: { $0.title })
                }
                Toggle(isOn: Binding(get: { model.cycles }, set: { model.setCycles($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appuyer de nouveau fait défiler ½, ⅔ et ⅓").font(.ui(12.5)).foregroundStyle(Theme.text)
                        Text("Pour les moitiés gauche et droite").font(.ui(11)).foregroundStyle(Theme.text3)
                    }
                }
                .switchToggles()
                HStack {
                    Text("Les raccourcis demandent ⌘, ⌥ ou ⌃. Clique sur un raccourci puis tape le nouveau ; ⌫ le retire, Échap annule.")
                        .font(.ui(11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Raccourcis par défaut") { model.resetShortcuts() }
                        .buttonStyle(SoftButtonStyle(small: true))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct WindowsBottomBar: View {
    var body: some View { EmptyView() }
}
