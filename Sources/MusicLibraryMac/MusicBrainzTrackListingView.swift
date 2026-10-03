import SwiftUI
import MusicApplication

/// Shared read-only preview in Find and Review. Never flattens disc boundaries.
struct MusicBrainzTrackListingView: View {
    let release: ExternalReleasePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if release.media.isEmpty {
                Text("No structured disc listing returned.").foregroundStyle(.secondary)
            }
            ForEach(Array(release.media.sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }.enumerated()), id: \.offset) { _, medium in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Disc \(medium.position.map(String.init) ?? "—")" + (medium.title.map { " · \($0)" } ?? "") + (medium.format.map { " · \($0)" } ?? ""))
                        .font(.subheadline.bold())
                    ForEach(Array(((medium.pregap.map { [$0] } ?? []) + medium.tracks).sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }.enumerated()), id: \.offset) { _, track in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(track.displayPosition ?? track.position.map(String.init) ?? "—")
                                .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                            Text(track.title ?? "Title unavailable").frame(maxWidth: .infinity, alignment: .leading)
                            if let milliseconds = track.durationMilliseconds, milliseconds >= 0 {
                                Text(String(format: "%d:%02d", milliseconds / 60_000, (milliseconds / 1_000) % 60))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
