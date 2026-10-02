import Foundation

/// Text-only lookup intent. Pasted URLs are parsed, never fetched directly.
public enum MusicBrainzReleaseLookup: Sendable, Equatable {
    case title(String, artist: String?)
    case barcode(String)
    case catalogueNumber(String, artist: String?)
    case releaseURL(String)

    static func releaseID(from text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              ["musicbrainz.org", "www.musicbrainz.org"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil else {
            throw MetadataLookupError.invalidReleaseURL
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard (parts.count == 3 || (parts.count == 4 && parts[3].isEmpty)),
              parts[0].isEmpty, parts[1] == "release" else { throw MetadataLookupError.invalidReleaseURL }
        return try validatedID(String(parts[2]))
    }

    static func validatedID(_ text: String) throws -> String {
        guard text.count == 36, let uuid = UUID(uuidString: text), uuid.uuidString.lowercased() == text.lowercased() else {
            throw MetadataLookupError.invalidReleaseURL
        }
        return uuid.uuidString.lowercased()
    }

    var query: String {
        get throws {
            func literal(_ text: String) -> String {
                "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }
            func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
            func withArtist(_ query: String, _ artist: String?) -> String {
                guard let artist, !trimmed(artist).isEmpty else { return query }
                return query + " AND artist:" + literal(trimmed(artist))
            }
            switch self {
            case .title(let title, let artist):
                guard !trimmed(title).isEmpty else { throw MetadataLookupError.missingTitle }
                return withArtist("release:" + literal(trimmed(title)), artist)
            case .barcode(let barcode):
                let value = trimmed(barcode)
                guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw MetadataLookupError.invalidBarcode }
                return "barcode:" + literal(value)
            case .catalogueNumber(let number, let artist):
                guard !trimmed(number).isEmpty else { throw MetadataLookupError.missingCatalogueNumber }
                return withArtist("catno:" + literal(trimmed(number)), artist)
            case .releaseURL:
                throw MetadataLookupError.invalidReleaseURL
            }
        }
    }
}
