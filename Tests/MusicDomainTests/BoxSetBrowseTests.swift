import Foundation
import Testing
@testable import MusicDomain

@Suite("Box-set browsing")
struct BoxSetBrowseTests {
    @Test("Search includes edition/full location paths; contents keep membership order and identities")
    func browsing() {
        let room = PhysicalLocation(id: .init(), name: "Music Room", parentID: nil, sortOrder: 0, notes: nil)
        let shelf = PhysicalLocation(id: .init(), name: "Shelf", parentID: room.id, sortOrder: 0, notes: nil)
        let box = BoxSet(id: .init(), title: "Collected", editionLabel: "Japan Edition", physicalLocationID: shelf.id)
        let other = BoxSet(id: .init(), title: "Collected", editionLabel: nil, physicalLocationID: room.id)
        #expect(BoxSetBrowseSummary.matching([box, other], locations: [room, shelf], query: " japan ") == [box])
        #expect(BoxSetBrowseSummary.matching([box, other], locations: [room, shelf], query: "room › shelf") == [box])
        #expect(BoxSetBrowseSummary.matching([box, other], locations: [room, shelf], query: "").count == 2)
        #expect(BoxSetBrowseSummary.matching([box], locations: [room, shelf], query: "missing").isEmpty)
        let first = Album(id: .init(), from: .init(title: "Same title"))
        let second = Album(id: .init(), from: .init(title: "Same title"))
        #expect(BoxSetBrowseSummary.members(ids: [second.id, first.id, second.id, .init()], albums: [first, second]) == [second, first])
    }
}
