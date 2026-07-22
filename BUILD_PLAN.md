# Music Library — Product and Build Plan

Date: 22 July 2026

Detailed coding handoff: [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md)

Implementation baseline (22 July 2026): the macOS catalogue foundation, persistent SQLite schema, album/location/box-set creation UI, and ten automated tests are complete in Git commit `2d02f10`. The next implementation slice is album editing and box-set membership management.

## 1. Recommendation

Build this as a **local-first macOS music catalog and lossless player**, with iPad support designed in from the start. Treat Android, network sync, AI cover recognition, and AI music generation as later modules.

The idea is sound. The risk is scope: the current requirements combine a cataloguing system, metadata editor, file scanner, high-quality player, multi-device service, lyrics client, image-recognition tool, and generative-music studio. Trying to deliver all of them together would delay the useful part and make data loss more likely.

The first useful release should do five things extremely well:

1. Catalogue physical releases and their locations.
2. Scan digital music without altering the files.
3. Match and correct metadata with human confirmation.
4. Search the combined library.
5. Reliably play local lossless files.

### One album profile in the interface

The user sees one album profile for both physical and digital availability. Its header shows simple derived indicators:

- `CD ✓` when the album's physical-CD field is enabled;
- `Digital ✓` when at least one playable digital asset is recorded.

The same profile contains the title, edition label, artists, artwork, release information, and track list. The physical location appears in a **Physical** section, while folder, format, sample rate, bit depth, and availability appear in a **Digital** section. If only one form exists, the other indicator is unticked and its section offers an add/import action.

The CD tick is a field on the album. Digital availability is calculated from its track files so it cannot become stale. Internally, digital availability has richer states: `none`, `complete`, `partial`, `offline`, and `broken`. The normal profile still shows a simple tick, with a warning when the digital copy is incomplete or unavailable.

## 2. Product decisions to make before coding

### Recommended decisions

- **Primary platforms:** macOS 26.5+ first, followed by a read-only iPadOS client. Android remains a later read-only option. The current development machine is Apple silicon with macOS 26.5.2 and Xcode 26.6.
- **Media ownership:** audio remains in the user's existing folders or NAS; the app stores references and metadata, not a second hidden copy.
- **Offline behaviour:** browsing and playback work without internet. Online services enhance metadata but are not required to use the library.
- **Editing safety:** scans and online matches update the app's database first. Writing tags back into audio files is a separate, explicit action with preview and backup.
- **Canonical metadata source:** MusicBrainz first, Cover Art Archive for artwork, embedded tags as the initial fallback, and AcoustID/Chromaprint for difficult audio identification.
- **Sync and ownership:** the Mac is the only catalogue writer and holds the authoritative SQLite database. iPad and Android are read-only clients that download versioned, consistent snapshots from the NAS. They never upload catalogue edits.
- **Read-only audio access:** companion clients use SMB to access NAS audio through device-local, user-selected root mappings.
- **Publication:** publishing is available manually and automatically after a debounced catalogue change and on orderly app quit. Clients check the published manifest's modification date at launch, then compare its revision before downloading.
- **AI:** keep provider access behind protocols so MiniMax can be replaced. Never put API keys in source code; store them in Keychain or use a small server-side proxy.

### Confirmed database ownership model

The Mac is the sole writer. This removes multi-device edit conflicts and avoids the need for PostgreSQL or a complex bidirectional synchronization service.

Do **not** put the Mac's live SQLite database on a NAS or allow clients to open it over SMB. Network interruptions can corrupt a live database, and copying only the main file can omit active SQLite WAL data. Instead:

1. The Mac keeps the live database locally.
2. After an explicit publish, a debounced successful write batch, or orderly app quit, the Mac uses SQLite's backup mechanism to create a consistent snapshot.
3. The Mac packages the snapshot with a manifest containing schema version, catalogue revision, creation date, database size, and SHA-256 checksum.
4. It writes the package to a temporary NAS filename, verifies it, and atomically renames it as the current published snapshot.
5. Read-only clients check the small manifest's modification date when launched and periodically while active. If it is newer than the last observed manifest, they fetch it and compare revision/schema/checksum metadata.
6. When the revision is newer, a client downloads to a temporary local file, verifies size/checksum and schema compatibility, then atomically replaces its local read-only copy.
7. If the NAS is unavailable or a download fails, the client continues using its last verified local snapshot.

Each client therefore reads its own local SQLite copy. The NAS distributes snapshots; it does not serve a live shared database.

## 3. Correct domain model

Use one album profile for each edition or pressing the user wants to catalogue. For example, the Japanese pressing, the 1980 release, and a remaster are separate album profiles even if they share the same musical title.

