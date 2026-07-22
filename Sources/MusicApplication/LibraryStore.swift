import Combine
import Foundation
import MusicDomain
import MusicPersistence

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var albums: [Album] = []
    @Published public private(set) var locations: [PhysicalLocation] = []
    @Published public private(set) var boxSets: [BoxSet] = []
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
        albums = try await loadedAlbums
        locations = try await loadedLocations
        boxSets = try await loadedBoxSets
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
}
