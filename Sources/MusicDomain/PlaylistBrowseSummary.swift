import Foundation

/// Entry-based totals; repeated tracks contribute once per playlist entry.
public struct PlaylistBrowseSummary: Equatable, Sendable {
    public let entryCount: Int
    public let knownDurationCount: Int
    public let availableEntryCount: Int
    public let totalMilliseconds: Int?

    public init(items: [PlaylistItem], tracks: [TrackID: TrackBrowseSummary]) {
        entryCount = items.count
        var known = 0, available = 0, total = 0
        var overflow = false
        for item in items {
            guard let track = tracks[item.trackID] else { continue }
            if track.audioStatus == .available { available += 1 }
            if let duration = track.durationMilliseconds, duration >= 0 {
                known += 1
                let addition = total.addingReportingOverflow(duration)
                if addition.overflow { overflow = true } else { total = addition.partialValue }
            }
        }
        knownDurationCount = known; availableEntryCount = available
        totalMilliseconds = overflow ? nil : total
    }

    public var durationLabel: String? {
        guard entryCount > 0 else { return nil }
        guard let totalMilliseconds else { return "Duration too large to display" }
        guard knownDurationCount > 0 else { return "Duration not recorded" }
        let seconds = totalMilliseconds / 1000
        let time = "\(seconds / 60):" + String(format: "%02d", seconds % 60)
        return knownDurationCount == entryCount ? "Duration: \(time)" : "Known duration: \(time) (\(knownDurationCount)/\(entryCount) entries)"
    }

    public var availabilityLabel: String? {
        entryCount == 0 ? nil : "\(availableEntryCount)/\(entryCount) audio entries available (catalogue)"
    }
}
