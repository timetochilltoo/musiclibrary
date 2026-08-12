# Music Library — Product and Build Plan

Original plan date: 22 July 2026

Last roadmap review: 12 August 2026

Detailed coding handoff: [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md)

Operational continuation guide: [HANDOFF.md](HANDOFF.md)

Implementation baseline (22 July 2026): the macOS catalogue foundation, retained local/NAS authorization, Import Inbox, assets, playback, recovery, destination-configured snapshot publication with revision retention/status and tested scheduling, verified read-only cache, iPad browsing/playback, foreground update indication, and a generated Xcode iPad project are complete and covered by thirty-seven automated tests. The remaining Mac publication gap is a time-bounded quit flush; device deployment needs a Development Team selected in Xcode. See [HANDOFF.md](HANDOFF.md) for the current Git baseline and next implementation slice.

## Current execution gate — audit hardening before visual redesign (12 August 2026)

The existing Mac catalogue and player now have enough working surface area to justify a release-oriented audit before the planned artwork-first UI pass. The audit found no evidence of a data breach or catalogue corruption in the current test baseline, but it identified several defensive and reliability improvements that must be completed first. The visual implementation workstream is therefore **blocked until this gate exits**.

The hardening workstream is executed as small, independently tested slices:

1. **Path and CUE safety:** enforce component-aware, symlink-resolved containment for registered roots, child-folder imports, replacement/relink paths, and CUE `FILE` references. Reject absolute/parent escapes and add traversal/symlink regression tests.
2. **Backup and snapshot safety:** validate manifest filenames and archive paths, preserve the last known-good manifest until the replacement is verified, and make local/NAS cache replacement pair-consistent and bounded.
3. **Audio-container validation:** make DSF/WAV arithmetic overflow-safe, reject malformed/truncated headers before allocation or playback, and add malformed-file tests for the supported catalogue/playback paths.
4. **Reliability and performance:** move full-file fingerprinting and other avoidable blocking work off the main actor, add bounded network/database waits, prevent startup failure from permanently disabling retry, and remove duplicate scheduled backup work.
5. **Exit verification:** run focused tests after each slice, then the complete debug/release Swift test and build checks, update `HANDOFF.md`, commit, and push. Only after this exit review may the visual foundation begin.

These changes preserve the fixed product invariants: the Mac remains the only catalogue writer, scans and lookups remain explicit and non-mutating, source audio is never rewritten by review actions, NAS publication remains snapshot-based, and the later UI redesign must not alter persistence semantics.

**Hardening progress (12 August 2026):** the registered-root/CUE containment, backup/snapshot safety, DSF/WAV validation, playback repeated-work cleanup, chunked background fingerprinting, startup retry, scheduled publication/backup isolation, bounded network request, grouped Library Health, and fail-closed security-scope slices are complete and independently tested. Only final release/exit verification remains; the visual redesign remains blocked until those checks pass.

**Audit hardening — bounded metadata and artwork requests (12 August 2026):** explicit MusicBrainz searches, release-detail requests, and cover-art downloads now share a 30-second `URLRequest` timeout. The request policy is applied both in the metadata provider and in Mac artwork actions, so a disconnected NAS/VPN or captive network cannot leave a user-triggered lookup waiting indefinitely. Audio files are still never uploaded by these actions, and no catalogue or source-file semantics changed. Regression coverage verifies the shared timeout policy; the full Swift suite passes 83 tests.
**Audit hardening — grouped Library Health root access (12 August 2026):** the available-asset health pass now groups candidates by registered storage-root ID, resolves each bookmark once, and holds that root's security-scoped access for the whole group. It still checks every stored relative path and writes the same availability result, but avoids reopening the same NAS/local root once per track. The full Swift suite passes 83 tests; no catalogue or source-file semantics changed.
**Audit hardening — fail-closed security-scoped operations (12 August 2026):** user-selected artwork, legacy artwork migration, snapshot publication, master-backup creation/restoration, and registered-folder bookmark creation now stop before filesystem or database work when macOS denies the security-scoped resource. Previously these paths could continue after a denied scope and report a later, less actionable filesystem error. The full Swift suite passes 83 tests; no catalogue, source audio, or backup data was changed by the test run.

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

### Mac visual design direction (reviewed 12 August 2026)

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

- Render each release proposal as a compact horizontal card: artwork at the leading edge; title, artist, source/provenance, confidence, disc/file summary, and creation status in the middle; the three state-appropriate actions at the trailing edge. Keep **Search MusicBrainz…**, **Approve for Later**, and **Dismiss** visually ordered by importance.
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
