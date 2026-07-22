# Music Library — Project Handoff

Last updated: 22 July 2026
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

Tests/
  MusicDomainTests/AlbumTests.swift
  MusicPersistenceTests/MusicDatabaseTests.swift
```

The package products are `MusicDomain`, `MusicPersistence`, `MusicApplication`, `MusicUIComponents`, and the `MusicLibraryMac` executable. SQLite is linked with the system `sqlite3` library; there are no third-party dependencies.

## 7. Current implemented behaviour

### Database and domain

Implemented and tested:

- Strong UUID types for core entities such as albums, locations, box sets, tracks, and assets.
- `NewAlbum` validation: nonblank title, disc count at least one, valid years, rating range, and no direct physical location when no CD is marked.
- Album display title combining title and optional edition label.
- Derived digital availability state model: `none`, `complete`, `partial`, `offline`, and `broken`.
- SQLite migrations 1 and 2 with foreign keys, catalogue revision state, album, aliases, locations, box sets, discs, tracks, contributors, digital assets, playlists, import records, edit events, and FTS table placeholders.
- SQLite WAL mode and foreign-key enforcement on database open.
- Persist/create/query albums; search title, edition label, and catalogue number.
- Persist/create/list/rename physical locations.
- Persist/create/list box sets.
- Add an existing album to a box set, clearing its direct location and ensuring CD availability.
- Create a new album directly in a box set atomically; failure to find the box rolls back album creation.
- Edit albums; browse, confirm moves into, remove from, and reorder box-set members.
- Distinguish standalone unknown physical location from boxed placement with `physical_location_unknown`.
- Begin the catalogue-content persistence layer: ordered discs/tracks, aliases, contributors, and album-level contributor roles.
- Increment catalogue revision once per successful high-level write operation.

### macOS UI

Implemented:

- Three-column SwiftUI navigation shell.
- Album browsing and local search.
- Add Album form: title, edition label, release year, country/region, catalogue number, disc count, CD toggle, direct location, and optional box set.
- Location list, create-location form with optional parent selection, and rename context menu.
- Box-set list and create-box-set form.
- Basic album detail view showing edition fields, CD status, and direct location or box/unknown state.
- Error alerts and initial database-opening progress UI.

Runtime database location on the Mac:

```text
~/Library/Application Support/MusicLibrary/MusicLibrary.sqlite
```

This database is user data. Do not remove it during development. If a destructive schema experiment is unavoidable, first make a recoverable copy and tell the user exactly what happened.

## 8. Current tests and verification baseline

The last verified baseline contains 14 tests in 2 suites. Run `swift test`; do not rely on this handoff alone.

`MusicDomainTests/AlbumTests.swift` verifies:

- Album title validation.
- Direct location requires CD availability.
- Edition label display formatting.
- Broken availability takes precedence.
- Complete assets produce complete availability.

`MusicPersistenceTests/MusicDatabaseTests.swift` verifies:

- Schema migration 2 and initial catalogue revision.
- Album persistence and revision increment.
- Box membership clears direct location while retaining CD availability.
- Location list and rename.
- Failed creation in a nonexistent box set rolls back the album and revision.
- Album editing preserves identity and revision semantics.
- Member moves, reordering, removal, and invalid removal rollback preserve placement rules.
- Ordered discs/tracks, aliases, and album contributor roles persist correctly.

There are no UI automation or visual snapshot tests yet. Building via `swift test` compiles the macOS executable, but does not exercise a real UI session. Add targeted tests before making core data behaviour more complex.

## 9. Important implementation details and limitations

### Persistence actor

`MusicDatabase` is an actor. Keep SQLite access inside it. Do not pass raw SQLite pointers, statements, or mutable database state into views or other modules.

`SQLiteHandle` is intentionally an internal `@unchecked Sendable` wrapper so the actor can own and close the SQLite handle under Swift 6 concurrency checking. Do not broaden this escape hatch beyond the persistence internals.

### Application state

`LibraryStore` is `@MainActor` and owns one `MusicDatabase` actor. It creates/migrates the Application Support database on app start, loads albums/locations/box sets, and refreshes after a successful write.

Views must call store use cases; they must not compose SQL or open databases directly.

### Search

Current search is a simple `LIKE ... COLLATE NOCASE` query over album title, edition label, and catalogue number. The FTS table exists in schema 1 but is not populated or used. Do not claim full alias/contributor/diacritic-tolerant search is implemented until a migration/repository/update strategy and tests exist.

### Locations

Parent links are stored. The UI permits choosing a parent when creating a location, but currently renders locations as a flat list and only supports rename (not move/delete). Cycle prevention, path rendering, moving, and deletion guards are future work.

### Box sets

Creating a new album inside a selected box set is atomic. Box detail lists ordered members, supports explicit confirmed moves, safe removal, and reordering.

Schema version 2 adds `physical_location_unknown`. A boxed album has no direct location and this flag is false; a standalone CD with an unknown location has this flag true. Preserve this distinction in future code and migrations.

### Album detail and editing

Albums are currently create-only in the UI. The data schema contains more fields than the initial detail view exposes. There is no edit, soft delete, restore, artwork, contributors, discs, or tracks UI.

### Digital media

No storage roots, file scans, audio metadata extraction, digital-asset persistence UI, playback, playlists, SMB, snapshots, iPad app, lyrics, tag write-back, or AI is implemented. Existing strings/enums/schema tables are scaffolding, not completed features.

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

## 11. Exact next slice: contributors, discs, tracks, aliases, and artwork

This is the next task. Complete it before scanning, playback, metadata services, or iPad work.

### Goal

Make each edition accurately represent its contents and credits:

- Add ordered discs and tracks.
- Add album-level and track-level contributors with roles.
- Add searchable aliases for original, translated, and romanized titles.
- Add selected front artwork with provenance.

### Required persistence work

1. Add domain entities/drafts and persistence repositories for discs, tracks, contributors, aliases, and artwork.
2. Preserve uniqueness of disc numbers within an album and track numbers within a disc.
3. Use the existing contributor join tables for album and track roles; do not introduce one authoritative artist string.
4. Add transactional create/edit/reorder operations and revision increment semantics.
5. Add artwork provenance and selected-state rules without automatic external downloading or source-file mutation.
6. Populate/use FTS only when its synchronization and search behaviour are tested.

### Required UI work

1. Add a disc/track editor from album detail.
2. Add contributor selection/creation with role labels and ordering.
3. Add alias and artwork management surfaces with clear source labels.
4. Show discs, tracks, and contributors in album detail.
5. Handle errors in the existing non-blocking alert pattern.

### Required tests

Add persistence tests for at least:

- Disc/track uniqueness and ordering.
- Contributor role relationships at album and track level.
- Alias persistence and future-search index behaviour.
- Artwork selected-state rules and provenance.
- Revision increments once for each successful high-level operation and rolls back on invalid input.

Run `swift test` after the slice. Update this document's completed/not-implemented sections, tests, limitations, and next task before committing.

## 12. Planned implementation order after the next slice

Do not implement all of this at once. Complete and test one vertical slice per commit group.

1. Contributors, discs, tracks, aliases, and artwork selection.
2. Storage root selection and security-scoped bookmark persistence on macOS.
3. Cancellable recursive scanner, embedded metadata extraction, grouping, and persistent Import Inbox.
4. External metadata proposals/review and artwork; no write-back.
5. Digital assets, availability health, duplicate detection, and relocation.
6. Lossless playback engine, queue, and playlists.
7. Library Health, soft delete/recovery, edit history, JSON/CSV export.
8. Safe tag write-back and lyrics only after robust backup/recovery work.
9. Mac snapshot publisher and validation harness.
10. Read-only iPad client, manifest check, snapshot replacement, and SMB root mapping.
11. AI/OCR/music generation last and behind provider protocols.

The detailed acceptance criteria and algorithms for later phases are in `IMPLEMENTATION_SPEC.md`.

## 13. Documentation maintenance policy

After every completed slice, update all applicable documents in the same commit:

- `HANDOFF.md`: current status, tests, limitations, precise next slice, known issues, and any changed command/environment fact.
- `IMPLEMENTATION_SPEC.md`: implementation status and any architectural/schema/invariant change.
- `BUILD_PLAN.md`: roadmap or user-facing scope changes only.

Do not merely write “implemented X.” State the files/modules affected, tests run, what still does not work, and the next safe starting point. This is what makes a context-recovery handoff useful.

## 14. Session-resume prompt

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

## 15. Open decisions requiring the user

Do not silently choose these when their implementation becomes necessary:

- Exact supported audio containers and metadata write-back matrix.
- Whether read-only client-local favourites and play history are allowed, since they cannot alter the Mac catalogue under the current writer rule.
- Snapshot retention count and automatic-publication debounce duration.
- Whether a standalone CD album may intentionally have an unknown physical location, and how that must appear in the UI.
- Rating scale and whether ratings remain album-only or also become track-level.
- Which metadata provider(s), lyrics provider(s), and AI provider(s) will be used after their adapter boundaries are implemented.

The user has already decided: iPad first, SMB for companion audio access, no CD ripping, and both manual and automatic Mac snapshot publishing.
