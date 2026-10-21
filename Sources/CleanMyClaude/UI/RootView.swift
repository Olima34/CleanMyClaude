import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            // A closed window would keep redrawing its pages and running their timers (processes, network):
            // they go away with it, so their onDisappear runs, and come back when it reopens.
            if app.mainWindowOpen {
                HStack(spacing: 0) {
                    Sidebar()
                        .frame(width: 248)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    ZStack {
                        Theme.bg
                        PageContainer()
                    }
                }
            } else {
                Color.clear
            }
        }
        // The first-launch cards, or a new version of the app: a panel in the middle, nothing behind it answers
        // until the user does. The cards come first; a new version waits for them.
        .disabled(app.showOnboarding || app.updates.selfUpdate.panelVisible || app.showProfilePanel || app.refuge.showsOverlay)
        .allowsHitTesting(!app.showOnboarding && !app.updates.selfUpdate.panelVisible && !app.showProfilePanel && !app.refuge.showsOverlay)
        .overlay {
            if app.mainWindowOpen && app.showOnboarding {
                OnboardingModal()
            } else if app.mainWindowOpen && app.updates.selfUpdate.panelVisible {
                UpdatesSelfModal()
            } else if app.mainWindowOpen && app.showProfilePanel {
                ProfileModal()
            } else if app.mainWindowOpen && app.refuge.showsOverlay {
                // Its birth or its mue, once the cards and the other panels are done.
                RefugeCeremonyModal()
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.showOnboarding)
        .animation(.easeOut(duration: 0.2), value: app.updates.selfUpdate.panelVisible)
        .animation(.easeOut(duration: 0.2), value: app.showProfilePanel)
        .animation(.easeOut(duration: 0.25), value: app.refuge.showsOverlay)
        .ignoresSafeArea()
        .background(Theme.bg)
        .tint(Theme.accent)
        .environment(\.mainWindowOnScreen, app.mainWindowOnScreen)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissions()
            app.refuge.arrived()
        }
        .onAppear { AppContext.openWindow = openWindow }
    }
}

/// True while the main window is really on screen (`AppModel.mainWindowOnScreen`): a small animation of its pages
/// (a blink, a clock ticking every second) stops while it is false. Other windows keep the default, true.
struct MainWindowOnScreenKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var mainWindowOnScreen: Bool {
        get { self[MainWindowOnScreenKey.self] }
        set { self[MainWindowOnScreenKey.self] = newValue }
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
        case .refuge: RefugePage()
        case .cleanup: CleanupPage()
        case .protection: ProtectionPage()
        case .performance: PerformancePage()
        case .battery: BatteryPage()
        case .apps: AppsPage()
        case .storage: StoragePage()
        case .phone: PhonePage()
        case .menubar: MenuBarPage()
        case .launcher: LauncherPage()
        case .wheel: WheelPage()
        case .media: MediaPage()
        case .hotkeys: HotkeysPage()
        case .toolbox: ToolboxPage()
        case .clipboard: ClipboardPage()
        case .updates: UpdatesPage()
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
        case .protection where app.protection.tab == .threats && !app.protection.selectedThreats.isEmpty:
            ThreatActionBar()
        case .storage where (app.storage.tab == .bigFiles && !app.storage.bigSelection.isEmpty)
            || (app.storage.tab == .duplicates && !app.storage.dupSelection.isEmpty):
            StorageActionBar()
        case .performance: PerformanceBottomBar()
        case .battery: BatteryBottomBar()
        case .phone where !app.phone.selection.isEmpty: PhoneBottomBar()
        case .launcher: LauncherBottomBar()
        case .wheel: WheelBottomBar()
        case .media: MediaBottomBar()
        case .hotkeys: HotkeysBottomBar()
        case .toolbox: ToolboxBottomBar()
        case .clipboard: ClipboardBottomBar()
        case .updates: UpdatesBottomBar()
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
    /// « Autres outils » unfolded.
    @AppStorage("sidebar.othersOpen") private var othersOpen = false
    /// Snapshots unfold it without touching the saved choice.
    var unfoldOthers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights.
            Color.clear.frame(height: 38)

