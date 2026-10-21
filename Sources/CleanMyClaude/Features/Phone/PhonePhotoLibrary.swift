import Foundation
import Photos

/// iCloud Photos is on: the iPhone refuses deletions through the cable. The Photos library of this Mac, when it is the
/// same iCloud library, deletes for every device instead, and keeps each photo 30 days in « Supprimés récemment ».
/// macOS asks for the Photos permission on the first use, and confirms every deletion itself.
enum PhonePhotoLibrary {
    static var access: PermissionState {
        guard !DemoData.isEnabled else { return .granted }
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return .granted
        case .denied, .restricted: return .denied
        default: return .notAsked
        }
    }

    /// Only from a click (the Info.plist of the assembled app explains it; `swift build` has none and would be stopped).
    @MainActor
    static func requestAccess() async -> PermissionState {
        guard Notifier.available else { return access }
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return access
    }

    /// The assets of this Mac's library that are these iPhone items (item id → asset id). Missing ones are not in it:
    /// another Apple Account, iCloud Photos off on the Mac, or not synced yet.
    static func find(_ items: [PhoneItem]) async -> [String: String] {
        guard access == .granted else { return [:] }
        return await Task.detached(priority: .userInitiated) {
            var out: [String: String] = [:]
            for item in items {
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                                item.date.addingTimeInterval(-2) as NSDate, item.date.addingTimeInterval(2) as NSDate)
                options.includeHiddenAssets = true
                let found = PHAsset.fetchAssets(with: options)
                var candidates: [(id: String, filename: String, date: Date)] = []
                found.enumerateObjects { asset, _, _ in
                    let name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
                    candidates.append((asset.localIdentifier, name, asset.creationDate ?? .distantPast))
                }
                if let id = PhoneRules.match(name: item.name, taken: item.date, in: candidates) { out[item.id] = id }
            }
            return out
        }.value
    }

    /// Moves the assets to « Supprimés récemment » (macOS shows its own confirmation). Returns how many went.
    static func delete(_ assetIDs: [String]) async throws -> Int {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        guard assets.count > 0 else { return 0 }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        ActionLog.write("PHOTOS iCLOUD SUPPRIMÉES \(assets.count) (Supprimés récemment, 30 jours)")
        return assets.count
    }
}
