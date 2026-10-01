import Foundation
import MusicDomain

enum StorageRootLocalityProbe {
    /// The caller owns the folder's security-scoped access. No audio is inspected.
    static func measure(at url: URL) -> StorageRootLocality {
        guard url.isFileURL else { return .unknown }
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        return .init(isLocalVolume: values?.volumeIsLocal)
    }

    static func retainUnchanged(_ measurements: [StorageRootID: StorageRootLocality],
                                previousRoots: [StorageRoot], currentRoots: [StorageRoot]) -> [StorageRootID: StorageRootLocality] {
        let previous = Dictionary(uniqueKeysWithValues: previousRoots.map { ($0.id, $0) })
        let unchangedIDs = Set(currentRoots.filter { root in
            guard let old = previous[root.id] else { return false }
            return root.status == .available && old.lastKnownPath == root.lastKnownPath
                && old.bookmarkData == root.bookmarkData && old.volumeIdentifier == root.volumeIdentifier
        }.map(\.id))
        return measurements.filter { unchangedIDs.contains($0.key) }
    }
}
