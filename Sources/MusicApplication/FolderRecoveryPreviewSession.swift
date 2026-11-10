import Combine
import Foundation
import MusicDomain

public enum FolderRecoveryPreviewError: Error, LocalizedError, Sendable {
    case permissionUnavailable
    case invalidManifest
    case invalidFixtureBoundary

    public var errorDescription: String? {
        switch self {
        case .permissionUnavailable: "Permission to read the selected candidate folder was not available. Choose the folder again."
        case .invalidManifest: "The registered folder could not be captured consistently. Reopen the preview and try again."
        case .invalidFixtureBoundary: "Preview fixtures require a directory inside their disposable temporary root."
        }
    }
}

/// One preview owns one run. Selection is inert; Verify explicitly acquires read access.
/// No operation in this session updates a folder association or persists a bookmark.
@MainActor
public final class FolderRecoveryPreviewSession: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case noSelection, ready, capturing, verifying, checkingCatalogue, finished, failed, cancelling, cancelled
    }
    public enum Freshness: Equatable, Sendable {
        /// Equal when rechecked; not a guarantee against subsequent changes.
        case unchanged
        case changed
        case unavailable(String)
    }
    public struct Completion: Equatable, Sendable {
        public let report: FolderRecoveryVerifier.Report
        public let freshness: Freshness
    }
    @Published public private(set) var candidateURL: URL?
    @Published public private(set) var phase: Phase = .noSelection
    @Published public private(set) var progress: FolderRecoveryVerifier.Progress?
    @Published public private(set) var completion: Completion?
    @Published public private(set) var errorMessage: String?
    public let rootID: StorageRootID
    public var isRunning: Bool { activeRunID != nil }

    struct ProgressSink: Sendable {
        let send: @Sendable (FolderRecoveryVerifier.Progress) -> Void
    }
    struct Dependencies {
        let loadManifest: @MainActor () async throws -> FolderRecoveryManifest
        let beginAccess: @MainActor (URL) throws -> FolderRecoveryReadAccess
        let verify: @MainActor (FolderRecoveryReferencePlan, URL, ProgressSink) async throws -> FolderRecoveryVerifier.Report
    }
    private let dependencies: Dependencies
    private var selectionID = UUID()
    private var activeRunID: UUID?
    private var restingPhase: Phase = .noSelection
    private var task: Task<Void, Never>?

    public convenience init(library: LibraryStore, rootID: StorageRootID) {
        self.init(rootID: rootID, dependencies: .init(
            loadManifest: { try await library.folderRecoveryManifest(rootID: rootID) },
            beginAccess: { try FolderRecoveryReadAccess.securityScoped($0) },
            verify: { plan, url, sink in
                try await FolderRecoveryVerifier.verify(plan, candidateRoot: url, onProgress: sink.send)
            }
        ))
    }

    init(rootID: StorageRootID, dependencies: Dependencies) {
        self.rootID = rootID
        self.dependencies = dependencies
    }

    deinit { task?.cancel() }

    public func selectCandidate(_ url: URL?) {
        selectionID = UUID()
        task?.cancel()
        candidateURL = url
        completion = nil; progress = nil; errorMessage = nil
        restingPhase = url == nil ? .noSelection : .ready
        phase = activeRunID == nil ? restingPhase : .cancelling
    }

    public func cancel() {
        selectionID = UUID()
        task?.cancel()
        completion = nil; progress = nil; errorMessage = nil
        restingPhase = candidateURL == nil ? .noSelection : .cancelled
        phase = activeRunID == nil ? restingPhase : .cancelling
    }

    /// A cancelled run must unwind before another run can acquire permission.
    @discardableResult
    public func verify() -> Task<Void, Never>? {
        guard activeRunID == nil, let url = candidateURL else { return nil }
        let run = UUID()
        let selection = selectionID
        let expectedRoot = rootID
        let operations = dependencies
        activeRunID = run
        phase = .capturing
        completion = nil; progress = nil; errorMessage = nil
        let operation = Task { [weak self] in
            defer { self?.finish(run: run, selection: selection) }
            do {
                try Task.checkCancellation()
                guard self?.accepts(run: run, selection: selection) == true else { throw CancellationError() }
                let manifest = try await operations.loadManifest()
                try Task.checkCancellation()
                guard self?.accepts(run: run, selection: selection) == true else { throw CancellationError() }
                guard manifest.root.id == expectedRoot else { throw FolderRecoveryPreviewError.invalidManifest }
                let access = try operations.beginAccess(url)
                defer { access.end() }
                try Task.checkCancellation()
                guard self?.accepts(run: run, selection: selection) == true else { throw CancellationError() }
                self?.phase = .verifying
                let updates = AsyncStream<FolderRecoveryVerifier.Progress>.makeStream(bufferingPolicy: .bufferingNewest(1))
                let monitor = Task { [weak self] in
                    for await update in updates.stream {
                        guard !Task.isCancelled else { return }
                        self?.receive(update, run: run, selection: selection)
                    }
                }
                defer { updates.continuation.finish(); monitor.cancel() }
                let report = try await operations.verify(.init(manifest: manifest), access.url,
                    .init(send: { updates.continuation.yield($0) }))
                updates.continuation.finish()
                await monitor.value
                try Task.checkCancellation()
                guard self?.accepts(run: run, selection: selection) == true else { throw CancellationError() }
                guard report.manifest == manifest else { throw FolderRecoveryPreviewError.invalidManifest }
                self?.phase = .checkingCatalogue
                let freshness: Freshness
                do {
                    let current = try await operations.loadManifest()
                    try Task.checkCancellation()
                    freshness = current == manifest ? .unchanged : .changed
                } catch is CancellationError { throw CancellationError() }
                catch { freshness = .unavailable(error.localizedDescription) }
                try Task.checkCancellation()
                guard self?.accepts(run: run, selection: selection) == true else { throw CancellationError() }
                self?.completion = .init(report: report, freshness: freshness)
                self?.phase = .finished
            } catch is CancellationError {
                if self?.accepts(run: run, selection: selection) == true { self?.phase = .cancelled }
            } catch {
                if self?.accepts(run: run, selection: selection) == true {
                    self?.errorMessage = error.localizedDescription
                    self?.phase = .failed
                }
            }
        }
        task = operation
        return operation
    }

    private func accepts(run: UUID, selection: UUID) -> Bool { activeRunID == run && selectionID == selection }
    private func receive(_ update: FolderRecoveryVerifier.Progress, run: UUID, selection: UUID) {
        guard accepts(run: run, selection: selection), phase == .verifying else { return }
        progress = update
    }
    private func finish(run: UUID, selection: UUID) {
        guard activeRunID == run else { return }
        task = nil; activeRunID = nil
        if selectionID != selection || phase == .cancelling { phase = restingPhase }
    }
}

