import Testing
@testable import MusicApplication

@Suite("Library transfer queue")
@MainActor
struct LibraryTransferQueueTests {
    @Test("Published activity distinguishes running and waiting work and clears after cancellation")
    func activity() async throws {
        let store = LibraryStore()
        var release: CheckedContinuation<Void, Never>?
        let first = Task {
            try await store.transferQueue.run(.databaseBackup) {
                await withCheckedContinuation { release = $0 }
            }
        }
        while release == nil { await Task.yield() }
        #expect(store.transferActivity.active == .databaseBackup)
        let waiting = Task {
            try await store.transferQueue.run(.archiveRestore) { _ = Issue.record("Cancelled restore ran") }
        }
        while store.transferActivity.waiting.isEmpty { await Task.yield() }
        #expect(store.transferActivity.active == .databaseBackup)
        #expect(store.transferActivity.waiting == [.archiveRestore])
        waiting.cancel()
        release?.resume()
        try await first.value
        do { try await waiting.value; Issue.record("Expected cancellation") } catch {}
        #expect(store.transferActivity == LibraryTransferActivity())
    }

    @Test("Suspended writer finishes before later writers; failure does not poison the queue")
    func ordering() async throws {
        let queue = LibraryTransferQueue()
        var release: CheckedContinuation<Void, Never>?
        var events: [Int] = []
        let first = Task {
            try await queue.run {
                events.append(1)
                await withCheckedContinuation { release = $0 }
                events.append(2)
            }
        }
        while release == nil { await Task.yield() }
        let second = Task {
            try await queue.run { events.append(3); throw Failure.expected }
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(events == [1])
        #expect(queue.isBusy)
        release?.resume()
        try await first.value
        do { try await second.value; Issue.record("Expected failure") } catch {}
        let result = try await queue.run { events.append(4); return 42 }
        #expect(result == 42)
        #expect(events == [1, 2, 3, 4])
        #expect(!queue.isBusy)
    }

    @Test("Cancelling a waiting request skips its operation and preserves the earlier writer")
    func cancellation() async throws {
        let queue = LibraryTransferQueue()
        var release: CheckedContinuation<Void, Never>?
        var finished = false
        let first = Task {
            try await queue.run {
                await withCheckedContinuation { release = $0 }
                finished = true
            }
        }
        while release == nil { await Task.yield() }
        let cancelled = Task {
            try await queue.run { _ = Issue.record("Cancelled writer ran") }
        }
        for _ in 0..<10 { await Task.yield() }
        cancelled.cancel()
        release?.resume()
        try await first.value
        do { try await cancelled.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(finished)
        #expect(!queue.isBusy)
        #expect(try await queue.run { 7 } == 7)
    }

    private enum Failure: Error { case expected }
}
