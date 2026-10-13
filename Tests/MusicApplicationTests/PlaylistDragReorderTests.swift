import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Guarded playlist drag reorder")
@MainActor
struct PlaylistDragReorderTests {
    @Test("Move before or to end preserves duplicate identities, normalizes gaps and treats unchanged drops as no-ops")
    func reorder() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PlaylistDrag-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture"))
        let disc = try await database.createDisc(albumID: album.id)
        let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Repeated"))
        let removed = try await database.createTrack(discID: disc.id, draft: .init(title: "Removed"))
        let playlist = try await database.createPlaylist(name: "Order")
        for id in [track.id, removed.id, track.id, track.id] { try await database.addTrack(id, to: playlist.id) }
        try await database.deleteTrack(removed.id)
        let store = LibraryStore(database: database)
        try await store.reload()
        let original = try #require(store.playlistContents[playlist.id])
        #expect(original.map(\.position) == [1, 3, 4])
        let ids = original.map(\.id)
        let before = try await database.currentRevision()
        try await store.movePlaylistItem(ids[2], in: playlist.id, before: ids[0], expectedItemIDs: ids)
        let moved = [ids[2], ids[0], ids[1]]
        #expect(store.playlistContents[playlist.id]?.map(\.id) == moved)
        #expect(store.playlistContents[playlist.id]?.map(\.position) == [1, 2, 3])
        #expect(store.playlistContents[playlist.id]?.map(\.trackID) == [track.id, track.id, track.id])
        #expect(try await database.currentRevision() == before + 1)
        for target in [Optional(ids[2]), Optional(ids[0])] {
            try await store.movePlaylistItem(ids[2], in: playlist.id, before: target, expectedItemIDs: moved)
            #expect(try await database.currentRevision() == before + 1)
        }
        try await store.movePlaylistItem(ids[2], in: playlist.id, before: nil, expectedItemIDs: moved)
        #expect(store.playlistContents[playlist.id]?.map(\.id) == ids)
        let endRevision = try await database.currentRevision()
        try await store.movePlaylistItem(ids[2], in: playlist.id, before: nil, expectedItemIDs: ids)
        #expect(try await database.currentRevision() == endRevision)
        #expect(try await database.track(id: track.id) != nil && store.storageRoots.isEmpty)
    }

    @Test("Stale order, invalid source/target and inactive playlist reject without writes")
    func refusals() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PlaylistDragRefusal-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture"))
        let disc = try await database.createDisc(albumID: album.id)
        let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Track"))
        let playlist = try await database.createPlaylist(name: "Order")
        let other = try await database.createPlaylist(name: "Other")
        for _ in 0..<3 { try await database.addTrack(track.id, to: playlist.id) }
        try await database.addTrack(track.id, to: other.id)
        let entries = try await database.playlistItems(playlistID: playlist.id)
        let ids = entries.map(\.id)
        let foreign = try #require(await database.playlistItems(playlistID: other.id).first?.id)
        let before = try await database.currentRevision()
        for (source, target, expected) in [
            (ids[0], Optional(ids[2]), Array(ids.reversed())),
            (ids[0], Optional(ids[2]), Array(ids.dropLast())),
            (ids[0], Optional(foreign), ids),
            (foreign, Optional(ids[0]), ids),
            (ids[0], Optional(UUID()), ids)
        ] {
            await #expect(throws: DatabaseError.self) { try await database.movePlaylistItem(source, in: playlist.id, before: target, expectedItemIDs: expected) }
            #expect(try await database.currentRevision() == before)
            #expect(try await database.playlistItems(playlistID: playlist.id) == entries)
        }
        try await database.deletePlaylist(playlist.id)
        let deletedRevision = try await database.currentRevision()
        await #expect(throws: DatabaseError.self) { try await database.movePlaylistItem(ids[0], in: playlist.id, before: nil, expectedItemIDs: ids) }
        #expect(try await database.currentRevision() == deletedRevision)
        #expect(try await database.playlistItems(playlistID: playlist.id) == entries)
    }
}
