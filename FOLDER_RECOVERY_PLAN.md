# Music folder recovery plan

Status: FR1 local acceptance and contextual accessibility implemented, broader acceptance partial, 12 November 2026. **Not an implemented relocation feature.**

Implemented so far: a coherent read-only root manifest, pure reference preflight
grouping, a cancellable read-only candidate-file verifier and permission-scoped
preview orchestration with catalogue freshness checks. Music Library 0.71 adds
the replacement selection/progress/results sheet. Apply remains absent. Synthetic
native mixed-result, cancellation and stale-state acceptance passed in compact
dark mode. Disposable local nonempty picker/verifier integration also passed;
full accessibility and NAS/remount acceptance remain pending. This is not a
relocation operation.

Accessibility checkpoint (0.72): each hash disclosure exposes its outcome and
relative path with a unique identifier. Its label is applied to the title only,
preserving expanded reference counts and expected/computed hash text. Sheet,
results and file paths expose headings; single references use singular wording.
Native light-mode checks independently expanded unverified/conflicting files and
retained their absent/baseline hashes. Return and Escape passed. Tab/Shift-Tab did
not establish traversal on this host; the Debug fixture reports AppKit full
keyboard access off. No system preference was changed. Full traversal in an
explicitly configured test environment and spoken VoiceOver remain open.

Operational state and the current next slice remain in [HANDOFF.md](HANDOFF.md).
Architecture/invariants remain in [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md).

## Current behavior and the gap

Music Library 0.70 renews permission for the same standardized registered path. A
known volume identifier must match. The expected-path database update preserves
the existing root ID, name, scope, volume and all asset references. It does not
support choosing a replacement path. Successful macOS permission renewal still
requires acceptance with a disposable authorized folder; fixture bookmark bytes
only validate persistence.

Existing bookmark resolution can find the original directory at a changed path;
`refreshStorageRootAccess` already records that resolved path. This behavior is
distinct from manually selecting a different directory and is unchanged here.

`StorageRoot.volumeIdentifier` identifies a volume, not a music directory or its
contents. `digital_asset.content_hash` can hold a full content hash, but it is
optional. `AssetFingerprinting` produces SHA-256 hashes through an explicit read
operation; its quick signature is a byte count and hash prefix, not independent
identity evidence. `assetFingerprintCandidates()` currently returns IDs/root IDs/
relative paths without expected hashes. A new preview therefore needs a scoped
read query rather than assuming that this method provides verification evidence.

## Separate user tasks

| Task | Existing or proposed route | Effect |
|---|---|---|
| Drive temporarily disconnected | Reconnect, then Check Access | Recheck the registered root |
| Permission expired at the same path | Renew Access | Replace its permission bookmark in place |
| Folder moved and the bookmark no longer resolves | Proposed Review Replacement Folder | Preview identity evidence without changing the catalogue |
| Individual files moved inside a root | Existing per-asset relink review | Explicit changes to selected references |

Do not offer Add Music Folder as recovery for an existing root: it creates another
root rather than repairing the original references. Never remove the old root to
work around a permission or relocation failure.

## FR1 — read-only replacement preview

Add **Review Replacement Folder…** beside an unavailable root's existing access
actions. The sheet explains the registered name/path and asks the user to select
the directory that contains the same relative layout. Selection alone does not
start verification, persist a bookmark, change root status or start an import.

Implemented in FolderRecoveryPreview and MusicFolderScanControls. The scrollable
sheet keeps Close/Verify/Cancel actions outside the results area, groups every
outcome with counts, and expands paths, hash evidence and reference counts.
Changed/unavailable rechecks retain explicit historical guidance; even unchanged
results describe the completion-time comparison. Empty manifests get a separate
no-references explanation. Dismissal cancels the session. Known registered volume
metadata is shown, but candidate volume identity is not used as content evidence.
Compact light-mode native acceptance passed selection, chooser cancellation,
explicit verification of a disposable empty folder, details/scrolling and close
with unchanged registered permission state. This does not cover nonempty results
or slow filesystem cancellation; backend fixture tests cover those mechanics.

Synthetic acceptance checkpoint: Debug `--folder-recovery-fixture` opens a
standalone workspace without LibraryStore startup or SQLite. Its dedicated bundle
guard, internal temporary-child permission substitute and disabled real picker
prevent unrelated candidate access. All eight outcomes, ten asset references
(including repeated CUE links), changed/unavailable rechecks and worker failure
are generated evidence, clearly labelled synthetic. A manually released worker
models cooperative cancellation blocked in an operation; it performs no hashing
or NAS calls. Compact dark native checks passed group expansion, missing-baseline
details, historical messages, retry admission, progress/cancel, superseding
selection, balanced access, Return and Escape/dismissal. These are presentation
and orchestration checks, not real file/grant/NAS evidence. Release refuses the
fixture flag; production contains neither the fixture factory nor controls.