            HStack(spacing: 9) {
                BrandMark(size: 20)
                Text("Chamois")
                    .font(.serif(18, .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
            if DemoData.isEnabled {
                Tag(text: "Démo · données fictives", symbol: "theatermasks", tint: Theme.brand, filled: true)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
            }
            SidebarProfileButton()
                .padding(.horizontal, 10)

            ScrollArea(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(app.profile.sections, id: \.0) { group in
                        header(group.0)
                        ForEach(group.1) { item($0) }
                    }
                    others
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)
            // The YouTube downloads (they have no page: pasted in the launcher), from every page: the one under way,
            // or what ended; a click shows the list.
            if !app.youtube.jobs.isEmpty {
                YouTubeActivityCard()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
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
                    .background(RoundedRectangle(cornerRadius: Theme.r(10)).fill(Theme.warn.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.r(10)).strokeBorder(Theme.warn.opacity(0.25)))
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

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.ui(11.5))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func item(_ p: Page) -> some View {
        SidebarItem(symbol: p.symbol, title: p.title, badge: badge(for: p), selected: app.page == p) {
            app.page = p
        }
        .contextMenu {
            if p != .dashboard {
                if app.profile.isFeatured(p) {
                    Button("Ranger dans Autres outils") { app.profile.setFeatured(p, false) }
                } else {
                    Button("Garder dans la barre latérale") { app.profile.setFeatured(p, true) }
                }
                Divider()
            }
            Button("Personnaliser la barre latérale…") { app.showProfilePanel = true }
        }
    }

    /// The tools outside the profile, folded at the bottom. Folded, the page open among them still shows.
    @ViewBuilder
    private var others: some View {
        let list = app.profile.others
        if !list.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { othersOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Autres outils")
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.text3)
                    Text("\(list.count)")
                        .font(.ui(10, .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(PillShape().fill(Theme.track))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.ui(9, .semibold))
                        .foregroundStyle(Theme.text3)
                        .rotationEffect(.degrees(othersOpen || unfoldOthers ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(othersOpen ? "Replier" : "Les outils hors de ton profil, toujours à un clic (et dans la barre \(app.launcher.combo?.display ?? "⌥Espace"))")
            if othersOpen || unfoldOthers {
                ForEach(list) { item($0) }
            } else if list.contains(app.page) {
                item(app.page)
            }
        }
    }

    private func badge(for p: Page) -> String? {
        switch p {
        case .cleanup: return app.cleanup.hasResults && app.cleanup.recommendedSize > 0 ? Fmt.bytes(app.cleanup.recommendedSize) : nil
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

/// The profile under the app's name: what the sidebar is tailored for, and the way to change it.
struct SidebarProfileButton: View {
    @Environment(AppModel.self) private var app
    @State private var hovering = false

    var body: some View {
        let profile = app.profile
        Button { app.showProfilePanel = true } label: {
            HStack(spacing: 8) {
                if Theme.icons != .hidden {
                    Image(systemName: profile.symbol)
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 18)
                }
                Text(profile.summary)
                    .font(.ui(12))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(profile.isChosen ? "Modifier" : "Personnaliser")
                    .font(.ui(11, .medium))
                    .foregroundStyle(hovering ? Theme.text : Theme.text3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(hovering ? Theme.hover : Theme.track.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Ton profil décide des outils mis en avant ; les autres sont rangés dans « Autres outils ».")
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
                if Theme.icons != .hidden {
                    Image(systemName: symbol)
                        .font(.ui(13))
                        .foregroundStyle(selected ? Theme.text : Theme.text2)
                        .frame(width: 18)
                }
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
                        .background(PillShape().fill(Theme.track))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.r(8)).fill(selected ? Theme.selected : (hovering ? Theme.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
