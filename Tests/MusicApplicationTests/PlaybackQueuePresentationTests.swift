import Testing
import MusicDomain
@testable import MusicApplication

@Suite struct PlaybackQueuePresentationTests {
    @Test func preservesQueueOrderDuplicatesAndUnavailableEntries() {
        let first = TrackID(), second = TrackID(), unavailable = TrackID()
        let queue = PlaybackQueue(trackIDs: [second, unavailable, first, second], currentIndex: 2, isShuffled: true)
        #expect(PlaybackQueuePresentation.titles(for: queue, resolvedTitles: [(first, "First"), (second, "Second")]) ==
                ["Second", "Unavailable track", "First", "Second"])
        #expect(queue.currentIndex == 2)
        #expect(queue.isShuffled)
    }

    @Test func emptyQueueHasNoRows() {
        #expect(PlaybackQueuePresentation.titles(for: PlaybackQueue(), resolvedTitles: []) == [])
    }
}
