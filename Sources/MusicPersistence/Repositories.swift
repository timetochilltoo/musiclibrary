import Foundation
import MusicDomain

public protocol AlbumRepository: Sendable {
    func createAlbum(_ draft: NewAlbum) async throws -> Album
    func album(id: AlbumID) async throws -> Album?
    func albums(matching term: String?) async throws -> [Album]
}

extension MusicDatabase: AlbumRepository {}
