import Foundation

public struct ExternalReleasePreview: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let releaseDate: String?
    public let countryCode: String?
    public let catalogueNumber: String?
    public let mediaCount: Int

    public init(id: String, title: String, artist: String?, releaseDate: String?, countryCode: String?, catalogueNumber: String?, mediaCount: Int) {
        self.id = id; self.title = title; self.artist = artist; self.releaseDate = releaseDate; self.countryCode = countryCode; self.catalogueNumber = catalogueNumber; self.mediaCount = mediaCount
    }
}

public protocol MetadataLookupProviding: Sendable {
    func searchRelease(title: String, artist: String?) async throws -> [ExternalReleasePreview]
}

public enum MetadataLookupError: LocalizedError, Equatable, Sendable {
    case missingTitle, invalidResponse, serviceStatus(Int)
    public var errorDescription: String? {
        switch self {
        case .missingTitle: "Enter an album title before searching."
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw MetadataLookupError.missingTitle }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedArtist?.isEmpty == false ? "release:\"\(trimmedTitle)\" AND artist:\"\(trimmedArtist!)\"" : "release:\"\(trimmedTitle)\""
        let cacheKey = "\(trimmedTitle.lowercased())|\(trimmedArtist?.lowercased() ?? "")"
        if let cached = await cache.value(for: cacheKey) { return cached }
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "12")]
        guard let url = components.url else { throw MetadataLookupError.invalidResponse }
        let results = try await fetch(url: url)
        await cache.store(results, for: cacheKey)
        return results
    }

    private func fetch(url: URL) async throws -> [ExternalReleasePreview] {
        for attempt in 0..<3 {
            do {
                try await rateLimiter.waitForTurn()
                var request = URLRequest(url: url)
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
        return payload.releases.map { .init(id: $0.id, title: $0.title, artist: $0.artistCredit?.map(\.name).joined(separator: ", "), releaseDate: $0.date, countryCode: $0.country ?? $0.releaseEvents?.first?.area?.iso31661Codes?.first, catalogueNumber: $0.labelInfo?.compactMap(\.catalogueNumber).first, mediaCount: $0.media?.count ?? 0) }
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
        let delay = nextAllowedRequest.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        nextAllowedRequest = Date().addingTimeInterval(1)
    }
}

private extension MusicBrainzMetadataProvider {
    struct Response: Decodable { let releases: [Release] }
    struct Release: Decodable {
        let id: String; let title: String; let date: String?; let country: String?; let artistCredit: [ArtistCredit]?; let labelInfo: [LabelInfo]?; let media: [Media]?; let releaseEvents: [ReleaseEvent]?
        enum CodingKeys: String, CodingKey { case id, title, date, country, media; case artistCredit = "artist-credit"; case labelInfo = "label-info"; case releaseEvents = "release-events" }
    }
    struct ArtistCredit: Decodable { let name: String }
    struct LabelInfo: Decodable { let catalogueNumber: String?; enum CodingKeys: String, CodingKey { case catalogueNumber = "catalog-number" } }
    struct Media: Decodable {}
    struct ReleaseEvent: Decodable { let area: Area? }
    struct Area: Decodable { let iso31661Codes: [String]?; enum CodingKeys: String, CodingKey { case iso31661Codes = "iso-3166-1-codes" } }
}
