import AVFoundation
import Foundation
import MusicDomain

public struct EmbeddedMetadataExtractor: Sendable {
    public init() {}

    public func extract(url: URL, relativePath: String) async -> EmbeddedMetadataPayload {
        if url.pathExtension.caseInsensitiveCompare("dsf") == .orderedSame, let dsf = try? DSFMetadataReader().read(url: url) {
            return metadata(from: dsf, relativePath: relativePath)
        }
        if let flac = try? FLACMetadataReader().read(url: url) {
            return metadata(from: flac, relativePath: relativePath)
        }
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

    private func metadata(from dsf: DSFMetadataReader.Result, relativePath: String) -> EmbeddedMetadataPayload {
        let fallback = Self.pathFallback(relativePath: relativePath)
        func tag(_ names: String...) -> String? { names.lazy.compactMap { dsf.tags[$0] }.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        let title = tag("TITLE") ?? fallback.title
        let album = tag("ALBUM") ?? fallback.albumTitle
        let artist = tag("ARTIST") ?? fallback.artist
        let albumArtist = tag("ALBUMARTIST")
        let discNumber = number(from: tag("DISCNUMBER")) ?? fallback.discNumber
        let trackNumber = number(from: tag("TRACKNUMBER")) ?? fallback.trackNumber
        var rawTags = dsf.tags
        rawTags["codec"] = "DSF"
        rawTags["sampleRateHz"] = String(dsf.sampleRateHz)
        rawTags["bitDepth"] = String(dsf.bitDepth)
        rawTags["channels"] = String(dsf.channelCount)
        if title == fallback.title, dsf.tags["TITLE"] == nil { rawTags["titleSource"] = "path" }
        if album == fallback.albumTitle, dsf.tags["ALBUM"] == nil { rawTags["albumSource"] = "path" }
        if artist == fallback.artist, dsf.tags["ARTIST"] == nil { rawTags["artistSource"] = "path" }
        return .init(title: title, albumTitle: album, artist: artist, albumArtist: albumArtist, discNumber: discNumber, trackNumber: trackNumber, durationMilliseconds: dsf.durationMilliseconds, rawTags: rawTags, provenance: "dsf-id3", releaseYear: year(from: tag("DATE")), genre: tag("GENRE"), codec: "DSF", sampleRateHz: dsf.sampleRateHz, bitDepth: dsf.bitDepth, channelCount: dsf.channelCount)
    }

    private func metadata(from flac: FLACMetadataReader.Result, relativePath: String) -> EmbeddedMetadataPayload {
        let fallback = Self.pathFallback(relativePath: relativePath)
        func tag(_ names: String...) -> String? {
            names.lazy.compactMap { flac.tags[$0] }.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        let title = tag("TITLE") ?? fallback.title
        let album = tag("ALBUM") ?? fallback.albumTitle
        let artist = tag("ARTIST") ?? fallback.artist
        let albumArtist = tag("ALBUMARTIST", "ALBUM ARTIST")
        let discNumber = number(from: tag("DISCNUMBER", "DISC")) ?? fallback.discNumber
        let trackNumber = number(from: tag("TRACKNUMBER", "TRACK")) ?? fallback.trackNumber
        let releaseYear = year(from: tag("DATE", "YEAR", "ORIGINALDATE"))
        let genre = tag("GENRE")
        var rawTags = flac.tags
        rawTags["codec"] = "FLAC"
        if let sampleRate = flac.sampleRateHz { rawTags["sampleRateHz"] = String(sampleRate) }
        if let bitDepth = flac.bitDepth { rawTags["bitDepth"] = String(bitDepth) }
        if let channels = flac.channelCount { rawTags["channels"] = String(channels) }
        if title == fallback.title, flac.tags["TITLE"] == nil { rawTags["titleSource"] = "path" }
        if album == fallback.albumTitle, flac.tags["ALBUM"] == nil { rawTags["albumSource"] = "path" }
        if artist == fallback.artist, flac.tags["ARTIST"] == nil { rawTags["artistSource"] = "path" }
        return .init(title: title, albumTitle: album, artist: artist, albumArtist: albumArtist, discNumber: discNumber, trackNumber: trackNumber, durationMilliseconds: flac.durationMilliseconds, rawTags: rawTags, provenance: "flac-vorbis-comments", releaseYear: releaseYear, genre: genre, codec: "FLAC", sampleRateHz: flac.sampleRateHz, bitDepth: flac.bitDepth, channelCount: flac.channelCount)
    }

    private func number(from value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.prefix { $0.isNumber }
        return Int(digits)
    }

    private func year(from value: String?) -> Int? {
        guard let value, let range = value.range(of: #"\b[0-9]{4}\b"#, options: .regularExpression) else { return nil }
        return Int(value[range])
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
    private struct GroupKey: Hashable {
        let title: String
        let artist: String?
    }

    private struct Group {
        let title: String
        let artist: String?
        var candidates: [ImportCandidate]
    }

    public init() {}

    public func group(candidates: [ImportCandidate]) -> [ImportReleaseProposalDraft] {
        var groups: [GroupKey: Group] = [:]
        for candidate in candidates {
            guard candidate.status == .proposed, let payload = candidate.payload, let metadata = candidate.metadata else { continue }
            let title = metadata.albumTitle?.nilIfBlank ?? fallbackAlbumTitle(relativePath: payload.relativePath)
            let artist = metadata.albumArtist?.nilIfBlank ?? metadata.artist?.nilIfBlank
            let key = GroupKey(title: groupingKey(title), artist: artist.map { groupingKey($0) })
            if var group = groups[key] {
                group.candidates.append(candidate)
                groups[key] = group
            } else {
                // Keep the first source spelling for the proposal UI. Only the
                // identity key is normalized, so catalogue metadata is never
                // silently rewritten by the grouping pass.
                groups[key] = Group(title: title, artist: artist, candidates: [candidate])
            }
        }
        return mergeSingleTrackArtistOutliers(Array(groups.values)).map { group in
            let members = group.candidates
            let discs = members.compactMap(\.metadata?.discNumber).max() ?? 1
            let hasEmbeddedAlbum = members.allSatisfy { $0.metadata?.rawTags["albumSource"] != "path" && $0.metadata?.albumTitle?.nilIfBlank != nil }
            let confidence = hasEmbeddedAlbum ? (group.artist == nil ? 0.75 : 0.9) : 0.35
            return .init(title: group.title, artist: group.artist, discCount: discs, confidence: confidence, candidateIDs: members.map(\.id))
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func groupingKey(_ value: String) -> String {
        let canonical = value.precomposedStringWithCanonicalMapping
        let collapsed = canonical.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.lowercased()
    }

    /// A number of rippers write a track's title into ARTIST on one file while
    /// leaving ALBUM correct. Attach that single outlier to the clear majority
    /// only when it lives in the same album folder and has no ALBUMARTIST tag.
    /// This deliberately does not merge same-titled albums in separate folders.
    private func mergeSingleTrackArtistOutliers(_ initialGroups: [Group]) -> [Group] {
        var groups = initialGroups
        let titleKeys = Set(groups.map { groupingKey($0.title) })

        for titleKey in titleKeys {
            let matchingIndices = groups.indices.filter { groupingKey(groups[$0].title) == titleKey }
            guard matchingIndices.count > 1 else { continue }
            let sortedBySize = matchingIndices.sorted { groups[$0].candidates.count > groups[$1].candidates.count }
            guard let dominantIndex = sortedBySize.first,
                  groups[dominantIndex].candidates.count > 1,
                  sortedBySize.dropFirst().first.map({ groups[$0].candidates.count }) != groups[dominantIndex].candidates.count
            else { continue }

            let dominantFolders = Set(groups[dominantIndex].candidates.compactMap(\.payload).map { albumFolderKey($0.relativePath) })
            guard !dominantFolders.isEmpty else { continue }
            var outlierIndices: [Int] = []
            for index in matchingIndices where index != dominantIndex {
                let group = groups[index]
                let folders = Set(group.candidates.compactMap(\.payload).map { albumFolderKey($0.relativePath) })
                let lacksAlbumArtist = group.candidates.allSatisfy { $0.metadata?.albumArtist?.nilIfBlank == nil }
                if group.candidates.count == 1, lacksAlbumArtist, !folders.isEmpty, folders.isSubset(of: dominantFolders) {
                    outlierIndices.append(index)
                }
            }
            guard !outlierIndices.isEmpty else { continue }
            for index in outlierIndices { groups[dominantIndex].candidates.append(contentsOf: groups[index].candidates) }
            for index in outlierIndices.sorted(by: >) { groups.remove(at: index) }
        }
        return groups
    }

    private func albumFolderKey(_ relativePath: String) -> String {
        let folder = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
        let withoutDiscSuffix = folder.replacingOccurrences(
            of: #"(?i)\\s*\\[(?:disc|cd)\\s*\\d+\\]$"#,
            with: "",
            options: .regularExpression
        )
        return groupingKey(withoutDiscSuffix)
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
