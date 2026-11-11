#if DEBUG
import Combine
import Foundation
import MusicDomain

/// Synthetic reports and controlled suspension, never filesystem verification.
/// Available only in Debug, with a dedicated fixture bundle and temporary children.
@MainActor
public final class FolderRecoveryPreviewFixture {
    public enum Mode: String, CaseIterable, Identifiable {
        case mixed = "Mixed results", changed = "Catalogue changed", unavailable = "Recheck unavailable"
        case failure = "Worker failure", slow = "Slow worker"
        public var id: Self { self }
    }
    @MainActor public final class Control: ObservableObject {
        @Published public var mode: Mode = .mixed
        @Published public private(set) var waiting = false
        @Published public private(set) var starts = 0
        @Published public private(set) var releases = 0
        @Published public private(set) var peakAccess = 0
        private var activeAccess = 0
        fileprivate var runMode: Mode = .mixed
        private var continuation: CheckedContinuation<Void, Never>?
        private var sink: FolderRecoveryPreviewSession.ProgressSink?
        private var steps = 0
        fileprivate func acquire() { starts += 1; activeAccess += 1; peakAccess = max(peakAccess, activeAccess) }
        fileprivate func release() { releases += 1; activeAccess -= 1 }
        fileprivate func hold(_ sink: FolderRecoveryPreviewSession.ProgressSink) async {
            self.sink = sink; steps = 0
            advance()
            await withCheckedContinuation { continuation = $0; waiting = true }
            self.sink = nil
        }
        public func advance() {
            steps = min(steps + 1, 7)
            sink?.send(.init(completedGroups: steps, totalGroups: 8,
                             currentRelativePath: "Synthetic album/Long movement \(steps).flac", bytesRead: Int64(steps) * 262144))
        }
        /// Deliberately ignores cancellation until released, modelling a blocked syscall.
        public func finishWorker() {
            let pending = continuation; continuation = nil; waiting = false; pending?.resume()
        }
    }
    private final class SessionBox { weak var value: FolderRecoveryPreviewSession? }
    public let session: FolderRecoveryPreviewSession
    public let control: Control
    public let root: StorageRoot
    public let directory: URL
    public let candidateA: URL
    public let candidateB: URL

    public static func make(bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> FolderRecoveryPreviewFixture {
        guard bundleIdentifier == "com.timetochilltoo.MusicLibraryNavigationFixture" else {
            throw FolderRecoveryPreviewError.invalidFixtureBoundary
        }
        return try .init()
    }

    private init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecoveryPreviewFixture-\(UUID().uuidString)")
        let a = directory.appending(path: "Candidate A — synthetic long directory name")
        let b = directory.appending(path: "Candidate B — synthetic second selection")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        self.directory = directory; candidateA = a; candidateB = b
        let root = StorageRoot(id: .init(), displayName: "Synthetic unavailable music folder", lastKnownPath: directory.appending(path: "Original registered folder").path,
                               bookmarkData: nil, volumeIdentifier: "SYNTHETIC-VOLUME", status: .offline, scope: .localOnly, bookmarkNeedsRefresh: false, lastSeenAt: nil)
        self.root = root
        let hash = String(repeating: "a", count: 64)
        let otherHash = String(repeating: "b", count: 64)
        let samples: [(String, FolderRecoveryVerifier.Outcome)] = [
            ("Synthetic album/01 — A very long movement title with multilingual text 樂章 and repeated CUE references.flac", .verified),
            ("Synthetic album/02 different.flac", .differentContent), ("Synthetic album/03 no baseline.flac", .unverified),
            ("Synthetic album/04 missing.flac", .missing), ("Synthetic album/05 unreadable.flac", .unreadable),
            ("../Synthetic unsafe.flac", .unsafePath), ("Synthetic album/07 conflict.flac", .catalogueConflict),
            ("Synthetic album/08 changed.flac", .unstableFile)
        ]
        var references = samples.map { path, outcome in
            FolderRecoveryReference(assetID: .init(), trackID: .init(), relativePath: path, expectedContentHash: outcome == .unverified ? nil : hash)
        }
        references.append(.init(assetID: .init(), trackID: .init(), relativePath: samples[0].0, expectedContentHash: hash, cueStartMilliseconds: 1000, cueEndMilliseconds: 2000))
        references.append(.init(assetID: .init(), trackID: .init(), relativePath: samples[6].0, expectedContentHash: otherHash))
        let snapshot = FolderRecoveryManifest(root: .init(id: root.id, displayName: root.displayName, registeredPath: root.lastKnownPath,
            volumeIdentifier: root.volumeIdentifier, scope: root.scope, status: root.status, bookmarkDigest: nil), catalogueRevision: 42, references: references)
        let control = Control()
        self.control = control
        let box = SessionBox()
        let outcomes = Dictionary(uniqueKeysWithValues: samples)
        session = .init(rootID: root.id, dependencies: .init(
            loadManifest: {
                guard box.value?.phase == .checkingCatalogue else { return snapshot }
                switch control.runMode {
                case .changed: return .init(root: snapshot.root, catalogueRevision: 43, references: snapshot.references)
                case .unavailable: throw NSError(domain: "SyntheticPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Synthetic recheck failure — no database was opened."])
                default: return snapshot
                }
            },
            beginAccess: { url in
                guard url == a || url == b else { throw FolderRecoveryPreviewError.invalidFixtureBoundary }
                let access = try FolderRecoveryReadAccess.fixture(url, within: directory, onEnd: { control.release() })
                control.acquire()
                return access
            },
            verify: { plan, url, sink in
                control.runMode = control.mode
                if control.runMode == .failure { throw FolderRecoveryVerificationError.candidateRootChanged }
                if control.runMode == .slow { await control.hold(sink) }
                return .init(manifest: plan.manifest, candidate: .init(selectedPath: url.path, resolvedPath: url.path, device: 0, inode: 0), evidence: plan.groups.map { group in
                    let outcome = outcomes[group.relativePath] ?? .unverified
                    return .init(group: group, outcome: outcome,
                        actualContentHash: outcome == .verified ? hash : (outcome == .differentContent ? otherHash : nil),
                        detail: "Synthetic \(String(describing: outcome)) evidence. No candidate file was read.")
                })
            }
        ))
        box.value = session
    }

    public func close() { session.cancel(); control.finishWorker() }
}
#endif
