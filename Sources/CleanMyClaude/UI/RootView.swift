import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 248)
            Rectangle().fill(Theme.border).frame(width: 1)
            ZStack {
                Theme.bg
                PageContainer()
            }
        }
        .ignoresSafeArea()
        .background(Theme.bg)
        .tint(Theme.accent)
        .sheet(isPresented: $app.showOnboarding) {
            OnboardingView().environment(app)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissions()
        }
        .onAppear { AppContext.openWindow = openWindow }
    }
}

struct PageContainer: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    PageView(page: app.page)
                        .frame(maxWidth: 1180)
                        .padding(.horizontal, 32)
                        .padding(.top, 30)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.automatic)
            .onChange(of: app.page) { _, _ in proxy.scrollTo("top", anchor: .top) }
            .safeAreaInset(edge: .bottom, spacing: 0) { BottomBar() }
        }
    }
}

struct PageView: View {
    var page: Page

    var body: some View {
        switch page {
        case .dashboard: DashboardPage()
        case .cleanup: CleanupPage()
        case .protection: ProtectionPage()
        case .performance: PerformancePage()
        case .apps: AppsPage()
        case .storage: StoragePage()
        case .menubar: MenuBarPage()
        case .launcher: LauncherPage()
        case .converter: ConverterPage()
        case .toolbox: ToolboxPage()
        case .clipboard: ClipboardPage()
        case .updates: UpdatesPage()
        case .network: NetworkPage()
        case .windows: WindowsPage()
        case .automation: AutomationPage()
        case .assistant: AssistantPage()
        }
    }
}

/// The action bar of the current page, when it has something selected.
struct BottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.page {
        case .cleanup where app.cleanup.hasResults && !app.cleanup.isScanning:
            CleanupActionBar()
        case .protection where app.protection.tab == .privacy && !app.protection.traces.isEmpty:
            PrivacyActionBar()
        case .storage where (app.storage.tab == .bigFiles && !app.storage.bigSelection.isEmpty)
            || (app.storage.tab == .duplicates && !app.storage.dupSelection.isEmpty):
            StorageActionBar()
        case .launcher: LauncherBottomBar()
        case .converter: ConverterBottomBar()
        case .toolbox: ToolboxBottomBar()
        case .clipboard: ClipboardBottomBar()
        case .updates: UpdatesBottomBar()
        case .network: NetworkBottomBar()
        case .windows: WindowsBottomBar()
        case .automation: AutomationBottomBar()
        case .assistant: AssistantBottomBar()
        default:
            EmptyView()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights.
            Color.clear.frame(height: 38)

