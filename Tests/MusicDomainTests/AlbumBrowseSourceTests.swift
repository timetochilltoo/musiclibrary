import Foundation
import Testing
@testable import MusicDomain

@Suite("Album browse source")
struct AlbumBrowseSourceTests {
    @Test("Locality requires measured volume information")
    func measuredLocality() {
        #expect(StorageRootLocality(isLocalVolume: true) == .local)
        #expect(StorageRootLocality(isLocalVolume: false) == .network)
        #expect(StorageRootLocality(isLocalVolume: nil) == .unknown)
    }

    @Test("Source filtering distinguishes local, network, mixed, and physical albums")
    func sourceFilters() {
        let local = StorageRootID()
        let network = StorageRootID()
        let unverified = StorageRootID()
        let localIDs: Set<StorageRootID> = [local]
        let physical = AlbumBrowseSummary()
        let localCopy = AlbumBrowseSummary(hasDigitalAssets: true, storageRootIDs: [local])
        let networkCopy = AlbumBrowseSummary(hasDigitalAssets: true, storageRootIDs: [network])
        let mixed = AlbumBrowseSummary(hasDigitalAssets: true, storageRootIDs: [local, network])
        let unknown = AlbumBrowseSummary(hasDigitalAssets: true, storageRootIDs: [unverified])
        #expect(AlbumBrowseSource.any.matches(physical, localRootIDs: localIDs))
        #expect(!AlbumBrowseSource.thisMac.matches(physical, localRootIDs: localIDs))
        #expect(AlbumBrowseSource.thisMac.matches(localCopy, localRootIDs: localIDs))
        #expect(!AlbumBrowseSource.thisMac.matches(networkCopy, localRootIDs: localIDs))
        #expect(AlbumBrowseSource.thisMac.matches(mixed, localRootIDs: localIDs))
        #expect(!AlbumBrowseSource.thisMac.matches(unknown, localRootIDs: localIDs))
        #expect(AlbumBrowseSource.folder(network).matches(networkCopy, localRootIDs: []))
        #expect(AlbumBrowseSource.folder(network).matches(mixed, localRootIDs: localIDs))
        #expect(AlbumBrowseSource.folder(unverified).matches(unknown, localRootIDs: []))
        // Losing verified access changes local filtering, not recorded root identity.
        #expect(!AlbumBrowseSource.thisMac.matches(localCopy, localRootIDs: []))
        #expect(AlbumBrowseSource.folder(local).matches(localCopy, localRootIDs: []))
    }

    @Test("Ten thousand synthetic summaries filter without media or database access")
    func largeFixture() {
        let local = StorageRootID()
        let network = StorageRootID()
        let summaries = (0..<10_000).map { index in
            AlbumBrowseSummary(hasDigitalAssets: true, storageRootIDs: index.isMultiple(of: 2) ? [local] : [network])
        }
        let localIDs: Set<StorageRootID> = [local]
        #expect(summaries.filter { AlbumBrowseSource.thisMac.matches($0, localRootIDs: localIDs) }.count == 5_000)
        #expect(summaries.filter { AlbumBrowseSource.folder(network).matches($0, localRootIDs: localIDs) }.count == 5_000)
    }
}
