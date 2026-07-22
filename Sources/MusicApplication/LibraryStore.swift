import Combine
import Foundation
import MusicDomain
import MusicPersistence

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var albums: [Album] = []
    @Published public private(set) var locations: [PhysicalLocation] = []
    @Published public private(set) var boxSets: [BoxSet] = []
    @Published public private(set) var storageRoots: [StorageRoot] = []
    @Published public private(set) var isReady = false
    @Published public private(set) var errorMessage: String?

    private var database: MusicDatabase?
    private var hasStarted = false

    public init() {}

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            let directory = try applicationSupportDirectory()
            let database = try MusicDatabase(url: directory.appending(path: "MusicLibrary.sqlite"))
            try await database.migrate()
            self.database = database
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
        albums = try await loadedAlbums
        locations = try await loadedLocations
        boxSets = try await loadedBoxSets
        storageRoots = try await loadedStorageRoots
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
