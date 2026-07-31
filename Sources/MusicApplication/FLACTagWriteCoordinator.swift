import Foundation
import MusicDomain

/// A deliberately narrow, lossless tag writer. It rewrites only the FLAC metadata
/// blocks and copies the encoded audio frames byte-for-byte.
public struct FLACTagWriteCoordinator: Sendable {
    public struct PlannedWrite: Codable, Hashable, Sendable, Identifiable {
        public let trackID: UUID
        public let trackTitle: String
        public let sourcePath: String
        public let changes: [String: String]
        public var id: UUID { trackID }
        public init(trackID: UUID, trackTitle: String, sourcePath: String, changes: [String: String]) { self.trackID = trackID; self.trackTitle = trackTitle; self.sourcePath = sourcePath; self.changes = changes }
    }

    public struct Preview: Codable, Hashable, Sendable, Identifiable {
        public let planned: PlannedWrite
        public let currentTags: [String: String]
        public let changedKeys: [String]
        public let unsupportedReason: String?
        public var id: UUID { planned.trackID }
        public var isWritable: Bool { unsupportedReason == nil && !changedKeys.isEmpty }
        public init(planned: PlannedWrite, currentTags: [String: String], changedKeys: [String], unsupportedReason: String?) { self.planned = planned; self.currentTags = currentTags; self.changedKeys = changedKeys; self.unsupportedReason = unsupportedReason }
    }

    public struct Journal: Codable, Sendable {
        public struct Entry: Codable, Sendable {
            public var trackID: UUID
            public var sourcePath: String
            public var backupPath: String?
            public var status: String
            public var changedKeys: [String]
            public var error: String?
        }
        public var id: UUID
        public var createdAt: Date
        public var completedAt: Date?
        public var status: String
        public var entries: [Entry]
    }

    public enum Error: LocalizedError {
        case unsupported(String)
        case invalidFLAC
        case insufficientSpace
        case verificationFailed(String)
        public var errorDescription: String? {
            switch self {
            case .unsupported(let detail): detail
            case .invalidFLAC: "This file is not a valid FLAC stream."
            case .insufficientSpace: "There is not enough free disk space to make a recoverable backup and temporary replacement."
            case .verificationFailed(let detail): "The replacement file did not pass verification: \(detail)"
            }
        }
    }

    public init() {}
    public func preview(_ planned: PlannedWrite) throws -> Preview {
        let url = URL(fileURLWithPath: planned.sourcePath)
        guard url.pathExtension.lowercased() == "flac" else {
            return .init(planned: planned, currentTags: [:], changedKeys: [], unsupportedReason: "\(url.pathExtension.uppercased().isEmpty ? "Unknown" : url.pathExtension.uppercased()) is catalogue-only in Phase 4. FLAC Vorbis comments are the only supported write-back format.")
        }
        guard let result = try FLACMetadataReader().read(url: url) else { throw Error.invalidFLAC }
        let changed = planned.changes.keys.filter { result.tags[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) != planned.changes[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }.sorted()
        return .init(planned: planned, currentTags: result.tags, changedKeys: changed, unsupportedReason: nil)
    }

    /// Back up every selected original before touching a source. Individual failures
    /// are journalled and do not make later files invisible.
    func execute(_ previews: [Preview], backupRoot: URL) throws -> Journal {
        let selected = previews.filter(\.isWritable)
        var journal = Journal(id: UUID(), createdAt: .now, completedAt: nil, status: "running", entries: selected.map { .init(trackID: $0.planned.trackID, sourcePath: $0.planned.sourcePath, backupPath: nil, status: "pending", changedKeys: $0.changedKeys, error: nil) })
        let batchDirectory = backupRoot.appending(path: journal.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        let journalURL = batchDirectory.appending(path: "journal.json")
        func save() { try? JSONEncoder().encode(journal).write(to: journalURL, options: .atomic) }
        save()

        for index in selected.indices {
            let preview = selected[index]
            let source = URL(fileURLWithPath: preview.planned.sourcePath)
            do {
                try Task.checkCancellation()
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .volumeAvailableCapacityForImportantUsageKey])
                let size = Int64(values.fileSize ?? 0)
                if let available = values.volumeAvailableCapacityForImportantUsage, available < size * 2 { throw Error.insufficientSpace }
                let backup = batchDirectory.appending(path: "\(preview.planned.trackID.uuidString).flac")
                try FileManager.default.copyItem(at: source, to: backup)
                journal.entries[index].backupPath = backup.path
                journal.entries[index].status = "backedUp"; save()

                let originalStream = try FLACMetadataReader().read(url: source)
                let temp = source.deletingLastPathComponent().appending(path: ".musiclibrary-tagwrite-\(UUID().uuidString).tmp.flac")
                defer { try? FileManager.default.removeItem(at: temp) }
                let rewritten = try rewrite(source: source, setting: preview.planned.changes)
                try rewritten.write(to: temp, options: .atomic)
                guard let verified = try FLACMetadataReader().read(url: temp) else { throw Error.verificationFailed("The temporary file could not be read as FLAC.") }
                for key in preview.changedKeys where verified.tags[key] != preview.planned.changes[key] { throw Error.verificationFailed("\(key) was not retained.") }
                guard originalStream?.sampleRateHz == verified.sampleRateHz, originalStream?.bitDepth == verified.bitDepth, originalStream?.channelCount == verified.channelCount else { throw Error.verificationFailed("The audio stream properties changed.") }
                _ = try FileManager.default.replaceItemAt(source, withItemAt: temp)
                journal.entries[index].status = "completed"; save()
            } catch {
                journal.entries[index].status = "failed"
                journal.entries[index].error = error.localizedDescription
                save()
            }
        }
        journal.completedAt = .now
        journal.status = journal.entries.allSatisfy { $0.status == "completed" } ? "completed" : "completedWithErrors"
        save()
        return journal
    }