The core concepts are:

- **Album:** one specific edition/profile, containing title, user-editable edition label, release year, country/region, label, catalogue number, barcode, remaster year, notes, `hasCD`, and a structured physical-location reference.
- **Disc/medium:** disc 1, disc 2, SACD layer, and so on.
- **Recording/track:** the recorded performance and its position on a release.
- **Contributor:** artist, album artist, composer, conductor, orchestra, soloist, remixer, etc.
- **Digital asset:** a specific audio file, with format, codec, sample rate, bit depth, channels, duration, file size, and availability.
- **Box set:** a named physical container with its own artwork, edition information, physical location, and notes.
- **Box-set membership:** an ordered link between a box set and its album profiles.
- **Physical location:** a reusable hierarchy such as `Living Room > Cabinet A > Shelf 2`, with an optional free-text note.
- **Storage root:** a user-selected folder or NAS share and its persistent access bookmark.
- **Playlist and playlist item:** an ordered list referring to recordings or digital assets.
- **Import batch and candidate:** persistent scan results with states such as `unreviewed`, `matched`, `needsReview`, `confirmed`, `skipped`, and `failed`.
- **External identifier:** MusicBrainz IDs, barcode, ISRC, AcoustID, Discogs ID if later supported, and provider provenance.
- **Artwork and lyrics:** separate records with source, language, rights/provenance, confidence, and user-selected status.
- **Generated work:** prompt, provider/model, generation parameters, date, rights notes, and one or more produced digital assets.

### Edition labels

`editionLabel` is a short, user-editable display qualifier, for example:

- `Japan version`
- `1980 pressing`
- `2011 remaster`
- `Hong Kong edition`
- `SACD`

Structured fields such as release year, country, label, catalogue number, and remaster year remain separate so they can be searched and sorted. The free-text edition label is what distinguishes similar albums in lists, for example `Kind of Blue — Japan 1980 pressing`. The user may leave it blank for an ordinary edition.

### Box sets

A box set groups several album profiles without merging their track lists. It owns the physical location for all member albums. A member album displays `In: [Box Set Name]` and inherits that box's location; it does not have an independent physical location while it belongs to the box. Albums are ordered inside the box using a sequence number.

Removing an album from a box does not delete it. The app asks for its new standalone physical location. Deleting a box is blocked until the user chooses whether to keep its member albums as standalone records.

This model supports physical-only, digital-only, and both in one album profile, distinct profiles for different editions, and multiple digital rips. A separate physical-copy table is deliberately omitted because the current requirement allows one physical instance per album profile.

### Multi-disc albums versus box sets

- A multi-disc edition of one album is one album profile containing several discs.
- A box containing independently named albums is one box-set profile containing several album profiles.
- An anthology with one continuous title may remain one multi-disc album instead of being divided artificially.
- The confirmation screen lets the user correct an automatic classification before saving.

### Classical music fields

Classical music cannot be represented reliably by only artist, album, and song title. Include work, movement number/name, composer, conductor, ensemble, soloists, opus/catalogue number, and recording date/location. Contributors need roles and must be many-to-many.

## 4. Proposed technical architecture

### Client

- SwiftUI app with macOS as the first target.
- Shared Swift packages for `Domain`, `Persistence`, `Metadata`, `FileScanning`, `Playback`, and `Networking`; UI code stays platform-specific where needed.
- Local SQLite persistence behind repository protocols. GRDB is a good implementation candidate because it exposes SQLite clearly and supports migrations; the domain layer should not depend directly on it.
- Structured concurrency for scans and metadata calls. Scanning must be cancellable, resumable, and bounded so a large library does not freeze the UI.
- App Sandbox access using security-scoped bookmarks for user-selected roots.
- Keychain for API credentials.

### Audio pipeline

- AVAudioEngine + AVAudioPlayerNode for local files, queueing, seeking, gapless preparation, and output-device handling.
- Preserve the source format where the selected hardware permits it. Display source format and actual output format so “lossless” and “bit-perfect” are not confused.
- Reconfigure carefully when tracks have different sample rates; add an optional exclusive/hog-mode experiment only after normal playback is stable.
- Support FLAC, ALAC, WAV, AIFF, AAC, and MP3 according to what the platform decoder accepts; validate actual formats with fixtures rather than assuming by extension.
- Persist the queue and playback position. Initial controls: play/pause, seek, previous, next, repeat off/all/one, shuffle, volume, and output device status.

“Highest quality” should mean no unnecessary transcoding or DSP, correct sample-rate handling, and a transparent signal path. It cannot guarantee bit-perfect output for every DAC and system configuration.

