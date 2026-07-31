import Foundation
import Testing
@testable import MusicApplication

struct FLACTagWriteCoordinatorTests {
    @Test func writesTagsWithBackupAndRestoresFromJournal() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "sample.flac")
        try fixtureFLAC(title: "Old").write(to: source)
        let writer = FLACTagWriteCoordinator()
        let plan = FLACTagWriteCoordinator.PlannedWrite(trackID: UUID(), trackTitle: "New", sourcePath: source.path, changes: ["TITLE": "New", "ALBUM": "Album"])
        let preview = try writer.preview(plan)
        #expect(preview.changedKeys == ["ALBUM", "TITLE"])
        let journal = try writer.execute([preview], backupRoot: folder.appending(path: "backups", directoryHint: .isDirectory))
        #expect(journal.entries[0].error == nil, "\(journal.entries[0].error ?? "unknown")")
        #expect(journal.status == "completed")
        #expect(try FLACMetadataReader().read(url: source)?.tags["TITLE"] == "New")
        let journalURL = folder.appending(path: "backups", directoryHint: .isDirectory).appending(path: journal.id.uuidString, directoryHint: .isDirectory).appending(path: "journal.json")
        try writer.undo(journalURL)
        #expect(try FLACMetadataReader().read(url: source)?.tags["TITLE"] == "Old")
    }

    @Test func refusesNonFLACWithoutChangingIt() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("unchanged".utf8).write(to: file)
        let preview = try FLACTagWriteCoordinator().preview(.init(trackID: UUID(), trackTitle: "x", sourcePath: file.path, changes: ["TITLE": "x"]))
        #expect(preview.unsupportedReason != nil)
        let unchanged = try Data(contentsOf: file)
        #expect(unchanged == Data("unchanged".utf8))
    }

    private func fixtureFLAC(title: String) -> Data {
        func uint32(_ value: UInt32) -> [UInt8] { [UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8((value >> 24) & 255)] }
        let vendor = Array("test".utf8); let entry = Array("TITLE=\(title)".utf8)
        var comment = Data(uint32(UInt32(vendor.count))); comment.append(contentsOf: vendor); comment.append(contentsOf: uint32(1)); comment.append(contentsOf: uint32(UInt32(entry.count))); comment.append(contentsOf: entry)
        let streamInfo = Data(repeating: 0, count: 34)
        var data = Data("fLaC".utf8)
        data.append(0x00); data.append(0); data.append(0); data.append(34); data.append(streamInfo)
        data.append(0x84); data.append(UInt8((comment.count >> 16) & 255)); data.append(UInt8((comment.count >> 8) & 255)); data.append(UInt8(comment.count & 255)); data.append(comment)
        data.append(Data([1, 2, 3, 4, 5]))
        return data
    }
}
