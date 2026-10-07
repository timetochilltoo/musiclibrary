import Foundation
import Testing
@testable import MusicDomain

@Suite("Location browse hierarchy")
struct LocationBrowseTests {
    @Test("Hierarchy orders siblings, distinguishes identical names and shows orphan/cyclic records")
    func hierarchy() {
        let room = PhysicalLocation(id: .init(), name: "Room", parentID: nil, sortOrder: 0, notes: nil)
        let shelf = PhysicalLocation(id: .init(), name: "Shelf", parentID: room.id, sortOrder: 1, notes: nil)
        let first = PhysicalLocation(id: .init(), name: "Shelf", parentID: room.id, sortOrder: 0, notes: nil)
        let orphan = PhysicalLocation(id: .init(), name: "Orphan", parentID: .init(), sortOrder: 0, notes: nil)
        let cycleID = PhysicalLocationID()
        let cycle = PhysicalLocation(id: cycleID, name: "Cycle", parentID: cycleID, sortOrder: 0, notes: nil)
        let summary = LocationBrowseSummary(locations: [shelf, cycle, orphan, room, first])
        #expect(summary.children(of: room.id).map(\.id) == [first.id, shelf.id])
        #expect(summary.path(of: shelf) == "Room › Shelf")
        #expect(summary.ancestors(of: cycle).count == 1)
        #expect(summary.ordered.count == 5)
        #expect(Set(summary.ordered.map(\.id)).count == 5)
        let roomIndex = summary.ordered.firstIndex { $0.id == room.id }!
        #expect(summary.ordered[roomIndex + 1].id == first.id)
    }

    @Test("Exact-location contents exclude descendants, unknown placement and boxed albums")
    func contents() {
        let room = PhysicalLocation(id: .init(), name: "Room", parentID: nil, sortOrder: 0, notes: nil)
        let shelf = PhysicalLocation(id: .init(), name: "Shelf", parentID: room.id, sortOrder: 0, notes: nil)
        let direct = Album(id: .init(), from: .init(title: "Direct", hasCD: true, physicalLocationID: room.id))
        let child = Album(id: .init(), from: .init(title: "Child", hasCD: true, physicalLocationID: shelf.id))
        let boxed = Album(id: .init(), from: .init(title: "Boxed", hasCD: true))
        let box = BoxSet(id: .init(), title: "Box", editionLabel: nil, physicalLocationID: room.id)
        let summary = LocationBrowseSummary(locations: [room, shelf])
        #expect(summary.directAlbums(at: room.id, albums: [direct, child, boxed]) == [direct])
        #expect(summary.boxes(at: room.id, boxSets: [box]) == [box])
        #expect(summary.boxes(at: shelf.id, boxSets: [box]).isEmpty)
    }
}
