import SwiftUI

/// Its birth or its mue, in the middle of the window: the window darkens, the old one trembles, and the new one appears.
/// Shown only on the dashboard or the Refuge, never in the middle of a task, never in sober mode.
struct RefugeCeremonyModal: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            // The only fixed color: a veil that darkens whatever theme is behind it.
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture {
                    // The birth waits for its name; a mue can be closed by clicking beside it.
                    if case .mue = app.refuge.ceremony { app.refuge.acknowledge() }
                }
            if let ceremony = app.refuge.ceremony {
                RefugeCeremonyPanel(ceremony: ceremony)
                    .themedShadow(color: .black.opacity(0.35), radius: 30, y: 12)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
    }
}

struct RefugeCeremonyPanel: View {
    static let width: CGFloat = 520
    var ceremony: RefugeCeremony

    var body: some View {
        RefugeCeremonyContent(ceremony: ceremony, compact: false)
            .padding(28)
            .frame(width: Self.width)
            .background(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).strokeBorder(Theme.border, lineWidth: Theme.line))
    }
}

/// What the ceremony says and shows; `compact` on the page itself (sober mode, themes without the mascot): no animation.
struct RefugeCeremonyContent: View {
    @Environment(AppModel.self) private var app
    var ceremony: RefugeCeremony
    var compact = false

    @State private var name = RefugeRules.defaultName
    /// 0: before (eyes closed, or the old stage trembling), 1: the flash, 2: after.
    @State private var phase = 2
    @State private var shake = false

    var body: some View {
        let m = app.refuge
        let content = VStack(alignment: compact ? .leading : .center, spacing: 14) {
            Text(kicker.uppercased())
                .font(.ui(10.5, .semibold)).tracking(0.8).foregroundStyle(RefugePage.tint)
            Text(title(m.name))
                .font(.serif(compact ? 22 : 26)).foregroundStyle(Theme.text)
                .multilineTextAlignment(compact ? .leading : .center)
            if !compact { figure.frame(height: 190) }
            Text(line)
                .font(.ui(13.5)).foregroundStyle(Theme.text2)
                .multilineTextAlignment(compact ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            controls(m)
        }
        Group {
            if compact {
                HStack(alignment: .center, spacing: 20) {
                    RefugeAvatar(stage: shownStage, mood: .happy, pixel: 6, animated: false)
                    content
                    Spacer(minLength: 0)
                }
            } else {
                content
            }
        }
        .onAppear { name = m.name }
        .task(id: ceremony) { await play() }
    }

    private var kicker: String {
        switch ceremony {
        case .birth: return "Il est né"
        case .mue: return "Il a mué"
        }
    }

    private func title(_ name: String) -> String {
        switch ceremony {
        case .birth: return "Un petit cabri vient de naître au Refuge"
        case .mue(let stage): return "\(name) est devenu un \(stage.title) !"
        }
    }

    private var line: String {
        switch ceremony {
        case .birth:
            let gift = app.refuge.state.total(.welcome)
            let start = gift > 0 ? "Tu prenais déjà soin de ce Mac avant mon arrivée : \(Fmt.int(gift)) myrtilles dans mon panier pour commencer. " : ""
            return "« Je suis né. Tout est nouveau ici. \(start)Comment veux-tu m'appeler ? »"
        case .mue(let stage):
            return "« \(stage.line) »"
        }
    }

    private var shownStage: RefugeStage {
        switch ceremony {
        case .birth: return .cabri
        case .mue(let stage): return stage
        }
    }

    // MARK: The animation

    @ViewBuilder
    private var figure: some View {
        let pixel: CGFloat = 10
        ZStack {
            switch ceremony {
            case .birth:
                RefugeAvatar(stage: .cabri, mood: phase < 2 ? .sleepy : .happy, pixel: pixel, animated: phase == 2)
            case .mue(let stage):
                let before = RefugeStage(rawValue: max(0, stage.rawValue - 1)) ?? .cabri
                RefugeAvatar(stage: phase == 0 ? before : stage, pixel: pixel, animated: phase == 2)
                    .offset(x: phase == 0 && shake ? 3 : 0)
                    .opacity(phase == 1 ? 0.35 : 1)
                if phase == 1 {
                    Circle().fill(Theme.mascot.star.opacity(0.55)).frame(width: 150, height: 150).blur(radius: 24)
                }
            }
        }
        .frame(width: pixel * CGFloat(RefugeFigure.cols), height: pixel * CGFloat(RefugeFigure.rows))
    }

    /// A few seconds, once: the cabri opens its eyes, or the old stage trembles, flashes and becomes the new one.
    private func play() async {
        guard !compact, !Snapshot.isActive else { phase = 2; return }
        phase = 0
        switch ceremony {
        case .birth:
            try? await Task.sleep(nanoseconds: 1_400_000_000)
        case .mue:
            for _ in 0..<12 where !Task.isCancelled {
                shake.toggle()
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            withAnimation(.easeIn(duration: 0.25)) { phase = 1 }
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        withAnimation(.easeOut(duration: 0.35)) { phase = 2 }
    }

    // MARK: The answer

    @ViewBuilder
    private func controls(_ m: RefugeModel) -> some View {
        switch ceremony {
        case .birth:
            HStack(spacing: 10) {
                if Snapshot.isActive {
                    Text(name).font(.serif(18)).foregroundStyle(Theme.text)
                        .frame(width: 220, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(Theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(9)).strokeBorder(Theme.borderStrong, lineWidth: max(1, Theme.line)))
                } else {
                    TextField("Son prénom", text: $name)
                        .textFieldStyle(.plain)
                        .font(.serif(18))
                        .foregroundStyle(Theme.text)
                        .frame(width: 220)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Theme.r(9)).fill(Theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r(9)).strokeBorder(Theme.borderStrong, lineWidth: max(1, Theme.line)))
                        .onSubmit { m.welcome(name: name) }
                }
                Button("Bienvenue, \(RefugeRules.cleanName(name)) !") { m.welcome(name: name) }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            Text("Tu pourras changer son prénom quand tu veux, dans le Refuge.")
                .font(.ui(11)).foregroundStyle(Theme.text3)
        case .mue(let stage):
            HStack(spacing: 10) {
                Button("Trop beau !") { m.acknowledge() }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                if app.page != .refuge && !compact {
                    Button("Voir le Refuge") {
                        m.acknowledge()
                        app.page = .refuge
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
            Text("Il y gagne \(stage.change).").font(.ui(11)).foregroundStyle(Theme.text3)
        }
    }
}
