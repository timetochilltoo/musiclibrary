#if DEBUG
import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Synthetic recovery preview fixture safety")
@MainActor
struct FolderRecoveryPreviewFixtureTests {
    @Test("Fixture bundle guard and scenario reports preserve production isolation")
    func reports() async throws {
        #expect(throws: FolderRecoveryPreviewError.self) {
            try FolderRecoveryPreviewFixture.make(bundleIdentifier: "com.timetochilltoo.MusicLibraryMac")
        }
        let fixture = try FolderRecoveryPreviewFixture.make(bundleIdentifier: "com.timetochilltoo.MusicLibraryNavigationFixture")
        defer { fixture.close(); try? FileManager.default.removeItem(at: fixture.directory) }
        #expect(RegisteredPathSecurity.contains(fixture.directory, within: FileManager.default.temporaryDirectory))
        fixture.session.selectCandidate(fixture.candidateA)
        for mode in [FolderRecoveryPreviewFixture.Mode.mixed, .changed, .unavailable, .failure, .mixed] {
            fixture.control.mode = mode
            let run = try #require(fixture.session.verify())
            await run.value
            if mode == .failure {
                #expect(fixture.session.phase == .failed && fixture.session.completion == nil)
            } else {
                let completion = try #require(fixture.session.completion)
                #expect(completion.report.evidence.count == 8)
                #expect(completion.report.manifest.references.count == 10)
                #expect(completion.report.evidence.filter { $0.outcome == .verified }.first?.group.references.count == 2)
                #expect(completion.report.manifest.root.registeredPath == fixture.root.lastKnownPath)
                switch mode {
                case .changed: #expect(completion.freshness == .changed)
                case .unavailable:
                    if case .unavailable = completion.freshness {} else { Issue.record("Expected unavailable recheck") }
                default: #expect(completion.freshness == .unchanged)
                }
            }
            #expect(fixture.control.starts == fixture.control.releases)
        }
        #expect(fixture.control.peakAccess == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.candidateA.path).isEmpty)
        // Arbitrary file URLs cannot use the fixture permission substitute.
        fixture.session.selectCandidate(fixture.directory.deletingLastPathComponent())
        await fixture.session.verify()?.value
        #expect(fixture.session.phase == .failed && fixture.control.starts == 5)
    }

    @Test("Paused worker drains before retry and old results cannot replace a new selection")
    func controlledDrain() async throws {
        let fixture = try FolderRecoveryPreviewFixture.make(bundleIdentifier: "com.timetochilltoo.MusicLibraryNavigationFixture")
        defer { fixture.close(); try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.control.mode = .slow
        fixture.session.selectCandidate(fixture.candidateA)
        let first = try #require(fixture.session.verify())
        while !fixture.control.waiting && fixture.session.isRunning { await Task.yield() }
        #expect(fixture.control.waiting)
        fixture.control.advance()
        fixture.session.cancel()
        #expect(fixture.session.phase == .cancelling && fixture.control.releases == 0)
        #expect(fixture.session.verify() == nil)
        fixture.session.selectCandidate(fixture.candidateB)
        fixture.control.finishWorker()
        await first.value
        #expect(fixture.session.phase == .ready && fixture.session.completion == nil && fixture.session.progress == nil)
        fixture.control.mode = .mixed
        let second = try #require(fixture.session.verify())
        await second.value
        #expect(fixture.session.completion?.report.candidate.selectedPath == fixture.candidateB.path)
        #expect(fixture.control.starts == 2 && fixture.control.releases == 2 && fixture.control.peakAccess == 1)
        fixture.control.mode = .slow
        let third = try #require(fixture.session.verify())
        while !fixture.control.waiting && fixture.session.isRunning { await Task.yield() }
        fixture.close()
        await third.value
        #expect(!fixture.session.isRunning && fixture.control.starts == fixture.control.releases)
    }
}
#endif