Real-file acceptance checkpoint: Debug `--folder-recovery-files-fixture` seeds a
temporary SQLite catalogue and known bytes, marks its original root offline
after seeding, and runs the real verifier with real operation-scoped access from
the native folder picker. Its additional selection guard accepts only the exact
disposable candidate directory (including the macOS /var alias), not parents or
unrelated URLs. Native light-mode selection, explicit Verify/Verify Again,
matching/read-hash equality and symlink refusal passed. Outcomes were one each:
verified, different content, unverified, missing and unsafe. Final integrity
checked the unchanged manifest/revision/root state, known bytes, outside sentinel,
symlink destination and absent original/missing paths. Baselines are controlled
fixture values, not inferred from a user's replacement. This is local disposable
grant/read evidence; it does not establish NAS/remount or sandbox endurance.

The explicit **Verify References** action reads only referenced paths beneath the
selected directory. Show progress, checked/total files and Cancel. Explain that
verification reads files and may take time on a NAS. Never enumerate unrelated
folders, search other drives or use an internet service. Release security scope
on completion/cancellation; returning to the chooser preserves the old root.

Present old and selected paths, known volume identities, unique file counts and
the following evidence groups. Keep technical hashes in expandable details.

| Classification | Required evidence | Meaning |
|---|---|---|
| Verified | Recorded full hash equals a stable candidate file's full hash | Strong match for that referenced file |
| Different content | Both full hashes exist and differ | Cannot use this candidate for a whole-root change |
| Unverified | No recorded full hash | Path, size, tags or duration alone cannot prove identity |
| Missing | Referenced candidate path is absent | Preview incomplete; do not mark the original asset missing |
| Unreadable | Access or hashing failed | Preserve details and allow explicit retry |
| Unsafe | Relative path/symlink escapes the selected root | Do not open the escaped file |
| Catalogue conflict | Expected hashes disagree for one physical path, or candidate root ownership is ambiguous | Require separate review |

An empty registered root gets a separate no-references explanation, not a claim
that its contents match. Do not call a sampled subset a verified folder. A same
volume ID, same folder name or equal file count is insufficient.

FR1 always has **Close** and **Choose Another Folder**; it has no Apply button or
path-writing service. Results are session-only. Missing original hashes remain
unverified; do not manufacture a baseline from the replacement and compare it to
itself. Keep the existing individual-relink route available for later user review.

### Code and data boundaries

Foundation implemented: `folderRecoveryManifest(rootID:)` reads root metadata,
revision and references in one deferred read transaction. Bookmark bytes are
represented only by a SHA-256 digest. Track IDs and CUE ranges are retained.
`FolderRecoveryReferencePlan` groups identical relative-path strings (not proven
physical file identities). It classifies ready-to-verify, unverified, unsafe-path
and conflicting-hash groups without opening files or producing verified evidence.
All references in a group must carry matching valid full hashes to be ready.
Ambiguous separators/dot components are conservatively unsafe.

Verifier backend implemented: FolderRecoveryVerifier runs a detached worker and
propagates parent cancellation. It canonicalizes the selected root with realpath,
opens it with no-symlink flags and anchors component-by-component read-only opens
to that descriptor. All referenced symlinks are rejected, including in-root links.
It hashes regular files in 256 KiB chunks, compares file identity/size/mtime/ctime
before and after reading, and re-walks the path to detect replacement. Candidate
root changes discard the report. Preflight-unverified/conflicting/unsafe groups
are reported without file reads. Empty roots remain a no-evidence result.

The caller must own any required security scope for the operation's duration;
the verifier does not acquire or persist permission. Cancellation is cooperative
between chunks/metadata operations; it cannot forcibly interrupt a blocked NAS
system call. A report is historical per-file evidence, not an atomic filesystem
snapshot. FolderRecoveryPreviewSession compares a freshly captured manifest,
including hash fields, when verification finishes; revision alone is insufficient
because recordAssetFingerprint does not increment the catalogue revision. An
unchanged result means equal at that recheck, not a guarantee about later edits.

Preview orchestration implemented: selection alone performs no reads. Explicit
Verify captures the manifest and acquires operation-scoped permission, balancing
release after success, failure or cancellation. A cancelled worker must drain
before another run starts; changing selection discards old progress/results.
Progress is coalesced to one pending update. Completed reports retain their
captured manifest and distinguish unchanged, changed and unavailable rechecks;
the latter two remain historical evidence. Tests substitute permission only
through an internal factory confined to disposable temporary children, not a
normal-launch bypass. Actual picker/security-scope grants remain unverified.
The UI must cancel on dismissal and present historical status accurately. Later
catalogue changes require a new verification; there is no global writer lock.

1. **MusicDatabase:** add a read-only root-scoped reference manifest query. Return
   root identity/path/bookmark digest/volume/scope and catalogue revision, plus
   asset IDs, relative paths and expected full hashes. No schema change is needed
   for FR1. Do not expose bookmark bytes in UI, logs or exported preview results.
