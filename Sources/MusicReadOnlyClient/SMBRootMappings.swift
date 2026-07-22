import Foundation

public struct SMBRootMapping: Codable, Equatable, Sendable { public let publishedRootID: String; public let localURL: URL; public init(publishedRootID: String, localURL: URL) { self.publishedRootID = publishedRootID; self.localURL = localURL } }
public final class SMBRootMappingStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func mappings() throws -> [SMBRootMapping] { guard FileManager.default.fileExists(atPath: url.path) else { return [] }; return try JSONDecoder().decode([SMBRootMapping].self, from: Data(contentsOf: url)) }
    public func set(_ mapping: SMBRootMapping) throws { var values = try mappings(); values.removeAll { $0.publishedRootID == mapping.publishedRootID }; values.append(mapping); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(values).write(to: url, options: .atomic) }
}
