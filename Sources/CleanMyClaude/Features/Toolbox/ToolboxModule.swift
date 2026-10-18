import SwiftUI

// Stub created by the foundation commit: the Toolbox module fills this folder in.

@Observable
@MainActor
final class ToolboxModel: AppModule {}

struct ToolboxPage: View {
    var body: some View {
        ModulePlaceholder(page: .toolbox,
                          subtitle: "Les petits outils du quotidien, à portée de clic ou de lanceur.",
                          features: [
            "Sélecteur de couleur à l'écran, conversions HEX, RGB, HSL.",
            "Générateur de mots de passe et de phrases de passe.",
            "Empreintes de fichiers (SHA-256, SHA-1, MD5), Base64, encodage d'URL, JSON, UUID.",
            "Horodatages, Lorem ipsum, compteur de mots, changement de casse.",
            "Caféine : empêcher la veille pendant X minutes, aussi depuis la barre des menus."
                          ],
                          tint: Theme.palette[7])
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct ToolboxBottomBar: View {
    var body: some View { EmptyView() }
}
