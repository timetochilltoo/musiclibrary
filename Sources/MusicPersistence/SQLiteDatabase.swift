import Foundation
import SQLite3
import MusicDomain

public enum DatabaseError: Error, Equatable, LocalizedError, Sendable {
    case sqlite(message: String)
    case notFound(String)
    case invalidIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): message
        case .notFound(let item): "\(item) was not found."
        case .invalidIdentifier(let value): "Invalid identifier: \(value)."
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
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            try Self.bind(Self.milliseconds(now), at: 18, to: statement)
            try Self.bind(Self.milliseconds(now), at: 19, to: statement)
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

            let update = try Self.prepare("UPDATE album SET has_cd = 1, physical_location_id = NULL, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(update) }
            try Self.bind(Self.milliseconds(Date()), at: 1, to: update)
            try Self.bind(albumID.description, at: 2, to: update)
            try Self.stepDone(update, connection: connection)
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

    private static let albumSelect = "SELECT id, title, edition_label, release_year, country_code, catalogue_number, disc_count, has_cd, physical_location_id, is_favourite, created_at, updated_at, deleted_at FROM album"

    private static func album(from statement: OpaquePointer) throws -> Album {
        guard let rawID = text(at: 0, from: statement), let uuid = UUID(uuidString: rawID) else { throw DatabaseError.invalidIdentifier("album.id") }
        let title = text(at: 1, from: statement) ?? ""
        let physicalLocationID = text(at: 8, from: statement).flatMap(UUID.init(uuidString:)).map(PhysicalLocationID.init(rawValue:))
        return Album(
            id: .init(rawValue: uuid),
            from: .init(
                title: title,
                editionLabel: text(at: 2, from: statement),
                releaseYear: int(at: 3, from: statement).map(Int.init),
                countryCode: text(at: 4, from: statement),
                catalogueNumber: text(at: 5, from: statement),
                discCount: Int(int(at: 6, from: statement) ?? 1),
                hasCD: int(at: 7, from: statement) == 1,
                physicalLocationID: physicalLocationID,
                isFavourite: int(at: 9, from: statement) == 1
            ),
            createdAt: date(fromMilliseconds: int(at: 10, from: statement) ?? 0),
            updatedAt: date(fromMilliseconds: int(at: 11, from: statement) ?? 0),
            deletedAt: int(at: 12, from: statement).map(date(fromMilliseconds:))
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
