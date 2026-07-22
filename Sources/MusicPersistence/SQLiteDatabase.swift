import Foundation
import SQLite3
import MusicDomain

public enum DatabaseError: Error, Equatable, LocalizedError, Sendable {
    case sqlite(message: String)
    case notFound(String)
    case invalidIdentifier(String)
    case invalidOperation(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): message
        case .notFound(let item): "\(item) was not found."
        case .invalidIdentifier(let value): "Invalid identifier: \(value)."
        case .invalidOperation(let message): message
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}

public actor MusicDatabase {
    private let connectionHandle: SQLiteHandle
    private var connection: OpaquePointer { connectionHandle.pointer }

    public init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            defer { if let handle { sqlite3_close(handle) } }
            throw DatabaseError.sqlite(message: "Unable to open SQLite database at \(url.path).")
        }
        connectionHandle = SQLiteHandle(handle)
        try Self.execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;", on: handle)
    }

    public func migrate() throws {
        try SchemaMigrator.migrate(connection)
    }

    public func schemaVersion() throws -> Int {
        try Int(Self.scalarInt("PRAGMA user_version;", on: connection))
    }

    public func currentRevision() throws -> Int64 {
        try Self.scalarInt("SELECT catalogue_revision FROM catalogue_state WHERE singleton_id = 1;", on: connection)
    }

    public func createStorageRoot(_ draft: NewStorageRoot) throws -> StorageRoot {
        let valid = try draft.validated()
        let id = StorageRootID(); let now = Date()
        try transaction {
            let statement = try Self.prepare("INSERT INTO storage_root (id, display_name, last_known_path, bookmark_data, volume_identifier, status, last_seen_at, bookmark_needs_refresh) VALUES (?, ?, ?, ?, ?, ?, ?, 0);", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.description, at: 1, to: statement); try Self.bind(valid.displayName, at: 2, to: statement); try Self.bind(valid.lastKnownPath, at: 3, to: statement); try Self.bind(valid.bookmarkData, at: 4, to: statement); try Self.bind(valid.volumeIdentifier, at: 5, to: statement); try Self.bind(valid.status.rawValue, at: 6, to: statement); try Self.bind(valid.status == .available ? Self.milliseconds(now) : nil, at: 7, to: statement); try Self.stepDone(statement, connection: connection)
            try incrementRevision()
        }
        return .init(id: id, displayName: valid.displayName, lastKnownPath: valid.lastKnownPath, bookmarkData: valid.bookmarkData, volumeIdentifier: valid.volumeIdentifier, status: valid.status, bookmarkNeedsRefresh: false, lastSeenAt: valid.status == .available ? now : nil)
    }

    public func storageRoots() throws -> [StorageRoot] {
        let statement = try Self.prepare("SELECT id, display_name, last_known_path, bookmark_data, volume_identifier, status, bookmark_needs_refresh, last_seen_at FROM storage_root ORDER BY display_name COLLATE NOCASE;", on: connection)
        defer { sqlite3_finalize(statement) }
        var values: [StorageRoot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: rawID), let rawStatus = Self.text(at: 5, from: statement), let status = StorageRootStatus(rawValue: rawStatus) else { throw DatabaseError.invalidIdentifier("storage_root") }
            values.append(.init(id: .init(rawValue: uuid), displayName: Self.text(at: 1, from: statement) ?? "", lastKnownPath: Self.text(at: 2, from: statement) ?? "", bookmarkData: Self.data(at: 3, from: statement), volumeIdentifier: Self.text(at: 4, from: statement), status: status, bookmarkNeedsRefresh: Self.int(at: 6, from: statement) == 1, lastSeenAt: Self.int(at: 7, from: statement).map(Self.date(fromMilliseconds:))))
        }
        return values
    }

    public func renameStorageRoot(_ id: StorageRootID, to displayName: String) throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Storage root name") }
        try transaction {
            let statement = try Self.prepare("UPDATE storage_root SET display_name = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(displayName, at: 1, to: statement); try Self.bind(id.description, at: 2, to: statement); try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Storage root") }; try incrementRevision()
        }
    }

    public func updateStorageRootAccess(_ id: StorageRootID, status: StorageRootStatus, lastKnownPath: String? = nil, bookmarkData: Data? = nil, bookmarkNeedsRefresh: Bool = false) throws {
        try transaction {
            let statement = try Self.prepare("UPDATE storage_root SET status = ?, last_known_path = COALESCE(?, last_known_path), bookmark_data = COALESCE(?, bookmark_data), bookmark_needs_refresh = ?, last_seen_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(status.rawValue, at: 1, to: statement); try Self.bind(lastKnownPath, at: 2, to: statement); try Self.bind(bookmarkData, at: 3, to: statement); try Self.bind(bookmarkNeedsRefresh ? 1 : 0, at: 4, to: statement); try Self.bind(status == .available ? Self.milliseconds(Date()) : nil, at: 5, to: statement); try Self.bind(id.description, at: 6, to: statement); try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Storage root") }; try incrementRevision()
        }
    }

    public func deleteStorageRoot(_ id: StorageRootID) throws {
        try transaction {
            guard !(try Self.exists("SELECT 1 FROM digital_asset WHERE storage_root_id = ? LIMIT 1;", value: id.description, on: connection)) else { throw DatabaseError.invalidOperation("A storage root with digital assets cannot be removed.") }
            let statement = try Self.prepare("DELETE FROM storage_root WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(id.description, at: 1, to: statement); try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Storage root") }; try incrementRevision()
        }
    }

    public func createLocation(_ draft: NewPhysicalLocation) throws -> PhysicalLocation {
        let valid = try draft.validated()
        let id = PhysicalLocationID()
        try transaction {
            let statement = try Self.prepare("""
                INSERT INTO physical_location (id, parent_id, name, sort_order, notes)
                VALUES (?, ?, ?, ?, ?);
                """, on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.description, at: 1, to: statement)
            try Self.bind(valid.parentID?.description, at: 2, to: statement)
            try Self.bind(valid.name, at: 3, to: statement)
            try Self.bind(Int64(valid.sortOrder), at: 4, to: statement)
            try Self.bind(valid.notes, at: 5, to: statement)
            try Self.stepDone(statement, connection: connection)
            try incrementRevision()
        }
        return .init(id: id, name: valid.name, parentID: valid.parentID, sortOrder: valid.sortOrder, notes: valid.notes)
    }

    public func locations() throws -> [PhysicalLocation] {
        let statement = try Self.prepare("SELECT id, parent_id, name, sort_order, notes FROM physical_location ORDER BY sort_order, name COLLATE NOCASE;", on: connection)
        defer { sqlite3_finalize(statement) }
        var results: [PhysicalLocation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: rawID) else { throw DatabaseError.invalidIdentifier("physical_location.id") }
            let parentID = Self.text(at: 1, from: statement).flatMap(UUID.init(uuidString:)).map(PhysicalLocationID.init(rawValue:))
            results.append(.init(
                id: .init(rawValue: uuid),
                name: Self.text(at: 2, from: statement) ?? "",
                parentID: parentID,
                sortOrder: Int(Self.int(at: 3, from: statement) ?? 0),
                notes: Self.text(at: 4, from: statement)
            ))
        }
        return results
    }

    public func renameLocation(_ id: PhysicalLocationID, to name: String) throws {
        let draft = try NewPhysicalLocation(name: name).validated()
        try transaction {
            let statement = try Self.prepare("UPDATE physical_location SET name = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(draft.name, at: 1, to: statement)
            try Self.bind(id.description, at: 2, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Physical location") }
            try incrementRevision()
        }
    }

    public func createAlbum(_ draft: NewAlbum) throws -> Album {
        try createAlbum(draft, in: nil, at: nil)
    }

    public func createAlbum(_ draft: NewAlbum, in boxSetID: BoxSetID?, at position: Int? = nil) throws -> Album {
        var valid = try draft.validated()
        if boxSetID != nil {
            valid.hasCD = true
            valid.physicalLocationID = nil
            valid.isPhysicalLocationUnknown = false
            valid = try valid.validated()
        }
        let id = AlbumID()
        let now = Date()
        try transaction {
            let statement = try Self.prepare("""
                INSERT INTO album (
                    id, title, edition_label, release_year, country_code, label_name,
                    catalogue_number, barcode, remaster_year, media_format, disc_count,
                    has_cd, physical_location_id, physical_note, notes, rating, is_favourite,
                    physical_location_unknown, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.description, at: 1, to: statement)
            try Self.bind(valid.title, at: 2, to: statement)
            try Self.bind(valid.editionLabel, at: 3, to: statement)
            try Self.bind(valid.releaseYear.map(Int64.init), at: 4, to: statement)
            try Self.bind(valid.countryCode, at: 5, to: statement)
            try Self.bind(valid.labelName, at: 6, to: statement)
            try Self.bind(valid.catalogueNumber, at: 7, to: statement)
            try Self.bind(valid.barcode, at: 8, to: statement)
            try Self.bind(valid.remasterYear.map(Int64.init), at: 9, to: statement)
            try Self.bind(valid.mediaFormat, at: 10, to: statement)
            try Self.bind(Int64(valid.discCount), at: 11, to: statement)
            try Self.bind(valid.hasCD ? 1 : 0, at: 12, to: statement)
            try Self.bind(valid.physicalLocationID?.description, at: 13, to: statement)
            try Self.bind(valid.physicalNote, at: 14, to: statement)
            try Self.bind(valid.notes, at: 15, to: statement)
            try Self.bind(valid.rating.map(Int64.init), at: 16, to: statement)
            try Self.bind(valid.isFavourite ? 1 : 0, at: 17, to: statement)
            try Self.bind(valid.isPhysicalLocationUnknown ? 1 : 0, at: 18, to: statement)
            try Self.bind(Self.milliseconds(now), at: 19, to: statement)
            try Self.bind(Self.milliseconds(now), at: 20, to: statement)
            try Self.stepDone(statement, connection: connection)
            if let boxSetID {
                guard try Self.exists("SELECT 1 FROM box_set WHERE id = ? AND deleted_at IS NULL;", value: boxSetID.description, on: connection) else { throw DatabaseError.notFound("Box set") }
                let membership = try Self.prepare("INSERT INTO box_set_album (box_set_id, album_id, position) VALUES (?, ?, ?);", on: connection)
                defer { sqlite3_finalize(membership) }
                try Self.bind(boxSetID.description, at: 1, to: membership)
                try Self.bind(id.description, at: 2, to: membership)
                let resolvedPosition: Int
                if let position { resolvedPosition = position }
                else { resolvedPosition = try Self.nextBoxPosition(for: boxSetID, on: connection) }
                try Self.bind(Int64(resolvedPosition), at: 3, to: membership)
                try Self.stepDone(membership, connection: connection)
            }
            try incrementRevision()
        }
        return .init(id: id, from: valid, createdAt: now, updatedAt: now)
    }

    public func album(id: AlbumID) throws -> Album? {
        let statement = try Self.prepare(Self.albumSelect + " WHERE id = ? AND deleted_at IS NULL;", on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(id.description, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try Self.album(from: statement)
    }

    public func updateAlbum(_ id: AlbumID, with draft: NewAlbum) throws -> Album {
        let valid = try draft.validated()
        try transaction {
            if try boxPlacement(for: id) != nil, (valid.physicalLocationID != nil || valid.isPhysicalLocationUnknown || !valid.hasCD) {
                throw DatabaseError.invalidOperation("A boxed album inherits its physical placement. Remove it from the box before changing CD location or availability.")
            }
            let statement = try Self.prepare("""
                UPDATE album SET title = ?, edition_label = ?, release_year = ?, country_code = ?, label_name = ?,
                    catalogue_number = ?, barcode = ?, remaster_year = ?, media_format = ?, disc_count = ?, has_cd = ?,
                    physical_location_id = ?, physical_location_unknown = ?, physical_note = ?, notes = ?, rating = ?,
                    is_favourite = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL;
                """, on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(valid.title, at: 1, to: statement)
            try Self.bind(valid.editionLabel, at: 2, to: statement)
            try Self.bind(valid.releaseYear.map(Int64.init), at: 3, to: statement)
            try Self.bind(valid.countryCode, at: 4, to: statement)
            try Self.bind(valid.labelName, at: 5, to: statement)
            try Self.bind(valid.catalogueNumber, at: 6, to: statement)
            try Self.bind(valid.barcode, at: 7, to: statement)
            try Self.bind(valid.remasterYear.map(Int64.init), at: 8, to: statement)
            try Self.bind(valid.mediaFormat, at: 9, to: statement)
            try Self.bind(Int64(valid.discCount), at: 10, to: statement)
            try Self.bind(valid.hasCD ? 1 : 0, at: 11, to: statement)
            try Self.bind(valid.physicalLocationID?.description, at: 12, to: statement)
            try Self.bind(valid.isPhysicalLocationUnknown ? 1 : 0, at: 13, to: statement)
            try Self.bind(valid.physicalNote, at: 14, to: statement)
            try Self.bind(valid.notes, at: 15, to: statement)
            try Self.bind(valid.rating.map(Int64.init), at: 16, to: statement)
            try Self.bind(valid.isFavourite ? 1 : 0, at: 17, to: statement)
            try Self.bind(Self.milliseconds(Date()), at: 18, to: statement)
            try Self.bind(id.description, at: 19, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Album") }
            try incrementRevision()
        }
        guard let updated = try album(id: id) else { throw DatabaseError.notFound("Album") }
        return updated
    }

    public func albums(matching term: String? = nil) throws -> [Album] {
        let query: String
        if let term, !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query = Self.albumSelect + " WHERE deleted_at IS NULL AND (title LIKE ? COLLATE NOCASE OR edition_label LIKE ? COLLATE NOCASE OR catalogue_number LIKE ? COLLATE NOCASE) ORDER BY title COLLATE NOCASE, edition_label COLLATE NOCASE;"
        } else {
            query = Self.albumSelect + " WHERE deleted_at IS NULL ORDER BY title COLLATE NOCASE, edition_label COLLATE NOCASE;"
        }
        let statement = try Self.prepare(query, on: connection)
        defer { sqlite3_finalize(statement) }
        if let term, !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pattern = "%\(term)%"
            try Self.bind(pattern, at: 1, to: statement)
            try Self.bind(pattern, at: 2, to: statement)
            try Self.bind(pattern, at: 3, to: statement)
        }
        var rows: [Album] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(try Self.album(from: statement)) }
        return rows
    }

    public func createBoxSet(_ draft: NewBoxSet) throws -> BoxSet {
        let valid = try draft.validated()
        let id = BoxSetID()
        let now = Self.milliseconds(Date())
        try transaction {
            let statement = try Self.prepare("""
                INSERT INTO box_set (id, title, edition_label, physical_location_id, notes, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """, on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.description, at: 1, to: statement)
            try Self.bind(valid.title, at: 2, to: statement)
            try Self.bind(valid.editionLabel, at: 3, to: statement)
            try Self.bind(valid.physicalLocationID.description, at: 4, to: statement)
            try Self.bind(valid.notes, at: 5, to: statement)
            try Self.bind(now, at: 6, to: statement)
            try Self.bind(now, at: 7, to: statement)
            try Self.stepDone(statement, connection: connection)
            try incrementRevision()
        }
        return .init(id: id, title: valid.title, editionLabel: valid.editionLabel, physicalLocationID: valid.physicalLocationID)
    }

    public func boxSets() throws -> [BoxSet] {
        let statement = try Self.prepare("SELECT id, title, edition_label, physical_location_id FROM box_set WHERE deleted_at IS NULL ORDER BY title COLLATE NOCASE, edition_label COLLATE NOCASE;", on: connection)
        defer { sqlite3_finalize(statement) }
        var results: [BoxSet] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let rawID = Self.text(at: 0, from: statement), let id = UUID(uuidString: rawID),
                let rawLocationID = Self.text(at: 3, from: statement), let locationID = UUID(uuidString: rawLocationID)
            else { throw DatabaseError.invalidIdentifier("box_set") }
            results.append(.init(id: .init(rawValue: id), title: Self.text(at: 1, from: statement) ?? "", editionLabel: Self.text(at: 2, from: statement), physicalLocationID: .init(rawValue: locationID)))
        }
        return results
    }

    public func boxMembers(of boxSetID: BoxSetID) throws -> [BoxSetMembership] {
        let sql = Self.albumSelect + " JOIN box_set_album ON box_set_album.album_id = album.id WHERE box_set_album.box_set_id = ? AND album.deleted_at IS NULL ORDER BY box_set_album.position;"
        let statement = try Self.prepare(sql, on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(boxSetID.description, at: 1, to: statement)
        var members: [BoxSetMembership] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let album = try Self.album(from: statement)
            members.append(.init(album: album, boxSetID: boxSetID, position: try Self.boxPosition(for: boxSetID, albumID: album.id, on: connection)))
        }
        return members
    }

    public func boxPlacement(for albumID: AlbumID) throws -> AlbumBoxPlacement? {
        let statement = try Self.prepare("""
            SELECT box_set.id, box_set.title, box_set_album.position
            FROM box_set_album JOIN box_set ON box_set.id = box_set_album.box_set_id
            WHERE box_set_album.album_id = ? AND box_set.deleted_at IS NULL;
            """, on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(albumID.description, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let rawID = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: rawID) else { return nil }
        return .init(boxSetID: .init(rawValue: uuid), boxSetTitle: Self.text(at: 1, from: statement) ?? "", position: Int(Self.int(at: 2, from: statement) ?? 0))
    }

    public func createDisc(albumID: AlbumID, title: String? = nil, mediaFormat: String? = nil) throws -> Disc {
        let id = DiscID(); var number = 0
        try transaction {
            guard try Self.exists("SELECT 1 FROM album WHERE id = ? AND deleted_at IS NULL;", value: albumID.description, on: connection) else { throw DatabaseError.notFound("Album") }
            number = try Self.nextNumber("SELECT COALESCE(MAX(number), 0) + 1 FROM disc WHERE album_id = ?;", ownerID: albumID.description, on: connection)
            let statement = try Self.prepare("INSERT INTO disc (id, album_id, number, title, media_format) VALUES (?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.description, at: 1, to: statement); try Self.bind(albumID.description, at: 2, to: statement); try Self.bind(Int64(number), at: 3, to: statement); try Self.bind(title, at: 4, to: statement); try Self.bind(mediaFormat, at: 5, to: statement)
            try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
        return .init(id: id, albumID: albumID, number: number, title: title, mediaFormat: mediaFormat)
    }

    public func discs(albumID: AlbumID) throws -> [Disc] {
        let statement = try Self.prepare("SELECT id, number, title, media_format FROM disc WHERE album_id = ? ORDER BY number;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(albumID.description, at: 1, to: statement)
        var values: [Disc] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("disc.id") }
            values.append(.init(id: .init(rawValue: uuid), albumID: albumID, number: Int(Self.int(at: 1, from: statement) ?? 0), title: Self.text(at: 2, from: statement), mediaFormat: Self.text(at: 3, from: statement)))
        }
        return values
    }

    public func createTrack(discID: DiscID, draft: NewTrack) throws -> Track {
        let valid = try draft.validated(); let id = TrackID(); var number = 0
        try transaction {
            guard try Self.exists("SELECT 1 FROM disc WHERE id = ?;", value: discID.description, on: connection) else { throw DatabaseError.notFound("Disc") }
            number = try Self.nextNumber("SELECT COALESCE(MAX(number), 0) + 1 FROM track WHERE disc_id = ?;", ownerID: discID.description, on: connection)
            let statement = try Self.prepare("INSERT INTO track (id, disc_id, number, display_position, title, duration_ms, work_name, movement_number, movement_name, is_instrumental) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.description, at: 1, to: statement); try Self.bind(discID.description, at: 2, to: statement); try Self.bind(Int64(number), at: 3, to: statement); try Self.bind(valid.displayPosition, at: 4, to: statement); try Self.bind(valid.title, at: 5, to: statement); try Self.bind(valid.durationMilliseconds.map(Int64.init), at: 6, to: statement); try Self.bind(valid.workName, at: 7, to: statement); try Self.bind(valid.movementNumber.map(Int64.init), at: 8, to: statement); try Self.bind(valid.movementName, at: 9, to: statement); try Self.bind(valid.isInstrumental.map { Int64($0 ? 1 : 0) }, at: 10, to: statement)
            try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
        return .init(id: id, discID: discID, number: number, title: valid.title, displayPosition: valid.displayPosition, durationMilliseconds: valid.durationMilliseconds, workName: valid.workName, movementNumber: valid.movementNumber, movementName: valid.movementName, isInstrumental: valid.isInstrumental)
    }

    public func updateTrack(_ trackID: TrackID, with draft: NewTrack) throws -> Track {
        let valid = try draft.validated()
        var result: Track?
        try transaction {
            let existing = try Self.prepare("SELECT disc_id, number FROM track WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(existing) }
            try Self.bind(trackID.description, at: 1, to: existing)
            guard sqlite3_step(existing) == SQLITE_ROW,
                  let rawDiscID = Self.text(at: 0, from: existing),
                  let discUUID = UUID(uuidString: rawDiscID) else { throw DatabaseError.notFound("Track") }
            let statement = try Self.prepare("UPDATE track SET title = ?, display_position = ?, duration_ms = ?, work_name = ?, movement_number = ?, movement_name = ?, is_instrumental = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(valid.title, at: 1, to: statement); try Self.bind(valid.displayPosition, at: 2, to: statement); try Self.bind(valid.durationMilliseconds.map(Int64.init), at: 3, to: statement); try Self.bind(valid.workName, at: 4, to: statement); try Self.bind(valid.movementNumber.map(Int64.init), at: 5, to: statement); try Self.bind(valid.movementName, at: 6, to: statement); try Self.bind(valid.isInstrumental.map { Int64($0 ? 1 : 0) }, at: 7, to: statement); try Self.bind(trackID.description, at: 8, to: statement); try Self.stepDone(statement, connection: connection)
            result = .init(id: trackID, discID: .init(rawValue: discUUID), number: Int(Self.int(at: 1, from: existing) ?? 0), title: valid.title, displayPosition: valid.displayPosition, durationMilliseconds: valid.durationMilliseconds, workName: valid.workName, movementNumber: valid.movementNumber, movementName: valid.movementName, isInstrumental: valid.isInstrumental)
            try incrementRevision()
        }
        guard let result else { throw DatabaseError.notFound("Track") }
        return result
    }

    public func deleteTrack(_ trackID: TrackID) throws {
        try transaction {
            let existing = try Self.prepare("SELECT disc_id, number FROM track WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(existing) }
            try Self.bind(trackID.description, at: 1, to: existing)
            guard sqlite3_step(existing) == SQLITE_ROW, let discID = Self.text(at: 0, from: existing) else { throw DatabaseError.notFound("Track") }
            let number = Self.int(at: 1, from: existing) ?? 0
            let delete = try Self.prepare("DELETE FROM track WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(delete) }; try Self.bind(trackID.description, at: 1, to: delete); try Self.stepDone(delete, connection: connection)
            let reorder = try Self.prepare("UPDATE track SET number = number - 1 WHERE disc_id = ? AND number > ?;", on: connection)
            defer { sqlite3_finalize(reorder) }; try Self.bind(discID, at: 1, to: reorder); try Self.bind(number, at: 2, to: reorder); try Self.stepDone(reorder, connection: connection)
            try incrementRevision()
        }
    }

    public func tracks(discID: DiscID) throws -> [Track] {
        let statement = try Self.prepare("SELECT id, number, title, display_position, duration_ms, work_name, movement_number, movement_name, is_instrumental FROM track WHERE disc_id = ? ORDER BY number;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(discID.description, at: 1, to: statement)
        var values: [Track] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("track.id") }
            let instrumental = Self.int(at: 8, from: statement).map { $0 == 1 }
            values.append(.init(id: .init(rawValue: uuid), discID: discID, number: Int(Self.int(at: 1, from: statement) ?? 0), title: Self.text(at: 2, from: statement) ?? "", displayPosition: Self.text(at: 3, from: statement), durationMilliseconds: Self.int(at: 4, from: statement).map(Int.init), workName: Self.text(at: 5, from: statement), movementNumber: Self.int(at: 6, from: statement).map(Int.init), movementName: Self.text(at: 7, from: statement), isInstrumental: instrumental))
        }
        return values
    }

    public func createContributor(_ draft: NewContributor) throws -> Contributor {
        let valid = try draft.validated(); let id = ContributorID(); let now = Self.milliseconds(Date())
        try transaction {
            let statement = try Self.prepare("INSERT INTO contributor (id, name, sort_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(id.description, at: 1, to: statement); try Self.bind(valid.name, at: 2, to: statement); try Self.bind(valid.sortName, at: 3, to: statement); try Self.bind(now, at: 4, to: statement); try Self.bind(now, at: 5, to: statement); try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
        return .init(id: id, name: valid.name, sortName: valid.sortName)
    }

    public func addAlbumContributor(_ contributorID: ContributorID, to albumID: AlbumID, role: ContributorRole, creditedName: String? = nil) throws {
        try transaction {
            guard try Self.exists("SELECT 1 FROM album WHERE id = ? AND deleted_at IS NULL;", value: albumID.description, on: connection) else { throw DatabaseError.notFound("Album") }
            guard try Self.exists("SELECT 1 FROM contributor WHERE id = ?;", value: contributorID.description, on: connection) else { throw DatabaseError.notFound("Contributor") }
            let position = try Self.nextNumber("SELECT COALESCE(MAX(position), -1) + 1 FROM album_contributor WHERE album_id = ? AND role = ?;", ownerID: albumID.description, on: connection, additionalValue: role.rawValue)
            let statement = try Self.prepare("INSERT INTO album_contributor (album_id, contributor_id, role, credited_name, position) VALUES (?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(albumID.description, at: 1, to: statement); try Self.bind(contributorID.description, at: 2, to: statement); try Self.bind(role.rawValue, at: 3, to: statement); try Self.bind(creditedName, at: 4, to: statement); try Self.bind(Int64(position), at: 5, to: statement); try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
    }

    public func albumContributors(albumID: AlbumID) throws -> [ContributorCredit] {
        let statement = try Self.prepare("SELECT contributor.id, contributor.name, contributor.sort_name, album_contributor.role, album_contributor.credited_name, album_contributor.position FROM album_contributor JOIN contributor ON contributor.id = album_contributor.contributor_id WHERE album_contributor.album_id = ? ORDER BY album_contributor.role, album_contributor.position;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(albumID.description, at: 1, to: statement)
        var values: [ContributorCredit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw), let roleRaw = Self.text(at: 3, from: statement), let role = ContributorRole(rawValue: roleRaw) else { throw DatabaseError.invalidIdentifier("album_contributor") }
            values.append(.init(contributor: .init(id: .init(rawValue: uuid), name: Self.text(at: 1, from: statement) ?? "", sortName: Self.text(at: 2, from: statement)), role: role, creditedName: Self.text(at: 4, from: statement), position: Int(Self.int(at: 5, from: statement) ?? 0)))
        }
        return values
    }

    public func addTrackContributor(_ contributorID: ContributorID, to trackID: TrackID, role: ContributorRole, creditedName: String? = nil) throws {
        try transaction {
            guard try Self.exists("SELECT 1 FROM track WHERE id = ?;", value: trackID.description, on: connection) else { throw DatabaseError.notFound("Track") }
            guard try Self.exists("SELECT 1 FROM contributor WHERE id = ?;", value: contributorID.description, on: connection) else { throw DatabaseError.notFound("Contributor") }
            let position = try Self.nextNumber("SELECT COALESCE(MAX(position), -1) + 1 FROM track_contributor WHERE track_id = ? AND role = ?;", ownerID: trackID.description, on: connection, additionalValue: role.rawValue)
            let statement = try Self.prepare("INSERT INTO track_contributor (track_id, contributor_id, role, credited_name, position) VALUES (?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(trackID.description, at: 1, to: statement); try Self.bind(contributorID.description, at: 2, to: statement); try Self.bind(role.rawValue, at: 3, to: statement); try Self.bind(creditedName, at: 4, to: statement); try Self.bind(Int64(position), at: 5, to: statement); try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
    }

    public func trackContributors(trackID: TrackID) throws -> [ContributorCredit] {
        let statement = try Self.prepare("SELECT contributor.id, contributor.name, contributor.sort_name, track_contributor.role, track_contributor.credited_name, track_contributor.position FROM track_contributor JOIN contributor ON contributor.id = track_contributor.contributor_id WHERE track_contributor.track_id = ? ORDER BY track_contributor.role, track_contributor.position;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(trackID.description, at: 1, to: statement)
        var values: [ContributorCredit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw), let roleRaw = Self.text(at: 3, from: statement), let role = ContributorRole(rawValue: roleRaw) else { throw DatabaseError.invalidIdentifier("track_contributor") }
            values.append(.init(contributor: .init(id: .init(rawValue: uuid), name: Self.text(at: 1, from: statement) ?? "", sortName: Self.text(at: 2, from: statement)), role: role, creditedName: Self.text(at: 4, from: statement), position: Int(Self.int(at: 5, from: statement) ?? 0)))
        }
        return values
    }

    public func addAlbumArtwork(albumID: AlbumID, localPath: String, role: ArtworkRole = .front, source: String = "user-selected") throws -> Artwork {
        let id = UUID()
        try transaction {
            guard try Self.exists("SELECT 1 FROM album WHERE id = ? AND deleted_at IS NULL;", value: albumID.description, on: connection) else { throw DatabaseError.notFound("Album") }
            if role == .front {
                let deselect = try Self.prepare("UPDATE artwork SET is_selected = 0 WHERE owner_type = 'album' AND owner_id = ? AND role = 'front';", on: connection)
                defer { sqlite3_finalize(deselect) }; try Self.bind(albumID.description, at: 1, to: deselect); try Self.stepDone(deselect, connection: connection)
            }
            let statement = try Self.prepare("INSERT INTO artwork (id, owner_type, owner_id, role, local_path, source, is_selected) VALUES (?, 'album', ?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(id.uuidString.lowercased(), at: 1, to: statement); try Self.bind(albumID.description, at: 2, to: statement); try Self.bind(role.rawValue, at: 3, to: statement); try Self.bind(localPath, at: 4, to: statement); try Self.bind(source, at: 5, to: statement); try Self.bind(role == .front ? 1 : 0, at: 6, to: statement); try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
        return .init(id: id, ownerType: "album", ownerID: albumID.description, role: role, localPath: localPath, source: source, isSelected: role == .front)
    }

    public func albumArtwork(albumID: AlbumID) throws -> [Artwork] {
        let statement = try Self.prepare("SELECT id, role, local_path, source, is_selected FROM artwork WHERE owner_type = 'album' AND owner_id = ? ORDER BY is_selected DESC, role;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(albumID.description, at: 1, to: statement)
        var values: [Artwork] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let id = UUID(uuidString: raw), let roleRaw = Self.text(at: 1, from: statement), let role = ArtworkRole(rawValue: roleRaw) else { throw DatabaseError.invalidIdentifier("artwork") }
            values.append(.init(id: id, ownerType: "album", ownerID: albumID.description, role: role, localPath: Self.text(at: 2, from: statement), source: Self.text(at: 3, from: statement) ?? "", isSelected: Self.int(at: 4, from: statement) == 1))
        }
        return values
    }

    public func addAlbumAlias(albumID: AlbumID, name: String, kind: AlbumAliasKind, locale: String? = nil) throws -> AlbumAlias {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Alias") }
        let id = UUID()
        try transaction {
            let statement = try Self.prepare("INSERT INTO album_alias (id, album_id, name, locale, kind) VALUES (?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(id.uuidString.lowercased(), at: 1, to: statement); try Self.bind(albumID.description, at: 2, to: statement); try Self.bind(name, at: 3, to: statement); try Self.bind(locale, at: 4, to: statement); try Self.bind(kind.rawValue, at: 5, to: statement); try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
        return .init(id: id, albumID: albumID, name: name, locale: locale, kind: kind)
    }

    public func albumAliases(albumID: AlbumID) throws -> [AlbumAlias] {
        let statement = try Self.prepare("SELECT id, name, locale, kind FROM album_alias WHERE album_id = ? ORDER BY kind, name COLLATE NOCASE;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(albumID.description, at: 1, to: statement)
        var values: [AlbumAlias] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let id = UUID(uuidString: raw), let kindRaw = Self.text(at: 3, from: statement), let kind = AlbumAliasKind(rawValue: kindRaw) else { throw DatabaseError.invalidIdentifier("album_alias") }
            values.append(.init(id: id, albumID: albumID, name: Self.text(at: 1, from: statement) ?? "", locale: Self.text(at: 2, from: statement), kind: kind))
        }
        return values
    }

    public func deleteAlbumAlias(_ aliasID: UUID) throws {
        try transaction {
            let statement = try Self.prepare("DELETE FROM album_alias WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(aliasID.uuidString.lowercased(), at: 1, to: statement); try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Album alias") }
            try incrementRevision()
        }
    }

    public func addAlbum(_ albumID: AlbumID, to boxSetID: BoxSetID, at position: Int) throws {
        try transaction {
            guard try Self.exists("SELECT 1 FROM album WHERE id = ? AND deleted_at IS NULL;", value: albumID.description, on: connection) else { throw DatabaseError.notFound("Album") }
            guard try Self.exists("SELECT 1 FROM box_set WHERE id = ? AND deleted_at IS NULL;", value: boxSetID.description, on: connection) else { throw DatabaseError.notFound("Box set") }
            let membership = try Self.prepare("INSERT INTO box_set_album (box_set_id, album_id, position) VALUES (?, ?, ?);", on: connection)
            defer { sqlite3_finalize(membership) }
            try Self.bind(boxSetID.description, at: 1, to: membership)
            try Self.bind(albumID.description, at: 2, to: membership)
            try Self.bind(Int64(position), at: 3, to: membership)
            try Self.stepDone(membership, connection: connection)

            let update = try Self.prepare("UPDATE album SET has_cd = 1, physical_location_id = NULL, physical_location_unknown = 0, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(update) }
            try Self.bind(Self.milliseconds(Date()), at: 1, to: update)
            try Self.bind(albumID.description, at: 2, to: update)
            try Self.stepDone(update, connection: connection)
            try incrementRevision()
        }
    }

    public func moveAlbum(_ albumID: AlbumID, to boxSetID: BoxSetID, at position: Int? = nil) throws {
        try transaction {
            guard try Self.exists("SELECT 1 FROM album WHERE id = ? AND deleted_at IS NULL;", value: albumID.description, on: connection) else { throw DatabaseError.notFound("Album") }
            guard try Self.exists("SELECT 1 FROM box_set WHERE id = ? AND deleted_at IS NULL;", value: boxSetID.description, on: connection) else { throw DatabaseError.notFound("Box set") }
            let delete = try Self.prepare("DELETE FROM box_set_album WHERE album_id = ?;", on: connection)
            defer { sqlite3_finalize(delete) }
            try Self.bind(albumID.description, at: 1, to: delete)
            try Self.stepDone(delete, connection: connection)
            let insert = try Self.prepare("INSERT INTO box_set_album (box_set_id, album_id, position) VALUES (?, ?, ?);", on: connection)
            defer { sqlite3_finalize(insert) }
            try Self.bind(boxSetID.description, at: 1, to: insert)
            try Self.bind(albumID.description, at: 2, to: insert)
            let resolvedPosition: Int
            if let position { resolvedPosition = position }
            else { resolvedPosition = try Self.nextBoxPosition(for: boxSetID, on: connection) }
            try Self.bind(Int64(resolvedPosition), at: 3, to: insert)
            try Self.stepDone(insert, connection: connection)
            let update = try Self.prepare("UPDATE album SET has_cd = 1, physical_location_id = NULL, physical_location_unknown = 0, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(update) }
            try Self.bind(Self.milliseconds(Date()), at: 1, to: update)
            try Self.bind(albumID.description, at: 2, to: update)
            try Self.stepDone(update, connection: connection)
            try incrementRevision()
        }
    }

    public func removeAlbum(_ albumID: AlbumID, from boxSetID: BoxSetID, assigning locationID: PhysicalLocationID?, locationUnknown: Bool) throws {
        guard locationID != nil || locationUnknown else { throw DatabaseError.invalidOperation("Choose a physical location or explicitly mark the location unknown before removing an album from its box.") }
        guard !(locationID != nil && locationUnknown) else { throw DatabaseError.invalidOperation("Choose either a physical location or unknown location, not both.") }
        try transaction {
            let delete = try Self.prepare("DELETE FROM box_set_album WHERE box_set_id = ? AND album_id = ?;", on: connection)
            defer { sqlite3_finalize(delete) }
            try Self.bind(boxSetID.description, at: 1, to: delete)
            try Self.bind(albumID.description, at: 2, to: delete)
            try Self.stepDone(delete, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Box-set membership") }
            let update = try Self.prepare("UPDATE album SET physical_location_id = ?, physical_location_unknown = ?, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(update) }
            try Self.bind(locationID?.description, at: 1, to: update)
            try Self.bind(locationUnknown ? 1 : 0, at: 2, to: update)
            try Self.bind(Self.milliseconds(Date()), at: 3, to: update)
            try Self.bind(albumID.description, at: 4, to: update)
            try Self.stepDone(update, connection: connection)
            try incrementRevision()
        }
    }

    public func reorderAlbum(_ albumID: AlbumID, in boxSetID: BoxSetID, to newPosition: Int) throws {
        try transaction {
            var orderedIDs = try Self.boxMemberIDs(for: boxSetID, on: connection)
            guard let currentIndex = orderedIDs.firstIndex(of: albumID) else { throw DatabaseError.notFound("Box-set membership") }
            orderedIDs.remove(at: currentIndex)
            orderedIDs.insert(albumID, at: min(max(0, newPosition - 1), orderedIDs.count))
            let negate = try Self.prepare("UPDATE box_set_album SET position = -position WHERE box_set_id = ?;", on: connection)
            defer { sqlite3_finalize(negate) }
            try Self.bind(boxSetID.description, at: 1, to: negate)
            try Self.stepDone(negate, connection: connection)
            for (index, memberID) in orderedIDs.enumerated() {
                let statement = try Self.prepare("UPDATE box_set_album SET position = ? WHERE box_set_id = ? AND album_id = ?;", on: connection)
                defer { sqlite3_finalize(statement) }
                try Self.bind(Int64(index + 1), at: 1, to: statement)
                try Self.bind(boxSetID.description, at: 2, to: statement)
                try Self.bind(memberID.description, at: 3, to: statement)
                try Self.stepDone(statement, connection: connection)
            }
            try incrementRevision()
        }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try Self.execute("BEGIN IMMEDIATE;", on: connection)
        do {
            try work()
            try Self.execute("COMMIT;", on: connection)
        } catch {
            try? Self.execute("ROLLBACK;", on: connection)
            throw error
        }
    }

    private func incrementRevision() throws {
        try Self.execute("UPDATE catalogue_state SET catalogue_revision = catalogue_revision + 1 WHERE singleton_id = 1;", on: connection)
    }

    private static let albumSelect = "SELECT id, title, edition_label, release_year, country_code, label_name, catalogue_number, barcode, remaster_year, media_format, disc_count, has_cd, physical_location_id, physical_location_unknown, physical_note, notes, rating, is_favourite, created_at, updated_at, deleted_at FROM album"

    private static func album(from statement: OpaquePointer) throws -> Album {
        guard let rawID = text(at: 0, from: statement), let uuid = UUID(uuidString: rawID) else { throw DatabaseError.invalidIdentifier("album.id") }
        let title = text(at: 1, from: statement) ?? ""
        let physicalLocationID = text(at: 12, from: statement).flatMap(UUID.init(uuidString:)).map(PhysicalLocationID.init(rawValue:))
        return Album(
            id: .init(rawValue: uuid),
            from: .init(
                title: title,
                editionLabel: text(at: 2, from: statement),
                releaseYear: int(at: 3, from: statement).map(Int.init),
                countryCode: text(at: 4, from: statement),
                labelName: text(at: 5, from: statement),
                catalogueNumber: text(at: 6, from: statement),
                barcode: text(at: 7, from: statement),
                remasterYear: int(at: 8, from: statement).map(Int.init),
                mediaFormat: text(at: 9, from: statement),
                discCount: Int(int(at: 10, from: statement) ?? 1),
                hasCD: int(at: 11, from: statement) == 1,
                physicalLocationID: physicalLocationID,
                isPhysicalLocationUnknown: int(at: 13, from: statement) == 1,
                physicalNote: text(at: 14, from: statement),
                notes: text(at: 15, from: statement),
                rating: int(at: 16, from: statement).map(Int.init),
                isFavourite: int(at: 17, from: statement) == 1
            ),
            createdAt: date(fromMilliseconds: int(at: 18, from: statement) ?? 0),
            updatedAt: date(fromMilliseconds: int(at: 19, from: statement) ?? 0),
            deletedAt: int(at: 20, from: statement).map(date(fromMilliseconds:))
        )
    }

    private static func execute(_ sql: String, on connection: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &error) == SQLITE_OK else {
            defer { sqlite3_free(error) }
            throw DatabaseError.sqlite(message: error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection)))
        }
    }

    private static func prepare(_ sql: String, on connection: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(connection)))
        }
        return statement
    }

    private static func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        if let value { result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) } }
        else { result = sqlite3_bind_null(statement, index) }
        guard result == SQLITE_OK else { throw DatabaseError.sqlite(message: "Unable to bind SQLite string value.") }
    }

    private static func bind(_ value: Int64?, at index: Int32, to statement: OpaquePointer) throws {
        let result = value.map { sqlite3_bind_int64(statement, index, $0) } ?? sqlite3_bind_null(statement, index)
        guard result == SQLITE_OK else { throw DatabaseError.sqlite(message: "Unable to bind SQLite integer value.") }
    }

    private static func bind(_ value: Data?, at index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        if let value { result = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient) } }
        else { result = sqlite3_bind_null(statement, index) }
        guard result == SQLITE_OK else { throw DatabaseError.sqlite(message: "Unable to bind SQLite data value.") }
    }

    private static func data(at column: Int32, from statement: OpaquePointer) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let pointer = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: pointer, count: count)
    }

    private static func stepDone(_ statement: OpaquePointer, connection: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(connection))) }
    }

    private static func scalarInt(_ sql: String, on connection: OpaquePointer) throws -> Int64 {
        let statement = try prepare(sql, on: connection)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DatabaseError.sqlite(message: "Expected a SQLite scalar result.") }
        return sqlite3_column_int64(statement, 0)
    }

    private static func exists(_ sql: String, value: String, on connection: OpaquePointer) throws -> Bool {
        let statement = try prepare(sql, on: connection)
        defer { sqlite3_finalize(statement) }
        try bind(value, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func nextBoxPosition(for boxSetID: BoxSetID, on connection: OpaquePointer) throws -> Int {
        let statement = try prepare("SELECT COALESCE(MAX(position), 0) + 1 FROM box_set_album WHERE box_set_id = ?;", on: connection)
        defer { sqlite3_finalize(statement) }
        try bind(boxSetID.description, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DatabaseError.sqlite(message: "Unable to determine the next box-set position.") }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func nextNumber(_ sql: String, ownerID: String, on connection: OpaquePointer, additionalValue: String? = nil) throws -> Int {
        let statement = try prepare(sql, on: connection)
        defer { sqlite3_finalize(statement) }
        try bind(ownerID, at: 1, to: statement)
        if let additionalValue { try bind(additionalValue, at: 2, to: statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DatabaseError.sqlite(message: "Unable to determine the next position.") }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func boxPosition(for boxSetID: BoxSetID, albumID: AlbumID, on connection: OpaquePointer) throws -> Int {
        let statement = try prepare("SELECT position FROM box_set_album WHERE box_set_id = ? AND album_id = ?;", on: connection)
        defer { sqlite3_finalize(statement) }
        try bind(boxSetID.description, at: 1, to: statement)
        try bind(albumID.description, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DatabaseError.notFound("Box-set membership") }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func boxMemberIDs(for boxSetID: BoxSetID, on connection: OpaquePointer) throws -> [AlbumID] {
        let statement = try prepare("SELECT album_id FROM box_set_album WHERE box_set_id = ? ORDER BY position;", on: connection)
        defer { sqlite3_finalize(statement) }
        try bind(boxSetID.description, at: 1, to: statement)
        var ids: [AlbumID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = text(at: 0, from: statement), let uuid = UUID(uuidString: rawID) else { throw DatabaseError.invalidIdentifier("box_set_album.album_id") }
            ids.append(.init(rawValue: uuid))
        }
        return ids
    }

    private static func text(at column: Int32, from statement: OpaquePointer) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private static func int(at column: Int32, from statement: OpaquePointer) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column)
    }

    private static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1_000).rounded()) }
    private static func date(fromMilliseconds milliseconds: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000) }
}
