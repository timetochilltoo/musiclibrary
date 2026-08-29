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

    @Test("A physical-only album can store a known location without digital assets")
    func physicalOnlyKnownLocation() throws {
        let locationID = PhysicalLocationID()
        let draft = try NewAlbum(
            title: "Physical edition",
            hasCD: true,
            physicalLocationID: locationID,
            physicalNote: "Shelf 4"
        ).validated()
        #expect(draft.hasCD)
        #expect(draft.physicalLocationID == locationID)
        #expect(draft.physicalNote == "Shelf 4")
        #expect(!draft.isPhysicalLocationUnknown)
        #expect(DigitalAvailabilitySummary.derive(expectedTrackCount: 0, assetsByTrack: []).status == .none)
    }

    @Test("A physical-only album can leave its location unknown")
    func physicalOnlyUnknownLocation() throws {
        let draft = try NewAlbum(
            title: "Unassigned physical edition",
            hasCD: true,
            isPhysicalLocationUnknown: true
        ).validated()
        #expect(draft.physicalLocationID == nil)
        #expect(draft.isPhysicalLocationUnknown)
    }

    @Test("Edition label is included in the display title")
    func editionLabelIsDisplayed() {
        let album = Album(id: AlbumID(), from: NewAlbum(title: "Kind of Blue", editionLabel: "Japan version"))
        #expect(album.displayTitle == "Kind of Blue — Japan version")
    }

    @Test("A new album contributor credit trims names and requires a contributor")
    func newAlbumContributorValidation() throws {
        let credit = try NewAlbumContributorCredit(
            name: "  Glenn Gould  ",
            role: .performer,
            creditedName: "  Gould  "
        ).validated()
        #expect(credit.name == "Glenn Gould")
        #expect(credit.creditedName == "Gould")
        #expect(throws: ValidationError.requiredField("Contributor name")) {
            try NewAlbumContributorCredit(name: "  ", role: .albumArtist).validated()
        }
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
        #expect(queue.skipForward() == second)
        let restored = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        #expect(restored == queue)
    }

    @Test("Starting a new queue clears an earlier shuffle state")
    func replacingQueueClearsShuffle() {
        var queue = PlaybackQueue(trackIDs: [TrackID()], currentIndex: 0, isShuffled: true)
        queue.replace(with: [TrackID(), TrackID()], startingAt: 1)
        #expect(!queue.isShuffled)
        #expect(queue.currentIndex == 1)
    }
}
