import Foundation
import Testing
@testable import MusicApplication

@Suite("Recovery transfer coordination")
@MainActor
struct RecoveryTransferCoordinationTests {
    @Test("Every recovery entry point waits for an active transfer before validating resources", arguments: 0..<5)
    func recoveryWaits(action: Int) async throws {
        // Never start the store: no Application Support or personal preferences.
        let store = LibraryStore()
        let unused = URL(fileURLWithPath: "/unused-test-resource")
        var release: CheckedContinuation<Void, Never>?
        let writer = Task {
            try await store.transferQueue.run {
                await withCheckedContinuation { release = $0 }
            }
        }
        while release == nil { await Task.yield() }
        var completed = false
        let recovery = Task {
            defer { completed = true }
            do {
                switch action {
                case 0: _ = try await store.exportCompleteCatalogueArchive(to: unused)
                case 1: try await store.restoreCompleteCatalogueArchive(from: unused)
                case 2: _ = try await store.resetCatalogue(confirmation: "RESET")
                case 3: try await store.restoreMasterBackup(from: unused)
                default: _ = try await store.performCatalogueCleanup(.init())
                }
                Issue.record("Unstarted store should refuse recovery")
            } catch {}
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!completed)
        release?.resume()
        try await writer.value
        await recovery.value
        #expect(completed)
        #expect(!store.transferQueue.isBusy)
        #expect(try await store.transferQueue.run { 1 } == 1)
    }
}
