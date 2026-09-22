# Music Library — Project Handoff

Last updated: 22 September 2026
Repository: `https://github.com/timetochilltoo/musiclibrary.git`
Primary branch: `main`

This is the operational handoff document for a new agent or developer. Read it first when resuming the project after context loss. It describes what is currently implemented, how to verify it, what must not be changed casually, and the exact next slice of work.

Do not treat a commit hash copied into a handoff as authoritative. Before changing code, run:

```bash
git status --short --branch
git log --oneline -5
git pull --ff-only
```

If the worktree is not clean, preserve and inspect those changes before starting new work. They may belong to the user or a previous agent.

## 1. Read these documents in this order

1. This file — current operational state and next task.
2. [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md) — source-of-truth technical architecture, schema, invariants, algorithms, and test strategy.
3. [BUILD_PLAN.md](BUILD_PLAN.md) — product scope, rationale, roadmap, and user-facing acceptance goals.
4. The current source and tests listed in section 6.

When requirements conflict, use this precedence:

1. The user's latest explicit instruction.
2. `IMPLEMENTATION_SPEC.md` fixed decisions and invariants.
3. This handoff's current implementation status and next-slice requirements.
4. `BUILD_PLAN.md`.
5. Reasonable engineering judgment, documented in the next handoff update.

## 2. Project objective

Build a personal music library application beginning on macOS in SwiftUI. It catalogues physical CDs and digital music in one album profile, allows local lossless playback later, and will later have a read-only iPad companion. The Mac is always the only catalogue writer.

The application must remain a dependable personal catalogue before it becomes a scanner, player, network client, or AI tool. Protecting the user’s existing music files and catalogue data is more important than automating data entry.

## 3. Fixed product and architecture decisions

These are agreed decisions. Do not silently reverse them.

| Area | Decision |
|---|---|
| Writer | macOS is the sole catalogue writer. |
| Companions | iPad is the first read-only companion; Android is deferred. |
| Database | The live SQLite database stays local to the Mac. Never open its live file directly over SMB/NAS. |
| Publishing | Mac publishes consistent snapshots to the NAS manually and automatically after a debounced change and on orderly quit. |
| Read-only launch | Clients check the snapshot manifest modification date, then revision/schema/checksum before downloading a newer snapshot. |
| Audio on iPad | iPad uses a user-selected SMB root with its own local root mapping. Catalogue snapshot availability is independent of SMB audio availability. |
| CD ripping | Out of scope. Import pre-existing audio files only. |
| Album identity | One album profile is one pressing/edition, not an abstract release group. |
| Physical/digital | One profile can show `CD ✓` and `Digital ✓`. `hasCD` is stored; digital state is derived from assets. |
| Editions | Different pressings/remasters/regions are separate album profiles with an edition label plus structured fields. |
| Physical copies | Version 1 assumes at most one physical instance for each album profile. No physical-copy table. |
| Multi-disc vs. box | Multi-disc is one album with several discs. A box set groups separately named album profiles. |
| Box location | A member album inherits its box set's location and has no direct location while boxed. |
| Metadata safety | Import/matching never writes tags or renames files automatically. |
| AI | Future optional provider adapters. They must not couple the catalogue, scan, or playback core to one vendor. |

## 4. Development environment and access

Verified on the current Mac:

| Tool | Known state |
|---|---|
| macOS | 26.5.2, Apple silicon |
| Xcode | 26.6 (build 17F113) |
| Swift | 6.3.3 |
| Git | 2.50.1 |
| XcodeGen | Installed, but not currently used; this project is a Swift package. |
| Git remote | `origin` is `https://github.com/timetochilltoo/musiclibrary.git` |
| Git identity | `timetochilltoo <152804118+timetochilltoo@users.noreply.github.com>` |
| Git authentication | HTTPS Git push works via macOS Keychain / `osxkeychain`. GitHub CLI (`gh`) token was invalid when checked; do not require `gh`. |

Use normal Git commands. Do not print, extract, or store Keychain credentials. If a new environment cannot push, ask the user to authenticate Git/Keychain rather than inventing a token workflow.

The workspace may require an elevated normal build environment for SwiftPM because its caches and manifest sandbox are outside the workspace sandbox. This is expected; `swift test` has been verified successfully with the normal Xcode/SwiftPM environment.

## 5. Exact build, test, and Git workflow

From the repository root:

```bash
swift test
swift build
git diff --check
git status --short --branch
```

Before committing:

```bash
git add <only intended files>
git diff --cached --check
git commit -m "Clear imperative summary"
git push
```

Required quality gates for every functional slice:

1. `swift test` passes.
2. `git diff --check` and `git diff --cached --check` produce no whitespace errors.
3. New behaviour has focused unit or persistence tests.
4. Relevant documentation is updated: implementation status, current next slice, any changed invariant, and any newly resolved user decision.
5. Commit and push the completed tested slice unless the user explicitly asks not to.

Never use `git reset --hard`, force push, or delete the user’s Application Support database. Do not commit `.build`, Xcode derived data, user databases, SQLite WAL/SHM files, API keys, or local media.

## 6. Current repository layout

```text
BUILD_PLAN.md                    Product plan and delivery roadmap
IMPLEMENTATION_SPEC.md           Technical source of truth
HANDOFF.md                       This operational handoff
Package.swift                    SwiftPM package definition
project.yml                      Reproducible XcodeGen iPad project definition
MusicLibraryPad.xcodeproj/       Generated Xcode iPad project

Sources/
  MusicDomain/
    Identifiers.swift            UUID-backed typed IDs
    Album.swift                  Album draft/entity, validation, availability enums
    PhysicalCollection.swift     Locations and box-set domain types
  MusicPersistence/
    SchemaMigrator.swift         SQLite schema migrations 1 and 2
    SQLiteDatabase.swift         Actor-backed database operations
    Repositories.swift           Initial repository protocol
  MusicApplication/
    LibraryService.swift         Thin album service
    LibraryStore.swift           Main-actor observable store for the macOS app
  MusicUIComponents/
    AlbumRow.swift               Album list row and availability display
    AvailabilityBadge.swift      CD/Digital badge component
  MusicLibraryMac/
    MusicLibraryMacApp.swift     Current macOS SwiftUI shell and editor sheets
    PhysicalAlbumMusicBrainzLookupView.swift  Explicit MusicBrainz search and physical-album prefill sheet
  MusicReadOnlyClient/
    SnapshotClient.swift         Verified, atomic local snapshot-cache updater
    ReadOnlyCatalogue.swift      Codable snapshot payload and album search model
    SMBRootMappings.swift        Device-local published-root to SMB-root preferences
    SnapshotSourceStore.swift    Security-scoped selected snapshot-source preference
  MusicLibraryPadShell/
    PadLibraryView.swift         Portable read-only SwiftUI companion shell
    CompanionPlaybackController.swift  Device-local resolved-URL playback controller
  MusicLibraryPad/
    MusicLibraryPadApp.swift     iPad SwiftUI application composition root

Tests/
  MusicDomainTests/AlbumTests.swift
  MusicPersistenceTests/MusicDatabaseTests.swift
```

The package products are `MusicDomain`, `MusicPersistence`, `MusicApplication`, `MusicReadOnlyClient`, `MusicLibraryPadShell`, `MusicUIComponents`, and the `MusicLibraryMac` and `MusicLibraryPad` executables. SQLite is linked with the system `sqlite3` library; there are no third-party dependencies. The package declares macOS 15 and iOS 18 support. `MusicLibraryPad` is the SwiftUI iPad application composition target. Run `xcodegen generate` to reproduce `MusicLibraryPad.xcodeproj`; its Xcode targets build the shared read-only client and pad shell directly, rather than resolving the local Swift package. Automatic signing is configured, but a Development Team must be selected in Xcode for a physical device/archive.

## 7. Current implemented behaviour

### Database and domain

Implemented and tested:

