import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Contributor browse integration")
@MainActor
struct ContributorBrowseIntegrationTests {
    @Test("Batched album/track roles are read-only, refresh after edits and exclude deleted albums")
    func roleEdges() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ContributorBrowse-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let contributor = try await database.createContributor(.init(name: "Fixture Composer"))
        let unused = try await database.createContributor(.init(name: "Unused"))
        let first = try await database.createAlbum(.init(title: "First", hasCD: true))
        let second = try await database.createAlbum(.init(title: "Second"))
        let disc = try await database.createDisc(albumID: first.id)
        let track = try await database.createTrack(discID: disc.id, draft: .init(title: "Track"))
        let anotherTrack = try await database.createTrack(discID: disc.id, draft: .init(title: "Another"))
        try await database.addAlbumContributor(contributor.id, to: first.id, role: .composer, creditedName: nil)
        try await database.addTrackContributor(contributor.id, to: track.id, role: .composer, creditedName: "C. Fixture")
        try await database.addTrackContributor(contributor.id, to: anotherTrack.id, role: .composer, creditedName: nil)
        try await database.addTrackContributor(contributor.id, to: track.id, role: .performer, creditedName: nil)
        try await database.addAlbumContributor(contributor.id, to: second.id, role: .conductor, creditedName: nil)
        let revision = try await database.currentRevision()
        let edges = try await database.contributorAlbumRoles()
        #expect(edges.count == 3)
        #expect(Set(edges) == [.init(contributorID: contributor.id, albumID: first.id, role: .composer),
                               .init(contributorID: contributor.id, albumID: first.id, role: .performer),
                               .init(contributorID: contributor.id, albumID: second.id, role: .conductor)])
        #expect(try await database.currentRevision() == revision)
        let store = LibraryStore(database: database)
        try await store.reload()
        #expect(store.contributorBrowseSummaries[contributor.id]?.albumIDs().count == 2)
        #expect(store.contributorBrowseSummaries[unused.id]?.albumIDs().isEmpty == true)
        #expect(!store.isSnapshotPublishPending)
        await store.search("First")
        #expect(store.albums.count == 1 && store.contributorBrowseSummaries[contributor.id]?.albumIDs().count == 2)
        try await store.softDeleteAlbum(first.id)
        #expect(store.contributorBrowseSummaries[contributor.id]?.roles == [.conductor])
        try await store.updateContributor(contributor.id, draft: .init(name: "Corrected", sortName: "Sort Corrected"))
        #expect(store.contributors.first { $0.id == contributor.id }?.name == "Corrected")
        #expect(store.contributorBrowseSummaries[contributor.id]?.albumIDs() == [second.id])
        try await store.restoreAlbum(first.id)
        #expect(store.contributorBrowseSummaries[contributor.id]?.albumIDs(role: .composer) == [first.id])
        #expect(store.storageRoots.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { $0.hasPrefix("fixture.sqlite") })
    }
}
