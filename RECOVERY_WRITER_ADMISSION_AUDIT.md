# Recovery writer-admission audit

Date: 13 November 2026. Scope: R8 source audit and regression design.
Status: **both restores are exclusive; installation identity protects attachment and selected deferred actions**. The latest packaged app remains 0.72/build 73, schema 17.
Operational next action belongs in [HANDOFF.md](HANDOFF.md).

RA1 checkpoint: [CatalogueAdmission](Sources/MusicApplication/CatalogueAdmission.swift)
and its [lifecycle tests](Tests/MusicApplicationTests/CatalogueAdmissionTests.swift)
implement the admission primitive. [CATALOGUE_USE_MIGRATION.md](CATALOGUE_USE_MIGRATION.md)
records current and remaining coverage. Cleanup, reset and both restore paths
hold one reservation from recovery capture through publication.

## Finding

`LibraryTransferQueue` serializes its participating services, not all catalogue
users. Main-actor isolation and individual SQLite transactions do not make an
async LibraryStore operation exclusive across its suspension points. Existing
restore rollback/recovery protections remain valuable, but do not establish that
an acknowledged concurrent edit is included in recovery or that all users of an
old database connection have stopped before file replacement.

This audit confirms missing admission/drain coverage from source. It does **not**
claim to have reproduced live corruption, lost personal data or a real NAS race.
No production code, catalogue, media or system preference changed for this audit.

## Evidence and coverage map

Links identify representative entry points, not an exhaustive migration allowlist.
Before integrating a gate, enumerate every public use case and private worker.

