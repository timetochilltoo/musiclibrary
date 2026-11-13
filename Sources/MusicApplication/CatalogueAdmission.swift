import Foundation

/// Operation lifetime coordination. LibraryStore uses this for a partial set
/// of ordinary operations; production maintenance reservation is not enabled.
/// Ordinary users share admission; maintenance closes admission and waits for
/// every admitted user before entering. Queue services must acquire their queue
/// turn first. Never await maintenance from inside an ordinary leased operation.
@MainActor
final class CatalogueAdmission {
    enum Failure: Error, LocalizedError, Equatable, Sendable {
        case maintenancePending, reviewRequired, invalidContext
        var errorDescription: String? {
            switch self {
            case .maintenancePending: "Wait for catalogue maintenance to finish, then try again."
            case .reviewRequired: "Catalogue recovery needs review before more work can start."
            case .invalidContext: "The catalogue operation has ended or belongs to another session."
            }
        }
    }
    enum Phase: Equatable, Sendable { case open, draining, exclusive, reviewRequired }
    struct Context: Equatable, Sendable {
        fileprivate enum Kind: Sendable { case ordinary, maintenance }
        fileprivate let owner: UUID
        fileprivate let id: UUID
        fileprivate let kind: Kind
    }
    private struct Waiter {
        let id: UUID
        var continuation: CheckedContinuation<Context, any Error>?
    }
    private let owner = UUID()
    private var users: Set<UUID> = []
    private var waiters: [Waiter] = []
    private var exclusive: UUID?
    private var needsReview = false

    var phase: Phase {
        if needsReview { return .reviewRequired }
        if exclusive != nil { return .exclusive }
        return waiters.isEmpty ? .open : .draining
    }
    var activeOperationCount: Int { users.count }
    var waitingMaintenanceCount: Int { waiters.count }

    /// Context reuse lets an admitted operation finish nested helpers while
    /// admission is draining. It does not extend ownership beyond the outer scope.
    /// An awaited worker must finish all resource use before this scope returns.
    func withOperation<Value: Sendable>(using context: Context? = nil,
        _ operation: @MainActor (Context) async throws -> Value) async throws -> Value {
        if let context {
            try validate(context)
            return try await operation(context)
        }
        try Task.checkCancellation()
        if needsReview { throw Failure.reviewRequired }
        guard exclusive == nil, waiters.isEmpty else { throw Failure.maintenancePending }
        let id = UUID()
        users.insert(id)
        let context = Context(owner: owner, id: id, kind: .ordinary)
        defer { users.remove(id); advance() }
        return try await operation(context)
    }

    /// Cancellation requests never revoke resource ownership from a running
    /// operation. A cancelled waiter is removed; a granted/active owner releases
    /// only as its scope unwinds, even if its worker ignores cancellation.
    /// Once entered, the body owns safe cancellation/rollback policy; there is
    /// no automatic post-body cancellation error after a successful commit.
    func withMaintenance<Value: Sendable>(
        _ operation: @MainActor (Context) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if needsReview { throw Failure.reviewRequired }
        let id = UUID()
        // Reserve before any await, independently of the async continuation
        // helper's executor behavior. An unattached head also blocks admission.
        waiters.append(.init(id: id, continuation: nil))
        let context = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Context, any Error>) in
                guard !Task.isCancelled else {
                    cancelWaiting(id)
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if needsReview { continuation.resume(throwing: Failure.reviewRequired); return }
                guard let index = waiters.firstIndex(where: { $0.id == id }) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[index].continuation = continuation
                advance()
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiting(id) }
        }
        defer { releaseMaintenance(context) }
        // A cancellation racing with the grant must not enter the operation.
        try Task.checkCancellation()
        return try await operation(context)
    }

    /// Validates membership, not cancellation: admitted cleanup/finalization may
    /// still need its context after cancellation. There is no TaskLocal bypass.
    func validate(_ context: Context) throws {
        guard context.owner == owner else { throw Failure.invalidContext }
        switch context.kind {
        case .ordinary: guard users.contains(context.id) else { throw Failure.invalidContext }
        case .maintenance: guard exclusive == context.id else { throw Failure.invalidContext }
        }
    }

    /// Only the exclusive owner can fail closed. It retains its own cleanup
    /// context until it returns, while queued/new admissions are refused.
    /// Reopening after incomplete recovery requires a separate reviewed lifecycle.
    func requireReview(using context: Context) throws {
        try validate(context)
        guard context.kind == .maintenance else { throw Failure.invalidContext }
        needsReview = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.continuation?.resume(throwing: Failure.reviewRequired) }
    }

    private func advance() {
        guard !needsReview, exclusive == nil, users.isEmpty,
              let continuation = waiters.first?.continuation else { return }
        let next = waiters.removeFirst()
        exclusive = next.id
        continuation.resume(returning: .init(owner: owner, id: next.id, kind: .maintenance))
    }
    private func cancelWaiting(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let cancelled = waiters.remove(at: index)
        cancelled.continuation?.resume(throwing: CancellationError())
        advance()
    }
    private func releaseMaintenance(_ context: Context) {
        guard context.owner == owner, exclusive == context.id else { return }
        exclusive = nil
        // Grant the next queued owner synchronously; ordinary users cannot slip
        // between consecutive maintenance reservations.
        advance()
    }
}
