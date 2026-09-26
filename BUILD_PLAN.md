# Music Library — Product and Build Plan

Original plan date: 22 July 2026

Last roadmap review: 27 September 2026

Detailed coding handoff: [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md)

Operational continuation guide: [HANDOFF.md](HANDOFF.md)

Implementation baseline (22 September 2026): the Mac catalogue, retained local/NAS authorization, safe scanner and review queue, explicit metadata comparison, digital assets, local playback and playlists, FLAC tag-write safety, manual lyrics, recovery/backup/export, snapshot publication, and the read-only companion foundation are implemented. The artwork-first Mac redesign is complete across Albums, the persistent player, Library Changes, playlists, and Settings. The current package is version 0.10 (build 11) and the rebuilt suite passes 102 automated tests in 9 suites. It includes a branded Dock icon, creates or attaches a reviewed release in one atomic action, keeps the UI responsive with a visible loading state while preparing slow NAS/DSF playback, provides a bounded user-configurable DSF PCM cache, one complete manual physical-album form with explicit MusicBrainz release prefill and optional managed cover import, preview-first catalogue cleanup, typed-confirm reset, and a checksummed complete catalogue archive containing SQLite plus managed artwork. Live NAS endurance and iPad device validation remain deliberately deferred. See [HANDOFF.md](HANDOFF.md) for the current Git baseline and next validation boundary.

Current baseline (27 September 2026): version 0.15 (build 16), with the first R0 redesign slice, the alternative-title empty-state correction, and the R1 shell/settings foundation implemented on top of the existing catalogue services. The slice adds shared native Mac visual primitives and isolated SwiftUI fixture previews, reworks Album Detail into a reading-oriented scroll layout, places recorded Other titles beside album identity with their add/remove actions, omits that section entirely when no variants exist while retaining Add Other Title in Album Actions, reduces track/disc/credit action clutter into contextual menus, moves artwork provenance/portability into an Artwork workspace instead of repeating it at the bottom of the page, and replaces the permanent three-column shell with a sidebar plus one main workspace and explicit Back actions. Settings now routes to functional General, Playback, Music Folders, iPad Sharing, Backup & Restore, and Advanced destinations. Debug/release tests both pass 102 tests in 9 suites; the packaged bundle passes plist and strict signature checks. Interactive visual verification is still pending because the development Mac was locked during delivery. The earlier visual workstream remains superseded by **section 12: Whole-app experience redesign**, which continues to control the remaining work. The existing architecture and data-safety invariants remain authoritative.

Real-library acceptance remains necessary for local/NAS playback endurance, slow DSF loading, offline/reconnect handling, and physical iPad behavior. Those checks cannot be proven by repository tests alone. They do not prevent isolated design and implementation work on section 12.

## Historical execution gate — audit hardening before visual redesign (12 August 2026)

The existing Mac catalogue and player received a release-oriented audit before the artwork-first UI pass. The audit found no evidence of a data breach or catalogue corruption, and its defensive and reliability actions are complete. The gate is closed and the visual implementation workstream is active.

The hardening workstream is executed as small, independently tested slices:

1. **Path and CUE safety:** enforce component-aware, symlink-resolved containment for registered roots, child-folder imports, replacement/relink paths, and CUE `FILE` references. Reject absolute/parent escapes and add traversal/symlink regression tests.
2. **Backup and snapshot safety:** validate manifest filenames and archive paths, preserve the last known-good manifest until the replacement is verified, and make local/NAS cache replacement pair-consistent and bounded.
3. **Audio-container validation:** make DSF/WAV arithmetic overflow-safe, reject malformed/truncated headers before allocation or playback, and add malformed-file tests for the supported catalogue/playback paths.
4. **Reliability and performance:** move full-file fingerprinting and other avoidable blocking work off the main actor, add bounded network/database waits, prevent startup failure from permanently disabling retry, and remove duplicate scheduled backup work.
5. **Exit verification:** run focused tests after each slice, then the complete debug/release Swift test and build checks, update `HANDOFF.md`, commit, and push. Only after this exit review may the visual foundation begin.

These changes preserve the fixed product invariants: the Mac remains the only catalogue writer, scans and lookups remain explicit and non-mutating, source audio is never rewritten by review actions, NAS publication remains snapshot-based, and the later UI redesign must not alter persistence semantics.

**Hardening progress (12 August 2026):** the registered-root/CUE containment, backup/snapshot safety, DSF/WAV validation, playback repeated-work cleanup, chunked background fingerprinting, startup retry, scheduled publication/backup isolation, bounded network request, grouped Library Health, and fail-closed security-scope slices are complete and independently tested. Final release/exit verification is complete, and the user has explicitly started the visual redesign workstream.

**Import-to-existing-edition workflow (23 August 2026):** a proposed release now offers two explicit outcomes without a preliminary approval step: create a new edition, or attach its digital files to a selected existing edition. Either successful choice records approval and the catalogue result atomically. Before attachment, the Mac shows every imported-file-to-catalogue-track pairing. A populated edition must have an exact disc set and per-disc track count; an empty edition may receive the imported disc/track structure. Catalogue album/track titles, credits, artwork, and edition metadata are preserved, reused root-relative paths are rejected, and compatibility is revalidated inside the same transaction. This closes the duplicate-album workflow gap without guessing identity or changing source files.

**Audit hardening — bounded metadata and artwork requests (12 August 2026):** explicit MusicBrainz searches, release-detail requests, and cover-art downloads now share a 30-second `URLRequest` timeout. The request policy is applied both in the metadata provider and in Mac artwork actions, so a disconnected NAS/VPN or captive network cannot leave a user-triggered lookup waiting indefinitely. Audio files are still never uploaded by these actions, and no catalogue or source-file semantics changed. Regression coverage verifies the shared timeout policy; the full Swift suite passes 83 tests.
**Audit hardening — grouped Library Health root access (12 August 2026):** the available-asset health pass now groups candidates by registered storage-root ID, resolves each bookmark once, and holds that root's security-scoped access for the whole group. It still checks every stored relative path and writes the same availability result, but avoids reopening the same NAS/local root once per track. The full Swift suite passes 83 tests; no catalogue or source-file semantics changed.
**Audit hardening — fail-closed security-scoped operations (12 August 2026):** user-selected artwork, legacy artwork migration, snapshot publication, master-backup creation/restoration, and registered-folder bookmark creation now stop before filesystem or database work when macOS denies the security-scoped resource. Previously these paths could continue after a denied scope and report a later, less actionable filesystem error. The full Swift suite passes 83 tests; no catalogue, source audio, or backup data was changed by the test run.

**Audit exit preparation — generated-project synchronization (12 August 2026):** regenerating with the repository's `project.yml` restored the existing `CompanionPreferences.swift` source reference in `MusicLibraryPad.xcodeproj`. `xcodebuild -project MusicLibraryPad.xcodeproj -list` now reports the expected three targets and three schemes. This is project bookkeeping only; no SwiftUI redesign or product behavior changed.

