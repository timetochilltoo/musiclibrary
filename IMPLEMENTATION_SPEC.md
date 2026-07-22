# Music Library — Implementation Specification

Date: 22 July 2026
Companion document: [BUILD_PLAN.md](BUILD_PLAN.md)

This document turns the product plan into implementation-level guidance. It intentionally specifies the complicated logic so a coding agent does not have to infer core behaviour while writing the application.

## Implementation status

Repository: `https://github.com/timetochilltoo/musiclibrary.git`
Current baseline: `2d02f10` on `main` (22 July 2026)

Completed and verified:

- Swift package structure with macOS SwiftUI executable and separate Domain, Persistence, Application, and UI modules.
- Domain identifiers, album/edition model, physical locations, box sets, contributor roles, and derived digital-availability logic.
- SQLite schema migration 1, foreign keys, catalogue revision tracking, and core repositories.
- Persistent Mac catalogue stored in the user's Application Support directory.
- Catalogue UI: browse/search albums; add albums; create/rename locations; create box sets; show basic album details.
- Atomic album creation inside a box set, including inherited physical-location behaviour.
- Ten automated domain/persistence tests, last verified with `swift test` on 22 July 2026.

Not yet implemented:

- Album editing, deletion/recovery, box-member browsing/reordering/removal, contributors, discs, tracks, aliases, and artwork.
- Folder access, scanning, metadata services, import inbox, file relocation, duplicate detection, playback, playlists, snapshots, iPad, SMB mapping, tag write-back, lyrics, and AI.

The next coding slice is **album editing and box-set membership management**, followed by contributors, discs, and tracks. Do not start file scanning or playback until those core catalogue relationships are complete and tested.

## 1. Fixed decisions

These decisions are requirements unless the user explicitly changes them:

1. macOS is the only platform allowed to create or modify catalogue data.
2. The authoritative live SQLite database is stored locally on the Mac, never opened directly from the NAS.
3. The Mac publishes consistent, versioned database snapshots to the NAS.
4. iPad and Android download snapshots into their own local storage and open them read-only.
5. One album profile represents one specific edition or pressing.
6. The same album profile represents both its physical CD and digital files.
7. `hasCD` and physical location are album-level data; there is no physical-copy table in version 1.
8. Digital availability is derived from track/file records rather than stored as a Boolean.
9. Different editions are separate album profiles, distinguished by a user-editable edition label and structured release fields.
10. A multi-disc album is one album with several discs. A box set groups several independently named album profiles.
11. Albums in a box inherit the box's physical location.
12. Scanning and online matching never rewrite source audio files automatically.
13. Online metadata is proposed and reviewed before becoming catalogue metadata.
14. Import review is persistent and resumable.
15. Media files remain in user folders or on the NAS; the app does not create a hidden duplicate library.
16. AI providers are optional adapters and must not be dependencies of the catalogue, scanner, or player.
17. iPad is the first companion client; Android is deferred.
18. CD ripping is out of scope. The app imports existing audio files only.
19. Read-only clients access NAS audio through SMB using device-local user-selected root mappings.
20. Snapshot publication supports manual publication and automatic publication after a debounced successful change and on orderly Mac app quit.

## 2. Terminology

- **Album:** one catalogued edition/pressing, not an abstract release group.
- **Disc:** an ordered medium within one album.
- **Track:** a position on a disc and its catalogue metadata.
- **Digital asset:** one concrete audio file associated with a track.
- **Storage root:** a folder selected by the user, such as a local Music folder or mounted NAS share.
- **Box set:** a physical container grouping multiple album profiles.
- **Candidate:** a not-yet-confirmed album assembled from files, barcode/photo input, or online search.
- **Proposal:** metadata from an external source presented for comparison.
- **Snapshot:** a consistent copy of the Mac catalogue published for read-only clients.

Use these names consistently in code, UI copy, tests, and documentation.

## 3. Module boundaries

Create separate Swift packages or targets with one-way dependencies:

