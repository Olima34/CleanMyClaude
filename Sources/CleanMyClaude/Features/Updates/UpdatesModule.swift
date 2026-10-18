import SwiftUI

// Stub created by the foundation commit: the Updates module fills this folder in.

@Observable
@MainActor
final class UpdatesModel: AppModule {}

struct UpdatesPage: View {
    var body: some View {
        ModulePlaceholder(page: .updates,
                          subtitle: "Garde tes apps à jour, sans passer par chacune.",
                          features: [
            "Homebrew : formules et casks en retard, mise à jour en un clic.",
            "Apps Sparkle : lecture de leur flux de mises à jour.",
            "App Store : versions disponibles, ouverture de la bonne page.",
            "macOS : mises à jour système en attente."
                          ],
                          tint: Theme.good)
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct UpdatesBottomBar: View {
    var body: some View { EmptyView() }
}
