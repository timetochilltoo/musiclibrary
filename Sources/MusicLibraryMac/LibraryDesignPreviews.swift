#if DEBUG
import SwiftUI
import MusicDomain

private enum LibraryDesignPreviewFixtures {
    static let album: Album = .init(
        id: .init(),
        from: .init(
            title: "The Piano",
            editionLabel: "Japan edition · 2011 remaster",
            releaseYear: 1993,
            countryCode: "AU",
            labelName: "Virgin",
            catalogueNumber: "0777 7 88274 2 9",
            barcode: "077778827429",
            remasterYear: 2011,
            mediaFormat: "CD",
            discCount: 1,
            hasCD: true,
            isPhysicalLocationUnknown: true,
            rating: 4
        )
    )

    static let credits: [ContributorCredit] = [
        .init(contributor: .init(id: .init(), name: "Michael Nyman", sortName: "Nyman, Michael"), role: .albumArtist, creditedName: nil, position: 0),
        .init(contributor: .init(id: .init(), name: "Andrew Lloyd Webber", sortName: nil), role: .producer, creditedName: nil, position: 1),
        .init(contributor: .init(id: .init(), name: "Royal Philharmonic Orchestra", sortName: nil), role: .orchestra, creditedName: nil, position: 2),
        .init(contributor: .init(id: .init(), name: "Additional contributor", sortName: nil), role: .performer, creditedName: nil, position: 3)
    ]

    static var aliases: [AlbumAlias] {
        [
            .init(id: UUID(), albumID: album.id, name: "The Piano (Original Soundtrack)", locale: "en", kind: .original),
            .init(id: UUID(), albumID: album.id, name: "La leçon de piano", locale: "fr", kind: .translated),
            .init(id: UUID(), albumID: album.id, name: "ピアノ", locale: "ja", kind: .translated)
        ]
    }
}

#Preview("Album identity — populated") {
    ScrollView {
        AlbumIdentityHeader(
            album: LibraryDesignPreviewFixtures.album,
            artworkPath: nil,
            isLocal: true,
            isPublished: true,
            locationName: "Pak Kee",
            credits: LibraryDesignPreviewFixtures.credits,
            aliases: LibraryDesignPreviewFixtures.aliases,
            canPlay: true,
            onChangeArtwork: {},
            onPlay: {},
            onShuffle: {},
            onAddContributor: {},
            onEditContributor: { _ in },
            onEditCreditedName: { _ in },
            onRemoveContributor: { _ in },
            onAddOtherTitle: {},
            onRemoveOtherTitle: { _ in }
        )
        .padding(24)
    }
    .frame(width: 1_000, height: 760)
}

#Preview("Album identity — sparse physical copy") {
    let album = Album(
        id: .init(),
        from: .init(title: "Uncatalogued pressing", discCount: 1, hasCD: true, isPhysicalLocationUnknown: true)
    )
    ScrollView {
        AlbumIdentityHeader(
            album: album,
            artworkPath: nil,
            isLocal: false,
            isPublished: false,
            locationName: "Unknown",
            credits: [],
            aliases: [],
            canPlay: false,
            onChangeArtwork: {},
            onPlay: {},
            onShuffle: {},
            onAddContributor: {},
            onEditContributor: { _ in },
            onEditCreditedName: { _ in },
            onRemoveContributor: { _ in },
            onAddOtherTitle: {},
            onRemoveOtherTitle: { _ in }
        )
        .padding(24)
    }
    .frame(width: 720, height: 600)
}

private struct LibraryBrowseFixture: View {
    @State private var selectedAlbumID: AlbumID?

    private let albums: [Album] = [
        LibraryDesignPreviewFixtures.album,
        Album(
            id: .init(),
            from: .init(
                title: "The Köln Concert",
                editionLabel: "Legacy Edition",
                releaseYear: 1975,
                countryCode: "DE",
                labelName: "ECM",
                mediaFormat: "CD",
                discCount: 1,
                hasCD: true,
                isPhysicalLocationUnknown: false
            )
        ),
        Album(
            id: .init(),
            from: .init(
                title: "A Very Long Classical Album Title That Must Wrap Gracefully",
                editionLabel: "Deluxe multi-disc set",
                releaseYear: 2024,
                mediaFormat: "SACD",
                discCount: 3,
                hasCD: true,
                isPhysicalLocationUnknown: true
            )
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Albums").font(.largeTitle.bold())
                    Text("Browse, filter, and open an album without losing your place.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("View", selection: .constant(true)) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(true)
                    Label("List", systemImage: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(24)
            Divider()
            AlbumBrowser(
                albums: albums,
                selectedAlbumID: $selectedAlbumID,
                usesGrid: true,
                artworkPaths: [:],
                localAlbumIDs: Set(albums.prefix(1).map(\.id)),
                publishedAlbumIDs: Set(albums.dropFirst().map(\.id)),
                onDelete: { _ in }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PhysicalAlbumEntryFixture: View {
    @State private var step = 0
    @State private var title = "The Piano"
    @State private var artist = "Michael Nyman"
    @State private var location = "Choose a location"
    @State private var saveArtwork = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Physical Album").font(.largeTitle.bold())
                    Text("Find a pressing, review its identity, then place your copy.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Step", selection: $step) {
                    Text("Find").tag(0)
                    Text("Review").tag(1)
                    Text("Place").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            .padding(24)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LibraryPanel {
                        LibrarySectionHeader(
                            step == 0 ? "1. Find a release" : step == 1 ? "2. Review the pressing" : "3. Place your copy",
                            subtitle: step == 0 ? "Search MusicBrainz only when you are ready; manual entry remains available." : "Returned metadata is a suggestion until you save the album."
                        )
                        if step == 0 {
                            TextField("Album title", text: $title)
                                .textFieldStyle(.roundedBorder)
                            TextField("Artist (optional)", text: $artist)
                                .textFieldStyle(.roundedBorder)
                            Button("Find on MusicBrainz…", systemImage: "magnifyingglass") { step = 1 }
                        } else if step == 1 {
                            HStack(spacing: 14) {
                                AlbumArtworkImage(path: nil)
                                    .frame(width: 118, height: 118)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(title).font(.headline)
                                    Text(artist).foregroundStyle(.secondary)
                                    Text("1993 · AU · Virgin · CD").font(.caption).foregroundStyle(.secondary)
                                    Text("1 disc · 12 tracks").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Toggle("Save selected cover with album", isOn: $saveArtwork)
                            Button("Use Selected Release") { step = 2 }
                        } else {
                            LabeledContent("Title", value: title)
                            LabeledContent("Artist", value: artist)
                            Picker("Stored in", selection: $location) {
                                Text("Choose a location").tag("Choose a location")
                                Text("Pak Kee").tag("Pak Kee")
                                Text("Box set").tag("Box set")
                            }
                            Text("No audio files are created or changed. Physical tracks remain catalogue-only until files are explicitly attached.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(24)
            }
            HStack {
                Spacer()
                Button("Cancel") { step = 0 }
                Button(step == 2 ? "Add Physical Album" : "Continue") { step = min(2, step + 1) }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 0 && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
            .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview("Library browse — fixture") {
    LibraryBrowseFixture()
        .frame(width: 980, height: 700)
}

#Preview("Physical entry — regular fixture") {
    PhysicalAlbumEntryFixture()
        .frame(width: 900, height: 700)
}

#Preview("Physical entry — compact fixture") {
    PhysicalAlbumEntryFixture()
        .frame(width: 640, height: 700)
}
#endif
