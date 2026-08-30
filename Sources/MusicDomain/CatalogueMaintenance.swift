import Foundation

public struct CatalogueCleanupPreview: Equatable, Sendable {
    public let supersededImportBatchCount: Int
    public let orphanContributorCount: Int
    public let unusedLocationCount: Int

    public init(
        supersededImportBatchCount: Int,
        orphanContributorCount: Int,
        unusedLocationCount: Int
    ) {
        self.supersededImportBatchCount = supersededImportBatchCount
        self.orphanContributorCount = orphanContributorCount
        self.unusedLocationCount = unusedLocationCount
    }

    public var totalCount: Int {
        supersededImportBatchCount + orphanContributorCount + unusedLocationCount
    }
}

public struct CatalogueCleanupOptions: Equatable, Sendable {
    public var removeSupersededImportBatches: Bool
    public var removeOrphanContributors: Bool
    public var removeUnusedLocations: Bool

    public init(
        removeSupersededImportBatches: Bool = true,
        removeOrphanContributors: Bool = true,
        removeUnusedLocations: Bool = true
    ) {
        self.removeSupersededImportBatches = removeSupersededImportBatches
        self.removeOrphanContributors = removeOrphanContributors
        self.removeUnusedLocations = removeUnusedLocations
    }
}

public struct CatalogueCleanupResult: Equatable, Sendable {
    public let removedImportBatchCount: Int
    public let removedContributorCount: Int
    public let removedLocationCount: Int

    public init(
        removedImportBatchCount: Int,
        removedContributorCount: Int,
        removedLocationCount: Int
    ) {
        self.removedImportBatchCount = removedImportBatchCount
        self.removedContributorCount = removedContributorCount
        self.removedLocationCount = removedLocationCount
    }

    public var totalCount: Int {
        removedImportBatchCount + removedContributorCount + removedLocationCount
    }
}
