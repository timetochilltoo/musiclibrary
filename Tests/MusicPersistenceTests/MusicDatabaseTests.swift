import Foundation
import Testing
@testable import MusicDomain
@testable import MusicPersistence

@Suite("Music database")
struct MusicDatabaseTests {
    @Test("Migration creates schema version one")
    func migrationCreatesSchema() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        #expect(try await database.schemaVersion() == 1)
        #expect(try await database.currentRevision() == 0)
    }

    @Test("Creating an album persists it and increments the revision")
    func albumCreation() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Kind of Blue", editionLabel: "Japan version", releaseYear: 1980, hasCD: true))
        let loaded = try await database.album(id: album.id)
        #expect(loaded?.displayTitle == "Kind of Blue — Japan version")
        #expect(loaded?.hasCD == true)
        #expect(try await database.currentRevision() == 1)
    }

    @Test("Adding an album to a box clears its direct location")
    func boxMembershipInheritsLocation() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let location = try await database.createLocation(.init(name: "Shelf 2"))
        let album = try await database.createAlbum(.init(title: "Album", hasCD: true, physicalLocationID: location.id))
        let box = try await database.createBoxSet(.init(title: "Collection", physicalLocationID: location.id))
        try await database.addAlbum(album.id, to: box.id, at: 1)
        let updated = try await database.album(id: album.id)
        #expect(updated?.hasCD == true)
        #expect(updated?.physicalLocationID == nil)
        #expect(try await database.currentRevision() == 4)
    }

    @Test("Locations can be listed and renamed")
    func locationManagement() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let location = try await database.createLocation(.init(name: "Shelf 2"))
        try await database.renameLocation(location.id, to: "Shelf 3")
        let locations = try await database.locations()
        #expect(locations.map(\.name) == ["Shelf 3"])
        #expect(try await database.currentRevision() == 2)
    }

    @Test("An invalid box set leaves album creation atomic")
    func invalidBoxSetRollsBackAlbum() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        await #expect(throws: DatabaseError.notFound("Box set")) {
            _ = try await database.createAlbum(.init(title: "Album", hasCD: true), in: BoxSetID())
        }
        #expect(try await database.albums().isEmpty)
        #expect(try await database.currentRevision() == 0)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "MusicDatabaseTests-\(UUID().uuidString).sqlite")
    }
}