| Operation | Present protection | Gap relevant to recovery |
|---|---|---|
| Sharing, database backup, archive export/restore, reset, cleanup | [Transfer queue](Sources/MusicApplication/LibraryTransferQueue.swift#L15); service entry points call `run` | Snapshot capture and master backup now acquire ordinary admission after their queue turn. Complete archive capture drains ordinary users. Cleanup, reset and both restore paths hold exclusive admission through recovery verification, commit or rollback, and refresh. |
| Album create/update and other catalogue edits | [addAlbum/updateAlbum](Sources/MusicApplication/LibraryStore.swift#L443), actor SQL/transactions | Album creation and updates are scoped through refresh. Both restore paths drain admitted edits before recovery capture. |
| Disc/track/credit/alias, box/location, playlist and lyrics edits | LibraryStore catalogue mutation methods; see the migration inventory | Same direct database access pattern. UI-local disabling is not service admission. |
| Managed artwork import/migration/selection | [addAlbumArtwork](Sources/MusicApplication/LibraryStore.swift#L652), [downloadManagedMusicBrainzArtwork](Sources/MusicApplication/LibraryStore.swift#L1010) | Provider covers, explicit artwork import and migration hold admission through their file work, catalogue writes and refresh. |
| Root renewal/scope/deletion and access refresh | [renewStorageRootAccess](Sources/MusicApplication/LibraryStore.swift#L732) and refreshStorageRootAccess | Root writes now use admission. Restore holds admission through installation and publication. |
| Metadata analysis, proposal confirmation/attachment and corrections | [analyzeImportBatch](Sources/MusicApplication/LibraryStore.swift#L890) and confirmImportReleaseProposal | Metadata analysis now holds admission through extraction and proposal writes. Proposal confirmation and attachment also hold admission through reload. |
| Missing-asset and relink decisions | [applyRelinkProposal](Sources/MusicApplication/LibraryStore.swift#L793) and related decision methods | Scoped through root refresh, verification, catalogue writes and publication. Restore holds admission through replacement and publication. |
| Scan startup and detached scan persistence | [startImportScan](Sources/MusicApplication/LibraryStore.swift#L1824) | Scan admission now covers candidate and error writes, completion, reconciliation and final publication after the detached task exits. |
| Scan cancellation | [cancelImportScan](Sources/MusicApplication/LibraryStore.swift#L1924) | Signals the worker during drain. The completion task releases admission after worker exit and publication. Archive capture drains the scan worker. |
| Fingerprinting and availability health | [verifyFingerprints](Sources/MusicApplication/LibraryStore.swift#L1766) | Fingerprint verification and availability checks now hold admission through their result writes and reloads. Hash recording need not increment revision. |
| Catalogue reads, reload, search, playback resolution, FR1 manifest reads | [reload](Sources/MusicApplication/LibraryStore.swift#L324), search and folderRecoveryManifest | RA2 scopes reload/search, but Mac catalogue and player presentation state is invalidated on installation change. Attachment, MusicBrainz, physical entry, relink and mutating file-picker actions validate their originating identity under admission. Destructive Settings approvals also validate identity before writes or queued maintenance starts. |
| Cleanup and tag previews, JSON/CSV exports | [catalogueCleanupPreview](Sources/MusicApplication/LibraryStore.swift#L1327) and related reader entry points | Scoped through catalogue or dry-run reads and export destination writes. Production recovery still uses the transfer queue. |
| Explicit FLAC tag execution | [executeTagWrite](Sources/MusicApplication/LibraryStore.swift#L1239) | Checks the approved preview identity under ordinary admission. An active writer drains through backup, replacement and journal even on caller cancellation. The opt-in and manual recovery protections remain. |
| Settings controls | [activity/disabled controls](Sources/MusicLibraryMac/MusicLibraryMacApp.swift#L1640) | Local submission and recovery-review flags cover selected controls, not all other workspaces, in-flight tasks or API callers. |

### A. Recovery boundary versus ordinary writes — high priority

Complete restore stages the chosen archive under the transfer queue. It then
drains ordinary catalogue users and holds an exclusive scope while it captures
and verifies the recovery archive, checkpoints, releases the old database,
replaces the database and artwork, and publishes either the restored or rolled
back catalogue. See [restore](Sources/MusicApplication/LibraryStore.swift#L1390).
The disposable regression confirms the recovery archive includes an admitted
edit that finishes during drain. [Database-only restore](Sources/MusicApplication/LibraryStore.swift#L1665)
verifies a staged SQLite copy before draining ordinary users. The corresponding
regression verifies the last admitted edit in the retained previous database
and publication after cancellation during final refresh.

[Reset](Sources/MusicApplication/LibraryStore.swift#L1523) and cleanup now keep
a single reservation from recovery capture through final publication. Reset
retains exact RESET confirmation and registered roots. A failed artwork
rollback keeps the verified archive and requires review before further edits.

### B. Old connection lifetime — high priority

Both restore paths drain catalogue operations before calling
SQLite's checked truncate checkpoint and a synchronous close in the database
actor. A busy or failed checkpoint aborts replacement. The app drops its
reference only after the close succeeds, and retained actors reject later
database operations. Rollback explicitly closes an opened replacement before
removing sidecars or moving the original back. Disposable fixtures pin a
second SQLite reader to verify refusal and successful retry on both paths.
[SQLite checkpoint API](https://sqlite.org/c3ref/wal_checkpoint_v2.html)
[SQLite close API](https://sqlite.org/c3ref/close.html)

### C. Complete archive coherence — high priority

[CompleteCatalogueArchive.create](Sources/MusicApplication/CompleteCatalogueArchive.swift#L52)
uses SQLite's backup API, then reads the revision and artwork paths from the
staged database using an immutable read-only connection. The export and local
recovery archive entry points hold exclusive admission through the database and
managed artwork copies and final archive publication. The interleaving
regression verifies drain, edit refusal, and manifest metadata against the copy.
Cleanup, reset and complete archive restore extend the reservation through
writes and publication. Database-only backup now derives the filename and
manifest revision from the captured SQLite payload as well. The regression
edits the live database immediately before and after the SQLite copy.

### D. Cancellation and stale results — required lifecycle coverage

Cancelling a scan does not wait for its worker to stop. Cancellation can still be
followed by batch-finalization writes and queued progress/refresh callbacks.
Fingerprint and metadata jobs likewise need ownership through their final write,
not merely through file reads. FR1's full-manifest freshness check remains a
read-only historical comparison; it is not a global lock and should stay so.

An incomplete rollback currently clears the store database and records recovery
review guidance. Existing tests show new ordinary database edits refuse in that
state. Do not generalize that result to operations already holding the old actor,
or to source-writing operations that do not require the database property.

## Proposed admission contract — design, not current behavior

1. Add a main-actor catalogue-use coordinator with scoped operation leases and
   an exclusive maintenance reservation. State transitions are open → draining
   → exclusive → open, or review-required after incomplete recovery. Set draining
   synchronously before the first await so new work cannot slip into admission.
2. Acquire a recovery reservation when the service reaches the head of the
   transfer queue, not while waiting behind earlier transfers. Existing edits can
   finish before that point and must be represented in the later recovery archive.
   Once draining begins, new ordinary work should fail locally with retry guidance;
   do not silently replay stale edits against a newly installed catalogue.
3. Drain admitted operations, including database readers and managed-artwork
   commits, before checkpoint/file replacement. Include the complete lifetime of
   detached workers and their final writes. Do not assume task cancellation is
   completion, or release a lease while a worker can still use the actor.
4. Bound the exclusive interval around recovery capture, checkpoint, installation
   or reset/cleanup, reopen/rollback and final reload. Reserve coherent capture for
   complete archive export too. Do not hold a UI/SQLite transaction across network
   or NAS waits; staging/provider preparation can be separate disposable work.
5. Capture a catalogue-installation epoch before long preparation; on return,
   revalidate before committing. A new store database or reset invalidates old
   intent/results even if IDs or revision values happen to match. Revision alone
   is insufficient because fingerprint writes do not increment it.
   A backup/export alone must not pretend that a different catalogue was installed;
   keep installation epochs distinct from ordinary request/progress generations.
6. Use explicit internal operation context for nested store helpers. Do not acquire
   another lease inside an admitted call after draining has begun, and do not use
   an unrestricted TaskLocal bypass inherited by arbitrary detached children.
   Detached work must explicitly own its lease/context through termination.
7. Keep acquisition order **transfer queue → catalogue admission** for queued
   services. Ordinary operations must not await a queued service while holding a
   lease that recovery is waiting to drain. Use private helpers under one context;
   reload may schedule later publication after completion, not deadlock on it.
8. Invalidate old reload/search/progress publication at the maintenance boundary.
   Hold read ownership through publication or use an epoch check; stale results
   must not overwrite post-restore state. Existing audio already prepared for
   playback need not be stopped merely to introduce catalogue admission.
9. Read archived revision/path mappings from the backed-up database or otherwise
   verify their equality under the coherent capture boundary. Retain full recovery
   archive verification and root-preserving reset checks. Consider explicit actor
   close/rejection of old-epoch access as defense in depth only after holder
   inventory; `database = nil` is not that mechanism today.
10. For opt-in FLAC writing, define conflict admission separately: no new execution
    during exclusive maintenance; already-started writes retain backup/journal
    protections and drain safely. Never add automatic retagging, undo, deletion or
    source movement. FR2 whole-root apply remains deferred.

## Deterministic regression design

Use checked continuations/latches and bounded test completion, not guessed sleeps.
All database, managed artwork and audio sentinels must be inside unique temporary
children. Hooks must be internal fixture composition, unavailable to normal
startup. Do not add passing tests that require unsafe admission to remain allowed.

| Case | Pause point / action | Required post-fix assertion |
|---|---|---|
| Existing edit before maintenance | Hold edit before commit, request exclusive reservation | Recovery waits; successful edit is in the required recovery snapshot. |
| New edit after reservation | Hold recovery in draining/exclusive, invoke public edit | Refuses before DB/file side effects; no false success and no implicit replay. |
| Detached scan drain | Hold scan before candidate/finalization write, request recovery, cancel scan | No file replacement until finalization/cleanup drains; no late original-actor write. |
| Metadata/fingerprint return | Hold extraction/hash result, replace/reset catalogue | Old epoch cannot commit to either old or new catalogue; hashes/status unchanged. |
| Artwork/provider return | Hold download/import preparation, restore/reset | No late managed file/register/cleanup against the wrong generation. |
| Read/cache return | Hold reload/search/manifest read before publication | Read lifetime is drained or old publication rejected; restored cache stays current. |
| Archive coherence | Hold after SQLite copy, attempt artwork/revision edit | Edit is excluded/deferred or archive capture is coherently validated; manifest matches copied DB. |
| FIFO and deadlock | Publication before recovery, another transfer after; nested helpers/reload | Order preserved; no double admission, starvation from new work or self-deadlock. |
| Cancel waiting reservation | Cancel recovery while draining an admitted operation | No replacement; admitted work is not cancelled by a waiter; admission reopens safely. |
| Cancellation after installation starts | Cancel active recovery at explicit safe points | Defined finish/rollback behavior; no early lease release or half-installed cancellation claim. |
| Failed recovery | Inject install/rollback failure | Existing retained recovery, review-required state and retry protections survive; no admission leak. |
| Reset/cleanup | Hold after verified archive; attempt root/edit/artwork change | Snapshot-to-mutation exclusion, exact confirmation and root/source preservation. |

## Incremental implementation order

- **RA1, implemented in isolation:** main-actor scoped ordinary ownership,
  FIFO maintenance reservation/drain, fail-fast new work, context membership,
  cancellation-safe release and terminal review-required state. Nine lifecycle
  tests include cancelled head/middle waiters, grant races, explicit nested
  helpers and detached-worker drain. A maintenance body retains its own context
  for cleanup after requesting review, while queued/new work refuses. Active-body
  cancellation/rollback policy remains with that body; the coordinator does not
  revoke ownership, force-stop a worker or inject failure after successful work.
  Contexts are active lease tokens, not installation epochs. RA2 begins partial
  LibraryStore integration below; global protection is not established.
- **RA2, partial:** inventory and migrate LibraryStore database/artwork uses to scoped
  context, including readers, scans, metadata and fingerprints; exercise real
  temporary workflows. Partial migration must not be described as global safety.
  The context-taking helper foundation and first ordinary read/edit slice are
  implemented. Scoped calls now include album details, box sets, placement,
  locations, playlists, album lifecycle, lyrics, embedded metadata, playback,
  storage root operations, folder recovery manifest reads and library health.
  Fingerprint verification now holds admission through the hash worker and result
  writes. Import scans transfer admission to their completion task. Import analysis,
  direct review readers, proposal decisions, composite preview and external metadata
  selection writes are scoped. Album creation and explicit artwork import and
  migration are scoped, as are missing-asset and relink decisions, cleanup and
  tag-write previews, and JSON and CSV exports. Queued snapshot and master-backup
  capture now use ordinary admission. Complete archive capture holds exclusive
  admission through publication. Cleanup extends this reservation through
  verification, commit and final refresh. Reset holds the same boundary through
  its artwork handling and rollback. Complete archive restore keeps the scope
  through installation or rollback and final publication. Database-only restore
  now holds the same boundary. The Mac invalidates catalogue-bound presentation
  on installation change, and attachment checks the preview's identity in its
  admitted write. MusicBrainz review, physical entry, relink and mutating
  file pickers now check their originating installation too. Destructive
  Settings approvals validate identity inside admission or at the start
  of the transfer queue turn. Explicit FLAC execution checks identity and holds
  admission through its detached worker.
  Production maintenance reservation depends on accounting for all holders and nested helper
  paths. Calling maintenance while holding an ordinary lease can deadlock.
- **RA3:** integrate queued recovery/capture boundaries and epoch invalidation;
  add the interleaving regressions above. Recheck every existing rollback/archive
  and root-preserving reset test before claiming exclusion.
- **RA4:** complete and database-only archive metadata now comes from the
  captured SQLite payload. Both restore paths require a successful checkpoint
  and close before file replacement. Next review Mac busy/retry feedback and
  exercise the disposable native recovery workflow.

RA2–RA4 are a proposed sequence, not completed work or permission for FR2. A
coordinator primitive passing its tests will not fix the present call-site gaps.

## Evidence boundaries

Source reviewed on 13 November 2026 against the files linked above. Existing
`swift test --filter 'RecoveryTransferCoordinationTests|RecoveryTransferIntegrationTests|LibraryTransferQueueTests'`
passed **19 tests in 3 suites**, using temporary fixtures. Log:
`/private/tmp/musiclibrary-recovery-admission-audit.log`. Those tests cover current
queue/rollback behavior, not the new concurrency cases in the design table.
Whitespace and repository-local Markdown link targets were checked. The initial
audit added no source/schema/test implementation and did not rerun full suites or
package an app. RA1 adds the primitive/lifecycle tests; RA2 adds partial scoped
use and temporary-database tests, with current validation in HANDOFF. None of these checkpoints
establishes application-wide exclusion or fixes the call-site races described here.
