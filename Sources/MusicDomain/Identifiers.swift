import Foundation

public protocol MusicIdentifier: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible where RawValue == UUID {
    init()
}

public extension MusicIdentifier {
    init() { self.init(rawValue: UUID())! }
    var description: String { rawValue.uuidString.lowercased() }
}

public struct AlbumID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct DiscID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct TrackID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct ContributorID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct PhysicalLocationID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct BoxSetID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct DigitalAssetID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct PlaylistID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct StorageRootID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct ImportBatchID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct ImportCandidateID: MusicIdentifier { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
