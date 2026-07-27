import Foundation

/// Reads the FLAC metadata blocks at the beginning of a file. FLAC stores its
/// user-facing tags as Vorbis comments, which AVFoundation does not expose
/// consistently for every FLAC file.
struct FLACMetadataReader: Sendable {
    struct Result: Sendable {
        var tags: [String: String] = [:]
        var durationMilliseconds: Int?
        var sampleRateHz: Int?
        var bitDepth: Int?
        var channelCount: Int?
    }

    func read(url: URL) throws -> Result? {
        guard url.pathExtension.lowercased() == "flac" else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try readExactly(4, from: handle) == Data("fLaC".utf8) else { return nil }

        var result = Result()
        var isLastBlock = false
        while !isLastBlock {
            guard let header = try readExactly(4, from: handle), header.count == 4 else { break }
            let bytes = [UInt8](header)
            isLastBlock = (bytes[0] & 0x80) != 0
            let type = bytes[0] & 0x7f
            let length = Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            switch type {
            case 0:
                if let block = try readExactly(length, from: handle) { applyStreamInfo(block, to: &result) }
            case 4:
                if let block = try readExactly(length, from: handle) { result.tags = parseVorbisComments(block) }
            default:
                try handle.seek(toOffset: handle.offsetInFile + UInt64(length))
            }
        }
        return result
    }

    private func readExactly(_ count: Int, from handle: FileHandle) throws -> Data? {
        guard count >= 0, let data = try handle.read(upToCount: count), data.count == count else { return nil }
        return data
    }

    private func applyStreamInfo(_ data: Data, to result: inout Result) {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { return }
        let packed = bytes[10...17].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let sampleRate = Int((packed >> 44) & 0xFFFFF)
        let channels = Int((packed >> 41) & 0x7) + 1
        let bitDepth = Int((packed >> 36) & 0x1F) + 1
        let totalSamples = packed & 0xFFFFFFFFF
        result.sampleRateHz = sampleRate > 0 ? sampleRate : nil
        result.channelCount = channels
        result.bitDepth = bitDepth
        if sampleRate > 0, totalSamples > 0 {
            result.durationMilliseconds = Int((Double(totalSamples) / Double(sampleRate) * 1_000).rounded())
        }
    }

    private func parseVorbisComments(_ data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        var offset = 0
        guard let vendorLength = littleEndianUInt32(bytes, at: &offset), vendorLength <= bytes.count - offset else { return [:] }
        offset += Int(vendorLength)
        guard let count = littleEndianUInt32(bytes, at: &offset) else { return [:] }
        var tags: [String: [String]] = [:]
        for _ in 0..<count {
            guard let length = littleEndianUInt32(bytes, at: &offset), length <= bytes.count - offset else { break }
            let value = String(decoding: bytes[offset..<(offset + Int(length))], as: UTF8.self)
            offset += Int(length)
            guard let separator = value.firstIndex(of: "=") else { continue }
            let key = String(value[..<separator]).uppercased()
            let tagValue = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !tagValue.isEmpty else { continue }
            tags[key, default: []].append(tagValue)
        }
        return tags.mapValues { $0.joined(separator: " / ") }
    }

    private func littleEndianUInt32(_ bytes: [UInt8], at offset: inout Int) -> Int? {
        guard offset + 4 <= bytes.count else { return nil }
        let value = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        offset += 4
        return value
    }
}
