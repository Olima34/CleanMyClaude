import SwiftUI

// Stub created by the foundation commit: the Clipboard module fills this folder in.

@Observable
@MainActor
final class ClipboardModel: AppModule {}

struct ClipboardPage: View {
    var body: some View {
        ModulePlaceholder(page: .clipboard,
                          subtitle: "Tout ce que tu as copié, retrouvable en un instant.",
                          features: [
            "Historique du texte, des images et des fichiers copiés, avec recherche.",
            "Épingles pour garder ce qui sert souvent.",
            "Accessible depuis le lanceur.",
            "Les mots de passe des gestionnaires sont ignorés ; activé seulement avec ton accord."
                          ],
                          tint: Theme.palette[4])
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct ClipboardBottomBar: View {
    var body: some View { EmptyView() }
}
