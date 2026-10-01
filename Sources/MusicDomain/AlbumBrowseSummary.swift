import Foundation

/// Catalogue-only display information. Loading this never probes source files.
public struct AlbumBrowseSummary: Equatable, Sendable {
    public var artist: String?
    public var hasDigitalAssets: Bool
    public var availability: DigitalAvailabilitySummary
    public var storageRootIDs: Set<StorageRootID>

    public init(artist: String? = nil, hasDigitalAssets: Bool = false,
                availability: DigitalAvailabilitySummary = .init(status: .none, availableTrackCount: 0, expectedTrackCount: 0),
                storageRootIDs: Set<StorageRootID> = []) {
        self.artist = artist
        self.hasDigitalAssets = hasDigitalAssets
        self.availability = availability
        self.storageRootIDs = storageRootIDs
    }

    public var artistDisplayName: String { artist ?? "Artist not recorded" }
    public var canPlay: Bool { availability.availableTrackCount > 0 }
    public var availabilityLabel: String {
        guard hasDigitalAssets else { return "No digital copy" }
        switch availability.status {
        case .none: return "No available audio"
        case .complete: return "Available to play"
        case .partial: return "Partial · \(availability.availableTrackCount)/\(availability.expectedTrackCount) tracks"
        case .offline: return "Music folder offline"
        case .broken: return canPlay ? "Some files unavailable" : "Files unavailable"
        }
    }
}
