import Foundation
import Testing
@testable import MusicApplication

struct MusicBrainzMetadataProviderTests {
    @Test("Metadata and artwork requests use a bounded timeout")
    func requestTimeoutIsBounded() {
        let request = MusicNetworkRequestPolicy.request(url: URL(string: "https://example.com")!)
        #expect(request.timeoutInterval == 30)
    }

    @Test("MusicBrainz release previews decode without changing catalogue data")
    func decodesReleasePreviews() throws {
        let data = Data("""
        { "releases": [{
          "id": "e7a1", "title": "Kind of Blue", "date": "1959-08-17", "country": "JP",
          "artist-credit": [{ "name": "Miles Davis" }],
          "label-info": [{ "catalog-number": "SRCS 9701" }], "media": [{ "tracks": [{ "title": "So What" }] }, { "tracks": [{ "title": "Flamenco Sketches" }] }]
        }] }
        """.utf8)
        let results = try MusicBrainzMetadataProvider.decodeReleases(from: data)
        #expect(results == [.init(id: "e7a1", title: "Kind of Blue", artist: "Miles Davis", releaseDate: "1959-08-17", countryCode: "JP", catalogueNumber: "SRCS 9701", mediaCount: 2, trackTitles: ["So What", "Flamenco Sketches"])])
    }

    @Test("A selected release detail supplies its real track list")
    func decodesReleaseDetails() throws {
        let data = Data("""
        { "id": "detail-1", "title": "Album", "date": "1981-04-12", "country": "GB", "barcode": "0123456789012",
          "artist-credit": [{ "name": "Artist" }],
          "label-info": [{ "catalog-number": "CAT-123", "label": { "name": "Example Records" } }],
          "media": [{ "format": "CD", "tracks": [{ "title": "First track" }, { "title": "Second track" }] }] }
        """.utf8)
        let result = try MusicBrainzMetadataProvider.decodeReleaseDetail(from: data)
        #expect(result.trackTitles == ["First track", "Second track"])
        #expect(result.mediaCount == 1)
        #expect(result.releaseYear == 1981)
        #expect(result.countryCode == "GB")
        #expect(result.catalogueNumber == "CAT-123")
        #expect(result.labelName == "Example Records")
        #expect(result.barcode == "0123456789012")
        #expect(result.mediaFormat == "CD")
    }

    @Test("MusicBrainz response cache returns a stored manual-search result")
    func cachesResults() async {
        let cache = MusicBrainzResponseCache()
        let preview = ExternalReleasePreview(id: "release", title: "Album", artist: nil, releaseDate: nil, countryCode: nil, catalogueNumber: nil, mediaCount: 1)
        await cache.store([preview], for: "album|")
        #expect(await cache.value(for: "album|") == [preview])
    }
}
