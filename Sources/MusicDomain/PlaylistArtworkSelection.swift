import Foundation

/// Existing selected album fronts in playlist order; never discovers or fetches artwork.
public struct PlaylistArtworkSelection: Equatable, Sendable {
    public let paths: [String]

    public init(items: [PlaylistItem], tracks: [TrackID: TrackBrowseSummary], frontPaths: [AlbumID: String]) {
        var albums = Set<AlbumID>()
        var selected: [String] = []
        for item in items {
            guard let albumID = tracks[item.trackID]?.albumID,
                  albums.insert(albumID).inserted,
                  let path = frontPaths[albumID],
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            selected.append(path)
            if selected.count == 4 { break }
        }
        paths = selected
    }
}
