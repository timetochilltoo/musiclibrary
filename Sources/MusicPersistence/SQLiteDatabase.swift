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

    public func recentCatalogueActivity(limit: Int = 30) throws -> [CatalogueActivity] {
        guard (1...100).contains(limit) else { throw DatabaseError.invalidOperation("Activity history limit must be between 1 and 100.") }
        let statement = try Self.prepare("SELECT id, new_value, occurred_at FROM edit_event WHERE entity_type = 'catalogue' AND field_name = 'catalogue_revision' ORDER BY occurred_at DESC, rowid DESC LIMIT ?;", on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(Int64(limit), at: 1, to: statement)
        var activity: [CatalogueActivity] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let id = UUID(uuidString: rawID), let revision = Self.text(at: 1, from: statement), let revisionValue = Int64(revision), let occurredAt = Self.int(at: 2, from: statement) else { continue }
            activity.append(.init(id: id, revision: revisionValue, occurredAt: Self.date(fromMilliseconds: occurredAt)))
        }
        return activity
    }

    public func createConsistentBackup(at url: URL) throws {
        var destination: OpaquePointer?
        guard sqlite3_open_v2(url.path, &destination, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let destination else {
            defer { if let destination { sqlite3_close(destination) } }
            throw DatabaseError.sqlite(message: "Unable to create backup database at \(url.path).")
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", connection, "main") else {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(destination)))
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE else {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(destination)))
        }
        guard finishResult == SQLITE_OK else {
            throw DatabaseError.sqlite(message: String(cString: sqlite3_errmsg(destination)))
        }
        try Self.execute("PRAGMA foreign_keys = ON;", on: destination)
        guard Self.textResult("PRAGMA integrity_check;", on: destination) == "ok" else {
            throw DatabaseError.sqlite(message: "Backup integrity check failed.")
        }
    }

    public func checkpointWAL() throws {
        try Self.execute("PRAGMA wal_checkpoint(TRUNCATE);", on: connection)
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

    public func createImportBatch(storageRootID: StorageRootID, sourceDescription: String) throws -> ImportBatch {
        let id = ImportBatchID(); let now = Date()
        try transaction {
            let root = try Self.prepare("SELECT status FROM storage_root WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(root) }; try Self.bind(storageRootID.description, at: 1, to: root)
            guard sqlite3_step(root) == SQLITE_ROW else { throw DatabaseError.notFound("Storage root") }
            guard Self.text(at: 0, from: root) == StorageRootStatus.available.rawValue else { throw DatabaseError.invalidOperation("The selected storage root is not available.") }
            let statement = try Self.prepare("INSERT INTO import_batch (id, kind, status, source_description, started_at, storage_root_id) VALUES (?, 'scan', ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(id.description, at: 1, to: statement); try Self.bind(ImportBatchStatus.scanning.rawValue, at: 2, to: statement); try Self.bind(sourceDescription, at: 3, to: statement); try Self.bind(Self.milliseconds(now), at: 4, to: statement); try Self.bind(storageRootID.description, at: 5, to: statement); try Self.stepDone(statement, connection: connection)
        }
        return .init(id: id, storageRootID: storageRootID, status: .scanning, sourceDescription: sourceDescription, startedAt: now, completedAt: nil, processedCount: 0, candidateCount: 0, errorCount: 0, errorSummary: nil)
    }

    public func importBatches() throws -> [ImportBatch] {
        let statement = try Self.prepare("SELECT id, storage_root_id, status, source_description, started_at, completed_at, processed_count, candidate_count, error_count, error_summary FROM import_batch WHERE kind = 'scan' ORDER BY started_at DESC;", on: connection)
        defer { sqlite3_finalize(statement) }; var values: [ImportBatch] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: rawID), let rawStatus = Self.text(at: 2, from: statement), let status = ImportBatchStatus(rawValue: rawStatus) else { throw DatabaseError.invalidIdentifier("import_batch") }
            let rootID = Self.text(at: 1, from: statement).flatMap(UUID.init(uuidString:)).map(StorageRootID.init(rawValue:))
            values.append(.init(id: .init(rawValue: uuid), storageRootID: rootID, status: status, sourceDescription: Self.text(at: 3, from: statement), startedAt: Self.date(fromMilliseconds: Self.int(at: 4, from: statement) ?? 0), completedAt: Self.int(at: 5, from: statement).map(Self.date(fromMilliseconds:)), processedCount: Int(Self.int(at: 6, from: statement) ?? 0), candidateCount: Int(Self.int(at: 7, from: statement) ?? 0), errorCount: Int(Self.int(at: 8, from: statement) ?? 0), errorSummary: Self.text(at: 9, from: statement)))
        }
        return values
    }

    public func importCandidates(batchID: ImportBatchID) throws -> [ImportCandidate] {
        let statement = try Self.prepare("SELECT id, status, proposed_payload, error_message, metadata_payload, proposal_id FROM import_candidate WHERE batch_id = ? ORDER BY rowid;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(batchID.description, at: 1, to: statement); var values: [ImportCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: rawID), let rawStatus = Self.text(at: 1, from: statement), let status = ImportCandidateStatus(rawValue: rawStatus) else { throw DatabaseError.invalidIdentifier("import_candidate") }
            let payload = Self.data(at: 2, from: statement).flatMap { try? JSONDecoder().decode(ImportCandidatePayload.self, from: $0) }
            let metadata = Self.data(at: 4, from: statement).flatMap { try? JSONDecoder().decode(EmbeddedMetadataPayload.self, from: $0) }
            values.append(.init(id: .init(rawValue: uuid), batchID: batchID, status: status, payload: payload, errorMessage: Self.text(at: 3, from: statement), metadata: metadata, proposalID: Self.text(at: 5, from: statement).flatMap(UUID.init(uuidString:))))
        }
        return values
    }

    public func recordImportCandidate(batchID: ImportBatchID, payload: ImportCandidatePayload) throws {
        let data = try JSONEncoder().encode(payload); let id = ImportCandidateID()
        try transaction {
            let statement = try Self.prepare("INSERT INTO import_candidate (id, batch_id, status, proposed_payload) VALUES (?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(id.description, at: 1, to: statement); try Self.bind(batchID.description, at: 2, to: statement); try Self.bind(ImportCandidateStatus.pending.rawValue, at: 3, to: statement); try Self.bind(data, at: 4, to: statement); try Self.stepDone(statement, connection: connection)
            try incrementImportProgress(batchID: batchID, candidates: 1, errors: 0)
        }
    }

    public func recordImportError(batchID: ImportBatchID, message: String) throws {
        let id = ImportCandidateID()
        try transaction {
            let statement = try Self.prepare("INSERT INTO import_candidate (id, batch_id, status, proposed_payload, error_message) VALUES (?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(id.description, at: 1, to: statement); try Self.bind(batchID.description, at: 2, to: statement); try Self.bind(ImportCandidateStatus.failed.rawValue, at: 3, to: statement); try Self.bind(Data(), at: 4, to: statement); try Self.bind(message, at: 5, to: statement); try Self.stepDone(statement, connection: connection)
            try incrementImportProgress(batchID: batchID, candidates: 0, errors: 1)
        }
    }

    public func saveEmbeddedMetadata(_ metadata: EmbeddedMetadataPayload, for candidateID: ImportCandidateID) throws {
        let data = try JSONEncoder().encode(metadata)
        try transaction {
            let statement = try Self.prepare("UPDATE import_candidate SET status = 'proposed', metadata_payload = ?, error_message = NULL WHERE id = ? AND status IN ('pending', 'proposed');", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(data, at: 1, to: statement); try Self.bind(candidateID.description, at: 2, to: statement); try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Import candidate") }
        }
    }

    public func importReleaseProposals(batchID: ImportBatchID) throws -> [ImportReleaseProposal] {
        let statement = try Self.prepare("SELECT id, title, artist, disc_count, track_count, confidence, provenance, status, created_album_id, country_code, catalogue_number FROM import_release_proposal WHERE batch_id = ? ORDER BY title COLLATE NOCASE;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(batchID.description, at: 1, to: statement); var values: [ImportReleaseProposal] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let id = UUID(uuidString: rawID), let rawStatus = Self.text(at: 7, from: statement), let status = ImportProposalStatus(rawValue: rawStatus) else { throw DatabaseError.invalidIdentifier("import_release_proposal") }
            values.append(.init(id: id, batchID: batchID, title: Self.text(at: 1, from: statement) ?? "", artist: Self.text(at: 2, from: statement), discCount: Int(Self.int(at: 3, from: statement) ?? 1), trackCount: Int(Self.int(at: 4, from: statement) ?? 0), confidence: sqlite3_column_double(statement, 5), provenance: Self.text(at: 6, from: statement) ?? "", status: status, createdAlbumID: Self.text(at: 8, from: statement).flatMap(UUID.init(uuidString:)).map(AlbumID.init(rawValue:)), countryCode: Self.text(at: 9, from: statement), catalogueNumber: Self.text(at: 10, from: statement)))
        }
        return values
    }

    public func rebuildImportReleaseProposals(batchID: ImportBatchID, drafts: [ImportReleaseProposalDraft]) throws {
        try transaction {
            let clear = try Self.prepare("UPDATE import_candidate SET proposal_id = NULL WHERE batch_id = ?;", on: connection)
            defer { sqlite3_finalize(clear) }; try Self.bind(batchID.description, at: 1, to: clear); try Self.stepDone(clear, connection: connection)
            let delete = try Self.prepare("DELETE FROM import_release_proposal WHERE batch_id = ?;", on: connection)
            defer { sqlite3_finalize(delete) }; try Self.bind(batchID.description, at: 1, to: delete); try Self.stepDone(delete, connection: connection)
            let now = Self.milliseconds(Date())
            for draft in drafts {
                let proposalID = UUID()
                let insert = try Self.prepare("INSERT INTO import_release_proposal (id, batch_id, title, artist, disc_count, track_count, confidence, provenance, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'proposed', ?, ?);", on: connection)
                defer { sqlite3_finalize(insert) }; try Self.bind(proposalID.uuidString.lowercased(), at: 1, to: insert); try Self.bind(batchID.description, at: 2, to: insert); try Self.bind(draft.title, at: 3, to: insert); try Self.bind(draft.artist, at: 4, to: insert); try Self.bind(Int64(draft.discCount), at: 5, to: insert); try Self.bind(Int64(draft.candidateIDs.count), at: 6, to: insert); try Self.bind(draft.confidence, at: 7, to: insert); try Self.bind(draft.provenance, at: 8, to: insert); try Self.bind(now, at: 9, to: insert); try Self.bind(now, at: 10, to: insert); try Self.stepDone(insert, connection: connection)
                for candidateID in draft.candidateIDs {
                    let attach = try Self.prepare("UPDATE import_candidate SET proposal_id = ? WHERE id = ? AND batch_id = ?;", on: connection)
                    defer { sqlite3_finalize(attach) }; try Self.bind(proposalID.uuidString.lowercased(), at: 1, to: attach); try Self.bind(candidateID.description, at: 2, to: attach); try Self.bind(batchID.description, at: 3, to: attach); try Self.stepDone(attach, connection: connection)
                }
            }
        }
    }

    public func updateImportReleaseProposal(_ id: UUID, status: ImportProposalStatus) throws {
        try transaction {
            let statement = try Self.prepare("UPDATE import_release_proposal SET status = ?, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(status.rawValue, at: 1, to: statement); try Self.bind(Self.milliseconds(Date()), at: 2, to: statement); try Self.bind(id.uuidString.lowercased(), at: 3, to: statement); try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Import release proposal") }
        }
    }

    public func saveExternalMetadataSelection(importProposalID: UUID, provider: String, externalID: String, title: String, artist: String?, discCount: Int, countryCode: String? = nil, catalogueNumber: String? = nil) throws {
        let now = Self.milliseconds(Date())
        try transaction {
            guard try Self.exists("SELECT 1 FROM import_release_proposal WHERE id = ?;", value: importProposalID.uuidString.lowercased(), on: connection) else { throw DatabaseError.notFound("Import release proposal") }
            let statement = try Self.prepare("INSERT INTO external_metadata_selection (id, import_proposal_id, provider, external_id, title, artist, disc_count, country_code, catalogue_number, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(import_proposal_id) DO UPDATE SET provider = excluded.provider, external_id = excluded.external_id, title = excluded.title, artist = excluded.artist, disc_count = excluded.disc_count, country_code = excluded.country_code, catalogue_number = excluded.catalogue_number, updated_at = excluded.updated_at;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(UUID().uuidString.lowercased(), at: 1, to: statement); try Self.bind(importProposalID.uuidString.lowercased(), at: 2, to: statement); try Self.bind(provider, at: 3, to: statement); try Self.bind(externalID, at: 4, to: statement); try Self.bind(title, at: 5, to: statement); try Self.bind(artist, at: 6, to: statement); try Self.bind(Int64(max(1, discCount)), at: 7, to: statement); try Self.bind(countryCode, at: 8, to: statement); try Self.bind(catalogueNumber, at: 9, to: statement); try Self.bind(now, at: 10, to: statement); try Self.bind(now, at: 11, to: statement); try Self.stepDone(statement, connection: connection)
        }
    }

    public func externalMetadataSelection(importProposalID: UUID) throws -> ExternalMetadataSelection? {
        let statement = try Self.prepare("SELECT id, provider, external_id, title, artist, disc_count, country_code, catalogue_number FROM external_metadata_selection WHERE import_proposal_id = ?;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(importProposalID.uuidString.lowercased(), at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW, let rawID = Self.text(at: 0, from: statement), let id = UUID(uuidString: rawID) else { return nil }
        return .init(id: id, importProposalID: importProposalID, provider: Self.text(at: 1, from: statement) ?? "", externalID: Self.text(at: 2, from: statement) ?? "", title: Self.text(at: 3, from: statement) ?? "", artist: Self.text(at: 4, from: statement), discCount: Int(Self.int(at: 5, from: statement) ?? 1), countryCode: Self.text(at: 6, from: statement), catalogueNumber: Self.text(at: 7, from: statement))
    }

    public func applyExternalMetadataSelection(_ selection: ExternalMetadataSelection, fields: ExternalMetadataFieldSelection) throws {
        try transaction {
            let existing = try Self.prepare("SELECT title, artist, disc_count, country_code, catalogue_number FROM import_release_proposal WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(existing) }; try Self.bind(selection.importProposalID.uuidString.lowercased(), at: 1, to: existing)
            guard sqlite3_step(existing) == SQLITE_ROW else { throw DatabaseError.notFound("Import release proposal") }
            let title = fields.title ? selection.title : (Self.text(at: 0, from: existing) ?? "")
            let artist = fields.artist ? selection.artist : Self.text(at: 1, from: existing)
            let discs = fields.discCount ? selection.discCount : Int(Self.int(at: 2, from: existing) ?? 1)
            let country = fields.countryCode ? selection.countryCode : Self.text(at: 3, from: existing)
            let catalogue = fields.catalogueNumber ? selection.catalogueNumber : Self.text(at: 4, from: existing)
            let update = try Self.prepare("UPDATE import_release_proposal SET title = ?, artist = ?, disc_count = ?, country_code = ?, catalogue_number = ?, provenance = provenance || ', ' || ?, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(update) }; try Self.bind(title, at: 1, to: update); try Self.bind(artist, at: 2, to: update); try Self.bind(Int64(discs), at: 3, to: update); try Self.bind(country, at: 4, to: update); try Self.bind(catalogue, at: 5, to: update); try Self.bind(selection.provider, at: 6, to: update); try Self.bind(Self.milliseconds(Date()), at: 7, to: update); try Self.bind(selection.importProposalID.uuidString.lowercased(), at: 8, to: update); try Self.stepDone(update, connection: connection)
        }
    }

    public func confirmImportReleaseProposal(_ proposalID: UUID) throws -> AlbumID {
        var result: AlbumID?
        try transaction {
            let proposal = try Self.prepare("SELECT proposal.batch_id, proposal.title, proposal.disc_count, proposal.status, proposal.created_album_id, batch.storage_root_id, proposal.country_code, proposal.catalogue_number FROM import_release_proposal proposal JOIN import_batch batch ON batch.id = proposal.batch_id WHERE proposal.id = ?;", on: connection)
            defer { sqlite3_finalize(proposal) }; try Self.bind(proposalID.uuidString.lowercased(), at: 1, to: proposal)
            guard sqlite3_step(proposal) == SQLITE_ROW, let rawBatch = Self.text(at: 0, from: proposal), let batchUUID = UUID(uuidString: rawBatch), let title = Self.text(at: 1, from: proposal), let rawStatus = Self.text(at: 3, from: proposal) else { throw DatabaseError.notFound("Import release proposal") }
            if let rawAlbum = Self.text(at: 4, from: proposal), let albumUUID = UUID(uuidString: rawAlbum) { result = .init(rawValue: albumUUID); return }
            guard rawStatus == ImportProposalStatus.approved.rawValue else { throw DatabaseError.invalidOperation("Approve the proposal before creating catalogue records.") }
            guard let rawRoot = Self.text(at: 5, from: proposal), let rootUUID = UUID(uuidString: rawRoot) else { throw DatabaseError.notFound("Storage root") }
            let batchID = ImportBatchID(rawValue: batchUUID); let rootID = StorageRootID(rawValue: rootUUID); let albumID = AlbumID(); let now = Self.milliseconds(Date())
            let album = try Self.prepare("INSERT INTO album (id, title, country_code, catalogue_number, disc_count, has_cd, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 0, ?, ?);", on: connection)
            defer { sqlite3_finalize(album) }; try Self.bind(albumID.description, at: 1, to: album); try Self.bind(title, at: 2, to: album); try Self.bind(Self.text(at: 6, from: proposal), at: 3, to: album); try Self.bind(Self.text(at: 7, from: proposal), at: 4, to: album); try Self.bind(Self.int(at: 2, from: proposal) ?? 1, at: 5, to: album); try Self.bind(now, at: 6, to: album); try Self.bind(now, at: 7, to: album); try Self.stepDone(album, connection: connection)
            let candidates = try Self.prepare("SELECT id, proposed_payload, metadata_payload FROM import_candidate WHERE batch_id = ? AND proposal_id = ? ORDER BY rowid;", on: connection)
            defer { sqlite3_finalize(candidates) }; try Self.bind(batchID.description, at: 1, to: candidates); try Self.bind(proposalID.uuidString.lowercased(), at: 2, to: candidates)
            var discs: [Int: DiscID] = [:]
            while sqlite3_step(candidates) == SQLITE_ROW {
                guard let payloadData = Self.data(at: 1, from: candidates), let payload = try? JSONDecoder().decode(ImportCandidatePayload.self, from: payloadData), let metadataData = Self.data(at: 2, from: candidates), let metadata = try? JSONDecoder().decode(EmbeddedMetadataPayload.self, from: metadataData) else { continue }
                let discNumber = max(1, metadata.discNumber ?? 1)
                let discID: DiscID
                if let existing = discs[discNumber] { discID = existing }
                else {
                    discID = DiscID(); discs[discNumber] = discID
                    let insertDisc = try Self.prepare("INSERT INTO disc (id, album_id, number) VALUES (?, ?, ?);", on: connection)
                    defer { sqlite3_finalize(insertDisc) }; try Self.bind(discID.description, at: 1, to: insertDisc); try Self.bind(albumID.description, at: 2, to: insertDisc); try Self.bind(Int64(discNumber), at: 3, to: insertDisc); try Self.stepDone(insertDisc, connection: connection)
                }
                let trackID = TrackID()
                let trackNumber: Int
                if let explicitNumber = metadata.trackNumber { trackNumber = explicitNumber }
                else { trackNumber = try Self.nextNumber("SELECT COALESCE(MAX(number), 0) + 1 FROM track WHERE disc_id = ?;", ownerID: discID.description, on: connection) }
                let insertTrack = try Self.prepare("INSERT INTO track (id, disc_id, number, title, duration_ms) VALUES (?, ?, ?, ?, ?);", on: connection)
                defer { sqlite3_finalize(insertTrack) }; try Self.bind(trackID.description, at: 1, to: insertTrack); try Self.bind(discID.description, at: 2, to: insertTrack); try Self.bind(Int64(trackNumber), at: 3, to: insertTrack); try Self.bind(metadata.title ?? payload.fileName, at: 4, to: insertTrack); try Self.bind(metadata.durationMilliseconds.map(Int64.init), at: 5, to: insertTrack); try Self.stepDone(insertTrack, connection: connection)
                let rootStatus = try Self.prepare("SELECT status FROM storage_root WHERE id = ?;", on: connection)
                defer { sqlite3_finalize(rootStatus) }; try Self.bind(rootID.description, at: 1, to: rootStatus); guard sqlite3_step(rootStatus) == SQLITE_ROW else { throw DatabaseError.notFound("Storage root") }
                let availability = Self.text(at: 0, from: rootStatus) == StorageRootStatus.available.rawValue ? DigitalAssetAvailability.available.rawValue : DigitalAssetAvailability.rootOffline.rawValue
                let asset = try Self.prepare("INSERT INTO digital_asset (id, track_id, storage_root_id, relative_path, file_size, modified_at, duration_ms, origin, availability) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);", on: connection)
                defer { sqlite3_finalize(asset) }; try Self.bind(DigitalAssetID().description, at: 1, to: asset); try Self.bind(trackID.description, at: 2, to: asset); try Self.bind(rootID.description, at: 3, to: asset); try Self.bind(payload.relativePath, at: 4, to: asset); try Self.bind(payload.fileSize, at: 5, to: asset); try Self.bind(payload.modifiedAt.map(Self.milliseconds), at: 6, to: asset); try Self.bind(metadata.durationMilliseconds.map(Int64.init), at: 7, to: asset); try Self.bind(metadata.provenance, at: 8, to: asset); try Self.bind(availability, at: 9, to: asset); try Self.stepDone(asset, connection: connection)
            }
            guard !discs.isEmpty else { throw DatabaseError.invalidOperation("The proposal has no readable metadata candidates.") }
            let confirm = try Self.prepare("UPDATE import_release_proposal SET created_album_id = ?, confirmed_at = ?, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(confirm) }; try Self.bind(albumID.description, at: 1, to: confirm); try Self.bind(now, at: 2, to: confirm); try Self.bind(now, at: 3, to: confirm); try Self.bind(proposalID.uuidString.lowercased(), at: 4, to: confirm); try Self.stepDone(confirm, connection: connection)
            try incrementRevision(); result = albumID
        }
        guard let result else { throw DatabaseError.notFound("Import release proposal") }
        return result
    }

    public func libraryHealthIssues() throws -> [LibraryHealthIssue] {
        let statement = try Self.prepare("SELECT album.id, album.title, track.id, digital_asset.availability, storage_root.status FROM album JOIN disc ON disc.album_id = album.id JOIN track ON track.disc_id = disc.id LEFT JOIN digital_asset ON digital_asset.track_id = track.id LEFT JOIN storage_root ON storage_root.id = digital_asset.storage_root_id WHERE album.deleted_at IS NULL ORDER BY album.title;", on: connection)
        defer { sqlite3_finalize(statement) }
        struct HealthRow { var title: String; var assets: [TrackID: [DigitalAssetAvailability]] }
        var albums: [AlbumID: HealthRow] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawAlbum = Self.text(at: 0, from: statement), let albumUUID = UUID(uuidString: rawAlbum), let rawTrack = Self.text(at: 2, from: statement), let trackUUID = UUID(uuidString: rawTrack) else { throw DatabaseError.invalidIdentifier("Library health") }
            let albumID = AlbumID(rawValue: albumUUID); let trackID = TrackID(rawValue: trackUUID)
            var row = albums[albumID] ?? .init(title: Self.text(at: 1, from: statement) ?? "", assets: [:])
            if let rawAvailability = Self.text(at: 3, from: statement), let stored = DigitalAssetAvailability(rawValue: rawAvailability) {
                let rootOffline = Self.text(at: 4, from: statement).flatMap(StorageRootStatus.init(rawValue:)) != .available
                row.assets[trackID, default: []].append(rootOffline ? .rootOffline : stored)
            } else { row.assets[trackID, default: []] = [] }
            albums[albumID] = row
        }
        var issues: [LibraryHealthIssue] = []
        for (albumID, row) in albums {
            let summary = DigitalAvailabilitySummary.derive(expectedTrackCount: row.assets.count, assetsByTrack: Array(row.assets.values))
            switch summary.status {
            case .broken: issues.append(.init(kind: .missing, albumID: albumID, albumTitle: row.title, detail: "One or more tracks have no usable file."))
            case .offline: issues.append(.init(kind: .offline, albumID: albumID, albumTitle: row.title, detail: "The storage root is currently offline."))
            case .partial: issues.append(.init(kind: .partial, albumID: albumID, albumTitle: row.title, detail: "\(summary.availableTrackCount) of \(summary.expectedTrackCount) tracks are available."))
            default: break
            }
        }
        return issues.sorted { $0.albumTitle.localizedCaseInsensitiveCompare($1.albumTitle) == .orderedAscending }
    }

    public func playbackAsset(trackID: TrackID) throws -> PlaybackAssetReference? {
        let statement = try Self.prepare("SELECT track.title, digital_asset.storage_root_id, digital_asset.relative_path, digital_asset.availability FROM track JOIN digital_asset ON digital_asset.track_id = track.id WHERE track.id = ? ORDER BY digital_asset.id LIMIT 1;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(trackID.description, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let rawRoot = Self.text(at: 1, from: statement), let rootUUID = UUID(uuidString: rawRoot), let rawAvailability = Self.text(at: 3, from: statement), let availability = DigitalAssetAvailability(rawValue: rawAvailability) else { throw DatabaseError.invalidIdentifier("Playback asset") }
        return .init(trackID: trackID, title: Self.text(at: 0, from: statement) ?? "", storageRootID: .init(rawValue: rootUUID), relativePath: Self.text(at: 2, from: statement) ?? "", availability: availability)
    }

    public func softDeleteAlbum(_ id: AlbumID) throws {
        try transaction { let statement = try Self.prepare("UPDATE album SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL;", on: connection); defer { sqlite3_finalize(statement) }; let now = Self.milliseconds(Date()); try Self.bind(now, at: 1, to: statement); try Self.bind(now, at: 2, to: statement); try Self.bind(id.description, at: 3, to: statement); try Self.stepDone(statement, connection: connection); guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Album") }; try incrementRevision() }
    }
    public func restoreAlbum(_ id: AlbumID) throws {
        try transaction { let statement = try Self.prepare("UPDATE album SET deleted_at = NULL, updated_at = ? WHERE id = ? AND deleted_at IS NOT NULL;", on: connection); defer { sqlite3_finalize(statement) }; try Self.bind(Self.milliseconds(Date()), at: 1, to: statement); try Self.bind(id.description, at: 2, to: statement); try Self.stepDone(statement, connection: connection); guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Deleted album") }; try incrementRevision() }
    }
    public func deletedAlbums() throws -> [Album] {
        let statement = try Self.prepare(Self.albumSelect + " WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC;", on: connection)
        defer { sqlite3_finalize(statement) }
        var values: [Album] = []
        while sqlite3_step(statement) == SQLITE_ROW { values.append(try Self.album(from: statement)) }
        return values
    }
    public func catalogueExportJSON() throws -> String {
        let albums = try self.albums()
        let digitalAlbumIDs = try albumIDsWithDigitalAssets()
        let rows: [[String: Any]] = try albums.map {
            var row: [String: Any] = [
                "id": $0.id.description,
                "title": $0.title,
                "hasCD": $0.hasCD,
                "hasDigital": digitalAlbumIDs.contains($0.id.description)
            ]
            if let editionLabel = $0.editionLabel, !editionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { row["editionLabel"] = editionLabel }
            if let releaseYear = $0.releaseYear { row["releaseYear"] = releaseYear }
            if let catalogueNumber = $0.catalogueNumber, !catalogueNumber.isEmpty { row["catalogueNumber"] = catalogueNumber }
            if let rating = $0.rating { row["rating"] = rating }
            row["discs"] = try snapshotDiscRows(albumID: $0.id)
            return row
        }
        let data = try JSONSerialization.data(withJSONObject: ["format": "music-library-json", "schemaVersion": try schemaVersion(), "catalogueRevision": try currentRevision(), "albums": rows], options: [.prettyPrinted, .sortedKeys]); return String(decoding: data, as: UTF8.self)
    }
    public func catalogueExportCSV() throws -> String {
        let header = ["id", "title", "edition_label", "release_year", "country_code", "catalogue_number", "has_cd", "digital_availability"]
        let digital = try albumIDsWithDigitalAssets()
        let rows = try albums().map { album in
            [album.id.description, album.title, album.editionLabel ?? "", album.releaseYear.map(String.init) ?? "", album.countryCode ?? "", album.catalogueNumber ?? "", album.hasCD ? "true" : "false", digital.contains(album.id.description) ? "available" : "none"]
                .map(Self.csvValue).joined(separator: ",")
        }
        return ([header.map(Self.csvValue).joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
    }
    public func publicationRevisionAndJSON() throws -> (Int64, String) { (try currentRevision(), try catalogueExportJSON()) }

    private func albumIDsWithDigitalAssets() throws -> Set<String> {
        let statement = try Self.prepare("SELECT DISTINCT disc.album_id FROM digital_asset JOIN track ON track.id = digital_asset.track_id JOIN disc ON disc.id = track.disc_id;", on: connection)
        defer { sqlite3_finalize(statement) }
        var values = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = Self.text(at: 0, from: statement) { values.insert(id) }
        }
        return values
    }

    private func snapshotDiscRows(albumID: AlbumID) throws -> [[String: Any]] {
        try discs(albumID: albumID).map { disc in
            var row: [String: Any] = ["id": disc.id.description, "number": disc.number, "tracks": try snapshotTrackRows(discID: disc.id)]
            if let title = disc.title, !title.isEmpty { row["title"] = title }
            return row
        }
    }

    private func snapshotTrackRows(discID: DiscID) throws -> [[String: Any]] {
        try tracks(discID: discID).map { track in
            var row: [String: Any] = ["id": track.id.description, "number": track.number, "title": track.title, "assets": try snapshotAssetRows(trackID: track.id)]
            if let durationMilliseconds = track.durationMilliseconds { row["durationMilliseconds"] = durationMilliseconds }
            if let rating = track.rating { row["rating"] = rating }
            return row
        }
    }

    private func snapshotAssetRows(trackID: TrackID) throws -> [[String: Any]] {
        let statement = try Self.prepare("SELECT digital_asset.storage_root_id, digital_asset.relative_path, digital_asset.availability, storage_root.status FROM digital_asset JOIN storage_root ON storage_root.id = digital_asset.storage_root_id WHERE digital_asset.track_id = ? ORDER BY digital_asset.id;", on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(trackID.description, at: 1, to: statement)
        var rows: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rootID = Self.text(at: 0, from: statement), let relativePath = Self.text(at: 1, from: statement) else { continue }
            let stored = Self.text(at: 2, from: statement) ?? "invalid"
            let rootOffline = Self.text(at: 3, from: statement) != StorageRootStatus.available.rawValue
            rows.append(["storageRootID": rootID, "relativePath": relativePath, "availability": rootOffline ? DigitalAssetAvailability.rootOffline.rawValue : stored])
        }
        return rows
    }

    public func recordAssetFingerprint(_ assetID: DigitalAssetID, contentHash: String, quickSignature: String) throws {
        try transaction { let statement = try Self.prepare("UPDATE digital_asset SET content_hash = ?, quick_signature = ? WHERE id = ?;", on: connection); defer { sqlite3_finalize(statement) }; try Self.bind(contentHash, at: 1, to: statement); try Self.bind(quickSignature, at: 2, to: statement); try Self.bind(assetID.description, at: 3, to: statement); try Self.stepDone(statement, connection: connection); guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Digital asset") } }
    }
    public func updateAssetAvailability(_ assetID: DigitalAssetID, to availability: DigitalAssetAvailability) throws {
        let statement = try Self.prepare("UPDATE digital_asset SET availability = ? WHERE id = ?;", on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(availability.rawValue, at: 1, to: statement)
        try Self.bind(assetID.description, at: 2, to: statement)
        try Self.stepDone(statement, connection: connection)
        guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Digital asset") }
    }
    public func duplicateAssets() throws -> [AssetDuplicate] {
        let statement = try Self.prepare("SELECT content_hash, group_concat(relative_path, '|') FROM digital_asset WHERE content_hash IS NOT NULL GROUP BY content_hash HAVING COUNT(*) > 1;", on: connection); defer { sqlite3_finalize(statement) }; var values: [AssetDuplicate] = []
        while sqlite3_step(statement) == SQLITE_ROW { guard let hash = Self.text(at: 0, from: statement) else { continue }; values.append(.init(contentHash: hash, paths: (Self.text(at: 1, from: statement) ?? "").split(separator: "|").map(String.init))) }
        return values
    }
    public func proposeRelink(assetID: DigitalAssetID, proposedRelativePath: String) throws -> AssetRelinkProposal {
        let id = UUID(); var current = ""
        try transaction { let source = try Self.prepare("SELECT relative_path FROM digital_asset WHERE id = ?;", on: connection); defer { sqlite3_finalize(source) }; try Self.bind(assetID.description, at: 1, to: source); guard sqlite3_step(source) == SQLITE_ROW else { throw DatabaseError.notFound("Digital asset") }; current = Self.text(at: 0, from: source) ?? ""; let statement = try Self.prepare("INSERT OR IGNORE INTO asset_relink_proposal (id, asset_id, proposed_relative_path, created_at) VALUES (?, ?, ?, ?);", on: connection); defer { sqlite3_finalize(statement) }; try Self.bind(id.uuidString.lowercased(), at: 1, to: statement); try Self.bind(assetID.description, at: 2, to: statement); try Self.bind(proposedRelativePath, at: 3, to: statement); try Self.bind(Self.milliseconds(Date()), at: 4, to: statement); try Self.stepDone(statement, connection: connection) }
        return .init(id: id, assetID: assetID, currentPath: current, proposedPath: proposedRelativePath)
    }
    public func relinkProposals() throws -> [AssetRelinkProposal] {
        let statement = try Self.prepare("SELECT asset_relink_proposal.id, asset_relink_proposal.asset_id, digital_asset.relative_path, asset_relink_proposal.proposed_relative_path FROM asset_relink_proposal JOIN digital_asset ON digital_asset.id = asset_relink_proposal.asset_id ORDER BY asset_relink_proposal.created_at DESC;", on: connection)
        defer { sqlite3_finalize(statement) }
        var values: [AssetRelinkProposal] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let id = UUID(uuidString: rawID), let rawAsset = Self.text(at: 1, from: statement), let asset = UUID(uuidString: rawAsset) else { continue }
            values.append(.init(id: id, assetID: .init(rawValue: asset), currentPath: Self.text(at: 2, from: statement) ?? "", proposedPath: Self.text(at: 3, from: statement) ?? ""))
        }
        return values
    }
    public func applyRelinkProposal(_ id: UUID) throws {
        try transaction {
            let proposal = try Self.prepare("SELECT asset_id, proposed_relative_path FROM asset_relink_proposal WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(proposal) }
            try Self.bind(id.uuidString.lowercased(), at: 1, to: proposal)
            guard sqlite3_step(proposal) == SQLITE_ROW, let assetID = Self.text(at: 0, from: proposal), let path = Self.text(at: 1, from: proposal) else { throw DatabaseError.notFound("Relink proposal") }
            let update = try Self.prepare("UPDATE digital_asset SET relative_path = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(update) }
            try Self.bind(path, at: 1, to: update); try Self.bind(assetID, at: 2, to: update); try Self.stepDone(update, connection: connection)
            let delete = try Self.prepare("DELETE FROM asset_relink_proposal WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(delete) }
            try Self.bind(id.uuidString.lowercased(), at: 1, to: delete); try Self.stepDone(delete, connection: connection)
            try incrementRevision()
        }
    }
    public func discardRelinkProposal(_ id: UUID) throws {
        let statement = try Self.prepare("DELETE FROM asset_relink_proposal WHERE id = ?;", on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(id.uuidString.lowercased(), at: 1, to: statement)
        try Self.stepDone(statement, connection: connection)
        guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Relink proposal") }
    }
    public func digitalAssetIDs(albumID: AlbumID) throws -> [DigitalAssetID] {
        let statement = try Self.prepare("SELECT digital_asset.id FROM digital_asset JOIN track ON track.id = digital_asset.track_id JOIN disc ON disc.id = track.disc_id WHERE disc.album_id = ? ORDER BY digital_asset.id;", on: connection); defer { sqlite3_finalize(statement) }; try Self.bind(albumID.description, at: 1, to: statement); var values: [DigitalAssetID] = []
        while sqlite3_step(statement) == SQLITE_ROW { guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("digital_asset") }; values.append(.init(rawValue: uuid)) }
        return values
    }
    public func assetFingerprintCandidates() throws -> [AssetFingerprintCandidate] {
        let statement = try Self.prepare("SELECT id, storage_root_id, relative_path FROM digital_asset;", on: connection); defer { sqlite3_finalize(statement) }; var values: [AssetFingerprintCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW { guard let raw = Self.text(at: 0, from: statement), let id = UUID(uuidString: raw), let rawRoot = Self.text(at: 1, from: statement), let rootID = UUID(uuidString: rawRoot) else { throw DatabaseError.invalidIdentifier("digital_asset") }; values.append(.init(id: .init(rawValue: id), rootID: .init(rawValue: rootID), relativePath: Self.text(at: 2, from: statement) ?? "")) }; return values
    }

    public func createPlaylist(name: String) throws -> Playlist {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Playlist name") }
        let id = PlaylistID(); let now = Self.milliseconds(Date())
        try transaction { let statement = try Self.prepare("INSERT INTO playlist (id, name, created_at, updated_at) VALUES (?, ?, ?, ?);", on: connection); defer { sqlite3_finalize(statement) }; try Self.bind(id.description, at: 1, to: statement); try Self.bind(name, at: 2, to: statement); try Self.bind(now, at: 3, to: statement); try Self.bind(now, at: 4, to: statement); try Self.stepDone(statement, connection: connection); try incrementRevision() }
        return .init(id: id, name: name)
    }

    public func playlists() throws -> [Playlist] {
        let statement = try Self.prepare("SELECT id, name FROM playlist WHERE deleted_at IS NULL ORDER BY name COLLATE NOCASE;", on: connection); defer { sqlite3_finalize(statement) }; var values: [Playlist] = []
        while sqlite3_step(statement) == SQLITE_ROW { guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("playlist") }; values.append(.init(id: .init(rawValue: uuid), name: Self.text(at: 1, from: statement) ?? "")) }
        return values
    }

    public func deletedPlaylists() throws -> [Playlist] {
        let statement = try Self.prepare("SELECT id, name FROM playlist WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC;", on: connection); defer { sqlite3_finalize(statement) }; var values: [Playlist] = []
        while sqlite3_step(statement) == SQLITE_ROW { guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("playlist") }; values.append(.init(id: .init(rawValue: uuid), name: Self.text(at: 1, from: statement) ?? "")) }
        return values
    }

    public func renamePlaylist(_ id: PlaylistID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.requiredField("Playlist name") }
        try transaction {
            let statement = try Self.prepare("UPDATE playlist SET name = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(trimmed, at: 1, to: statement)
            try Self.bind(Self.milliseconds(Date()), at: 2, to: statement)
            try Self.bind(id.description, at: 3, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Playlist") }
            try incrementRevision()
        }
    }

    public func deletePlaylist(_ id: PlaylistID) throws {
        try transaction {
            let statement = try Self.prepare("UPDATE playlist SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL;", on: connection)
            defer { sqlite3_finalize(statement) }
            let now = Self.milliseconds(Date())
            try Self.bind(now, at: 1, to: statement)
            try Self.bind(now, at: 2, to: statement)
            try Self.bind(id.description, at: 3, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Playlist") }
            try incrementRevision()
        }
    }

    public func restorePlaylist(_ id: PlaylistID) throws {
        try transaction {
            let statement = try Self.prepare("UPDATE playlist SET deleted_at = NULL, updated_at = ? WHERE id = ? AND deleted_at IS NOT NULL;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(Self.milliseconds(Date()), at: 1, to: statement); try Self.bind(id.description, at: 2, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Deleted playlist") }
            try incrementRevision()
        }
    }

    public func addTrack(_ trackID: TrackID, to playlistID: PlaylistID) throws {
        try transaction { guard try Self.exists("SELECT 1 FROM playlist WHERE id = ? AND deleted_at IS NULL;", value: playlistID.description, on: connection) else { throw DatabaseError.notFound("Playlist") }; guard try Self.exists("SELECT 1 FROM track WHERE id = ?;", value: trackID.description, on: connection) else { throw DatabaseError.notFound("Track") }; let position = try Self.nextNumber("SELECT COALESCE(MAX(position), 0) + 1 FROM playlist_item WHERE playlist_id = ?;", ownerID: playlistID.description, on: connection); let statement = try Self.prepare("INSERT INTO playlist_item (id, playlist_id, track_id, position) VALUES (?, ?, ?, ?);", on: connection); defer { sqlite3_finalize(statement) }; try Self.bind(UUID().uuidString.lowercased(), at: 1, to: statement); try Self.bind(playlistID.description, at: 2, to: statement); try Self.bind(trackID.description, at: 3, to: statement); try Self.bind(Int64(position), at: 4, to: statement); try Self.stepDone(statement, connection: connection); try incrementRevision() }
    }

    public func removePlaylistItem(_ id: UUID) throws {
        try transaction {
            let source = try Self.prepare("SELECT playlist_id FROM playlist_item WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(source) }
            try Self.bind(id.uuidString.lowercased(), at: 1, to: source)
            guard sqlite3_step(source) == SQLITE_ROW, let rawPlaylist = Self.text(at: 0, from: source), let playlistUUID = UUID(uuidString: rawPlaylist) else { throw DatabaseError.notFound("Playlist item") }
            let statement = try Self.prepare("DELETE FROM playlist_item WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.uuidString.lowercased(), at: 1, to: statement)
            try Self.stepDone(statement, connection: connection)
            try renumberPlaylistItems(.init(rawValue: playlistUUID), orderedItemIDs: try playlistItemIDs(.init(rawValue: playlistUUID)))
            try incrementRevision()
        }
    }

    public func movePlaylistItem(_ id: UUID, to position: Int) throws {
        try transaction {
            let source = try Self.prepare("SELECT playlist_id FROM playlist_item WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(source) }
            try Self.bind(id.uuidString.lowercased(), at: 1, to: source)
            guard sqlite3_step(source) == SQLITE_ROW, let rawPlaylist = Self.text(at: 0, from: source), let playlistUUID = UUID(uuidString: rawPlaylist) else { throw DatabaseError.notFound("Playlist item") }
            let playlistID = PlaylistID(rawValue: playlistUUID)
            var ids = try playlistItemIDs(playlistID)
            guard let currentIndex = ids.firstIndex(of: id) else { throw DatabaseError.notFound("Playlist item") }
            ids.remove(at: currentIndex)
            ids.insert(id, at: min(max(0, position - 1), ids.count))
            try renumberPlaylistItems(playlistID, orderedItemIDs: ids)
            try incrementRevision()
        }
    }

    public func playlistItems(playlistID: PlaylistID) throws -> [PlaylistItem] {
        let statement = try Self.prepare("SELECT playlist_item.id, playlist_item.track_id, playlist_item.position, track.title FROM playlist_item JOIN track ON track.id = playlist_item.track_id WHERE playlist_item.playlist_id = ? ORDER BY playlist_item.position;", on: connection); defer { sqlite3_finalize(statement) }; try Self.bind(playlistID.description, at: 1, to: statement); var values: [PlaylistItem] = []
        while sqlite3_step(statement) == SQLITE_ROW { guard let raw = Self.text(at: 0, from: statement), let id = UUID(uuidString: raw), let rawTrack = Self.text(at: 1, from: statement), let trackUUID = UUID(uuidString: rawTrack) else { throw DatabaseError.invalidIdentifier("playlist_item") }; values.append(.init(id: id, playlistID: playlistID, trackID: .init(rawValue: trackUUID), position: Int(Self.int(at: 2, from: statement) ?? 0), title: Self.text(at: 3, from: statement) ?? "")) }
        return values
    }

    private func playlistItemIDs(_ playlistID: PlaylistID) throws -> [UUID] {
        let statement = try Self.prepare("SELECT id FROM playlist_item WHERE playlist_id = ? ORDER BY position;", on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(playlistID.description, at: 1, to: statement)
        var values: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let id = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("playlist_item") }
            values.append(id)
        }
        return values
    }

    private func renumberPlaylistItems(_ playlistID: PlaylistID, orderedItemIDs: [UUID]) throws {
        let offset = try Self.prepare("UPDATE playlist_item SET position = position + 1000000 WHERE playlist_id = ?;", on: connection)
        defer { sqlite3_finalize(offset) }
        try Self.bind(playlistID.description, at: 1, to: offset)
        try Self.stepDone(offset, connection: connection)
        let update = try Self.prepare("UPDATE playlist_item SET position = ? WHERE id = ? AND playlist_id = ?;", on: connection)
        defer { sqlite3_finalize(update) }
        for (index, id) in orderedItemIDs.enumerated() {
            sqlite3_reset(update)
            try Self.bind(Int64(index + 1), at: 1, to: update)
            try Self.bind(id.uuidString.lowercased(), at: 2, to: update)
            try Self.bind(playlistID.description, at: 3, to: update)
            try Self.stepDone(update, connection: connection)
        }
    }

    public func finishImportBatch(_ batchID: ImportBatchID, status: ImportBatchStatus, errorSummary: String? = nil) throws {
        guard status != .scanning else { throw DatabaseError.invalidOperation("A finished import batch must have a terminal status.") }
        try transaction {
            let statement = try Self.prepare("UPDATE import_batch SET status = ?, completed_at = ?, error_summary = ? WHERE id = ? AND status = 'scanning';", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(status.rawValue, at: 1, to: statement); try Self.bind(Self.milliseconds(Date()), at: 2, to: statement); try Self.bind(errorSummary, at: 3, to: statement); try Self.bind(batchID.description, at: 4, to: statement); try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Active import batch") }
        }
    }

    public func recoverInterruptedImportBatches() throws {
        try transaction {
            let statement = try Self.prepare("UPDATE import_batch SET status = 'cancelled', completed_at = ?, error_summary = COALESCE(error_summary, 'Scan interrupted by a previous app session.') WHERE kind = 'scan' AND status = 'scanning';", on: connection)
            defer { sqlite3_finalize(statement) }; try Self.bind(Self.milliseconds(Date()), at: 1, to: statement); try Self.stepDone(statement, connection: connection)
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
            query = Self.albumSelect + " WHERE deleted_at IS NULL AND (title LIKE ? COLLATE NOCASE OR edition_label LIKE ? COLLATE NOCASE OR catalogue_number LIKE ? COLLATE NOCASE OR barcode LIKE ? COLLATE NOCASE OR EXISTS (SELECT 1 FROM album_alias WHERE album_alias.album_id = album.id AND album_alias.name LIKE ? COLLATE NOCASE) OR EXISTS (SELECT 1 FROM disc JOIN track ON track.disc_id = disc.id WHERE disc.album_id = album.id AND track.title LIKE ? COLLATE NOCASE) OR EXISTS (SELECT 1 FROM album_contributor JOIN contributor ON contributor.id = album_contributor.contributor_id WHERE album_contributor.album_id = album.id AND contributor.name LIKE ? COLLATE NOCASE) OR EXISTS (SELECT 1 FROM disc JOIN track ON track.disc_id = disc.id JOIN track_contributor ON track_contributor.track_id = track.id JOIN contributor ON contributor.id = track_contributor.contributor_id WHERE disc.album_id = album.id AND contributor.name LIKE ? COLLATE NOCASE) OR EXISTS (SELECT 1 FROM box_set_album JOIN box_set ON box_set.id = box_set_album.box_set_id WHERE box_set_album.album_id = album.id AND box_set.title LIKE ? COLLATE NOCASE) OR EXISTS (SELECT 1 FROM physical_location WHERE physical_location.id = album.physical_location_id AND physical_location.name LIKE ? COLLATE NOCASE) OR EXISTS (SELECT 1 FROM box_set_album JOIN box_set ON box_set.id = box_set_album.box_set_id JOIN physical_location ON physical_location.id = box_set.physical_location_id WHERE box_set_album.album_id = album.id AND physical_location.name LIKE ? COLLATE NOCASE)) ORDER BY title COLLATE NOCASE, edition_label COLLATE NOCASE;"
        } else {
            query = Self.albumSelect + " WHERE deleted_at IS NULL ORDER BY title COLLATE NOCASE, edition_label COLLATE NOCASE;"
        }
        let statement = try Self.prepare(query, on: connection)
        defer { sqlite3_finalize(statement) }
        if let term, !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pattern = "%\(term)%"
            for index in 1...11 { try Self.bind(pattern, at: Int32(index), to: statement) }
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

    public func deletedBoxSets() throws -> [BoxSet] {
        let statement = try Self.prepare("SELECT id, title, edition_label, physical_location_id FROM box_set WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC;", on: connection)
        defer { sqlite3_finalize(statement) }
        var results: [BoxSet] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = Self.text(at: 0, from: statement), let id = UUID(uuidString: rawID), let rawLocationID = Self.text(at: 3, from: statement), let locationID = UUID(uuidString: rawLocationID) else { throw DatabaseError.invalidIdentifier("box_set") }
            results.append(.init(id: .init(rawValue: id), title: Self.text(at: 1, from: statement) ?? "", editionLabel: Self.text(at: 2, from: statement), physicalLocationID: .init(rawValue: locationID)))
        }
        return results
    }

    public func softDeleteEmptyBoxSet(_ id: BoxSetID) throws {
        try transaction {
            guard try Self.exists("SELECT 1 FROM box_set WHERE id = ? AND deleted_at IS NULL;", value: id.description, on: connection) else { throw DatabaseError.notFound("Box set") }
            guard !(try Self.exists("SELECT 1 FROM box_set_album WHERE box_set_id = ?;", value: id.description, on: connection)) else { throw DatabaseError.invalidOperation("Remove or relocate every album before moving a box set to Recently Deleted.") }
            let statement = try Self.prepare("UPDATE box_set SET deleted_at = ?, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            let now = Self.milliseconds(Date()); try Self.bind(now, at: 1, to: statement); try Self.bind(now, at: 2, to: statement); try Self.bind(id.description, at: 3, to: statement)
            try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
    }

    public func restoreBoxSet(_ id: BoxSetID) throws {
        try transaction {
            let statement = try Self.prepare("UPDATE box_set SET deleted_at = NULL, updated_at = ? WHERE id = ? AND deleted_at IS NOT NULL;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(Self.milliseconds(Date()), at: 1, to: statement); try Self.bind(id.description, at: 2, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Deleted box set") }
            try incrementRevision()
        }
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

    public func reorderDisc(_ discID: DiscID, in albumID: AlbumID, to targetNumber: Int) throws {
        try transaction {
            let existing = try Self.prepare("SELECT number FROM disc WHERE id = ? AND album_id = ?;", on: connection)
            defer { sqlite3_finalize(existing) }
            try Self.bind(discID.description, at: 1, to: existing)
            try Self.bind(albumID.description, at: 2, to: existing)
            guard sqlite3_step(existing) == SQLITE_ROW else { throw DatabaseError.notFound("Disc") }
            let currentNumber = Int(Self.int(at: 0, from: existing) ?? 0)
            let count = try Self.nextNumber("SELECT COALESCE(MAX(number), 0) FROM disc WHERE album_id = ?;", ownerID: albumID.description, on: connection)
            guard (1...count).contains(targetNumber) else { throw DatabaseError.invalidOperation("Disc position is outside this album.") }
            guard targetNumber != currentNumber else { return }

            let park = try Self.prepare("UPDATE disc SET number = -1 WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(park) }
            try Self.bind(discID.description, at: 1, to: park)
            try Self.stepDone(park, connection: connection)
            let offset: Int64 = 1_000_000
            let offsetOthers = try Self.prepare("UPDATE disc SET number = number + ? WHERE album_id = ? AND id != ?;", on: connection)
            defer { sqlite3_finalize(offsetOthers) }
            try Self.bind(offset, at: 1, to: offsetOthers); try Self.bind(albumID.description, at: 2, to: offsetOthers); try Self.bind(discID.description, at: 3, to: offsetOthers)
            try Self.stepDone(offsetOthers, connection: connection)
            if targetNumber < currentNumber {
                let shift = try Self.prepare("UPDATE disc SET number = CASE WHEN number >= ? AND number < ? THEN number - ? ELSE number - ? END WHERE album_id = ?;", on: connection)
                defer { sqlite3_finalize(shift) }
                try Self.bind(offset + Int64(targetNumber), at: 1, to: shift); try Self.bind(offset + Int64(currentNumber), at: 2, to: shift); try Self.bind(offset - 1, at: 3, to: shift); try Self.bind(offset, at: 4, to: shift); try Self.bind(albumID.description, at: 5, to: shift)
                try Self.stepDone(shift, connection: connection)
            } else {
                let shift = try Self.prepare("UPDATE disc SET number = CASE WHEN number > ? AND number <= ? THEN number - ? ELSE number - ? END WHERE album_id = ?;", on: connection)
                defer { sqlite3_finalize(shift) }
                try Self.bind(offset + Int64(currentNumber), at: 1, to: shift); try Self.bind(offset + Int64(targetNumber), at: 2, to: shift); try Self.bind(offset + 1, at: 3, to: shift); try Self.bind(offset, at: 4, to: shift); try Self.bind(albumID.description, at: 5, to: shift)
                try Self.stepDone(shift, connection: connection)
            }
            let place = try Self.prepare("UPDATE disc SET number = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(place) }
            try Self.bind(Int64(targetNumber), at: 1, to: place); try Self.bind(discID.description, at: 2, to: place)
            try Self.stepDone(place, connection: connection)
            try incrementRevision()
        }
    }

    public func deleteDisc(_ discID: DiscID) throws {
        try transaction {
            let existing = try Self.prepare("SELECT album_id, number FROM disc WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(existing) }
            try Self.bind(discID.description, at: 1, to: existing)
            guard sqlite3_step(existing) == SQLITE_ROW, let albumID = Self.text(at: 0, from: existing) else { throw DatabaseError.notFound("Disc") }
            let number = Self.int(at: 1, from: existing) ?? 0
            let delete = try Self.prepare("DELETE FROM disc WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(delete) }
            try Self.bind(discID.description, at: 1, to: delete)
            try Self.stepDone(delete, connection: connection)
            let reorder = try Self.prepare("UPDATE disc SET number = number - 1 WHERE album_id = ? AND number > ?;", on: connection)
            defer { sqlite3_finalize(reorder) }
            try Self.bind(albumID, at: 1, to: reorder); try Self.bind(number, at: 2, to: reorder)
            try Self.stepDone(reorder, connection: connection)
            try incrementRevision()
        }
    }

    public func createTrack(discID: DiscID, draft: NewTrack) throws -> Track {
        let valid = try draft.validated(); let id = TrackID(); var number = 0
        try transaction {
            guard try Self.exists("SELECT 1 FROM disc WHERE id = ?;", value: discID.description, on: connection) else { throw DatabaseError.notFound("Disc") }
            number = try Self.nextNumber("SELECT COALESCE(MAX(number), 0) + 1 FROM track WHERE disc_id = ?;", ownerID: discID.description, on: connection)
            let statement = try Self.prepare("INSERT INTO track (id, disc_id, number, display_position, title, duration_ms, work_name, movement_number, movement_name, is_instrumental, rating) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(id.description, at: 1, to: statement); try Self.bind(discID.description, at: 2, to: statement); try Self.bind(Int64(number), at: 3, to: statement); try Self.bind(valid.displayPosition, at: 4, to: statement); try Self.bind(valid.title, at: 5, to: statement); try Self.bind(valid.durationMilliseconds.map(Int64.init), at: 6, to: statement); try Self.bind(valid.workName, at: 7, to: statement); try Self.bind(valid.movementNumber.map(Int64.init), at: 8, to: statement); try Self.bind(valid.movementName, at: 9, to: statement); try Self.bind(valid.isInstrumental.map { Int64($0 ? 1 : 0) }, at: 10, to: statement); try Self.bind(valid.rating.map(Int64.init), at: 11, to: statement)
            try Self.stepDone(statement, connection: connection); try incrementRevision()
        }
        return .init(id: id, discID: discID, number: number, title: valid.title, displayPosition: valid.displayPosition, durationMilliseconds: valid.durationMilliseconds, workName: valid.workName, movementNumber: valid.movementNumber, movementName: valid.movementName, isInstrumental: valid.isInstrumental, rating: valid.rating)
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
            let statement = try Self.prepare("UPDATE track SET title = ?, display_position = ?, duration_ms = ?, work_name = ?, movement_number = ?, movement_name = ?, is_instrumental = ?, rating = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(valid.title, at: 1, to: statement); try Self.bind(valid.displayPosition, at: 2, to: statement); try Self.bind(valid.durationMilliseconds.map(Int64.init), at: 3, to: statement); try Self.bind(valid.workName, at: 4, to: statement); try Self.bind(valid.movementNumber.map(Int64.init), at: 5, to: statement); try Self.bind(valid.movementName, at: 6, to: statement); try Self.bind(valid.isInstrumental.map { Int64($0 ? 1 : 0) }, at: 7, to: statement); try Self.bind(valid.rating.map(Int64.init), at: 8, to: statement); try Self.bind(trackID.description, at: 9, to: statement); try Self.stepDone(statement, connection: connection)
            result = .init(id: trackID, discID: .init(rawValue: discUUID), number: Int(Self.int(at: 1, from: existing) ?? 0), title: valid.title, displayPosition: valid.displayPosition, durationMilliseconds: valid.durationMilliseconds, workName: valid.workName, movementNumber: valid.movementNumber, movementName: valid.movementName, isInstrumental: valid.isInstrumental, rating: valid.rating)
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
        let statement = try Self.prepare("SELECT id, number, title, display_position, duration_ms, work_name, movement_number, movement_name, is_instrumental, rating FROM track WHERE disc_id = ? ORDER BY number;", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(discID.description, at: 1, to: statement)
        var values: [Track] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("track.id") }
            let instrumental = Self.int(at: 8, from: statement).map { $0 == 1 }
            values.append(.init(id: .init(rawValue: uuid), discID: discID, number: Int(Self.int(at: 1, from: statement) ?? 0), title: Self.text(at: 2, from: statement) ?? "", displayPosition: Self.text(at: 3, from: statement), durationMilliseconds: Self.int(at: 4, from: statement).map(Int.init), workName: Self.text(at: 5, from: statement), movementNumber: Self.int(at: 6, from: statement).map(Int.init), movementName: Self.text(at: 7, from: statement), isInstrumental: instrumental, rating: Self.int(at: 9, from: statement).map(Int.init)))
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

    public func contributors() throws -> [Contributor] {
        let statement = try Self.prepare("SELECT id, name, sort_name FROM contributor ORDER BY COALESCE(sort_name, name) COLLATE NOCASE, name COLLATE NOCASE;", on: connection)
        defer { sqlite3_finalize(statement) }
        var values: [Contributor] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = Self.text(at: 0, from: statement), let uuid = UUID(uuidString: raw) else { throw DatabaseError.invalidIdentifier("contributor") }
            values.append(.init(id: .init(rawValue: uuid), name: Self.text(at: 1, from: statement) ?? "", sortName: Self.text(at: 2, from: statement)))
        }
        return values
    }

    public func albums(creditedTo contributorID: ContributorID) throws -> [Album] {
        let sql = Self.albumSelect + " WHERE deleted_at IS NULL AND (EXISTS (SELECT 1 FROM album_contributor WHERE album_contributor.album_id = album.id AND album_contributor.contributor_id = ?) OR EXISTS (SELECT 1 FROM disc JOIN track ON track.disc_id = disc.id JOIN track_contributor ON track_contributor.track_id = track.id WHERE disc.album_id = album.id AND track_contributor.contributor_id = ?)) ORDER BY title COLLATE NOCASE, edition_label COLLATE NOCASE;"
        let statement = try Self.prepare(sql, on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(contributorID.description, at: 1, to: statement); try Self.bind(contributorID.description, at: 2, to: statement)
        var values: [Album] = []
        while sqlite3_step(statement) == SQLITE_ROW { values.append(try Self.album(from: statement)) }
        return values
    }

    public func updateContributor(_ contributorID: ContributorID, with draft: NewContributor) throws -> Contributor {
        let valid = try draft.validated()
        try transaction {
            let statement = try Self.prepare("UPDATE contributor SET name = ?, sort_name = ?, updated_at = ? WHERE id = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(valid.name, at: 1, to: statement)
            try Self.bind(valid.sortName, at: 2, to: statement)
            try Self.bind(Self.milliseconds(Date()), at: 3, to: statement)
            try Self.bind(contributorID.description, at: 4, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Contributor") }
            try incrementRevision()
        }
        return .init(id: contributorID, name: valid.name, sortName: valid.sortName)
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

    public func deleteAlbumContributor(_ contributorID: ContributorID, from albumID: AlbumID, role: ContributorRole, position: Int) throws {
        try transaction {
            let statement = try Self.prepare("DELETE FROM album_contributor WHERE album_id = ? AND contributor_id = ? AND role = ? AND position = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(albumID.description, at: 1, to: statement)
            try Self.bind(contributorID.description, at: 2, to: statement)
            try Self.bind(role.rawValue, at: 3, to: statement)
            try Self.bind(Int64(position), at: 4, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Album contributor credit") }
            try incrementRevision()
        }
    }

    public func updateAlbumContributorCredit(_ contributorID: ContributorID, in albumID: AlbumID, role: ContributorRole, position: Int, creditedName: String?, newRole: ContributorRole? = nil) throws {
        try transaction {
            let targetRole = newRole ?? role
            if targetRole == role {
                let statement = try Self.prepare("UPDATE album_contributor SET credited_name = ? WHERE album_id = ? AND contributor_id = ? AND role = ? AND position = ?;", on: connection)
                defer { sqlite3_finalize(statement) }
                try Self.bind(creditedName, at: 1, to: statement); try Self.bind(albumID.description, at: 2, to: statement); try Self.bind(contributorID.description, at: 3, to: statement); try Self.bind(role.rawValue, at: 4, to: statement); try Self.bind(Int64(position), at: 5, to: statement)
                try Self.stepDone(statement, connection: connection)
                guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Album contributor credit") }
            } else {
                let delete = try Self.prepare("DELETE FROM album_contributor WHERE album_id = ? AND contributor_id = ? AND role = ? AND position = ?;", on: connection)
                defer { sqlite3_finalize(delete) }
                try Self.bind(albumID.description, at: 1, to: delete); try Self.bind(contributorID.description, at: 2, to: delete); try Self.bind(role.rawValue, at: 3, to: delete); try Self.bind(Int64(position), at: 4, to: delete)
                try Self.stepDone(delete, connection: connection)
                guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Album contributor credit") }
                let targetPosition = try Self.nextNumber("SELECT COALESCE(MAX(position), -1) + 1 FROM album_contributor WHERE album_id = ? AND role = ?;", ownerID: albumID.description, on: connection, additionalValue: targetRole.rawValue)
                let insert = try Self.prepare("INSERT INTO album_contributor (album_id, contributor_id, role, credited_name, position) VALUES (?, ?, ?, ?, ?);", on: connection)
                defer { sqlite3_finalize(insert) }
                try Self.bind(albumID.description, at: 1, to: insert); try Self.bind(contributorID.description, at: 2, to: insert); try Self.bind(targetRole.rawValue, at: 3, to: insert); try Self.bind(creditedName, at: 4, to: insert); try Self.bind(Int64(targetPosition), at: 5, to: insert)
                try Self.stepDone(insert, connection: connection)
            }
            try incrementRevision()
        }
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

    public func deleteTrackContributor(_ contributorID: ContributorID, from trackID: TrackID, role: ContributorRole, position: Int) throws {
        try transaction {
            let statement = try Self.prepare("DELETE FROM track_contributor WHERE track_id = ? AND contributor_id = ? AND role = ? AND position = ?;", on: connection)
            defer { sqlite3_finalize(statement) }
            try Self.bind(trackID.description, at: 1, to: statement)
            try Self.bind(contributorID.description, at: 2, to: statement)
            try Self.bind(role.rawValue, at: 3, to: statement)
            try Self.bind(Int64(position), at: 4, to: statement)
            try Self.stepDone(statement, connection: connection)
            guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Track contributor credit") }
            try incrementRevision()
        }
    }

    public func updateTrackContributorCredit(_ contributorID: ContributorID, in trackID: TrackID, role: ContributorRole, position: Int, creditedName: String?, newRole: ContributorRole? = nil) throws {
        try transaction {
            let targetRole = newRole ?? role
            if targetRole == role {
                let statement = try Self.prepare("UPDATE track_contributor SET credited_name = ? WHERE track_id = ? AND contributor_id = ? AND role = ? AND position = ?;", on: connection)
                defer { sqlite3_finalize(statement) }
                try Self.bind(creditedName, at: 1, to: statement); try Self.bind(trackID.description, at: 2, to: statement); try Self.bind(contributorID.description, at: 3, to: statement); try Self.bind(role.rawValue, at: 4, to: statement); try Self.bind(Int64(position), at: 5, to: statement)
                try Self.stepDone(statement, connection: connection)
                guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Track contributor credit") }
            } else {
                let delete = try Self.prepare("DELETE FROM track_contributor WHERE track_id = ? AND contributor_id = ? AND role = ? AND position = ?;", on: connection)
                defer { sqlite3_finalize(delete) }
                try Self.bind(trackID.description, at: 1, to: delete); try Self.bind(contributorID.description, at: 2, to: delete); try Self.bind(role.rawValue, at: 3, to: delete); try Self.bind(Int64(position), at: 4, to: delete)
                try Self.stepDone(delete, connection: connection)
                guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Track contributor credit") }
                let targetPosition = try Self.nextNumber("SELECT COALESCE(MAX(position), -1) + 1 FROM track_contributor WHERE track_id = ? AND role = ?;", ownerID: trackID.description, on: connection, additionalValue: targetRole.rawValue)
                let insert = try Self.prepare("INSERT INTO track_contributor (track_id, contributor_id, role, credited_name, position) VALUES (?, ?, ?, ?, ?);", on: connection)
                defer { sqlite3_finalize(insert) }
                try Self.bind(trackID.description, at: 1, to: insert); try Self.bind(contributorID.description, at: 2, to: insert); try Self.bind(targetRole.rawValue, at: 3, to: insert); try Self.bind(creditedName, at: 4, to: insert); try Self.bind(Int64(targetPosition), at: 5, to: insert)
                try Self.stepDone(insert, connection: connection)
            }
            try incrementRevision()
        }
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
        let revision = try currentRevision()
        let statement = try Self.prepare("INSERT INTO edit_event (id, entity_type, entity_id, field_name, old_value, new_value, source, occurred_at) VALUES (?, 'catalogue', '1', 'catalogue_revision', ?, ?, 'mac', ?);", on: connection)
        defer { sqlite3_finalize(statement) }
        try Self.bind(UUID().uuidString.lowercased(), at: 1, to: statement)
        try Self.bind(String(revision - 1), at: 2, to: statement)
        try Self.bind(String(revision), at: 3, to: statement)
        try Self.bind(Self.milliseconds(Date()), at: 4, to: statement)
        try Self.stepDone(statement, connection: connection)
    }

    private func incrementImportProgress(batchID: ImportBatchID, candidates: Int64, errors: Int64) throws {
        let statement = try Self.prepare("UPDATE import_batch SET processed_count = processed_count + 1, candidate_count = candidate_count + ?, error_count = error_count + ? WHERE id = ? AND status = 'scanning';", on: connection)
        defer { sqlite3_finalize(statement) }; try Self.bind(candidates, at: 1, to: statement); try Self.bind(errors, at: 2, to: statement); try Self.bind(batchID.description, at: 3, to: statement); try Self.stepDone(statement, connection: connection)
        guard sqlite3_changes(connection) == 1 else { throw DatabaseError.notFound("Active import batch") }
    }

    private static let albumSelect = "SELECT id, title, edition_label, release_year, country_code, label_name, catalogue_number, barcode, remaster_year, media_format, disc_count, has_cd, physical_location_id, physical_location_unknown, physical_note, notes, rating, is_favourite, created_at, updated_at, deleted_at FROM album"
    private static func csvValue(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }

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

    private static func bind(_ value: Double, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else { throw DatabaseError.sqlite(message: "Unable to bind SQLite decimal value.") }
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

    private static func textResult(_ sql: String, on connection: OpaquePointer) -> String? {
        guard let statement = try? prepare(sql, on: connection) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(at: 0, from: statement)
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
