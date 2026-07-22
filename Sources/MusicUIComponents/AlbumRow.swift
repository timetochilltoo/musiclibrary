import SwiftUI
import MusicDomain

public struct AlbumRow: View {
    public let album: Album
    public let digitalAvailability: DigitalAvailability

    public init(album: Album, digitalAvailability: DigitalAvailability = .none) {
        self.album = album
        self.digitalAvailability = digitalAvailability
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(album.displayTitle).font(.headline)
            HStack(spacing: 10) {
                AvailabilityBadge(title: "CD", isAvailable: album.hasCD)
                AvailabilityBadge(
                    title: "Digital",
                    isAvailable: digitalAvailability != .none,
                    warning: digitalAvailability == .partial || digitalAvailability == .offline || digitalAvailability == .broken
                )
            }
        }
        .padding(.vertical, 2)
    }
}
