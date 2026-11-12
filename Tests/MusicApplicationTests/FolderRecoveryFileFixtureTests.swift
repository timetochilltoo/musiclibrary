#if DEBUG
import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Disposable real-file recovery fixture")
@MainActor
struct FolderRecoveryFileFixtureTests {
    @Test("Real seeded manifests and bytes classify without mutation")
    func evidence() async throws {
        let fixture = try await FolderRecoveryFileFixture.make(bundleIdentifier: "com.timetochilltoo.MusicLibraryNavigationFixture")
        defer { fixture.close(); try? FileManager.default.removeItem(at: fixture.directory) }
        let before = try await fixture.library.folderRecoveryManifest(rootID: fixture.root.id)
        #expect(before.references.count == 5 && before.root.status == .offline && before.root.bookmarkDigest == nil)
        let report = try await FolderRecoveryVerifier.verify(.init(manifest: before), candidateRoot: fixture.candidate)
        #expect(report.evidence.count == 5)
        for (path, expected) in [("01 matching.bin", FolderRecoveryVerifier.Outcome.verified), ("02 different.bin", .differentContent),
                                 ("03 unverified.bin", .unverified), ("04 missing.bin", .missing), ("05 symlink.bin", .unsafePath)] {
            let result = try #require(report.evidence.first { $0.group.relativePath == path })
            #expect(result.outcome == expected)
            if expected == .verified || expected == .differentContent { #expect(result.actualContentHash != nil) }
            else { #expect(result.actualContentHash == nil) }
        }
        #expect(try await fixture.library.folderRecoveryManifest(rootID: fixture.root.id) == before)
        #expect(try await fixture.checkIntegrity().contains("Integrity passed"))
    }

    @Test("Bundle and picker boundary refuse unrelated URLs before security scope")
    func boundaries() async throws {
        do {
            _ = try await FolderRecoveryFileFixture.make(bundleIdentifier: "com.timetochilltoo.MusicLibraryMac")
            Issue.record("Production bundle admitted a fixture")
        } catch FolderRecoveryPreviewError.invalidFixtureBoundary {}
        let fixture = try await FolderRecoveryFileFixture.make(bundleIdentifier: "com.timetochilltoo.MusicLibraryNavigationFixture")
        defer { fixture.close(); try? FileManager.default.removeItem(at: fixture.directory) }
        for candidate in [fixture.directory, fixture.directory.deletingLastPathComponent(), URL(string: "https://example.invalid")!] {
            fixture.session.selectCandidate(candidate)
            let run = try #require(fixture.session.verify())
            await run.value
            #expect(fixture.session.phase == .failed && fixture.session.completion == nil)
        }
        #expect(try await fixture.checkIntegrity().contains("Integrity passed"))
    }
}
#endif
