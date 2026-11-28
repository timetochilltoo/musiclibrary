import Foundation
import Observation

public struct SnapshotRefreshResult: Sendable {
    public let updated: Bool
    public let catalogue: ReadOnlyCatalogue?
    public let verifiedAt: Date?
}

@MainActor
@Observable
public final class SnapshotRefresh {
    public private(set) var isRefreshing = false
    private let operation: @Sendable (URL) async throws -> SnapshotRefreshResult

    public convenience init(cacheDirectory: URL) {
        self.init { source in
            try Self.perform(from: source, cacheDirectory: cacheDirectory)
        }
    }

    init(operation: @escaping @Sendable (URL) async throws -> SnapshotRefreshResult) {
        self.operation = operation
    }

    nonisolated static func perform(from source: URL, cacheDirectory: URL) throws -> SnapshotRefreshResult {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let client = SnapshotClient(cacheDirectory: cacheDirectory)
        let result = try client.refreshCatalogue(from: source)
        return SnapshotRefreshResult(
            updated: result.updated,
            catalogue: try result.catalogue ?? client.localCatalogue(),
            verifiedAt: try? client.localManifestModificationDate()
        )
    }

    @discardableResult
    public func start(
        from source: URL,
        completion: @escaping @MainActor (Result<SnapshotRefreshResult, any Error>) -> Void
    ) -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        isRefreshing = true
        let operation = operation
        let worker = Task.detached(priority: .userInitiated) { try await operation(source) }
        return Task {
            let result = await worker.result
            isRefreshing = false
            completion(result)
        }
    }
}