2. **Domain/application model:** represent the immutable manifest, selected-folder
   metadata, evidence per physical path and aggregate progress/results. Group
   repeated physical paths while retaining all affected asset IDs and track links.
3. **Application verifier:** validate lexical and resolved containment before
   opening a file. Reject escaping symlinks and directories at file paths. Hash
   off the main actor in bounded chunks, supporting cancellation between chunks.
   Check file identity/size/modification metadata before and after reading; changed
   files are unreadable/unstable evidence, never verified. Do not assume the current
   hashing helper already implements these new checks or cancellation.
4. **SwiftUI:** own selection and presentation only. Show task-local failures,
   retain the registered root context and avoid global alerts for ordinary retry.
   Changing candidate selection invalidates old results. Prevent double verification.
5. **Fixture composition:** use temporary databases and byte sentinels only.
   Native error/progress fixtures must be clearly synthetic and isolated from
   normal startup. Do not use the user's catalogue to construct recovery cases.

Verification may discover a changed catalogue while running. Keep its captured
manifest as historical preview evidence, label it stale and require a fresh
preview before any future write. FR1 must not claim a global catalogue lock.

## FR2 — future manual apply, deferred from FR1

Before implementing a write, resolve writer exclusion for root renewal, scans,
edits, restore/reset and publication. The current transfer queue does not cover
all those operations; merely adding one queued task cannot establish exclusion.
The [R8 writer-admission audit](RECOVERY_WRITER_ADMISSION_AUDIT.md) now maps these
gaps and proposes staged coordinator/integration coverage. It is a source audit,
not an implemented lock or evidence that live corruption occurred. RA1's isolated
coordinator is the next implementation boundary; FR2 remains deferred.

A proposed apply contract must include all of the following:

- An explicit review/confirmation identifies the root and old/new path, affected
  reference count and scope. Verification never implies permission to apply.
- Every referenced physical file must have current strong evidence. Missing,
  differing, unstable, unsafe or unverified files block a blanket root change.
  A policy for empty roots must be explicit and separately tested.
- Preserve a verified local complete recovery archive before the database write.
  Abort if archive creation or verification fails; include no source audio.
- Revalidate candidate access and captured root/reference/hash evidence after
  recovery creation and immediately before commit. Selection/evidence must still
  refer to the same directory. Define conservative invalidation for concurrent
  catalogue changes and candidate file replacement; do not rely on path alone.
- One database transaction replaces the root's path/bookmark/volume/access fields
  under expected-state guards. Preserve its ID, name and scope, all asset IDs,
  relative paths, cue/disc/track relationships, playlists and physical placements.
  Record one revision/audit result; do not create another root or rewrite assets.
- Keep publication/client root IDs stable. Invalidate Mac locality caches; retain
  existing publication rules and never publish Mac bookmarks or absolute paths to
  clients. Decide file-availability refresh separately rather than silently
  clearing confirmed missing states during a root metadata update.
- Failed/cancelled apply preserves the old association and retained recovery
  archive. No source file is moved, renamed, deleted, uploaded or retagged. No
  automatic scan, tag write, recursive relink or retry is added.

This plan does not implement automatic relinking or promise restart recovery.
Different-volume relocation can be reviewed in a future explicit workflow using
strong file evidence; it must not weaken same-path Renew Access checks.

## Validation and acceptance

| Slice | Cases and required outcomes |
|---|---|
| Same-path renewal, existing | With a disposable authorized folder, grant access to exactly the registered path; verify one unchanged root ID/name/scope and unchanged relative references/source bytes; reopen the app and check the persisted bookmark. Cancel/wrong path/wrong known volume must preserve prior state. Current automated tests cover persistence/refusal, not successful OS grants. |
| FR1 manifest | Read only the requested root; retain repeated-file asset mappings; handle zero references, absent hashes and conflicting hashes; confirm no revision/bookmark/status/path changes. |
| FR1 verifier | Full match, mismatch, missing, unreadable, escaping symlink, directory at file path, replaced/changed file, cancellation and duplicate physical paths. No escaped read, source write or catalogue mutation. |
| FR1 UI | Compact light/dark, long paths, choosing another folder, cancellation, retry, progress and task-local errors. No Apply control; root remains unchanged on close. Record keyboard/VoiceOver acceptance separately. |
| FR2 eventual apply | Stale root/reference state, overlapping/ambiguous root, changed candidate, archive failure, commit failure and restart boundaries. Verify atomic root update, all references preserved and no mutation of media; do not claim these pass from FR1 tests. |

For native checks, opening and cancelling a picker does not establish a successful
permission grant. Use a deliberately disposable folder for actual authorization;
never reset or substitute the user's Application Support catalogue. NAS remount,
endurance, iPad/device behavior and interrupted-process recovery remain separate
acceptance, with their exact results recorded in the canonical handoff.
