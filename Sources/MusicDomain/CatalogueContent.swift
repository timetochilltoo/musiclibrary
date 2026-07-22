import Foundation

public enum AlbumAliasKind: String, Codable, CaseIterable, Sendable {
    case original, translated, romanized, alternate
}

public enum ArtworkRole: String, Codable, CaseIterable, Sendable {
    case front, back, booklet, tray, disc, other
}

public struct Disc: Identifiable, Equatable, Sendable {
    public let id: DiscID
    public let albumID: AlbumID
    public let number: Int
    public let title: String?
    public let mediaFormat: String?

    public init(id: DiscID, albumID: AlbumID, number: Int, title: String?, mediaFormat: String?) { self.id = id; self.albumID = albumID; self.number = number; self.title = title; self.mediaFormat = mediaFormat }
}

public struct NewTrack: Equatable, Sendable {
    public var title: String
    public var displayPosition: String?
    public var durationMilliseconds: Int?
    public var workName: String?
    public var movementNumber: Int?
    public var movementName: String?
    public var isInstrumental: Bool?

    public init(title: String, displayPosition: String? = nil, durationMilliseconds: Int? = nil, workName: String? = nil, movementNumber: Int? = nil, movementName: String? = nil, isInstrumental: Bool? = nil) {
        self.title = title
        self.displayPosition = displayPosition
        self.durationMilliseconds = durationMilliseconds
        self.workName = workName
        self.movementNumber = movementNumber
        self.movementName = movementName
        self.isInstrumental = isInstrumental
    }

    public func validated() throws -> NewTrack {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Track title") }
        if let durationMilliseconds, durationMilliseconds < 0 { throw ValidationError.invalidDuration }
        return self
    }
}

public struct Track: Identifiable, Equatable, Sendable {
    public let id: TrackID
    public let discID: DiscID
    public let number: Int
    public let title: String
    public let displayPosition: String?
    public let durationMilliseconds: Int?
    public let workName: String?
    public let movementNumber: Int?
    public let movementName: String?
    public let isInstrumental: Bool?

    public init(id: TrackID, discID: DiscID, number: Int, title: String, displayPosition: String?, durationMilliseconds: Int?, workName: String?, movementNumber: Int?, movementName: String?, isInstrumental: Bool?) { self.id = id; self.discID = discID; self.number = number; self.title = title; self.displayPosition = displayPosition; self.durationMilliseconds = durationMilliseconds; self.workName = workName; self.movementNumber = movementNumber; self.movementName = movementName; self.isInstrumental = isInstrumental }
}

public struct NewContributor: Equatable, Sendable {
    public var name: String
    public var sortName: String?

    public init(name: String, sortName: String? = nil) {
        self.name = name
        self.sortName = sortName
    }

    public func validated() throws -> NewContributor {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Contributor name") }
        return self
    }
}

public struct Contributor: Identifiable, Equatable, Sendable {
    public let id: ContributorID
    public let name: String
    public let sortName: String?

    public init(id: ContributorID, name: String, sortName: String?) { self.id = id; self.name = name; self.sortName = sortName }
}

public struct ContributorCredit: Identifiable, Equatable, Sendable {
    public let contributor: Contributor
    public let role: ContributorRole
    public let creditedName: String?
    public let position: Int

    public var id: String { "\(contributor.id.description)-\(role.rawValue)-\(position)" }

    public init(contributor: Contributor, role: ContributorRole, creditedName: String?, position: Int) { self.contributor = contributor; self.role = role; self.creditedName = creditedName; self.position = position }
}

public struct AlbumAlias: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let albumID: AlbumID
    public let name: String
    public let locale: String?
    public let kind: AlbumAliasKind

    public init(id: UUID, albumID: AlbumID, name: String, locale: String?, kind: AlbumAliasKind) { self.id = id; self.albumID = albumID; self.name = name; self.locale = locale; self.kind = kind }
}

public struct Artwork: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let ownerType: String
    public let ownerID: String
    public let role: ArtworkRole
    public let localPath: String?
    public let source: String
    public let isSelected: Bool
}
