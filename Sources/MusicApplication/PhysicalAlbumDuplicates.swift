import Foundation
import MusicDomain

public struct PhysicalAlbumDuplicate: Identifiable, Equatable, Sendable {
    public let album: Album
    public let reason: String
    public var id: AlbumID { album.id }
}

public enum PhysicalAlbumDuplicates {
    public static func suggestions(title: String, artist: String, barcode: String, catalogueNumber: String,
                                   releaseID: String?, albums: [Album], summaries: [AlbumID: AlbumBrowseSummary],
                                   releaseIDs: [AlbumID: String]) -> [PhysicalAlbumDuplicate] {
        func text(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func number(_ value: String) -> String { text(value).filter { $0.isLetter || $0.isNumber } }
        var results: [(Int, PhysicalAlbumDuplicate)] = []
        for album in albums {
            if let releaseID, releaseIDs[album.id]?.lowercased() == releaseID.lowercased() {
                results.append((0, .init(album: album, reason: "Same MusicBrainz release ID")))
                continue
            }
            let identityMatches = !text(title).isEmpty && !text(artist).isEmpty
                && text(album.title) == text(title) && text(summaries[album.id]?.artist ?? "") == text(artist)
            guard identityMatches else { continue }
            if !number(barcode).isEmpty, number(album.barcode ?? "") == number(barcode) {
                results.append((1, .init(album: album, reason: "Same barcode, title and artist")))
            } else if !number(catalogueNumber).isEmpty, number(album.catalogueNumber ?? "") == number(catalogueNumber) {
                results.append((2, .init(album: album, reason: "Same catalogue number, title and artist")))
            }
        }
        return results.sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            if lhs.1.album.title != rhs.1.album.title { return lhs.1.album.title < rhs.1.album.title }
            return lhs.1.id.description < rhs.1.id.description
        }.map(\.1)
    }
}
