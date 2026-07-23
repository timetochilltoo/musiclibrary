import Combine
import CryptoKit
import Foundation
import MusicDomain
import MusicPersistence

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var albums: [Album] = []
    @Published public private(set) var locations: [PhysicalLocation] = []
    @Published public private(set) var boxSets: [BoxSet] = []
    @Published public private(set) var storageRoots: [StorageRoot] = []
    @Published public private(set) var importBatches: [ImportBatch] = []
    @Published public private(set) var libraryHealthIssues: [LibraryHealthIssue] = []
    @Published public private(set) var playlists: [Playlist] = []
    @Published public private(set) var duplicateAssets: [AssetDuplicate] = []
    @Published public private(set) var relinkProposals: [AssetRelinkProposal] = []
    @Published public private(set) var isReady = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var snapshotDestinationPath: String?
    @Published public private(set) var snapshotPublishStatus = "Snapshot destination not configured"
    @Published public private(set) var catalogueRevision: Int64 = 0
    @Published public private(set) var lastPublishedRevision: Int64?
    @Published public private(set) var lastPublishedAt: Date?
    @Published public private(set) var lastSnapshotPublishFailure: String?
    @Published public private(set) var isSnapshotPublishPending = false

    private var database: MusicDatabase?
    private var hasStarted = false
    private var scanTasks: [ImportBatchID: Task<Void, Never>] = [:]
    private var snapshotPublishTask: Task<Void, Never>?
    private let snapshotDestinationBookmarkKey = "MusicLibrary.snapshotDestinationBookmark"
    private let lastPublishedRevisionKey = "MusicLibrary.lastPublishedRevision"
    private let lastPublishedAtKey = "MusicLibrary.lastPublishedAt"
    private let lastSnapshotPublishFailureKey = "MusicLibrary.lastSnapshotPublishFailure"
    private var publicationSchedule = SnapshotPublicationSchedule()

    public init() {}

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            let directory = try applicationSupportDirectory()
            let database = try MusicDatabase(url: directory.appending(path: "MusicLibrary.sqlite"))
            try await database.migrate()
            self.database = database
            loadSnapshotDestination()
            try await database.recoverInterruptedImportBatches()
            try await reload()
            try await refreshStorageRootAccess()
            isReady = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reload(searchTerm: String? = nil) async throws {
        guard let database else { return }
        async let loadedAlbums = database.albums(matching: searchTerm)
        async let loadedLocations = database.locations()
        async let loadedBoxSets = database.boxSets()
        async let loadedStorageRoots = database.storageRoots()
        async let loadedImportBatches = database.importBatches()
        async let loadedHealth = database.libraryHealthIssues()
        async let loadedPlaylists = database.playlists()
        albums = try await loadedAlbums
        locations = try await loadedLocations
        boxSets = try await loadedBoxSets
        storageRoots = try await loadedStorageRoots
        importBatches = try await loadedImportBatches
        libraryHealthIssues = try await loadedHealth
        playlists = try await loadedPlaylists
        duplicateAssets = try await database.duplicateAssets()
        relinkProposals = try await database.relinkProposals()
        let revision = try await database.currentRevision()
        catalogueRevision = revision
        if publicationSchedule.observe(revision) { scheduleSnapshotPublication() }
    }

    public func search(_ term: String) async {
        do { try await reload(searchTerm: term) }
        catch { errorMessage = error.localizedDescription }
    }

    public func addAlbum(_ draft: NewAlbum, toBoxSet boxSetID: BoxSetID? = nil) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        _ = try await database.createAlbum(draft, in: boxSetID)
        try await reload()
    }

    public func updateAlbum(_ id: AlbumID, with draft: NewAlbum) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        _ = try await database.updateAlbum(id, with: draft)
        try await reload()
    }

    public func boxMembers(of boxSetID: BoxSetID) async throws -> [BoxSetMembership] {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        return try await database.boxMembers(of: boxSetID)
    }

    public func boxPlacement(for albumID: AlbumID) async throws -> AlbumBoxPlacement? {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        return try await database.boxPlacement(for: albumID)
    }

    public func moveAlbum(_ albumID: AlbumID, to boxSetID: BoxSetID) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.moveAlbum(albumID, to: boxSetID)
        try await reload()
    }

    public func removeAlbum(_ albumID: AlbumID, from boxSetID: BoxSetID, assigning locationID: PhysicalLocationID?, locationUnknown: Bool) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.removeAlbum(albumID, from: boxSetID, assigning: locationID, locationUnknown: locationUnknown)
        try await reload()
    }

    public func reorderAlbum(_ albumID: AlbumID, in boxSetID: BoxSetID, to position: Int) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.reorderAlbum(albumID, in: boxSetID, to: position)
        try await reload()
    }

    public func discs(albumID: AlbumID) async throws -> [Disc] { guard let database else { throw DatabaseError.notFound("Catalogue database") }; return try await database.discs(albumID: albumID) }
    public func tracks(discID: DiscID) async throws -> [Track] { guard let database else { throw DatabaseError.notFound("Catalogue database") }; return try await database.tracks(discID: discID) }
    public func albumContributors(albumID: AlbumID) async throws -> [ContributorCredit] { guard let database else { throw DatabaseError.notFound("Catalogue database") }; return try await database.albumContributors(albumID: albumID) }
    public func trackContributors(trackID: TrackID) async throws -> [ContributorCredit] { guard let database else { throw DatabaseError.notFound("Catalogue database") }; return try await database.trackContributors(trackID: trackID) }
    public func albumAliases(albumID: AlbumID) async throws -> [AlbumAlias] { guard let database else { throw DatabaseError.notFound("Catalogue database") }; return try await database.albumAliases(albumID: albumID) }
    public func albumArtwork(albumID: AlbumID) async throws -> [Artwork] { guard let database else { throw DatabaseError.notFound("Catalogue database") }; return try await database.albumArtwork(albumID: albumID) }
    public func addDisc(albumID: AlbumID, title: String?) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; _ = try await database.createDisc(albumID: albumID, title: title); try await reload() }
    public func addTrack(discID: DiscID, draft: NewTrack) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; _ = try await database.createTrack(discID: discID, draft: draft); try await reload() }
    public func updateTrack(_ trackID: TrackID, draft: NewTrack) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; _ = try await database.updateTrack(trackID, with: draft); try await reload() }
    public func deleteTrack(_ trackID: TrackID) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; try await database.deleteTrack(trackID); try await reload() }
    public func addAlbumAlias(albumID: AlbumID, name: String, kind: AlbumAliasKind, locale: String?) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; _ = try await database.addAlbumAlias(albumID: albumID, name: name, kind: kind, locale: locale); try await reload() }
    public func deleteAlbumAlias(_ aliasID: UUID) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; try await database.deleteAlbumAlias(aliasID); try await reload() }
    public func addAlbumContributor(albumID: AlbumID, name: String, role: ContributorRole, creditedName: String?) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; let contributor = try await database.createContributor(.init(name: name)); try await database.addAlbumContributor(contributor.id, to: albumID, role: role, creditedName: creditedName); try await reload() }
    public func addTrackContributor(trackID: TrackID, name: String, role: ContributorRole, creditedName: String?) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; let contributor = try await database.createContributor(.init(name: name)); try await database.addTrackContributor(contributor.id, to: trackID, role: role, creditedName: creditedName); try await reload() }
    public func addAlbumArtwork(albumID: AlbumID, localPath: String, role: ArtworkRole) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; _ = try await database.addAlbumArtwork(albumID: albumID, localPath: localPath, role: role); try await reload() }

    public func addStorageRoot(url: URL) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        let bookmarkData = try makeSecurityScopedBookmark(for: url)
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey])
        _ = try await database.createStorageRoot(.init(displayName: url.lastPathComponent, lastKnownPath: url.path, bookmarkData: bookmarkData, volumeIdentifier: values?.volumeUUIDString, status: .available))
        try await reload()
    }

    public func renameStorageRoot(_ id: StorageRootID, to displayName: String) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.renameStorageRoot(id, to: displayName)
        try await reload()
    }

    public func deleteStorageRoot(_ id: StorageRootID) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.deleteStorageRoot(id)
        try await reload()
    }

    public func refreshStorageRootAccess() async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        for root in storageRoots {
            let state = resolveSecurityScopedBookmark(root)
            if root.status != state.status || root.bookmarkNeedsRefresh != state.bookmarkNeedsRefresh || state.refreshedBookmarkData != nil || (state.status == .available && root.lastKnownPath != state.url?.path) {
                try await database.updateStorageRootAccess(root.id, status: state.status, lastKnownPath: state.url?.path, bookmarkData: state.refreshedBookmarkData, bookmarkNeedsRefresh: state.bookmarkNeedsRefresh)
            }
        }
        try await reload()
    }

    public func recheckLibraryHealth() async throws {
        try await refreshStorageRootAccess()
        try await reload()
    }
    public func applyRelinkProposal(_ id: UUID) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.applyRelinkProposal(id)
        try await reload()
    }
    public func discardRelinkProposal(_ id: UUID) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.discardRelinkProposal(id)
        try await reload()
    }

    public func importCandidates(batchID: ImportBatchID) async throws -> [ImportCandidate] {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        return try await database.importCandidates(batchID: batchID)
    }

    public func importReleaseProposals(batchID: ImportBatchID) async throws -> [ImportReleaseProposal] {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        return try await database.importReleaseProposals(batchID: batchID)
    }

    public func analyzeImportBatch(_ batchID: ImportBatchID) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await refreshStorageRootAccess()
        guard let batch = importBatches.first(where: { $0.id == batchID }), let rootID = batch.storageRootID, let root = storageRoots.first(where: { $0.id == rootID }) else { throw DatabaseError.notFound("Storage root for import batch") }
        let resolved = resolveSecurityScopedBookmark(root)
        guard resolved.status == .available, let rootURL = resolved.url else { throw DatabaseError.invalidOperation("The source storage root is not available.") }
        let accessed = rootURL.startAccessingSecurityScopedResource()
        defer { if accessed { rootURL.stopAccessingSecurityScopedResource() } }
        guard accessed else { throw DatabaseError.invalidOperation("Permission to access the source storage root was not available.") }
        let candidates = try await database.importCandidates(batchID: batchID)
        let extractor = EmbeddedMetadataExtractor()
        for candidate in candidates where candidate.status != .failed {
            guard let payload = candidate.payload else { continue }
            let metadata = await extractor.extract(url: rootURL.appending(path: payload.relativePath))
            try await database.saveEmbeddedMetadata(metadata, for: candidate.id)
        }
        let extracted = try await database.importCandidates(batchID: batchID)
        try await database.rebuildImportReleaseProposals(batchID: batchID, drafts: MetadataProposalGrouper().group(candidates: extracted))
    }

    public func setImportReleaseProposal(_ id: UUID, status: ImportProposalStatus) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.updateImportReleaseProposal(id, status: status)
    }

    public func confirmImportReleaseProposal(_ id: UUID) async throws -> AlbumID {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        let albumID = try await database.confirmImportReleaseProposal(id)
        try await reload()
        return albumID
    }

    public func playbackURL(for trackID: TrackID) async throws -> (url: URL, title: String) {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await refreshStorageRootAccess()
        guard let asset = try await database.playbackAsset(trackID: trackID) else { throw DatabaseError.notFound("Playable asset") }
        guard asset.availability == .available else { throw DatabaseError.invalidOperation("This asset is not currently available.") }
        guard let root = storageRoots.first(where: { $0.id == asset.storageRootID }) else { throw DatabaseError.notFound("Storage root") }
        let resolved = resolveSecurityScopedBookmark(root)
        guard resolved.status == .available, let rootURL = resolved.url else { throw DatabaseError.invalidOperation("The asset's storage root is unavailable.") }
        let url = rootURL.appending(path: asset.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw DatabaseError.invalidOperation("The audio file is missing. Its catalogue record was left unchanged.") }
        return (url, asset.title)
    }

    public func playbackURLs(discID: DiscID) async throws -> [(url: URL, trackID: TrackID, title: String)] {
        let discTracks = try await tracks(discID: discID)
        var results: [(url: URL, trackID: TrackID, title: String)] = []
        for track in discTracks { let asset = try await playbackURL(for: track.id); results.append((asset.url, track.id, asset.title)) }
        return results
    }
    public func playlistItems(_ id: PlaylistID) async throws -> [PlaylistItem] { guard let database else { throw DatabaseError.notFound("Catalogue database") }; return try await database.playlistItems(playlistID: id) }
    public func addPlaylist(name: String) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; _ = try await database.createPlaylist(name: name); try await reload() }
    public func addTrack(_ trackID: TrackID, toPlaylist id: PlaylistID) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; try await database.addTrack(trackID, to: id); try await reload() }
    public func softDeleteAlbum(_ id: AlbumID) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; try await database.softDeleteAlbum(id); try await reload() }
    public func exportCatalogue(to url: URL) async throws { guard let database else { throw DatabaseError.notFound("Catalogue database") }; let json = try await database.catalogueExportJSON(); try json.write(to: url, atomically: true, encoding: .utf8) }
    public func publishSnapshot(to directory: URL) async throws -> SnapshotManifest { guard let database else { throw DatabaseError.notFound("Catalogue database") }; let value = try await database.publicationRevisionAndJSON(); return try SnapshotPublisher.publish(json: value.1, revision: value.0, to: directory) }
    public func setSnapshotDestination(_ url: URL) throws {
        let bookmark = try makeSecurityScopedBookmark(for: url)
        UserDefaults.standard.set(bookmark, forKey: snapshotDestinationBookmarkKey)
        snapshotDestinationPath = url.path
        snapshotPublishStatus = "Ready to publish"
    }
    public func publishSnapshotNow() async throws {
        guard let destination = resolvedSnapshotDestination() else { throw DatabaseError.invalidOperation("Choose a snapshot destination first.") }
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        let manifest = try await publishSnapshot(to: destination)
        lastPublishedRevision = manifest.revision
        publicationSchedule.markPublished(manifest.revision)
        UserDefaults.standard.set(manifest.revision, forKey: lastPublishedRevisionKey)
        lastPublishedAt = Date()
        UserDefaults.standard.set(lastPublishedAt, forKey: lastPublishedAtKey)
        snapshotPublishStatus = "Published revision \(manifest.revision)"
        lastSnapshotPublishFailure = nil
        UserDefaults.standard.removeObject(forKey: lastSnapshotPublishFailureKey)
        isSnapshotPublishPending = false
    }
    public func flushPendingSnapshotPublication(maximumWait: Duration = .seconds(3)) async {
        guard publicationSchedule.needsPublication else { return }
        let publication = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.publishSnapshotNow() }
            catch { self.isSnapshotPublishPending = false; self.snapshotPublishStatus = "Background publish deferred: \(error.localizedDescription)" }
        }
        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await publication.value; return true }
            group.addTask { try? await Task.sleep(for: maximumWait); return false }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        if !completed { snapshotPublishStatus = "Publish continues in the background." }
    }
    public func verifyFingerprints() async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }; try await refreshStorageRootAccess()
        for candidate in try await database.assetFingerprintCandidates() {
            guard let root = storageRoots.first(where: { $0.id == candidate.rootID }) else { continue }; let state = resolveSecurityScopedBookmark(root); guard state.status == .available, let url = state.url?.appending(path: candidate.relativePath), let data = try? Data(contentsOf: url) else { continue }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(); try await database.recordAssetFingerprint(candidate.id, contentHash: hash, quickSignature: "\(data.count)-\(hash.prefix(16))")
        }
        try await reload()
    }

    public func startImportScan(rootID: StorageRootID) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await refreshStorageRootAccess()
        guard let root = storageRoots.first(where: { $0.id == rootID }) else { throw DatabaseError.notFound("Storage root") }
        let resolved = resolveSecurityScopedBookmark(root)
        guard resolved.status == .available, let url = resolved.url else { throw DatabaseError.invalidOperation("The selected storage root is not available.") }
        let batch = try await database.createImportBatch(storageRootID: rootID, sourceDescription: url.path)
        await refreshImportBatches()
        let task = Task.detached { [weak self, database] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard accessed else {
                try? await database.finishImportBatch(batch.id, status: .failed, errorSummary: "Permission to access the selected folder was not available.")
                await self?.refreshImportBatches()
                return
            }
            let result = ImportScanner().scan(rootURL: url)
            do {
                for (index, candidate) in result.candidates.enumerated() {
                    if Task.isCancelled { break }
                    try await database.recordImportCandidate(batchID: batch.id, payload: candidate)
                    if index.isMultiple(of: 20) { await self?.refreshImportBatches() }
                }
                for error in result.errors { try await database.recordImportError(batchID: batch.id, message: error) }
                let status: ImportBatchStatus = (result.wasCancelled || Task.isCancelled) ? .cancelled : .completed
                try await database.finishImportBatch(batch.id, status: status, errorSummary: result.errors.first)
            } catch {
                try? await database.finishImportBatch(batch.id, status: .failed, errorSummary: error.localizedDescription)
            }
            await self?.refreshImportBatches()
        }
        scanTasks[batch.id] = task
    }

    public func cancelImportScan(_ batchID: ImportBatchID) async {
        scanTasks[batchID]?.cancel()
    }

    public func retryImportScan(_ batchID: ImportBatchID) async throws {
        guard let batch = importBatches.first(where: { $0.id == batchID }), let rootID = batch.storageRootID else { throw DatabaseError.notFound("Storage root for import batch") }
        guard batch.status != .scanning else { throw DatabaseError.invalidOperation("This import batch is already scanning.") }
        try await startImportScan(rootID: rootID)
    }

    public func addLocation(_ draft: NewPhysicalLocation) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        _ = try await database.createLocation(draft)
        try await reload()
    }

    public func renameLocation(_ id: PhysicalLocationID, to name: String) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        try await database.renameLocation(id, to: name)
        try await reload()
    }

    public func addBoxSet(_ draft: NewBoxSet) async throws {
        guard let database else { throw DatabaseError.notFound("Catalogue database") }
        _ = try await database.createBoxSet(draft)
        try await reload()
    }

    public func dismissError() {
        errorMessage = nil
    }

    private func loadSnapshotDestination() {
        guard let destination = resolvedSnapshotDestination() else { return }
        snapshotDestinationPath = destination.path
        if UserDefaults.standard.object(forKey: lastPublishedRevisionKey) != nil {
            let revision = Int64(UserDefaults.standard.integer(forKey: lastPublishedRevisionKey))
            lastPublishedRevision = revision
            publicationSchedule.markPublished(revision)
        }
        lastPublishedAt = UserDefaults.standard.object(forKey: lastPublishedAtKey) as? Date
        lastSnapshotPublishFailure = UserDefaults.standard.string(forKey: lastSnapshotPublishFailureKey)
        snapshotPublishStatus = "Ready to publish"
    }

    private func resolvedSnapshotDestination() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: snapshotDestinationBookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private func scheduleSnapshotPublication() {
        guard resolvedSnapshotDestination() != nil else { return }
        snapshotPublishTask?.cancel()
        isSnapshotPublishPending = true
        snapshotPublishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            do { if self.publicationSchedule.needsPublication { try await self.publishSnapshotNow() } else { self.isSnapshotPublishPending = false } }
            catch { self.recordSnapshotPublishFailure(error, prefix: "Automatic publish failed") }
        }
    }

    private func recordSnapshotPublishFailure(_ error: Error, prefix: String) {
        isSnapshotPublishPending = false
        let message = "\(prefix): \(error.localizedDescription)"
        snapshotPublishStatus = message
        lastSnapshotPublishFailure = message
        UserDefaults.standard.set(message, forKey: lastSnapshotPublishFailureKey)
    }

    private func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "MusicLibrary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func refreshImportBatches() async {
        guard let database else { return }
        importBatches = (try? await database.importBatches()) ?? importBatches
    }

    private func makeSecurityScopedBookmark(for url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolveSecurityScopedBookmark(_ root: StorageRoot) -> (status: StorageRootStatus, url: URL?, refreshedBookmarkData: Data?, bookmarkNeedsRefresh: Bool) {
        guard let bookmarkData = root.bookmarkData else { return (.permissionRequired, nil, nil, false) }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard accessed else { return (.permissionRequired, nil, nil, isStale) }
            guard FileManager.default.fileExists(atPath: url.path) else { return (.offline, url, nil, isStale) }
            let refreshed = isStale ? try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            return (.available, url, refreshed, isStale && refreshed == nil)
        } catch {
            return (.permissionRequired, nil, nil, false)
        }
    }
}
