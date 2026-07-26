import AVFoundation
import Foundation
import MusicDomain

public struct EmbeddedMetadataExtractor: Sendable {
    public init() {}

    public func extract(url: URL, relativePath: String) async -> EmbeddedMetadataPayload {
        let asset = AVURLAsset(url: url)
        let items = (try? await asset.load(.commonMetadata)) ?? []
        let embeddedTitle = value(for: .commonKeyTitle, in: items)
        let embeddedAlbum = value(for: .commonKeyAlbumName, in: items)
        let embeddedArtist = value(for: .commonKeyArtist, in: items)
        let fallback = Self.pathFallback(relativePath: relativePath)
        let duration = (try? await asset.load(.duration)).flatMap { value in
            let seconds = CMTimeGetSeconds(value)
            return seconds.isFinite && seconds >= 0 ? Int((seconds * 1_000).rounded()) : nil
        }
        var rawTags: [String: String] = [:]
        let title = embeddedTitle ?? fallback.title
        let album = embeddedAlbum ?? fallback.albumTitle
        let artist = embeddedArtist ?? fallback.artist
        if let title { rawTags["title"] = title }
        if let album { rawTags["album"] = album }
        if let artist { rawTags["artist"] = artist }
        if embeddedTitle == nil { rawTags["titleSource"] = "path" }
        if embeddedAlbum == nil { rawTags["albumSource"] = "path" }
        if embeddedArtist == nil, fallback.artist != nil { rawTags["artistSource"] = "path" }
        return .init(title: title, albumTitle: album, artist: artist, albumArtist: nil, discNumber: fallback.discNumber, trackNumber: fallback.trackNumber, durationMilliseconds: duration, rawTags: rawTags)
    }

    public static func pathFallback(relativePath: String) -> EmbeddedMetadataPayload {
        let components = relativePath.split(separator: "/").map(String.init)
        let fileName = components.last ?? relativePath
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let (trackNumber, title) = parsedTrackName(baseName)
        let folder = components.dropLast().last ?? "Unknown album"
        let (albumTitle, discNumber) = parsedAlbumFolder(folder)
        let artist = components.count >= 3 ? components[components.count - 3].nilIfBlank : nil
        return .init(title: title, albumTitle: albumTitle, artist: artist, albumArtist: nil, discNumber: discNumber, trackNumber: trackNumber, durationMilliseconds: nil, rawTags: ["fallbackSource": "path"])
    }

    private static func parsedTrackName(_ baseName: String) -> (Int?, String) {
        let pattern = #"^\s*([0-9]{1,3})\s*[. _-]+(.+?)\s*$"#
        guard let range = baseName.range(of: pattern, options: .regularExpression) else { return (nil, baseName) }
        let matched = String(baseName[range])
        let parts = matched.split(maxSplits: 1, whereSeparator: { !$0.isNumber })
        guard let number = parts.first.flatMap({ Int($0) }), parts.count == 2 else { return (nil, baseName) }
        return (number, String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parsedAlbumFolder(_ folder: String) -> (String, Int?) {
        let pattern = #"(?i)\s*\[(?:disc|cd)\s*([0-9]+)\]\s*$"#
        guard let range = folder.range(of: pattern, options: .regularExpression) else { return (folder, nil) }
        let suffix = String(folder[range])
        let discNumber = Int(suffix.filter(\.isNumber))
        let album = String(folder[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (album.nilIfBlank ?? folder, discNumber)
    }

    private func value(for key: AVMetadataKey, in items: [AVMetadataItem]) -> String? {
        items.first(where: { $0.commonKey == key })?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

public struct MetadataProposalGrouper: Sendable {
    public init() {}

    public func group(candidates: [ImportCandidate]) -> [ImportReleaseProposalDraft] {
        struct Key: Hashable { let title: String; let artist: String? }
        var groups: [Key: [ImportCandidate]] = [:]
        for candidate in candidates {
            guard candidate.status == .proposed, let payload = candidate.payload, let metadata = candidate.metadata else { continue }
            let title = metadata.albumTitle?.nilIfBlank ?? fallbackAlbumTitle(relativePath: payload.relativePath)
            let artist = metadata.albumArtist?.nilIfBlank ?? metadata.artist?.nilIfBlank
            groups[.init(title: title, artist: artist), default: []].append(candidate)
        }
        return groups.map { key, members in
            let discs = members.compactMap(\.metadata?.discNumber).max() ?? 1
            let hasEmbeddedAlbum = members.allSatisfy { $0.metadata?.rawTags["albumSource"] != "path" && $0.metadata?.albumTitle?.nilIfBlank != nil }
            let confidence = hasEmbeddedAlbum ? (key.artist == nil ? 0.75 : 0.9) : 0.35
            return .init(title: key.title, artist: key.artist, discCount: discs, confidence: confidence, candidateIDs: members.map(\.id))
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func fallbackAlbumTitle(relativePath: String) -> String {
        let parent = URL(fileURLWithPath: relativePath).deletingLastPathComponent().lastPathComponent
        return parent.nilIfBlank ?? "Unknown album"
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
