import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Same-folder access renewal")
struct StorageRootAccessRenewalTests {
    @Test("Selection accepts only the same path and matching known volume")
    func validatesIdentity() throws {
        let root = StorageRoot(id: .init(), displayName: "Music", lastKnownPath: "/Music", bookmarkData: nil, volumeIdentifier: "volume-A", status: .permissionRequired, scope: .localOnly, bookmarkNeedsRefresh: false, lastSeenAt: nil)
        try StorageRootAccessRenewal.validatePath(URL(fileURLWithPath: "/Music/"), for: root)
        try StorageRootAccessRenewal.validateVolume("volume-A", for: root)
        for path in ["/Other", "/Music/Album", "/", "/Music-copy"] {
            do { try StorageRootAccessRenewal.validatePath(URL(fileURLWithPath: path), for: root); Issue.record("Different folder accepted") } catch {}
        }
        for volume in [nil, "volume-B"] as [String?] {
            do { try StorageRootAccessRenewal.validateVolume(volume, for: root); Issue.record("Unknown/wrong volume accepted") } catch {}
        }
    }

    @Test("Wrong-folder and missing-root renewal refuse before permission or writes")
    @MainActor func refusesSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RootRenewalService-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Music", lastKnownPath: directory.path, bookmarkData: Data([1]), status: .permissionRequired))
        let store = LibraryStore(database: database)
        let revision = try await database.currentRevision()
        for id in [root.id, StorageRootID()] {
            do { try await store.renewStorageRootAccess(id, selecting: directory.appending(path: "wrong")); Issue.record("Invalid renewal accepted") } catch {}
        }
        let unchanged = try #require(await database.storageRoots().first)
        #expect(unchanged.id == root.id && unchanged.bookmarkData == Data([1]))
        #expect(try await database.currentRevision() == revision)
    }
}
