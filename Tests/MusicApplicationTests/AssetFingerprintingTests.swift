import CryptoKit
import Foundation
import Testing
@testable import MusicApplication
@testable import MusicDomain

struct AssetFingerprintingTests {
    @Test("Fingerprint verification hashes large files in chunks")
    func hashesLargeFileWithoutChangingIt() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "fingerprint-\(UUID().uuidString).bin")
        let data = Data(repeating: 0x5A, count: (2 * 1024 * 1024) + 17)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try AssetFingerprinting.fingerprint(.init(id: .init(), rootURL: url.deletingLastPathComponent(), url: url))
        let expectedHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        #expect(result.contentHash == expectedHash)
        #expect(result.quickSignature == "\(data.count)-\(expectedHash.prefix(16))")
        #expect(try Data(contentsOf: url) == data)
    }
}