**Audit exit verification (12 August 2026):** the complete debug and release Swift suites pass (83 tests in 8 suites), the release Swift package build passes, `xcodegen generate` is clean, `xcodebuild -project MusicLibraryPad.xcodeproj -list` reports the expected targets and schemes, a real Release iOS Simulator Xcode build succeeds, the Mac app packaging script succeeds, and `git diff --check` is clean. The final local error-path review found no new correctness issue: remaining best-effort `try?` uses are limited to cleanup, optional metadata/artwork fallbacks, or local UI-state persistence; the constant MusicBrainz URL construction does not depend on user input. The known AVFoundation `stringValue` deprecation is non-blocking and deferred as maintenance. No catalogue, source-media, or user Application Support data was changed, and no visual redesign work started.

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

On Mac, the Albums toolbar's **Add Physical Album** command opens one complete manual entry form. It records edition metadata, multiple contributor credits with roles, CD availability, a required structured location/box-set/explicit-unknown choice, physical and catalogue notes, rating, and favourite state without creating digital assets. Exact existing contributor names are reused case-insensitively, and the album, any new contributors, their role links, and an explicitly selected MusicBrainz front cover are committed atomically. The resulting catalogue record is intentionally not playable until digital audio is attached later. Local artwork and manual disc/track details remain available from Album Detail after creation.

When a digital scan resembles an existing album, the app explicitly offers **Attach to Existing Album** or **Create Another Edition**. It never merges editions silently.

#### Resumable Import Inbox

All scanned candidates are persisted before review. Inbox states are `needsConfirmation`, `possibleMatch`, `missingInformation`, `confirmed`, `ignored`, and `failed`. The user can confirm albums individually or in batches, close the app, and continue later without repeating the scan.

#### Metadata comparison

Before accepting an online result, show existing and suggested values side by side with source and confidence. The user may accept the complete proposal or selected fields only. Rejected values remain unchanged, and no source audio file is rewritten during this step.

#### Box-set entry

Create or find the box, assign its physical location once, add or scan its member albums, arrange them in box order, and confirm members individually or in batches. Members inherit the box location.

#### Search and aliases

Store alternate, translated, original-language, and romanized titles as searchable aliases. Search covers album title, edition label, alias, track, contributor, barcode, catalogue number, box-set name, and physical location.

### Mac visual design direction (reviewed 12 August 2026)

Historical first-pass direction. For new UI work, section 12 takes precedence, including where it changes navigation, editing, entry, and review workflows. Do not reproduce the old screens simply because their implementation checkpoints say complete.

The catalogue and player workflow is now solid enough to receive a deliberate visual pass. The next Mac UI direction is **artwork-first, icon-led, and progressively disclosed**: show the information needed for the current decision, keep advanced/raw details available behind an obvious control, and replace repeated explanatory paragraphs with artwork, badges, concise labels, and familiar controls. This is a presentation workstream; it does not change database ownership, scan semantics, explicit metadata approval, tag-write safety, or NAS publication rules.

