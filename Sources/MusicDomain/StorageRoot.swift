import Foundation

public enum StorageRootStatus: String, Codable, CaseIterable, Sendable {
    case available
    case offline
    case permissionRequired
}

/// Decides whether media beneath a registered folder is included in the
/// read-only snapshot consumed by iPad clients.
public enum StorageRootScope: String, Codable, CaseIterable, Sendable {
    case localOnly
    case nasPublished

    public var displayName: String {
        switch self {
        case .localOnly: "This Mac only"
        case .nasPublished: "NAS / iPad music"
        }
    }
}

public struct NewStorageRoot: Equatable, Sendable {
    public var displayName: String
    public var lastKnownPath: String
    public var bookmarkData: Data?
    public var volumeIdentifier: String?
    public var status: StorageRootStatus
    public var scope: StorageRootScope

    public init(displayName: String, lastKnownPath: String, bookmarkData: Data?, volumeIdentifier: String? = nil, status: StorageRootStatus = .available, scope: StorageRootScope = .localOnly) {
        self.displayName = displayName
        self.lastKnownPath = lastKnownPath
        self.bookmarkData = bookmarkData
        self.volumeIdentifier = volumeIdentifier
        self.status = status
        self.scope = scope
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
    public let scope: StorageRootScope
    public let bookmarkNeedsRefresh: Bool
    public let lastSeenAt: Date?

    public init(id: StorageRootID, displayName: String, lastKnownPath: String, bookmarkData: Data?, volumeIdentifier: String?, status: StorageRootStatus, scope: StorageRootScope, bookmarkNeedsRefresh: Bool, lastSeenAt: Date?) {
        self.id = id
        self.displayName = displayName
        self.lastKnownPath = lastKnownPath
        self.bookmarkData = bookmarkData
        self.volumeIdentifier = volumeIdentifier
        self.status = status
        self.scope = scope
        self.bookmarkNeedsRefresh = bookmarkNeedsRefresh
        self.lastSeenAt = lastSeenAt
    }
}