- Strong UUID types for core entities such as albums, locations, box sets, tracks, and assets.
- `NewAlbum` validation: nonblank title, disc count at least one, valid years, rating range, and no direct physical location when no CD is marked.
- Album display title combining title and optional edition label.
- Derived digital availability state model: `none`, `complete`, `partial`, `offline`, and `broken`.
- SQLite migrations 1 through 7 with foreign keys, catalogue revision state, album, aliases, locations, box sets, discs, tracks, contributors, storage roots, digital assets, playlists, import batches/candidates/release proposals, and relink proposals.
- SQLite WAL mode and foreign-key enforcement on database open.
- Persist/create/query albums; search title, edition label, catalogue number, barcode, aliases, tracks, contributors, box names, and physical-location paths through the transactionally rebuilt FTS5 catalogue index, with the existing LIKE fallback retained for compatibility.
- Persist/create/list/rename/move/delete physical locations. Parent validation, self/descendant cycle protection, and deletion guards prevent orphaned albums, box sets, and child locations.
- Persist/create/list box sets.
- Add an existing album to a box set, clearing its direct location and ensuring CD availability.
- Create a new album directly in a box set atomically; failure to find the box rolls back album creation.
- Edit albums; browse, confirm moves into, remove from, and reorder box-set members.
- Distinguish standalone unknown physical location from boxed placement with `physical_location_unknown`.
- Catalogue-content persistence: ordered discs/tracks, aliases, contributors, album- and track-level contributor roles, and album artwork records with source provenance.
- Album detail displays and adds discs, tracks, aliases, album contributor credits, and track contributor credits.
- Tracks can be edited in persistence and safely removed from the UI; remaining tracks are renumbered transactionally. Album Detail exposes track-title editing, displays its contributor credits, and lets the user correct a contributor's shared display/sort name. Album title and edition corrections use the existing album editor. These are catalogue-only corrections; they never write source audio tags. Aliases can be removed from the UI.
- New user-selected artwork is copied into `Application Support/MusicLibrary/Artwork` before its managed path and source label are recorded. Selecting another front image switches the selected state transactionally; the source image is never modified. Existing path-only artwork records can now be migrated explicitly from Album Detail: the app verifies the source, copies it first, updates the same artwork row only after the copy succeeds, and removes the new managed copy if the database update fails. Missing or unreadable legacy sources leave the catalogue unchanged; originals are never modified or deleted.
- Storage roots persist a display name, last-known path, security-scoped bookmark data, volume identifier, availability state, and bookmark-refresh flag. Root access is checked without scanning files.
- The Settings UI lets the user choose a local/NAS folder, rename it, recheck access, or remove it when it has no digital assets. It labels roots as Available, Offline, or Permission required.
- The completed scanning workflow creates audit batches and audio-file candidates only. It recursively probes standard audio content types plus DSF, expands WAV+CUE into timed virtual tracks, skips hidden/package content, retains file-level errors, supports cancellation/retry, and recovers an interrupted scan as cancelled on relaunch. While scanning, Library Changes shows transient item/audio counts and the current relative path; persisted batch counts describe the completed recorded results. It never creates catalogue records or modifies audio files until the user explicitly reads metadata, approves a proposal, and confirms record creation.
- Embedded common tags and duration are read locally through AVFoundation, preserved with `embedded-tags` provenance, and grouped deterministically into release proposals. Review can directly create a new edition, open attachment review for an existing edition, or dismiss a proposal. Creation and attachment atomically record approval with the catalogue change; dismissal creates no catalogue records, changes no source files, and contacts no external service.
- Creating an edition directly from a proposal creates an album, ordered discs/tracks, and root-relative digital assets in one idempotent transaction. Attaching to an existing edition uses the same one-step transactional behavior. A repeated operation returns the already associated album. Library Health derives missing/offline/partial status from track assets and current root status, and flags any active album without selected front artwork; it never relocates or deletes a file.
- Local Mac playback resolves only available, authorized root-relative assets, verifies file existence, and uses normal shared AVFoundation output. Playing a track queues its disc; the persisted queue supports previous/next, repeat, shuffle, volume, pause, stop, and seek API. Missing/offline files fail locally without any catalogue mutation.
- Playlists use the existing ordered playlist tables. The UI supports playlist creation, listing/detail, and adding album tracks. Normal playback completion advances the resolved local queue; no queue failure changes catalogue data.
- Snapshot publication writes a revisioned sanitized JSON payload and writes the SHA-256-protected manifest last. Its current payload contains a format, schema version, catalogue revision, album rows with ID, edition/year/catalogue/CD/digital data, ordered discs/tracks, and root-relative digital-asset references. It contains no Mac bookmark or absolute path. The read-only client refuses malformed formats, unsupported newer schemas, unsafe names, stale revisions, and checksum failures; it atomically retains the last verified cache after any failure.
- Mac Settings now stores a security-scoped snapshot-destination bookmark, provides Publish Now, reports publication state, and waits five seconds after the final catalogue change before automatic publication. The publisher retains the current revision plus three prior revision payloads by default, writes the revision file before the manifest, and leaves the prior manifest untouched on a failed write.
- The Mac displays observed catalogue and last-published revisions. Reload schedules automatic publication only after a changed revision; scene background attempts a best-effort final publish without becoming a hard quit blocker.
- Publication status now includes a pending state. Automatic/background publication skips work when the current revision is already published; an unavailable destination becomes a deferred, retryable status rather than a catalogue error.
- Device-local SMB root mappings are persisted separately from published snapshot content. Replacing a mapping changes only the selected published-root ID.
- `MusicLibraryPadShell` supplies a read-only SwiftUI navigation view which shows whether the local verified snapshot cache exists, lists the device-local SMB mappings, and browses the verified payload as searchable album list/detail views. Album detail shows tracks and whether their first asset is mapped, unmapped, unavailable, or refused for an unsafe path. A device-local player exposes play/pause/stop only for an existing file under a mapped, available root. It persists a user-selected snapshot folder as a security-scoped bookmark, offers manual verified refresh, and provides user-selected SMB root add/replace/remove controls. It exposes no catalogue edit controls.
- `MusicLibraryPadApp` keeps all companion state under `Application Support/MusicLibraryPad`: `SnapshotCache`, `SMBRootMappings.json`, and `SnapshotSource.bookmark`. At launch it opens the last verified cache independently of the NAS and checks the selected source manifest modification date, non-blockingly indicating when a refresh is available.
- Increment catalogue revision once per successful high-level write operation.

### macOS UI

Implemented:

- Three-column SwiftUI navigation shell.
- Album browsing and local search.
- **Add Physical Album** is now the Albums toolbar's single manual-entry command. Its one-pass form captures complete structured edition fields, multiple contributor credits and roles, an explicit direct-location/box-set/unknown choice, inline creation of a hierarchical location, physical and catalogue notes, rating, and favourite state. Album creation, any new contributor identities, their role links, and optional box membership are one SQLite transaction and one revision. It creates no digital assets, so it is not playable until audio is attached later. Artwork and optional manual disc/track data remain Album Detail actions.
- Hierarchical location list with full paths, indentation, create/rename/move/delete actions, parent-cycle protection, and visible deletion explanations when child locations, albums, or box sets still reference a node.
- Box-set list and create-box-set form.
- Basic album detail view showing edition fields, CD status, and direct location or box/unknown state.
- Library Changes list/detail with live scan progress, cancellation, retry, clear completed-scan outcome, per-file error review, candidate paths/types, embedded tag values, grouped release proposals, confidence/provenance, explicit review controls, and an explicit create-catalogue-records confirmation.
- Settings shows calculated Library Health issues for missing, offline, and partial digital albums, plus albums with no selected front artwork.
- Album tracks have Play controls; a persistent Now Playing strip provides transport, Queue (shuffle/repeat), volume, and stop controls.
- Playlist navigation provides playlist creation, membership detail, and add-track actions.
- Error alerts and initial database-opening progress UI.

**Visual implementation checkpoint (13 August 2026):** the sidebar is now grouped into Library (Albums, Contributors, Playlists), Organize (Locations, Box Sets), Review (Library Changes), and Settings. Albums defaults to an adaptive artwork grid and can switch to a dense list; toolbar controls cover All Music / This Mac Only / NAS / iPad Music, title/newest/recent/rating sorting, and favourites-only filtering. Selected front-artwork paths are fetched in one persistence query and image decoding runs off the main actor. Album detail leads with a large artwork hero, edition/source/favourite badges, and Play/Shuffle actions, while catalogue fields remain progressively disclosed. The persistent MiniPlayer exposes seekable elapsed/duration progress, previous/play/next, visible shuffle/repeat states, volume, and stop. A pre-existing import-attention string-interpolation defect was also corrected. These changes preserve catalogue and source-media semantics. `swift build` and all 86 tests pass at this checkpoint; the next presentation slice is Library Changes, playlists, Settings, and Library Health.

**Review and organization presentation checkpoint (13 August 2026):** Library Changes root rows now carry explicit status icons/text, its detail begins with four compact scan metrics, and the primary combined action is labelled **Rescan and Review New Files**. Proposal review uses horizontal artwork/title/provenance/action cards; full embedded tag walls are collapsed under **Technical details**. Playlists now have a visual header, count, prominent whole-playlist action, and individual direct-play/reorder/remove rows with tooltips. Settings starts with Catalogue, Music Folders, and Library Health summary cards and uses icon-led publishing, export, folder, and health headings. Settings is rendered in the wide detail workspace instead of being squeezed into the middle navigation column. Section-specific empty states replace the former generic album message, and compact Library Changes rows keep status text with their file/error summary instead of wrapping a detached status column. These are presentation-only changes; the separate reconciliation-only Rescan remains available and no network lookup or catalogue mutation became automatic. The rebuilt app and all 86 tests pass.

**Mac visual-workstream exit verification (13 August 2026):** `swift build`, all 86 tests in 8 suites, `git diff --check`, the production packaging script, and the project-steward Git/GitHub/tool preflight pass. The packaged `/Users/patrickshi/Documents/Codex/Music Library/build/Music Library.app` was launched without scanning, publishing, or editing the user's catalogue. Real compact-window inspection covered Albums/MiniPlayer, Library Changes, Playlists, and Settings; it caught and corrected the Settings column placement, Library Changes status wrapping, and generic empty-detail wording. The final corrected production app was rebuilt at 00:44 local time. No source media or Application Support catalogue was modified by this validation.

**Visual design review (12 August 2026):** the next Mac presentation workstream is artwork-first, icon-led, and progressively disclosed. The approved direction keeps the existing three-column shell and catalogue/review safety semantics, while simplifying the visible surfaces: Albums gets an artwork grid/list toggle plus All Music / This Mac Only / NAS / iPad Music scope filters; album detail leads with artwork and concise badges, with raw tags/technical fields behind Files or Details disclosure; Library Changes uses artwork/title/provenance/action cards; MusicBrainz Lookup becomes a resizable candidate-and-comparison workspace with imported/remote artwork and track comparison; and the MiniPlayer becomes artwork-led with explicit source, shuffle/repeat selected states, queue, lyrics, and an expanded technical view. Use native symbols consistently, pair ambiguous/destructive symbols with labels/tooltips, and never rely on color alone for status. This is UI-only scope: it must not add automatic network lookup, source-file mutation, or client-side catalogue writes. The detailed workstream and visual acceptance checks are in [BUILD_PLAN.md](BUILD_PLAN.md).

Runtime database location on the Mac:

```text
~/Library/Application Support/MusicLibrary/MusicLibrary.sqlite
```

This database is user data. Do not remove it during development. If a destructive schema experiment is unavoidable, first make a recoverable copy and tell the user exactly what happened.

## 8. Current tests and verification baseline

The current debug baseline contains 101 tests in 9 suites. Delivery validation for version 0.9 (build 10) also runs the rebuilt release suite before commit. Run `swift test` and `swift test -c release`; do not rely on this handoff alone.

Albums now expose **Move to Recently Deleted** in the Albums list context menu. Settings displays a **Recently Deleted** section and its Restore action. This uses the existing soft-delete records, preserves album relationships, and never deletes or changes source media files.

