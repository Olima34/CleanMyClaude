import SwiftUI

// Stub created by the foundation commit: the Assistant module fills this folder in.

@Observable
@MainActor
final class AssistantModel: AppModule {}

struct AssistantPage: View {
    var body: some View {
        ModulePlaceholder(page: .assistant,
                          subtitle: "Claude t'explique ton Mac et agit pour toi, avec ton accord.",
                          features: [
            "« Explique-moi » sur un processus, un agent de démarrage, un cache ou un fichier inconnu.",
            "Dans le lanceur : « ? » suivi d'une demande en langage naturel.",
            "Chaque action est confirmée par toi ; tu vois exactement ce qui est envoyé.",
            "Ta clé API reste dans le Trousseau de macOS."
                          ],
                          tint: Theme.brand)
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct AssistantBottomBar: View {
    var body: some View { EmptyView() }
}