### Metadata pipeline

1. Read filenames, folders, embedded tags, duration, audio properties, and embedded artwork.
2. Group files using disc/album IDs and tags—not folder name alone. Split a folder when album identity differs.
3. Generate candidate releases and confidence scores.
4. Search MusicBrainz and artwork services with caching and rate limiting.
5. Use audio fingerprints for ambiguous or poorly tagged files.
6. Show a side-by-side review: current value, proposed value, source, and confidence.
7. Save confirmed corrections to the database overlay.
8. Offer “write tags to files” later as an explicit batch operation with dry run, conflict report, backup, and rollback log.

Never silently rewrite original music files after an online match.

### File identity and relocation

Store more than an absolute path:

- storage-root ID plus relative path;
- volume identity and file resource identifier where available;
- file size, modification time, duration, and audio properties;
- a fast fingerprint or content hash for recovery/deduplication;
- security-scoped bookmark for selected roots.

When a file is unavailable, check whether the root is offline before declaring it missing. Relinking a moved root should repair all descendant paths at once. For individual moved files, search within selected roots by fingerprint/signature and ask the user before changing the link.

### Future read-only distribution service

When the Mac version is stable, add:

- a snapshot publisher in the Mac app using SQLite's online-backup mechanism;
- a versioned manifest and checksum validation;
- SMB-based snapshot download on the trusted local network;
- a local snapshot cache on every client, with atomic replacement and rollback to the last valid version;
- client schema-version checks so an older app never opens an incompatible snapshot;
- artwork thumbnails alongside the snapshot; original audio stays on the NAS unless remote streaming is intentionally built.

Because clients are read-only, there is no outbox, record merge, conflict resolution, or client-to-server database upload.

### Core interaction workflows

#### Unified Add Album

One **Add Album** command offers several starting methods:

1. Scan a barcode.
2. Take or import a cover photograph.
3. Search by artist and title.
4. Scan a digital folder.
5. Enter information manually.

Every method leads to the same confirmation screen: choose the matching edition, compare metadata, edit the edition label, enable CD and select a location or box set, attach digital files, then confirm.

When a digital scan resembles an existing album, the app explicitly offers **Attach to Existing Album** or **Create Another Edition**. It never merges editions silently.

#### Resumable Import Inbox

All scanned candidates are persisted before review. Inbox states are `needsConfirmation`, `possibleMatch`, `missingInformation`, `confirmed`, `ignored`, and `failed`. The user can confirm albums individually or in batches, close the app, and continue later without repeating the scan.

#### Metadata comparison

Before accepting an online result, show existing and suggested values side by side with source and confidence. The user may accept the complete proposal or selected fields only. Rejected values remain unchanged, and no source audio file is rewritten during this step.

#### Box-set entry

Create or find the box, assign its physical location once, add or scan its member albums, arrange them in box order, and confirm members individually or in batches. Members inherit the box location.

#### Search and aliases

Store alternate, translated, original-language, and romanized titles as searchable aliases. Search covers album title, edition label, alias, track, contributor, barcode, catalogue number, box-set name, and physical location.

### Maintenance, safety, and portability

- **Library Health:** show missing files, offline roots, partial digital albums, duplicate assets, missing artwork, suspicious track counts, candidates awaiting review, failed imports, and unpublished Mac changes.
- **Publish status:** show the current catalogue revision, last successful NAS publication time, and number of unpublished changes.
- **Snapshot recovery:** retain several older verified snapshots on the NAS so a bad publication or incompatible client can be rolled back.
- **Recently Deleted:** soft-delete albums and box sets for a retention period before permanent removal.
- **Edit history:** record important metadata changes with time, old value, new value, and source; support undo where safe.
- **Artwork roles:** support front, back, booklet, tray, disc, and other images with source/provenance.
- **Personal organisation:** support album notes, personal tags, favourites, and ratings. Play statistics are optional and can be deferred.
- **Open export:** provide documented CSV and JSON exports in addition to the restorable database backup.
- **Offline playlists:** playlist membership remains valid when its files or storage root are temporarily offline.
- **Digital origin:** record whether an asset is a CD rip, download, high-resolution release, other local file, or AI-generated output.
- **Duplicate detection:** use content hashes or audio fingerprints in addition to paths and filenames.

iPad cannot use an arbitrary Mac/NAS path as though it were local. It selects its SMB music root through the system UI and maintains a device-local mapping to the published storage-root ID. Catalogue snapshot download remains independent of whether the SMB music root is available.

## 5. Delivery roadmap

