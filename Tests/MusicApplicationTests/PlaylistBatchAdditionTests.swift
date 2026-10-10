import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Atomic playlist additions")
@MainActor
struct PlaylistBatchAdditionTests {
    @Test("A batch preserves order and duplicate tracks, refreshes once and retries without another revision")
    func orderedRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PlaylistBatch-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture"))
        let disc = try await database.createDisc(albumID: album.id)
        let first = try await database.createTrack(discID: disc.id, draft: .init(title: "First"))
        let second = try await database.createTrack(discID: disc.id, draft: .init(title: "Second"))
        let playlist = try await database.createPlaylist(name: "Listening")
        try await database.addTrack(first.id, to: playlist.id)
        let additions = [second.id, first.id, second.id].map { PlaylistTrackAddition(trackID: $0) }
        let store = LibraryStore(database: database)
        let before = try await database.currentRevision()
        try await store.addTracks(additions, toPlaylist: playlist.id)
        #expect(try await database.currentRevision() == before + 1)
        let entries = try #require(store.playlistContents[playlist.id])
        #expect(entries.map(\.trackID) == [first.id, second.id, first.id, second.id])
        #expect(entries.map(\.position) == [1, 2, 3, 4])
        #expect(Array(entries.dropFirst()).map(\.id) == additions.map(\.id))
        // Simulates a successful commit followed by a failed UI refresh: retry the captured request.
        try await store.addTracks(additions, toPlaylist: playlist.id)
        #expect(try await database.currentRevision() == before + 1)
        #expect(store.playlistContents[playlist.id] == entries)
        try await store.addTracks([PlaylistTrackAddition(trackID: second.id)], toPlaylist: playlist.id)
        #expect(store.playlistContents[playlist.id]?.count == 5)
        #expect(store.storageRoots.isEmpty)
    }

    @Test("Invalid targets, late invalid tracks, collisions and partial retries leave no batch writes")
    func rollback() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PlaylistBatchRollback-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture"))
        let disc = try await database.createDisc(albumID: album.id)
        let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Track"))
        let playlist = try await database.createPlaylist(name: "Listening")
        let other = try await database.createPlaylist(name: "Other")
        let saved = PlaylistTrackAddition(trackID: track.id)
        try await database.addTracks([saved], to: other.id)
        let before = try await database.currentRevision()
        let new = PlaylistTrackAddition(trackID: track.id)
        for additions in [[], [new, new], [new, PlaylistTrackAddition(trackID: TrackID())], [new, saved]] {
            await #expect(throws: DatabaseError.self) { try await database.addTracks(additions, to: playlist.id) }
            #expect(try await database.currentRevision() == before)
            #expect(try await database.playlistItems(playlistID: playlist.id).isEmpty)
        }
        await #expect(throws: DatabaseError.self) { try await database.addTracks([new, saved], to: other.id) }
        #expect(try await database.currentRevision() == before)
        #expect(try await database.playlistItems(playlistID: other.id).map(\.id) == [saved.id])
        try await database.softDeleteAlbum(album.id)
        let deletedAlbumRevision = try await database.currentRevision()
        await #expect(throws: DatabaseError.self) { try await database.addTracks([new], to: playlist.id) }
        #expect(try await database.currentRevision() == deletedAlbumRevision)
        try await database.restoreAlbum(album.id)
        try await database.deletePlaylist(playlist.id)
        let deletedPlaylistRevision = try await database.currentRevision()
        await #expect(throws: DatabaseError.self) { try await database.addTracks([new], to: playlist.id) }
        #expect(try await database.currentRevision() == deletedPlaylistRevision)
        #expect(try await database.track(id: track.id) != nil)
    }
}