```text
MusicDomain              Pure value types, identifiers, enums, validation
    ↑
MusicPersistence         SQLite schema, migrations, repositories, transactions
    ↑
MusicMetadata            Embedded-tag readers, MusicBrainz, artwork, fingerprinting
MusicFileScanning        Roots, enumeration, grouping, file identity, relinking
MusicPlayback            Queue and AVAudioEngine implementation
MusicSnapshot            Publish/download manifest and verification logic
    ↑
MusicApplication         Use cases coordinating repositories and services
    ↑
MusicUIComponents        Reusable SwiftUI components
    ↑
MusicLibraryMac          macOS composition root and platform integrations
MusicLibraryPad          Read-only iPad composition root, later
```

Rules:

- `MusicDomain` must not import SwiftUI, GRDB, AVFoundation, or networking frameworks.
- UI views must not execute SQL or call provider endpoints directly.
- External providers conform to protocols defined by the application/domain boundary.
- The playback module receives resolved local URLs; it does not query catalogue tables.
- Every write use case runs through a transaction in the Mac application.
- Read-only clients compile without write-use-case UI and open SQLite using read-only flags.

## 4. Identifier and time conventions

- Use UUID strings generated by the app for all internal primary keys.
- Store UUIDs in canonical lowercase textual form for portability across Swift and Android.
- Use external IDs only as alternate identifiers; never use a MusicBrainz ID as an internal primary key.
- Store timestamps as UTC ISO-8601 strings with fractional seconds, or consistently as Unix milliseconds. Choose once in migration 1 and do not mix formats.
- Store durations as integer milliseconds.
- Store file sizes as 64-bit integers.
- Store disc and track positions as integers; preserve an optional display position for unusual releases.
- Store user-facing text as Unicode without destructive normalization. Maintain normalized search columns or an FTS index separately.

## 5. Database schema version 1

The names below are normative. Exact SQL may change to accommodate GRDB, but relationships and delete behaviour should remain.

### `album`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Internal UUID |
| `title` | TEXT NOT NULL | Edition title |
| `sort_title` | TEXT | Optional user override |
| `edition_label` | TEXT | e.g. `Japan version`, `2011 remaster` |
| `release_date` | TEXT | Partial dates need separate precision or text handling |
| `release_year` | INTEGER | Search/sort convenience |
| `country_code` | TEXT | Prefer ISO code when known |
| `label_name` | TEXT | Version 1 may keep label denormalized |
| `catalogue_number` | TEXT | Preserve punctuation and leading zeroes |
| `barcode` | TEXT | Text, never numeric |
| `remaster_year` | INTEGER | Nullable |
| `media_format` | TEXT | CD, SACD, Hybrid SACD, etc. |
| `disc_count` | INTEGER NOT NULL | Minimum 1 |
| `has_cd` | INTEGER NOT NULL | SQLite Boolean |
| `physical_location_id` | TEXT FK nullable | Must be null when album belongs to a box |
| `physical_note` | TEXT | Optional free-text detail |
| `notes` | TEXT | User notes |
| `rating` | INTEGER | Nullable, constrain to agreed scale |
| `is_favourite` | INTEGER NOT NULL DEFAULT 0 | |
| `created_at` | timestamp | |
| `updated_at` | timestamp | Updated by write transaction |
| `deleted_at` | timestamp nullable | Recently Deleted tombstone |

Do not add a stored `has_digital` column.

### `album_alias`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `album_id` | TEXT FK | Cascade with album |
| `name` | TEXT NOT NULL | Alternate title |
| `locale` | TEXT | e.g. `zh-Hant`, `ja`, `en` |
| `kind` | TEXT | original, translated, romanized, alternate |

### `physical_location`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `parent_id` | TEXT FK nullable | Self-reference, restrict deletion when used |
| `name` | TEXT NOT NULL | e.g. `Shelf 2` |
| `sort_order` | INTEGER | Sibling order |
| `notes` | TEXT | |

Reject cycles in the application layer. Build the display path from ancestors and cap traversal depth defensively.

### `box_set`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `title` | TEXT NOT NULL | |
| `edition_label` | TEXT | |
| `physical_location_id` | TEXT FK NOT NULL | One inherited location |
| `notes` | TEXT | |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |
| `deleted_at` | timestamp nullable | |

### `box_set_album`

