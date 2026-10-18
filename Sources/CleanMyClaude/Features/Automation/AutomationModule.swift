import SwiftUI

// Stub created by the foundation commit: the Automation module fills this folder in.

@Observable
@MainActor
final class AutomationModel: AppModule {}

struct AutomationPage: View {
    var body: some View {
        ModulePlaceholder(page: .automation,
                          subtitle: "Ton Mac s'entretient tout seul, selon tes règles.",
                          features: [
            "Nettoyage planifié de ce qui est sans risque.",
            "Vidage automatique des éléments de la Corbeille trop anciens.",
            "Rangement de Téléchargements par règles, avec aperçu avant activation.",
            "Historique de santé du Mac en graphiques, notifications."
                          ],
                          tint: Theme.warn)
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct AutomationBottomBar: View {
    var body: some View { EmptyView() }
}
