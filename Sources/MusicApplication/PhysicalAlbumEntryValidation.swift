import Foundation
import MusicDomain

public enum PhysicalAlbumEntryValidation {
    public struct Failure: LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static func year(_ text: String, field: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count == 4, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(trimmed), (1000...9999).contains(value) else {
            throw Failure(message: "\(field) must be a four-digit year, or left empty.")
        }
        return value
    }

    public static func credits(_ rows: [NewAlbumContributorCredit]) throws -> [NewAlbumContributorCredit] {
        var result: [NewAlbumContributorCredit] = []
        for row in rows {
            let emptyName = row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let emptyOverride = row.creditedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            if emptyName && emptyOverride && row.role == .albumArtist { continue }
            guard !emptyName else { throw Failure(message: "A contributor with a role or credited name needs a name.") }
            result.append(try row.validated())
        }
        guard !result.isEmpty else { throw Failure(message: "Add at least one named contributor.") }
        return result
    }
}