Settings also provides **Export Catalogue JSON…**, which uses the system Save dialog and writes only a portable catalogue JSON file to the user-selected destination. It never copies audio or changes catalogue data.

**Export Catalogue CSV…** writes a quoted, spreadsheet-friendly album-level export to a user-selected location. It includes identity, edition, release/country/catalogue fields and CD/digital availability; it never copies media.

The Mac Add/Edit Album forms now expose the agreed 1–5 catalogue rating and favourite flag; Album Detail displays both. These remain Mac-authored catalogue data, distinct from future device-local companion favourites.

`MusicDomainTests/AlbumTests.swift` verifies:

- Album title validation.
- Direct location requires CD availability.
- Edition label display formatting.
- Broken availability takes precedence.
- Complete assets produce complete availability.

`MusicPersistenceTests/MusicDatabaseTests.swift` verifies:

- Schema migration 6 and initial catalogue revision.
- Album persistence and revision increment.
- Box membership clears direct location while retaining CD availability.
- Location list and rename.
- Failed creation in a nonexistent box set rolls back the album and revision.
- Album editing preserves identity and revision semantics.
- Member moves, reordering, removal, and invalid removal rollback preserve placement rules.
- Ordered discs/tracks, aliases, contributor roles at both album and track levels, selected artwork provenance, and safe content removal persist correctly.
- Storage-root bookmark round-trip, offline state retention, rename/removal, and revision behaviour.
- Import Inbox batch/candidate persistence and proof that scanning does not mutate albums or catalogue revision.
- Metadata-proposal persistence, approval state, and proof that review does not create catalogue records or alter catalogue revision.
- Idempotent approved-proposal confirmation and offline-root Library Health derivation.
- Explicit individual relink application: updates only the catalogue-relative path, consumes the reviewed proposal, and increments the catalogue revision.
- Queue ordering/repeat and Codable state restoration.
- Playlist ordered membership persistence.
- Safe-cleanup preview/removal boundaries and single-revision behavior.
- Typed catalogue reset rejection plus registered-root preservation.

`MusicApplicationTests/ImportScannerTests.swift` verifies content-type audio discovery, hidden-file exclusion, cancellation before enumeration, Unicode/multi-disc proposal grouping, manifest-last publication, bounded snapshot retention, verified master-archive creation, and daily master-backup retention. `CompleteCatalogueArchiveTests.swift` verifies database-plus-artwork archive creation, staging, exact recorded artwork-path mapping, and checksum failure after tampering.

`MusicReadOnlyClientTests/SnapshotClientTests.swift` verifies verified snapshot replacement, checksum-failure fallback to the prior local cache, device-local SMB mapping replacement semantics, snapshot-source bookmark persistence/clear behavior, verified-payload Unicode/search decoding, root-relative asset resolution (including unmapped, unavailable, and traversal-path refusal states), selection of a playable URL only from a mapped available asset, and manifest-date refresh indication without cache mutation.

There are no UI automation or visual snapshot tests yet. Building via `swift test` compiles the macOS executable, but does not exercise a real UI session. Add targeted tests before making core data behaviour more complex.

## 9. Important implementation details and limitations

### Persistence actor

`MusicDatabase` is an actor. Keep SQLite access inside it. Do not pass raw SQLite pointers, statements, or mutable database state into views or other modules.

`SQLiteHandle` is intentionally an internal `@unchecked Sendable` wrapper so the actor can own and close the SQLite handle under Swift 6 concurrency checking. Do not broaden this escape hatch beyond the persistence internals.

### Application state

`LibraryStore` is `@MainActor` and owns one `MusicDatabase` actor. It creates/migrates the Application Support database on app start, loads albums/locations/box sets, and refreshes after a successful write.

Views must call store use cases; they must not compose SQL or open databases directly.

### Search

Catalogue search now uses the existing FTS5 table as a local index over album titles, edition labels, catalogue numbers, barcodes, aliases, track titles, album/track contributor names, box-set names, and direct/inherited physical-location paths. The index is rebuilt transactionally during migration and after each successful catalogue revision; a normalized phrase-prefix query is combined with the legacy `LIKE ... COLLATE NOCASE` predicates for compatibility. Search remains local/offline and preserves original display text. The current rebuild strategy favors correctness; a future large-library optimization can replace full rebuilds with incremental triggers.

### Locations

Locations are stored as parent links and rendered as a hierarchy with full paths. The Mac UI supports create, rename, move, and delete. A move validates that the target exists and rejects self/descendant cycles. Deletion is guarded when the node has children or is referenced by an album or box set; the user must move those records first. Album and box editors display the full hierarchy path so similarly named shelves remain distinguishable.

### Box sets

Creating a new album inside a selected box set is atomic. Box detail lists ordered members, supports explicit confirmed moves, safe removal, and reordering.

Schema version 2 adds `physical_location_unknown`. Schema version 3 adds `storage_root.bookmark_needs_refresh`. A boxed album has no direct location and this flag is false; a standalone CD with an unknown location has this flag true. Preserve this distinction and add future changes through migrations.

### Album detail and editing

Album edits and box membership workflows are available. Album detail supports manual content entry, alias removal, track removal, track-level credit creation/removal/editing, disc reorder/removal, and front-artwork selection. Disc removal requires confirmation and removes only its catalogue tracks; it cannot bypass a protected digital asset and never removes a source file. Its Edit Track sheet corrects title, display position, duration, work, movement number/name, and instrumental state; it is explicitly catalogue-only and never rewrites audio tags. Removing a credit preserves its contributor record for other credits; editing a contributor name changes the shared catalogue person everywhere it is credited, while **Edit credited name** changes only that album or track credit. That sheet also edits the credit's role; a role change keeps the contributor and displayed name but appends the credit to the selected role's ordered list.
Album-detail track and disc removal now require explicit confirmation, and removal/reorder actions surface failures through the app error alert rather than silently ignoring them.
The add-disc, add-track, add-alias, add-credit, and add-to-playlist actions use the same rule: on failure they keep the current UI open where applicable and surface the error.
Selecting a music folder for a new storage root also surfaces authorization/addition failures through the shared app alert.
Creating a playlist, renaming a storage root, and starting an import scan now follow the same visible-error rule. Import Inbox retry, embedded-metadata analysis, proposal approval/dismissal, final catalogue-record creation, and detail reloads do too; the view reloads or dismisses only after a successful action, and a failed reload retains previously displayed candidates/proposals.
Selecting a snapshot/NAS destination follows the same visible-error rule. Contributor and album-detail reads, box-placement reads, and local playback setup also report failures instead of quietly displaying incomplete information or doing nothing.
The macOS sidebar includes a Contributors section, backed by a deterministic name/sort-name query and local name/sort-name search. Selecting a contributor lists all active albums where they hold either an album or track credit; selecting one of those rows opens its normal album detail. Contributor corrections remain available through existing album/track credit editing.
Settings now includes **Recent Catalogue Activity**. `MusicDatabase.incrementRevision()` records one catalogue-revision marker in the same transaction as every successful catalogue revision. Album edits, track edits, artwork add/migrate operations, playlist name/lifecycle edits, playlist membership/reordering, and album-alias add/remove operations additionally record one `edit_event` row per changed field with the entity, field name, old value, new value, and source. The Settings view renders field diffs as `old → new` beside their revision and time; older operations remain marker-only. This is an audit history, not undo/replay, and it does not reconstruct activity that predates the current database rows. Field rows reuse schema version 16 and the marker's strictly increasing millisecond timestamp, so the read-only snapshot schema remains compatible.

### Digital media

Storage-root authorization, Import Inbox scanning, embedded common-tag proposal review, confirmed digital assets, basic Library Health, local Mac playback, playlists, and explicit SHA-256 duplicate diagnostics are implemented. Fingerprint verification is user-triggered. A stored relink proposal can be applied only after a Mac confirmation: it changes the catalogue's root-relative path and removes the proposal; it never moves, renames, or otherwise changes an audio file. A missing-file rescan review can now create that proposal through **Choose Replacement File…**: the selected regular audio/DSF file must be inside the asset's same available registered root, and its derived relative path is saved for Settings review without changing the live asset path. `PlaybackController` now turns failed resume/previous/next AVFoundation opens into a stopped **Playback unavailable** state and the Mac shell presents its local error alert; it does not mutate catalogue data or silently retain a playing state. It now registers standard macOS media-key/Now Playing controls and displays the source container plus decoded runtime sample rate and channel count in the playback bar; it does not claim an original bit depth or actual DAC output format that `AVAudioPlayer` cannot prove.

### Read-only companion foundation

`SnapshotClient` reads a published directory supplied by its host, verifies its JSON manifest and payload checksum, and maintains a local cache. `localCatalogue()` validates the cached payload checksum again before decoding it. `SnapshotSourceStore` persists a security-scoped selected source, and `SMBRootMappingStore` remains a separate device-local JSON preference store. `ReadOnlyDigitalAsset.resolve(using:)` only joins a safe relative path to a matching device-local mapped root; it refuses absolute/traversal paths and never falls back to a Mac path. `CompanionPlaybackController` checks for a resolved mapped URL and local file existence before using `AVAudioPlayer`; its transport state is device-local and it never mutates catalogue/mapping data. `MusicLibraryPadApp` is the SwiftUI composition target. `PadLibraryView` checks a selected manifest's modification date at launch and whenever its scene becomes active, displays a non-blocking update-available indicator, shows when the local verified cache was last refreshed, and retains the existing cache until an explicit refresh. Run `xcodegen generate`, open `MusicLibraryPad.xcodeproj`, select a Development Team, then build the `MusicLibraryPad` scheme. An unsigned iOS Simulator build was verified with `xcodebuild` on 22 July 2026.

