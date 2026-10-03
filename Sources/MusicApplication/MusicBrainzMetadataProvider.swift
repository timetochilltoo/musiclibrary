import Foundation
import MusicDomain

public struct ExternalReleasePreview: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let releaseDate: String?
    public let countryCode: String?
    public let catalogueNumber: String?
    public let mediaCount: Int
    public let trackTitles: [String]
    public let labelName: String?
    public let barcode: String?
    public let mediaFormat: String?
    public let media: [ExternalMediumPreview]

    public init(id: String, title: String, artist: String?, releaseDate: String?, countryCode: String?, catalogueNumber: String?, mediaCount: Int, trackTitles: [String] = [], labelName: String? = nil, barcode: String? = nil, mediaFormat: String? = nil, media: [ExternalMediumPreview] = []) {
        self.id = id; self.title = title; self.artist = artist; self.releaseDate = releaseDate; self.countryCode = countryCode; self.catalogueNumber = catalogueNumber; self.mediaCount = mediaCount; self.trackTitles = trackTitles; self.labelName = labelName; self.barcode = barcode; self.mediaFormat = mediaFormat
        self.media = media
    }

    /// Never manufacture positions or silently save a partial listing.
    public var physicalDiscs: [NewAlbumDisc]? {
        guard !media.isEmpty, media.count == mediaCount, mediaCount <= 99,
              media.compactMap(\.position).sorted() == Array(1...mediaCount) else { return nil }
        var result: [NewAlbumDisc] = []
        for medium in media.sorted(by: { ($0.position ?? 0) < ($1.position ?? 0) }) {
            guard !medium.hasUnsupportedContent, let position = medium.position, let count = medium.trackCount, count > 0,
                  medium.tracks.count == count,
                  medium.tracks.compactMap(\.position).sorted() == Array(1...count) else { return nil }
            let tracks = medium.tracks + (medium.pregap.map { [$0] } ?? [])
            if let pregap = medium.pregap, pregap.position != 0 { return nil }
            var drafts: [NewAlbumTrack] = []
            for track in tracks.sorted(by: { ($0.position ?? 0) < ($1.position ?? 0) }) {
                guard let number = track.position, let title = track.title,
                      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      track.durationMilliseconds.map({ $0 >= 0 }) ?? true else { return nil }
                drafts.append(.init(number: number, draft: .init(title: title, displayPosition: track.displayPosition, durationMilliseconds: track.durationMilliseconds)))
            }
            result.append(.init(number: position, title: medium.title, mediaFormat: medium.format, tracks: drafts))
        }
        return result
    }

    public var coverArtworkURL: URL? { URL(string: "https://coverartarchive.org/release/\(id)/front") }
    /// A small derivative for responsive comparison previews. Downloads still use `coverArtworkURL`.
    public var coverArtworkThumbnailURL: URL? { URL(string: "https://coverartarchive.org/release/\(id)/front-250") }
    public var releaseYear: Int? { releaseDate.flatMap { Int($0.prefix(4)) } }
}

public struct ExternalMediumPreview: Equatable, Sendable, Decodable {
    public let position: Int?
    public let title: String?
    public let format: String?
    public let trackCount: Int?
    public let tracks: [ExternalTrackPreview]
    public let pregap: ExternalTrackPreview?
    public let hasUnsupportedContent: Bool

    enum CodingKeys: String, CodingKey {
        case position, title, format, tracks, pregap
        case trackCount = "track-count", dataTracks = "data-tracks", dataTrackCount = "data-track-count"
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        position = try? values.decode(Int.self, forKey: .position)
        title = try? values.decode(String.self, forKey: .title)
        format = try? values.decode(String.self, forKey: .format)
        trackCount = try? values.decode(Int.self, forKey: .trackCount)
        tracks = (try? values.decode([ExternalTrackPreview].self, forKey: .tracks)) ?? []
        pregap = try? values.decode(ExternalTrackPreview.self, forKey: .pregap)
        let dataCount = try? values.decode(Int.self, forKey: .dataTrackCount)
        let dataTracks = try? values.decode([ExternalTrackPreview].self, forKey: .dataTracks)
        let hasPregap = values.contains(.pregap) && (try? values.decodeNil(forKey: .pregap)) != true
        let hasDataCount = values.contains(.dataTrackCount) && (try? values.decodeNil(forKey: .dataTrackCount)) != true
        let hasDataTracks = values.contains(.dataTracks) && (try? values.decodeNil(forKey: .dataTracks)) != true
        hasUnsupportedContent = (dataCount ?? 0) != 0 || !(dataTracks ?? []).isEmpty
            || (hasPregap && pregap == nil) || (hasDataCount && dataCount == nil) || (hasDataTracks && dataTracks == nil)
    }
}

