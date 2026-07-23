import Foundation
import Testing
@testable import MusicApplication
@testable import MusicDomain
@testable import MusicPersistence

@Suite("Import scanner")
struct ImportScannerTests {
    @Test("Scanner discovers audio by content type and skips hidden files")
    func discoversAudioAndSkipsHidden() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let nested = root.appending(path: "Nested", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try? Data([0]).write(to: nested.appending(path: "song.mp3"))
        try? Data([0]).write(to: root.appending(path: ".hidden.mp3"))
        try? Data("not audio".utf8).write(to: root.appending(path: "notes.txt"))

        let result = ImportScanner().scan(rootURL: root)
        #expect(result.candidates.map(\.relativePath) == ["Nested/song.mp3"])
        #expect(result.candidates.first?.contentTypeIdentifier.isEmpty == false)
    }

    @Test("Scanner stops before enumerating when cancelled")
    func cancellation() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data([0]).write(to: root.appending(path: "song.mp3"))

        let result = ImportScanner().scan(rootURL: root, isCancelled: { true })
        #expect(result.wasCancelled)
        #expect(result.candidates.isEmpty)
    }

    @Test("Metadata grouping keeps Unicode multi-disc candidates in one proposal")
    func groupsMetadata() {
        let batchID = ImportBatchID()
        let first = ImportCandidate(id: ImportCandidateID(), batchID: batchID, status: .proposed, payload: .init(relativePath: "宇多田/アルバム/01.mp3", fileName: "01.mp3", contentTypeIdentifier: "public.mp3", fileSize: 1, modifiedAt: nil), errorMessage: nil, metadata: .init(title: "曲一", albumTitle: "アルバム", artist: "宇多田", albumArtist: nil, discNumber: 1, trackNumber: 1, durationMilliseconds: nil, rawTags: [:]))
        let second = ImportCandidate(id: ImportCandidateID(), batchID: batchID, status: .proposed, payload: .init(relativePath: "宇多田/アルバム/02.mp3", fileName: "02.mp3", contentTypeIdentifier: "public.mp3", fileSize: 1, modifiedAt: nil), errorMessage: nil, metadata: .init(title: "曲二", albumTitle: "アルバム", artist: "宇多田", albumArtist: nil, discNumber: 2, trackNumber: 1, durationMilliseconds: nil, rawTags: [:]))
        let proposals = MetadataProposalGrouper().group(candidates: [first, second])
        #expect(proposals.count == 1)
        #expect(proposals.first?.title == "アルバム")
        #expect(proposals.first?.discCount == 2)
        #expect(proposals.first?.candidateIDs.count == 2)
    }

    @Test("Snapshot publisher writes a checksummed manifest after the revision file")
    func publishesSnapshot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try SnapshotPublisher.publish(json: "{\"format\":\"music-library-json\"}", revision: 42, to: directory)
        #expect(manifest.fileName == "catalogue-42.json")
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: manifest.fileName).path))
        let decoded = try JSONDecoder().decode(SnapshotManifest.self, from: Data(contentsOf: directory.appending(path: "manifest.json")))
        #expect(decoded.sha256 == manifest.sha256)
    }

    @Test("Managed artwork import copies the selected image into catalogue storage")
    func importsManagedArtwork() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appending(path: "cover.jpg")
        try Data([1, 2, 3]).write(to: source)
        let destination = try ManagedArtworkStore(directory: directory.appending(path: "Artwork")).importArtwork(from: source)
        #expect(destination.deletingLastPathComponent().lastPathComponent == "Artwork")
        #expect(destination != source)
        #expect(try Data(contentsOf: destination) == Data([1, 2, 3]))
    }

    @Test("Master archive writes a checksummed verified SQLite backup")
    func writesMasterArchive() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MusicDatabase(url: directory.appending(path: "source.sqlite"))
        try await database.migrate()
        _ = try await database.createAlbum(.init(title: "Archived"))

        let archiveDirectory = directory.appending(path: "Backups")
        let manifest = try await MasterBackupArchive.create(database: database, in: archiveDirectory, now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(FileManager.default.fileExists(atPath: archiveDirectory.appending(path: manifest.fileName).path))
        try await MasterBackupArchive.verify(manifest, in: archiveDirectory)
    }

    @Test("Snapshot publisher retains only the configured recent revisions")
    func retainsSnapshotRevisions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for revision in 1...4 { _ = try SnapshotPublisher.publish(json: "{\"format\":\"music-library-json\",\"revision\":\(revision)}", revision: Int64(revision), to: directory, retainRevisions: 2) }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("catalogue-") && $0.hasSuffix(".json") }
        #expect(files.sorted() == ["catalogue-3.json", "catalogue-4.json"])
        let manifest = try JSONDecoder().decode(SnapshotManifest.self, from: Data(contentsOf: directory.appending(path: "manifest.json")))
        #expect(manifest.fileName == "catalogue-4.json")
    }

    @Test("Snapshot publisher keeps the current revision and three prior revisions by default")
    func retainsDefaultSnapshotRevisions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for revision in 1...5 { _ = try SnapshotPublisher.publish(json: "{\"format\":\"music-library-json\",\"revision\":\(revision)}", revision: Int64(revision), to: directory) }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("catalogue-") && $0.hasSuffix(".json") }
        #expect(files.sorted() == ["catalogue-2.json", "catalogue-3.json", "catalogue-4.json", "catalogue-5.json"])
    }

    @Test("Publication scheduling ignores initial and read-only observations but coalesces mutations")
    func publicationScheduling() {
        var schedule = SnapshotPublicationSchedule()
        let initial = schedule.observe(4)
        #expect(!initial)
        let readOnly = schedule.observe(4)
        #expect(!readOnly)
        let mutation = schedule.observe(5)
        #expect(mutation)
        #expect(schedule.needsPublication)
        schedule.markPublished(5)
        #expect(!schedule.needsPublication)
        let sameRevision = schedule.observe(5)
        #expect(!sameRevision)
        let nextMutation = schedule.observe(6)
        #expect(nextMutation)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ImportScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