`CompanionPreferenceStore` writes `CompanionPreferences.json` under iPad Application Support. It holds published album IDs starred by the user plus up to 20 recently played album IDs in newest-first order, album playback-start counts, and elapsed seconds keyed by published track ID. The iPad album detail toggles favourites, album rows show a star and local play count, a **Favourites only** filter narrows local browsing, and starting playback of a different album's track records that album and increments its count. This is a local playback-start count, not proof that an album was listened to fully. The history respects the current search/favourites filter and has a local **Clear** action; clearing it leaves favourites and counts unchanged. Pausing or switching away from a track stores its current elapsed seconds, and the iPad scene also stores the active track position when leaving the active state. Replaying that same mapped track restores it unless it is within three seconds of the track end. This data is intentionally outside the verified snapshot cache and Mac master: it is never published, uploaded, merged, or treated as catalogue data. Snapshot refresh preserves it; IDs that are absent from a newer snapshot simply do not appear until/if that album returns. It is not yet per-track history, a shared play count, or cross-device resume.

`Scripts/package-mac-app.sh` produces a sequentially versioned, locally ad-hoc-signed release app (currently `build/Music Library 0.9.app`); its committed bundle metadata is in `Packaging/MusicLibraryMac-Info.plist`. The stable installed copy is `/Applications/Music Library.app`. This is suitable for local launch on this Mac, not public distribution or notarization. `MAC_AND_NAS_TESTING.md` is the step-by-step Mac/NAS/iPad real-world acceptance guide. It isolates destructive/corrupt-snapshot checks to a disposable copy and states the expected safe outcomes.

`USER_TEST_FEEDBACK.md` records the 26 July first Mac/NAS smoke-test findings and follow-up checks. The import fallback now safely interprets conventional `Artist/Album [Disc 1]/01 Track.flac` paths when tags are missing; it takes effect only when metadata is read for a future import proposal and never rewrites existing catalogue records or source files. The Mac player now reorders the actual playback items when shuffle is enabled, visibly labels that state, and rehydrates reachable saved queue tracks after relaunch without autoplaying. The MusicBrainz lookup sheet's earlier clipped-layout issue is repaired; proposal rows now use a three-column artwork, metadata, and actions layout.

Settings → Recently Deleted now also exposes **Permanently Remove…** for a soft-deleted album. It requires a confirmation, removes its catalogue tracks and registered asset paths so a corrected re-import can use those paths, and does not delete or alter any source media file. It refuses records still owned by a box set or referenced from a playlist.

`PlaybackController` now best-effort preloads one next queued file on a dedicated background queue while the current track plays. It never reads or caches a whole music folder; it reuses a prepared `AVAudioPlayer` only when the queue has not changed, otherwise it discards it and safely falls back to opening the selected file. This is intended to reduce SMB next-track startup delay and needs real NAS measurement.

**DSF playback decision and implementation (28 July 2026):** DSF is explicitly recognised by import scanning even when macOS does not identify it as a standard audio UTI. `DSFMetadataReader` reads the DSF header (one-bit stream properties) and optional trailing ID3v2 tags. Mac playback preserves the original DSF and uses `DSFPCMTranscoder` to create a private Cache-directory 24-bit PCM WAV at a high PCM rate (normally 176.4 kHz); the derived cache may be deleted/recreated at any time and source DSF is never changed. DSF preparation can be noticeably slower than ordinary playback on a first play because conversion is local and intentional. Native DSD/DoP output is **not** implemented: it is a future hardware-specific feature that must enumerate and verify the active DAC/driver/output-path capability instead of claiming bit-perfect output from the source extension alone.

The iPad library view has a **This iPad** section with counts for favourites, recently played albums, albums with local play counts, and saved track positions. Its explanatory text makes the ownership boundary visible: these preference and activity values remain only on that iPad and are never sent to the Mac catalogue.

The iPad toolbar also provides **Local data → Clear Local Playback Activity…** with a destructive confirmation. It clears Recently Played, local playback-start counts, and saved resume positions on that iPad only. It deliberately retains favourites, the verified snapshot cache, source choice, and SMB mappings.

**Local data → Clear Local Favourites…** is a separate destructive confirmed action. It removes only the iPad's starred album IDs and turns off the Favourites-only filter; it retains local playback activity, snapshots, source choice, and SMB mappings.

When local Recently Played albums are visible in the iPad catalogue, they appear first under **Recently played**. The remaining matching records appear under **All albums**, so the same album is not immediately duplicated; both slices obey the active search and Favourites-only filter.

## 10. Non-negotiable invariants to preserve

Enforce these with transactions, validation, constraints, and tests where possible:

1. An album belongs to zero or one box set.
2. A boxed album has CD availability and no direct physical location.
3. A standalone CD album has a direct location or an explicit unknown-location state.
4. A box set always has a location.
5. Box positions are unique within a box; disc and track positions are unique within their parent.
6. A digital asset belongs to one track in version 1.
7. Digital availability is derived; never add a stale stored `hasDigital` Boolean.
8. A failed import/box assignment/write operation must not leave partial catalogue changes.
9. Catalogue revision increments once per committed user operation, never per individual SQL statement.
10. Metadata imports do not rewrite original audio files.
11. Soft-deleted records must be excluded from normal search but retain restoration relationships when deletion is implemented.
12. Companion clients never upload catalogue edits.

If an invariant needs to change, stop and document the proposed migration and user-facing impact before implementing it.

## 11. Current recovery and backup workflow; next safe slice

