# Catalogue-use migration inventory

Snapshot: 28 November 2026, companion snapshot source switching. Source: [LibraryStore.swift](Sources/MusicApplication/LibraryStore.swift).
Operational state: [HANDOFF.md](HANDOFF.md). Safety design: [recovery admission audit](RECOVERY_WRITER_ADMISSION_AUDIT.md).

## Coverage and lifetime contract

The 112 public declarations below currently use catalogue admission. A call to
public reload from an otherwise unscoped mutation does not cover the earlier
mutation or its retained database. Complete archive capture reserves maintenance
inside a transfer queue turn. Cleanup holds the reservation through
verification, commit and refresh. Reset holds the same boundary through managed
artwork displacement or rollback. Both restore paths reserve admission
from recovery capture through installation, rollback and refresh.

`withCatalogueUse` acquires/validates context before capturing the store database,
then awaits the caller's resource work. Never return the database actor or launch
an unowned worker from this scope. Await all resource use before returning.
`reload(using:)` and `search(_:using:)` are explicit context-taking nested helpers:
they do not reacquire admission, even when maintenance is draining. Ownership
includes structured reads and cache/search publication. An unstarted reload/search
retains its earlier no-database behavior; resource use through the helper still
refuses a missing database. Expired/foreign contexts refuse before database capture.
Search admission refusal remains task-local feedback and does not adopt the
rejected query. Existing search/reload generation and cancellation guards remain.

This is a declaration inventory, not a compiler-enforced allowlist. Overloads are
counted separately; every public `func` name in LibraryStore at this checkpoint is
listed once in one category. Initializers, properties, detached closures and private
helpers also need lifetime review. Update this inventory with each migration.
The only current LibraryStore extension, [LibraryNavigationFixture](Sources/MusicApplication/LibraryNavigationFixture.swift),
is a Debug temporary-data factory; its seeding is separate from production uses.

## Migrated public methods

- `addAlbum`
- `addAlbumAlias`
- `addAlbumArtwork`
- `addAlbumContributor`
- `addBoxSet`
- `addDisc`
- `addLocation`
- `addPlaylist`
- `addStorageRoot`
- `addTrack(_:toPlaylist:itemID:)`
- `addTrack(discID:draft:)`
- `addTrackContributor`
- `addTracks`
- `albumAliases`
- `albumArtwork`
- `albumContributors`
- `albums`
- `applyExternalMetadataSelection`
- `applyRelinkProposal`
- `availableTrackIDs`
- `boxMembers`
- `boxPlacement`
- `catalogueCleanupPreview`
- `deleteAlbumAlias`
- `deleteAlbumContributor`
- `deleteDisc`
- `deleteLocation`
- `deleteLyrics`
- `deletePlaylist`
- `deleteStorageRoot`
- `deleteTrackContributor`
- `deleteTrack`
- `discs`
- `discardRelinkProposal`
- `embeddedMetadata`
- `exportCatalogue`
- `exportCatalogueCSV`
- `folderRecoveryManifest`
- `lyrics`
- `migrateArtworkToManagedStorage`
- `moveAlbum`
- `moveLocation`
- `movePlaylistItem` (3 overloads)
- `nowPlayingLyrics`
- `permanentlyDeleteAlbum`
- `permanentlyDeletePlaylist`
- `playbackAlbumIDs`
- `playbackURL`
- `playbackURLs` (3 overloads)
- `playlistItems`
- `playlistPlaybackPlan`
- `recheckLibraryHealth`
- `proposeRelink`
- `refreshStorageRootAccess`
- `reload`
- `removeAlbum`
- `removePlaylistItem`
- `removeMissingAssetReference`
- `renameLocation`
- `renamePlaylist`
- `renameStorageRoot`
- `renewStorageRootAccess`
- `reorderAlbum` (2 overloads)
- `reorderDisc`
- `restoreAlbum`
- `restoreBoxSet`
- `restorePlaylist`
- `saveLyrics`
- `saveMusicBrainzSelection`
- `search`
- `softDeleteAlbum`
- `softDeleteEmptyBoxSet`
- `tagWritePreviews`
- `executeTagWrite`
- `trackContributors`
- `tracks`
- `updateAlbumContributorCredit`
- `updateAlbum`
- `updateContributor`
- `updateStorageRootScope`
- `updateTrackContributorCredit`
- `updateTrack`
- `verifyFingerprints`
- `retryImportScan`
- `startImportScan` (2 overloads)
- `importCandidates`
- `unregisteredImportCandidates`
- `importReleaseProposals`
- `missingAssetReviews`
- `importAttachmentPreview`
- `externalMetadataSelection`
- `analyzeImportBatch`
- `setImportReleaseProposal`
- `confirmImportReleaseProposal`
- `confirmAssetMissing`
- `attachImportReleaseProposal`
- `importProposalPreview`

