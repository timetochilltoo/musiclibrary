import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Occurrence-preserving playback shuffle")
@MainActor
struct PlaybackShuffleTests {
    @Test("Toggle retains duplicates and restores the exact playing occurrence without loading again")
    func toggles() throws {
        let namespace = "MusicLibrary.Shuffle.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: namespace))
        var requests: [URL] = []
        let controller = PlaybackController(preferences: preferences, preparation: { url, _, _ in requests.append(url) })
        defer { controller.stop(); preferences.removePersistentDomain(forName: namespace) }
        let repeated = TrackID(), other = TrackID()
        let items: [PlaylistPlaybackPlan.QueueItem] = [
            (URL(fileURLWithPath: "/synthetic/first.wav"), repeated, "First occurrence", 100, 500),
            (URL(fileURLWithPath: "/synthetic/other.wav"), other, "Other", nil, nil),
            (URL(fileURLWithPath: "/synthetic/second.wav"), repeated, "Second occurrence", 600, 900)
        ]
        controller.setRepeatMode(.one)
        try controller.play(items: items, startingAt: 2)
        for _ in 0..<10 {
            controller.toggleShuffle()
            #expect(controller.queue.trackIDs.count == 3)
            #expect(controller.queue.trackIDs.filter { $0 == repeated }.count == 2)
            #expect(controller.queue.currentIndex == 0 && controller.queue.isShuffled)
            #expect(controller.currentTitle == "Second occurrence")
            controller.toggleShuffle()
            #expect(controller.queue.trackIDs == items.map(\.trackID))
            #expect(controller.queue.currentIndex == 2 && !controller.queue.isShuffled)
        }
        #expect(requests == [items[2].url] && controller.queue.repeatMode == .one)
        try controller.playQueueEntry(at: 2, expectedTrackID: repeated)
        #expect(requests.last == items[2].url)
    }

    @Test("Shuffled start prepares once, keeps every occurrence and restores input order at its selected occurrence")
    func shuffledStart() throws {
        let namespace = "MusicLibrary.ShuffleStart.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: namespace))
        var requests: [URL] = []
        let controller = PlaybackController(preferences: preferences, preparation: { url, _, _ in requests.append(url) })
        defer { controller.stop(); preferences.removePersistentDomain(forName: namespace) }
        let repeated = TrackID()
        let items: [PlaylistPlaybackPlan.QueueItem] = (0..<5).map { number in
            (URL(fileURLWithPath: "/synthetic/\(number).wav"), number < 2 ? repeated : TrackID(), "Occurrence \(number)", number * 1000, (number + 1) * 1000)
        }
        controller.setRepeatMode(.all)
        try controller.play(items: items, startingAt: 0, shuffled: true)
        #expect(controller.queue.isShuffled && controller.queue.currentIndex == 0)
        #expect(controller.queue.trackIDs.count == items.count && controller.queue.repeatMode == .all)
        #expect(controller.queue.trackIDs.filter { $0 == repeated }.count == 2)
        #expect(requests.count == 1)
        let selected = try #require(items.firstIndex { $0.url == requests[0] })
        #expect(controller.currentTitle == items[selected].title)
        // Every shuffled occurrence retains its own tuple, even when track IDs repeat.
        for index in controller.queue.trackIDs.indices {
            try controller.playQueueEntry(at: index, expectedTrackID: controller.queue.trackIDs[index])
        }
        #expect(Set(requests.dropFirst()) == Set(items.map(\.url)))
        let lastOriginal = try #require(items.firstIndex { $0.url == requests.last })
        controller.toggleShuffle()
        #expect(controller.queue.currentIndex == lastOriginal)
        #expect(controller.queue.trackIDs == items.map(\.trackID) && !controller.queue.isShuffled)
        let data = try #require(preferences.data(forKey: "MusicLibrary.playbackQueue"))
        #expect(try JSONDecoder().decode(PlaybackQueue.self, from: data) == controller.queue)
        let before = controller.queue
        #expect(throws: (any Error).self) { try controller.play(items: [], startingAt: 0, shuffled: true) }
        #expect(controller.queue == before)
    }
}