public struct ExternalTrackPreview: Equatable, Sendable, Decodable {
    public let position: Int?
    public let displayPosition: String?
    public let title: String?
    public let durationMilliseconds: Int?
    enum CodingKeys: String, CodingKey { case position, number, title, length, recording }
    private struct Recording: Decodable { let title: String? }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        position = try? values.decode(Int.self, forKey: .position)
        displayPosition = try? values.decode(String.self, forKey: .number)
        let trackTitle = try? values.decode(String.self, forKey: .title)
        title = trackTitle.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? (try? values.decode(Recording.self, forKey: .recording))?.title
        durationMilliseconds = try? values.decode(Int.self, forKey: .length)
    }
}

public protocol MetadataLookupProviding: Sendable {
    func searchRelease(title: String, artist: String?) async throws -> [ExternalReleasePreview]
    func lookupRelease(_ lookup: MusicBrainzReleaseLookup) async throws -> [ExternalReleasePreview]
    func releaseDetails(id: String) async throws -> ExternalReleasePreview
}

public enum MetadataLookupError: LocalizedError, Equatable, Sendable {
    case missingTitle, invalidResponse, serviceStatus(Int), invalidReleaseURL, invalidBarcode, missingCatalogueNumber
    public var errorDescription: String? {
        switch self {
        case .missingTitle: "Enter an album title before searching."
        case .invalidReleaseURL: "Paste a MusicBrainz release URL, not an artist or release-group URL."
        case .invalidBarcode: "Enter the barcode digits, including any leading zeros."
        case .missingCatalogueNumber: "Enter a catalogue number before searching."
        case .invalidResponse: "The metadata service returned an unreadable response."
        case .serviceStatus(let status): "The metadata service returned HTTP \(status)."
        }
    }
}

/// An explicitly invoked, text-only MusicBrainz release search. It never uploads audio
/// and returns ephemeral previews only; accepting catalogue changes stays a separate step.
public struct MusicBrainzMetadataProvider: MetadataLookupProviding {
    private let session: URLSession
    private let rateLimiter: MusicBrainzRateLimiter
    private let cache: MusicBrainzResponseCache

    public init(session: URLSession = .shared, rateLimiter: MusicBrainzRateLimiter = .init(), cache: MusicBrainzResponseCache = .init()) {
        self.session = session
        self.rateLimiter = rateLimiter
        self.cache = cache
    }

    public func searchRelease(title: String, artist: String?) async throws -> [ExternalReleasePreview] {
        try await lookupRelease(.title(title, artist: artist))
    }

