import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Storage root locality")
struct StorageRootLocalityProbeTests {
    @Test("A disposable local folder is measured from its volume")
    func localFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Locality-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(StorageRootLocalityProbe.measure(at: directory) == .local)
    }

    @Test("Non-file URLs are unknown and never trigger network lookup")
    func nonFileURL() throws {
        let url = try #require(URL(string: "https://example.invalid/music"))
        #expect(StorageRootLocalityProbe.measure(at: url) == .unknown)
    }

    @Test("Reload discards measurements for replaced, offline, unauthorized, and removed roots")
    func invalidateMeasurements() {
        let id = StorageRootID()
        func root(path: String = "/synthetic/music", bookmark: Data = Data([1]), volume: String = "local-volume",
                  status: StorageRootStatus = .available, scope: StorageRootScope = .localOnly) -> StorageRoot {
            .init(id: id, displayName: "Fixture", lastKnownPath: path, bookmarkData: bookmark,
                  volumeIdentifier: volume, status: status, scope: scope, bookmarkNeedsRefresh: false, lastSeenAt: nil)
        }
        let measured: [StorageRootID: StorageRootLocality] = [id: .local]
        // Sharing is independent of physical locality and must not invalidate it.
        #expect(StorageRootLocalityProbe.retainUnchanged(measured, previousRoots: [root()], currentRoots: [root(scope: .nasPublished)]) == measured)
        for replacement in [root(path: "/synthetic/replacement"), root(bookmark: Data([2])), root(volume: "another-volume"),
                            root(status: .offline), root(status: .permissionRequired)] {
            #expect(StorageRootLocalityProbe.retainUnchanged(measured, previousRoots: [root()], currentRoots: [replacement]).isEmpty)
        }
        #expect(StorageRootLocalityProbe.retainUnchanged(measured, previousRoots: [root()], currentRoots: []).isEmpty)
        #expect(StorageRootLocalityProbe.retainUnchanged(measured, previousRoots: [], currentRoots: [root()]).isEmpty)
    }
}
