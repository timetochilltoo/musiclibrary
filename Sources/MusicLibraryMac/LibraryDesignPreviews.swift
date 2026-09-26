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
#endif
