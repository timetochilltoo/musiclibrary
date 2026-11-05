import Foundation

public struct LibraryTransferActivity: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sharing = "Shared library update"
        case databaseBackup = "Database backup"
        case archiveExport = "Complete archive export"
        case archiveRestore = "Complete archive restore"
        case databaseRestore = "Database restore"
        case reset = "Catalogue reset"
        case cleanup = "Catalogue cleanup"
    }

    public var active: Kind?
    public var waiting: [Kind]
    public init(active: Kind? = nil, waiting: [Kind] = []) {
        self.active = active
        self.waiting = waiting
    }
    public var isBusy: Bool { active != nil || !waiting.isEmpty }
}
