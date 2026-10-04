import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Playback queue selection")
@MainActor
struct PlaybackQueueSelectionTests {
    @Test("Restoration does not autoplay; explicit selection preserves order, duplicates and preferences")
    func selectionAndPersistence() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.stop(); fixture.preferences.removePersistentDomain(forName: fixture.namespace) }
        let controller = fixture.controller
        let original = controller.queue
        #expect(fixture.loader.requests.isEmpty && !controller.isLoading && !controller.isPlaying)
        try controller.playQueueEntry(at: 2, expectedTrackID: original.trackIDs[2])
        #expect(controller.queue.currentIndex == 2)
        #expect(controller.queue.trackIDs == original.trackIDs)
        #expect(controller.queue.isShuffled && controller.queue.repeatMode == .one)
        #expect(controller.currentTitle == "First" && controller.isLoading)
        let data = try #require(fixture.preferences.data(forKey: "MusicLibrary.playbackQueue"))
        #expect(try JSONDecoder().decode(PlaybackQueue.self, from: data) == controller.queue)
        #expect(fixture.loader.requests.count == 1)
        let reopened = PlaybackController(preferences: fixture.preferences, preparation: { _, _, _ in })
        #expect(reopened.queue == controller.queue)
        #expect(!reopened.isLoading && !reopened.isPlaying)
    }

    @Test("Stale identity, invalid index and unresolved restoration cannot change selection or start loading")
    func invalidAndUnresolved() throws {
        let fixture = try makeFixture()
        defer { fixture.controller.stop(); fixture.preferences.removePersistentDomain(forName: fixture.namespace) }
        let controller = fixture.controller
        let original = controller.queue
        #expect(throws: (any Error).self) { try controller.playQueueEntry(at: -1, expectedTrackID: TrackID()) }
        #expect(throws: (any Error).self) { try controller.playQueueEntry(at: 99, expectedTrackID: TrackID()) }
        #expect(throws: (any Error).self) { try controller.playQueueEntry(at: 1, expectedTrackID: original.trackIDs[0]) }
        #expect(controller.queue == original && fixture.loader.requests.isEmpty)
        let unresolved = PlaybackController(preferences: fixture.preferences, preparation: { _, _, _ in })
        unresolved.restore(items: [])
        #expect(!unresolved.canPlayQueueEntry(at: 0))
        #expect(throws: (any Error).self) { try unresolved.playQueueEntry(at: 0, expectedTrackID: original.trackIDs[0]) }
        #expect(unresolved.queue.trackIDs == original.trackIDs && !unresolved.isLoading)
    }

    @Test("Newer selection rejects older loading progress and failure, including repeated track IDs")
    func latestSelectionWins() async throws {
        let fixture = try makeFixture()
        defer { fixture.controller.stop(); fixture.preferences.removePersistentDomain(forName: fixture.namespace) }
        let controller = fixture.controller
        let first = controller.queue.trackIDs[0]
        try controller.playQueueEntry(at: 0, expectedTrackID: first)
        try controller.playQueueEntry(at: 2, expectedTrackID: first)
        fixture.loader.requests[1].progress(.init(fractionCompleted: 0.7, estimatedTimeRemaining: 4, isFinalizing: false))
        try await waitUntil { controller.loadingProgress == 0.7 }
        fixture.loader.requests[0].progress(.init(fractionCompleted: 0.1, estimatedTimeRemaining: 99, isFinalizing: true))
        fixture.loader.requests[0].completion(.failure("Old request failure"))
        // Wait for the latest callback to publish before checking the selection.
        fixture.loader.requests[1].progress(.init(fractionCompleted: 0.8, estimatedTimeRemaining: 3, isFinalizing: false))
        try await waitUntil { controller.loadingProgress == 0.8 }
        #expect(controller.queue.currentIndex == 2 && controller.currentTrackID == first)
        #expect(controller.currentTitle == "First" && controller.isLoading && controller.errorMessage == nil)
        #expect(controller.loadingEstimatedTimeRemaining == 3 && !controller.isFinalizingLoad)
        fixture.loader.requests[1].completion(.failure("Current request failure"))
        try await waitUntil { controller.errorMessage == "Current request failure" }
        #expect(!controller.isLoading && controller.queue.currentIndex == 2)
        try controller.playQueueEntry(at: 1, expectedTrackID: controller.queue.trackIDs[1])
        #expect(controller.currentTitle == "Second" && controller.errorMessage == nil && controller.isLoading)
        #expect(controller.queue.repeatMode == .one && controller.queue.isShuffled)
    }

    @Test("Stop invalidates pending queue selection callbacks and retains the queue")
    func stopDuringSelection() async throws {
        let fixture = try makeFixture()
        defer { fixture.preferences.removePersistentDomain(forName: fixture.namespace) }
        let controller = fixture.controller
        try controller.playQueueEntry(at: 1, expectedTrackID: controller.queue.trackIDs[1])
        let selected = controller.queue
        controller.stop()
        fixture.loader.requests[0].progress(.init(fractionCompleted: 0.5, estimatedTimeRemaining: 2, isFinalizing: false))
        fixture.loader.requests[0].completion(.failure("Cancelled request failure"))
        // Allow callbacks to publish without ever preparing or playing actual media.
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.queue == selected && !controller.isLoading && !controller.isPlaying)
        #expect(controller.loadingProgress == nil && controller.errorMessage == nil)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(predicate(), "Playback callback did not settle")
    }

    private func makeFixture() throws -> (namespace: String, preferences: UserDefaults, controller: PlaybackController, loader: ControlledPreparation) {
        let namespace = "MusicLibrary.QueueSelection.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: namespace))
        let first = TrackID(), second = TrackID()
        let queue = PlaybackQueue(trackIDs: [first, second, first], currentIndex: 0, repeatMode: .one, isShuffled: true)
        preferences.set(try JSONEncoder().encode(queue), forKey: "MusicLibrary.playbackQueue")
        let loader = ControlledPreparation()
        let controller = PlaybackController(preferences: preferences, preparation: { url, progress, completion in
            loader.requests.append(.init(url: url, progress: progress, completion: completion))
        })
        // These URLs are labels only; injected preparation and disabled preloading never open them.
        let directory = FileManager.default.temporaryDirectory.appending(path: namespace)
        controller.restore(items: [
            (directory.appending(path: "first.wav"), first, "First", 100, 500),
            (directory.appending(path: "second.wav"), second, "Second", nil, nil),
            (directory.appending(path: "first.wav"), first, "First", 100, 500)
        ])
        return (namespace, preferences, controller, loader)
    }
}

@MainActor
private final class ControlledPreparation {
    struct Request {
        let url: URL
        let progress: @Sendable (PlaybackPreparationProgress) -> Void
        let completion: @Sendable (PreparedAudioResult) -> Void
    }
    var requests: [Request] = []
}