The estimates below assume one developer using Codex, working part-time to steady full-time, and include tests and polish. They are planning ranges, not promises.

### Phase 0 — Product spike (3–5 days)

- Confirm 15–30 real sample albums: FLAC, ALAC, WAV/AIFF, multi-disc, compilation, classical, Chinese/Japanese metadata, bad tags, mixed folder, and NAS files.
- The first read-only companion is iPad; Android remains deferred.
- CD ripping is explicitly out of scope. The app imports existing digital files only; reliable ripping, AccurateRip verification, drive offsets, and error correction are not planned.
- Build small spikes for metadata reading, bookmark persistence, MusicBrainz lookup, and FLAC playback.
- Write the schema and migration strategy before building screens.

Exit: technical risks demonstrated on the actual library, not only test MP3s.

### Phase 1 — Catalogue MVP (2–3 weeks)

- App shell and navigation: Albums, Artists/Contributors, Box Sets, Import Inbox, Playlists, Settings.
- Database migrations and repository layer.
- Manual album entry with CD availability, physical location, edition label, structured edition fields, artwork, notes, and multiple discs.
- Box-set creation, ordered album membership, and inherited box location.
- Unified album profile with derived `CD` and `Digital` availability indicators and separate detail sections.
- Unified Add Album entry points and side-by-side metadata confirmation.
- Search by album, track, contributor, catalogue number, barcode, and physical location.
- Search aliases for translated, original-language, and romanized titles.
- MusicBrainz search and a selection/import screen with provenance.
- Recently Deleted, edit history for important changes, and backup/export to documented archive, JSON, and CSV formats.

Exit: the physical collection can be catalogued, found, backed up, and restored.

### Phase 2 — Digital import and review (3–5 weeks)

- Select one or multiple roots and retain access.
- Recursive, cancellable scan with progress, errors, and persistent import batches.
- Parse embedded metadata and audio technical properties.
- Correctly split mixed and multi-disc folders.
- Duplicate detection and unavailable-file state.
- Candidate review that can be stopped and resumed over multiple sessions.
- Import Inbox states, batch confirmation, and attach-to-existing versus create-edition decisions.
- MusicBrainz/AcoustID matching, cover selection, and database-only corrections.
- Root and file relinking workflows.
- Digital availability calculation for complete, partial, offline, and broken albums.
- Library Health view and hash/fingerprint-assisted duplicate detection.

Exit: a large sample can be scanned twice without duplicate records; closing the app mid-review loses no work.

### Phase 3 — Lossless player and playlists (2–4 weeks)

- Playback engine, queue, transport controls, seek, shuffle, and repeat.
- Playlist create/rename/delete/reorder and persistence.
- Gapless transition tests, mixed sample-rate tests, output failure recovery, sleep/wake, and unplugged DAC behaviour.
- Now Playing mini-player and media-key/remote-command integration.
- Show codec, sample rate, bit depth, channels, and actual output format.

Exit: hours-long playback is stable and the queue survives relaunch.

### Phase 4 — Metadata writing and lyrics (2–3 weeks)

- Tag-write preview and a supported-format matrix.
- Backup, transactional batch log, failure recovery, and undo where technically possible.
- Lyrics provider adapter; store synced/plain lyrics, language, instrumental status, and source.
- Manual lyrics import/edit. Do not treat “no lyrics” as an error for classical or instrumental works.

Exit: a deliberately interrupted tag-write operation does not leave the library silently inconsistent.

### Phase 5 — Snapshot distribution and read-only clients (3–6+ weeks)

- Add consistent snapshot publishing and manifest generation to the Mac app.
- Display the catalogue revision, last publication, and unpublished-change count; retain several verified previous snapshots.
- Build launch-time revision checks, verified downloads, atomic local replacement, and offline fallback.
- Build the read-only iPad client first with shared domain/UI components. Android with Room/SQLite remains a later option.
- Hide all editing operations in companion clients and enforce read-only database access at the persistence layer.
- Add SMB root selection and device-local root mappings for iPad audio access; catalogue snapshot download remains independent of SMB audio availability.

Exit: a Mac-published change appears on a client after launch; an interrupted or corrupt download leaves the client's previous snapshot usable; clients cannot modify or upload catalogue data.

### Phase 6 — AI modules (2–5+ weeks each)

- **Cover recognition:** start with Apple's on-device Vision OCR and barcode recognition, then use extracted text/barcode to search the metadata provider. Add a hosted vision model only when local extraction is insufficient. Always present candidates for confirmation.
- **Music generation:** provider protocol, prompt/lyrics editor, job state, cancellation, cost disclosure, result download, provenance, and import into the same digital-asset model.
- Save generated output immediately: MiniMax URL responses can expire. Record provider, exact model, parameters, prompt, rights notes, and a checksum.

