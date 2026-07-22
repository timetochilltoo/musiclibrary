import AVFoundation
import Foundation
import MusicDomain

public struct EmbeddedMetadataExtractor: Sendable {
    public init() {}

    public func extract(url: URL) async -> EmbeddedMetadataPayload {
        let asset = AVURLAsset(url: url)
        let items = (try? await asset.load(.commonMetadata)) ?? []
        let title = value(for: .commonKeyTitle, in: items)
        let album = value(for: .commonKeyAlbumName, in: items)
        let artist = value(for: .commonKeyArtist, in: items)
        let duration = (try? await asset.load(.duration)).flatMap { value in
            let seconds = CMTimeGetSeconds(value)
            return seconds.isFinite && seconds >= 0 ? Int((seconds * 1_000).rounded()) : nil
        }
        var rawTags: [String: String] = [:]
        if let title { rawTags["title"] = title }
        if let album { rawTags["album"] = album }
        if let artist { rawTags["artist"] = artist }
        return .init(title: title, albumTitle: album, artist: artist, albumArtist: nil, discNumber: nil, trackNumber: nil, durationMilliseconds: duration, rawTags: rawTags)
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
            let hasEmbeddedAlbum = members.allSatisfy { $0.metadata?.albumTitle?.nilIfBlank != nil }
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
