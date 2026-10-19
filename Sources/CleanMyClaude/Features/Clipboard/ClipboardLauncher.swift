import SwiftUI
import AppKit

/// What the clipboard history gives the launcher: `clip_…` commands, and the history itself
/// ("cb" followed by words, or any search of three letters or more).
@MainActor
enum ClipboardLauncher {
    private static let tint = Theme.palette[4]

    static func commands(_ m: ClipboardModel) -> [AppCommand] {
        let words = ["presse-papiers", "historique", "clipboard", "copier", "coller", "copié"]
        return [
            AppCommand(id: "clip_search", title: "Rechercher dans le presse-papiers", subtitle: m.isActive ? "Tape « cb » puis quelques mots" : "L'historique n'est pas activé",
                       keywords: words + ["cb"], icon: .symbol("doc.on.clipboard", tint), group: .clipboard, assistantSafe: true) { ctx in
                if m.isActive { m.showInLauncher() } else { m.openPage() }
                return .done
            },
            AppCommand(id: "clip_toggle", title: m.isActive ? "Mettre en pause l'historique du presse-papiers" : "Activer l'historique du presse-papiers",
                       subtitle: m.settings.acknowledged ? nil : "Ouvre la page qui explique ce qui est enregistré",
                       keywords: words + ["pause", "activer", "désactiver"], icon: .symbol(m.isActive ? "pause.circle" : "play.circle", tint),
                       group: .clipboard, assistantSafe: true) { _ in
                if m.settings.acknowledged {
                    m.setEnabled(!m.settings.enabled)
                } else {
                    m.openPage()
                }
                return .done
            },
            AppCommand(id: "clip_plain", title: "Coller en texte brut", subtitle: "Retire polices, couleurs et liens du texte copié",
                       keywords: ["texte brut", "sans mise en forme", "plain text", "coller", "nettoyer"],
                       icon: .symbol("textformat", tint), group: .clipboard, assistantSafe: true) { _ in
                m.pastePlainText()
            },
            AppCommand(id: "clip_pin_last", title: "Épingler le dernier élément copié", keywords: words + ["épingler", "garder"],
                       icon: .symbol("pin", tint), group: .clipboard, assistantSafe: true) { _ in
                // The newest item, even when it is already pinned (an older unpinned one is not "the last copied").
                guard let first = m.items.first else { return .failed("Rien à épingler.") }
                guard !first.pinned else { return .message("Déjà épinglé : \(first.title.prefix(40))") }
                m.togglePin(first.id)
                return .message("Épinglé : \(first.title.prefix(40))")
            },
            AppCommand(id: "clip_clear", title: "Effacer l'historique du presse-papiers", subtitle: "Les éléments épinglés restent",
                       keywords: words + ["effacer", "vider", "supprimer"], icon: .symbol("trash", Theme.bad), group: .clipboard,
                       risk: .confirm("Tout l'historique du presse-papiers (sauf les épingles) sera effacé de ce Mac.")) { _ in
                m.clear()
                return .message("Historique effacé")
            }
        ]
    }

    static func results(_ raw: String, model m: ClipboardModel) -> [AppCommand] {
        let q = Fuzzy.fold(raw.trimmingCharacters(in: .whitespaces))
        let prefixed = q == "cb" || q.hasPrefix("cb ")
        if prefixed {
            guard m.isActive || !m.items.isEmpty else {
                return [AppCommand(id: "clip_r_enable", title: "Activer l'historique du presse-papiers", subtitle: "Il est désactivé : la page t'explique tout",
                                   icon: .symbol("doc.on.clipboard", tint), group: .clipboard, boost: 1900) { _ in
                    m.openPage()
                    return .done
                }]
            }
            let term = String(q.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let found = ClipboardHistory.search(m.items, query: term, keys: m.key, limit: 9, pinnedFirst: term.isEmpty)
            if found.isEmpty {
                return [AppCommand(id: "clip_r_none", title: "Rien de tel dans l'historique", subtitle: "Essaie d'autres mots",
                                   icon: .symbol("magnifyingglass", Theme.text3), group: .clipboard, boost: 1900) { _ in .done }]
            }
            return found.enumerated().map { i, item in command(item, rank: i, boost: 1900 - Double(i), m) }
        }
        guard m.isActive, q.count >= 3 else { return [] }
        return ClipboardHistory.search(m.items, query: q, keys: m.key, limit: 3)
            .enumerated().map { i, item in command(item, rank: i, boost: 120 - Double(i), m) }
    }

    private static func command(_ item: ClipboardItem, rank: Int, boost: Double, _ m: ClipboardModel) -> AppCommand {
        var details: [String] = []
        if item.pinned { details.append("Épinglé") }
        if let a = item.appName { details.append(a) }
        details.append(Fmt.relative(item.date))
        if item.kind == .text, let t = item.text {
            let lines = ClipboardText.lineCount(t)
            if lines > 1 { details.append(Fmt.plural(lines, "ligne", "lignes")) }
        }
        return AppCommand(id: "clip_r_\(rank)", title: item.title, subtitle: details.joined(separator: " · "), icon: icon(item),
                          group: .clipboard, hint: m.canPaste ? "Coller · ⌘ Copier" : "Copier", boost: boost) { ctx in
            m.recopy(item, paste: !ctx.alternate)
        }
    }

    static func icon(_ item: ClipboardItem) -> CommandIcon {
        switch item.kind {
        case .image: return .symbol("photo", tint)
        case .files: return .file(item.files?.first ?? "/")
        case .text:
            switch item.textKind {
            case .link: return .symbol("link", tint)
            case .color: return ClipboardText.color(item.text ?? "").map { .color($0) } ?? .symbol("paintpalette", tint)
            case .code: return .symbol("chevron.left.forwardslash.chevron.right", tint)
            case .plain: return .symbol("text.alignleft", tint)
            }
        }
    }
}
