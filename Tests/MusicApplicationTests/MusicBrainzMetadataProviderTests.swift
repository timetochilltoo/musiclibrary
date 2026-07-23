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
}
