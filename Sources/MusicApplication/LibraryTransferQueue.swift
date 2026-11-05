import Foundation

/// Orders publication, backup and recovery across UI and background callers.
/// Cancellation of a waiter never cancels an earlier writer.
@MainActor
final class LibraryTransferQueue {
    private var tail: Task<Void, Never>?
    private var generation = 0
    private(set) var isBusy = false

    func run<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        generation += 1
        let ticket = generation
        let previous = tail
        isBusy = true
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = await task.result }
        defer {
            if generation == ticket { tail = nil; isBusy = false }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
