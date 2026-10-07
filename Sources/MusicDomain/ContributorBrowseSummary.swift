import Foundation

public struct ContributorAlbumRole: Hashable, Sendable {
    public let contributorID: ContributorID
    public let albumID: AlbumID
    public let role: ContributorRole
    public init(contributorID: ContributorID, albumID: AlbumID, role: ContributorRole) {
        self.contributorID = contributorID; self.albumID = albumID; self.role = role
    }
}

public struct ContributorBrowseSummary: Equatable, Sendable {
    public private(set) var albumRoles: [AlbumID: Set<ContributorRole>] = [:]
    public init() {}
    public var roles: [ContributorRole] {
        let values = Set(albumRoles.values.flatMap { $0 })
        return ContributorRole.allCases.filter { values.contains($0) }
    }
    public func albumIDs(role: ContributorRole? = nil) -> Set<AlbumID> {
        Set(albumRoles.compactMap { id, roles in (role.map { roles.contains($0) } ?? true) ? id : nil })
    }
    public static func index(contributors: [Contributor], albums: [Album], credits: [ContributorAlbumRole]) -> [ContributorID: Self] {
        let contributorIDs = Set(contributors.map(\.id)), albumIDs = Set(albums.map(\.id))
        var values = Dictionary(uniqueKeysWithValues: contributorIDs.map { ($0, Self()) })
        for credit in credits where contributorIDs.contains(credit.contributorID) && albumIDs.contains(credit.albumID) {
            values[credit.contributorID, default: Self()].albumRoles[credit.albumID, default: []].insert(credit.role)
        }
        return values
    }
    public static func matching(_ contributors: [Contributor], summaries: [ContributorID: Self], query: String, role: ContributorRole?) -> [Contributor] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return contributors.filter { contributor in
            (term.isEmpty || contributor.name.localizedCaseInsensitiveContains(term) || (contributor.sortName?.localizedCaseInsensitiveContains(term) ?? false))
                && (role.map { summaries[contributor.id]?.roles.contains($0) == true } ?? true)
        }.sorted {
            let comparison = ($0.sortName ?? $0.name).localizedStandardCompare($1.sortName ?? $1.name)
            return comparison == .orderedSame ? $0.id.description < $1.id.description : comparison == .orderedAscending
        }
    }
}
