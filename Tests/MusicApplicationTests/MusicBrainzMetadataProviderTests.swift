import Foundation
import Testing
@testable import MusicApplication

struct MusicBrainzMetadataProviderTests {
    @Test("MusicBrainz release previews decode without changing catalogue data")
    func decodesReleasePreviews() throws {
        let data = Data("""
        { "releases": [{
          "id": "e7a1", "title": "Kind of Blue", "date": "1959-08-17", "country": "JP",
          "artist-credit": [{ "name": "Miles Davis" }],
          "label-info": [{ "catalog-number": "SRCS 9701" }], "media": [{}, {}]
        }] }
        """.utf8)
        let results = try MusicBrainzMetadataProvider.decodeReleases(from: data)
        #expect(results == [.init(id: "e7a1", title: "Kind of Blue", artist: "Miles Davis", releaseDate: "1959-08-17", countryCode: "JP", catalogueNumber: "SRCS 9701", mediaCount: 2)])
    }

    @Test("MusicBrainz response cache returns a stored manual-search result")
    func cachesResults() async {
        let cache = MusicBrainzResponseCache()
        let preview = ExternalReleasePreview(id: "release", title: "Album", artist: nil, releaseDate: nil, countryCode: nil, catalogueNumber: nil, mediaCount: 1)
        await cache.store([preview], for: "album|")
        #expect(await cache.value(for: "album|") == [preview])
    }
}