    /// Restores every completed source from its untouched batch copy.
    func undo(_ journalURL: URL) throws {
        var journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard journal.status != "reverted" else { return }
        for index in journal.entries.indices where journal.entries[index].status == "completed" {
            guard let backupPath = journal.entries[index].backupPath else { continue }
            let source = URL(fileURLWithPath: journal.entries[index].sourcePath)
            let backup = URL(fileURLWithPath: backupPath)
            let replacement = source.deletingLastPathComponent().appending(path: ".musiclibrary-undo-\(UUID().uuidString).tmp")
            try FileManager.default.copyItem(at: backup, to: replacement)
            _ = try FileManager.default.replaceItemAt(source, withItemAt: replacement)
            journal.entries[index].status = "reverted"
        }
        journal.status = "reverted"
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }

    private func rewrite(source: URL, setting changes: [String: String]) throws -> Data {
        let data = try Data(contentsOf: source)
        let bytes = [UInt8](data)
        guard bytes.starts(with: Array("fLaC".utf8)) else { throw Error.invalidFLAC }
        var offset = 4
        var blocks: [(type: UInt8, payload: Data)] = []
        var foundLast = false
        while offset + 4 <= bytes.count, !foundLast {
            let header = bytes[offset]; foundLast = (header & 0x80) != 0
            let type = header & 0x7F
            let length = Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            offset += 4
            guard offset + length <= bytes.count else { throw Error.invalidFLAC }
            blocks.append((type, Data(bytes[offset..<(offset + length)])))
            offset += length
        }
        guard foundLast else { throw Error.invalidFLAC }
        let audio = Data(bytes[offset...])
        var replaced = false
        for index in blocks.indices where blocks[index].type == 4 {
            blocks[index].payload = updatedVorbisPayload(blocks[index].payload, changes: changes)
            replaced = true
            break
        }
        if !replaced { blocks.append((4, newVorbisPayload(changes: changes))) }
        var output = Data("fLaC".utf8)
        for index in blocks.indices {
            let last = index == blocks.indices.last
            let payload = blocks[index].payload
            guard payload.count <= 0xFF_FFFF else { throw Error.invalidFLAC }
            output.append((last ? 0x80 : 0) | blocks[index].type)
            output.append(UInt8((payload.count >> 16) & 0xFF)); output.append(UInt8((payload.count >> 8) & 0xFF)); output.append(UInt8(payload.count & 0xFF))
            output.append(payload)
        }
        output.append(audio)
        return output
    }

    private func updatedVorbisPayload(_ payload: Data, changes: [String: String]) -> Data {
        let bytes = [UInt8](payload); var offset = 0
        guard let vendorLength = readUInt32(bytes, &offset), offset + Int(vendorLength) <= bytes.count else { return newVorbisPayload(changes: changes) }
        let vendor = Data(bytes[offset..<(offset + Int(vendorLength))]); offset += Int(vendorLength)
        guard let count = readUInt32(bytes, &offset) else { return newVorbisPayload(changes: changes) }
        var retained: [String] = []
        for _ in 0..<count {
            guard let length = readUInt32(bytes, &offset), offset + Int(length) <= bytes.count else { break }
            let entry = String(decoding: bytes[offset..<(offset + Int(length))], as: UTF8.self); offset += Int(length)
            let key = entry.split(separator: "=", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
            if changes[key] == nil { retained.append(entry) }
        }
        retained += changes.keys.sorted().compactMap { key in changes[key].map { "\(key)=\($0)" } }
        return encodeVorbis(vendor: vendor, entries: retained)
    }

    private func newVorbisPayload(changes: [String: String]) -> Data { encodeVorbis(vendor: Data("Music Library".utf8), entries: changes.keys.sorted().compactMap { key in changes[key].map { "\(key)=\($0)" } }) }
    private func encodeVorbis(vendor: Data, entries: [String]) -> Data {
        var data = Data(); appendUInt32(UInt32(vendor.count), to: &data); data.append(vendor); appendUInt32(UInt32(entries.count), to: &data)
        for entry in entries { let value = Data(entry.utf8); appendUInt32(UInt32(value.count), to: &data); data.append(value) }
        return data
    }
    private func readUInt32(_ bytes: [UInt8], _ offset: inout Int) -> UInt32? { guard offset + 4 <= bytes.count else { return nil }; defer { offset += 4 }; return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24 }
    private func appendUInt32(_ value: UInt32, to data: inout Data) { data.append(UInt8(value & 0xFF)); data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8((value >> 24) & 0xFF)) }
}
