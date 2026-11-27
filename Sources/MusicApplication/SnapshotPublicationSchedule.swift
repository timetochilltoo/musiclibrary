import Foundation

public struct SnapshotPublicationSchedule: Sendable, Equatable {
    public private(set) var observedRevision: Int64?
    public private(set) var publishedRevision: Int64?
    private var publicationInvalidated = false

    public init(observedRevision: Int64? = nil, publishedRevision: Int64? = nil) {
        self.observedRevision = observedRevision
        self.publishedRevision = publishedRevision
    }

    public mutating func observe(_ revision: Int64) -> Bool {
        defer { observedRevision = revision }
        if publicationInvalidated { return observedRevision != revision }
        guard let previous = observedRevision else { return false }
        return previous != revision && publishedRevision != revision
    }

    public mutating func markPublished(_ revision: Int64) {
        publishedRevision = revision
        publicationInvalidated = false
    }

    public mutating func invalidatePublication() {
        publicationInvalidated = true
    }

    public var needsPublication: Bool {
        guard let observedRevision else { return false }
        return publicationInvalidated || observedRevision != publishedRevision
    }
}
