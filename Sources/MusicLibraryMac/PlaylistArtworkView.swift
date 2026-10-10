import SwiftUI

/// Decorative collage. The surrounding playlist name supplies its accessible identity.
struct PlaylistArtworkView: View {
    let paths: [String]
    let size: CGFloat

    var body: some View {
        GeometryReader { geometry in
            if paths.isEmpty {
                ZStack {
                    LinearGradient(colors: [.accentColor.opacity(0.22), .purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note.list")
                        .font(.system(size: size * 0.36, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            } else if paths.count == 1 {
                tile(paths[0], width: geometry.size.width, height: geometry.size.height)
            } else {
                let width = (geometry.size.width - 2) / 2
                let halfHeight = (geometry.size.height - 2) / 2
                HStack(spacing: 2) {
                    if paths.count == 4 {
                        VStack(spacing: 2) {
                            tile(paths[0], width: width, height: halfHeight)
                            tile(paths[1], width: width, height: halfHeight)
                        }
                    } else {
                        tile(paths[0], width: width, height: geometry.size.height)
                    }
                    if paths.count >= 3 {
                        VStack(spacing: 2) {
                            tile(paths[paths.count == 4 ? 2 : 1], width: width, height: halfHeight)
                            tile(paths[paths.count - 1], width: width, height: halfHeight)
                        }
                    } else {
                        tile(paths[1], width: width, height: geometry.size.height)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .accessibilityHidden(true)
    }

    private func tile(_ path: String, width: CGFloat, height: CGFloat) -> some View {
        AlbumArtworkImage(path: path).frame(width: width, height: height).clipped()
    }
}