Exit: changing provider does not require changing catalogue or player code.

## 6. MVP acceptance tests

- Add a physical-only release and find it by artist, title, barcode, and shelf location.
- Create two editions of the same title and distinguish them by edition label and structured release information.
- Attach digital files later to the same edition's album profile rather than creating a duplicate profile.
- Import a matching folder and deliberately choose between attaching it to an existing profile and creating a separate edition.
- Scan nested folders containing at least 1,000 tracks while keeping the UI responsive.
- Correctly represent a compilation, multi-disc release, and classical box set whose member albums inherit the box location.
- Move a box to a new structured location and verify that every member displays the new inherited location.
- Pause review, quit, relaunch, and continue at the same candidate.
- Re-scan unchanged roots without duplicating assets.
- Disconnect a NAS root: show “storage offline,” not “deleted.” Reconnect and play without manual repair.
- Move a root and relink it once; all contained tracks resolve.
- Play FLAC/ALAC/WAV fixtures, use previous/next/seek/shuffle, and recover after output-device changes.
- Back up the catalogue, delete the test database, restore it, and verify record counts and relationships.
- Export useful catalogue data to both JSON and CSV and verify non-ASCII titles and aliases.
- Soft-delete and restore an album without losing its relationships.
- Reject an incorrect online match without altering the source files.
- Fail a metadata/API request gracefully and allow retry.
- Interrupt a snapshot download and verify that the read-only client retains its previous valid database.

## 7. Improvements to the original requirements

1. Keep CD availability and physical location directly on the album profile; derive digital availability from its track files.
2. Treat each pressing or edition as a distinct album profile and distinguish it with both a free-text edition label and searchable structured fields.
3. Add box-set grouping with ordered member albums and one inherited physical location.
4. Add barcode, label, catalogue number, country, release date, media format, disc count, condition, purchase information, and notes.
5. Add classical work/movement and contributor-role modelling now; retrofitting it later is painful.
6. Make every automated correction reviewable and record its source.
7. Do not write file metadata during import. Separate catalog corrections from file mutations.
8. Define duplicate rules and backup/restore before importing the real library.
9. Treat network sync and network audio access as different features.
10. Keep CD ripping out of scope; import files created by existing rippers when needed.
11. Treat AI-generated music as ordinary assets plus provenance, not as a second incompatible library.
12. Do not assume MiniMax is the best cover-recognition provider. OCR/barcode plus catalogue search will often be cheaper, faster, and more verifiable.
13. Define privacy: whether album photos/audio may leave the device, retention policy, and whether cloud AI may train on submitted content.
14. Define lyric provenance and provider terms. Generating or redistributing lyrics for existing copyrighted songs has legal and quality risks.

## 8. What not to build initially

- A custom CD ripping engine.
- Direct database access over the internet.
- Audio uploads/sync between every device.
- Automatic file renaming or tag replacement.
- AI recognition as the primary import method.
- AI music generation inside the same first milestone.
- Android UI before the data and sync model is proven.
- DSP, equalizer, loudness normalization, or “audiophile” modes before transparent basic playback is reliable.

## 9. Suggested project structure

```text
MusicLibrary/
  Apps/
    MusicLibraryMac/
    MusicLibraryPad/          # later
  Packages/
    MusicDomain/
    MusicPersistence/
    MusicMetadata/
    MusicFileScanning/
    MusicPlayback/
    MusicServices/
    MusicUIComponents/
  Tests/
    Fixtures/
    IntegrationTests/
  Documentation/
    schema.md
    metadata-sources.md
    supported-formats.md
    backup-and-restore.md
```

## 10. Immediate next step

Do Phase 0 before generating the full app. Assemble representative sample media (copies, not the only originals), prove metadata reading, bookmark persistence, MusicBrainz matching, FLAC playback, and iPad SMB-root selection with the real NAS. Then lock schema version 1 and build the Catalogue MVP.

## 11. Technical references

- Apple AVFoundation: https://developer.apple.com/documentation/avfoundation/
- Apple AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine
- Apple sandboxed file access: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- MusicBrainz API: https://musicbrainz.org/doc/MusicBrainz_API
- Cover Art Archive API: https://musicbrainz.org/doc/Cover_Art_Archive/API
- AcoustID web service: https://acoustid.org/webservice
- LRCLIB API: https://www.lrclib.net/docs
- MiniMax music generation: https://platform.minimax.io/docs/api-reference/music-generation