The Mac now persists the latest publication failure, shows it in Settings after relaunch, and changes the manual action to Retry Publish. Settings also provides a safe Library Health recheck: it refreshes root authorization and, for reachable authorized roots, checks each stored relative path to mark an asset available or missing. This never modifies media files or stored paths, and availability refreshes do not increment catalogue revision.
Each Library Health issue has a **Show Album** action, which changes the Mac shell to Albums and selects the affected record; the health list is therefore a repair starting point rather than a dead-end report. Missing-front-artwork rows use a dedicated photo warning and direct the user to the Album Detail artwork picker; deleted albums are excluded. Rows sort case-insensitively by album title, then by repair priority (missing file, offline, partial, duplicate, missing artwork), with album ID as a final stable tie-breaker.
The Mac Settings view always shows a **Library Health** section. When no current repair items are detected, it displays an explicit green confirmation instead of hiding the section; this does not claim that an unscanned/offline folder is healthy beyond the last check.
Settings also has an **Import Inbox Attention** section for batches that failed, were cancelled, or recorded file-level scan errors. **Review Import** changes the sidebar to Import Inbox and selects the exact batch, where existing retry/review controls remain explicit; it never retries, discards, or changes candidates automatically.
The Settings **No music folders** empty state is now contained inside the Music Folders section. It no longer overlays the full Settings view, so snapshot setup, backup/restore, export, Library Health, Import Inbox Attention, and activity history remain available before a storage root is configured.
Health-panel actions (recheck, fingerprint verification, root access/removal, relink apply/discard, and manual publishing) surface an app error alert if they fail; they do not silently absorb an error.
**Metadata correction decision (23 July 2026):** Japanese CD rip tags may legitimately be correct for a Japanese pressing but unsuitable for this user's preferred catalogue display. The Mac catalogue must support corrections to album title, track title, and contributor names without writing into source audio files. File tag write-back is deferred and, if added, must be opt-in with a field-by-field preview and recoverable backup.
**Companion preference decision (23 July 2026):** iPad/read-only clients may maintain device-local favourites, recent-play history, play counts, and resume positions. They do not change or sync into the Mac catalogue in version 1; shared playlists remain Mac-authored and companion read-only.
**Physical location decision (23 July 2026):** a CD-bearing album may intentionally have an unknown physical location. Use the explicit `locationUnknown` state and display “Unknown location”; do not overload an empty field, which would be ambiguous with a digital-only album or incomplete entry.
**Rating decision (23 July 2026):** catalogue ratings use a shared 1–5 star scale for albums and tracks. Deliver album ratings first; use the same scale for tracks when that UI is added. Ratings are Mac-authored/published catalogue data, unlike device-local companion favourites and play history.
Schema 10 now delivers the track half of that decision: each track has an optional 1–5 rating, editable in the catalogue-only Edit Track sheet and displayed beside its title. The sanitized read-only snapshot track payload also carries the optional rating.
The iPad read-only album detail renders that published track rating beside the track title; it remains display-only. Album ratings are likewise published and shown on iPad album rows/details.
**Backup and rollback decision (23 July 2026):** NAS-published snapshots are read-only iPad distribution/rollback artefacts, not direct backups of the live Mac master. Before tag write-back, implement explicit dated, checksummed master SQLite backups to the NAS and a verified restore workflow that retains the current master as a recovery copy. Create a backup before risky operations (especially tag write-back) and daily only after catalogue changes; retain 7 daily and 12 monthly master backups. Do not present snapshot import as normal master restoration.
The persistence layer creates a consistent standalone SQLite backup through SQLite's online-backup API and verifies its integrity while the live catalogue remains open. In Settings, **Back Up Master Database** stores a timestamped `.sqlite` file and SHA-256 `.manifest.json` under the selected snapshot/NAS destination's `MasterBackups` folder. Retention keeps the newest manifest-backed backup for each of the seven most recent days and twelve most recent months. A changed catalogue also creates at most one automatic backup on a day after a destination has been configured. **Restore Master Backup…** asks the user to select a backup manifest, verifies both checksum and SQLite integrity, checkpoints the live WAL, moves the current master into `~/Library/Application Support/MusicLibrary/Recovery`, then replaces and reopens it. A failed replacement attempts to restore the recovery copy. This remains the lightweight SQLite-only scheduled backup; **Complete Catalogue Archive** is the portable database-plus-managed-artwork workflow. Tag-write backups and source audio remain outside both formats.
**Snapshot publication decision (23 July 2026):** retain the current published snapshot plus three prior revisions (four revision payloads total), and automatically publish five seconds after the final catalogue change. Manual Publish Now remains immediate.
**External metadata decision (23 July 2026):** external metadata lookup is manually triggered only in version 1. Scanning/import never contacts a provider automatically, and every returned value remains a preview until the user explicitly accepts it into the catalogue.
The MusicBrainz adapter is available from each Import Inbox release proposal's **Search MusicBrainz…** button. It sends only the user-visible title and optional artist text after the user presses **Search MusicBrainz**, uses an identifiable User-Agent and a one-request-per-second request gate, and displays title/artist/date/country/catalogue-number/disc-count results in a preview sheet. It does not upload audio, alter catalogue data directly, or modify source files.
Selected MusicBrainz results are now persisted in schema 8 against their import proposal. **Use for Field Comparison** stores the chosen release; **Review MusicBrainz Fields…** provides independent title, artist, and disc-count toggles. Applying only updates the import proposal and appends `musicbrainz` provenance; catalogue records are still created only through the existing explicit approval and confirmation workflow. No source tag is changed.
The lookup provider keeps a session-only in-memory cache keyed by normalized title/artist, so repeating the same manual search reuses the prior response without another request. Temporary 429/5xx service responses and URL-loading failures retry at most twice with bounded delay; malformed/non-transient responses fail immediately. The cache does not persist search data across app relaunch, and no lookup occurs without an explicit Search action.
Schema 9 extends the selected external result and review sheet with country/region and catalogue number. Each is an independent toggle, and only accepted fields become part of the pending import proposal. When the existing approval/create action finally creates an album, it maps these accepted values into that album's country code and catalogue number; it still never edits source audio files.
**Artwork storage decision (23 July 2026, migration follow-through 10 August 2026):** new selected artwork is copied into managed catalogue storage, making it resilient to moved source folders and eligible for master backups and later iPad publication. Album Detail now offers an explicit **Make Portable** action for legacy path-only artwork outside managed storage. It verifies the source and copies before updating the existing artwork row; a failed database update removes only the newly copied managed file, while the original remains untouched. Managed artwork is shown as already portable, and missing legacy paths are reported without changing the row.
**Online lookup/privacy decision (23 July 2026):** textual metadata lookup runs only after an explicit user action. Scanning never contacts the internet automatically; source audio files are never uploaded by default. Any future acoustic fingerprint lookup is disabled by default and requires a clearly labelled user action plus approval before sending a derived fingerprint to a provider.
Playlists now have persistent rename and soft-delete operations, exposed from the playlist list's context menu. These operations increment the catalogue revision and are reflected in the next published snapshot.
Settings now also lists **Recently Deleted Playlists**. Restore returns the playlist and its existing ordered items, without touching tracks or media files.
An empty box set can also be moved to Recently Deleted and restored in Settings. The database refuses to delete a non-empty box set, so a visible album never loses its inherited physical placement; no media file is touched.
Playlist detail now supports moving an item earlier/later and removing it. The persistence layer renumbers its ordered items safely inside one transaction and increments the catalogue revision once per user action.
The Mac playlist detail has a Play action. It resolves saved items in playlist order and skips files that are currently unavailable; if none can be resolved it shows an error instead of replacing the current queue.
Possible duplicate assets are shown in Settings by shared verified content hash and path list. This is review-only: no duplicate is removed, moved, or relinked automatically.
Stored relink proposals are visible with before/after relative paths. The Mac requires an explicit confirmation before applying one, and also provides a discard action; both are database-only operations. Applying updates the stored path and revision; discarding leaves the asset and revision unchanged. Neither moves or renames media. A missing-file review may now create a proposal from a system-picked replacement file; it validates that the file is a readable regular audio/DSF file inside the asset's same registered available root. Automatic hash/signature discovery of candidates remains intentionally unimplemented, so no relink is proposed merely from a scan.
The macOS Import Inbox view was refactored into small row/summary helpers and now uses the current SwiftUI confirmation-dialog API. This prevents the compiler type-check failures previously seen when launching `swift run MusicLibraryMac`.
**Mac local/NAS library scope (29 July 2026):** `storage_root` schema version 15 adds a persistent `scope`: **This Mac only** or **NAS / iPad music**. Existing mounted `/Volumes/...` roots migrate to NAS / iPad music; other existing roots migrate to This Mac only, and the user can correct either classification in Settings. The Mac Albums toolbar has All Music, NAS / iPad Music, and This Mac Only filters. Albums with assets in both folders appear under both relevant filters. A published snapshot now selects only albums/assets from NAS / iPad roots; full Mac JSON/CSV exports remain intentionally complete. Settings exposes each folder's scope and an explicit **Rescan** action. The sidebar's former Import Inbox is now **Library Changes** and shows only the latest scan for each root rather than an unbounded duplicate path history; old batches remain in SQLite for traceability. `swift test` passed all 62 tests after this change.
**Safe rescan reconciliation (29 July 2026):** schema version 16 adds `root_scan_missing_asset`, a review-only association between a completed scan batch and assets whose root-relative paths were not found by that scan. `LibraryStore.startImportScan` creates this review only after a completed scan of an available root; unavailable/offline roots are never reconciled. Library Changes displays each candidate with its album, track, and root-relative path. **Mark Asset Missing** requires a destructive confirmation, changes only `digital_asset.availability` to `missing`, and clears that single review entry. It does not delete the track, album, catalogue history, or source file. The focused persistence test proves that an asset is retained until confirmation and remains retained afterward as a missing reference. `swift test` passes all 63 tests.
**Child-folder import (29 July 2026):** the Library Changes folder picker now includes **Scan Album Folder…**. The picked folder must be inside one registered available storage root; the store selects the deepest matching root and rejects unrelated folders. `ImportCandidatePayload.prefixed(relativeDirectory:)` turns scanner-relative paths back into registered-root-relative paths, preserving CUE timing/track fields. A child scan never performs missing-file reconciliation, because it deliberately sees only part of the root. Retrying a child batch uses its stored source folder rather than escalating to a full-root scan. `swift test` passes all 64 tests.
**Reviewed missing-reference cleanup (30 July 2026):** a missing-file review now has two deliberate catalogue-only outcomes. **Mark Catalogue Asset Missing** preserves the `digital_asset` record and marks its availability missing. **Remove Asset Reference** permanently deletes only the reviewed `digital_asset` row, after confirmation; SQLite cascades its temporary review row. It does not delete the track, album, contributor, playlist item, or source media file. The removal method requires a current completed-scan review row, so it cannot be called for arbitrary existing assets. The focused persistence test proves the asset reference disappears while its track remains. `swift test` passes all 65 tests.
**Manual replacement-file relink proposal (30 July 2026):** each current missing-file review now also provides **Choose Replacement File…**. The system picker returns a URL which `LibraryStore.proposeRelink` checks is a regular audio (or DSF) file beneath the same available bookmarked storage root. It derives the registered-root-relative path and stores an `asset_relink_proposal`; it never changes the live asset path, moves/renames/copies the selected media, or modifies tags. Settings remains the only place to explicitly apply or discard the proposal. The persistence layer now returns the existing proposal ID for an identical repeated proposal instead of returning a fabricated ID after SQLite's unique constraint ignored the duplicate. The existing relink test covers that deduplication; `swift test` passes all 65 tests.
**Rescan attention and relink verification (30 July 2026):** Library Changes now calculates **New audio files** by comparing each candidate's root-relative path with registered `digital_asset` paths under that same root; all scanned candidates remain behind an expandable diagnostic section. **Read Metadata for New Files** extracts and groups only those unregistered paths, preventing a routine full-root health rescan from creating repeat proposals for already-catalogued albums. Applying a relink proposal now reopens its registered root, verifies that its target is still a regular audio/DSF file, then applies the path and refreshes availability. A stale or non-audio target leaves the catalogue unchanged. The persistence test covers distinction of a known path from one new path; `swift test` passes all 66 tests.

**Scanning completion pass (30 July 2026):** `ImportScanner` now reports item-count, audio-count, and current-path progress during the recursive walk. The Mac holds this information only while a batch is actively scanning, then clears it after recording the terminal result, preventing stale progress from a finished/cancelled run. Library Changes distinguishes actual audio candidates from file-level failures, exposes every retained scan error, and gives each completed scan an explicit outcome: no supported audio, no catalogue changes, or the exact reviewed new/missing counts. This makes the intended workflow unambiguous: **Rescan** discovers paths and reconciliation only; **Read Metadata for New Files** is required only when the scan actually lists new, unregistered audio. The focused progress test increases the full suite to 67 tests.

