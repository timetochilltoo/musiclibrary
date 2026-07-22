import Testing
import Foundation
@testable import MusicDomain

@Suite("Album validation")
struct AlbumTests {
    @Test("An album title is required")
    func titleIsRequired() {
        #expect(throws: ValidationError.requiredField("Album title")) {
            _ = try NewAlbum(title: "  ").validated()
        }
    }

    @Test("A direct physical location requires a CD")
    func directLocationRequiresCD() {
        #expect(throws: ValidationError.invalidLocationPlacement) {
            _ = try NewAlbum(title: "Album", hasCD: false, physicalLocationID: PhysicalLocationID()).validated()
        }
    }

    @Test("Edition label is included in the display title")
    func editionLabelIsDisplayed() {
        let album = Album(id: AlbumID(), from: NewAlbum(title: "Kind of Blue", editionLabel: "Japan version"))
        #expect(album.displayTitle == "Kind of Blue — Japan version")
    }

    @Test("Digital status prioritises broken assets")
    func brokenAssetsWin() {
        let summary = DigitalAvailabilitySummary.derive(
            expectedTrackCount: 2,
            assetsByTrack: [[.available], [.missing]]
        )
        #expect(summary.status == .broken)
        #expect(summary.availableTrackCount == 1)
    }

    @Test("An album with all available assets is complete")
    func completeAssetsAreComplete() {
        let summary = DigitalAvailabilitySummary.derive(
            expectedTrackCount: 2,
            assetsByTrack: [[.available], [.available]]
        )
        #expect(summary.status == .complete)
    }
}

@Suite("Playback queue")
struct PlaybackQueueTests {
    @Test("Queue advances, repeats, and preserves a Codable state")
    func queueBehaviour() throws {
        let first = TrackID(); let second = TrackID()
        var queue = PlaybackQueue(trackIDs: [first, second], currentIndex: 0)
        #expect(queue.next() == second)
        #expect(queue.next() == nil)
        queue.repeatMode = .all
        #expect(queue.next() == first)
        queue.repeatMode = .one
        #expect(queue.next() == first)
        let restored = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        #expect(restored == queue)
    }
}
