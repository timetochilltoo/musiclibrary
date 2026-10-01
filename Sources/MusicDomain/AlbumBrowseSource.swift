import Foundation

/// Physical volume locality is independent of snapshot publication scope.
/// Unknown includes offline, unauthorized, and unmeasured folders.
public enum StorageRootLocality: Equatable, Sendable {
    case local
    case network
    case unknown

    public init(isLocalVolume: Bool?) {
        switch isLocalVolume {
        case true: self = .local
        case false: self = .network
        case nil: self = .unknown
        }
    }
}

public enum AlbumBrowseSource: Equatable, Sendable {
    case any
    case thisMac
    case folder(StorageRootID)

    public func matches(_ summary: AlbumBrowseSummary, localRootIDs: Set<StorageRootID>) -> Bool {
        switch self {
        case .any: true
        case .thisMac: !summary.storageRootIDs.isDisjoint(with: localRootIDs)
        case .folder(let id): summary.storageRootIDs.contains(id)
        }
    }
}
