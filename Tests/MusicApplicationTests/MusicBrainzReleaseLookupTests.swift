import Foundation
import Testing
@testable import MusicApplication

@Suite("MusicBrainz exact release lookup")
struct MusicBrainzReleaseLookupTests {
    private let id = "9383a6f5-9607-4a36-9c68-8663aad3592b"

    @Test("Concurrent requests reserve different rate-limit slots before suspending")
    func rateLimit() async throws {
        let limiter = MusicBrainzRateLimiter()
        let times = try await withThrowingTaskGroup(of: Date.self) { group in
            for _ in 0..<3 {
                group.addTask { try await limiter.waitForTurn(); return Date() }
            }
            var times: [Date] = []
            for try await time in group { times.append(time) }
            return times.sorted()
        }
        #expect(times.count == 3)
        #expect(times[1].timeIntervalSince(times[0]) >= 0.8)
        #expect(times[2].timeIntervalSince(times[1]) >= 0.8)
    }

    @Test("Search values preserve leading zeros and escape Lucene literals")
    func queries() throws {
        #expect(try MusicBrainzReleaseLookup.barcode(" 0077778827429 ").query == "barcode:\"0077778827429\"")
        #expect(try MusicBrainzReleaseLookup.catalogueNumber(" 0777 7 ", artist: "Nyman").query == "catno:\"0777 7\" AND artist:\"Nyman\"")
        #expect(try MusicBrainzReleaseLookup.title("A\" OR barcode:*", artist: "X\\Y").query == "release:\"A\\\" OR barcode:*\" AND artist:\"X\\\\Y\"")
        for barcode in ["", "012x", "１２３", "12 34"] {
            #expect(throws: MetadataLookupError.invalidBarcode) { try MusicBrainzReleaseLookup.barcode(barcode).query }
        }
        #expect(throws: MetadataLookupError.missingCatalogueNumber) { try MusicBrainzReleaseLookup.catalogueNumber("  ", artist: nil).query }
    }

    @Test("Release URL parsing accepts only trusted exact release identifiers")
    func URLs() throws {
        for url in ["https://musicbrainz.org/release/\(id)", "http://www.musicbrainz.org/release/\(id.uppercased())/?x=1#info"] {
            #expect(try MusicBrainzReleaseLookup.releaseID(from: url) == id)
        }
        for url in ["https://evil.example/release/\(id)", "https://musicbrainz.org.evil.example/release/\(id)",
                    "https://user@musicbrainz.org/release/\(id)", "https://musicbrainz.org:443/release/\(id)",
                    "https://musicbrainz.org/release-group/\(id)", "https://musicbrainz.org/artist/\(id)",
                    "https://musicbrainz.org/release/invalid", "https://musicbrainz.org/release/\(id)/extra", "file:///release/\(id)"] {
            #expect(throws: MetadataLookupError.invalidReleaseURL) { try MusicBrainzReleaseLookup.releaseID(from: url) }
        }
        #expect(throws: MetadataLookupError.invalidReleaseURL) { try MusicBrainzReleaseLookup.validatedID("../artist?id=oops") }
    }

    @Test("Provider dispatches typed searches and pasted URLs through the fixed release API")
    func providerRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LookupFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = MusicBrainzResponseCache()
        let provider = MusicBrainzMetadataProvider(session: session, cache: cache)
        let request = MusicBrainzReleaseLookup.catalogueNumber("CAT \"001\" & 02", artist: "A/B")
        let query = try request.query
        let result = try await provider.lookupRelease(request)
        #expect(result.first?.title == query)
        #expect(await cache.value(for: "search:" + query) == result)
        let exact = try await provider.lookupRelease(.releaseURL("https://musicbrainz.org/release/\(id)?ignored=1"))
        #expect(exact.first?.id == id)
        #expect(exact.first?.title == "Exact release")
        #expect(await cache.value(for: "detail:" + id) == exact)
        #expect(try await provider.lookupRelease(.releaseURL("https://musicbrainz.org/release/\(id)")) == exact)
        #expect(try await provider.lookupRelease(request) == result)
    }
}

/// Offline transport fixture: echoes decoded query text, verifies trusted origin.
private final class LookupFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(url.scheme == "https")
            #expect(url.host == "musicbrainz.org")
            #expect(url.path == "/ws/2/release" || url.path.hasPrefix("/ws/2/release/"))
            #expect(request.timeoutInterval == 30)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value
            let release: [String: Any] = ["id": query == nil ? url.lastPathComponent : "9383a6f5-9607-4a36-9c68-8663aad3592b", "title": query ?? "Exact release"]
            let payload: [String: Any]
            if query == nil { payload = release } else { payload = ["releases": [release]] }
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
