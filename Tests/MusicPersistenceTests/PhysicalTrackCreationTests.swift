import Foundation
import SQLite3
import Testing
import MusicDomain
@testable import MusicPersistence

@Suite("Atomic physical track creation")
struct PhysicalTrackCreationTests {
    private let releaseID = "9383a6f5-9607-4a36-9c68-8663aad3592b"
    private var discs: [NewAlbumDisc] {
        [.init(number: 1, title: "Original", mediaFormat: "CD", tracks: [
            .init(number: 0, draft: .init(title: "Pregap", displayPosition: "00")),
            .init(number: 1, draft: .init(title: "Opening", displayPosition: "A1", durationMilliseconds: 123456))
        ]), .init(number: 2, title: "Bonus", mediaFormat: "CD", tracks: [
            .init(number: 1, draft: .init(title: "Finale", displayPosition: "B1"))
        ])]
    }

    @Test("Album, credits, artwork, identifier, discs and tracks commit once without assets")
    func creation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "physical-tracks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.sqlite")
        let database = try MusicDatabase(url: url)
        try await database.migrate()
        let album = try await database.createAlbum(.init(title: "Physical", discCount: 2, hasCD: true, isPhysicalLocationUnknown: true), in: nil, contributors: [.init(name: "Artist", role: .albumArtist)], frontArtworkPath: directory.appending(path: "cover.jpg").path, musicBrainzReleaseID: releaseID, discs: discs)
        #expect(try await database.currentRevision() == 1)
        let loaded = try await database.discs(albumID: album.id)
        #expect(loaded.map(\.number) == [1, 2])
        #expect(loaded.map(\.title) == ["Original", "Bonus"])
        let tracks = try await database.tracks(discID: loaded[0].id)
        #expect(tracks.map(\.number) == [0, 1])
        #expect(tracks.map(\.displayPosition) == ["00", "A1"])
        #expect(tracks[1].durationMilliseconds == 123456)
        #expect(try await database.digitalAssetIDs(albumID: album.id).isEmpty)
        #expect(try await database.playbackAsset(trackID: tracks[1].id) == nil)
        #expect(try await database.availableTrackIDs(albumID: album.id).isEmpty)
        #expect(try await database.albumBrowseSummaries()[album.id]?.canPlay == false)
        let reopened = try MusicDatabase(url: url)
        #expect(try await reopened.tracks(discID: loaded[0].id) == tracks)
        #expect(try await reopened.musicBrainzReleaseIDs()[album.id] == releaseID)
    }

    @Test("A late track insertion failure rolls back all rows and the revision")
    func rollback() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "physical-rollback-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.sqlite")
        let database = try MusicDatabase(url: url)
        try await database.migrate()
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let handle = try #require(connection)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "CREATE TRIGGER fail_finale BEFORE INSERT ON track WHEN NEW.title = 'Finale' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END;", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: (any Error).self) {
            try await database.createAlbum(.init(title: "Fail", discCount: 2), in: nil, contributors: [.init(name: "New Artist", role: .albumArtist)], frontArtworkPath: directory.appending(path: "cover.jpg").path, musicBrainzReleaseID: releaseID, discs: discs)
        }
        for table in ["album", "disc", "track", "contributor", "album_contributor", "artwork", "external_identifier", "digital_asset"] {
            var statement: OpaquePointer?
            #expect(sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_ROW)
            #expect(sqlite3_column_int(statement, 0) == 0)
            sqlite3_finalize(statement)
        }
        #expect(try await database.currentRevision() == 0)
    }

    @Test("Track readiness excludes physical-only, missing and offline tracks without probing files")
    func readiness() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "track-readiness-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.sqlite")
        let database = try MusicDatabase(url: url)
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Synthetic root", lastKnownPath: directory.path, bookmarkData: nil))
        let album = try await database.createAlbum(.init(title: "Mixed", discCount: 2), in: nil, discs: discs)
        let medium = try await database.discs(albumID: album.id)
        let tracks = try await database.tracks(discID: medium[0].id)
        let bonus = try await database.tracks(discID: medium[1].id)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let handle = try #require(connection)
        defer { sqlite3_close(handle) }
        for (track, availability) in [(tracks[1], "available"), (bonus[0], "missing")] {
            let sql = "INSERT INTO digital_asset (id, track_id, storage_root_id, relative_path, file_size, origin, availability) VALUES ('\(UUID())', '\(track.id)', '\(root.id)', '\(track.id).flac', 1, 'localOther', '\(availability)');"
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }
        let revision = try await database.currentRevision()
        #expect(try await database.availableTrackIDs(albumID: album.id) == [tracks[1].id])
        #expect(try await database.currentRevision() == revision)
        #expect(sqlite3_exec(handle, "UPDATE storage_root SET status = 'offline';", nil, nil, nil) == SQLITE_OK)
        #expect(try await database.availableTrackIDs(albumID: album.id).isEmpty)
        #expect(try await database.tracks(discID: medium[0].id).count == 2)
    }

    @Test("Invalid disc count and duplicate track positions fail before creation")
    func invalid() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "physical-invalid-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        await #expect(throws: (any Error).self) { try await database.createAlbum(.init(title: "Mismatch"), in: nil, discs: discs) }
        let duplicate = NewAlbumDisc(number: 1, tracks: [.init(number: 1, draft: .init(title: "One")), .init(number: 1, draft: .init(title: "Two"))])
        await #expect(throws: (any Error).self) { try await database.createAlbum(.init(title: "Duplicate"), in: nil, discs: [duplicate]) }
        #expect(try await database.currentRevision() == 0)
    }
}
