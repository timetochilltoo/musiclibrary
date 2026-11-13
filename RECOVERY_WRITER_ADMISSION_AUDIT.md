# Recovery writer-admission audit

Date: 13 November 2026. Scope: R8 source audit and regression design.
Status: **gaps identified; no exclusion fix implemented**. Production remains 0.72/build 73, schema 17.
Operational next action belongs in [HANDOFF.md](HANDOFF.md).

RA1 checkpoint: [CatalogueAdmission](Sources/MusicApplication/CatalogueAdmission.swift)
and its [lifecycle tests](Tests/MusicApplicationTests/CatalogueAdmissionTests.swift)
now implement the isolated admission primitive. Nothing in LibraryStore uses it
yet; the audited call-site gaps below remain open.

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
| Sharing, database backup, archive export/restore, reset, cleanup | [Transfer queue](Sources/MusicApplication/LibraryTransferQueue.swift#L15); service entry points call `run` | Orders these services only; not an application-wide resource lease. |
| Album create/update and other catalogue edits | [addAlbum/updateAlbum](Sources/MusicApplication/LibraryStore.swift#L398), actor SQL/transactions | Capture `database` without a maintenance gate. Album creation can await cover download before its commit. |
| Disc/track/credit/alias, box/location, playlist and lyrics edits | LibraryStore methods around lines 441–565, 968–1033 and 1506–1535 | Same direct database access pattern. UI-local disabling is not service admission. |
| Managed artwork import/migration/selection | [addAlbumArtwork](Sources/MusicApplication/LibraryStore.swift#L503), [downloadManagedMusicBrainzArtwork](Sources/MusicApplication/LibraryStore.swift#L827) | Catalogue records and artwork files can change outside the transfer queue. Provider work retains the managed store across an await. |
| Root renewal/scope/deletion and access refresh | [renewStorageRootAccess](Sources/MusicApplication/LibraryStore.swift#L575), refresh around line 606 | Root metadata writes do not join recovery exclusion. Access refresh is a writer, despite its name. |
| Metadata analysis, proposal confirmation/attachment and corrections | [analyzeImportBatch](Sources/MusicApplication/LibraryStore.swift#L709), confirmation around line 746 | Multiple await/write steps; metadata reads can return after a catalogue replacement. |
| Scan startup and detached scan persistence | [startImportScan](Sources/MusicApplication/LibraryStore.swift#L1423) | Detached task explicitly captures `database`; persists candidates/errors/completion/reconciliation outside the queue. |
| Scan cancellation | [cancelImportScan](Sources/MusicApplication/LibraryStore.swift#L1485) | Sets cancellation only; does not await worker completion. Recovery does not call a scan-drain barrier. |
| Fingerprinting and availability health | [verifyFingerprints](Sources/MusicApplication/LibraryStore.swift#L1362) | Hash worker returns to a retained database and records results later. Availability checks also write. Hash recording need not increment revision. |
| Catalogue reads, reload, search, playback resolution, FR1 manifest reads | [reload](Sources/MusicApplication/LibraryStore.swift#L295), search around line 379, manifest around line 570 | Readers also retain database actors. Reload/search generations protect their own requests, not an explicit catalogue-installation epoch. Reader lifetime matters when replacing database files. |
| Explicit FLAC tag execution | [executeTagWrite](Sources/MusicApplication/LibraryStore.swift#L1007) | Separate opt-in source writer; not a database lease or queued service. Its already-started work must never be automatically undone to facilitate recovery. |
| Settings controls | [activity/disabled controls](Sources/MusicLibraryMac/MusicLibraryMacApp.swift#L1699) | Local submission and recovery-review flags cover selected controls, not all other workspaces, in-flight tasks or API callers. |

### A. Recovery boundary versus ordinary writes — high priority

Complete restore stages the chosen archive, creates a local recovery archive,
checkpoints, sets `self.database = nil`, then moves/copies database and artwork
files. See [restore](Sources/MusicApplication/LibraryStore.swift#L1079).
Ordinary operations can capture the old database before these steps and suspend.
Setting the store property to nil refuses *new captures* during that interval;
it does not revoke existing references or drain workers.

An allowed interleaving is: recovery captures a recovery snapshot; another
operation commits an edit to the original catalogue; restore replaces the live
catalogue. The edit may be absent from both the installed archive and the earlier
recovery snapshot. This data-loss consequence is an **inference**, not a race
reproduced by this audit. Staging before the recovery snapshot is not itself a
problem if the eventual exclusive boundary covers snapshot-through-install.

Reset similarly awaits its complete recovery archive before deleting rows and
moving/removing artwork. See [reset](Sources/MusicApplication/LibraryStore.swift#L1190).
A write admitted after that recovery snapshot can be removed by the reset
without being represented in the snapshot. Cleanup also has a snapshot-to-delete
window. Preserve exact RESET confirmation and root-preservation behavior.

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
reads revision, calls `createConsistentBackup`, then queries managed artwork paths
from the **live** database and copies artwork. These are separate steps.
[createConsistentBackup](Sources/MusicPersistence/SQLiteDatabase.swift#L136) uses
SQLite's backup API and verifies the payload: the SQLite copy itself has a
consistency safeguard. The missing guarantee is coherence between that copy,
manifest revision, live path query and managed artwork at one capture boundary.

An intervening edit can make manifest revision differ from the backed-up
catalogue, or make copied artwork/path mappings describe a different state.
Missing-artwork checks may reject some cases, but do not prove a single coherent
capture. Database-only backup also reads revision separately before backup.
Checksum verification establishes payload bytes, not this multi-resource
capture contract. These interleavings were source-reviewed, not fault-injected.

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
  Contexts are active lease tokens, not installation epochs. No LibraryStore
  integration, filesystem replacement or global protection is established.
- **RA2, next:** inventory and migrate LibraryStore database/artwork uses to scoped
  context, including readers, scans, metadata and fingerprints; exercise real
  temporary workflows. Partial migration must not be described as global safety.
  Start with a context-taking helper foundation and an ordinary read/edit vertical
  slice; do not enable production maintenance reservation until all affected
  holders and nested helper paths are accounted for. Calling maintenance while
  holding an ordinary lease remains a prohibited acquisition-order deadlock.
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
package an app. The later RA1 checkpoint adds the isolated primitive and lifecycle
tests, with current full/focused validation in HANDOFF. Neither checkpoint
establishes application-wide exclusion or fixes the call-site races described here.
