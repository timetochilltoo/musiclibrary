# Recovery writer-admission audit

Date: 13 November 2026. Scope: R8 source audit and regression design.
Status: **archive capture, cleanup and reset are exclusive; restore integration is pending**. The latest packaged app remains 0.72/build 73, schema 17.
Operational next action belongs in [HANDOFF.md](HANDOFF.md).

RA1 checkpoint: [CatalogueAdmission](Sources/MusicApplication/CatalogueAdmission.swift)
and its [lifecycle tests](Tests/MusicApplicationTests/CatalogueAdmissionTests.swift)
implement the admission primitive. [CATALOGUE_USE_MIGRATION.md](CATALOGUE_USE_MIGRATION.md)
records current and remaining coverage. Cleanup and reset each use one
reservation from archive capture through publication. Restore still continues
outside the archive reservation after capture.

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
| Sharing, database backup, archive export/restore, reset, cleanup | [Transfer queue](Sources/MusicApplication/LibraryTransferQueue.swift#L15); service entry points call `run` | Snapshot capture and master backup now acquire ordinary admission after their queue turn. Complete archive capture drains ordinary users. Cleanup and reset hold exclusive admission through verification, commit and refresh. Restore releases the archive reservation before proceeding. |
| Album create/update and other catalogue edits | [addAlbum/updateAlbum](Sources/MusicApplication/LibraryStore.swift#L434), actor SQL/transactions | Album creation and updates are scoped through refresh. Restore still releases archive admission before catalogue replacement. |
| Disc/track/credit/alias, box/location, playlist and lyrics edits | LibraryStore catalogue mutation methods; see the migration inventory | Same direct database access pattern. UI-local disabling is not service admission. |
| Managed artwork import/migration/selection | [addAlbumArtwork](Sources/MusicApplication/LibraryStore.swift#L641), [downloadManagedMusicBrainzArtwork](Sources/MusicApplication/LibraryStore.swift#L989) | Provider covers, explicit artwork import and migration hold admission through their file work, catalogue writes and refresh. |
| Root renewal/scope/deletion and access refresh | [renewStorageRootAccess](Sources/MusicApplication/LibraryStore.swift#L719) and refreshStorageRootAccess | Root writes now use admission. Destructive recovery still needs admission through installation. |
| Metadata analysis, proposal confirmation/attachment and corrections | [analyzeImportBatch](Sources/MusicApplication/LibraryStore.swift#L874) and confirmImportReleaseProposal | Metadata analysis now holds admission through extraction and proposal writes. Proposal confirmation and attachment also hold admission through reload. |
| Missing-asset and relink decisions | [applyRelinkProposal](Sources/MusicApplication/LibraryStore.swift#L779) and related decision methods | Scoped through root refresh, verification, catalogue writes and publication. Destructive recovery still needs admission through replacement and publication. |
| Scan startup and detached scan persistence | [startImportScan](Sources/MusicApplication/LibraryStore.swift#L1714) | Scan admission now covers candidate and error writes, completion, reconciliation and final publication after the detached task exits. |
| Scan cancellation | [cancelImportScan](Sources/MusicApplication/LibraryStore.swift#L1813) | Signals the worker during drain. The completion task releases admission after worker exit and publication. Archive capture drains the scan worker. |
| Fingerprinting and availability health | [verifyFingerprints](Sources/MusicApplication/LibraryStore.swift#L1656) | Fingerprint verification and availability checks now hold admission through their result writes and reloads. Hash recording need not increment revision. |
| Catalogue reads, reload, search, playback resolution, FR1 manifest reads | [reload](Sources/MusicApplication/LibraryStore.swift#L315), search and folderRecoveryManifest | RA2 scopes reload/search, but destructive recovery does not hold one scope through replacement and publication. Request generations are not an installation epoch. |
| Cleanup and tag previews, JSON/CSV exports | [catalogueCleanupPreview](Sources/MusicApplication/LibraryStore.swift#L1279) and related reader entry points | Scoped through catalogue or dry-run reads and export destination writes. Production recovery still uses the transfer queue. |
| Explicit FLAC tag execution | [executeTagWrite](Sources/MusicApplication/LibraryStore.swift#L1214) | Separate opt-in source writer; not a database lease or queued service. Its already-started work must never be automatically undone to facilitate recovery. |
| Settings controls | [activity/disabled controls](Sources/MusicLibraryMac/MusicLibraryMacApp.swift#L1699) | Local submission and recovery-review flags cover selected controls, not all other workspaces, in-flight tasks or API callers. |

### A. Recovery boundary versus ordinary writes — high priority

Complete restore stages the chosen archive, creates a local recovery archive,
checkpoints, sets `self.database = nil`, then moves/copies database and artwork
files. See [restore](Sources/MusicApplication/LibraryStore.swift#L1327).
Ordinary operations can capture the old database before these steps and suspend.
Setting the store property to nil refuses *new captures* during that interval;
it does not revoke existing references or drain workers.

An allowed interleaving is: recovery captures a recovery snapshot; another
operation commits an edit to the original catalogue; restore replaces the live
catalogue. The edit may be absent from both the installed archive and the earlier
recovery snapshot. This data-loss consequence is an **inference**, not a race
reproduced by this audit. Staging before the recovery snapshot is not itself a
problem if the eventual exclusive boundary covers snapshot-through-install.

[Reset](Sources/MusicApplication/LibraryStore.swift#L1438) and cleanup now keep
a single reservation from recovery capture through final publication. Reset
retains exact RESET confirmation and registered roots. A failed artwork
rollback keeps the verified archive and requires review before further edits.

### B. Old connection lifetime — high priority

[SQLiteHandle](Sources/MusicPersistence/SQLiteDatabase.swift#L23) closes SQLite in
`deinit`. The store dropping its reference is not a close acknowledgement from
all other holders. Detached scans, metadata/fingerprint work, ordinary reads and
other service helpers can retain the actor. Per-actor SQL serialization does not
serialize filesystem moves performed outside that actor.

Consequences can include late writes to displaced files, SQLite errors or stale
cache publication. Their exact manifestation needs deterministic fixture tests;
this report does not assert which filesystem/SQLite failure will occur first.
A checkpoint alone neither drains holders nor prevents the next actor message.

### C. Complete archive coherence — high priority

[CompleteCatalogueArchive.create](Sources/MusicApplication/CompleteCatalogueArchive.swift#L52)
uses SQLite's backup API, then reads the revision and artwork paths from the
staged database using an immutable read-only connection. The export and local
recovery archive entry points hold exclusive admission through the database and
managed artwork copies and final archive publication. The interleaving
regression verifies drain, edit refusal, and manifest metadata against the copy.
Cleanup and reset extend the reservation through writes and publication.
Restore still releases it after archive capture. Database-only backup still
reads revision separately before backup.

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
  its artwork handling and rollback. Complete archive restore comes next.
  Production maintenance reservation depends on accounting for all holders and nested helper
  paths. Calling maintenance while holding an ordinary lease can deadlock.
- **RA3:** integrate queued recovery/capture boundaries and epoch invalidation;
  add the interleaving regressions above. Recheck every existing rollback/archive
  and root-preserving reset test before claiming exclusion.
- **RA4:** audit coherent archive metadata and explicit connection-close defense;
  complete native busy/retry feedback and opt-in tag-write conflict policy.

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
