import CryptoKit
import Foundation

/// Reads the public DSF container header and its optional trailing ID3 tag.
/// DSF stores one-bit DSD samples; AVFoundation does not expose this container as a normal audio asset.
struct DSFMetadataReader: Sendable {
    struct Result: Sendable {
        let tags: [String: String]
        let sampleRateHz: Int
        let bitDepth: Int
        let channelCount: Int
        let sampleCount: UInt64
        let dataOffset: UInt64
        let blockSizePerChannel: Int

        var durationMilliseconds: Int? {
            guard sampleRateHz > 0 else { return nil }
            return Int((Double(sampleCount) / Double(sampleRateHz) * 1_000).rounded())
        }
    }

    func read(url: URL) throws -> Result {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try requiredData(handle, count: 92)
        guard header.ascii(at: 0, count: 4) == "DSD ", header.ascii(at: 28, count: 4) == "fmt " else {
            throw DSFError.invalidContainer
        }
        let fmtSize = header.uint64LE(at: 32)
        guard fmtSize >= 52 else { throw DSFError.invalidContainer }
        let channelCount = Int(header.uint32LE(at: 52))
        let sampleRate = Int(header.uint32LE(at: 56))
        let bitDepth = Int(header.uint32LE(at: 60))
        let sampleCount = header.uint64LE(at: 64)
        let blockSize = Int(header.uint32LE(at: 72))
        let dataOffset = UInt64(28) + fmtSize + 12
        guard channelCount > 0, channelCount <= 8, sampleRate > 0, bitDepth == 1, sampleCount > 0, blockSize > 0 else {
            throw DSFError.unsupportedStream
        }
        let fileSize = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard dataOffset <= UInt64(fileSize) else { throw DSFError.invalidContainer }
        let metadataOffset = header.uint64LE(at: 20)
        let tags = try metadataOffset > 0 ? readID3(handle: handle, at: metadataOffset) : [:]
        return .init(tags: tags, sampleRateHz: sampleRate, bitDepth: bitDepth, channelCount: channelCount, sampleCount: sampleCount, dataOffset: dataOffset, blockSizePerChannel: blockSize)
    }

    private func readID3(handle: FileHandle, at offset: UInt64) throws -> [String: String] {
        try handle.seek(toOffset: offset)
        let header = try requiredData(handle, count: 10)
        guard header.ascii(at: 0, count: 3) == "ID3" else { return [:] }
        let version = Int(header[3])
        guard version == 3 || version == 4 else { return [:] }
        let bodySize = header.synchsafeInt(at: 6)
        guard bodySize > 0, bodySize <= 4_000_000 else { return [:] }
        let body = try requiredData(handle, count: bodySize)
        var cursor = 0
        var tags: [String: String] = [:]
        let mappings = ["TIT2": "TITLE", "TALB": "ALBUM", "TPE1": "ARTIST", "TPE2": "ALBUMARTIST", "TRCK": "TRACKNUMBER", "TPOS": "DISCNUMBER", "TDRC": "DATE", "TYER": "DATE", "TCON": "GENRE"]
        while cursor + 10 <= body.count {
            let frameID = body.ascii(at: cursor, count: 4)
            guard frameID.allSatisfy({ $0.isLetter || $0.isNumber }) else { break }
            let size = version == 4 ? body.synchsafeInt(at: cursor + 4) : Int(body.uint32BE(at: cursor + 4))
            guard size > 0, cursor + 10 + size <= body.count else { break }
            if let key = mappings[frameID], let value = decodeTextFrame(body.subdata(in: (cursor + 10)..<(cursor + 10 + size)))?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                tags[key] = value
            }
            cursor += 10 + size
        }
        return tags
    }

    private func decodeTextFrame(_ data: Data) -> String? {
        guard let encoding = data.first else { return nil }
        let bytes = data.dropFirst()
        switch encoding {
        case 0: return String(data: bytes, encoding: .isoLatin1)
        case 1: return String(data: bytes, encoding: .utf16)
        case 2: return String(data: bytes, encoding: .utf16BigEndian)
        case 3: return String(data: bytes, encoding: .utf8)
        default: return nil
        }
    }
}