/// Balanced operation-scoped permission. Only the internal fixture factory can
/// substitute access, and that factory refuses paths outside a temporary child.
@MainActor
final class FolderRecoveryReadAccess {
    let url: URL
    private var release: (() -> Void)?
    private init(url: URL, release: @escaping () -> Void) { self.url = url; self.release = release }
    func end() { let action = release; release = nil; action?() }

    static func securityScoped(_ url: URL) throws -> FolderRecoveryReadAccess {
        guard url.isFileURL, !url.path.contains("\0"), url.startAccessingSecurityScopedResource() else {
            throw FolderRecoveryPreviewError.permissionUnavailable
        }
        return .init(url: url, release: { url.stopAccessingSecurityScopedResource() })
    }

    static func fixture(_ url: URL, within root: URL, onEnd: @escaping () -> Void) throws -> FolderRecoveryReadAccess {
        guard url.isFileURL, root.isFileURL, !url.path.contains("\0"), !root.path.contains("\0"),
              RegisteredPathSecurity.relativePath(of: root, within: FileManager.default.temporaryDirectory)?.isEmpty == false,
              RegisteredPathSecurity.contains(url, within: root) else { throw FolderRecoveryPreviewError.invalidFixtureBoundary }
        return .init(url: url, release: onEnd)
    }
}
