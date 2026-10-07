import Foundation
import Testing
@testable import MusicDomain

@Suite("Contributor browse summaries")
struct ContributorBrowseTests {
    @Test("Unique albums and roles do not double-count credits or merge same-name people")
    func counts() {
        let first = Contributor(id: ContributorID(), name: "Same Name", sortName: nil)
        let other = Contributor(id: ContributorID(), name: "Same Name", sortName: nil)
        let album = Album(id: AlbumID(), from: .init(title: "Fixture"))
        let composer = ContributorAlbumRole(contributorID: first.id, albumID: album.id, role: .composer)
        let summaries = ContributorBrowseSummary.index(contributors: [first, other], albums: [album], credits: [composer, composer,
            .init(contributorID: first.id, albumID: album.id, role: .performer),
            .init(contributorID: first.id, albumID: AlbumID(), role: .conductor),
            .init(contributorID: ContributorID(), albumID: album.id, role: .producer)])
        #expect(summaries.count == 2)
        #expect(summaries[first.id]?.albumIDs() == [album.id])
        #expect(summaries[first.id]?.albumIDs(role: .composer) == [album.id])
        #expect(summaries[first.id]?.albumIDs(role: .conductor).isEmpty == true)
        #expect(summaries[first.id]?.roles == [.performer, .composer])
        #expect(summaries[other.id]?.roles.isEmpty == true)
    }

    @Test("Name/sort-name search combines with roles and retains unused contributors in All Roles")
    func filtering() {
        let composer = Contributor(id: ContributorID(), name: "Renée", sortName: "Z Composer")
        let performer = Contributor(id: ContributorID(), name: "Renée", sortName: "A Performer")
        let unused = Contributor(id: ContributorID(), name: "Unused", sortName: nil)
        let album = Album(id: AlbumID(), from: .init(title: "Fixture"))
        let summaries = ContributorBrowseSummary.index(contributors: [composer, performer, unused], albums: [album], credits: [
            .init(contributorID: composer.id, albumID: album.id, role: .composer),
            .init(contributorID: performer.id, albumID: album.id, role: .performer)])
        #expect(ContributorBrowseSummary.matching([composer, performer, unused], summaries: summaries, query: " RENÉE ", role: nil).map(\.id) == [performer.id, composer.id])
        #expect(ContributorBrowseSummary.matching([composer, performer, unused], summaries: summaries, query: "composer", role: .composer) == [composer])
        #expect(ContributorBrowseSummary.matching([composer, performer, unused], summaries: summaries, query: "composer", role: .performer).isEmpty)
        #expect(ContributorBrowseSummary.matching([unused], summaries: summaries, query: "", role: nil) == [unused])
        #expect(ContributorBrowseSummary.matching([unused], summaries: summaries, query: "", role: .composer).isEmpty)
    }
}
