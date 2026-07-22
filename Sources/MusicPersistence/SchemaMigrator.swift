import Foundation
import SQLite3

enum SchemaMigrator {
    static let currentVersion = 2

    static func migrate(_ connection: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DatabaseError.sqlite(message: "Unable to read schema version.") }
        var version = Int(sqlite3_column_int64(statement, 0))
        guard version <= currentVersion else { throw DatabaseError.sqlite(message: "Database schema \(version) is newer than this app supports.") }
        if version == 0 {
            try migrateToVersion1(connection)
            version = 1
        }
        if version == 1 { try migrateToVersion2(connection) }
    }

    private static func migrateToVersion1(_ connection: OpaquePointer) throws {
        let sql = """
        BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS catalogue_state (
            singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
            schema_version INTEGER NOT NULL,
            catalogue_revision INTEGER NOT NULL DEFAULT 0,
            last_published_revision INTEGER NOT NULL DEFAULT 0,
            last_published_at INTEGER
        );
        INSERT OR IGNORE INTO catalogue_state (singleton_id, schema_version) VALUES (1, 1);

        CREATE TABLE IF NOT EXISTS physical_location (
            id TEXT PRIMARY KEY,
            parent_id TEXT REFERENCES physical_location(id) ON DELETE RESTRICT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            notes TEXT
        );
        CREATE INDEX IF NOT EXISTS physical_location_parent_index ON physical_location(parent_id, sort_order, name);

        CREATE TABLE IF NOT EXISTS album (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            sort_title TEXT,
            edition_label TEXT,
            release_date TEXT,
            release_year INTEGER,
            country_code TEXT,
            label_name TEXT,
            catalogue_number TEXT,
            barcode TEXT,
            remaster_year INTEGER,
            media_format TEXT,
            disc_count INTEGER NOT NULL CHECK (disc_count >= 1),
            has_cd INTEGER NOT NULL DEFAULT 0 CHECK (has_cd IN (0, 1)),
            physical_location_id TEXT REFERENCES physical_location(id) ON DELETE RESTRICT,
            physical_note TEXT,
            notes TEXT,
            rating INTEGER CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
            is_favourite INTEGER NOT NULL DEFAULT 0 CHECK (is_favourite IN (0, 1)),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER
        );
        CREATE INDEX IF NOT EXISTS album_title_index ON album(title, edition_label);
        CREATE INDEX IF NOT EXISTS album_barcode_index ON album(barcode);
        CREATE INDEX IF NOT EXISTS album_catalogue_number_index ON album(catalogue_number);

        CREATE TABLE IF NOT EXISTS album_alias (
            id TEXT PRIMARY KEY,
            album_id TEXT NOT NULL REFERENCES album(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            locale TEXT,
            kind TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS box_set (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            edition_label TEXT,
            physical_location_id TEXT NOT NULL REFERENCES physical_location(id) ON DELETE RESTRICT,
            notes TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS box_set_album (
            box_set_id TEXT NOT NULL REFERENCES box_set(id) ON DELETE CASCADE,
            album_id TEXT NOT NULL UNIQUE REFERENCES album(id) ON DELETE RESTRICT,
            position INTEGER NOT NULL,
            PRIMARY KEY (box_set_id, album_id),
            UNIQUE (box_set_id, position)
        );

        CREATE TABLE IF NOT EXISTS disc (
            id TEXT PRIMARY KEY,
            album_id TEXT NOT NULL REFERENCES album(id) ON DELETE CASCADE,
            number INTEGER NOT NULL,
            title TEXT,
            media_format TEXT,
            UNIQUE (album_id, number)
        );
        CREATE TABLE IF NOT EXISTS track (
            id TEXT PRIMARY KEY,
            disc_id TEXT NOT NULL REFERENCES disc(id) ON DELETE CASCADE,
            number INTEGER NOT NULL,
            display_position TEXT,
            title TEXT NOT NULL,
            sort_title TEXT,
            duration_ms INTEGER,
            work_name TEXT,
            movement_number INTEGER,
            movement_name TEXT,
            is_instrumental INTEGER,
            notes TEXT,
            UNIQUE (disc_id, number)
        );
        CREATE TABLE IF NOT EXISTS contributor (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            sort_name TEXT,
            locale TEXT,
            notes TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS album_contributor (
            album_id TEXT NOT NULL REFERENCES album(id) ON DELETE CASCADE,
            contributor_id TEXT NOT NULL REFERENCES contributor(id) ON DELETE RESTRICT,
            role TEXT NOT NULL,
            credited_name TEXT,
            position INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (album_id, contributor_id, role, position)
        );
        CREATE TABLE IF NOT EXISTS track_contributor (
            track_id TEXT NOT NULL REFERENCES track(id) ON DELETE CASCADE,
            contributor_id TEXT NOT NULL REFERENCES contributor(id) ON DELETE RESTRICT,
            role TEXT NOT NULL,
            credited_name TEXT,
            position INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (track_id, contributor_id, role, position)
        );

        CREATE TABLE IF NOT EXISTS storage_root (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            last_known_path TEXT NOT NULL,
            bookmark_data BLOB,
            volume_identifier TEXT,
            status TEXT NOT NULL,
            last_seen_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS digital_asset (
            id TEXT PRIMARY KEY,
            track_id TEXT NOT NULL REFERENCES track(id) ON DELETE RESTRICT,
            storage_root_id TEXT NOT NULL REFERENCES storage_root(id) ON DELETE RESTRICT,
            relative_path TEXT NOT NULL,
            file_resource_id TEXT,
            file_size INTEGER NOT NULL,
            modified_at INTEGER,
            duration_ms INTEGER,
            codec TEXT,
            container TEXT,
            sample_rate_hz INTEGER,
            bit_depth INTEGER,
            channel_count INTEGER,
            bit_rate INTEGER,
            origin TEXT NOT NULL,
            content_hash TEXT,
            quick_signature TEXT,
            acoustid TEXT,
            availability TEXT NOT NULL,
            last_verified_at INTEGER
        );
        CREATE UNIQUE INDEX IF NOT EXISTS digital_asset_path_index ON digital_asset(storage_root_id, relative_path);
        CREATE INDEX IF NOT EXISTS digital_asset_hash_index ON digital_asset(content_hash);

        CREATE TABLE IF NOT EXISTS external_identifier (
            id TEXT PRIMARY KEY,
            owner_type TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            kind TEXT NOT NULL,
            value TEXT NOT NULL,
            UNIQUE (provider, kind, value)
        );
        CREATE TABLE IF NOT EXISTS artwork (
            id TEXT PRIMARY KEY,
            owner_type TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            role TEXT NOT NULL,
            local_path TEXT,
            remote_url TEXT,
            mime_type TEXT,
            width INTEGER,
            height INTEGER,
            source TEXT NOT NULL,
            is_selected INTEGER NOT NULL DEFAULT 0,
            checksum TEXT
        );
        CREATE TABLE IF NOT EXISTS lyrics (
            id TEXT PRIMARY KEY,
            track_id TEXT NOT NULL REFERENCES track(id) ON DELETE CASCADE,
            language TEXT,
            kind TEXT NOT NULL,
            text TEXT NOT NULL,
            source TEXT NOT NULL,
            provider_id TEXT,
            is_user_edited INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS playlist (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            notes TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS playlist_item (
            id TEXT PRIMARY KEY,
            playlist_id TEXT NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
            track_id TEXT NOT NULL REFERENCES track(id) ON DELETE RESTRICT,
            preferred_asset_id TEXT REFERENCES digital_asset(id) ON DELETE SET NULL,
            position INTEGER NOT NULL,
            UNIQUE (playlist_id, position)
        );
        CREATE TABLE IF NOT EXISTS import_batch (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            source_description TEXT,
            started_at INTEGER NOT NULL,
            completed_at INTEGER,
            scan_cursor TEXT,
            error_summary TEXT
        );
        CREATE TABLE IF NOT EXISTS import_candidate (
            id TEXT PRIMARY KEY,
            batch_id TEXT NOT NULL REFERENCES import_batch(id) ON DELETE CASCADE,
            status TEXT NOT NULL,
            proposed_payload BLOB NOT NULL,
            selected_provider_id TEXT,
            confidence REAL,
            error_message TEXT,
            created_album_id TEXT REFERENCES album(id) ON DELETE SET NULL
        );
        CREATE TABLE IF NOT EXISTS edit_event (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            field_name TEXT NOT NULL,
            old_value TEXT,
            new_value TEXT,
            source TEXT NOT NULL,
            occurred_at INTEGER NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS catalogue_search USING fts5(owner_type UNINDEXED, owner_id UNINDEXED, content);
        PRAGMA user_version = 1;
        COMMIT;
        """
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &error) == SQLITE_OK else {
            defer { sqlite3_free(error) }
            throw DatabaseError.sqlite(message: error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection)))
        }
    }

    private static func migrateToVersion2(_ connection: OpaquePointer) throws {
        let sql = """
        BEGIN IMMEDIATE;
        ALTER TABLE album ADD COLUMN physical_location_unknown INTEGER NOT NULL DEFAULT 0 CHECK (physical_location_unknown IN (0, 1));
        PRAGMA user_version = 2;
        UPDATE catalogue_state SET schema_version = 2 WHERE singleton_id = 1;
        COMMIT;
        """
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &error) == SQLITE_OK else {
            defer { sqlite3_free(error) }
            throw DatabaseError.sqlite(message: error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection)))
        }
    }
}
