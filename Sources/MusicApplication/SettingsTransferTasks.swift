import Combine
import Foundation

/// Session-only feedback for explicit Settings actions. This does not schedule or
/// serialize background publication, and never owns a destination or a database.
@MainActor
public final class SettingsTransferTasks: ObservableObject {
    public enum Kind: Sendable { case sharing, databaseBackup }
    public enum State: Equatable, Sendable {
        case idle, running, succeeded(String), failed(String)

        public var failure: String? {
            if case let .failed(message) = self { message } else { nil }
        }
    }

    @Published public private(set) var sharing: State = .idle
    @Published public private(set) var databaseBackup: State = .idle
    public var isRunning: Bool { sharing == .running || databaseBackup == .running }

    public init() {}

    /// Set the guard synchronously, before creating the task, so repeated clicks
    /// cannot queue multiple transfers while the main actor is suspended.
    @discardableResult
    public func start(_ kind: Kind, operation: @escaping @MainActor () async throws -> String) -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        set(.running, for: kind)
        return Task {
            do { set(.succeeded(try await operation()), for: kind) }
            catch { set(.failed(error.localizedDescription), for: kind) }
        }
    }

    private func set(_ state: State, for kind: Kind) {
        switch kind {
        case .sharing: sharing = state
        case .databaseBackup: databaseBackup = state
        }
    }
}
