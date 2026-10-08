import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Playlist browse contents")
@MainActor
struct PlaylistBrowseIntegrationTests {
    @Test("Batched contents preserve duplicate entries and refresh independently of album search")
    func contents() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PlaylistBrowse-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Fixture"))
        let disc = try await database.createDisc(albumID: album.id)
        let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Track"))
        let playlist = try await database.createPlaylist(name: "Listening")
        let empty = try await database.createPlaylist(name: "Empty")
        try await database.addTrack(track.id, to: playlist.id)
        try await database.addTrack(track.id, to: playlist.id)
        let revision = try await database.currentRevision()
        let entries = try #require(try await database.playlistContents()[playlist.id])
        #expect(entries.count == 2 && entries[0].id != entries[1].id)
        #expect(entries.map(\.trackID) == [track.id, track.id])
        #expect(try await database.currentRevision() == revision)
        let store = LibraryStore(database: database)
        try await store.reload()
        await store.search("No matching albums")
        #expect(store.albums.isEmpty)
        #expect(store.playlistContents[playlist.id] == entries)
        #expect((store.playlistContents[empty.id] ?? []).isEmpty)
        try await store.movePlaylistItem(entries[1].id, to: 1)
        #expect(store.playlistContents[playlist.id]?.map(\.id) == [entries[1].id, entries[0].id])
        try await store.removePlaylistItem(entries[0].id)
        #expect(store.playlistContents[playlist.id]?.map(\.id) == [entries[1].id])
        #expect(try await database.track(id: track.id) != nil)
        try await store.deletePlaylist(playlist.id)
        #expect(store.playlistContents[playlist.id] == nil)
        try await store.restorePlaylist(playlist.id)
        #expect(store.playlistContents[playlist.id]?.count == 1)
        #expect(store.storageRoots.isEmpty)
    }
}
