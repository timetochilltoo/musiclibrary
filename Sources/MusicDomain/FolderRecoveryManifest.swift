import Foundation

/// Read-only evidence captured for one registered root. Contains no bookmark bytes.
public struct FolderRecoveryRootSnapshot: Equatable, Sendable {
    public let id: StorageRootID
    public let displayName: String
    public let registeredPath: String
    public let volumeIdentifier: String?
    public let scope: StorageRootScope
    public let status: StorageRootStatus
    public let bookmarkDigest: String?

    public init(id: StorageRootID, displayName: String, registeredPath: String, volumeIdentifier: String?, scope: StorageRootScope, status: StorageRootStatus, bookmarkDigest: String?) {
        self.id = id; self.displayName = displayName; self.registeredPath = registeredPath
        self.volumeIdentifier = volumeIdentifier; self.scope = scope; self.status = status; self.bookmarkDigest = bookmarkDigest
    }
}

public struct FolderRecoveryReference: Equatable, Sendable {
    public let assetID: DigitalAssetID
    public let trackID: TrackID
    public let relativePath: String
    public let expectedContentHash: String?
    public let cueStartMilliseconds: Int64?
    public let cueEndMilliseconds: Int64?

    public init(assetID: DigitalAssetID, trackID: TrackID, relativePath: String, expectedContentHash: String?, cueStartMilliseconds: Int64? = nil, cueEndMilliseconds: Int64? = nil) {
        self.assetID = assetID; self.trackID = trackID; self.relativePath = relativePath
        self.expectedContentHash = expectedContentHash
        self.cueStartMilliseconds = cueStartMilliseconds; self.cueEndMilliseconds = cueEndMilliseconds
    }
}

public struct FolderRecoveryManifest: Equatable, Sendable {
    public let root: FolderRecoveryRootSnapshot
    public let catalogueRevision: Int64
    public let references: [FolderRecoveryReference]

    public init(root: FolderRecoveryRootSnapshot, catalogueRevision: Int64, references: [FolderRecoveryReference]) {
        self.root = root; self.catalogueRevision = catalogueRevision; self.references = references
    }
}