| Column | Type | Notes |
|---|---|---|
| `box_set_id` | TEXT FK | Composite PK, cascade with box |
| `album_id` | TEXT FK UNIQUE | An album belongs to at most one box |
| `position` | INTEGER NOT NULL | Unique within box |

Adding an album to a box must set `album.has_cd = true` and clear `album.physical_location_id` in the same transaction.

### `disc`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `album_id` | TEXT FK | Cascade with album |
| `number` | INTEGER NOT NULL | Unique within album |
| `title` | TEXT | Optional disc subtitle |
| `media_format` | TEXT | Optional override |

### `track`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `disc_id` | TEXT FK | Cascade with disc |
| `number` | INTEGER NOT NULL | Unique within disc |
| `display_position` | TEXT | Optional A1/B2 or unusual numbering |
| `title` | TEXT NOT NULL | |
| `sort_title` | TEXT | |
| `duration_ms` | INTEGER | Canonical catalogue duration |
| `work_name` | TEXT | Classical work |
| `movement_number` | INTEGER | |
| `movement_name` | TEXT | |
| `is_instrumental` | INTEGER | Nullable if unknown |
| `notes` | TEXT | |

Do not store a single artist string as the only contributor representation.

### `contributor` and role joins

`contributor` contains `id`, `name`, `sort_name`, optional locale, notes, and timestamps.

Use `album_contributor` and `track_contributor` join tables containing the parent ID, contributor ID, role, credited name, and position. Roles include album artist, performer, composer, conductor, orchestra, ensemble, soloist, featured artist, remixer, and producer. Role is data, not a hard-coded one-to-one column.

### `storage_root`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `display_name` | TEXT NOT NULL | |
| `last_known_path` | TEXT NOT NULL | Diagnostic/UI use |
| `bookmark_data` | BLOB | macOS security-scoped bookmark; absent on clients |
| `volume_identifier` | TEXT | When available |
| `status` | TEXT | online, offline, permissionRequired |
| `last_seen_at` | timestamp | |

Read-only clients may have a separate device-local SMB root mapping because a Mac path is not meaningful on iPad. Device-local mappings must not modify the published catalogue snapshot. The iPad must request SMB access through its own system file picker and map the selected root to a published root ID.

### `digital_asset`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `track_id` | TEXT FK | Restrict track deletion unless asset handled |
| `storage_root_id` | TEXT FK | |
| `relative_path` | TEXT NOT NULL | Normalize separators in catalogue representation |
| `file_resource_id` | TEXT | Platform identifier when stable |
| `file_size` | INTEGER NOT NULL | |
| `modified_at` | timestamp | Filesystem timestamp, not catalogue edit time |
| `duration_ms` | INTEGER | Measured file duration |
| `codec` | TEXT | flac, alac, pcm, aac, mp3, etc. |
| `container` | TEXT | flac, m4a, wav, aiff, etc. |
| `sample_rate_hz` | INTEGER | |
| `bit_depth` | INTEGER | Nullable when not meaningful |
| `channel_count` | INTEGER | |
| `bit_rate` | INTEGER | Nullable |
| `origin` | TEXT | cdRip, download, highResolution, localOther, aiGenerated |
| `content_hash` | TEXT | Full SHA-256, calculated lazily |
| `quick_signature` | TEXT | Fast identity aid |
| `acoustid` | TEXT | External fingerprint result if known |
| `availability` | TEXT | available, rootOffline, missing, permissionRequired, invalid |
| `last_verified_at` | timestamp | |

Allow multiple assets for one track. One may be marked preferred using a separate preference column or table. Never infer duplicates from filename alone.

### Remaining tables

Implement these with UUID primary keys and appropriate foreign keys:

- `external_identifier(owner_type, owner_id, provider, kind, value)` with a uniqueness constraint appropriate to provider/kind/value.
- `artwork(owner_type, owner_id, role, local_path, remote_url, mime_type, width, height, source, is_selected, checksum)`.
- `lyrics(track_id, language, kind, text, source, provider_id, is_user_edited)` where kind is plain or synchronized.
- `playlist(id, name, notes, created_at, updated_at, deleted_at)`.
- `playlist_item(id, playlist_id, track_id, preferred_asset_id, position)`; membership survives asset outages.
- `import_batch(id, kind, status, source_description, started_at, completed_at, scan_cursor, error_summary)`.
- `import_candidate(id, batch_id, status, proposed_payload, selected_provider_id, confidence, error_message, created_album_id)`.
- `edit_event(id, entity_type, entity_id, field_name, old_value, new_value, source, occurred_at)`.
- `catalogue_state(singleton_id, schema_version, catalogue_revision, last_published_revision, last_published_at)`.