`editCatalogue` keeps each detail edit, its reload and active search in one
scope. This includes contributor creation and its credit insert. Detail readers
use `withCatalogueUse`, including reads of artwork records and albums credited
to a contributor. Managed artwork file operations have separate lifetimes.
Public reload and search also own their complete scopes.

Box-set and location edits also retain admission through refresh. Location
creation returns its saved record from within the same scope. Box membership
and placement readers use the scoped helper.

Playlist lifecycle and item edits hold admission through reload, including
batch addition and all three reorder overloads. The direct item reader uses
the same admission helper as the other direct readers.

Album deletion and restoration and lyrics edits retain admission through
refresh. Embedded metadata and lyrics readers borrow the database after
admission. The Now Playing lyrics query uses a single scope for its track
and lyrics reads.

Playback identity, availability and URL resolution acquire admission before
database use. Disc and playlist playback read members through their admitted
database. Root access refresh and its reload reuse the playback context. Direct
root access refresh has its own scope for callers outside playback.

Storage root edits own admission through validation, writes and reload. Folder
recovery manifest reads acquire scoped database access. Library health holds
one scope for root refresh, asset availability checks and reload.

Fingerprint verification holds one scope from root refresh and candidate reads
through the awaited hash worker, result writes and reload.

Scan startup owns admission from root refresh through batch creation. The
completion task takes that ownership through worker exit, publication and
progress cleanup. Cancel requests signal the existing worker during a drain
and leave admission held until completion.

Import metadata analysis holds admission across root refresh, extraction and
proposal writes. The direct candidate, proposal, missing-asset, attachment and
external selection readers each acquire admission before capturing the database.

Proposal status changes, confirmation, attachment and composite preview use
catalogue admission. Confirmation and attachment reuse the scope through
reload. Preview and confirmation pass their admitted database to the folder
artwork lookup.

Import metadata selection save and application use catalogue admission.
Application holds admission through optional provider cover download, temporary
and managed file work, selection and proposal writes, any album cover
registration and its reload.

Album creation holds admission through the optional provider cover download
and managed copy, the creation transaction, rollback file cleanup, and
refresh. Artwork import and migration hold admission through security-scoped
access, managed copy, catalogue update, cleanup and refresh.

Missing-asset confirmation and reference removal and relink dismissal use the
shared edit scope through publication. Relink proposal creation and application
also reuse their scope through root refresh, replacement verification and
catalogue publication. Application uses its admitted database for availability
refresh.

Cleanup preview borrows the database under admission. JSON and CSV exports
keep admission through serialization and the atomic destination write. FLAC
tag-write preview retains one scope across all tracks, including root refresh,
playback path resolution and dry-run reads. Explicit write-back requires the
preview installation identity and retains ordinary admission through detached
backup, writing and journal completion. A store refuses another write while
one is active.

### Queued capture entry points

Snapshot publication captures revision and JSON under admission, then publishes
the values under the existing transfer queue turn. Manual and background
publication, including a pending flush, delegate to that capture. Master backup
holds admission through its awaited detached backup and retention work.
It names the backup and writes the manifest revision using a read-only
immutable inspection of the captured SQLite payload.

Complete archive export and pre-recovery archive creation drain ordinary users
and hold exclusive admission until the archive is published. The SQLite copy
supplies the revision and artwork paths through an immutable read. Cleanup
reuses its existing exclusive context for capture. It verifies the recovery
archive before committing and awaits publication under the same context.
Reset also reuses its exclusive context. It verifies the archive before
displacing artwork, restores the original artwork on pre-commit failure and
requires review if rollback fails. Complete archive restore stages and verifies
the source archive before reserving admission. It then drains existing users and
holds one exclusive context from recovery archive verification through
installation or rollback and final publication. Database-only restore stages
a copy and verifies it against the selected manifest before reserving admission.
It then drains existing users, checkpoints and verifies the retained previous
database, and holds admission through replacement or rollback and publication.

