import Foundation
import SQLite3
import Testing
import MusicDomain
@testable import MusicPersistence

@Suite("External identifier migration")
struct ExternalIdentifierMigrationTests {
    @Test("Version 16 identifiers survive migration and can be shared by separate albums")
    func migration() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "identifier-migration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.sqlite")
        let database = try MusicDatabase(url: url)
        try await database.migrate()
        let release = "9383a6f5-9607-4a36-9c68-8663aad3592b"
        let first = try await database.createAlbum(.init(title: "Existing"), in: nil, musicBrainzReleaseID: release)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let handle = try #require(connection)
        defer { sqlite3_close(handle) }
        let sql = """
        BEGIN IMMEDIATE;
        CREATE TABLE external_identifier_old (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, provider TEXT NOT NULL, kind TEXT NOT NULL, value TEXT NOT NULL, UNIQUE(provider, kind, value));
        INSERT INTO external_identifier_old SELECT * FROM external_identifier;
        DROP TABLE external_identifier;
        ALTER TABLE external_identifier_old RENAME TO external_identifier;
        PRAGMA user_version = 16;
        UPDATE catalogue_state SET schema_version = 16 WHERE singleton_id = 1;
        COMMIT;
        """
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        let revision = try await database.currentRevision()
        try await database.migrate()
        try await database.migrate()
        #expect(try await database.schemaVersion() == 17)
        #expect(try await database.currentRevision() == revision)
        #expect(try await database.musicBrainzReleaseIDs() == [first.id: release])
        let second = try await database.createAlbum(.init(title: "Separate copy"), in: nil, musicBrainzReleaseID: release)
        #expect(try await database.musicBrainzReleaseIDs() == [first.id: release, second.id: release])
        try await database.softDeleteAlbum(first.id)
        #expect(try await database.musicBrainzReleaseIDs() == [second.id: release])
        try await database.restoreAlbum(first.id)
        #expect(try await database.musicBrainzReleaseIDs().count == 2)
    }
}
