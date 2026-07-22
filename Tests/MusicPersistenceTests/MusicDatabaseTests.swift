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
        #expect(try await database.schemaVersion() == 2)
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

    @Test("Editing an album preserves identity and increments revision once")
    func albumEditing() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Original", editionLabel: "1980 pressing"))
        var draft = album.draft
        draft.title = "Corrected"
        draft.editionLabel = "Japan version"
        let updated = try await database.updateAlbum(album.id, with: draft)
        #expect(updated.id == album.id)
        #expect(updated.displayTitle == "Corrected — Japan version")
        #expect(try await database.currentRevision() == 2)
    }

    @Test("Moving, reordering, and removing box members preserves placement rules")
    func boxMembershipManagement() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let shelf = try await database.createLocation(.init(name: "Shelf"))
        let box = try await database.createBoxSet(.init(title: "Collection", physicalLocationID: shelf.id))
        let first = try await database.createAlbum(.init(title: "First", hasCD: true), in: box.id)
        let second = try await database.createAlbum(.init(title: "Second", hasCD: true))
        try await database.moveAlbum(second.id, to: box.id)
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [first.id, second.id])
        try await database.reorderAlbum(second.id, in: box.id, to: 1)
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [second.id, first.id])
        try await database.removeAlbum(second.id, from: box.id, assigning: nil, locationUnknown: true)
        let removed = try #require(await database.album(id: second.id))
        #expect(removed.hasCD)
        #expect(removed.physicalLocationID == nil)
        #expect(removed.isPhysicalLocationUnknown)
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [first.id])
    }

    @Test("Removing a box member without a location rolls back")
    func invalidBoxRemovalRollsBack() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let shelf = try await database.createLocation(.init(name: "Shelf"))
        let box = try await database.createBoxSet(.init(title: "Collection", physicalLocationID: shelf.id))
        let album = try await database.createAlbum(.init(title: "Album", hasCD: true), in: box.id)
        await #expect(throws: DatabaseError.invalidOperation("Choose a physical location or explicitly mark the location unknown before removing an album from its box.")) {
            try await database.removeAlbum(album.id, from: box.id, assigning: nil, locationUnknown: false)
        }
        #expect(try await database.boxMembers(of: box.id).map(\.album.id) == [album.id])
    }

    @Test("Discs, tracks, aliases, and contributor roles preserve catalogue order")
    func catalogueContent() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Album"))
        let firstDisc = try await database.createDisc(albumID: album.id, title: "Disc One")
        let secondDisc = try await database.createDisc(albumID: album.id, title: "Disc Two")
        #expect(try await database.discs(albumID: album.id).map(\.id) == [firstDisc.id, secondDisc.id])
        let firstTrack = try await database.createTrack(discID: firstDisc.id, draft: .init(title: "First"))
        let secondTrack = try await database.createTrack(discID: firstDisc.id, draft: .init(title: "Second", durationMilliseconds: 210_000))
        #expect(try await database.tracks(discID: firstDisc.id).map(\.id) == [firstTrack.id, secondTrack.id])
        let alias = try await database.addAlbumAlias(albumID: album.id, name: "別名", kind: .original, locale: "ja")
        #expect(alias.name == "別名")
        let contributor = try await database.createContributor(.init(name: "Miles Davis"))
        try await database.addAlbumContributor(contributor.id, to: album.id, role: .albumArtist)
        #expect(try await database.albumContributors(albumID: album.id).first?.contributor.name == "Miles Davis")
    }

    @Test("Track credits, artwork selection, and content removal are persisted safely")
    func detailedCatalogueContent() async throws {
        let database = try MusicDatabase(url: temporaryDatabaseURL())
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Album"))
        let disc = try await database.createDisc(albumID: album.id, title: nil)
        let first = try await database.createTrack(discID: disc.id, draft: .init(title: "First"))
        let second = try await database.createTrack(discID: disc.id, draft: .init(title: "Second"))
        let contributor = try await database.createContributor(.init(name: "Guest"))
        try await database.addTrackContributor(contributor.id, to: first.id, role: .performer, creditedName: "G. Artist")
        #expect(try await database.trackContributors(trackID: first.id).first?.creditedName == "G. Artist")
        _ = try await database.addAlbumArtwork(albumID: album.id, localPath: "/art/first.jpg")
        let selected = try await database.addAlbumArtwork(albumID: album.id, localPath: "/art/second.jpg")
        #expect(try await database.albumArtwork(albumID: album.id).filter(\.isSelected).map(\.id) == [selected.id])
        try await database.deleteTrack(first.id)
        #expect(try await database.tracks(discID: disc.id).map(\.number) == [1])
        #expect(try await database.tracks(discID: disc.id).first?.id == second.id)
        let alias = try await database.addAlbumAlias(albumID: album.id, name: "Alternate", kind: .alternate)
        try await database.deleteAlbumAlias(alias.id)
        #expect(try await database.albumAliases(albumID: album.id).isEmpty)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "MusicDatabaseTests-\(UUID().uuidString).sqlite")
    }
}
