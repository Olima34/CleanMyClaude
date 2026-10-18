import SwiftUI

// Stub created by the foundation commit: the Windows module fills this folder in.

@Observable
@MainActor
final class WindowsModel: AppModule {}

struct WindowsPage: View {
    var body: some View {
        ModulePlaceholder(page: .windows,
                          subtitle: "Range tes fenêtres au clavier, comme avec Rectangle.",
                          features: [
            "Moitiés, quarts, tiers, plein écran, centrer.",
            "Envoyer une fenêtre sur l'écran suivant.",
            "Raccourcis ⌃⌥ + flèches, entièrement personnalisables.",
            "Demande l'autorisation Accessibilité de macOS."
                          ],
                          tint: Theme.palette[6])
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct WindowsBottomBar: View {
    var body: some View { EmptyView() }
}
