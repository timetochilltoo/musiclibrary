import Foundation
import MusicDomain
import UniformTypeIdentifiers

public struct ImportScanResult: Sendable {
    public let candidates: [ImportCandidatePayload]
    public let errors: [String]
    public let wasCancelled: Bool

    public init(candidates: [ImportCandidatePayload], errors: [String], wasCancelled: Bool) {
        self.candidates = candidates; self.errors = errors; self.wasCancelled = wasCancelled
    }
}

public struct ImportScanner: Sendable {
    public init() {}

    public func scan(rootURL: URL, isCancelled: @Sendable () -> Bool = { Task.isCancelled }) -> ImportScanResult {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .contentTypeKey, .fileSizeKey, .contentModificationDateKey]
        var errors: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
            errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            return true
        }) else {
            return .init(candidates: [], errors: ["Unable to enumerate \(rootURL.path)."], wasCancelled: false)
        }
        var candidates: [ImportCandidatePayload] = []
        for case let url as URL in enumerator {
            if isCancelled() { return .init(candidates: candidates, errors: errors, wasCancelled: true) }
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isDirectory == true || values.isPackage == true || values.isHidden == true { continue }
                guard let type = values.contentType, type.conforms(to: .audio) else { continue }
                let relative = relativePath(of: url, within: rootURL)
                candidates.append(.init(relativePath: relative, fileName: url.lastPathComponent, contentTypeIdentifier: type.identifier, fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return .init(candidates: candidates, errors: errors, wasCancelled: isCancelled())
    }

    private func relativePath(of url: URL, within rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path.hasSuffix("/") ? rootURL.standardizedFileURL.path : rootURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent
    }
}
