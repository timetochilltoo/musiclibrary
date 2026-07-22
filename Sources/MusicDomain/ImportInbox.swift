import Foundation

public enum ImportBatchStatus: String, Codable, CaseIterable, Sendable {
    case scanning, completed, cancelled, failed
}

public enum ImportCandidateStatus: String, Codable, CaseIterable, Sendable {
    case pending, failed
}

public struct ImportBatch: Identifiable, Equatable, Sendable {
    public let id: ImportBatchID
    public let storageRootID: StorageRootID?
    public let status: ImportBatchStatus
    public let sourceDescription: String?
    public let startedAt: Date
    public let completedAt: Date?
    public let processedCount: Int
    public let candidateCount: Int
    public let errorCount: Int
    public let errorSummary: String?

    public init(id: ImportBatchID, storageRootID: StorageRootID?, status: ImportBatchStatus, sourceDescription: String?, startedAt: Date, completedAt: Date?, processedCount: Int, candidateCount: Int, errorCount: Int, errorSummary: String?) {
        self.id = id; self.storageRootID = storageRootID; self.status = status; self.sourceDescription = sourceDescription; self.startedAt = startedAt; self.completedAt = completedAt; self.processedCount = processedCount; self.candidateCount = candidateCount; self.errorCount = errorCount; self.errorSummary = errorSummary
    }
}

public struct ImportCandidatePayload: Codable, Equatable, Sendable {
    public let relativePath: String
    public let fileName: String
    public let contentTypeIdentifier: String
    public let fileSize: Int64
    public let modifiedAt: Date?

    public init(relativePath: String, fileName: String, contentTypeIdentifier: String, fileSize: Int64, modifiedAt: Date?) {
        self.relativePath = relativePath; self.fileName = fileName; self.contentTypeIdentifier = contentTypeIdentifier; self.fileSize = fileSize; self.modifiedAt = modifiedAt
    }
}

public struct ImportCandidate: Identifiable, Equatable, Sendable {
    public let id: ImportCandidateID
    public let batchID: ImportBatchID
    public let status: ImportCandidateStatus
    public let payload: ImportCandidatePayload?
    public let errorMessage: String?

    public init(id: ImportCandidateID, batchID: ImportBatchID, status: ImportCandidateStatus, payload: ImportCandidatePayload?, errorMessage: String?) {
        self.id = id; self.batchID = batchID; self.status = status; self.payload = payload; self.errorMessage = errorMessage
    }
}