Use an FTS5 index for album titles, aliases, edition labels, track titles, contributor names, catalogue numbers, barcodes, box names, and location path text. Rebuild or update the index transactionally.

## 6. Domain invariants

Enforce these in application validation and, where possible, database constraints:

1. An album belongs to zero or one box set.
2. A boxed album has `has_cd = true` and no direct `physical_location_id`.
3. A standalone album with `has_cd = true` should have a physical location or be explicitly marked `location unknown`.
4. Setting `has_cd = false` clears its standalone location and removes box membership only after confirmation.
5. A box set must have a physical location.
6. Box positions and disc/track numbers are unique within their parent.
7. A digital asset belongs to exactly one track in version 1.
8. Removing the last usable asset changes derived digital status; it does not alter `has_cd`.
9. Soft-deleted records do not appear in normal search, boxes, or playlists, but relationships needed for restoration remain.
10. Permanent deletion is blocked when restoration-dependent relationships have not been handled.
11. Confirming an import candidate is idempotent; retrying after interruption must not create another album.
12. Every confirmed external value retains provider provenance.
13. A catalogue write increments `catalogue_revision` once per committed user operation, not once per SQL statement.
14. Publishing never changes catalogue content or revision.

## 7. Derived digital status

Calculate album status using all non-deleted expected tracks and their preferred assets:

```text
none:
    no track has a digital asset

complete:
    every expected track has at least one available playable asset

partial:
    at least one, but not every, expected track has an asset

offline:
    every expected track has an asset reference, but one or more roots are offline
    and no asset is known to be individually missing

broken:
    one or more referenced assets are confirmed missing, invalid, or unreadable
```

Precedence when several conditions apply: `broken` > `partial` > `offline` > `complete` > `none`. Keep the detailed counts so UI can say `9 of 10 tracks available` rather than only showing a state.

Do not mark every file missing when a NAS root is disconnected. First determine root availability; mark assets `rootOffline` and preserve their paths.

## 8. Add Album use case

All entry methods create an `AlbumDraft` rather than writing album tables directly.

```swift
struct AlbumDraft {
    var source: DraftSource
    var metadata: AlbumMetadataProposal
    var discs: [DiscDraft]
    var hasCD: Bool
    var physicalPlacement: PhysicalPlacement?
    var matchedExistingAlbumID: AlbumID?
    var externalIdentifiers: [ExternalIdentifier]
    var artworkChoices: [ArtworkCandidate]
}
```

Flow:

1. Capture barcode/photo/search/folder/manual input.
2. Build a local draft immediately.
3. Fetch zero or more external proposals without blocking manual continuation.
4. Show exact edition fields and track-list differences.
5. If a likely existing album is found, require the explicit choice `attachExisting` or `createNewEdition`.
6. Validate physical placement:
   - standalone CD requires a structured location or explicit unknown location;
   - boxed CD requires a box and no album location;
   - digital-only album requires neither.
7. Confirm in one transaction.
8. Record edit/provenance events and mark the import candidate confirmed.
9. Increment the catalogue revision.

The transaction must be idempotent using `import_candidate.created_album_id` or an operation UUID.

## 9. File-scanning pipeline

### Enumeration

- Resolve and start security-scoped access for each selected root.
- Enumerate recursively off the main actor.
- Ignore hidden/system files, package contents, and configured exclusions.
- Recognize supported audio by Uniform Type Identifier/content probe, not extension alone.
- Yield progress periodically by item count and current path.
- Support cancellation without discarding already persisted candidates.
- Persist recoverable errors per file; one corrupt file must not abort the root.

### Metadata extraction

For every audio file, collect:

- embedded album, album artist, track artist, title, disc/track number and totals;
- date/year, genre, composer and classical fields where present;
- MusicBrainz IDs, barcode, ISRC, compilation flag;
- duration, codec, container, sample rate, bit depth, channels, bitrate;
- embedded artwork references;
- root-relative path, size, modification time, resource ID, and quick signature.

Preserve raw tag values in the import candidate payload for diagnostics. Map them into normalized proposal fields without destroying the originals.

### Grouping

Group in descending confidence:

1. Exact embedded release ID.
2. Album ID plus disc identity.
3. Normalized album title + album artist + release year + compatible disc totals.
4. Folder boundary as a weak hint only.

Split one folder when strong album identity differs. Merge subfolders such as `CD1` and `CD2` when tags and totals indicate one edition. Never merge solely because files share a parent folder.

Flag uncertain groups instead of guessing. Persist the grouping reason and confidence for the review UI.

### Duplicate strategy

Use staged cost:

1. Exact existing root + relative path.
2. File resource ID where available.
3. Size + duration + quick signature.
4. Full SHA-256 for likely duplicates.
5. Chromaprint for audio-equivalent files with different encodings; do not treat differently mastered recordings as byte duplicates.

Hashing must be bounded, cancellable, and performed off the main actor.

## 10. Metadata matching and precedence

Suggested source order:

1. User-confirmed catalogue value
2. User-edited value
3. Confirmed exact-edition online match
4. Embedded file metadata
5. Folder/filename inference
6. AI/OCR proposal

Higher priority does not automatically overwrite lower priority. It decides which value is preselected in the comparison UI. The user can retain any existing value.

MusicBrainz requests must use an identifiable User-Agent, respect the current service rate limit, cache responses, coalesce duplicate requests, and retry transient errors with bounded exponential backoff. Provider failures must not block local import.

Matching score should consider barcode, catalogue number, release country/date, disc count, track count, track positions, normalized durations, titles, and contributors. Barcode/catalogue number exact matches are strong but still require confirmation when track lists conflict.

## 11. Metadata write-back

Do not implement tag writing in the initial scanner. When implemented:

1. Maintain an explicit supported container/tag matrix.
2. Present the exact files and field changes in a dry-run report.
3. Verify write permission and free space.
4. Create recoverable backups or replacement files according to format capability.
5. Write to a temporary sibling file when possible.
6. Re-read and verify tags and audio properties.
7. Atomically replace the original only after verification.
8. Keep a batch journal containing before/after state and errors.
9. Never rewrite audio frames merely to change metadata unless the format library requires it and the user has approved the risk.

Partial batch failure must be visible and resumable. Do not report success for the entire batch when one file fails.

## 12. Physical locations and box sets

Represent location paths through parent links rather than a single uncontrolled string. UI selection uses a tree with create/rename/move operations.

Moving a location node changes the displayed path of all descendants without updating every album. Prevent deletion of a location referenced by an album or box until the user moves those records.

Box operations are transactional:

- Adding a member clears its direct location and sets `has_cd`.
- Removing a member requires a destination location or explicit unknown-location state.
- Moving the box changes only `box_set.physical_location_id`.
- Deleting a box requires the user to move, retain with unknown locations, or soft-delete its members.
- Reordering members updates positions without delete/reinsert identity changes.

## 13. Playback state machine

Keep playback state separate from SwiftUI view state:

```text
idle
  → preparing(track)
  → playing(track)
  ↔ paused(track)
  → preparing(nextTrack)
  → playing(nextTrack)

Any active state → failed(error, recoverableAction)
Any active state → idle
```

Queue state contains ordered track IDs, selected asset IDs when overridden, current index, shuffle seed/order, and repeat mode. Persist enough information to reconstruct the queue after relaunch.

Requirements:

- Resolve root and asset availability before preparing playback.
- Choose the preferred available asset; do not silently choose a lossy file over a preferred lossless file without indicating it.
- Pre-open/schedule the next compatible file for gapless transition.
- Handle different sample rates explicitly and show source versus output format.
- Recover from sleep/wake, output-device removal, and NAS disconnection.
- Update UI from a single observable playback controller on the main actor.
- Keep audio callbacks free of database and network work.
- Define previous-button behaviour: restart current track after a threshold, otherwise move to previous.
- Shuffle produces a stable order for the current session and avoids immediately replaying the current item.

