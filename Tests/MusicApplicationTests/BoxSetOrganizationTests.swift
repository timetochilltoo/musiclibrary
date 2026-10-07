import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Box-set organization")
@MainActor
struct BoxSetOrganizationTests {
    @Test("Visible neighbor movement handles deleted-member gaps and rejects stale/nonadjacent commands atomically")
    func movement() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BoxOrder-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let location = try await database.createLocation(.init(name: "Shelf"))
        let box = try await database.createBoxSet(.init(title: "Box", physicalLocationID: location.id))
        let first = try await database.createAlbum(.init(title: "First", hasCD: true), in: box.id)
        let hidden = try await database.createAlbum(.init(title: "Deleted", hasCD: true), in: box.id)
        let second = try await database.createAlbum(.init(title: "Second", hasCD: true), in: box.id)
        let third = try await database.createAlbum(.init(title: "Third", hasCD: true), in: box.id)
        let store = LibraryStore(database: database)
        try await store.reload()
        try await store.softDeleteAlbum(hidden.id)
        let original = [first.id, second.id, third.id]
        #expect(store.boxAlbumIDs[box.id] == original)
        let revision = try await database.currentRevision()
        do {
            try await store.reorderAlbum(third.id, in: box.id, adjacentTo: first.id, expectedAlbumIDs: original)
            Issue.record("Nonadjacent command must fail")
        } catch {}
        #expect(try await database.currentRevision() == revision)
        try await store.reorderAlbum(second.id, in: box.id, adjacentTo: first.id, expectedAlbumIDs: original)
        #expect(store.boxAlbumIDs[box.id] == [second.id, first.id, third.id])
        let movedRevision = try await database.currentRevision()
        do {
            try await store.reorderAlbum(second.id, in: box.id, adjacentTo: first.id, expectedAlbumIDs: original)
            Issue.record("Stale command must fail")
        } catch {}
        #expect(try await database.currentRevision() == movedRevision)
        try await store.reorderAlbum(second.id, in: box.id, adjacentTo: first.id, expectedAlbumIDs: [second.id, first.id, third.id])
        #expect(store.boxAlbumIDs[box.id] == original)
        try await store.restoreAlbum(hidden.id)
        #expect(Set(store.boxAlbumIDs[box.id] ?? []) == [first.id, second.id, third.id, hidden.id])
        #expect(store.catalogueAlbums.allSatisfy { $0.hasCD && $0.physicalLocationID == nil })
        #expect(store.storageRoots.isEmpty)
    }
}
