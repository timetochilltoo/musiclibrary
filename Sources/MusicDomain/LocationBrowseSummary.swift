import Foundation

/// Read-only hierarchy and exact-location contents. Child contents are not rolled up.
public struct LocationBrowseSummary: Sendable {
    public let locations: [PhysicalLocation]
    private let byID: [PhysicalLocationID: PhysicalLocation]

    public init(locations: [PhysicalLocation]) {
        self.locations = locations
        byID = Dictionary(locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func ancestors(of location: PhysicalLocation) -> [PhysicalLocation] {
        var result = [PhysicalLocation]()
        var current: PhysicalLocation? = location
        var visited = Set<PhysicalLocationID>()
        while let value = current, visited.insert(value.id).inserted {
            result.append(value)
            current = value.parentID.flatMap { byID[$0] }
        }
        return result.reversed()
    }

    public func path(of location: PhysicalLocation) -> String {
        ancestors(of: location).map(\.name).joined(separator: " › ")
    }

    public func children(of id: PhysicalLocationID) -> [PhysicalLocation] {
        sorted(locations.filter { $0.parentID == id && $0.id != id })
    }

    public var ordered: [PhysicalLocation] {
        var result = [PhysicalLocation]()
        var visited = Set<PhysicalLocationID>()
        func append(_ location: PhysicalLocation) {
            guard visited.insert(location.id).inserted else { return }
            result.append(location)
            for child in children(of: location.id) { append(child) }
        }
        for root in sorted(locations.filter { $0.parentID == nil || byID[$0.parentID!] == nil }) { append(root) }
        // Defensive fallback for cyclic imported data; never hide a location.
        for remaining in sorted(locations) { append(remaining) }
        return result
    }

    public func directAlbums(at id: PhysicalLocationID, albums: [Album]) -> [Album] {
        albums.filter { $0.hasCD && $0.physicalLocationID == id }
    }

    public func boxes(at id: PhysicalLocationID, boxSets: [BoxSet]) -> [BoxSet] {
        boxSets.filter { $0.physicalLocationID == id }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func sorted(_ values: [PhysicalLocation]) -> [PhysicalLocation] {
        values.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id.description < $1.id.description : comparison == .orderedAscending
        }
    }
}
