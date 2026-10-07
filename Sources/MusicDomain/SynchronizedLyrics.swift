import Foundation

/// Conservative line-timed LRC. Unsupported documents remain available as original text.
public struct SynchronizedLyrics: Equatable, Sendable {
    public struct Cue: Equatable, Sendable, Identifiable {
        public let id: Int
        public let milliseconds: Int
        public let text: String
        public var time: TimeInterval { Double(milliseconds) / 1_000 }
    }
    public let cues: [Cue]

    public init?(text: String) {
        var lines: [(time: Int, text: String, order: Int)] = []
        var offset = 0
        var hasOffset = false
        let metadata = ["ar", "al", "au", "ti", "by", "re", "ve", "length", "la"]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            var times: [Int] = []
            while line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                let tag = String(line[line.index(after: line.startIndex)..<end])
                if let time = Self.timestamp(tag) {
                    times.append(time)
                    line = String(line[line.index(after: end)...])
                } else {
                    // Metadata occupies its own line. Unknown/mixed tags require raw fallback.
                    guard times.isEmpty, end == line.index(before: line.endIndex),
                          let colon = tag.firstIndex(of: ":") else { return nil }
                    let key = String(tag[..<colon])
                    let value = String(tag[tag.index(after: colon)...])
                    if key == "offset" {
                        guard !hasOffset, let parsed = Self.signedInteger(value) else { return nil }
                        offset = parsed
                        hasOffset = true
                    } else if !metadata.contains(key) { return nil }
                    line = ""
                    break
                }
            }
            if times.isEmpty {
                guard line.isEmpty else { return nil }
                continue
            }
            // Word-level/enhanced timestamps are not silently treated as simple LRC.
            guard line.range(of: "<[0-9]+:", options: .regularExpression) == nil else { return nil }
            for time in times { lines.append((time, line, lines.count)) }
        }
        guard !lines.isEmpty else { return nil }
        var adjusted: [(time: Int, text: String, order: Int)] = []
        for line in lines {
            // Positive LRC offset advances lyrics; negative delays them.
            // Convention: https://github.com/Clarkkkk/paroles#lyricsinfo
            let result = line.time.subtractingReportingOverflow(offset)
            guard !result.overflow else { return nil }
            adjusted.append((max(0, result.partialValue), line.text, line.order))
        }
        adjusted.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
        var values: [Cue] = []
        for line in adjusted {
            if let last = values.last, last.milliseconds == line.time {
                values[values.count - 1] = Cue(id: last.id, milliseconds: last.milliseconds, text: last.text + "\n" + line.text)
            } else {
                values.append(Cue(id: values.count, milliseconds: line.time, text: line.text))
            }
        }
        cues = values
    }

    /// Stateless lookup handles pause and backward/forward seeking without a second timer.
    public func activeCueIndex(at time: TimeInterval?) -> Int? {
        guard let time, time.isFinite, time >= 0 else { return nil }
        var low = 0, high = cues.count
        while low < high {
            let middle = low + (high - low) / 2
            if cues[middle].time <= time { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }

    private static func digits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    private static func signedInteger(_ value: String) -> Int? {
        let unsigned = value.hasPrefix("+") || value.hasPrefix("-") ? String(value.dropFirst()) : value
        guard digits(unsigned) else { return nil }
        return Int(value)
    }
    private static func timestamp(_ tag: String) -> Int? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, digits(String(parts[0])), let minutes = Int(parts[0]) else { return nil }
        let seconds = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(seconds.count), seconds[0].count == 2,
              digits(String(seconds[0])), let wholeSeconds = Int(seconds[0]), wholeSeconds < 60 else { return nil }
        var fraction = 0
        if seconds.count == 2 {
            guard (1...3).contains(seconds[1].count), digits(String(seconds[1])), let value = Int(seconds[1]) else { return nil }
            fraction = value * (seconds[1].count == 1 ? 100 : seconds[1].count == 2 ? 10 : 1)
        }
        let base = minutes.multipliedReportingOverflow(by: 60_000)
        guard !base.overflow else { return nil }
        let result = base.partialValue.addingReportingOverflow(wholeSeconds * 1_000 + fraction)
        return result.overflow ? nil : result.partialValue
    }
}

/// Lyrics are relative to the selected track, even when its player uses whole-file CUE time.
public enum LyricsPlaybackClock {
    public static func time(sourceTime: TimeInterval, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?) -> TimeInterval? {
        guard sourceTime.isFinite, sourceTime >= 0 else { return nil }
        let start = Double(cueStartMilliseconds ?? 0) / 1_000
        guard start >= 0, sourceTime >= start else { return nil }
        if let end = cueEndMilliseconds {
            let endTime = Double(end) / 1_000
            guard endTime > start, sourceTime < endTime else { return nil }
        }
        return sourceTime - start
    }
}
