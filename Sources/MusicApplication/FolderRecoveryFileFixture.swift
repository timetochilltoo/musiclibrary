#if DEBUG
import CryptoKit
import Foundation
import MusicDomain
import MusicPersistence

/// Real SQLite manifests, security scope and verifier; only disposable seeded bytes.
@MainActor
public final class FolderRecoveryFileFixture {
    public let library: LibraryStore
    public let root: StorageRoot
    public let directory: URL
    public let candidate: URL
    public let session: FolderRecoveryPreviewSession
    private let originalManifest: FolderRecoveryManifest
    private let sentinels: [URL: Data]
    private let link: URL
    private let linkDestination: String

    public static func make(bundleIdentifier: String? = Bundle.main.bundleIdentifier) async throws -> FolderRecoveryFileFixture {
        guard bundleIdentifier == "com.timetochilltoo.MusicLibraryNavigationFixture" else {
            throw FolderRecoveryPreviewError.invalidFixtureBoundary
        }
        return try await .init()
    }

    private init() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecoveryRealFiles-\(UUID().uuidString)")
        let candidate = directory.appending(path: "Candidate — disposable synthetic bytes")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        self.directory = directory; self.candidate = candidate
        let matching = Data(repeating: 0x37, count: 64 * 1024)
        let changed = Data(repeating: 0x82, count: 32 * 1024)
        let noBaseline = Data("No baseline; this file must not be hashed.".utf8)
        let outside = Data("Outside candidate sentinel; symlink must not be followed.".utf8)
        let sentinels = [candidate.appending(path: "01 matching.bin"): matching,
                         candidate.appending(path: "02 different.bin"): changed,
                         candidate.appending(path: "03 unverified.bin"): noBaseline,
                         directory.appending(path: "outside-sentinel.bin"): outside]
        for (url, bytes) in sentinels { try bytes.write(to: url) }
        self.sentinels = sentinels
        link = candidate.appending(path: "05 symlink.bin")
        linkDestination = "../outside-sentinel.bin"
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: linkDestination)
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Disposable real-file verification", lastKnownPath: directory.appending(path: "Original offline folder").path, bookmarkData: nil))
        let batch = try await database.createImportBatch(storageRootID: root.id, sourceDescription: "Seeded references only — no scanner or metadata extraction")
        let paths = ["01 matching.bin", "02 different.bin", "03 unverified.bin", "04 missing.bin", "05 symlink.bin"]
        for (index, path) in paths.enumerated() {
            try await database.recordImportCandidate(batchID: batch.id, payload: .init(relativePath: path, fileName: path, contentTypeIdentifier: "public.data", fileSize: 0, modifiedAt: nil))
            let item = try await database.importCandidates(batchID: batch.id).first { $0.payload?.relativePath == path }
            guard let item else { throw DatabaseError.notFound("Synthetic import candidate") }
            try await database.saveEmbeddedMetadata(.init(title: "Synthetic reference \(index + 1)", albumTitle: "Disposable verification", artist: nil, albumArtist: nil, discNumber: 1, trackNumber: index + 1, durationMilliseconds: nil, rawTags: [:]), for: item.id)
        }
        let candidates = try await database.importCandidates(batchID: batch.id)
        try await database.rebuildImportReleaseProposals(batchID: batch.id, drafts: [.init(title: "Disposable verification", artist: nil, discCount: 1, confidence: 1, candidateIDs: candidates.map(\.id))])
        guard let proposal = try await database.importReleaseProposals(batchID: batch.id).first else { throw DatabaseError.notFound("Synthetic release") }
        _ = try await database.confirmImportReleaseProposal(proposal.id)
        let baseline = Self.hash(matching)
        for reference in try await database.folderRecoveryManifest(rootID: root.id).references where reference.relativePath != "03 unverified.bin" {
            try await database.recordAssetFingerprint(reference.assetID, contentHash: reference.relativePath == "05 symlink.bin" ? Self.hash(outside) : baseline, quickSignature: "fixture-baseline")
        }
        try await database.updateStorageRootAccess(root.id, status: .offline)
        guard let offlineRoot = try await database.storageRoots().first(where: { $0.id == root.id }) else { throw DatabaseError.notFound("Synthetic root") }
        self.root = offlineRoot
        let library = LibraryStore(database: database)
        self.library = library
        originalManifest = try await library.folderRecoveryManifest(rootID: root.id)
        let rootID = root.id
        session = .init(rootID: rootID, dependencies: .init(
            loadManifest: { try await library.folderRecoveryManifest(rootID: rootID) },
            beginAccess: { selected in
                // The native picker may canonicalize /var to /private/var. Accept
                // that alias only for this exact disposable directory, never a parent.
                guard selected.isFileURL,
                      selected.standardizedFileURL.resolvingSymlinksInPath().path == candidate.standardizedFileURL.resolvingSymlinksInPath().path else {
                    throw FolderRecoveryPreviewError.invalidFixtureBoundary
                }
                return try FolderRecoveryReadAccess.securityScoped(selected)
            },
            verify: { plan, url, sink in
                try await FolderRecoveryVerifier.verify(plan, candidateRoot: url, onProgress: sink.send)
            }
        ))
    }

    public func checkIntegrity() async throws -> String {
        guard try await library.folderRecoveryManifest(rootID: root.id) == originalManifest,
              !FileManager.default.fileExists(atPath: root.lastKnownPath),
              !FileManager.default.fileExists(atPath: candidate.appending(path: "04 missing.bin").path),
              try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == linkDestination else {
            throw FolderRecoveryPreviewError.invalidManifest
        }
        for (url, expected) in sentinels {
            guard try Data(contentsOf: url) == expected else { throw FolderRecoveryVerificationError.candidateRootChanged }
        }
        return "Integrity passed: catalogue/revision/bookmark/status, seeded bytes and outside sentinel unchanged. Original folder and missing file remain absent."
    }

    public func close() { session.cancel() }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