**Library Changes refresh and proposal grouping correction (1 August 2026):** a retry now returns the newly created audit-batch ID, and the Mac selects that fresh batch immediately. Its detail view reloads whenever the batch status or recorded counts change, so the completed rescan result appears without manually selecting the same registered folder again. Metadata proposal identity now normalizes Unicode composition, collapses harmless whitespace, and ignores letter case for grouping only; the first source spelling is preserved for display and later review. If an otherwise matching album folder has a clear multi-track artist majority but exactly one track lacks `ALBUMARTIST` and has a divergent `ARTIST`, that one outlier joins the majority proposal; this covers a ripper writing a track/title-like value into `ARTIST` for one file. Same-titled albums in separate folders, and separate local/NAS registered roots, remain separate. No catalogue record, file path, or audio tag is changed by either correction. `swift test` passes all 72 tests.
**Mac lyrics editor layout (2 August 2026):** `LyricsEditor` no longer uses a `Form` for the editable lyrics content, avoiding the form label-column clipping seen in the modal. It now uses a scrollable `VStack`/`GroupBox` layout, a large bordered multiline `TextEditor` for manual plain/LRC text, bounded scrollable previews for saved lyrics, and a larger resizable sheet frame (minimum 760 × 700). Storage remains manual SQLite text with no provider/network or tag write-back behavior changed. `swift test` passes all 72 tests.
**Release proposal artwork layout (2 August 2026):** Mac Library Changes now loads each proposal's imported folder artwork from the existing proposal preview and presents it in a fixed left column. The middle column shows album title, artist, provenance, confidence/file summary, and creation status. The right column keeps Search MusicBrainz… plus the state-appropriate review, approve, dismiss, and create actions aligned at the trailing edge; proposed rows retain the expected Search, Approve, and Dismiss action set. This changes presentation only and does not alter proposal persistence or approval semantics. `swift test` and `swift build` pass all 72 tests.
**Explicit combined rescan and metadata action (2 August 2026):** Library Changes keeps the fast **Retry Scan** reconciliation action and the separate **Read Metadata for New Files** action, and now also offers **Rescan and Read Metadata for New Files**. The combined action starts a new audit batch, selects it immediately, waits for that batch to reach a completed state, and then invokes the existing new-file-only metadata pass exactly once. It never reads metadata during an ordinary rescan, never analyzes a failed/cancelled scan, and remains a no-op for a completed scan with no unregistered paths. This is intentionally explicit rather than changing the meaning of the existing Rescan button. `swift test` and `swift build` pass all 72 tests.
**Library management enhancements (3 August 2026):** Catalogue search now populates and uses the existing FTS5 index. It covers album/edition text, catalogue numbers and barcodes, aliases, track titles, contributor names, box-set titles, and direct/inherited location paths; writes rebuild it transactionally and retain the prior LIKE fallback. Physical locations now render as a hierarchy and support safe move/delete operations. Moves reject self/descendant cycles, while deletes explain and block remaining child, album, or box-set references. The location picker uses the full hierarchy path throughout the Mac editors. Added persistence coverage for safe moves and guarded deletion. `swift test` passes all 73 tests and `swift build` passes.
**Managed artwork migration (10 August 2026):** `ManagedArtworkStore.contains` now recognizes only paths inside the managed directory boundary, including symlink-resolved paths. `MusicDatabase.migrateAlbumArtwork` updates an existing album artwork row transactionally while preserving its identity and selected state. `LibraryStore.migrateArtworkToManagedStorage` verifies a legacy source, copies it into managed storage, updates the row only after the copy succeeds, removes the new copy on database failure, and never modifies/deletes the original. Album Detail exposes **Make Portable** only for path-only legacy artwork and labels migrated rows **Managed**. The focused persistence test covers path/source/selection preservation; `swift test` passes all 74 tests and `swift build` passes.
**Field-level catalogue activity history (11 August 2026):** `CatalogueActivity` now carries entity/field/old/new/source data while retaining the existing revision-marker shape. `MusicDatabase.incrementRevision(changes:)` writes marker and field rows atomically; album edits, track edits, and artwork add/migrate paths supply changed-field rows, while unrelated operations continue to write marker-only history. Activity timestamps are made strictly increasing per revision so rapid edits cannot be attributed to a later revision. Settings renders the previous and new values without changing the schema version or published snapshot contract. Focused persistence assertions cover album, track, and artwork diffs; `swift test` passes all 74 tests and the package build succeeds.
**Playlist and alias activity history (11 August 2026):** the same field-level audit stream now covers playlist creation/rename/soft-delete/restore/permanent removal, playlist-item add/remove/reorder, and album-alias add/remove. Each operation remains transactional and records only catalogue state; playlist ordering and recovery semantics are unchanged. Focused persistence assertions cover names, lifecycle status, membership/positions, and alias fields. The schema remains version 16 and the published snapshot contract is unchanged; `swift test` passes all 74 tests and the package build succeeds.
**Audit hardening — registered-root and CUE containment (12 August 2026):** `RegisteredPathSecurity` centralizes component-aware, symlink-resolved containment and safe root-relative path derivation. Import enumeration now rejects audio entries whose resolved target escapes a registered root; child-folder selection and replacement-file relink use the same boundary check instead of raw string prefixes. CUE `FILE` references reject absolute, parent-directory, and NUL-containing values before resolution, and an escaped reference is retained as a scan error rather than becoming a candidate. Regression coverage includes a parent-directory CUE escape and an audio symlink escape; the full Swift suite passes 76 tests. No media file, catalogue record, or user Application Support database was changed.
**Audit hardening — backup and snapshot safety (12 August 2026):** master-backup manifests now accept only canonical revisioned SQLite filenames and restore/retention resolve them through the registered-root boundary helper; traversal or non-canonical names are rejected before file access. Snapshot publishing refuses conflicting content for an existing revision, writes the new manifest through a temporary replacement, and preserves the prior manifest on replacement failure. The read-only client accepts only canonical `catalogue-<revision>.json` payload names, validates the remote checksum before cache mutation, and stages payload/manifest updates so the last verified pair remains usable if a later step fails. Regression coverage includes unsafe master names, conflicting revisions, unsafe snapshot names, and checksum fallback; the full Swift suite passes 79 tests. No media file, catalogue record, or user Application Support database was changed.

**Audit hardening — DSF/WAV container validation (12 August 2026):** `DSFMetadataReader` now uses checked arithmetic for format/data offsets, validates the `data` chunk identifier and declared payload against the actual file, rejects impossible sample/metadata offsets before reads, and bounds ID3 inspection to a valid trailing region. DSF duration calculation, PCM buffer sizing, output-byte accumulation, and generated WAV header fields now reject integer overflow or values outside the WAV format limits. Regression coverage includes overflowing format declarations, truncated/undersized data declarations, invalid metadata offsets, overflow-safe duration handling, and the existing DSF scan/playback fixtures; the focused Import Scanner suite passes 24 tests. No source audio or catalogue data was changed.

**Audit hardening — bulk playback repeated-work cleanup (12 August 2026):** `LibraryStore` now refreshes registered storage-root access once before resolving a disc, playlist, or explicit track-ID playback list, then resolves each `PlaybackAssetReference` against the already refreshed root state. A single-track lookup keeps the existing refresh and availability checks. Root access refresh now reloads the catalogue only when a root status/bookmark/path actually changed; unchanged playback requests no longer trigger a full `reload()` per track. The persistence suite passes 34 tests and the full Swift suite passes 80 tests. No playback ordering, availability, relink, or source-file semantics changed.

**Audit hardening — chunked background fingerprinting (12 August 2026):** explicit asset fingerprint verification now builds safe jobs from the current available registered roots, hashes source files in 1 MiB chunks on a utility detached task, and writes the same SHA-256/content-size signatures back only after hashing completes. It no longer loads an entire audio file into main-actor memory or blocks the Mac UI while hashing; security-scoped access is held for the registered root during each background job. A 2 MiB+ regression fixture verifies the digest, quick signature, and byte-for-byte source preservation; the full Swift suite passes 81 tests. No source audio or catalogue data is changed until the existing fingerprint database update step.
**Audit hardening — startup and scheduled-work reliability (12 August 2026):** `LibraryStore.start()` now uses a small retryable gate: concurrent initialization attempts are ignored, a successful initialization remains one-shot, and a failed initialization clears the gate so a later launch/retry can try again. Snapshot publication and master-backup file operations now run in utility detached tasks while database/status coordination remains on the main actor. Daily master-backup scheduling coalesces repeated reloads for the same revision, so a slow backup cannot create duplicate same-day archives. The focused import/snapshot suite passes 24 tests and the full Swift suite passes 82 tests. No source audio, catalogue data, or user Application Support database was changed by the test run.
**Audit hardening — bounded metadata and artwork requests (12 August 2026):** explicit MusicBrainz searches, release-detail requests, and cover-art downloads now use one shared 30-second `URLRequest` timeout. This keeps user-triggered lookups bounded when a NAS/VPN or external service is unavailable, while preserving the rule that no audio is uploaded and no catalogue/source file is changed by lookup or artwork download. A focused timeout regression and the full Swift suite pass 83 tests.
**Audit hardening — grouped Library Health root access (12 August 2026):** the available-asset health pass now groups candidates by registered storage-root ID, resolves each bookmark once, and holds that root's security-scoped access for the whole group. It still checks every stored relative path and writes the same availability result, but avoids reopening the same NAS/local root once per track. The full Swift suite passes 83 tests; no catalogue or source-file semantics changed.
**Audit hardening — fail-closed security-scoped operations (12 August 2026):** user-selected artwork, legacy artwork migration, snapshot publication, master-backup creation/restoration, and registered-folder bookmark creation now stop before filesystem or database work when macOS denies the security-scoped resource. Previously these paths could continue after a denied scope and report a later, less actionable filesystem error. The full Swift suite passes 83 tests; no catalogue, source audio, or backup data was changed by the test run.
**Audit exit preparation — generated-project synchronization (12 August 2026):** `xcodegen generate` restored the existing `CompanionPreferences.swift` source reference in `MusicLibraryPad.xcodeproj`, which had drifted from `project.yml`. `xcodebuild -project MusicLibraryPad.xcodeproj -list` now reports the expected `MusicLibraryPad`, `MusicLibraryPadShell`, and `MusicReadOnlyClient` targets and schemes. This is project bookkeeping only; no UI redesign or catalogue behavior changed.

**Audit exit verification (12 August 2026):** the complete debug and release Swift suites pass (83 tests in 8 suites), the release Swift package build passes, `xcodegen generate` is clean, `xcodebuild -project MusicLibraryPad.xcodeproj -list` reports the expected targets and schemes, a real Release iOS Simulator Xcode build succeeds, the Mac app packaging script succeeds, and `git diff --check` is clean. The final local error-path review found no new correctness issue: remaining best-effort `try?` uses are limited to cleanup, optional metadata/artwork fallbacks, or local UI-state persistence; the constant MusicBrainz URL construction does not depend on user input. The known AVFoundation `stringValue` deprecation is non-blocking and deferred as maintenance. No catalogue, source-media, or user Application Support data was changed, and no visual redesign work started.
**Import robustness correction (28 July 2026):** an approved release proposal could fail with SQLite `UNIQUE constraint failed: track.disc_id, track.number` when multiple audio files carried the same embedded track number (or number zero). The entire proposal was already transactional, so no partial catalogue album was committed; however, the raw error prevented the intended album from appearing. `MusicDatabase.confirmImportReleaseProposal` now preserves positive unique embedded positions and assigns the next free catalogue position for duplicate/invalid values. The focused persistence test imports duplicated `1` tags plus a `0` tag and verifies one album with tracks 1, 2, and 3. `swift test` passes (58 tests), and the rebuilt app was installed/relaunched from `/Applications/Music Library.app`. Source audio files and the Application Support catalogue database were not modified by the update.

