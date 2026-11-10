import Foundation
import Testing
import MusicDomain
import MusicPersistence
@testable import MusicApplication

@Suite("Folder recovery preflight")
struct FolderRecoveryReferencePlanTests {
    private let hash = String(repeating: "a", count: 64)

    @Test("Repeated paths retain every asset, track and CUE boundary for one verification group")
    func groupsReferences() {
        let references = [reference("Album/source.flac", hash: hash, start: 0), reference("Album/source.flac", hash: hash.uppercased(), start: 1000)]
        let plan = FolderRecoveryReferencePlan(manifest: manifest(references))
        #expect(plan.groups.count == 1)
        #expect(plan.groups.first?.eligibility == .readyToVerify)
        #expect(plan.groups.first?.expectedContentHash == hash)
        #expect(Set(plan.groups[0].references.map(\.assetID)) == Set(references.map(\.assetID)))
        #expect(Set(plan.groups[0].references.map(\.trackID)) == Set(references.map(\.trackID)))
        #expect(Set(plan.groups[0].references.compactMap(\.cueStartMilliseconds)) == Set([Int64(0), 1000]))
    }

    @Test("Absent, malformed and contradictory full hashes cannot be ready")
    func incompleteEvidence() {
        let references = [reference("missing.flac", hash: nil), reference("short.flac", hash: "12-abcd"), reference("invalid.flac", hash: String(repeating: "g", count: 64)), reference("mixed.flac", hash: hash), reference("mixed.flac", hash: nil), reference("conflict.flac", hash: hash), reference("conflict.flac", hash: String(repeating: "b", count: 64))]
        let plan = FolderRecoveryReferencePlan(manifest: manifest(references))
        #expect(plan.groups.first(where: { $0.relativePath == "conflict.flac" })?.eligibility == .conflictingHashes)
        #expect(plan.groups.filter { $0.relativePath != "conflict.flac" }.allSatisfy { $0.eligibility == .unverified })
        #expect(plan.groups.allSatisfy { $0.expectedContentHash == nil })
        #expect(FolderRecoveryReferencePlan(manifest: manifest([])).groups.isEmpty)
    }

    @Test("Unsafe and ambiguous relative paths produce no verification job", arguments: ["", "/outside.flac", "../outside.flac", "Album/../outside.flac", "~/music.flac", "C:/music.flac", "Album\\music.flac", "Album//music.flac", "./music.flac", "Album/", "Album/\u{0}file.flac"])
    func unsafePaths(path: String) {
        let plan = FolderRecoveryReferencePlan(manifest: manifest([reference(path, hash: hash)]))
        #expect(plan.groups.first?.eligibility == .unsafePath)
        #expect(plan.groups.first?.expectedContentHash == nil)
    }

    @Test("Store manifest reads do not refresh unavailable root access")
    @MainActor func storeSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RecoveryManifestStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MusicDatabase(url: directory.appending(path: "fixture.sqlite"))
        try await database.migrate()
        let root = try await database.createStorageRoot(.init(displayName: "Offline", lastKnownPath: directory.path, bookmarkData: nil, status: .offline))
        let store = LibraryStore(database: database)
        let revision = try await database.currentRevision()
        let captured = try await store.folderRecoveryManifest(rootID: root.id)
        #expect(captured.root.status == .offline && captured.references.isEmpty)
        #expect(try await database.storageRoots().first?.status == .offline)
        #expect(try await database.currentRevision() == revision)
        #expect(store.importBatches.isEmpty && store.errorMessage == nil)
    }

    private func reference(_ path: String, hash: String?, start: Int64? = nil) -> FolderRecoveryReference {
        .init(assetID: .init(), trackID: .init(), relativePath: path, expectedContentHash: hash, cueStartMilliseconds: start, cueEndMilliseconds: start.map { $0 + 1000 })
    }
    private func manifest(_ references: [FolderRecoveryReference]) -> FolderRecoveryManifest {
        .init(root: .init(id: .init(), displayName: "Synthetic root", registeredPath: "/not-read", volumeIdentifier: nil, scope: .localOnly, status: .offline, bookmarkDigest: nil), catalogueRevision: 7, references: references)
    }
}
