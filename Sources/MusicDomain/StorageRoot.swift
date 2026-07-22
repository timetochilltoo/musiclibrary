import Foundation

public enum StorageRootStatus: String, Codable, CaseIterable, Sendable {
    case available
    case offline
    case permissionRequired
}

public struct NewStorageRoot: Equatable, Sendable {
    public var displayName: String
    public var lastKnownPath: String
    public var bookmarkData: Data?
    public var volumeIdentifier: String?
    public var status: StorageRootStatus

    public init(displayName: String, lastKnownPath: String, bookmarkData: Data?, volumeIdentifier: String? = nil, status: StorageRootStatus = .available) {
        self.displayName = displayName
        self.lastKnownPath = lastKnownPath
        self.bookmarkData = bookmarkData
        self.volumeIdentifier = volumeIdentifier
        self.status = status
    }

    public func validated() throws -> NewStorageRoot {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Storage root name") }
        guard !lastKnownPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Storage root path") }
        return self
    }
}

public struct StorageRoot: Identifiable, Equatable, Sendable {
    public let id: StorageRootID
    public let displayName: String
    public let lastKnownPath: String
    public let bookmarkData: Data?
    public let volumeIdentifier: String?
    public let status: StorageRootStatus
    public let bookmarkNeedsRefresh: Bool
    public let lastSeenAt: Date?

    public init(id: StorageRootID, displayName: String, lastKnownPath: String, bookmarkData: Data?, volumeIdentifier: String?, status: StorageRootStatus, bookmarkNeedsRefresh: Bool, lastSeenAt: Date?) {
        self.id = id
        self.displayName = displayName
        self.lastKnownPath = lastKnownPath
        self.bookmarkData = bookmarkData
        self.volumeIdentifier = volumeIdentifier
        self.status = status
        self.bookmarkNeedsRefresh = bookmarkNeedsRefresh
        self.lastSeenAt = lastSeenAt
    }
}