### Goal

Automatic publication is already observable and bounded; do not regress it while working on the next capability.

### 12 August 2026 visual review checkpoint

The user requested an internet-informed UI review before more feature work. The review compared the current Mac surfaces with Apple macOS HIG patterns, Apple Music's MiniPlayer, Roon album/queue/identification flows, and MusicBrainz Picard's candidate and metadata comparison layout. The product direction is now fixed in `BUILD_PLAN.md`: artwork-first library browsing, compact source/edition/health badges, progressive disclosure for raw metadata, a resizable MusicBrainz comparison workspace, and an artwork-led persistent player. No source code, schema, catalogue data, or application-support database was changed in this documentation checkpoint.

### 12 August 2026 audit and hardening gate

Before starting the visual implementation workstream, the existing Mac catalogue/player was audited for correctness, performance, resilience, and security. The baseline is healthy (`swift test` 74 tests, debug/release package builds, `xcodebuild -project MusicLibraryPad.xcodeproj -list`, `git diff --check`), and no source audio or user catalogue data was changed by the audit. The review nevertheless identified hardening work that must precede UI redesign:

- Registered-root, child-folder, relink, and CUE paths need component-aware containment after symlink resolution; simple string-prefix checks and arbitrary CUE `FILE` values are not sufficient.
- Master-backup restore must reject manifest path traversal. Snapshot publication/cache replacement must not remove the last good manifest before a replacement is verified.
- DSF/WAV header arithmetic and allocation sizes need overflow/truncation checks before playback or catalogue inspection.
- Full-file fingerprinting, asset verification, and other avoidable I/O currently run on the Mac main actor; startup retry, scheduled backup duplication, URL/database waits, and swallowed errors also need reliability cleanup.

The execution order is now one tested slice at a time: (1) path/CUE containment, (2) backup/snapshot validation and atomicity, (3) DSF/WAV validation, (4) main-actor/performance and reliability cleanup, then (5) full validation, documentation, commit, and push. The visual foundation, Albums source filter, grid/list presentation, and other artwork-first UI work must not begin until the hardening exit criteria are met. No duplicate handoff file is to be created; this file remains the canonical continuation document.

### Audit hardening exit (12 August 2026)

All implementation slices and release/exit verification in the pre-UI audit are complete: path/CUE containment, backup and snapshot safety, DSF/WAV validation, playback/fingerprint/startup reliability, bounded network requests, grouped Library Health access, fail-closed security-scoped operations, generated-project synchronization, full Swift debug/release validation, Mac packaging, and a real Release iOS Simulator build. The visual redesign has not started, and no catalogue or source-media data was changed by this audit.

### Existing-edition import attachment (23 August 2026)

The first post-audit workflow gap is implemented across `MusicDomain`, `MusicPersistence`, `MusicApplication`, and the Mac app. A proposed Library Changes release now has direct **Create New Edition**, **Attach to Existing Edition**, and **Dismiss** actions; there is no redundant **Approve for Later** step. Legacy approved rows remain accepted. The creation or attachment transaction records approval and the selected catalogue result together. The attachment sheet searches active catalogue editions and displays an explicit imported-file-to-catalogue-track preview. Populated targets require an exact disc set and per-disc track count; empty targets can receive the imported structure. Catalogue titles, credits, artwork, and edition metadata are never overwritten. Root-relative asset paths are checked for reuse and every condition is revalidated inside the attachment transaction. Repeating the same attachment is idempotent; mismatch tests verify atomic rollback and no revision. `swift test` passes 87 tests in 8 suites. No user Application Support catalogue or source media was touched by development validation.

### 23 August 2026 icon and responsive playback checkpoint

The Mac release is now bundle version 0.2 (build 2) and uses the repository-owned `Packaging/AppIcon-1024.png` source plus `Packaging/AppIcon.icns`. `Scripts/package-mac-app.sh` copies the icon into `Contents/Resources`; the resulting `build/Music Library.app` passes plist, icon-dimension, and code-signature verification. The icon intentionally combines a vinyl record, compact disc, archive card, and waveform to represent a catalogue and player without imitating another product's mark.

`PlaybackController` no longer performs slow network opens, DSF-to-PCM conversion, `AVAudioPlayer` construction, or `prepareToPlay()` on the main actor. A serial user-initiated loader performs that work, publishes `isLoading` and `loadingTitle`, and uses a monotonically increasing generation so a superseded NAS request cannot take control later. Selecting a new track stops the old player promptly; the MiniPlayer displays a spinner and `Now Loading “title”…` until preparation succeeds or fails. This improves responsiveness and acknowledgement, not NAS bandwidth or DSF conversion speed. The final release package and full 87-test suite pass.

### 23 August 2026 packaged icon and DSF progress checkpoint

Bundle version 0.3 (build 4) replaces the earlier preview-derived icon with a repository-owned transparent 1024-pixel source and a system-decodable multi-resolution ICNS. `Scripts/prepare-app-icon.swift`, `Scripts/build-app-icon.sh`, and `Scripts/build-icns.swift` make the transformation reproducible without relying on the current macOS `iconutil` encoder, which rejected otherwise valid iconsets. The plist names `AppIcon.icns` explicitly. The packaging script reads the plist version and writes `build/Music Library 0.3.app`; the exact icon is copied into the bundle, the bundle is ad-hoc signed, and the stable installed copy at `/Applications/Music Library.app` was refreshed with Launch Services. Plist linting, embedded-icon checksum comparison, direct AppKit rendering, system ICNS decoding, and strict code-signature verification pass.

First-play DSF conversion now publishes actual input-byte completion from `DSFPCMTranscoder`. The MiniPlayer shows a determinate progress bar, integer percentage, and a smoothed approximate remaining time once enough progress has been observed. At 100% it changes to **DSF conversion complete — preparing playback** while `AVAudioPlayer` opens the derived PCM file. A cached DSF reports completion immediately. Ordinary audio/NAS opening remains indeterminate because `AVAudioPlayer(contentsOf:)` exposes no byte-level load callback. Progress updates are generation-guarded, so a superseded slow request cannot update the newest selection. The monotonic progress regression test is included in the full 87-test suite; the Release package, installed bundle, plist, icon, and signature all pass validation.

### 23 August 2026 DSF playback-cache management checkpoint

`DSFPlaybackCache` owns only replaceable `.wav` conversions inside `~/Library/Caches/MusicLibrary/DSFPlayback`; it neither considers nor removes files outside that directory, symbolic links, hidden/partial conversion files, or any source DSF. `DSFPlaybackCachePreferences` persists a 10 GiB default with a clamped 2–100 GiB range. Cache hits update modification time, which is the LRU signal. A completed DSF conversion trims oldest entries when over budget, opening Settings also reconciles an old oversized cache, and lowering the limit trims immediately. The current playing conversion is excluded from cleanup, and `PlaybackController` prevents new playback from starting during the brief mutating cache operation.

Settings > DSF Playback Cache shows binary-formatted usage, the number of cached conversions, the maximum-size stepper, and a confirmed **Clear DSF Cache** action. Clear removes only unprotected derived conversions; the originals remain untouched and replay regenerates them. The implementation is in `Sources/MusicApplication/DSFPlaybackCache.swift`, `DSFSupport.swift`, `PlaybackController.swift`, and `Sources/MusicLibraryMac/MusicLibraryMacApp.swift`, with isolated-cache LRU, clear/protection, conversion, and preference-range tests in `ImportScannerTests.swift`. Bundle version 0.4 (build 5) is the sequential Mac delivery for this slice.

The rebuilt full Swift baseline passes 90 tests in 8 suites. `Scripts/package-mac-app.sh` produced the signed versioned delivery at `build/Music Library 0.4.app`; its Info.plist reports version 0.4 (build 5), `plutil -lint` passes, and `codesign --verify --deep --strict` succeeds. The same bundle was installed at `/Applications/Music Library.app`; the installed executable and packaged executable have matching SHA-256 digests, the installed artwork digest matches the repository application icon, and the verified installed executable was launched successfully from `/Applications` (PID 71092 during the delivery smoke check).

### 24 August 2026 Mac validation-release checkpoint

The complete debug and release Swift suites were rebuilt on 24 August 2026 and both passed **90 tests in 8 suites**. Release compilation included the Mac, iPad shell, shared UI, persistence, application, and test products; the only compiler diagnostic remains the known non-blocking AVFoundation `AVMetadataItem.stringValue` deprecation in `EmbeddedMetadataExtractor.swift`.

`Packaging/MusicLibraryMac-Info.plist` now advances the user-facing Mac bundle to version **0.5 (build 6)**. The next package is `build/Music Library 0.5.app`; the packaging script must continue to copy `AppIcon.icns`, ad-hoc sign the bundle, and pass plist/signature checks. The stable installed path remains `/Applications/Music Library.app`. This checkpoint changes no catalogue, source audio, snapshot, or user Application Support data.

This is the implementation-to-real-library validation boundary. The next user-run checks are in `MAC_AND_NAS_TESTING.md`: one-click create/attach and duplicate avoidance, local playback and playlist behavior, NAS/DSF loading acknowledgement and latest-selection behavior, offline/reconnect recovery, long-session playback, large-library scroll/search, and VoiceOver/contrast inspection. Report those results before opening another Mac feature slice. Automatic hash-based relinking, snapshot-to-master reconstruction, WAV/DSF/other non-FLAC tag write-back, internet lyrics providers, AI modules, live NAS endurance, and iPad device validation remain explicitly deferred.

### 25 August 2026 physical-only album-entry checkpoint

The Mac Albums toolbar now has a dedicated **Add Physical-only Album** workflow for CDs that are not represented by digital files. The form preselects CD availability, accepts the same edition metadata as a normal album, allows a structured physical location or an explicit **Location unknown for now** state, and stores an optional physical note (for example, shelf or box text). Saving creates one catalogue album with no discs, tracks, or digital-asset rows; its derived digital availability is `none`, so no player controls are shown. The album can be edited later and digital audio can be attached through the existing import flow without changing the physical identity.

