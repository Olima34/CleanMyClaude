import SwiftUI

// Stub created by the foundation commit: the Converter module fills this folder in.

@Observable
@MainActor
final class ConverterModel: AppModule {
    /// Files handed over by the Finder service ("Convertir avec Clean My Claude"), a Dock drop or the launcher.
    var pendingFiles: [URL] = []

    func receive(_ urls: [URL]) {
        pendingFiles = urls
    }
}

struct ConverterPage: View {
    var body: some View {
        ModulePlaceholder(page: .converter,
                          subtitle: "Convertis, compresse et transforme tes fichiers : images, vidéos, audio, PDF, documents, archives.",
                          features: [
            "Images : HEIC, JPEG, PNG, TIFF, GIF, BMP, PDF ; redimensionner, compresser, retirer GPS et métadonnées.",
            "Vidéos : MOV ↔ MP4, H.264 ou HEVC, compression, extraction de l'audio, vidéo → GIF animé.",
            "Audio : M4A/AAC, WAV, AIFF.",
            "PDF : fusionner, découper, pivoter, compresser ; images ↔ PDF.",
            "Documents : DOCX, RTF, HTML, TXT, ODT, Markdown → HTML ou PDF.",
            "ZIP, renommage par lot, OCR (texte d'une image), QR codes.",
            "Depuis le Finder : clic droit › Services › Convertir avec Clean My Claude."
                          ],
                          tint: Theme.palette[1])
    }
}

/// The action bar pinned at the bottom of the page (EmptyView when there is nothing to act on).
struct ConverterBottomBar: View {
    var body: some View { EmptyView() }
}
