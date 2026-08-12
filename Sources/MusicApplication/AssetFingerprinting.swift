import CryptoKit
import Foundation
import MusicDomain
import MusicPersistence

/// Chunked, non-UI file hashing used by the explicit fingerprint verification action.
/// It intentionally does not mutate the source file or the catalogue.
enum AssetFingerprinting {
    struct Job: Sendable {
        let id: DigitalAssetID
        let rootURL: URL
        let url: URL

        init(id: DigitalAssetID, rootURL: URL, url: URL) {
            self.id = id
            self.rootURL = rootURL
            self.url = url
        }
    }

    struct Result: Sendable, Equatable {
        let id: DigitalAssetID
        let contentHash: String
        let quickSignature: String

        init(id: DigitalAssetID, contentHash: String, quickSignature: String) {
            self.id = id
            self.contentHash = contentHash
            self.quickSignature = quickSignature
        }
    }

    static func fingerprint(_ job: Job) throws -> Result {
        let handle = try FileHandle(forReadingFrom: job.url)
        defer { try? handle.close() }

        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            let (updatedCount, overflow) = byteCount.addingReportingOverflow(Int64(chunk.count))
            guard !overflow else { throw DatabaseError.invalidOperation("Asset is too large to fingerprint safely.") }
            byteCount = updatedCount
            hasher.update(data: chunk)
        }

        let contentHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return .init(id: job.id, contentHash: contentHash, quickSignature: "\(byteCount)-\(contentHash.prefix(16))")
    }
}