The slice adds domain and persistence coverage for known and unknown physical locations. The complete debug and release suites both pass **93 tests in 8 suites**. The known non-blocking compiler diagnostic remains the AVFoundation `AVMetadataItem.stringValue` deprecation in `EmbeddedMetadataExtractor.swift`.

`Packaging/MusicLibraryMac-Info.plist` now reports version **0.6 (build 7)**. `Scripts/package-mac-app.sh` produced and ad-hoc-signed `build/Music Library 0.6.app`; plist linting, embedded icon presence, and strict code-signature verification pass. The package is ready for the user test in `MAC_AND_NAS_TESTING.md` section **A0. Manual physical-only album**. This validation changed no source audio, catalogue database, snapshots, or user Application Support data.

### 29 August 2026 complete manual physical-album checkpoint

The prior split between generic **Add Album** and **Add Physical-only Album** was too easy to misunderstand: the generic form hid location until its CD toggle was enabled and could not link contributors. The Albums toolbar now opens one complete **Add Physical Album** form. It requires a title, at least one named contributor, and an explicit placement choice. Placement can be a direct hierarchical location, an existing box set, or **Unknown**; a new location and parent can be created and selected inline. The form also captures edition label, release/country, label, catalogue number, barcode, remaster year, media format, disc count, physical note, general note, rating, and favourite state. Album editing now preserves correction access to those structured fields and notes.

`NewAlbumContributorCredit` validates manual role links. `MusicDatabase.createAlbum` accepts contributor drafts and writes the album, optional box membership, reused-or-new contributor identities, and ordered role joins in one transaction with one revision. Exact contributor names are reused case-insensitively; invalid contributor or placement data leaves no partial record. `LibraryStore` exposes this atomic workflow and returns newly created physical locations so the editor can select them immediately. Focused tests cover trimming/validation, multi-role linking and reuse, and rollback. Debug and release suites both pass **96 tests in 8 suites**. The known non-blocking AVFoundation `AVMetadataItem.stringValue` deprecation remains unchanged.

`Packaging/MusicLibraryMac-Info.plist` advances to version **0.7 (build 8)** and `MAC_AND_NAS_TESTING.md` A0 now covers contributors, direct/box/unknown placement, inline location creation, search, editability, and the absence of digital playback. The sequential package is `build/Music Library 0.7.app`. This development validation does not open or modify the user's live Application Support catalogue or any source media.

### 30 August 2026 catalogue maintenance and complete-archive checkpoint

Settings now has a distinct **Catalogue Maintenance** section. **Review Safe Cleanup…** previews three narrow categories and lets the user opt each category in or out: superseded terminal import batches (keeping the newest per registered root/source), contributors that have no album or track credit, and physical-location nodes that are not an album/box location or an ancestor of one. Cleanup creates a complete local recovery archive before its single transaction and increments catalogue revision once only when rows are actually removed. It does not remove albums, tracks, playlists, linked people/locations, registered roots, source audio, or artwork in use.

**Export Complete Catalogue Archive…** creates a normal `.musiclibraryarchive` folder containing a consistent SQLite online backup, every file in app-managed Artwork, and a manifest with sizes, SHA-256 checksums, original recorded artwork paths, revision, and date. Verification rejects unsafe names, missing/unexpected files, symlinks, checksum differences, unsupported schema, and failed SQLite integrity. **Restore Complete Catalogue Archive…** stages and verifies before closing the live database, creates a complete pre-restore local archive, keeps a physical rollback database/artwork directory until reopen succeeds, remaps exact historical managed-artwork paths, and restores the rollback on installation failure. Source audio and FLAC tag-write backups are deliberately excluded.

**Reset Catalogue…** is separate from cleanup and requires the exact text `RESET`. It creates a complete local recovery archive first, clears catalogue/import rows and managed artwork, but preserves registered storage roots so local/NAS folders can be rescanned. The operation never deletes or modifies source media. The persistence and archive regression tests cover cleanup boundaries, typed reset/root preservation, complete archive creation/staging, recorded artwork-path mapping, missing managed-artwork refusal, and tamper rejection. The full debug and release baselines pass **101 tests in 9 suites**, and the production build succeeds with only the pre-existing non-blocking `AVMetadataItem.stringValue` deprecation warning. Bundle metadata advances to **0.8 (build 9)**.

`Scripts/package-mac-app.sh` produced and ad-hoc-signed `build/Music Library 0.8.app`. Plist linting, embedded `AppIcon.icns`, and strict deep signature verification pass. The same bundle is installed at `/Applications/Music Library.app`; its Info.plist reports version 0.8 (build 9), and the installed and packaged executables have the same SHA-256 digest. Packaging and validation did not launch the app, open the live catalogue, or modify source audio.

### 22 September 2026 MusicBrainz physical-album prefill checkpoint

The **Add Physical Album** form now has an explicit **Find on MusicBrainz…** action. The lookup sends only the user-entered title and optional artist after the user presses **Search MusicBrainz**. It lists release candidates, loads the selected release details, and shows cover artwork plus the track listing for review. **Use Selected Release** fills the returned title, release year, country/region, record label, catalogue number, barcode, media format, disc count, and primary artist contributor. Existing placement, notes, and additional contributor rows remain under the user's control; the catalogue record is still created only when the user submits the physical-album form. No audio file or source tag is touched.

`ExternalReleasePreview` now decodes the physical-edition fields returned by MusicBrainz. The focused provider regression covers label, barcode, format, release year, and track-list decoding. The rebuilt debug and release suites pass **101 tests in 9 suites**. `Scripts/package-mac-app.sh` produced and ad-hoc-signed `build/Music Library 0.9.app` (build 10); its plist and strict signature checks pass, and the same executable is installed at `/Applications/Music Library.app`. Packaging did not launch the app, open the live catalogue, or modify source media.

### Next safe slice

The local/NAS folder workflow, safe scanning/reconciliation workflow, one-step new-versus-existing-edition import decision, MusicBrainz-assisted and manual physical-album entry, safe catalogue cleanup/reset, portable complete archive/restore, legacy-artwork migration, field-level catalogue activity history, audit hardening, branded Mac packaging, responsive slow-file loading, configurable DSF PCM caching, and the artwork-first Mac presentation workstream are implemented. The next safe boundary is user acceptance of `MAC_AND_NAS_TESTING.md` sections **A0. Manual physical album** and **3.0 Catalogue cleanup and complete archive**, especially MusicBrainz field prefill, export, restore with covers, tamper refusal, and optional reset/root preservation. Do not perform those destructive live-catalogue checks automatically. Automatic hash-based relinking, snapshot-to-master reconstruction, WAV/DSF/other non-FLAC tag write-back, internet lyrics providers, AI modules, live NAS endurance, and iPad device validation remain deferred; the provider/format choices in the Open Decisions section still require the user.

## 13. Planned implementation order after the next slice

Do not implement all of this at once. Complete and test one vertical slice per commit group.

1. Duplicate detection and safe relocation proposals.
5. Digital assets, availability health, duplicate detection, and relocation.
6. Lossless playback engine, queue, and playlists.
7. Library Health, soft delete/recovery, edit history, JSON/CSV export.
8. Phase 4 Mac-first tag write-back and manual lyrics are implemented. FLAC Vorbis comments are the only supported source-file write format: preview, full original backup, temporary replacement, re-read verification, retained JSON journal, and journal-based undo. WAV+CUE, DSF, and all other formats remain catalogue-only. Manual plain/LRC lyrics are stored in SQLite with language, source, and user-edited status; no network lyrics provider is active.
9. Mac snapshot publisher and validation harness.
10. Read-only iPad client, manifest check, snapshot replacement, and SMB root mapping.
11. AI/OCR/music generation last and behind provider protocols.

The detailed acceptance criteria and algorithms for later phases are in `IMPLEMENTATION_SPEC.md`.

## 14. Documentation maintenance policy

After every completed slice, update all applicable documents in the same commit:

- `HANDOFF.md`: current status, tests, limitations, precise next slice, known issues, and any changed command/environment fact.
- `IMPLEMENTATION_SPEC.md`: implementation status and any architectural/schema/invariant change.
- `BUILD_PLAN.md`: roadmap or user-facing scope changes only.

Do not merely write “implemented X.” State the files/modules affected, tests run, what still does not work, and the next safe starting point. This is what makes a context-recovery handoff useful.

## 15. Session-resume prompt

Use this prompt for a new coding agent:

```text
Resume the Music Library project in /Users/patrickshi/Documents/Codex/Music Library.

Read HANDOFF.md first, then IMPLEMENTATION_SPEC.md and BUILD_PLAN.md. Treat their fixed
decisions and invariants as requirements. Inspect git status and the latest commits before
editing. Run swift test to establish the actual baseline.

Continue only the exact next slice stated in HANDOFF.md. Keep all SQLite operations inside
MusicDatabase, preserve Mac-only catalogue writes, add focused tests, run swift test and Git
whitespace checks, update all handoff/status documentation, commit, and push with normal Git
HTTPS. Do not use gh, destructive Git commands, or modify the user's Application Support
database without explicit permission.
```

## 16. Open decisions requiring the user

Do not silently choose these when their implementation becomes necessary:

- Future source-file write support beyond the Phase 4 FLAC/Vorbis matrix: WAV+CUE, DSF, AIFF, ALAC, MP3, and other containers each need a separately reviewed implementation.
- Exact lyrics and AI provider selections remain deferred. The lyrics UI intentionally has no internet provider enabled and supports manual import/edit only until the user selects a service and accepts its terms.

The user has already decided: iPad first; SMB for companion audio access; no CD ripping; manual and automatic Mac snapshot publishing; current plus three prior published snapshots with a five-second automatic-publish delay; explicit NAS master backups; manual preview-only metadata lookup; managed artwork storage; device-local companion listening preferences; explicit unknown CD locations; and shared 1–5 catalogue ratings.