            HStack(spacing: 9) {
                ClaudeSpark(size: 20)
                Text("Clean My Claude")
                    .font(.serif(18, .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
            if DemoData.isEnabled {
                Tag(text: "Démo · données fictives", symbol: "theatermasks", tint: Theme.brand, filled: true)
                    .padding(.horizontal, 18)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Page.groups, id: \.0) { group in
                        Text(group.0)
                            .font(.ui(11.5))
                            .foregroundStyle(Theme.text3)
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(group.1) { p in
                            SidebarItem(symbol: p.symbol, title: p.title, badge: badge(for: p), selected: app.page == p) {
                                app.page = p
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            if !app.fullDiskAccess {
                Button { Finder.open(Permissions.fullDiskAccessURL) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.open").font(.ui(12)).foregroundStyle(Theme.warn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accès complet au disque").font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                            Text("Pour voir la Corbeille, Mail et les autorisations.").font(.ui(10.5)).foregroundStyle(Theme.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warn.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.warn.opacity(0.25)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .background(Theme.sidebar)
    }

    private func badge(for p: Page) -> String? {
        switch p {
        case .cleanup: return app.cleanup.hasResults && app.cleanup.recommendedSize > 0 ? Fmt.bytes(app.cleanup.recommendedSize) : nil
        case .protection: return app.protection.issues.isEmpty ? nil : "\(app.protection.issues.count)"
        case .apps: return app.apps.unused.isEmpty ? nil : "\(app.apps.unused.count)"
        default: return ModuleRegistry.module(for: p, app: app)?.sidebarBadge
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: Double(app.healthScore) / 100, tint: app.healthColor, lineWidth: 3)
                Text("\(app.healthScore)").font(.ui(10, .semibold)).foregroundStyle(Theme.text)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.healthLabel).font(.ui(12.5, .medium)).foregroundStyle(Theme.text)
                Text(app.history.totalFreed > 0 ? "\(Fmt.bytes(app.history.totalFreed)) libérés au total" : "Prêt pour un premier nettoyage")
                    .font(.ui(10.5)).foregroundStyle(Theme.text3)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape").font(.ui(13)).foregroundStyle(Theme.text2).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Réglages (⌘,)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SidebarItem: View {
    var symbol: String
    var title: String
    var badge: String? = nil
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.ui(13))
                    .foregroundStyle(selected ? Theme.text : Theme.text2)
                    .frame(width: 18)
                Text(title)
                    .font(.ui(13.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.ui(10.5, .medium))
                        .foregroundStyle(Theme.text2)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.track))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.selected : (hovering ? Theme.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                ClaudeSpark(size: 40, animate: true)
                PixelMascot(pixel: 6, broom: true)
            }
            .padding(.top, 8)
            VStack(spacing: 8) {
                Text("Bienvenue dans Clean My Claude").font(.serif(28)).foregroundStyle(Theme.text)
                Text("Tu me demandes de faire le ménage, je m'en occupe. Trois promesses avant de commencer :")
                    .font(.ui(13)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                promise("hand.raised", "Rien sans ton accord", "J'analyse en lecture seule. Je ne supprime que ce que tu coches, après confirmation.")
                promise("arrow.uturn.backward", "Le plus prudent d'abord", "Les caches se suppriment (les apps les recréent), tout le reste passe par la Corbeille. Un journal note chaque action.")
                promise("lock", "Rien ne sort sans ton clic", "Tes données restent sur ton Mac. Les rares connexions (test de débit, recherche de mises à jour, Assistant Claude) partent seulement quand tu cliques. Le code est ouvert, sur GitHub.")
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: app.fullDiskAccess ? "checkmark.circle.fill" : "externaldrive.badge.checkmark")
                        .foregroundStyle(app.fullDiskAccess ? Theme.good : Theme.accent)
                    Text(app.fullDiskAccess ? "Accès complet au disque accordé" : "Recommandé : l'accès complet au disque")
                        .font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                }
                if !app.fullDiskAccess {
                    Text("Sans lui, macOS me cache la Corbeille, les pièces jointes de Mail et la liste des autorisations. Active Clean My Claude dans Réglages › Confidentialité et sécurité › Accès complet au disque.")
                        .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir le réglage") { Finder.open(Permissions.fullDiskAccessURL) }
                        .buttonStyle(SoftButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Les autres autorisations, je ne te les demanderai qu'au moment où tu en auras besoin :")
                    .font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                later("rectangle.split.2x1", "Accessibilité", "ranger tes fenêtres au clavier et coller depuis l'historique du presse-papiers")
                later("location", "Localisation", "afficher le nom de ton réseau Wi-Fi (macOS le cache sans elle)")
                later("bell", "Notifications", "te prévenir quand la mémoire sature ou qu'une automatisation a travaillé")
                HStack(spacing: 6) {
                    Image(systemName: "command").font(.ui(11, .semibold)).foregroundStyle(Theme.brand)
                    Text("Astuce : \(app.launcher.combo?.display ?? "⌥Espace") ouvre le lanceur depuis n'importe quelle app.")
                        .font(.ui(12, .medium)).foregroundStyle(Theme.text)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                app.finishOnboarding()
            } label: {
                Text("C'est parti").frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 520)
        .background(Theme.bg)
    }

    private func later(_ symbol: String, _ title: String, _ use: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.ui(11)).foregroundStyle(Theme.text3).frame(width: 16)
            (Text(title).font(.ui(12, .semibold)).foregroundColor(Theme.text) + Text(" : pour " + use + ".").font(.ui(12)).foregroundColor(Theme.text2))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func promise(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.ui(14, .medium)).foregroundStyle(Theme.good).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
