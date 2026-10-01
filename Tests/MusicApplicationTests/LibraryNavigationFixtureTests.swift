#if DEBUG
import Foundation
import Testing
@testable import MusicApplication

@Suite("Navigation fixture")
@MainActor
struct LibraryNavigationFixtureTests {
    @Test("Real shell data stays disposable and startup cannot switch to the personal catalogue")
    func isolatedStartup() async throws {
        let fixture = try await LibraryStore.makeNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = fixture.store
        let revision = store.catalogueRevision
        let albumIDs = store.catalogueAlbums.map(\.id)
        #expect(store.isReady)
        #expect(albumIDs.count == 240)
        #expect(store.storageRoots.isEmpty)
        #expect(store.albumFrontArtworkPaths.isEmpty)
        #expect(store.localAlbumIDs.isEmpty)
        #expect(store.libraryHealthIssues.count == 240)
        let contributor = try #require(store.contributors.first)
        #expect(try await store.albums(creditedTo: contributor.id).count == 240)
        let box = try #require(store.boxSets.first)
        #expect(try await store.boxMembers(of: box.id).count == 12)
        await store.start()
        try await store.reload()
        #expect(store.catalogueAlbums.map(\.id) == albumIDs)
        #expect(store.catalogueRevision == revision)
        #expect(store.snapshotDestinationPath == nil)
        #expect(!store.isSnapshotPublishPending)
        #expect(store.errorMessage == nil)
    }
}
#endif
