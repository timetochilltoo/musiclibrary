import Foundation
import Testing
@testable import MusicApplication

@Suite("Settings transfer feedback")
@MainActor
struct SettingsTransferTasksTests {
    @Test("Archive failure releases all manual actions and retry preserves the other archive result")
    func archiveRetry() async throws {
        struct Failure: LocalizedError { var errorDescription: String? { "Archive verification failed" } }
        let tasks = SettingsTransferTasks()
        let export = try #require(tasks.start(.archiveExport) { "Export verified" })
        #expect(tasks.isRunning)
        #expect(tasks.start(.sharing) { "Must not run" } == nil)
        #expect(tasks.start(.archiveRestore) { "Must not run" } == nil)
        await export.value
        let restore = try #require(tasks.start(.archiveRestore) { throw Failure() })
        await restore.value
        #expect(!tasks.isRunning)
        #expect(tasks.archiveRestore.failure == "Archive verification failed")
        #expect(tasks.archiveExport == .succeeded("Export verified"))
        let retry = try #require(tasks.start(.archiveRestore) { "Restore verified" })
        #expect(tasks.archiveRestore == .running)
        await retry.value
        #expect(tasks.archiveRestore == .succeeded("Restore verified"))
        #expect(tasks.archiveExport == .succeeded("Export verified"))
    }

    @Test("A suspended transfer blocks duplicate and cross-category submissions")
    func busyGuard() async throws {
        let tasks = SettingsTransferTasks()
        var continuation: CheckedContinuation<Void, Never>?
        let first = try #require(tasks.start(.sharing) {
            await withCheckedContinuation { continuation = $0 }
            return "Shared revision 7"
        })
        #expect(tasks.sharing == .running)
        #expect(tasks.isRunning)
        #expect(tasks.start(.sharing) { Issue.record("Duplicate ran"); return "" } == nil)
        #expect(tasks.start(.databaseBackup) { Issue.record("Concurrent backup ran"); return "" } == nil)
        while continuation == nil { await Task.yield() }
        continuation?.resume()
        await first.value
        #expect(tasks.sharing == .succeeded("Shared revision 7"))
        #expect(tasks.databaseBackup == .idle)
        #expect(!tasks.isRunning)
    }

    @Test("Failure stays beside its action and a deliberate retry clears it")
    func retry() async throws {
        struct Failure: LocalizedError { var errorDescription: String? { "Destination unavailable" } }
        let tasks = SettingsTransferTasks()
        let failed = try #require(tasks.start(.databaseBackup) { throw Failure() })
        await failed.value
        #expect(tasks.databaseBackup.failure == "Destination unavailable")
        #expect(!tasks.isRunning)
        let retry = try #require(tasks.start(.databaseBackup) { "Backed up revision 8" })
        #expect(tasks.databaseBackup == .running)
        #expect(tasks.databaseBackup.failure == nil)
        await retry.value
        #expect(tasks.databaseBackup == .succeeded("Backed up revision 8"))
        #expect(tasks.sharing == .idle)
    }

    @Test("A later action does not overwrite the other category's feedback")
    func separateFeedback() async throws {
        let tasks = SettingsTransferTasks()
        let shared = try #require(tasks.start(.sharing) { "Shared revision 9" })
        await shared.value
        let backup = try #require(tasks.start(.databaseBackup) { "Backed up revision 9" })
        await backup.value
        #expect(tasks.sharing == .succeeded("Shared revision 9"))
        #expect(tasks.databaseBackup == .succeeded("Backed up revision 9"))
        #expect(!tasks.isRunning)
    }
}
