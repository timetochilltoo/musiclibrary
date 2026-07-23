import CryptoKit
import Foundation
import MusicPersistence

public struct MasterBackupManifest: Codable, Equatable, Sendable {
    public let format: String
    public let revision: Int64
    public let createdAt: Date
    public let fileName: String
    public let sha256: String

    public init(revision: Int64, createdAt: Date, fileName: String, sha256: String) {
        self.format = "music-library-master-backup-v1"
        self.revision = revision
        self.createdAt = createdAt
        self.fileName = fileName
        self.sha256 = sha256
    }
}

public enum MasterBackupArchive {
    public static func create(database: MusicDatabase, in directory: URL, now: Date = .now) async throws -> MasterBackupManifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let revision = try await database.currentRevision()
        let stamp = Int64((now.timeIntervalSince1970 * 1_000).rounded())
        let fileName = "MusicLibrary-master-r\(revision)-\(stamp).sqlite"
        let destination = directory.appending(path: fileName)
        let temporary = directory.appending(path: ".\(fileName).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await database.createConsistentBackup(at: temporary)
        let data = try Data(contentsOf: temporary)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.moveItem(at: temporary, to: destination)
        let manifest = MasterBackupManifest(revision: revision, createdAt: now, fileName: fileName, sha256: checksum)
        let manifestURL = directory.appending(path: "\(fileName).manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        return manifest
    }

    public static func verify(_ manifest: MasterBackupManifest, in directory: URL) async throws {
        guard manifest.format == "music-library-master-backup-v1" else { throw DatabaseError.invalidOperation("Unsupported master backup format.") }
        let fileURL = directory.appending(path: manifest.fileName)
        let data = try Data(contentsOf: fileURL)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard checksum == manifest.sha256 else { throw DatabaseError.invalidOperation("Master backup checksum failed.") }
        let backup = try MusicDatabase(url: fileURL)
        try await backup.migrate()
    }

    public static func retain(in directory: URL, daily: Int = 7, monthly: Int = 12) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        let manifests = files.filter { $0.lastPathComponent.hasPrefix("MusicLibrary-master-") && $0.lastPathComponent.hasSuffix(".manifest.json") }
            .compactMap { url -> (URL, MasterBackupManifest)? in
                guard let manifest = try? JSONDecoder().decode(MasterBackupManifest.self, from: Data(contentsOf: url)) else { return nil }
                return (url, manifest)
            }
            .sorted { $0.1.createdAt > $1.1.createdAt }
        var keep = Set<String>()
        var days = Set<String>()
        var months = Set<String>()
        let calendar = Calendar(identifier: .gregorian)
        for (_, manifest) in manifests {
            let day = calendar.dateComponents([.year, .month, .day], from: manifest.createdAt)
            let dayKey = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
            let monthKey = "\(day.year ?? 0)-\(day.month ?? 0)"
            if days.count < daily, days.insert(dayKey).inserted { keep.insert(manifest.fileName) }
            if months.count < monthly, months.insert(monthKey).inserted { keep.insert(manifest.fileName) }
        }
        for (manifestURL, manifest) in manifests where !keep.contains(manifest.fileName) {
            try? FileManager.default.removeItem(at: directory.appending(path: manifest.fileName))
            try? FileManager.default.removeItem(at: manifestURL)
        }
    }
}