- `exportCompleteCatalogueArchive`
- `createMasterBackupNow`
- `flushPendingSnapshotPublication`
- `performCatalogueCleanup`
- `publishSnapshot`
- `publishSnapshotNow`
- `resetCatalogue`
- `restoreCompleteCatalogueArchive`
- `restoreMasterBackup`

## Worker lifecycle control

Scan cancellation signals an admitted worker during drain. The completion task
owns the worker's catalogue scope until it exits and publishes.

- `cancelImportScan`

## Preference and directory helpers

These helpers have no independent catalogue scope. Destination changes use the
existing transfer-queue busy check. The tag backup directory helper resolves
the location used by the scoped writer.

- `setSnapshotDestination`
- `tagWriteBackupDirectory`

## Startup and non-borrowing/presentation boundaries

`start` creates/assigns the database and remains a separate lifecycle review.
The following do not themselves borrow the database actor; this is not a blanket
exemption for their callers or asynchronously spawned work. `isManagedArtwork` is
a managed-path membership check, and synthetic activity helpers are Debug-only.

- `beginSyntheticQueueActivity`
- `dismissError`
- `finishSyntheticQueueTask`
- `holdMaintenanceFixtureReader`
- `releaseMaintenanceFixtureReader`
- `isManagedArtwork`
- `lookupMusicBrainz`
- `musicBrainzReleaseDetails`
- `presentError`
- `searchMusicBrainz`
- `showSyntheticRecoveryFailure`

## Private helpers and detached work

The migrated private reload/search helpers reuse their caller's context. Review
all other private resource paths before enabling maintenance. In particular:

- Scans retain `database` in a detached task through candidate/error/finalization/
  reconciliation writes and queued callbacks. Cancellation alone is not drain.
- Metadata extraction, fingerprinting and artwork/provider return paths need
  explicit lifetime ownership plus later installation-epoch revalidation.
- `refreshImportBatches`, root/availability refresh, imported artwork discovery,
  local recovery archive creation and queued capture/install helpers retain or
  derive shared catalogue/artwork state.
- Delayed publication/daily-backup scheduling must not deadlock by waiting for a
  queued transfer while an admitted scope is held. Reload only schedules that
  work; it does not await the queued service.
- Recovery reloads eventually require their existing exclusive context; do not
  call the public ordinary-admission wrapper from an exclusive owner.

## Acceptance and next slice

Temporary SQLite tests hold search completion with continuations. They verify an
album edit owns one scope through nested reload/search, drains before a synthetic
maintenance barrier, rejects new migrated entry points without SQL changes, keeps
a rejected query from becoming active, and preserves reader ownership after parent
cancellation until the held work returns. Provider/validation/missing-database/
invalid-context failures release or refuse cleanly. Existing search overlap tests
continue to cover generation ordering. These are partial integration checks, not
live recovery exclusion or reader migration completeness.

Catalogue installation identity changes after a committed reset, successful
restore, or incomplete rollback. Ordinary edits and recovered rollbacks keep
it. Mac catalogue workspaces and player presentation invalidate their cached
state on replacement. Attachment previews capture this identity and pass it
to the admitted write.

MusicBrainz review and physical entry retain the identity of their drafts.
Relink confirmation and mutating folder and artwork pickers capture it when
opened. The store checks it inside admission before catalogue or file work.
Scan startup releases admission if the identity check refuses.

Permanent album and playlist removal validate the Settings confirmation's
identity inside admission. Cleanup, reset and both restores capture the
request identity at submission and check it after the transfer queue wait,
before staging, recovery writes or the exclusive reservation.

Both restore paths check the truncate checkpoint result and explicitly close
the live SQLite connection before moving the database file. An incomplete
checkpoint leaves the original connection available. Closed actors refuse
subsequent database work. Rollback closes any replacement connection before
moving the original back.

The Mac observes admission phase separately from the transfer queue. Its
window banner distinguishes drain, exclusive work and recovery review.
The Debug-only recovery fixture holds an ordinary reader to exercise drain.

Committed resets and successful restores invalidate the scheduled shared
snapshot independently of revision equality. The publisher orders snapshots
within the sharing destination and records the captured catalogue revision
separately. The companion compares the publication order.

The companion compares publication numbers only when the selected folder
matches the source recorded with its active cache. A new source can install a
lower or equal publication after checksum and schema validation. Its manifest
and source identity activate together, while the previous verified snapshot
remains available on failure.

Next address repair of a missing or damaged local payload when the selected
source still advertises the same publication number.
