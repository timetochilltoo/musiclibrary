# Catalogue-use migration inventory

Snapshot: 20 November 2026, RA2 detail operations. Source: [LibraryStore.swift](Sources/MusicApplication/LibraryStore.swift).
Operational state: [HANDOFF.md](HANDOFF.md). Safety design: [recovery admission audit](RECOVERY_WRITER_ADMISSION_AUDIT.md).

## Coverage and lifetime contract

The 25 public declarations below currently use catalogue admission. A call to
public reload from an otherwise unscoped mutation does not cover the earlier
mutation or its retained database. No production caller reserves maintenance;
existing restore/reset/scan races remain open. Recovery must not be connected to
exclusive admission while unaccounted holders can continue using old resources.

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

- `addAlbumAlias`
- `addAlbumContributor`
- `addDisc`
- `addTrack(discID:draft:)`
- `addTrackContributor`
- `albumAliases`
- `albumArtwork`
- `albumContributors`
- `albums`
- `deleteAlbumAlias`
- `deleteAlbumContributor`
- `deleteDisc`
- `deleteTrack`
- `deleteTrackContributor`
- `discs`
- `reload`
- `reorderDisc`
- `search`
- `trackContributors`
- `tracks`
- `updateAlbum`
- `updateAlbumContributorCredit`
- `updateContributor`
- `updateTrack`
- `updateTrackContributorCredit`

`editCatalogue` keeps each detail edit, its reload and active search in one
scope. This includes contributor creation and its credit insert. Detail readers
use `withCatalogueUse`, including reads of artwork records and albums credited
to a contributor. Managed artwork file operations have separate lifetimes.
Public reload and search also own their complete scopes.

## Remaining catalogue mutations and worker lifecycle entry points

These remain unscoped for their full operation, even when their final reload now
uses admission. Some entries are worker lifecycle controls rather than SQL writers.

- `addAlbum`
- `addAlbumArtwork`
- `addBoxSet`
- `addLocation`
- `addPlaylist`
- `addStorageRoot`
- `addTrack(_:toPlaylist:itemID:)`
- `addTracks`
- `analyzeImportBatch`
- `applyExternalMetadataSelection`
- `applyRelinkProposal`
- `attachImportReleaseProposal`
- `cancelImportScan`
- `confirmAssetMissing`
- `confirmImportReleaseProposal`
- `deleteLocation`
- `deleteLyrics`
- `deletePlaylist`
- `deleteStorageRoot`
- `discardRelinkProposal`
- `migrateArtworkToManagedStorage`
- `moveAlbum`
- `moveLocation`
- `movePlaylistItem` (3 overloads)
- `permanentlyDeleteAlbum`
- `permanentlyDeletePlaylist`
- `proposeRelink`
- `recheckLibraryHealth`
- `refreshStorageRootAccess`
- `removeAlbum`
- `removeMissingAssetReference`
- `removePlaylistItem`
- `renameLocation`
- `renamePlaylist`
- `renameStorageRoot`
- `renewStorageRootAccess`
- `reorderAlbum` (2 overloads)
- `restoreAlbum`
- `restoreBoxSet`
- `restorePlaylist`
- `retryImportScan`
- `saveLyrics`
- `saveMusicBrainzSelection`
- `setImportReleaseProposal`
- `softDeleteAlbum`
- `softDeleteEmptyBoxSet`
- `startImportScan` (2 overloads)
- `updateStorageRootScope`
- `verifyFingerprints`

## Remaining readers, previews and exports

Readers can retain an old database actor and must be accounted for before file
replacement; being read-only does not make an outstanding use safe to ignore.

- `availableTrackIDs`
- `boxMembers`
- `boxPlacement`
- `catalogueCleanupPreview`
- `embeddedMetadata`
- `exportCatalogue`
- `exportCatalogueCSV`
- `externalMetadataSelection`
- `folderRecoveryManifest`
- `importAttachmentPreview`
- `importCandidates`
- `importProposalPreview`
- `importReleaseProposals`
- `lyrics`
- `missingAssetReviews`
- `nowPlayingLyrics`
- `playbackAlbumIDs`
- `playbackURL`
- `playbackURLs` (3 overloads)
- `playlistItems`
- `playlistPlaybackPlan`
- `tagWritePreviews`
- `unregisteredImportCandidates`

## Queued services, maintenance and source-writing policy

Some already use LibraryTransferQueue, but none reserves catalogue admission.
Preserve acquisition order: transfer queue first, admission second. Never await
these services while holding an ordinary scope they need to drain. Explicit FLAC
execution keeps its independent opt-in backup/journal and safe-finish policy.

- `createMasterBackupNow`
- `executeTagWrite`
- `exportCompleteCatalogueArchive`
- `flushPendingSnapshotPublication`
- `performCatalogueCleanup`
- `publishSnapshot`
- `publishSnapshotNow`
- `resetCatalogue`
- `restoreCompleteCatalogueArchive`
- `restoreMasterBackup`
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

Next migrate box-set and location operations, including album placement and
their direct readers. Keep provider and artwork work, scans, metadata,
fingerprints and queued recovery as separately accounted lifetimes. Production
recovery reservation depends on complete holder coverage and interleaving tests.
