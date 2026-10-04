#if DEBUG
import Foundation
import Testing
@testable import MusicApplication

@Suite("Navigation fixture")
@MainActor
struct LibraryNavigationFixtureTests {
    @Test("Attachment preview is read-only and explicit attachment preserves the target and retries idempotently")
    func attachmentReview() async throws {
        let fixture = try await LibraryStore.makeNavigationFixture(includeImportReview: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = fixture.store
        let batch = try #require(store.importBatches.first)
        let proposal = try #require(await store.importReleaseProposals(batchID: batch.id).first(where: { $0.status == .proposed }))
        let target = try #require(store.catalogueAlbums.first(where: { $0.title == "Fixture Album 001" }))
        let credits = try await store.albumContributors(albumID: target.id)
        let revision = store.catalogueRevision
        let preview = try await store.importAttachmentPreview(proposalID: proposal.id, albumID: target.id)
        #expect(preview.isCompatible && preview.pairs.count == 1)
        #expect(store.catalogueRevision == revision && store.catalogueAlbums.count == 241)
        #expect(try await store.attachImportReleaseProposal(proposal.id, to: target.id) == target.id)
        let attachedRevision = store.catalogueRevision
        #expect(attachedRevision == revision + 1)
        #expect(try await store.attachImportReleaseProposal(proposal.id, to: target.id) == target.id)
        #expect(store.catalogueRevision == attachedRevision)
        var after = try #require(store.catalogueAlbums.first(where: { $0.id == target.id }))
        // Populating empty structure legitimately updates its modification time.
        after.updatedAt = target.updatedAt
        #expect(after == target)
        #expect(try await store.albumContributors(albumID: target.id) == credits)
        #expect(store.catalogueAlbums.count == 241)
        let completed = try #require(await store.importReleaseProposals(batchID: batch.id).first(where: { $0.id == proposal.id }))
        #expect(completed.createdAlbumID == target.id)
        let root = try #require(store.storageRoots.first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.lastKnownPath).isEmpty)
    }

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
        for request: MusicBrainzReleaseLookup in [.title("Synthetic", artist: "Fixture Orchestra"), .barcode("001234"), .catalogueNumber("FIXTURE", artist: nil), .releaseURL("https://musicbrainz.org/release/9383a6f5-9607-4a36-9c68-8663aad3592b")] {
            let result = try #require(await store.lookupMusicBrainz(request).first)
            let detail = try await store.musicBrainzReleaseDetails(id: result.id)
            try await store.saveMusicBrainzSelection(detail, for: pending.id)
        }
        let unchanged = try #require(await store.importReleaseProposals(batchID: batch.id).first(where: { $0.id == pending.id }))
        #expect(unchanged == pending)
        #expect(store.catalogueAlbums.count == 241)
        let selection = try #require(await store.externalMetadataSelection(for: pending.id))
        #expect(selection.trackTitles.count == 3)
        #expect(selection.discCount == 2)
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
