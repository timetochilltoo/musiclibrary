import Combine
import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Library search")
@MainActor
struct LibrarySearchTests {
    @Test("Search does not republish catalogue summaries or change revision; clearing uses the cached catalogue")
    func lightweightSearch() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let first = try await database.createAlbum(.init(title: "The Piano", catalogueNumber: "0777"))
        let second = try await database.createAlbum(.init(title: "Kind of Blue"))
        let store = LibraryStore(database: database)
        try await store.reload()
        let revision = try await database.currentRevision()
        var summaryPublications = 0
        let subscription = store.$albumBrowseSummaries.sink { _ in summaryPublications += 1 }
        let baseline = summaryPublications
        await store.search("0777")
        #expect(store.albums.map(\.id) == [first.id])
        #expect(Set(store.catalogueAlbums.map(\.id)) == [first.id, second.id])
        #expect(summaryPublications == baseline)
        await store.search("no matching album")
        #expect(store.albums.isEmpty)
        await store.search("  ")
        #expect(store.albums == store.catalogueAlbums)
        #expect(summaryPublications == baseline)
        #expect(try await database.currentRevision() == revision)
        #expect(!store.isSnapshotPublishPending)
        subscription.cancel()
    }

    @Test("Refresh preserves the search after catalogue edits and keeps detail navigation complete")
    func refreshAfterEdit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let first = try await database.createAlbum(.init(title: "Piano"))
        let second = try await database.createAlbum(.init(title: "Blue"))
        let store = LibraryStore(database: database)
        try await store.reload()
        await store.search("Piano")
        #expect(store.albums.map(\.id) == [first.id])
        _ = try await database.createAlbum(.init(title: "Piano concerts"))
        try await store.reload()
        #expect(store.albums.count == 2)
        #expect(store.albums.allSatisfy { $0.title.contains("Piano") })
        #expect(store.catalogueAlbums.contains { $0.id == second.id })
    }

    @Test("Older search results and errors cannot overwrite the latest search")
    func supersededSearches() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let latest = Album(id: AlbumID(), from: .init(title: "Latest"))
        let harness = SearchHarness()
        let store = LibraryStore(database: database) { _, _ in try await harness.load() }
        let old = Task { await store.search("Old") }
        await harness.waitForRequests(1)
        let new = Task { await store.search("Latest") }
        await harness.waitForRequests(2)
        await harness.succeed(2, with: [latest])
        await new.value
        await harness.fail(1)
        await old.value
        #expect(store.albums == [latest])
        #expect(store.errorMessage == nil)

        let cancelled = Task { await store.search("Cancelled") }
        await harness.waitForRequests(3)
        cancelled.cancel()
        await harness.succeed(3, with: [])
        await cancelled.value
        #expect(store.albums == [latest])
        #expect(store.errorMessage == nil)

        let currentFailure = Task { await store.search("Current failure") }
        await harness.waitForRequests(4)
        await harness.fail(4)
        await currentFailure.value
        #expect(store.errorMessage != nil)
        #expect(store.albums == [latest])
    }

    @Test("A catalogue refresh and older query cannot overwrite a newer overlapping search")
    func refreshOverlap() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let first = try await database.createAlbum(.init(title: "Old"))
        let latest = try await database.createAlbum(.init(title: "Latest"))
        let harness = SearchHarness()
        let store = LibraryStore(database: database) { _, _ in try await harness.load() }
        try await store.reload() // Empty query uses the full catalogue, not the loader.
        let old = Task { await store.search("Old") }
        await harness.waitForRequests(1)
        let refresh = Task { try await store.reload() }
        await harness.waitForRequests(2)
        let new = Task { await store.search("Latest") }
        await harness.waitForRequests(3)
        await harness.succeed(3, with: [latest])
        await new.value
        await harness.succeed(2, with: [first])
        try await refresh.value
        await harness.succeed(1, with: [first])
        await old.value
        #expect(store.albums == [latest])
        #expect(Set(store.catalogueAlbums.map(\.id)) == [first.id, latest.id])
        #expect(store.albumBrowseSummaries.count == 2)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LibrarySearch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor SearchHarness {
    enum Failure: Error { case stale }
    private var count = 0
    private var pending: [Int: CheckedContinuation<[Album], any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func load() async throws -> [Album] {
        count += 1
        let request = count
        return try await withCheckedThrowingContinuation { continuation in
            pending[request] = continuation
            let ready = waiters.filter { $0.0 <= count }
            waiters.removeAll { $0.0 <= count }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequests(_ expected: Int) async {
        if count >= expected { return }
        await withCheckedContinuation { waiters.append((expected, $0)) }
    }

    func succeed(_ request: Int, with albums: [Album]) { pending.removeValue(forKey: request)?.resume(returning: albums) }
    func fail(_ request: Int) { pending.removeValue(forKey: request)?.resume(throwing: Failure.stale) }
}