The direction is based on the platform patterns we reviewed: macOS expects resizable windows and customizable toolbars; Apple recommends sidebars for primary navigation, image-based collections for visual content, disclosure controls for advanced information, and familiar symbols with labels/tooltips for actions. Music's MiniPlayer demonstrates a persistent compact player with artwork, progress, lyrics, and queue access. Roon and MusicBrainz Picard provide useful reference patterns for artwork-rich album browsing, direct track play, candidate identification, and side-by-side metadata/cover comparison. References: [Apple Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [Apple Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Apple Collections](https://developer.apple.com/design/human-interface-guidelines/collections), [Apple Disclosure Controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls), [Apple Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Apple Music MiniPlayer](https://support.apple.com/guide/music/use-music-miniplayer-mus71d7dcfce/mac), [Roon albums](https://help.roonlabs.com/portal/en/kb/articles/albums), and [Picard's main screen](https://picard-docs.musicbrainz.org/en/latest/getting_started/screen_main.html).

#### Information architecture

- **Library:** Albums, Contributors, and Box Sets remain the primary browsing destinations.
- **Review:** Library Changes is a review queue for new, missing, duplicate, and failed scan work. It shows the latest result per registered root; it is not a permanent list of every historical path scan. Root registration, source scope, rescan, and access permissions belong in Settings.
- **Play:** Playlists remains a focused destination for saved ordered collections.
- **Settings:** group Music Folders, snapshot/master-backup controls, Library Health, export, activity history, and advanced diagnostics into clearly separated sections. Keep destructive/recovery actions visually distinct.

#### Albums home

- Default to an artwork grid for visual recognition, with a list toggle for dense catalogue work and accessibility.
- Keep a prominent search field and a compact source filter: **All Music**, **This Mac Only**, and **NAS / iPad Music**. The selected filter must be visible and survive navigation; an album with both kinds of assets appears in both scoped views.
- Each card/list row shows artwork, album title, artist, edition label/year, CD and Digital badges, source badge(s), and a small health indicator when a file/artwork/review issue exists. Do not make the user open the detail view to understand why an album is unavailable.
- Keep sorting and secondary filters in a toolbar/menu rather than consuming permanent screen space. Empty states should show one useful illustration/icon, the reason, and one next action.

#### Album detail

- Lead with a compact artwork header containing title, edition label, artist, release/edition badges, CD/Digital availability, physical location, and the primary Play action.
- Use tabs or a segmented control for **Overview**, **Tracks**, **Files**, **Credits**, and **Notes & History**. Tracks is the default when the user entered from an album card; Overview is the default for a newly created record.
- Keep the normal track list clean: title, number, duration, play, add-to-playlist, lyrics, and a compact health/format indicator. Put raw embedded tags, technical audio fields, provenance, file identity, and repair controls in Files or an expandable Details section.
- Artwork roles (front/back/booklet/disc) stay accessible from the artwork header, with a clear selected-front state and an explicit managed/legacy status.

#### Library Changes and MusicBrainz review

- Render each release proposal as a compact horizontal card: artwork at the leading edge; title, artist, source/provenance, confidence, disc/file summary, and creation status in the middle; the state-appropriate actions at the trailing edge. Keep **Search MusicBrainz…**, **Create New Edition** or **Attach to Existing Edition…**, and **Dismiss** visually ordered by importance. Creation and attachment are the approval decisions; do not require a redundant **Approve for Later** click.
- Keep raw tag dumps and long paths collapsed under **Technical details**. The card must still expose enough title/artist/file information to distinguish candidates without opening a modal.
- Make MusicBrainz Lookup a genuinely resizable review workspace. Keep candidate releases in a left pane and the selected candidate in a right pane. The right pane shows imported artwork beside MusicBrainz artwork, a concise field comparison, and a two-column track comparison with counts and clear mismatch highlighting. Download-cover-art remains a separate, explicit JPEG action.
- Preserve the existing safety language: lookup is user-triggered, audio is never uploaded by default, the preview changes nothing, and only the selected fields/release are applied after explicit confirmation.

#### Player

- Keep a persistent MiniPlayer, led by artwork and title/artist/source rather than a wall of text. It contains play/pause, previous/next, progress, volume, queue, shuffle, repeat, lyrics, and stop using familiar symbols with labels or tooltips where the symbol is not self-evident.
- Selected shuffle/repeat states must be visually unambiguous (tint/background plus accessible label), and the current source (This Mac/NAS) must be visible before playback starts.
- The expanded Now Playing view may reveal codec, sample rate, bit depth, channels, output format, queue, lyrics, and file path. Keep those details out of the compact bar unless the user asks for them.

#### Visual system and guardrails

- Use SF Symbols or another native symbol set consistently; pair an icon with a short label for destructive, ambiguous, or high-impact actions and provide macOS tooltips/accessibility labels for icon-only controls.
- Prefer one clear primary action per surface, restrained secondary actions, consistent status colors, and shared artwork placeholders/loading/error states. Keep loading states local to the artwork or candidate that is loading.
- Do not hide safety-critical state behind color alone. Offline, missing, pending, proposed, approved, and destructive states need text or accessible labels in addition to tint.
- Do not redesign by adding automatic network lookup, automatic metadata mutation, source-file writes, or client-side catalogue edits. Visual changes must leave the existing persistence and review invariants intact.

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

### Visual implementation workstream (Mac-first, after the current logic baseline)

This workstream runs across the existing phases; it is not a new persistence or synchronization phase. Each slice must be implemented without changing the catalogue contract, then checked on a real Mac window at narrow and wide sizes.

**Implementation checkpoint (13 August 2026):** the planned Mac presentation slices are implemented. The sidebar is grouped by Library, Organize, Review, and Settings; Albums has artwork grid/list presentations, persistent source/favourite/sort controls, batched selected-front-artwork lookup, and an artwork-led detail hero with Play and Shuffle actions. The persistent player shows title/source-format context, elapsed and total time, seek progress, transport, visible shuffle/repeat state, volume, and stop. Artwork decoding is performed away from the main actor. Library Changes has icon/status root rows, a compact scan metric dashboard, one prominent combined Rescan and Review action, artwork-led proposal cards, and collapsed raw candidate tags. Playlists have an artwork-style header, track count, Play Playlist action, and direct-play/reorder/remove rows. Settings uses the wide detail workspace for Catalogue, Music Folders, and Library Health status cards plus icon-led sections. Section-specific empty states and compact Library Changes rows remain legible at the packaged app's minimum practical window size. Browsing these surfaces does not change the catalogue. Automated accessibility labels remain in place; real-window visual checks cover Albums, Library Changes, Playlists, and Settings.

**Implementation checkpoint (23 August 2026):** the packaged Mac app has a repository-owned 1024-pixel application icon and generated `.icns`, bundle version 0.2 (build 2), and packaging support that embeds the icon in `Contents/Resources`. Library Changes removes the redundant approve-then-create sequence: direct creation and attachment accept proposed or legacy-approved rows and commit approval plus the selected catalogue result atomically. Playback file opening, DSF conversion, player construction, and preparation run on a serial user-initiated loader; the MiniPlayer reports the selected title while loading and a generation guard prevents an older slow NAS request from starting after a newer selection. The full Swift suite passes 87 tests in 8 suites.

**Implementation checkpoint (23 August 2026, DSF cache controls):** Settings now presents DSF playback-cache usage and file count, a 2–100 GiB maximum-size control with a 10 GiB default, and a confirmed Clear DSF Cache action. Completed conversions are retained for faster replay and trimmed least-recently-used when the budget is exceeded; lowering the limit trims immediately. Current playback, in-progress conversions, and every source DSF are protected. Playback is briefly held while a destructive cache-maintenance operation is active. The sequentially packaged Mac build for this checkpoint is 0.4 (build 5).

The cache slice adds isolated LRU, clear/protection, conversion, and preference-range coverage; the full rebuilt baseline passes 90 tests in 8 suites.

**Implementation checkpoint (30 August 2026, catalogue maintenance):** Settings adds preview-first safe cleanup, portable complete archive export/restore, and a separate typed-confirm catalogue reset. Cleanup is limited to superseded terminal scan history, genuinely uncredited contributors, and unused physical-location nodes, and it creates a complete local recovery archive first. The archive combines a consistent SQLite backup and all app-managed artwork with byte counts and SHA-256 checksums; restore verifies/stages the whole package, remaps exact recorded artwork paths, and retains rollback data until reopen succeeds. Reset preserves registered music roots and never touches source media. Debug and release suites pass 101 tests in 9 suites; the signed sequential delivery is version 0.8 (build 9), installed at `/Applications/Music Library.app`, and its executable matches the packaged build byte-for-byte.

1. **Visual foundation:** make the three-column shell, sidebar, toolbars, cards, empty states, status badges, artwork placeholders, loading/error states, and window sizing/resizing behavior consistent. Add the All/This Mac/NAS source filter to the Albums home and make the active scope obvious.
2. **Artwork-led library:** add the Albums grid/list toggle, compact artwork cards, concise edition/source/health badges, sorting controls, and the artwork-first album detail header. Move raw tags and technical metadata behind Files/Details disclosure without removing the existing verification actions.
3. **Review workspace:** reshape Library Changes proposal rows into artwork/title/provenance/action cards and make MusicBrainz Lookup a resizable candidate-and-comparison workspace with imported/remote artwork, field comparison, track comparison, and explicit cover download. Keep scan/review actions and approval semantics unchanged.
4. **Playback presentation:** refine the persistent MiniPlayer and expanded Now Playing view around artwork, title/artist/source, familiar transport icons, visible selected shuffle/repeat states, queue, lyrics, and progressive technical details.
5. **Polish and accessibility:** add tooltips, accessibility labels, keyboard focus/order, text equivalents for status colors, consistent destructive-action treatment, and snapshot/visual regression checks for the major Mac surfaces.

#### Visual workstream exit criteria

- A user can identify an album from artwork and concise badges without opening it, then switch between All Music, This Mac Only, and NAS / iPad Music without losing context.
- A user can resize the MusicBrainz workspace, select candidates from the left pane, compare imported and remote artwork/tracks on the right, and understand which action is safe before accepting it.
- A user can tell at a glance whether playback is local or NAS, whether shuffle/repeat is selected, and what is currently playing; the expanded view still exposes the full technical metadata and lyrics.
- Narrow/wide window checks show no clipped fields, horizontal text walls, or artwork stuck on a previous candidate. Loading/error/empty states are local and understandable.
- UI-only tests and `swift test` pass; no catalogue revision or source-file checksum changes occur from merely browsing, filtering, resizing, or opening a preview.

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

**Phase 4 v1 implementation decision (Mac-first, July 2026):** FLAC Vorbis-comment write-back is supported. WAV+CUE, DSF, AIFF, ALAC, MP3, and every other container remain catalogue-only until each has a separately tested write-back implementation. Every FLAC write is previewed, backed up before mutation, written through a temporary file, re-read for verification, and recorded in a retained JSON batch journal that can restore the untouched originals. Lyrics are stored as manually entered plain or LRC text with language and source. A provider adapter remains deliberately inactive until a lyrics provider and its terms are chosen.

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

### Visual acceptance additions

- Open Albums at a narrow and wide window size; switch grid/list and All/This Mac/NAS filters; verify artwork, edition labels, CD/Digital/source badges, health indicators, search, and empty states remain legible.
- Open an album and confirm the artwork-led header, primary Play action, concise Tracks view, and Overview/Files/Credits/Notes & History disclosure keep raw tags and technical fields available without overwhelming the default view.
- Open Library Changes and confirm each proposal presents artwork, title, artist, provenance/confidence, file/disc summary, and the state-appropriate actions in one row/card; verify long paths and raw tags are collapsed.
- Open MusicBrainz Lookup, resize the window, select at least three candidates, and verify the imported and MusicBrainz artwork/track lists refresh for each selection. Confirm cover download remains explicit and preview-only until the user accepts it.
- Start playback from a local album and a NAS album; verify the MiniPlayer source badge, artwork, transport controls, progress, queue, lyrics, and visually distinct shuffle/repeat states. Expand Now Playing to inspect technical fields.
- Toggle appearance/contrast or use VoiceOver/accessibility inspection and verify icon controls expose labels, status colors have text equivalents, and destructive actions remain clearly identified.

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

Start section 12, milestone R0, using the existing app and safe fixtures. Establish connected, native screen compositions for the library, album detail, and physical entry, then implement milestones in dependency order. Do not restart Phase 0, recreate the database, or rebuild completed playback/scanning infrastructure. The canonical operational continuation remains HANDOFF.md.

## 11. Technical references

- Apple AVFoundation: https://developer.apple.com/documentation/avfoundation/
- Apple AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine
- Apple sandboxed file access: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- MusicBrainz API: https://musicbrainz.org/doc/MusicBrainz_API
- Cover Art Archive API: https://musicbrainz.org/doc/Cover_Art_Archive/API
- AcoustID web service: https://acoustid.org/webservice
- LRCLIB API: https://www.lrclib.net/docs
- MiniMax music generation: https://platform.minimax.io/docs/api-reference/music-generation

## 12. Whole-app experience redesign — implementation specification

Specification date: 26 September 2026. Status: active implementation; milestones remain.

### 12.0 Implementation status — 27 September 2026

The R0/R1 foundation is implemented in the Mac target. `LibraryDesignSystem.swift` contains reusable panels, section headers, metadata grids, status pills, the connected album identity header, and the single identity-area Other titles editor. `LibraryDesignPreviews.swift` provides isolated populated, sparse physical-only, browse, and physical-entry fixtures at compact and regular widths; it never starts `LibraryStore` or reads the live catalogue. Album Detail uses a native `ScrollView` reading layout with identity, artwork, primary artist, recorded Other titles, catalogue metadata, credits, tracks, collection notes, and contextual action menus. Albums without variants have no empty Other titles section, with Add Other Title retained in Album Actions. The Mac shell now uses a sidebar plus one workspace with explicit Back actions, and Settings routes to functional category destinations while retaining the existing guarded service actions. The follow-up correction also removed the duplicate Other titles panel below Tracks. The next unfinished work is R2: an explicit reading/edit boundary for album identity and tracks, a focused artwork viewer workflow, and further reduction of edit clutter, followed by R3 batched artist and availability summaries.

### 12.1 Purpose, authority, and scope

The user rejected the overall appearance and invited changes to the workflows, not just rearrangement of fields. The goal is a coherent music collection application where identifying, finding, listening to, adding, and organizing albums feel natural.

This section is the controlling redesign specification for the next implementation agent, including Luna. It supersedes earlier UI layout recommendations in this file. It does not supersede IMPLEMENTATION_SPEC.md's safety invariants. Where a planned workflow changes an existing product rule, update the affected technical specification in the same implementation slice.

The current request is to prepare this plan. No app implementation is authorized by this documentation update alone. When the user subsequently requests a build, use the milestone sequence here; do not ask again about routine choices already specified. Do not create or message another chat merely because Luna is mentioned.

Scope levels:

| Level | Included |
|---|---|
| Required Mac redesign | Navigation, library browsing, album identity and other titles, track rows, explicit edit mode, physical entry, import review, player, contributors, locations, box sets, playlists, settings, error/empty/loading states, accessibility |
| Functional enhancements within planned Mac milestones | Artist summaries, accurate availability, release URL/barcode/catalogue lookup, optional MusicBrainz catalogue tracks, duplicate suggestions, playlist track picker, queue view, artwork viewer |
| Later companion milestone | iPad browsing and setup redesign, subject to available snapshot data and a separate implementation/delivery boundary |
| Deferred | Camera barcode scanning, OCR, AcoustID integration, AI, new metadata/lyrics providers, non-FLAC tag writing, automatic merging/relinking, new playback engine/DSP, internet audio sync |

Do not interpret a new button in a design as evidence that its underlying service already exists.

### 12.2 Evidence and problems to solve

Review basis: user screenshots plus the source at the version 0.11 baseline. There was no fresh live walkthrough of every screen. Treat actual visual inspection as required evidence during implementation.

1. Album detail is still composed as a grouped form. It displays administrative controls while the user is trying to read or listen.
2. Other titles are called Aliases and appear below tracks, detached from the primary title.
3. The latest hero duplicates cover selection as both an overlay button and a text button, and uses caption-sized single-line fields that can truncate names, catalogue numbers, and locations.
4. Track rows expose about seven actions each. Destructive and infrequent controls compete with playback.
5. The permanent three-column shell constrains both cover browsing and album reading.
6. Album cards/list rows omit the artist; the player uses a generic symbol and technical audio text rather than cover/artist identity.
7. The Settings category list has no selection routing and sits beside a single long page.
8. Physical entry starts with many empty fields; lookup is a nested sheet. Blank contributor rows block submission.
9. MusicBrainz physical-release tracks are preview-only; the current provider flattens tracks into title strings, losing medium boundaries needed for reliable import.
10. Import uses internal concepts such as batches and release proposals prominently. Folder registration, scanning, metadata review, and attachment are distributed across screens.
11. Playlists and box sets expose repeated movement/remove buttons. Empty playlists have no direct track picker.
12. The iPad starts with snapshot configuration, local statistics, and raw root identifiers mixed into browsing.
13. The existing album detail enables playback from catalogue track presence, which is not proof of playable digital assets. The tag-write menu similarly checks discs rather than supported assets.

### 12.3 Experience principles

- Browse first: normal pages display music and collection information. Editing opens a deliberate editor or Organize mode.
- Put related information together: title variants with the title, credits with identity, location with ownership, source paths with Files, restoration with backups.
- Each workspace has one clear primary action and a small set of contextual secondary actions.
- Frequent actions remain visible and labelled. Overflow menus hold secondary actions, not the only way to perform an everyday task.
- Use progressive disclosure for advanced detail, not for basic album identity.
- Browsing remains useful without internet or a connected music root. Availability explains what can be played.
- Save returns the user to the created/edited object. Back returns to the same filters, selection, and scroll position.
- Optional data is genuinely optional. Empty fields do not leave visible holes on reading pages.
- External matching suggests an edition; it never silently equates editions or overwrites corrections.
- Preserve existing safety mechanisms while reducing repeated technical explanation on everyday screens.

### 12.4 Navigation and workspace architecture

Default Mac shell: a sidebar and one main workspace. The player occupies a persistent bottom region when active. A selected album opens inside the main workspace with a visible Back action.

Sidebar:

| Group | Destinations | Behavior |
|---|---|---|
| Library | Albums, Artists & Contributors, Playlists | Main browsing destinations; retain per-destination state |
| Collection | Locations, Box Sets | Physical organization, covers, counts, breadcrumb paths |
| Review | Imports, Library Issues | Badge counts represent actionable work; no badge for normal historical activity |
| Utilities | Settings | Opens real categories; recovery/history live within Settings |

Use “Imports” in UI in place of “Library Changes”; keep existing persistence names if appropriate. Library Issues groups missing files, offline folders, duplicate candidates, and optional missing artwork. Missing artwork is an enhancement suggestion, not the same severity as unavailable music.

The Add Album toolbar menu offers Physical Album and Import Music Folder. Their different workflows can share the same album draft/review components without forcing file import through the physical form.

Use a typed navigation destination with stable IDs for albums, contributors, playlists, locations, box sets, imports, and settings categories. Keep destination history separate from selected sidebar section. Do not allow an old selectedAlbumID to show an unrelated album when switching to another destination with no selection.

Navigation requirements:

- Back preserves library search, filters, sort, grid/list mode, and scroll anchor.
- Going from a location/box/contributor to an album returns to that origin, not always Albums.
- Selecting a search result opens its associated object; deleting it produces an appropriate local empty state.
- Optional split browsing may show a compact album list and detail on wide windows, but is a later refinement, not a prerequisite for the default layout.
- Settings category clicks change actual content. No decorative navigation labels.
- Common keyboard behavior: Command-F focuses search; standard Back navigation works; Escape dismisses transient UI; text-field Space remains text input.
- Use stable IDs for selection and restoration. Async detail results must be ignored if the selected object changes before completion.

### 12.5 Visual system and responsive layout

Use native SwiftUI controls, system text styles, and semantic colors. Album covers provide visual character; avoid arbitrary gradients, decorative dashboards, and a rounded grey container around every group.

Initial design tokens, adjustable after native visual inspection:

| Element | Starting rule |
|---|---|
| Spacing | 4, 8, 12, 16, 24, 32 points; use one consistent rhythm |
| Workspace gutters | 24 points regular, 16 compact |
| Sidebar | Approximately 210–240 points; user-resizable/collapsible |
| Main title | Approximately 28–32 points, semibold; wraps naturally |
| Artist | Approximately 17–20 points, with clear secondary hierarchy |
| Readable metadata | Body/callout size, typically 13–14 points; reserve caption for provenance |
| Cover on album page | Approximately 220–260 points regular, 160–190 compact; preserve aspect ratio |
| Cards | Cover with modest 8–12 point corner radius; subtle or no shadow; title and artist below |
| Track rows | Approximately 40–48 points for ordinary tracks; expand for multiline/classical titles |
| Forms | Labels close to left-aligned input controls; do not separate labels and values across huge widths |
| Player | Approximately 72–88 points high, adapting controls to available width |

At narrow main-content widths (starting breakpoint about 700 points), reflow the album header vertically or use a smaller cover; do not shrink the text until it fits. At wide sizes, cap reading-column width around 1100 points while allowing album grids to use available space. Treat breakpoints as content-based, not device-name checks.

Test at full window sizes around 900×650, 1200×800, and 1600×1000 points. At the smallest size, permit sidebar collapse and vertical scrolling. Sheets must fit the available display; replace the current fixed 900-point lookup minimum with a responsive composition.

Required visual states: light/dark appearance, increased contrast, reduced motion, keyboard focus, selected row, long CJK/Latin titles, missing artwork, sparse metadata, and dense classical credits. Do not rely on color or hover alone. Full essential text must be accessible by wrapping or a clearly available detail view.

### 12.6 Albums library and search

Toolbar: destination title/count, search, filter control, sort, grid/list switch, Add Album. Avoid placing every filter as its own always-visible control.

Card hierarchy:

1. Cover.
2. Album title, up to two visible lines with full accessible text.
3. Primary artist or a justified “Various Artists”/“Artist not recorded” value.
4. Edition/year summary when present.
5. Restrained ownership/availability indicators; explain ambiguous icons through accessible labels and tooltips.

Do not infer “Various Artists” solely because composer and conductor credits both exist. Prefer recorded album-artist credits; when absent, use an explicit display fallback without changing catalogue data.

Filters are independent concepts:

- Ownership: All / Physical / Digital / Both.
- Availability: Any / Available to Play / Unavailable.
- Source: Any / This Mac / named registered music folder.
- Favourite and rating filters are optional refinements.

Do not use publishedAlbumIDs or an “iPad Music” sharing scope as proof that audio is physically on a NAS or currently accessible. Build display/query models from actual root and asset metadata. Physical ownership must respect the existing hasCD model while showing the recorded media format; broadening physical-media ownership semantics requires an explicit domain change.

Default sort: Title; offer Artist, Release year, Recently added, Rating. Persist user preferences locally. Search continues to find titles, other titles, credits, tracks, catalogue numbers, barcode, boxes, and locations. Add a result-context subtitle such as “Matched other title” where feasible; no need to rebuild the proven search index merely to restyle results.

Data loading: fetch artist/cover/availability summaries in bounded batched queries. Avoid per-card database queries, NAS existence checks, or synchronous image decoding. Cancel superseded search tasks and protect against out-of-order results.

Empty states distinguish an empty library (“Add your first album”) from no search/filter results (“Clear filters”). Offer useful actions directly.

### 12.7 Album page: reading layout

Use a ScrollView/composed page rather than a giant Form for reading.

Regular-width layout:

    Back to origin                               Edit Album   More

    [                     ]  Album title
    [     Front cover     ]  Primary artist
    [                     ]  Other titles, when recorded
    [                     ]  Edition · year · label · country · format
    Change cover…            Key credits, with roles
                             Owned / available / offline status
                             Physical location or box link
                             Play   Shuffle   Favourite

    Catalogue details: catalogue no. · barcode · remaster · rating
    Tracks                     Credits             Files & Notes
    Disc heading
    Number   Track / work and movement             Duration   More

This is a hierarchy guide, not a requirement to put all fields into fixed horizontal rows. Wrap/reflow gracefully. Catalogue details stay near identity, outside the track list; do not reintroduce a full-width label-at-left/value-at-far-right form.

Other titles:

- User-facing name is “Other titles”; keep album_alias as the internal entity.
- Display meaningful nonduplicate variants immediately below title/artist, with a compact language/type label when useful.
- Show up to two initially, then “Show all titles” expands in the same identity area.
- Edit title and variants in the same album editor, including add/edit/remove and optional locale/type.
- No empty Other titles section or Add Alias card at the page bottom.
- A variant is searchable and never creates or renames an album implicitly.

Credits:

- Show primary artist prominently; display relevant composer/conductor/ensemble roles below, in readable text.
- Limit the initial secondary summary to roughly three credits, with “View all credits” selecting the Credits section.
- Full credits group by role and link to contributor pages.
- In browse mode, no edit/remove buttons on every credit. Edit Album exposes credit editing.
- Editing a shared person's canonical name must explain that it affects other credits; an album-only credited-name override is a separate action.

Details and actions:

- One Change cover action next to the cover. Click the image to open the artwork viewer.
- Location and box names are navigable breadcrumbs. Display the inherited location for a boxed album.
- A physical album without audio shows “Physical copy · No digital audio attached” and Attach digital files. Hide unavailable Play/Shuffle.
- An offline digital album explains the unavailable folder and offers the relevant reconnect/issue route.
- A partially playable album shows a count and plays only resolvable tracks, with a clear summary of skipped tracks.
- Availability uses cached catalogue/root state; resolve and verify files again at actual playback time. Browsing must not probe every NAS file.
- More holds secondary commands, including Recently Deleted and advanced file operations. Do not place permanent deletion beside Play.

Tracks:

- Default columns: number, title, optional artist, duration, status, one More menu. Show the current-playing marker in the number area.
- Double-click/keyboard activation can play a playable track; a visible row action/menu provides an equivalent route.
- More: Play Next, Add to Queue (only once implemented), Add to Playlist, Lyrics, Track Details, Edit Track, Remove from Album.
- Disc/track creation and reordering belong in Edit Tracks/Organize mode. Preserve removal confirmations and existing reference/playlist cleanup semantics.
- Classical display supports work headings and movement titles without flattening or renumbering musical positions incorrectly.
- Catalogue tracks without assets remain readable and explicitly unplayable.

Files & Notes:

- Show physical/catalogue notes and source file information under clear subheadings.
- Expose existing metadata inspector, source format, root/path, and availability. Never claim unmeasured DAC output or bit depth.
- Place “Write catalogue changes to FLAC files…” in the Files area/advanced actions only when candidate FLAC assets exist. Do not read or prepare writes simply to decide menu visibility.
- Opening that action starts the existing preview; confirmation, backups, journal, verification, and undo remain mandatory.

### 12.8 Editing and artwork

Edit Album is one resizable editor with sections Identity, Edition, Credits, Physical Copy, Notes. Other titles belong to Identity. Use readable aligned fields and preserve unsaved input while moving between sections. Save commits the intended draft; Cancel discards unsaved changes. Confirm discard only when there are actual changes.

Normalize fully blank added credit rows away. A row with a role-specific override or other meaningful input but no name is incomplete and gets an inline error. Keep at least one meaningful contributor for physical entry under the current product rule. Explain missing requirements next to the relevant field and summarize them near Save.

Validate numeric fields explicitly: invalid nonempty years must not silently become nil. Keep a visible error after submission failure and preserve the draft for retry. Show progress during saves and prevent duplicate submission.

Artwork viewer:

- Selected cover appears large with optional front/back/booklet/disc thumbnails when records exist.
- Choose image, select front cover, and inspect source/provenance are deliberate actions.
- Reuse managed-artwork copying. Never delete the original chosen image.
- If select-existing-cover functionality is missing, implement a transaction that switches selection without duplicating files.
- Legacy “Make Portable” becomes “Store a copy with the library,” with its existing copy/rollback protections.
- Keep provenance/path/managed-state in Details. Never show a second oversized static cover at the bottom of the album page.
- Remote artwork failure offers retry, local image selection, or explicit Save without cover; no silently dropped cover promise.

### 12.9 Physical album entry and MusicBrainz

One workflow workspace, with Back/Continue and preserved draft state:

1. Find: search by title/artist, barcode, catalogue number, or paste a MusicBrainz release URL. Enter manually is visible from the start.
2. Review: select a specific pressing; inspect cover, artist, release date, country, label, catalogue number, barcode, format, discs, and track list.
3. Your copy: choose direct location, box set, or Set location later; optionally add a note, rating, and favourite.
4. Save: Add Album creates the confirmed catalogue draft and opens the resulting album.

Use at most one main sheet/window; candidate selection and review should not require a stack of modal sheets. The step labels may be combined on wide screens, but the state machine must remain explicit.

Review defaults:

- Import the selected release's provided fields and cover only after the user's selection; preserve user edits when returning from a different step.
- Changing to a different release shows which edited fields will change. Do not blend residual values from two releases silently.
- Provide an optional “Include track listing” control, enabled only when complete structured media/track detail is available.
- Keep remote lookup user-triggered. Retain the shared request timeout, caching, rate limit, and generation/cancellation protection.
- Clearly distinguish search results, loading selected release detail, no results, unavailable cover, offline service, and saving.

Implementation details:

- Current ExternalReleasePreview.trackTitles is flattened. Add a structured medium/track preview model before saving track lists: medium position/title/format, track position/display position/title/duration, optional credits/IDs where reliably supplied.
- Decode missing/irregular provider fields defensively; preserve catalogue numeric ordering separately from original display positions.
- Extend the atomic create use case to optionally create discs/tracks with credits and selected artwork. No digital assets are created; those tracks remain unplayable.
- Keep the old no-track manual-entry path valid. Provider failure must not prevent manual entry.
- Validate pasted URLs as MusicBrainz release identifiers using a fixed trusted API origin. Do not fetch arbitrary pasted URLs or interpret release-group links as exact pressings.
- Barcode search is typed/pasted text in this phase. Camera scanning and OCR are deferred.
- Preserve leading zeros in barcode/catalogue fields; encode provider queries safely.
- Duplicate suggestions prioritize exact external release ID when stored, then barcode/catalogue plus artist/title. Explain the evidence. Title alone must not block saving another pressing.
- Offer Open existing album or Add separate edition. Do not merge automatically or overwrite existing metadata.
- Persist external IDs/provenance only through an appropriate existing table/use case, or add a reviewed migration if needed; do not hide them in notes.
- Offer inline location creation with clear persistence semantics: either stage it until album Save, or explicitly label that Create Location saves it immediately and survives cancelling the album. Prefer staged creation if safely supported by the transaction.

### 12.10 Digital import and review

Entry: Add Album → Import Music Folder, or Imports → Scan Folder.

Flow:

1. Choose an existing registered folder or authorize a new folder. Reuse compatible existing registration rather than creating duplicate roots.
2. Scan and read metadata under one visible progress experience, with Cancel and clear completion/error counts.
3. Review album candidates, grouped into Needs Review, Ready, Added, and Skipped presentation categories mapped to existing persisted states.
4. For each candidate, choose Add new album, Link to existing album, or Skip.
5. On success, offer Open album and continue with the next pending candidate.

Import workspace: compact candidate list at left, selected album review at right on wide screens; single-page navigation at narrow widths. Show cover/title/artist and a concise pressing summary. Raw tags, paths, scan logs, and batch IDs belong in Details.

MusicBrainz matching belongs within the selected candidate review workspace. Use a shared candidate/detail component with physical entry, but preserve different save semantics: physical entry creates a new draft; digital review applies explicitly selected proposal fields before final import.

Attachment:

- From an existing album, Attach digital files opens this workflow with that album as the intended target.
- Still show file-to-track pairing and existing compatibility failures.
- Revalidate compatibility and root-relative path uniqueness transactionally.
- Preserve existing catalogue titles, credits, and artwork unless the user separately approves specific corrections.
- A mismatch offers Review matching or Add separate edition, not an unsafe Force attach.

Resume: persisted candidates survive closing/reopening; selection/filter restoration is device-local. Keep retry idempotent. If batch actions are added, report per-album results and allow retry of failures; never claim the whole selection succeeded after partial failure.

Do not perform online searches for every scanned album automatically. “Ready” means ready for explicit review/save, not authority for unattended import.

### 12.11 Player, queue, and lyrics

Compact player has cover/title/artist at left, transport/progress centrally, volume and Queue at right. Click identity to open its album or expanded player. At compact widths, move volume and secondary repeat/shuffle controls into an accessible popover. Stop may be secondary; Pause stays prominent.

Expanded player provides large cover, title/artist/album, transport, queue, lyrics, and Audio Details. It is presentation around the existing PlaybackController, not a new audio engine.

Queue:

- Display actual playback order and current index.
- Selecting an entry uses the existing resolved playback pipeline.
- Implement Play Next/Add to Queue/reorder only with explicit queue semantics and meaningful queue tests; do not draw enabled commands without behavior.
- Preserve repeat/shuffle selection, restored queue, no autoplay on relaunch, and latest-selection-wins behavior.
- Resolve artwork/artist through a batched/cacheable catalogue summary keyed by current track ID, not stale view selection.

Loading retains existing DSF percentage/estimate and NAS opening feedback. Show “Preparing playback” as the main message, with conversion/audio details available when useful. An older cancelled request must not replace the newest title, cover, progress, or error.

Lyrics use existing manual/plain/LRC storage. Empty state offers Add lyrics on Mac; instrumental works do not produce a warning. No internet lyrics provider is part of this redesign.

### 12.12 Contributors, locations, box sets, and playlists

Artists & Contributors:

- Searchable names with role filters; use initials/placeholders where no portraits exist rather than adding an unsolicited image service.
- Detail shows name, roles, album count, and credited album covers.
- Role-filtered album navigation supports classical collections.
- Shared-name edits explain their scope; do not merge people on fuzzy name similarity.

Locations:

- Tree or breadcrumb navigation, full hierarchical names, album/box counts, and covers in the selected location.
- Move a selection through a labelled Move action and location picker; drag-and-drop can be an enhancement.
- Preserve cycle prevention, inherited box location, and deletion guards.
- Direct albums and albums inside a box must be distinguishable to avoid double-counting.

Box sets:

- Header with title, edition, inherited location, member count, and optional available artwork.
- Members are ordered cover rows/cards that open album pages.
- Organize mode supports reorder and remove; retain keyboard-accessible movement commands alongside dragging.
- Removing a member opens the existing placement decision and never deletes its album.

Playlists:

- Header uses a collage of existing album covers, count, duration when known, Play and Shuffle.
- Add Tracks opens a searchable picker inside the playlist workflow; selected tracks are added without navigating away.
- Rows show track, artist, album, duration and availability, with one secondary menu.
- Reorder by drag and keyboard commands; removal is clearly “Remove from playlist.”
- Empty state includes Add Tracks. Any duration total based on incomplete data must be labelled accordingly.

### 12.13 Settings, issues, onboarding, and recovery

Settings has functional selection routing:

| Category | Content |
|---|---|
| General | Appearance/display preferences and catalogue export |
| Playback | DSF cache usage/limit/clear and supported player preferences |
| Music Folders | Named roots, access status, authorize/reconnect, scope, scan |
| iPad Sharing | Publication destination, last successful update, update/retry, advanced revision details |
| Backup & Restore | Complete archive as the primary recovery route; existing database-only backup clearly distinguished |
| Advanced | Safe cleanup, diagnostics, history, Recently Deleted, guarded reset |

Use ordinary descriptions such as “Update shared library” with an explanation that the catalogue is shared and source audio is not copied. Preserve the distinction between publication snapshots, complete recovery archives, database-only backups, and audio files.

Library Issues is an actionable page linked from badges/errors: group unavailable folders, missing files, potential duplicates, and artwork suggestions. Each issue explains the affected music and offers the existing appropriate repair workflow. No automatic relinking or deletion.

First-run empty library offers Add physical album and Import music folder. Explain folder permissions at the point of selection. Sharing and NAS configuration are optional until needed.

Errors stay near the task, preserve input, and provide Retry/Choose another folder/etc. Reserve blocking alerts for operations requiring immediate acknowledgement. Success should identify what was added and provide navigation, not just dismiss a sheet.

Reset and destructive recovery keep current verified archive and exact typed confirmation requirements. Improving wording or placement must not weaken the service layer.

### 12.14 iPad follow-on

After the Mac milestones stabilize, apply the same album identity and browsing hierarchy to the companion while preserving read-only catalogue access.

- Setup chooses a shared catalogue source and named audio-folder mappings.
- On later launches, show the cached library promptly, with unobtrusive refresh status.
- Root mapping UI selects published named roots instead of requiring a user to type UUIDs.
- Move snapshot paths, revision numbers, root IDs, and local statistics into Settings/Details.
- Keep local favourites, recent play, queue/preferences distinct from Mac catalogue data.
- Audit snapshot payload availability before promising artist/cover parity. Add backward-compatible fields/capability handling and verified managed-artwork distribution if necessary; never expose Mac absolute paths or bookmarks.
- iPad visual/device verification is a separate milestone. Do not mark it complete based on a Mac build.

### 12.15 Implementation architecture and change boundaries

The Mac UI currently lives mostly in MusicLibraryMacApp.swift. Avoid another large nested ViewBuilder change. Extract code incrementally around the feature being changed, keeping the composition root small and builds passing.

Suggested files/modules (names may be adjusted to existing conventions):

| Area | Suggested units |
|---|---|
| Navigation | LibraryNavigationState, LibrarySidebar, LibraryWorkspace |
| Design primitives | LibrarySpacing, ArtworkView, AvailabilityLabel, EmptyStateView |
| Albums | AlbumBrowserView, AlbumCardView, AlbumDetailView, AlbumIdentityHeader, AlbumTrackList, AlbumCreditsView |
| Editing | AlbumEditDraft, AlbumEditorView, OtherTitlesEditor, ContributorDraftEditor, ArtworkViewer |
| Add/review | AddAlbumCoordinator, PhysicalAlbumEntryView, ReleaseSearchView, ReleaseComparisonView, ImportReviewView |
| Playback | MiniPlayerView, NowPlayingView, QueueView |
| Organization | ContributorDetailView, LocationBrowserView, BoxSetDetailView, PlaylistDetailView, PlaylistTrackPicker |
| Settings | SettingsNavigation, individual category views, LibraryIssuesView |

Keep transient draft/navigation state in UI-specific observable models. Keep use cases in LibraryStore/application services; keep SQL and transactions in MusicDatabase. Do not spread database handles into the new views.

Source map:

- Sources/MusicLibraryMac/MusicLibraryMacApp.swift: existing shell, screens, editors, helpers.
- Sources/MusicLibraryMac/PhysicalAlbumMusicBrainzLookupView.swift: existing physical release search/detail composition.
- Sources/MusicApplication/LibraryStore.swift: catalogue use cases, managed artwork, import, publication, playback resolution.
- Sources/MusicApplication/MusicBrainzMetadataProvider.swift: provider query/preview models.
- Sources/MusicApplication/PlaybackController.swift: player lifecycle and queue integration.
- Sources/MusicPersistence/SQLiteDatabase.swift: transactional catalogue access.
- Sources/MusicDomain/Album.swift and CatalogueContent.swift: edition, aliases, credits, tracks, artwork.
- Sources/MusicLibraryPadShell/PadLibraryView.swift and MusicReadOnlyClient: later companion changes.

Required data work should be narrowly scoped:

1. Add batched album/track display summaries rather than repeated per-row reads.
2. Derive playable/FLAC candidate availability from catalogue assets and root state, with actual verification deferred to the action.
3. Add typed structured release media before optional track creation.
4. Audit existing alias update, cover selection, credits update, and queue APIs before introducing new ones.
5. Prefer one transaction for Save of an album draft spanning identity/aliases/credits/location, avoiding partial saves on Cancel/failure.
6. Reuse existing tables when possible; schema migrations require compatibility tests and documented snapshot implications.

Existing safety protections to retain: Mac-only catalogue writing, local SQLite, root-relative assets, authorized security scopes, offline roots not treated as deleted, explicit matching, no automatic retagging, verified archive/restore/reset, FLAC backup/journal protections, latest-selection playback generation checks.

### 12.16 Ordered milestones and completion gates

Work on one milestone at a time. A passing build is necessary but does not demonstrate a beautiful or usable screen. Each milestone must show visual evidence and a completed user journey.

| ID | Deliverable | Dependencies | Completion gate |
|---|---|---|---|
| R0 | Connected native design compositions with safe fixture data; token/layout definitions | Current baseline | Library → album → edit/add navigation demonstrated at compact/regular widths; long titles, sparse data, many credits and physical-only examples shown |
| R1 | Extract focused components; two-column navigation and real Settings routing skeleton | R0 | Back/context restoration works across Albums, locations and contributors; no stale album when changing destinations; no service behavior regressions |
| R2 | Album page, Other titles, readable credits/details, track reading/edit modes, artwork viewer | R1 | All identity information placed together; no duplicate cover controls; physical/offline/partial states correct; edits and cancellation work |
| R3 | Album library/search, batched artist and availability summaries, filters | R1–R2 | Cards show artist; filters reflect actual ownership/source; large fixture library remains responsive; empty/no-match states actionable |
| R4a | Unified physical workflow using current title/artist lookup and manual path | R2 | Find → review → location → save → open album; no nested modal maze; empty-row/validation behavior resolved |
| R4b | Barcode/catalogue/release-URL lookup, duplicate suggestions, optional structured track creation | R4a | Exact-release parsing/query tests, multi-disc fixtures, transactional rollback, no digital assets for physical tracks, failed cover save recovery |
| R5 | Import review workspace and attachment from an album | R2, shared R4 review components | Add/link/skip, mismatch explanation, resume/retry, existing metadata preservation, source file safety verified |
| R6 | Player identity, expanded player, queue/lyrics routes | R3 display summaries | Correct cover/artist during rapid selections, compact controls usable, queue semantics tested, no playback lifecycle regression |
| R7 | Contributor/location/box/playlist browsing and organize flows | R1–R3 | Albums navigable from each; playlist adds in place; reorder accessible; placement guards preserved |
| R8 | Complete Settings categories, issues, onboarding, recovery wording | R1 | Every category/action works; publication vs backup distinctions clear; guards and recovery paths verified with disposable fixtures |
| R9 | Whole-app visual/accessibility/performance pass and delivery | R2–R8 | Acceptance matrix below passed or explicitly reported blocked; sequential package verified; handoff records exact next boundary |
| R10 | iPad follow-on design/implementation | Stable Mac; snapshot capability audit | Read-only behavior and cache/offline/connection flow verified; separate device validation status reported |

R0 should use native previews or a dedicated fixture-backed showcase that never starts the live LibraryStore or reads personal Application Support. If a safe visual harness does not exist, make its isolation explicit before running it. Do not substitute an HTML imitation as proof of native layout.

When a build is authorized, routine design choices follow this specification. Present R0 visual evidence and continue within the authorized scope; seek clarification only for a materially new product decision or a real ambiguity. Do not require repeated approvals for each spacing/label choice.

### 12.17 Validation and acceptance matrix

Use disposable fixture catalogues, generated/local test images, and stubbed provider responses. Do not use the user's live catalogue as a test fixture. Real NAS endurance, actual DAC behavior, and iPad device checks remain separately reported.

Required fixture set:

- Sparse physical-only album with no artwork/tracks.
- Complete digital album and mixed physical/digital album.
- Two editions with the same title/artist and different pressing details.
- Chinese/Japanese title plus translated and romanized other titles.
- Long classical title with composer, conductor, ensemble, many soloists, and multiple discs.
- Compilation with explicitly recorded Various Artists.
- Offline root, missing asset, partial album, unsupported write-back format.
- Album in a box with inherited hierarchical location.
- Empty and large playlist; large library around 1000 albums using synthetic metadata.
- MusicBrainz zero results, incomplete media detail, unavailable cover, timeout, and stale response after selection changes.

| Journey | Observable pass condition |
|---|---|
| Find by other title | Search returns correct album; variant is readable near title; no new album created |
| Browse/back | Grid/list/filter/search/scroll context restored from album and contributor routes |
| Edit identity | Main/other titles and credits editable together; Cancel writes nothing; invalid draft shows specific errors |
| Physical save | Title/credit/location sufficient; extra blank row does not block; save opens new album |
| Physical tracks | Structured multi-disc listing saved only if selected; zero digital assets/playable actions created |
| Duplicate suggestion | Correct pressing evidence shown; user can open existing or intentionally add another edition |
| Link files | Pairing reviewed; mismatch refused; successful attachment idempotent and metadata preserved |
| Artwork | Change action obvious; chosen front persists; viewer source details accessible; originals unchanged |
| Playback | Correct identity, progress and queue; no late request wins; offline failure understandable |
| Organization | Add/reorder/remove works; box removal preserves album and requires correct placement |
| Settings | Every category changes content; no dead category labels; reset/restore guards retained |
| Resize/accessibility | No horizontal overflow/overlap; usable keyboard focus and screen-reader labels; no color-only status |
| Safety | Browsing does not change catalogue revision; source checksums unchanged except explicit isolated FLAC-write tests |

Automated tests should cover meaningful behavior: draft normalization, numeric validation, summary derivation, navigation restoration/stale-response handling when practical, provider parsing, transactions, duplicate suggestion evidence, queue semantics, and existing safety regressions. Do not add tests that simply assert view label strings or mirror trivial layout code.

Run focused tests while implementing. At delivery, run repository-required swift build, swift test, swift test -c release, and git diff --check. Reuse successful results until relevant code changes. Capture native visual evidence at the three target sizes and note what was actually inspected. Include editor, menu, empty, loading, error, and success states, not just an attractive populated album.

No release claim based solely on compilation or screenshots of old binaries. Package via Scripts/package-mac-app.sh, advance the next sequential version only for an actual app delivery, check plist/signature, and verify the installed executable matches the packaged executable if installing. Documentation-only planning does not bump a version.

### 12.18 Handoff and execution instructions for Luna

For each milestone, record in HANDOFF.md: completed behavior, actual files changed, tests/visual evidence, remaining limitations, and exactly which milestone comes next. Keep this section as the product specification; do not duplicate progress diaries here or in AGENTS.md.

Suggested implementation prompt:

> Implement the Music Library redesign in BUILD_PLAN.md section 12, beginning at the next unfinished milestone in HANDOFF.md. Read AGENTS.md and IMPLEMENTATION_SPEC.md first. The current app and its safe services are the baseline; do not restart the original project phases. Build connected native fixture compositions for R0, then implement the milestones in dependency order. Follow the specified navigation, title/other-title grouping, browsing/editing separation, physical entry and import flows. Preserve all catalogue, artwork, playback, and source-file safety invariants. Validate real native layouts at compact and wide sizes, use isolated fixtures, and report what was actually verified. Keep changes incremental, update the canonical handoff, and deliver a sequentially versioned app only after the applicable checks pass.

If the user asks for only one milestone, stop after completing that milestone and its handoff. If the user asks for the whole Mac redesign, continue R0–R9 without treating each routine milestone as a new permission request. R10 and deferred provider/audio features do not become included automatically.

Design references used for hierarchy and navigation principles:

- [Apple Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

These are guidance, not evidence that the app already implements or has passed the proposed design.