/// Creates a private, replaceable PCM cache for DSF playback. Source DSF files are never modified.
struct DSFPCMTranscoder: Sendable {
    func playableURL(for sourceURL: URL) throws -> URL {
        guard sourceURL.pathExtension.caseInsensitiveCompare("dsf") == .orderedSame else { return sourceURL }
        let reader = DSFMetadataReader()
        let metadata = try reader.read(url: sourceURL)
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fingerprint = "\(sourceURL.standardizedFileURL.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let name = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = try cacheDirectory()
        let outputURL = directory.appending(path: "\(name).wav")
        if FileManager.default.fileExists(atPath: outputURL.path) { return outputURL }
        let stagingURL = directory.appending(path: "\(name).partial")
        try? FileManager.default.removeItem(at: stagingURL)
        do {
            try transcode(sourceURL: sourceURL, metadata: metadata, outputURL: stagingURL)
            try FileManager.default.moveItem(at: stagingURL, to: outputURL)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    private func cacheDirectory() throws -> URL {
        let root = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appending(path: "MusicLibrary/DSFPlayback", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func transcode(sourceURL: URL, metadata: DSFMetadataReader.Result, outputURL: URL) throws {
        let factor = decimationFactor(sampleRate: metadata.sampleRateHz)
        let outputRate = metadata.sampleRateHz / factor
        let coefficients = FIR.lowPass(taps: 255, cutoff: 0.45 / Double(factor))
        var filters = (0..<metadata.channelCount).map { _ in FIR(coefficients: coefficients, factor: factor) }
        let input = try FileHandle(forReadingFrom: sourceURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? input.close(); try? output.close() }
        try output.write(contentsOf: Data(repeating: 0, count: 44))
        try input.seek(toOffset: metadata.dataOffset)
        let perChannelBytes = Int((metadata.sampleCount + 7) / 8)
        var bytesRemaining = perChannelBytes * metadata.channelCount
        var outputBytes = 0
        while bytesRemaining > 0 {
            let bytesForRound = min(bytesRemaining, metadata.blockSizePerChannel * metadata.channelCount)
            let round = try requiredData(input, count: bytesForRound)
            var channelFrames: [[Double]] = []
            var offset = 0
            for channel in 0..<metadata.channelCount {
                let count = min(metadata.blockSizePerChannel, round.count - offset)
                guard count >= 0 else { throw DSFError.invalidContainer }
                var frames: [Double] = []
                if count > 0 {
                    for byte in round[offset..<(offset + count)] {
                        for bit in 0..<8 {
                            if let value = filters[channel].push((byte & (1 << bit)) == 0 ? -1 : 1) { frames.append(value) }
                        }
                    }
                }
                channelFrames.append(frames)
                offset += count
            }
            let frameCount = channelFrames.map(\.count).min() ?? 0
            var pcm = Data(capacity: frameCount * metadata.channelCount * 3)
            for frame in 0..<frameCount {
                for channel in 0..<metadata.channelCount {
                    let sample = Int32((max(-1, min(1, channelFrames[channel][frame])) * 8_388_607).rounded())
                    pcm.append(UInt8(truncatingIfNeeded: sample))
                    pcm.append(UInt8(truncatingIfNeeded: sample >> 8))
                    pcm.append(UInt8(truncatingIfNeeded: sample >> 16))
                }
            }
            try output.write(contentsOf: pcm)
            outputBytes += pcm.count
            bytesRemaining -= bytesForRound
        }
        try output.seek(toOffset: 0)
        try output.write(contentsOf: wavHeader(sampleRate: outputRate, channels: metadata.channelCount, dataByteCount: outputBytes))
    }

    private func decimationFactor(sampleRate: Int) -> Int {
        for target in [176_400, 88_200, 44_100] where sampleRate >= target && sampleRate.isMultiple(of: target) { return sampleRate / target }
        return max(1, sampleRate / 176_400)
    }

    private func wavHeader(sampleRate: Int, channels: Int, dataByteCount: Int) -> Data {
        let byteRate = sampleRate * channels * 3
        var data = Data("RIFF".utf8)
        data.appendUInt32LE(UInt32(36 + dataByteCount)); data.append(Data("WAVEfmt ".utf8))
        data.appendUInt32LE(16); data.appendUInt16LE(1); data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate)); data.appendUInt32LE(UInt32(byteRate)); data.appendUInt16LE(UInt16(channels * 3)); data.appendUInt16LE(24)
        data.append(Data("data".utf8)); data.appendUInt32LE(UInt32(dataByteCount))
        return data
    }
}

private struct FIR {
    let coefficients: [Double]
    let factor: Int
    private var samples: [Double]
    private var cursor = 0
    private var count = 0

    init(coefficients: [Double], factor: Int) {
        self.coefficients = coefficients; self.factor = factor; samples = Array(repeating: 0, count: coefficients.count)
    }

    mutating func push(_ sample: Double) -> Double? {
        samples[cursor] = sample; cursor = (cursor + 1) % samples.count; count += 1
        guard count >= samples.count, count.isMultiple(of: factor) else { return nil }
        var value = 0.0
        for index in coefficients.indices {
            value += coefficients[index] * samples[(cursor - 1 - index + samples.count) % samples.count]
        }
        return value
    }

    static func lowPass(taps: Int, cutoff: Double) -> [Double] {
        let middle = Double(taps - 1) / 2
        var values = (0..<taps).map { index -> Double in
            let x = Double(index) - middle
            let sinc = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            let window = 0.42 - 0.5 * cos(2 * .pi * Double(index) / Double(taps - 1)) + 0.08 * cos(4 * .pi * Double(index) / Double(taps - 1))
            return sinc * window
        }
        let total = values.reduce(0, +)
        values = values.map { $0 / total }
        return values
    }
}

private enum DSFError: LocalizedError { case invalidContainer, unsupportedStream
    var errorDescription: String? {
        switch self {
        case .invalidContainer: return "This DSF file has an invalid container header."
        case .unsupportedStream: return "This DSF stream uses an unsupported channel layout or sample format."
        }
    }
}

private func requiredData(_ handle: FileHandle, count: Int) throws -> Data {
    guard let data = try handle.read(upToCount: count), data.count == count else { throw DSFError.invalidContainer }
    return data
}

private extension Data {
    func ascii(at offset: Int, count: Int) -> String { String(decoding: self[offset..<(offset + count)], as: UTF8.self) }
    func uint32LE(at offset: Int) -> UInt32 { self[offset..<(offset + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
    func uint32BE(at offset: Int) -> UInt32 { self[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) } }
    func uint64LE(at offset: Int) -> UInt64 { self[offset..<(offset + 8)].enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * $1.offset) } }
    func synchsafeInt(at offset: Int) -> Int { self[offset..<(offset + 4)].reduce(0) { ($0 << 7) | Int($1 & 0x7f) } }
    mutating func appendUInt16LE(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8)) }
    mutating func appendUInt32LE(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) } }
}
