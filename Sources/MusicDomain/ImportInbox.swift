import Foundation

public enum ImportBatchStatus: String, Codable, CaseIterable, Sendable {
    case scanning, completed, cancelled, failed
}

public enum ImportCandidateStatus: String, Codable, CaseIterable, Sendable {
    case pending, proposed, failed
}

public enum ImportProposalStatus: String, Codable, CaseIterable, Sendable {
    case proposed, approved, dismissed
}

public struct ImportBatch: Identifiable, Equatable, Sendable {
    public let id: ImportBatchID
    public let storageRootID: StorageRootID?
    public let status: ImportBatchStatus
    public let sourceDescription: String?
    public let startedAt: Date
    public let completedAt: Date?
    public let processedCount: Int
    public let candidateCount: Int
    public let errorCount: Int
    public let errorSummary: String?

    public init(id: ImportBatchID, storageRootID: StorageRootID?, status: ImportBatchStatus, sourceDescription: String?, startedAt: Date, completedAt: Date?, processedCount: Int, candidateCount: Int, errorCount: Int, errorSummary: String?) {
        self.id = id; self.storageRootID = storageRootID; self.status = status; self.sourceDescription = sourceDescription; self.startedAt = startedAt; self.completedAt = completedAt; self.processedCount = processedCount; self.candidateCount = candidateCount; self.errorCount = errorCount; self.errorSummary = errorSummary
    }
}

public struct ImportCandidatePayload: Codable, Equatable, Sendable {
    public let relativePath: String
    public let fileName: String
    public let contentTypeIdentifier: String
    public let fileSize: Int64
    public let modifiedAt: Date?

    public init(relativePath: String, fileName: String, contentTypeIdentifier: String, fileSize: Int64, modifiedAt: Date?) {
        self.relativePath = relativePath; self.fileName = fileName; self.contentTypeIdentifier = contentTypeIdentifier; self.fileSize = fileSize; self.modifiedAt = modifiedAt
    }
}

public struct ImportCandidate: Identifiable, Equatable, Sendable {
    public let id: ImportCandidateID
    public let batchID: ImportBatchID
    public let status: ImportCandidateStatus
    public let payload: ImportCandidatePayload?
    public let errorMessage: String?
    public let metadata: EmbeddedMetadataPayload?
    public let proposalID: UUID?

    public init(id: ImportCandidateID, batchID: ImportBatchID, status: ImportCandidateStatus, payload: ImportCandidatePayload?, errorMessage: String?, metadata: EmbeddedMetadataPayload? = nil, proposalID: UUID? = nil) {
        self.id = id; self.batchID = batchID; self.status = status; self.payload = payload; self.errorMessage = errorMessage; self.metadata = metadata; self.proposalID = proposalID
    }
}

public struct EmbeddedMetadataPayload: Codable, Equatable, Sendable {
    public let title: String?
    public let albumTitle: String?
    public let artist: String?
    public let albumArtist: String?
    public let discNumber: Int?
    public let trackNumber: Int?
    public let durationMilliseconds: Int?
    public let rawTags: [String: String]
    public let provenance: String

    public init(title: String?, albumTitle: String?, artist: String?, albumArtist: String?, discNumber: Int?, trackNumber: Int?, durationMilliseconds: Int?, rawTags: [String: String], provenance: String = "embedded-tags") {
        self.title = title; self.albumTitle = albumTitle; self.artist = artist; self.albumArtist = albumArtist; self.discNumber = discNumber; self.trackNumber = trackNumber; self.durationMilliseconds = durationMilliseconds; self.rawTags = rawTags; self.provenance = provenance
    }
}

public struct ImportReleaseProposal: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let batchID: ImportBatchID
    public let title: String
    public let artist: String?
    public let discCount: Int
    public let trackCount: Int
    public let confidence: Double
    public let provenance: String
    public let status: ImportProposalStatus
    public let createdAlbumID: AlbumID?

    public init(id: UUID, batchID: ImportBatchID, title: String, artist: String?, discCount: Int, trackCount: Int, confidence: Double, provenance: String, status: ImportProposalStatus, createdAlbumID: AlbumID? = nil) {
        self.id = id; self.batchID = batchID; self.title = title; self.artist = artist; self.discCount = discCount; self.trackCount = trackCount; self.confidence = confidence; self.provenance = provenance; self.status = status; self.createdAlbumID = createdAlbumID
    }
}

public struct ExternalMetadataSelection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let importProposalID: UUID
    public let provider: String
    public let externalID: String
    public let title: String
    public let artist: String?
    public let discCount: Int
    public init(id: UUID, importProposalID: UUID, provider: String, externalID: String, title: String, artist: String?, discCount: Int) { self.id = id; self.importProposalID = importProposalID; self.provider = provider; self.externalID = externalID; self.title = title; self.artist = artist; self.discCount = discCount }
}

public struct ExternalMetadataFieldSelection: Equatable, Sendable {
    public var title: Bool; public var artist: Bool; public var discCount: Bool
    public init(title: Bool, artist: Bool, discCount: Bool) { self.title = title; self.artist = artist; self.discCount = discCount }
}

public enum LibraryHealthKind: String, Codable, CaseIterable, Sendable { case missing, offline, partial, duplicate }

public struct LibraryHealthIssue: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: LibraryHealthKind
    public let albumID: AlbumID
    public let albumTitle: String
    public let detail: String
    public init(kind: LibraryHealthKind, albumID: AlbumID, albumTitle: String, detail: String) { self.id = "\(kind.rawValue)-\(albumID.description)"; self.kind = kind; self.albumID = albumID; self.albumTitle = albumTitle; self.detail = detail }
}

public struct PlaybackAssetReference: Equatable, Sendable {
    public let trackID: TrackID
    public let title: String
    public let storageRootID: StorageRootID
    public let relativePath: String
    public let availability: DigitalAssetAvailability
    public init(trackID: TrackID, title: String, storageRootID: StorageRootID, relativePath: String, availability: DigitalAssetAvailability) { self.trackID = trackID; self.title = title; self.storageRootID = storageRootID; self.relativePath = relativePath; self.availability = availability }
}

public struct AssetDuplicate: Identifiable, Equatable, Sendable { public let id: String; public let contentHash: String; public let paths: [String]; public init(contentHash: String, paths: [String]) { self.id = contentHash; self.contentHash = contentHash; self.paths = paths } }
public struct AssetRelinkProposal: Identifiable, Equatable, Sendable { public let id: UUID; public let assetID: DigitalAssetID; public let currentPath: String; public let proposedPath: String; public init(id: UUID, assetID: DigitalAssetID, currentPath: String, proposedPath: String) { self.id = id; self.assetID = assetID; self.currentPath = currentPath; self.proposedPath = proposedPath } }
public struct AssetFingerprintCandidate: Sendable { public let id: DigitalAssetID; public let rootID: StorageRootID; public let relativePath: String; public init(id: DigitalAssetID, rootID: StorageRootID, relativePath: String) { self.id = id; self.rootID = rootID; self.relativePath = relativePath } }

public struct ImportReleaseProposalDraft: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let discCount: Int
    public let confidence: Double
    public let candidateIDs: [ImportCandidateID]
    public let provenance: String

    public init(title: String, artist: String?, discCount: Int, confidence: Double, candidateIDs: [ImportCandidateID], provenance: String = "embedded-tags") {
        self.title = title; self.artist = artist; self.discCount = discCount; self.confidence = confidence; self.candidateIDs = candidateIDs; self.provenance = provenance
    }
}
