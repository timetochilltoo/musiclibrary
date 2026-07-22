import Foundation

public struct NewPhysicalLocation: Sendable, Equatable {
    public var name: String
    public var parentID: PhysicalLocationID?
    public var sortOrder: Int
    public var notes: String?

    public init(name: String, parentID: PhysicalLocationID? = nil, sortOrder: Int = 0, notes: String? = nil) {
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.notes = notes
    }

    public func validated() throws -> NewPhysicalLocation {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Location name") }
        return self
    }
}

public struct PhysicalLocation: Identifiable, Equatable, Sendable {
    public let id: PhysicalLocationID
    public let name: String
    public let parentID: PhysicalLocationID?
    public let sortOrder: Int
    public let notes: String?

    public init(id: PhysicalLocationID, name: String, parentID: PhysicalLocationID?, sortOrder: Int, notes: String?) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.notes = notes
    }
}

public struct NewBoxSet: Sendable, Equatable {
    public var title: String
    public var editionLabel: String?
    public var physicalLocationID: PhysicalLocationID
    public var notes: String?

    public init(title: String, editionLabel: String? = nil, physicalLocationID: PhysicalLocationID, notes: String? = nil) {
        self.title = title
        self.editionLabel = editionLabel
        self.physicalLocationID = physicalLocationID
        self.notes = notes
    }

    public func validated() throws -> NewBoxSet {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.requiredField("Box set title") }
        return self
    }
}

public struct BoxSet: Identifiable, Equatable, Sendable {
    public let id: BoxSetID
    public let title: String
    public let editionLabel: String?
    public let physicalLocationID: PhysicalLocationID

    public init(id: BoxSetID, title: String, editionLabel: String?, physicalLocationID: PhysicalLocationID) {
        self.id = id
        self.title = title
        self.editionLabel = editionLabel
        self.physicalLocationID = physicalLocationID
    }
}

public struct BoxSetMembership: Identifiable, Equatable, Sendable {
    public let album: Album
    public let boxSetID: BoxSetID
    public let position: Int

    public var id: AlbumID { album.id }

    public init(album: Album, boxSetID: BoxSetID, position: Int) {
        self.album = album
        self.boxSetID = boxSetID
        self.position = position
    }
}

public struct AlbumBoxPlacement: Equatable, Sendable {
    public let boxSetID: BoxSetID
    public let boxSetTitle: String
    public let position: Int

    public init(boxSetID: BoxSetID, boxSetTitle: String, position: Int) {
        self.boxSetID = boxSetID
        self.boxSetTitle = boxSetTitle
        self.position = position
    }
}
