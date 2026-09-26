import AppKit
import SwiftUI
import MusicDomain

/// Shared visual primitives for the Mac catalogue. These keep the application
/// screens visually related without making the domain or persistence layers
/// depend on SwiftUI.
struct LibraryPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
    }
}

struct LibrarySectionHeader: View {
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let actionTitle: String?
    let actionSymbol: String?

    init(
        _ title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        actionSymbol: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.actionTitle = actionTitle
        self.actionSymbol = actionSymbol
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if let action, let actionTitle {
                Button(actionTitle, systemImage: actionSymbol ?? "plus", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct LibraryPill: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.11), in: Capsule())
            .overlay { Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1) }
    }
}

struct LibraryMetadataItem: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct LibraryMetadataGrid: View {
    let items: [LibraryMetadataItem]

    var body: some View {
        if !items.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                ForEach(items) { item in
                    GridRow {
                        Text(item.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .gridCellAnchor(.leading)
                        Text(item.value)
                            .font(.callout)
                            .textSelection(.enabled)
                            .gridCellAnchor(.leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AlbumIdentityHeader: View {
    let album: Album
    let artworkPath: String?
    let isLocal: Bool
    let isPublished: Bool
    let locationName: String?
    let credits: [ContributorCredit]
    let aliases: [AlbumAlias]
    let canPlay: Bool
    let onChangeArtwork: () -> Void
    let onPlay: () -> Void
    let onShuffle: () -> Void
    let onAddContributor: () -> Void
    let onEditContributor: (ContributorCredit) -> Void
    let onEditCreditedName: (ContributorCredit) -> Void
    let onRemoveContributor: (ContributorCredit) -> Void
    let onAddOtherTitle: () -> Void
    let onRemoveOtherTitle: (AlbumAlias) -> Void

    var body: some View {
        LibraryPanel {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    artwork
                    details
                }
                VStack(alignment: .leading, spacing: 18) {
                    artwork
                    details
                }
            }
        }
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            AlbumArtworkImage(path: artworkPath)
                .frame(width: 210, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
            Button("Change cover", systemImage: "photo.badge.plus", action: onChangeArtwork)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(9)
                .help("Choose a different front cover")
                .accessibilityLabel("Change album cover")
        }
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(3)
                    .textSelection(.enabled)
                if let artist = albumArtist {
                    Text(artist)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Artist not recorded")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                if let edition = album.editionLabel, !edition.isEmpty {
                    Text(edition)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !aliases.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    LibrarySectionHeader(
                        "Other titles",
                        subtitle: "Alternative, translated, and romanized names used for search",
                        actionTitle: "Add title",
                        actionSymbol: "plus",
                        action: onAddOtherTitle
                    )
                    ForEach(aliases) { alias in
                        AlbumOtherTitleRow(alias: alias, onRemove: { onRemoveOtherTitle(alias) })
                    }
                }
            }

            LibraryMetadataGrid(items: metadataItems)

            HStack(spacing: 7) {
                if album.hasCD {
                    LibraryPill(title: "Physical", symbol: "opticaldisc", tint: .orange)
                }
                if isLocal {
                    LibraryPill(title: "On this Mac", symbol: "laptopcomputer", tint: .blue)
                }
                if isPublished {
                    LibraryPill(title: "Published", symbol: "externaldrive.connected.to.line.below", tint: .purple)
                }
                if album.isFavourite {
                    LibraryPill(title: "Favourite", symbol: "heart.fill", tint: .pink)
                }
            }

            creditSummary

            HStack(spacing: 10) {
                Button("Play", systemImage: "play.fill", action: onPlay)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canPlay)
                Button("Shuffle", systemImage: "shuffle", action: onShuffle)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!canPlay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataItems: [LibraryMetadataItem] {
        var result: [LibraryMetadataItem] = []
        if let year = album.releaseYear { result.append(.init(label: "Released", value: String(year))) }
        if let label = album.labelName, !label.isEmpty { result.append(.init(label: "Label", value: label)) }
        if let country = album.countryCode, !country.isEmpty { result.append(.init(label: "Country", value: country)) }
        if let catalogue = album.catalogueNumber, !catalogue.isEmpty { result.append(.init(label: "Catalogue", value: catalogue)) }
        if let barcode = album.barcode, !barcode.isEmpty { result.append(.init(label: "Barcode", value: barcode)) }
        if let format = album.mediaFormat, !format.isEmpty { result.append(.init(label: "Format", value: format)) }
        if let remaster = album.remasterYear { result.append(.init(label: "Remaster", value: String(remaster))) }
        result.append(.init(label: "Discs", value: String(album.discCount)))
        if let rating = album.rating { result.append(.init(label: "Rating", value: "\(rating) / 5")) }
        if let locationName { result.append(.init(label: "Location", value: locationName)) }
        return result
    }

    private var albumArtist: String? {
        let credit = credits.first(where: { $0.role == .albumArtist }) ?? credits.first
        return credit.map { $0.creditedName ?? $0.contributor.name }
    }

    private var creditSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Credits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Manage", systemImage: "person.2", action: onAddContributor)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            if credits.isEmpty {
                Text("No contributors recorded")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(credits.prefix(3))) { credit in
                    HStack(spacing: 8) {
                        Text(credit.creditedName ?? credit.contributor.name)
                            .font(.callout)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Text(credit.role.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Menu {
                            Button("Edit contributor name", systemImage: "pencil") { onEditContributor(credit) }
                            Button("Edit credited name", systemImage: "text.cursor") { onEditCreditedName(credit) }
                            Divider()
                            Button("Remove credit", systemImage: "trash", role: .destructive) { onRemoveContributor(credit) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Actions for \(credit.contributor.name)")
                    }
                }
                if credits.count > 3 {
                    Text("+\(credits.count - 3) more credits")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 2)
    }
}

struct AlbumOtherTitleRow: View {
    let alias: AlbumAlias
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(alias.name)
                    .textSelection(.enabled)
                Text([alias.kind.rawValue.capitalized, alias.locale].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Remove Other Title", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Actions for \(alias.name)")
        }
    }
}
