import SwiftUI

// Stub created by the foundation commit: the Network module fills this folder in.

@Observable
@MainActor
final class NetworkModel: AppModule {}

struct NetworkPage: View {
    var body: some View {
        ModulePlaceholder(page: .network,
                          subtitle: "Ta connexion à la loupe : débit, Wi-Fi, adresses et ports ouverts.",
                          features: [
            "Test de débit avec l'outil intégré à macOS.",
            "Wi-Fi : signal, bruit, canal, débit.",
            "IP locale et publique (sur demande), latence.",
            "Ports ouverts et l'app qui les écoute."
                          ],
                          tint: Theme.palette[1])
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct NetworkBottomBar: View {
    var body: some View { EmptyView() }
}
