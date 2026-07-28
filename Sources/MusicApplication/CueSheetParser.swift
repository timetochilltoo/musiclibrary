import Foundation
import MusicDomain

/// Minimal CUE parser for a single audio-file album. INDEX 01 positions are stored in CD frames (75/s).
struct CueSheetParser: Sendable {
    struct Track: Sendable {
        let fileName: String
        let number: Int
        let title: String?
        let artist: String?
        let albumTitle: String?
        let albumArtist: String?
        let startMilliseconds: Int
        let endMilliseconds: Int?
    }

    func parse(url: URL) throws -> [Track] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
            throw NSError(domain: "MusicLibrary.CUE", code: 1, userInfo: [NSLocalizedDescriptionKey: "The CUE sheet could not be decoded as UTF-8 or Shift JIS."])
        }
        var fileName: String?
        var albumTitle: String?
        var albumArtist: String?
        var currentNumber: Int?
        var currentTitle: String?
        var currentArtist: String?
        var entries: [(file: String, number: Int, title: String?, artist: String?, start: Int)] = []

        func quotedValue(_ line: String, keyword: String) -> String? {
            guard line.uppercased().hasPrefix(keyword + " ") else { return nil }
            let value = line.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
            if value.first == "\"", value.last == "\"", value.count >= 2 { return String(value.dropFirst().dropLast()) }
            return value.isEmpty ? nil : String(value)
        }
        func fileValue(_ line: String) -> String? {
            guard line.uppercased().hasPrefix("FILE ") else { return nil }
            let value = line.dropFirst("FILE".count).trimmingCharacters(in: .whitespaces)
            if value.first == "\"", let end = value.dropFirst().firstIndex(of: "\"") { return String(value[value.index(after: value.startIndex)..<end]) }
            return value.split(separator: " ").first.map(String.init)
        }
        func finishCurrent() {
            guard let fileName, let number = currentNumber else { return }
            // A CUE track without INDEX 01 is not playable and is deliberately omitted.
            guard let start = cueStart else { return }
            entries.append((fileName, number, currentTitle, currentArtist, start))
        }
        var cueStart: Int?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let value = fileValue(line) { fileName = value; continue }
            if line.uppercased().hasPrefix("TRACK ") {
                finishCurrent()
                let parts = line.split(separator: " ")
                currentNumber = parts.dropFirst().first.flatMap { Int($0) }
                currentTitle = nil; currentArtist = nil; cueStart = nil
                continue
            }
            if let value = quotedValue(line, keyword: "TITLE") {
                if currentNumber == nil { albumTitle = value } else { currentTitle = value }
                continue
            }
            if let value = quotedValue(line, keyword: "PERFORMER") {
                if currentNumber == nil { albumArtist = value } else { currentArtist = value }
                continue
            }
            if line.uppercased().hasPrefix("INDEX 01 ") {
                let value = line.dropFirst("INDEX 01".count).trimmingCharacters(in: .whitespaces)
                let parts = value.split(separator: ":").compactMap { Int($0) }
                if parts.count == 3 { cueStart = ((parts[0] * 60 + parts[1]) * 1_000) + (parts[2] * 1_000 / 75) }
            }
        }
        finishCurrent()
        return entries.enumerated().map { index, entry in
            .init(fileName: entry.file, number: entry.number, title: entry.title, artist: entry.artist, albumTitle: albumTitle, albumArtist: albumArtist, startMilliseconds: entry.start, endMilliseconds: entries.indices.contains(index + 1) ? entries[index + 1].start : nil)
        }
    }
}
