import Combine
import CryptoKit
import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Permission-scoped recovery preview session")
@MainActor
struct FolderRecoveryPreviewSessionTests {
    @Test("Selection is inert and permission failure starts no verifier")
    func permissionDenial() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let snapshot = manifest()
        var loads = 0, attempts = 0, verifications = 0
        let session = FolderRecoveryPreviewSession(rootID: snapshot.root.id, dependencies: .init(
            loadManifest: { loads += 1; return snapshot },
            beginAccess: { _ in attempts += 1; throw FolderRecoveryPreviewError.permissionUnavailable },
            verify: { plan, url, _ in verifications += 1; return report(plan, url) }
        ))
        #expect(session.verify() == nil)
        session.selectCandidate(fixture.first)
        #expect(session.phase == .ready && loads == 0 && attempts == 0)
        let run = try #require(session.verify())
        await run.value
        #expect(session.phase == .failed && session.errorMessage != nil)
        #expect(session.completion == nil && !session.isRunning)
        #expect(loads == 1 && attempts == 1 && verifications == 0)
        #expect(session.candidateURL == fixture.first)
    }

    @Test("Real verification detects hash changes even without revision changes", arguments: [false, true])
    func fullManifestFreshness(changeHash: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data(repeating: 3, count: 600_000)
        try bytes.write(to: fixture.first.appending(path: "file.bin"))
        let database = try MusicDatabase(url: fixture.base.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Original", lastKnownPath: fixture.base.appending(path: "original").path, bookmarkData: Data([1])))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "Synthetic reference only")
        try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: "file.bin", fileName: "file.bin", contentTypeIdentifier: "org.xiph.flac", fileSize: Int64(bytes.count), modifiedAt: nil))
        let candidate = try #require(await database.importCandidates(batchID: batch.id).first)
        try await database.saveEmbeddedMetadata(.init(title: "Synthetic track", albumTitle: "Synthetic album", artist: nil, albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: 1000, rawTags: [:]), for: candidate.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Synthetic album", artist: nil, discCount: 1, confidence: 1, candidateIDs: [candidate.id])])
        let proposal = try #require(await database.importReleaseProposals(batchID: batch.id).first)
        let album = try await database.confirmImportReleaseProposal(proposal.id)
        let asset = try #require(await database.digitalAssetIDs(albumID: album).first)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try await database.recordAssetFingerprint(asset, contentHash: hash, quickSignature: "fixture")
        try await database.updateStorageRootAccess(root.id, status: .offline)
        let rootsBefore = try await database.storageRoots()
        let revision = try await database.currentRevision()
        let library = LibraryStore(database: database)
        let balance = Balance(fixture.base)
        let session = FolderRecoveryPreviewSession(rootID: root.id, dependencies: .init(
            loadManifest: { try await library.folderRecoveryManifest(rootID: root.id) },
            beginAccess: { try balance.begin($0) },
            verify: { plan, url, sink in
                #expect(balance.active == 1)
                let evidence = try await FolderRecoveryVerifier.verify(plan, candidateRoot: url, onProgress: sink.send)
                if changeHash { try await database.recordAssetFingerprint(asset, contentHash: String(repeating: "b", count: 64), quickSignature: "changed") }
                return evidence
            }
        ))
        session.selectCandidate(fixture.first)
        let run = try #require(session.verify())
        await run.value
        let completed = try #require(session.completion)
        #expect(session.phase == .finished && !session.isRunning)
        #expect(completed.report.evidence.first?.outcome == .verified)
        #expect(completed.report.manifest.references.first?.expectedContentHash == hash)
        #expect(completed.freshness == (changeHash ? .changed : .unchanged))
        #expect(balance.begins == 1 && balance.ends == 1 && balance.active == 0)
        #expect(session.progress?.completedGroups == 1)
        #expect(try await database.currentRevision() == revision)
        #expect(try await database.storageRoots() == rootsBefore)
        #expect(try Data(contentsOf: fixture.first.appending(path: "file.bin")) == bytes)
    }

    @Test("Superseding selection discards late progress/results and waits for access to drain")
    func supersedingSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let snapshot = manifest()
        let balance = Balance(fixture.base)
        let gate = Gate()
        var oldSink: FolderRecoveryPreviewSession.ProgressSink?
        var attempts = 0
        let session = FolderRecoveryPreviewSession(rootID: snapshot.root.id, dependencies: .init(
            loadManifest: { snapshot }, beginAccess: { try balance.begin($0) },
            verify: { plan, url, sink in
                attempts += 1
                if attempts == 1 { oldSink = sink; await gate.hold() }
                return report(plan, url)
            }
        ))
        session.selectCandidate(fixture.first)
        var reentrantAccepted = false
        let observation = session.$phase.sink { phase in
            if phase == .capturing && session.verify() != nil { reentrantAccepted = true }
        }
        let first = try #require(session.verify())
        while !gate.started && session.isRunning { await Task.yield() }
        #expect(gate.started && !reentrantAccepted)
        #expect(session.verify() == nil)
        session.selectCandidate(fixture.second)
        #expect(session.phase == .cancelling && balance.ends == 0)
        #expect(session.verify() == nil)
        oldSink?.send(.init(completedGroups: 8, totalGroups: 8, currentRelativePath: "old", bytesRead: 999))
        gate.resume()
        await first.value
        #expect(session.phase == .ready && session.completion == nil && session.progress == nil)
        #expect(balance.ends == 1 && balance.active == 0)
        let second = try #require(session.verify())
        await second.value
        oldSink?.send(.init(completedGroups: 9, totalGroups: 9, currentRelativePath: "late", bytesRead: 999))
        await Task.yield()
        #expect(session.completion?.report.candidate.selectedPath == fixture.second.path)
        #expect(session.progress == nil && balance.peak == 1)
        #expect(balance.begins == 2 && balance.ends == 2)
        withExtendedLifetime(observation) {}
    }

    @Test("Cancel keeps access until an uncooperative worker stops")
    func cancellationDrain() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let snapshot = manifest()
        let balance = Balance(fixture.base)
        let gate = Gate()
        let session = FolderRecoveryPreviewSession(rootID: snapshot.root.id, dependencies: .init(
            loadManifest: { snapshot }, beginAccess: { try balance.begin($0) },
            verify: { plan, url, _ in await gate.hold(); return report(plan, url) }
        ))
        session.selectCandidate(fixture.first)
        let run = try #require(session.verify())
        while !gate.started && session.isRunning { await Task.yield() }
        #expect(gate.started)
        session.cancel()
        #expect(session.phase == .cancelling && balance.active == 1 && balance.ends == 0)
        #expect(session.verify() == nil)
        gate.resume()
        await run.value
        #expect(session.phase == .cancelled && session.completion == nil && !session.isRunning)
        #expect(balance.active == 0 && balance.ends == 1)
    }

    @Test("Worker failure releases access and retry clears local failure")
    func failureAndRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let snapshot = manifest()
        let balance = Balance(fixture.base)
        var attempts = 0
        let session = FolderRecoveryPreviewSession(rootID: snapshot.root.id, dependencies: .init(
            loadManifest: { snapshot }, beginAccess: { try balance.begin($0) },
            verify: { plan, url, _ in
                attempts += 1
                if attempts == 1 { throw FolderRecoveryVerificationError.candidateRootChanged }
                return report(plan, url)
            }
        ))
        session.selectCandidate(fixture.first)
        await session.verify()?.value
        #expect(session.phase == .failed && session.errorMessage != nil)
        #expect(balance.ends == 1 && balance.active == 0)
        let retry = try #require(session.verify())
        #expect(session.errorMessage == nil && session.completion == nil)
        await retry.value
        #expect(session.phase == .finished && session.completion?.freshness == .unchanged)
        #expect(balance.ends == 2 && balance.peak == 1)
    }

    @Test("Initial capture failure refuses access; recheck failure retains historical evidence", arguments: [true, false])
    func manifestFailure(initial: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let snapshot = manifest()
        let balance = Balance(fixture.base)
        var loads = 0
        let session = FolderRecoveryPreviewSession(rootID: snapshot.root.id, dependencies: .init(
            loadManifest: {
                loads += 1
                if loads == (initial ? 1 : 2) { throw DatabaseError.notFound("Storage root") }
                return snapshot
            }, beginAccess: { try balance.begin($0) },
            verify: { plan, url, _ in report(plan, url) }
        ))
        session.selectCandidate(fixture.first)
        await session.verify()?.value
        if initial {
            #expect(session.phase == .failed && session.completion == nil && balance.begins == 0)
        } else {
            #expect(session.phase == .finished && session.errorMessage == nil)
            let completion = try #require(session.completion)
            if case .unavailable = completion.freshness {} else { Issue.record("Failed recheck appeared current") }
            #expect(completion.report.manifest == snapshot && balance.ends == 1)
        }
        #expect(!session.isRunning && balance.active == 0)
    }

    @Test("Fixture access refuses broad/outside roots and releases exactly once")
    func accessBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var releases = 0
        let access = try FolderRecoveryReadAccess.fixture(fixture.first, within: fixture.base, onEnd: { releases += 1 })
        access.end(); access.end()
        #expect(releases == 1)
        for (url, root) in [(fixture.first, FileManager.default.temporaryDirectory), (fixture.base.deletingLastPathComponent(), fixture.base)] {
            do { _ = try FolderRecoveryReadAccess.fixture(url, within: root, onEnd: {}); Issue.record("Invalid fixture access accepted") } catch {}
        }
        do { _ = try FolderRecoveryReadAccess.securityScoped(try #require(URL(string: "https://example.invalid"))); Issue.record("Non-file selection accepted") } catch {}
    }

    @Test("Session disposal cancels work and releases access after the worker drains")
    func disposal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let snapshot = manifest()
        let balance = Balance(fixture.base)
        let gate = Gate()
        var session: FolderRecoveryPreviewSession? = .init(rootID: snapshot.root.id, dependencies: .init(
            loadManifest: { snapshot }, beginAccess: { try balance.begin($0) },
            verify: { plan, url, _ in await gate.hold(); return report(plan, url) }
        ))
        session?.selectCandidate(fixture.first)
        let run = try #require(session?.verify())
        while !gate.started && session?.isRunning == true { await Task.yield() }
        #expect(gate.started)
        weak let weakSession = session
        session = nil
        #expect(weakSession == nil && balance.active == 1)
        gate.resume()
        await run.value
        #expect(balance.active == 0 && balance.ends == 1)
    }

    private func manifest() -> FolderRecoveryManifest {
        .init(root: .init(id: .init(), displayName: "Synthetic original", registeredPath: "/original-not-read", volumeIdentifier: nil, scope: .localOnly, status: .offline, bookmarkDigest: nil), catalogueRevision: 7, references: [])
    }
    private func report(_ plan: FolderRecoveryReferencePlan, _ url: URL) -> FolderRecoveryVerifier.Report {
        .init(manifest: plan.manifest, candidate: .init(selectedPath: url.path, resolvedPath: url.path, device: 0, inode: 0), evidence: [])
    }
    private struct Fixture {
        let base: URL
        var first: URL { base.appending(path: "first") }
        var second: URL { base.appending(path: "second") }
        init() throws {
            base = FileManager.default.temporaryDirectory.appending(path: "RecoveryPreviewSession-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: base) }
    }
    @MainActor private final class Gate {
        var started = false
        private var continuation: CheckedContinuation<Void, Never>?
        func hold() async { await withCheckedContinuation { continuation = $0; started = true } }
        func resume() { let release = continuation; continuation = nil; release?.resume() }
    }
    @MainActor private final class Balance {
        let root: URL
        var begins = 0, ends = 0, active = 0, peak = 0
        init(_ root: URL) { self.root = root }
        func begin(_ url: URL) throws -> FolderRecoveryReadAccess {
            let access = try FolderRecoveryReadAccess.fixture(url, within: root, onEnd: { self.ends += 1; self.active -= 1 })
            begins += 1; active += 1; peak = max(peak, active)
            return access
        }
    }
}
