#if DEBUG
import Foundation
import MusicDomain
import MusicPersistence

extension LibraryStore {
    /// Real services over disposable synthetic data; never calls live startup.
    /// The caller may remove the returned temporary directory after closing the fixture.
    public static func makeNavigationFixture() async throws -> (store: LibraryStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MusicLibrary-Navigation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let location = try await database.createLocation(.init(name: "Fixture shelf"))
        let box = try await database.createBoxSet(.init(title: "Fixture collected editions", physicalLocationID: location.id))
        let contributor = try await database.createContributor(.init(name: "Fixture Orchestra"))
        for index in 1...240 {
            let album = try await database.createAlbum(.init(
                title: String(format: "Fixture Album %03d", index) + (index.isMultiple(of: 20) ? " — A long classical title with several movements" : ""),
                releaseYear: 1970 + index % 50,
                catalogueNumber: index == 1 ? "FIXTURE-001" : nil,
                barcode: index == 1 ? "0077" : nil, mediaFormat: "CD", hasCD: true,
                physicalLocationID: location.id
            ))
            try await database.addAlbumContributor(contributor.id, to: album.id, role: .albumArtist)
            if index <= 12 { try await database.addAlbum(album.id, to: box.id, at: index) }
        }
        let store = LibraryStore(database: database)
        try await store.reload()
        return (store, directory)
    }
}
#endif
