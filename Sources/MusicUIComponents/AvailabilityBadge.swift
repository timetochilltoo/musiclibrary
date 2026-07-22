import SwiftUI
import MusicDomain

public struct AvailabilityBadge: View {
    private let title: String
    private let isAvailable: Bool
    private let warning: Bool

    public init(title: String, isAvailable: Bool, warning: Bool = false) {
        self.title = title
        self.isAvailable = isAvailable
        self.warning = warning
    }

    public var body: some View {
        Label(title, systemImage: isAvailable ? (warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill") : "circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(warning ? .orange : (isAvailable ? .green : .secondary))
            .accessibilityLabel("\(title): \(isAvailable ? (warning ? "needs attention" : "available") : "not available")")
    }
}
