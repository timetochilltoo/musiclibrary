import Foundation

public struct SnapshotPublicationSchedule: Sendable, Equatable {
    public private(set) var observedRevision: Int64?
    public private(set) var publishedRevision: Int64?

    public init(observedRevision: Int64? = nil, publishedRevision: Int64? = nil) {
        self.observedRevision = observedRevision
        self.publishedRevision = publishedRevision
    }

    public mutating func observe(_ revision: Int64) -> Bool {
        defer { observedRevision = revision }
        guard let previous = observedRevision else { return false }
        return previous != revision && publishedRevision != revision
    }

    public mutating func markPublished(_ revision: Int64) {
        publishedRevision = revision
    }

    public var needsPublication: Bool {
        guard let observedRevision else { return false }
        return observedRevision != publishedRevision
    }
}