## 14. Snapshot publication protocol

### Manifest

Publish `catalogue-manifest.json` similar to:

```json
{
  "formatVersion": 1,
  "schemaVersion": 1,
  "catalogueRevision": 154,
  "createdAt": "2026-07-22T07:15:30.000Z",
  "databaseFile": "catalogue-154.sqlite",
  "databaseBytes": 10485760,
  "sha256": "...",
  "minimumClientSchemaVersion": 1
}
```

### Mac publish algorithm

1. Refuse to publish while a migration is incomplete.
2. Use SQLite's online-backup API to produce a consistent local temporary snapshot; never copy the live database file directly.
3. Run `PRAGMA integrity_check` against the snapshot.
4. Ensure no private bookmark data or Mac-only secrets are included in the published representation. Prefer a sanitized snapshot if device-local tables share the database.
5. Calculate size and SHA-256.
6. Upload/copy the database under a revisioned temporary NAS filename.
7. Verify the NAS copy by size and checksum.
8. Rename the database to its final revisioned name.
9. Write and verify a temporary manifest.
10. Rename the manifest last so clients never discover an incomplete publication.
11. Update local `last_published_revision` only after the manifest is committed.
12. Retain the latest N verified revisions; never delete the currently referenced snapshot.

Publishing is available explicitly and automatically. Automatic publishing runs after a debounced successful catalogue change and on orderly app quit, but it must never block quitting indefinitely. Coalesce repeated writes into one publication and surface a non-blocking error if the NAS is unavailable.

### Read-only client algorithm

1. Open the last verified local snapshot immediately so launch does not depend on the NAS.
2. Check the manifest's SMB modification date in the background. If it is not newer than the device's recorded manifest date, stop without downloading it.
3. If newer, fetch the manifest and compare format, schema, catalogue revision, and checksum metadata.
4. If newer and compatible, download to a device-local temporary file.
5. Verify byte size, SHA-256, and SQLite integrity.
6. Close active readers, then atomically replace the local snapshot.
7. Reopen read-only and refresh repositories/UI.
8. On any failure, remove only the temporary download and keep the previous snapshot.
9. Show last sync time and a non-blocking error/retry action.

Client-local preferences such as root mappings or UI settings belong in a separate local preferences database, never inside the replaceable catalogue snapshot.

## 15. Relocation and availability

Root check order:

1. Resolve stored bookmark/root mapping.
2. Determine whether the root itself is reachable.
3. If unreachable, mark root offline and do not rewrite asset rows.
4. If reachable, verify referenced relative paths.
5. For missing files, search a user-selected replacement root using resource ID, quick signature, then content hash.
6. Present proposed relinks before committing ambiguous matches.

Relinking an entire root updates the root mapping once; asset relative paths remain stable. Individual relinking changes the asset root/path and records an edit event.

## 16. Library Health queries

The health screen uses independently refreshable sections:

- albums with derived status `partial`;
- assets `missing`, `invalid`, or `permissionRequired`;
- storage roots offline;
- likely duplicate assets grouped by hash/signature;
- albums without selected front artwork;
- albums whose expected track count differs from attached assets;
- import candidates not confirmed/ignored;
- failed import files and provider requests;
- soft-deleted records approaching permanent deletion;
- `catalogue_revision - last_published_revision` unpublished changes.

Each item must link to a repair action. Avoid a dashboard that reports problems without a way to resolve them.

## 17. Search behaviour

- Search is case-insensitive and diacritic-tolerant where practical, while displaying original text.
- Tokenize aliases and contributor credited names.
- Exact barcode and catalogue-number matches rank first.
- Album title + edition label results show edition, year, country, CD/digital state, box name, and location so similar pressings are distinguishable.
- Soft-deleted records are excluded unless searching Recently Deleted.
- Search remains local and works offline on every client.

## 18. Error handling

Use typed errors with a user action:

```swift
enum RecoveryAction {
    case retry
    case chooseFolder
    case reconnectStorage
    case reviewCandidate
    case openSettings
    case restorePreviousSnapshot
    case none
}
```

Log technical context without exposing API keys, bookmark blobs, lyrics, or full private paths unnecessarily. User-facing errors state what failed, what remains safe, and what can be done next.

