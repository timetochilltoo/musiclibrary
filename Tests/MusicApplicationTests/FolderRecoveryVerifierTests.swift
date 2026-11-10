import CryptoKit
import Darwin
import Dispatch
import Foundation
import Testing
import MusicDomain
@testable import MusicApplication

@Suite("Read-only candidate folder verification")
struct FolderRecoveryVerifierTests {
    @Test("Stable matches, differences and failures retain references without escaped reads")
    @MainActor
    func evidence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = Data(repeating: 1, count: 600_000)
        let different = Data([2, 3, 4])
        let nested = Data([7, 8])
        let secret = Data(repeating: 9, count: 2_000_000)
        try match.write(to: fixture.root.appending(path: "match.bin"))
        try different.write(to: fixture.root.appending(path: "different.bin"))
        try Data().write(to: fixture.root.appending(path: "empty.bin"))
        let nestedFile = fixture.root.appending(path: "Disc/Album/nested.bin")
        try FileManager.default.createDirectory(at: nestedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try nested.write(to: nestedFile)
        try secret.write(to: fixture.outside.appending(path: "secret.bin"))
        try FileManager.default.createDirectory(at: fixture.root.appending(path: "directory"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: fixture.root.appending(path: "link.bin").path, withDestinationPath: fixture.outside.appending(path: "secret.bin").path)
        try FileManager.default.createSymbolicLink(atPath: fixture.root.appending(path: "outside").path, withDestinationPath: fixture.outside.path)
        try FileManager.default.createSymbolicLink(atPath: fixture.root.appending(path: "inside-link.bin").path, withDestinationPath: "match.bin")
        #expect(mkfifo(fixture.root.appending(path: "pipe").path, 0o600) == 0)
        let repeated = [reference("match.bin", hash: digest(match), start: 0), reference("match.bin", hash: digest(match), start: 1000)]
        let references = repeated + [
            reference("different.bin", hash: digest(match)),
            reference("Disc/Album/nested.bin", hash: digest(nested)),
            reference("empty.bin", hash: digest(Data())),
            reference("missing.bin", hash: digest(match)),
            reference("missing/sub.bin", hash: digest(match)),
            reference("different.bin/child", hash: digest(match)),
            reference("directory", hash: digest(match)),
            reference("pipe", hash: digest(match)),
            reference("link.bin", hash: digest(secret)),
            reference("outside/secret.bin", hash: digest(secret)),
            reference("inside-link.bin", hash: digest(match)),
            reference("../outside/secret.bin", hash: digest(secret)),
            reference("no-baseline.bin", hash: nil),
            reference("conflict.bin", hash: digest(match)),
            reference("conflict.bin", hash: digest(different))
        ]
        let progress = Probe()
        let plan = plan(references)
        let report = try await FolderRecoveryVerifier.verify(plan, candidateRoot: fixture.root) { progress.record($0) }
        let outcomes = Dictionary(uniqueKeysWithValues: report.evidence.map { ($0.group.relativePath, $0.outcome) })
        #expect(outcomes["match.bin"] == .verified && outcomes["different.bin"] == .differentContent)
        #expect(outcomes["empty.bin"] == .verified)
        #expect(outcomes["Disc/Album/nested.bin"] == .verified)
        #expect(outcomes["missing/sub.bin"] == .missing && outcomes["different.bin/child"] == .unreadable)
        #expect(outcomes["missing.bin"] == .missing && outcomes["directory"] == .unreadable && outcomes["pipe"] == .unreadable)
        for path in ["link.bin", "outside/secret.bin", "inside-link.bin", "../outside/secret.bin"] { #expect(outcomes[path] == .unsafePath) }
        #expect(outcomes["no-baseline.bin"] == .unverified && outcomes["conflict.bin"] == .catalogueConflict)
        #expect(report.evidence.first(where: { $0.group.relativePath == "match.bin" })?.group.references.count == 2)
        #expect(report.manifest == plan.manifest)
        #expect(progress.last?.bytesRead == Int64(match.count + different.count + nested.count))
        #expect(progress.last?.completedGroups == plan.groups.count)
        #expect(!progress.sawMainThread)
        #expect(try Data(contentsOf: fixture.root.appending(path: "match.bin")) == match)
        #expect(try Data(contentsOf: fixture.outside.appending(path: "secret.bin")) == secret)
    }

    @Test("Modification and atomic replacement during a read never produce verified evidence", arguments: [false, true])
    func unstableFiles(atomic: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appending(path: "file.bin")
        let bytes = Data(repeating: 1, count: 800_000)
        try bytes.write(to: url)
        let once = OneShot()
        let report = try await FolderRecoveryVerifier.verify(plan([reference("file.bin", hash: digest(bytes))]), candidateRoot: fixture.root) { update in
            if update.bytesRead > 0 && once.take() {
                do { try Data(repeating: 2, count: bytes.count + 17).write(to: url, options: atomic ? .atomic : []) }
                catch { Issue.record(error) }
            }
        }
        #expect(report.evidence.first?.outcome == .unstableFile)
        #expect(report.evidence.first?.actualContentHash == nil)
    }

    @Test("Directory substitution between progress and open cannot escape the anchored root")
    func directorySwap() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let album = fixture.root.appending(path: "Album")
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        try Data([1]).write(to: album.appending(path: "song.bin"))
        let secret = Data([9])
        try secret.write(to: fixture.outside.appending(path: "song.bin"))
        let once = OneShot()
        let probe = Probe()
        let report = try await FolderRecoveryVerifier.verify(plan([reference("Album/song.bin", hash: digest(secret))]), candidateRoot: fixture.root) { update in
            probe.record(update)
            if update.currentRelativePath != nil && once.take() {
                do {
                    try FileManager.default.moveItem(at: album, to: fixture.base.appending(path: "old-album"))
                    try FileManager.default.createSymbolicLink(atPath: album.path, withDestinationPath: fixture.outside.path)
                } catch { Issue.record(error) }
            }
        }
        #expect(report.evidence.first?.outcome == .unsafePath)
        #expect(probe.last?.bytesRead == 0)
    }

    @Test("Replacing the candidate root discards the entire report")
    func rootSwap() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data(repeating: 1, count: 800_000)
        try bytes.write(to: fixture.root.appending(path: "file.bin"))
        let once = OneShot()
        do {
            _ = try await FolderRecoveryVerifier.verify(plan([reference("file.bin", hash: digest(bytes))]), candidateRoot: fixture.root) { update in
                if update.bytesRead > 0 && once.take() {
                    do {
                        try FileManager.default.moveItem(at: fixture.root, to: fixture.base.appending(path: "old-root"))
                        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
                    } catch { Issue.record(error) }
                }
            }
            Issue.record("Changed root produced a report")
        } catch { #expect(error as? FolderRecoveryVerificationError == .candidateRootChanged) }
    }

    @Test("Parent cancellation interrupts a worker between chunks and returns no report")
    func cancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data(repeating: 1, count: 800_000)
        try bytes.write(to: fixture.root.appending(path: "file.bin"))
        let plan = plan([reference("file.bin", hash: digest(bytes))])
        let updates = AsyncStream<FolderRecoveryVerifier.Progress>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        let once = OneShot()
        let verification = Task {
            defer { updates.continuation.finish() }
            return try await FolderRecoveryVerifier.verify(plan, candidateRoot: fixture.root) { update in
                updates.continuation.yield(update)
                if update.bytesRead > 0 && once.take() { _ = gate.wait(timeout: .now() + 10) }
            }
        }
        defer { verification.cancel(); gate.signal(); updates.continuation.finish() }
        var startedReading = false
        for await update in updates.stream where update.bytesRead > 0 {
            startedReading = true
            verification.cancel()
            gate.signal()
            break
        }
        #expect(startedReading)
        do { _ = try await verification.value; Issue.record("Cancelled verification returned a report") }
        catch { #expect(error is CancellationError) }
        #expect(try Data(contentsOf: fixture.root.appending(path: "file.bin")) == bytes)
    }

    @Test("Already-cancelled verification does not open the candidate root")
    func cancelledBeforeOpen() async throws {
        let plan = plan([])
        let verification = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FolderRecoveryVerifier.verify(plan, candidateRoot: URL(fileURLWithPath: "/not-opened"))
        }
        do { _ = try await verification.value; Issue.record("Cancelled verification returned a report") }
        catch { #expect(error is CancellationError) }
    }

    @Test("Empty plans stay empty and invalid candidate roots fail without file hashing")
    func emptyAndInvalidRoots() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let report = try await FolderRecoveryVerifier.verify(plan([]), candidateRoot: fixture.root)
        #expect(report.evidence.isEmpty)
        let file = fixture.root.appending(path: "file.bin")
        try Data([1]).write(to: file)
        for url in [file, fixture.base.appending(path: "absent"), try #require(URL(string: "https://example.invalid/folder"))] {
            do { _ = try await FolderRecoveryVerifier.verify(plan([]), candidateRoot: url); Issue.record("Invalid root accepted") }
            catch { #expect(error as? FolderRecoveryVerificationError == .invalidCandidateRoot) }
        }
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func reference(_ path: String, hash: String?, start: Int64? = nil) -> FolderRecoveryReference {
        .init(assetID: .init(), trackID: .init(), relativePath: path, expectedContentHash: hash, cueStartMilliseconds: start)
    }
    private func plan(_ references: [FolderRecoveryReference]) -> FolderRecoveryReferencePlan {
        .init(manifest: .init(root: .init(id: .init(), displayName: "Synthetic original", registeredPath: "/original-not-read", volumeIdentifier: nil, scope: .localOnly, status: .offline, bookmarkDigest: nil), catalogueRevision: 7, references: references))
    }
    private struct Fixture: Sendable {
        let base: URL
        var root: URL { base.appending(path: "candidate") }
        var outside: URL { base.appending(path: "outside") }
        init() throws {
            base = FileManager.default.temporaryDirectory.appending(path: "RecoveryVerifier-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: base) }
    }
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func take() -> Bool { lock.withLock { if used { return false }; used = true; return true } }
    }
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var value: FolderRecoveryVerifier.Progress?
        private var mainThread = false
        func record(_ update: FolderRecoveryVerifier.Progress) { lock.withLock { value = update; mainThread = mainThread || Thread.isMainThread } }
        var last: FolderRecoveryVerifier.Progress? { lock.withLock { value } }
        var sawMainThread: Bool { lock.withLock { mainThread } }
    }
}
