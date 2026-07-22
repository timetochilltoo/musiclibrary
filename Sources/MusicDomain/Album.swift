import Foundation

public enum DigitalAvailability: String, Codable, CaseIterable, Sendable {
    case none, complete, partial, offline, broken
}

public enum DigitalAssetAvailability: String, Codable, CaseIterable, Sendable {
    case available, rootOffline, missing, permissionRequired, invalid
}

public enum DigitalAssetOrigin: String, Codable, CaseIterable, Sendable {
    case cdRip, download, highResolution, localOther, aiGenerated
}

public enum ContributorRole: String, Codable, CaseIterable, Sendable {
    case albumArtist, performer, composer, conductor, orchestra, ensemble, soloist, featuredArtist, remixer, producer
}

public enum ValidationError: Error, Equatable, LocalizedError, Sendable {
    case requiredField(String)
    case invalidDiscCount
    case invalidReleaseYear
    case invalidRating
    case invalidLocationPlacement

    public var errorDescription: String? {
        switch self {
        case .requiredField(let name): "\(name) is required."
        case .invalidDiscCount: "Disc count must be at least one."
        case .invalidReleaseYear: "Release year must be between 1000 and 9999."
        case .invalidRating: "Rating must be between 1 and 5."
        case .invalidLocationPlacement: "A boxed album cannot also have a direct physical location."
        }
    }
}

public struct NewAlbum: Sendable, Equatable {
    public var title: String
    public var editionLabel: String?
    public var releaseYear: Int?
    public var countryCode: String?
    public var labelName: String?
    public var catalogueNumber: String?
    public var barcode: String?
    public var remasterYear: Int?
    public var mediaFormat: String?
    public var discCount: Int
    public var hasCD: Bool
    public var physicalLocationID: PhysicalLocationID?
    public var physicalNote: String?
    public var notes: String?
    public var rating: Int?
    public var isFavourite: Bool

    public init(
        title: String,
        editionLabel: String? = nil,
        releaseYear: Int? = nil,
        countryCode: String? = nil,
        labelName: String? = nil,
        catalogueNumber: String? = nil,
        barcode: String? = nil,
        remasterYear: Int? = nil,
        mediaFormat: String? = nil,
        discCount: Int = 1,
        hasCD: Bool = false,
        physicalLocationID: PhysicalLocationID? = nil,
        physicalNote: String? = nil,
        notes: String? = nil,
        rating: Int? = nil,
        isFavourite: Bool = false
    ) {
        self.title = title
        self.editionLabel = editionLabel
        self.releaseYear = releaseYear
        self.countryCode = countryCode
        self.labelName = labelName
        self.catalogueNumber = catalogueNumber
        self.barcode = barcode
        self.remasterYear = remasterYear
        self.mediaFormat = mediaFormat
        self.discCount = discCount
        self.hasCD = hasCD
        self.physicalLocationID = physicalLocationID
        self.physicalNote = physicalNote
        self.notes = notes
        self.rating = rating
        self.isFavourite = isFavourite
    }

    public func validated() throws -> NewAlbum {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Album title") }
        guard discCount >= 1 else { throw ValidationError.invalidDiscCount }
        if let releaseYear, !(1000...9999).contains(releaseYear) { throw ValidationError.invalidReleaseYear }
        if let remasterYear, !(1000...9999).contains(remasterYear) { throw ValidationError.invalidReleaseYear }
        if let rating, !(1...5).contains(rating) { throw ValidationError.invalidRating }
        if !hasCD && physicalLocationID != nil { throw ValidationError.invalidLocationPlacement }
        return self
    }
}

public struct Album: Identifiable, Equatable, Sendable {
    public let id: AlbumID
    public var title: String
    public var editionLabel: String?
    public var releaseYear: Int?
    public var countryCode: String?
    public var catalogueNumber: String?
    public var discCount: Int
    public var hasCD: Bool
    public var physicalLocationID: PhysicalLocationID?
    public var isFavourite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: AlbumID, from draft: NewAlbum, createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id
        title = draft.title
        editionLabel = draft.editionLabel
        releaseYear = draft.releaseYear
        countryCode = draft.countryCode
        catalogueNumber = draft.catalogueNumber
        discCount = draft.discCount
        hasCD = draft.hasCD
        physicalLocationID = draft.physicalLocationID
        isFavourite = draft.isFavourite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var displayTitle: String {
        guard let editionLabel, !editionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return title }
        return "\(title) — \(editionLabel)"
    }
}

public struct DigitalAvailabilitySummary: Equatable, Sendable {
    public let status: DigitalAvailability
    public let availableTrackCount: Int
    public let expectedTrackCount: Int

    public init(status: DigitalAvailability, availableTrackCount: Int, expectedTrackCount: Int) {
        self.status = status
        self.availableTrackCount = availableTrackCount
        self.expectedTrackCount = expectedTrackCount
    }

    public static func derive(expectedTrackCount: Int, assetsByTrack: [[DigitalAssetAvailability]]) -> DigitalAvailabilitySummary {
        let expected = max(0, expectedTrackCount)
        let available = assetsByTrack.filter { $0.contains(.available) }.count
        let containsBroken = assetsByTrack.joined().contains { $0 == .missing || $0 == .invalid || $0 == .permissionRequired }
        let containsOffline = assetsByTrack.joined().contains(.rootOffline)

        let status: DigitalAvailability
        if containsBroken { status = .broken }
        else if available == 0 && assetsByTrack.isEmpty { status = .none }
        else if available < expected { status = containsOffline && available == 0 ? .offline : .partial }
        else if containsOffline { status = .offline }
        else { status = .complete }

        return .init(status: status, availableTrackCount: available, expectedTrackCount: expected)
    }
}
