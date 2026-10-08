import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Playlist identity and organization")
@MainActor
struct PlaylistOrganizationTests {
    @Test("Playback starts at the selected duplicate entry after unavailable entries are skipped")
    func playbackIdentity() throws {
        let trackID = TrackID()
        let first = UUID(), second = UUID(), missing = UUID()
        let audio: PlaylistPlaybackPlan.QueueItem = (URL(fileURLWithPath: "/synthetic/no-audio.flac"), trackID, "Repeated track", 1000, 2000)
        let entries: [PlaylistPlaybackPlan.Entry] = [(first, audio), (second, audio)]
        let plan = try PlaylistPlaybackPlan(entries: entries, selectedItemID: second)
        #expect(plan.startingIndex == 1 && plan.items.count == 2)
        #expect(plan.items.map(\.trackID) == [trackID, trackID])
        #expect(plan.items[1].cueStartMilliseconds == 1000 && plan.items[1].cueEndMilliseconds == 2000)
        #expect(try PlaylistPlaybackPlan(entries: entries).startingIndex == 0)
        #expect(throws: DatabaseError.self) { try PlaylistPlaybackPlan(entries: entries, selectedItemID: missing) }
        #expect(throws: DatabaseError.self) { try PlaylistPlaybackPlan(entries: [], selectedItemID: second) }
    }

    @Test("Adjacent entry swaps normalize deletion gaps and reject stale, nonadjacent and wrong-playlist commands")
    func movement() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PlaylistOrder-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture"))
        let disc = try await database.createDisc(albumID: album.id)
        let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Repeated"))
        let removed = try await database.createTrack(discID: disc.id, draft: .init(title: "Removed fixture track"))
        let playlist = try await database.createPlaylist(name: "Listening")
        let other = try await database.createPlaylist(name: "Other")
        for id in [track.id, removed.id, track.id, track.id] { try await database.addTrack(id, to: playlist.id) }
        try await database.deleteTrack(removed.id)
        let store = LibraryStore(database: database)
        try await store.reload()
        let entries = try #require(store.playlistContents[playlist.id])
        #expect(entries.map(\.position) == [1, 3, 4])
        let ids = entries.map(\.id)
        let revision = try await database.currentRevision()
        await #expect(throws: DatabaseError.self) { try await store.movePlaylistItem(ids[2], in: playlist.id, adjacentTo: ids[0], expectedItemIDs: ids) }
        await #expect(throws: DatabaseError.self) { try await store.movePlaylistItem(ids[1], in: other.id, adjacentTo: ids[0], expectedItemIDs: ids) }
        #expect(try await database.currentRevision() == revision)
        try await store.movePlaylistItem(ids[1], in: playlist.id, adjacentTo: ids[2], expectedItemIDs: ids)
        let moved = [ids[0], ids[2], ids[1]]
        #expect(store.playlistContents[playlist.id]?.map(\.id) == moved)
        #expect(store.playlistContents[playlist.id]?.map(\.position) == [1, 2, 3])
        let movedRevision = try await database.currentRevision()
        await #expect(throws: DatabaseError.self) { try await store.movePlaylistItem(ids[1], in: playlist.id, adjacentTo: ids[2], expectedItemIDs: ids) }
        #expect(try await database.currentRevision() == movedRevision)
        try await store.movePlaylistItem(ids[1], in: playlist.id, adjacentTo: ids[2], expectedItemIDs: moved)
        #expect(store.playlistContents[playlist.id]?.map(\.id) == ids)
        try await store.deletePlaylist(playlist.id)
        let deletedRevision = try await database.currentRevision()
        await #expect(throws: DatabaseError.self) { try await store.movePlaylistItem(ids[1], in: playlist.id, adjacentTo: ids[0], expectedItemIDs: ids) }
        #expect(try await database.currentRevision() == deletedRevision)
        #expect(try await database.track(id: track.id) != nil && store.storageRoots.isEmpty)
    }
}