    public func lookupRelease(_ lookup: MusicBrainzReleaseLookup) async throws -> [ExternalReleasePreview] {
        if case .releaseURL(let text) = lookup {
            return [try await releaseDetails(id: MusicBrainzReleaseLookup.releaseID(from: text))]
        }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        let query = try lookup.query
        let cacheKey = "search:" + query
        if let cached = await cache.value(for: cacheKey) { return cached }
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "12"), URLQueryItem(name: "inc", value: "recordings")]
        guard let url = components.url else { throw MetadataLookupError.invalidResponse }
        let results = try await fetch(url: url)
        await cache.store(results, for: cacheKey)
        return results
    }

    public func releaseDetails(id: String) async throws -> ExternalReleasePreview {
        let id = try MusicBrainzReleaseLookup.validatedID(id)
        let cacheKey = "detail:" + id
        if let cached = await cache.value(for: cacheKey), let detail = cached.first { return detail }
        let url = URL(string: "https://musicbrainz.org/ws/2/release/\(id)?inc=recordings+artist-credits+labels+release-groups&fmt=json")!
        try await rateLimiter.waitForTurn()
        var request = MusicNetworkRequestPolicy.request(url: url)
        request.setValue("MusicLibrary/0.1 (+https://github.com/timetochilltoo/musiclibrary)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw MetadataLookupError.invalidResponse }
        let detail = try Self.decodeReleaseDetail(from: data)
        guard detail.id.lowercased() == id else { throw MetadataLookupError.invalidResponse }
        await cache.store([detail], for: cacheKey)
        return detail
    }

    private func fetch(url: URL) async throws -> [ExternalReleasePreview] {
        for attempt in 0..<3 {
            do {
                try await rateLimiter.waitForTurn()
                var request = MusicNetworkRequestPolicy.request(url: url)
                request.setValue("MusicLibrary/0.1 (+https://github.com/timetochilltoo/musiclibrary)", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw MetadataLookupError.invalidResponse }
                guard (200...299).contains(http.statusCode) else { throw MetadataLookupError.serviceStatus(http.statusCode) }
                return try Self.decodeReleases(from: data)
            } catch let error as MetadataLookupError where error.isTransient && attempt < 2 {
                try await Task.sleep(for: .seconds(Double(attempt + 1)))
            } catch _ as URLError where attempt < 2 {
                try await Task.sleep(for: .seconds(Double(attempt + 1)))
            }
        }
        throw MetadataLookupError.invalidResponse
    }

    static func decodeReleases(from data: Data) throws -> [ExternalReleasePreview] {
        let payload = try JSONDecoder().decode(Response.self, from: data)
        return payload.releases.map(Self.preview)
    }

    static func decodeReleaseDetail(from data: Data) throws -> ExternalReleasePreview {
        let release = try JSONDecoder().decode(Release.self, from: data)
        return preview(from: release)
    }

    private static func preview(from release: Release) -> ExternalReleasePreview {
        var mediaFormats: [String] = []
        for format in release.media?.compactMap(\.format) ?? [] where !format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !mediaFormats.contains(format) { mediaFormats.append(format) }
        }
        return .init(
            id: release.id,
            title: release.title,
            artist: release.artistCredit?.map(\.name).joined(separator: ", "),
            releaseDate: release.date,
            countryCode: release.country ?? release.releaseEvents?.first?.area?.iso31661Codes?.first,
            catalogueNumber: release.labelInfo?.compactMap(\.catalogueNumber).first,
            mediaCount: release.media?.count ?? 0,
            trackTitles: release.media?.flatMap(\.tracks).compactMap(\.title) ?? [],
            labelName: release.labelInfo?.compactMap { $0.label?.name }.first,
            barcode: release.barcode,
            mediaFormat: mediaFormats.isEmpty ? nil : mediaFormats.joined(separator: ", "),
            media: release.media ?? []
        )
    }
}

public actor MusicBrainzResponseCache {
    private var values: [String: [ExternalReleasePreview]] = [:]
    public init() {}
    public func value(for key: String) -> [ExternalReleasePreview]? { values[key] }
    public func store(_ value: [ExternalReleasePreview], for key: String) { values[key] = value }
}

private extension MetadataLookupError {
    var isTransient: Bool {
        if case .serviceStatus(let status) = self { return status == 429 || (500...599).contains(status) }
        return false
    }
}

public actor MusicBrainzRateLimiter {
    private var nextAllowedRequest = Date.distantPast

    public init() {}

    public func waitForTurn() async throws {
        // Reserve before suspending: actor reentrancy must not give concurrent
        // detail/search requests the same slot.
        let now = Date()
        let slot = max(now, nextAllowedRequest)
        nextAllowedRequest = slot.addingTimeInterval(1)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
    }
}

private extension MusicBrainzMetadataProvider {
    struct Response: Decodable { let releases: [Release] }
    struct Release: Decodable {
        let id: String; let title: String; let date: String?; let country: String?; let barcode: String?; let artistCredit: [ArtistCredit]?; let labelInfo: [LabelInfo]?; let media: [ExternalMediumPreview]?; let releaseEvents: [ReleaseEvent]?
        enum CodingKeys: String, CodingKey { case id, title, date, country, barcode, media; case artistCredit = "artist-credit"; case labelInfo = "label-info"; case releaseEvents = "release-events" }
    }
    struct ArtistCredit: Decodable { let name: String }
    struct LabelInfo: Decodable { let catalogueNumber: String?; let label: Label?; enum CodingKeys: String, CodingKey { case catalogueNumber = "catalog-number"; case label } }
    struct Label: Decodable { let name: String? }
    struct ReleaseEvent: Decodable { let area: Area? }
    struct Area: Decodable { let iso31661Codes: [String]?; enum CodingKeys: String, CodingKey { case iso31661Codes = "iso-3166-1-codes" } }
}
