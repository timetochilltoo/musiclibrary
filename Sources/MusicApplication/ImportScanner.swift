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
        var cueFiles: [URL] = []
        for case let url as URL in enumerator {
            if isCancelled() { return .init(candidates: candidates, errors: errors, wasCancelled: true) }
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isDirectory == true || values.isPackage == true || values.isHidden == true { continue }
                if url.pathExtension.lowercased() == "cue" { cueFiles.append(url); continue }
                guard let type = values.contentType, type.conforms(to: .audio) else { continue }
                let relative = relativePath(of: url, within: rootURL)
                candidates.append(.init(relativePath: relative, fileName: url.lastPathComponent, contentTypeIdentifier: type.identifier, fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        for cueURL in cueFiles {
            guard !isCancelled() else { break }
            do {
                let tracks = try CueSheetParser().parse(url: cueURL)
                let cueDirectory = cueURL.deletingLastPathComponent()
                for fileName in Set(tracks.map(\.fileName)) {
                    let audioURL = cueDirectory.appending(path: fileName)
                    let relative = relativePath(of: audioURL, within: rootURL)
                    guard let base = candidates.first(where: { $0.relativePath.caseInsensitiveCompare(relative) == .orderedSame }) else {
                        errors.append("\(cueURL.lastPathComponent): referenced audio file \(fileName) was not found.")
                        continue
                    }
                    let virtualTracks = tracks.filter { $0.fileName.caseInsensitiveCompare(fileName) == .orderedSame }.map {
                        ImportCandidatePayload(relativePath: base.relativePath, fileName: base.fileName, contentTypeIdentifier: base.contentTypeIdentifier, fileSize: base.fileSize, modifiedAt: base.modifiedAt, cueStartMilliseconds: $0.startMilliseconds, cueEndMilliseconds: $0.endMilliseconds, cueTrackNumber: $0.number, cueTitle: $0.title, cueArtist: $0.artist, cueAlbumTitle: $0.albumTitle, cueAlbumArtist: $0.albumArtist)
                    }
                    if !virtualTracks.isEmpty {
                        candidates.removeAll { $0.relativePath.caseInsensitiveCompare(relative) == .orderedSame }
                        candidates.append(contentsOf: virtualTracks)
                    }
                }
            } catch { errors.append("\(cueURL.lastPathComponent): \(error.localizedDescription)") }
        }
        return .init(candidates: candidates, errors: errors, wasCancelled: isCancelled())
    }

    private func relativePath(of url: URL, within rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path.hasSuffix("/") ? rootURL.standardizedFileURL.path : rootURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent
    }
}
