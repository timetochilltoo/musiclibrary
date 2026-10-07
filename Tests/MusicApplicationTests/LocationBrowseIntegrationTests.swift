import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Location browse integration")
@MainActor
struct LocationBrowseIntegrationTests {
    @Test("Box contents refresh independently of search and preserve placement safeguards")
    func contents() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LocationBrowse-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let room = try await database.createLocation(.init(name: "Room"))
        let shelf = try await database.createLocation(.init(name: "Shelf", parentID: room.id))
        let box = try await database.createBoxSet(.init(title: "Box", physicalLocationID: shelf.id))
        let first = try await database.createAlbum(.init(title: "First", hasCD: true, physicalLocationID: room.id))
        let second = try await database.createAlbum(.init(title: "Second", hasCD: true, physicalLocationID: shelf.id))
        try await database.addAlbum(second.id, to: box.id, at: 1)
        try await database.addAlbum(first.id, to: box.id, at: 2)
        let revision = try await database.currentRevision()
        #expect(try await database.boxAlbumIDs()[box.id] == [second.id, first.id])
        #expect(try await database.currentRevision() == revision)
        let store = LibraryStore(database: database)
        try await store.reload()
        await store.search("First")
        #expect(store.albums.count == 1)
        #expect(store.boxAlbumIDs[box.id]?.count == 2)
        #expect(store.catalogueAlbums.allSatisfy { $0.physicalLocationID == nil })
        do { try await store.moveLocation(room.id, under: shelf.id); Issue.record("Cycle should be rejected") } catch {}
        do { try await store.deleteLocation(shelf.id); Issue.record("Occupied location should be rejected") } catch {}
        try await store.softDeleteAlbum(second.id)
        #expect(store.boxAlbumIDs[box.id] == [first.id])
        try await store.restoreAlbum(second.id)
        #expect(store.boxAlbumIDs[box.id] == [second.id, first.id])
        try await store.removeAlbum(first.id, from: box.id, assigning: room.id, locationUnknown: false)
        #expect(store.boxAlbumIDs[box.id] == [second.id])
        #expect(store.catalogueAlbums.first { $0.id == first.id }?.physicalLocationID == room.id)
        #expect(store.storageRoots.isEmpty)
    }
}
