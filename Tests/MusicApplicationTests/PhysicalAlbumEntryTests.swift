import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Physical album entry")
struct PhysicalAlbumEntryTests {
    @Test("Years are optional but nonempty invalid input is never silently discarded")
    func years() throws {
        #expect(try PhysicalAlbumEntryValidation.year("  ", field: "Release year") == nil)
        #expect(try PhysicalAlbumEntryValidation.year(" 1993 ", field: "Release year") == 1993)
        for value in ["abc", "1993x", "999", "10000", "01993", "-1993", "１９９３"] {
            #expect(throws: PhysicalAlbumEntryValidation.Failure.self) {
                try PhysicalAlbumEntryValidation.year(value, field: "Release year")
            }
        }
    }

    @Test("Untouched credit rows are ignored, named credits are normalized")
    func emptyRows() throws {
        let credits = try PhysicalAlbumEntryValidation.credits([
            .init(name: " Michael Nyman ", role: .albumArtist, creditedName: " Nyman "),
            .init(name: "  ", role: .albumArtist)
        ])
        #expect(credits == [.init(name: "Michael Nyman", role: .albumArtist, creditedName: "Nyman")])
        #expect(throws: PhysicalAlbumEntryValidation.Failure.self) {
            try PhysicalAlbumEntryValidation.credits([.init(name: "", role: .albumArtist)])
        }
    }

    @Test("An edited role or credited name requires a contributor name")
    func incompleteCredits() {
        for row in [NewAlbumContributorCredit(name: "", role: .composer),
                    .init(name: "", role: .albumArtist, creditedName: "Nyman")] {
            #expect(throws: PhysicalAlbumEntryValidation.Failure.self) {
                try PhysicalAlbumEntryValidation.credits([.init(name: "Artist", role: .albumArtist), row])
            }
        }
    }

    @Test("Saving returns the committed album for navigation without creating digital content")
    @MainActor
    func save() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "physical-entry-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let store = LibraryStore(database: database)
        let credits = try PhysicalAlbumEntryValidation.credits([
            .init(name: "Michael Nyman", role: .albumArtist), .init(name: "", role: .albumArtist)
        ])
        let album = try await store.addAlbum(.init(title: "The Piano", releaseYear: 1993, hasCD: true, isPhysicalLocationUnknown: true), contributors: credits)
        #expect(store.catalogueAlbums.map(\.id) == [album.id])
        #expect(album.title == "The Piano")
        #expect(album.hasCD)
        #expect(album.isPhysicalLocationUnknown)
        #expect(store.contributors.map(\.name) == ["Michael Nyman"])
        #expect(store.storageRoots.isEmpty)
        #expect(store.localAlbumIDs.isEmpty)
        #expect(try await database.discs(albumID: album.id).isEmpty)
    }
}
