import Foundation

/// Catalogue metadata only; does not resolve or probe audio files.
public struct TrackBrowseSummary: Identifiable, Equatable, Sendable {
    public let id: TrackID
    public let albumID: AlbumID
    public let title: String
    public let albumTitle: String
    public let discNumber: Int
    public let trackNumber: Int
    public let durationMilliseconds: Int?

    public init(id: TrackID, albumID: AlbumID, title: String, albumTitle: String, discNumber: Int, trackNumber: Int, durationMilliseconds: Int?) {
        self.id = id; self.albumID = albumID; self.title = title; self.albumTitle = albumTitle
        self.discNumber = discNumber; self.trackNumber = trackNumber; self.durationMilliseconds = durationMilliseconds
    }

    public var durationLabel: String? {
        guard let durationMilliseconds, durationMilliseconds >= 0 else { return nil }
        let seconds = durationMilliseconds / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    public func matches(_ query: String, albumArtist: String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [title, albumTitle, albumArtist ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
