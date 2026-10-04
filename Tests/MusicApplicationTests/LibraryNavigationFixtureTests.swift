#if DEBUG
import Foundation
import Testing
@testable import MusicApplication

@Suite("Navigation fixture")
@MainActor
struct LibraryNavigationFixtureTests {
    @Test("Import review fixtures use only offline metadata references below a disposable root")
    func importReview() async throws {
        let fixture = try await LibraryStore.makeNavigationFixture(includeImportReview: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = fixture.store
        let root = try #require(store.storageRoots.first)
        #expect(root.lastKnownPath.hasPrefix(fixture.directory.path + "/"))
        #expect(root.status == .offline)
        #expect(root.bookmarkData == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.lastKnownPath).isEmpty)
        let batch = try #require(store.importBatches.first)
        let proposals = try await store.importReleaseProposals(batchID: batch.id)
        #expect(Set(proposals.map(ImportReviewCategory.category)) == [.needsReview, .ready, .skipped, .added])
        let pending = try #require(proposals.first(where: { $0.status == .proposed }))
        let selection = try #require(await store.externalMetadataSelection(for: pending.id))
        try await store.applyExternalMetadataSelection(selection, fields: .init(title: true, artist: false, discCount: false))
        let revised = try #require(await store.importReleaseProposals(batchID: batch.id).first(where: { $0.id == pending.id }))
        #expect(revised.title == selection.title)
        #expect(revised.createdAlbumID == nil)
        #expect(revised.artist == pending.artist && revised.discCount == pending.discCount)
        #expect(store.catalogueAlbums.count == 241)
        try await store.setImportReleaseProposal(pending.id, status: .dismissed)
        try await store.setImportReleaseProposal(pending.id, status: .proposed)
        let id = try await store.confirmImportReleaseProposal(pending.id)
        #expect(try await store.confirmImportReleaseProposal(pending.id) == id)
        #expect(store.catalogueAlbums.count == 242)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.lastKnownPath).isEmpty)
    }

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
        let release = try #require(try await store.searchMusicBrainz(title: "Synthetic", artist: nil).first)
        #expect(release.title == "Synthetic two-disc release")
        #expect(release.physicalDiscs?.count == 2)
        #expect(store.catalogueRevision == revision)
    }
}
#endif