Long operations report determinate progress when total work is known, otherwise current phase and item. Cancellation is cooperative and leaves persistent data in a valid resumable state.

## 19. Security and privacy

- Store provider API keys in Keychain on the Mac.
- Never include credentials in the published database or manifest.
- Use HTTPS for NAS services when traffic leaves a trusted LAN.
- Explain before uploading cover images, audio, or lyrics to an AI provider.
- Keep an AI request history with provider, model, purpose, timestamp, and resulting asset, but redact credentials.
- Make cloud features optional; catalogue, scan, search, and local playback must continue without them.
- Validate downloaded snapshot filenames and never construct arbitrary local paths from an untrusted manifest.

## 20. Migration policy

- Every schema change is an ordered, tested migration.
- Back up before migration.
- Migrations are transactional where SQLite permits.
- A failed migration leaves the previous database usable.
- Published manifests declare schema compatibility.
- An older read-only client refuses an incompatible snapshot and continues using its last compatible version.
- Maintain fixture databases for every released schema version and test forward migration.

## 21. Testing strategy

### Unit tests

- Album/box/location invariants
- Digital-status derivation and precedence
- Edition display-name formatting
- Search normalization and ranking
- Grouping-confidence rules
- Duplicate-candidate stages
- Queue shuffle/repeat/previous behaviour
- Snapshot manifest compatibility and validation

### Persistence tests

- All migrations from empty and previous fixtures
- Foreign-key and uniqueness constraints
- Idempotent import confirmation
- Soft delete and restoration
- Revision increment exactly once per use case
- FTS synchronization after create/edit/delete/restore

### Scanner fixtures

Include legal test files representing FLAC, ALAC/M4A, WAV, AIFF, MP3, multi-disc folders, mixed albums in one folder, compilations, classical metadata, Unicode titles, corrupt files, missing tags, conflicting release IDs, embedded artwork, and duplicate audio in different containers.

### Integration tests

- Scan → review → attach existing/create edition → search → play
- Box creation → member inheritance → move box → remove member
- Root offline → reconnect → relink
- Publish → interrupt client download → retain old snapshot → retry successfully
- Metadata comparison → selective acceptance → source files unchanged
- Backup → delete test database → restore relationships and counts

### Playback soak tests

- Several hours of sequential playback
- Gapless album boundaries
- Mixed sample rates and bit depths
- Sleep/wake
- Output DAC unplug/replug
- NAS temporarily unavailable
- Corrupt next track while queue continues safely

## 22. Implementation sequence for the coding model

Do not scaffold every future feature at once. Implement vertical slices in this order:

1. Domain IDs/enums/value types and validation tests.
2. SQLite migration 1, repositories, and persistence tests.
3. Basic Mac shell with Albums, album editor, structured locations, and local search.
4. Box sets and location inheritance.
5. External metadata provider protocol and MusicBrainz search/review.
6. Storage-root selection and security-scoped bookmark persistence.
7. Scanner enumeration and technical metadata extraction.
8. Persistent Import Inbox, grouping, and confirmation transactions.
9. Digital health and relinking.
10. Playback engine and persistent queue.
11. Playlists.
12. Library Health, edit history, Recently Deleted, and export.
13. Snapshot publisher and a command-line/read-only validation harness.
14. First read-only iPad client with SMB root mapping and snapshot download.
15. Tag write-back, lyrics, and AI only after the earlier gates pass.

For each slice:

1. Add or update the relevant specification test.
2. Implement the smallest complete use case.
3. Run unit and integration tests.
4. Manually verify with representative real-library copies.
5. Update schema/format documentation when behaviour changes.
6. Do not begin the next slice with failing tests or an unreviewed migration.

## 23. Questions that remain intentionally open

These require user choice or a technical spike; the coding model should not silently decide them:

- The exact supported audio/tag-writing matrix.
- Whether client-local favourites/play history are permitted, since those cannot modify the Mac catalogue under the current rule.
- Whether an album may intentionally have an unknown physical location.
- Rating scale and whether ratings are album-only or also track-level.

Until decided, keep these behind interfaces or configuration and use the simplest safe default described above.
