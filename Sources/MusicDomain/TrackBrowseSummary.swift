import Foundation

public enum TrackAudioStatus: Equatable, Sendable {
    case available, offline, permissionRequired, unavailable, noDigitalCopy, unknown

    public var label: String {
        switch self {
        case .available: "Audio available (catalogue)"
        case .offline: "Music folder offline"
        case .permissionRequired: "Folder permission required"
        case .unavailable: "Audio unavailable"
        case .noDigitalCopy: "No digital copy"
        case .unknown: "Audio status unknown"
        }
    }

    public static func derive(hasAsset: Bool, asset: DigitalAssetAvailability?, root: StorageRootStatus?) -> Self {
        guard hasAsset else { return .noDigitalCopy }
        if root == .offline { return .offline }
        if root == .permissionRequired { return .permissionRequired }
        guard root == .available, let asset else { return .unknown }
        switch asset {
        case .available: return .available
        case .rootOffline: return .offline
        case .permissionRequired: return .permissionRequired
        case .missing, .invalid: return .unavailable
        }
    }
}

/// Catalogue metadata only; does not resolve or probe audio files.
public struct TrackBrowseSummary: Identifiable, Equatable, Sendable {
    public let id: TrackID
    public let albumID: AlbumID
    public let title: String
    public let albumTitle: String
    public let discNumber: Int
    public let trackNumber: Int
    public let durationMilliseconds: Int?
    public let audioStatus: TrackAudioStatus

    public init(id: TrackID, albumID: AlbumID, title: String, albumTitle: String, discNumber: Int, trackNumber: Int, durationMilliseconds: Int?, audioStatus: TrackAudioStatus = .unknown) {
        self.id = id; self.albumID = albumID; self.title = title; self.albumTitle = albumTitle
        self.discNumber = discNumber; self.trackNumber = trackNumber; self.durationMilliseconds = durationMilliseconds
        self.audioStatus = audioStatus
    }

    public var durationLabel: String? {
        guard let durationMilliseconds, durationMilliseconds >= 0 else { return nil }
        let seconds = durationMilliseconds / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    public func matches(_ query: String, albumArtist: String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [title, albumTitle, albumArtist ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
