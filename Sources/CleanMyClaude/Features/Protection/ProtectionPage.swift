import SwiftUI

struct ProtectionPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.protection
        VStack(alignment: .leading, spacing: 18) {
            PageHero(symbol: "lock.shield", title: "Protection et confidentialité",
                     subtitle: "Les défenses de macOS, ce qui se lance tout seul, qui a accès à quoi, et les traces que tu laisses derrière toi.",
                     tint: Theme.good, seed: 33) {
                HStack(spacing: 16) {
                    if model.hasAudit {
                        Gauge(value: model.securityRatio, text: "\(model.passedCount)/\(model.scoredCount)", caption: "protections",
                              tint: model.securityRatio >= 0.85 ? Theme.good : (model.securityRatio >= 0.6 ? Theme.warn : Theme.bad),
                              size: 74, lineWidth: 6)
                    }
                    ScanButton(title: model.hasAudit ? "Refaire le bilan" : "Lancer le bilan", symbol: "checkmark.shield",
                               running: model.isAuditing || app.startup.isScanning) {
                        let protection = app.protection, startup = app.startup
                        Task {
                            async let a: Void = protection.audit()
                            async let b: Void = startup.scan()
                            _ = await (a, b)
                        }
                    }
                }
            }

            PillPicker(options: ProtectionTab.allCases, selection: $model.tab, label: { $0.title }, badge: { tab in
                switch tab {
                case .security: return model.issues.isEmpty ? nil : "\(model.issues.count)"
                case .persistence: return app.startup.flagged.isEmpty ? nil : "\(app.startup.flagged.count)"
                case .permissions: return model.grants.map { "\($0.count)" }
                case .privacy: return model.traces.isEmpty ? nil : "\(model.traces.count)"
                }
            })

            if model.isAuditing && !model.hasAudit {
                ScanProgressCard(title: "J'inspecte les défenses de ton Mac…", label: "FileVault, coupe-feu, Gatekeeper, signatures…", progress: nil)
            } else if !model.hasAudit && model.tab != .persistence {
                ProtectionIntro()
            } else {
                switch model.tab {
                case .security: SecurityTab()
                case .persistence: PersistenceTab()
                case .permissions: PermissionsTab()
                case .privacy: PrivacyTab()
                }
            }
        }
    }
}

