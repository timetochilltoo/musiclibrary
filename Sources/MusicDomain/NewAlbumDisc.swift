import Foundation

/// Catalogue-only content created atomically with an album. Numeric order is
/// separate from the printed position (for example A1, B1, or 01).
public struct NewAlbumDisc: Equatable, Sendable {
    public let number: Int
    public let title: String?
    public let mediaFormat: String?
    public let tracks: [NewAlbumTrack]

    public init(number: Int, title: String? = nil, mediaFormat: String? = nil, tracks: [NewAlbumTrack]) {
        self.number = number; self.title = title; self.mediaFormat = mediaFormat; self.tracks = tracks
    }
}

public struct NewAlbumTrack: Equatable, Sendable {
    public let number: Int
    public let draft: NewTrack

    public init(number: Int, draft: NewTrack) { self.number = number; self.draft = draft }
}
