import Foundation
import MusicDomain
import MusicPersistence

public struct LibraryService: Sendable {
    private let albums: any AlbumRepository

    public init(albums: some AlbumRepository) {
        self.albums = albums
    }

    public func addAlbum(_ draft: NewAlbum) async throws -> Album {
        try await albums.createAlbum(draft)
    }

    public func browseAlbums(searchTerm: String? = nil) async throws -> [Album] {
        try await albums.albums(matching: searchTerm)
    }
}
