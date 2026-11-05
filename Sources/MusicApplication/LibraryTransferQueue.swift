import Foundation

/// Orders publication, backup and recovery across UI and background callers.
/// Cancellation of a waiter never cancels an earlier writer.
@MainActor
final class LibraryTransferQueue {
    private var tail: Task<Void, Never>?
    private var generation = 0
    private(set) var activity = LibraryTransferActivity()
    var onChange: ((LibraryTransferActivity) -> Void)?
    private var waiting: [(Int, LibraryTransferActivity.Kind)] = []
    var isBusy: Bool { activity.isBusy }

    func run<Value: Sendable>(_ kind: LibraryTransferActivity.Kind = .sharing, _ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        generation += 1
        let ticket = generation
        let previous = tail
        waiting.append((ticket, kind))
        updateActivity()
        let task = Task {
            await previous?.value
            self.waiting.removeAll { $0.0 == ticket }
            defer { self.activity.active = nil; self.updateActivity() }
            try Task.checkCancellation()
            self.activity.active = kind
            self.updateActivity()
            return try await operation()
        }
        tail = Task { _ = await task.result }
        defer {
            if generation == ticket { tail = nil }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func updateActivity() {
        activity.waiting = waiting.map(\.1)
        onChange?(activity)
    }
}