struct ProtectionIntro: View {
    var body: some View {
        Card(padding: 24) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Un bilan en dix secondes").font(.serif(24)).foregroundStyle(Theme.text)
                    Text("Je lis l'état des protections de macOS, je vérifie la signature de tout ce qui démarre seul, je liste les apps qui ont accès à ta caméra, ton micro ou ton écran, et je repère les traces de ton activité.")
                        .font(.ui(13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    Text("Tout se passe en lecture seule : rien n'est modifié sans ton accord.")
                        .font(.ui(12)).foregroundStyle(Theme.text3)
                }
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.good.opacity(0.85))
                    .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Security

struct SecurityTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        VStack(alignment: .leading, spacing: 14) {
            if !model.issues.isEmpty {
                Callout(symbol: "exclamationmark.shield", title: "\(Fmt.plural(model.issues.count, "point mérite", "points méritent")) ton attention",
                        text: "Chaque carte explique le risque et ouvre le bon réglage. Les corrections se font dans Réglages Système : macOS garde la main sur sa sécurité.",
                        tint: Theme.warn)
            } else if model.hasAudit {
                Callout(symbol: "checkmark.shield", title: "Toutes les protections essentielles sont actives",
                        text: "Ton Mac applique les bonnes pratiques de sécurité d'Apple. Bravo.", tint: Theme.good)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(model.allChecks) { c in
                    SecurityCheckCard(check: c)
                }
                if model.isCheckingUpdates {
                    Card {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Mises à jour en attente").font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                                Text("Je demande aux serveurs d'Apple…").font(.ui(11.5)).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SecurityCheckCard: View {
    var check: SecurityCheck

    var body: some View {
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: check.symbol, tint: check.status.color, size: 32)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(check.title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                        Spacer(minLength: 6)
                        StatusBadge(status: check.status, text: check.status == .ok ? "Actif" : nil)
                    }
                    Text(check.detail).font(.ui(12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    if let advice = check.advice {
                        Text(advice).font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = check.settingsURL, check.status == .warn || check.status == .bad {
                        Button("Ouvrir le réglage") { Finder.open(url) }
                            .buttonStyle(SoftButtonStyle(small: true))
                            .padding(.top, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Persistence

struct PersistenceTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let startup = app.startup
        VStack(alignment: .leading, spacing: 14) {
            Callout(symbol: "eye.trianglebadge.exclamationmark", title: "Là où se cachent les indésirables",
                    text: "Presque tous les logiciels malveillants sur Mac s'installent comme « agent » ou « service » pour redémarrer avec le Mac. Je vérifie qui a signé chaque programme et je signale ce qui est inhabituel : non signé, introuvable, script, emplacement suspect.",
                    tint: Theme.accent)
            if startup.isScanning && startup.items.isEmpty {
                ScanProgressCard(title: "Je vérifie les signatures…", label: "LaunchAgents et LaunchDaemons", progress: nil)
            } else if startup.items.isEmpty {
                Card {
                    EmptyHint(text: startup.lastScan == nil ? "Lance le bilan pour lister les éléments persistants." : "Aucun agent ni service tiers. Rien ne se lance en douce.",
                              symbol: "checkmark.seal")
                }
            } else {
                TileRow {
                    StatTile(symbol: "list.bullet", value: "\(startup.items.count)", label: "Éléments", detail: "Agents et services installés")
                    StatTile(symbol: "checkmark.seal", value: "\(startup.items.filter { $0.signature.isTrusted }.count)", label: "Signés et vérifiés",
                             detail: "Apple, App Store ou développeur identifié", tint: Theme.good)
                    StatTile(symbol: "exclamationmark.triangle", value: "\(startup.flagged.count)", label: "À examiner",
                             detail: "Non signés, orphelins ou scripts", tint: startup.flagged.isEmpty ? Theme.good : Theme.warn)
                }
                if let msg = startup.message {
                    Callout(symbol: "info.circle", title: "Fait", text: msg)
                }
                if !startup.flagged.isEmpty {
                    Panel(title: "Points d'attention", subtitle: "Pas forcément dangereux : souvent un reste d'app désinstallée ou un petit outil maison. Mais à regarder de près.",
                          symbol: "exclamationmark.triangle", tint: Theme.warn) {
                        LaunchItemList(items: startup.flagged)
                    }
                }
                ForEach(LaunchDomain.allCases, id: \.self) { d in
                    let items = startup.items.filter { $0.domain == d && $0.flags.isEmpty }
                    if !items.isEmpty {
                        Panel(title: d.title, subtitle: d.folder.replacingOccurrences(of: FS.home, with: "~"), symbol: "folder") {
                            LaunchItemList(items: items)
                        }
                    }
                }
            }
        }
    }
}

struct LaunchItemList: View {
    var items: [LaunchItem]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                LaunchItemRow(item: item)
            }
        }
    }
}

struct LaunchItemRow: View {
    @Environment(AppModel.self) private var app
    var item: LaunchItem
    @State private var confirmRemove = false

    var body: some View {
        let startup = app.startup
        HoverRow {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let a = item.appPath {
                        FileIcon(path: a, size: 28)
                    } else {
                        Image(systemName: item.domain == .globalDaemon ? "gearshape.2" : "person.crop.circle.badge.clock")
                            .font(.ui(15)).foregroundStyle(Theme.text2).frame(width: 28, height: 28)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.label).font(.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                        if item.running { Tag(text: "En cours", symbol: "circle.fill", tint: Theme.good, filled: true) }
                        if item.disabled { Tag(text: "Désactivé", tint: Theme.text3) }
                    }
                    HStack(spacing: 6) {
                        Tag(text: item.signature.label, symbol: item.signature.isTrusted ? "checkmark.seal" : "seal",
                            tint: item.signature.isTrusted ? Theme.good : Theme.warn, filled: true)
                        ForEach(item.flags, id: \.self) { f in
                            Tag(text: f.rawValue, symbol: f.severity.symbol, tint: f.severity.color, filled: true)
                        }
                        if item.keepAlive { Tag(text: "Relancé s'il s'arrête", tint: Theme.text3) }
                    }
                    Text(item.commandLine).font(.mono(10.5)).foregroundStyle(Theme.text3).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if startup.busy.contains(item.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Menu {
                        Button(item.disabled ? "Réactiver" : "Désactiver") {
                            Task { await startup.setDisabled(item, !item.disabled) }
                        }
                        Button("Afficher dans le Finder") { Finder.reveal(item.plistPath) }
                        if let p = item.program, FS.exists(p) {
                            Button("Afficher le programme") { Finder.reveal(p) }
                        }
                        if item.domain == .userAgent {
                            Divider()
                            Button("Supprimer…", role: .destructive) { confirmRemove = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.ui(14)).foregroundStyle(Theme.text2)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(item.domain.needsAdmin ? "Modifier un service système demande ton mot de passe" : "Actions")
                }
            }
        }
        .help(item.plistPath)
        .confirmAction("Supprimer « \(item.label) » ?",
                       message: "L'agent est arrêté et son fichier va dans la Corbeille. Si l'app qui l'a installé est encore là, elle risque de le recréer : désinstalle-la plutôt depuis Applications.",
                       button: "Supprimer", isPresented: $confirmRemove) {
            Task { await startup.remove(item) }
        }
    }
}

// MARK: - Permissions

struct PermissionsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        VStack(alignment: .leading, spacing: 14) {
            if let grants = model.grants {
                Callout(symbol: "hand.raised", title: "Qui a accès à quoi",
                        text: "La liste des autorisations que tu as accordées. Je ne peux pas les retirer moi-même (macOS l'interdit, et c'est tant mieux) : chaque bloc ouvre le bon panneau des Réglages.")
                let services = TCCService.all.filter { s in grants.contains { $0.service == s } }
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
                                        if let p = g.path { FileIcon(path: p, size: 20) } else {
                                            Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundStyle(Theme.text3)
                                        }
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
            } else {
                FullDiskAccessCard(reason: "macOS cache la liste des autorisations aux apps qui n'ont pas l'accès complet au disque.")
            }
        }
    }
}

struct FullDiskAccessCard: View {
    @Environment(AppModel.self) private var app
    var reason: String

    var body: some View {
        Card(padding: 22) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 34)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accès complet au disque requis").font(.serif(20)).foregroundStyle(Theme.text)
                    Text(reason + " Ouvre Réglages › Confidentialité et sécurité › Accès complet au disque, active Clean My Claude, puis relance l'analyse.")
                        .font(.ui(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Ouvrir le réglage") { Finder.open(Permissions.fullDiskAccessURL) }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                        Button("J'ai donné l'accès") { app.refreshPermissions() }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Privacy

struct PrivacyTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.protection
        let groups = model.traces.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
        VStack(alignment: .leading, spacing: 14) {
            if let r = model.traceReport {
                Callout(symbol: "checkmark.seal", title: "Traces effacées", text: r.summary, tint: r.failures.isEmpty ? Theme.good : Theme.warn)
            }
            ForEach(groups, id: \.self) { g in
                Panel(title: g, symbol: g == "Système" ? "macbook" : "globe") {
                    VStack(spacing: 2) {
                        ForEach(model.traces.filter { $0.group == g }) { t in
                            TraceRow(trace: t)
                        }
                    }
                }
            }
            Callout(symbol: "safari", title: "Et Safari ?",
                    text: "Son historique est synchronisé avec iCloud sur tous tes appareils : efface-le depuis Safari › Historique › Effacer l'historique… pour que la suppression se propage partout.")
        }
    }
}

struct TraceRow: View {
    @Environment(AppModel.self) private var app
    var trace: PrivacyTrace

    var body: some View {
        let model = app.protection
        let blocked = trace.blockedReason != nil || trace.needsFullDiskAccess
        HoverRow {
            HStack(spacing: 12) {
                CheckBox(state: model.traceSelection.contains(trace.id) ? .on : .off, disabled: blocked) { model.toggle(trace) }
                Image(systemName: trace.symbol).font(.ui(13)).foregroundStyle(Theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trace.title).font(.ui(12.5, .medium)).foregroundStyle(Theme.text)
                    if let reason = trace.blockedReason {
                        Label(reason, systemImage: "lock").font(.ui(11)).foregroundStyle(Theme.warn)
                    } else if trace.needsFullDiskAccess {
                        Label("Accès complet au disque requis", systemImage: "lock").font(.ui(11)).foregroundStyle(Theme.warn)
                    } else {
                        Text(trace.detail).font(.ui(11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    if let n = trace.count {
                        Text(Fmt.plural(n, "entrée", "entrées")).font(.ui(11.5, .medium)).foregroundStyle(Theme.text2)
                    }
                    if trace.size > 0 {
                        Text(Fmt.bytes(trace.size)).font(.ui(10.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
    }
}

struct PrivacyActionBar: View {
    @Environment(AppModel.self) private var app
    @State private var confirm = false

    var body: some View {
        let model = app.protection
        ActionBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.plural(model.selectedTraces.count, "trace sélectionnée", "traces sélectionnées"))
                    .font(.serif(18)).foregroundStyle(Theme.text)
                Text("L'effacement est définitif.").font(.ui(11)).foregroundStyle(Theme.text3)
            }
            Spacer()
            Button {
                confirm = true
            } label: {
                HStack(spacing: 6) {
                    if model.isCleaningTraces { ProgressView().controlSize(.small).scaleEffect(0.7).tint(.white) }
                    Text("Effacer les traces")
                }
            }
            .buttonStyle(SoftButtonStyle(prominent: true))
            .disabled(model.selectedTraces.isEmpty || model.isCleaningTraces)
        }
        .confirmAction("Effacer ces traces ?",
                       message: model.selectedTraces.map { "• \($0.group) : \($0.title)" }.joined(separator: "\n"),
                       button: "Effacer", isPresented: $confirm) {
            Task { await model.cleanTraces() }
        }
    }
}
