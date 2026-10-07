import Foundation

public enum BoxSetBrowseSummary {
    public static func matching(_ boxes: [BoxSet], locations: [PhysicalLocation], query: String) -> [BoxSet] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hierarchy = LocationBrowseSummary(locations: locations)
        return boxes.filter { box in
            let path = locations.first { $0.id == box.physicalLocationID }.map { hierarchy.path(of: $0) } ?? ""
            return query.isEmpty || [box.title, box.editionLabel ?? "", path].contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return comparison == .orderedSame ? $0.id.description < $1.id.description : comparison == .orderedAscending
        }
    }

    public static func members(ids: [AlbumID], albums: [Album]) -> [Album] {
        let byID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<AlbumID>()
        return ids.compactMap { seen.insert($0).inserted ? byID[$0] : nil }
    }
}
