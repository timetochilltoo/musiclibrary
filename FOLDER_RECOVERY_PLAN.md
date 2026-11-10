# Music folder recovery plan

Status: design checkpoint, 10 November 2026. **Not an implemented relocation feature.**

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

## FR1 — next implementation slice: read-only replacement preview

Add **Review Replacement Folder…** beside an unavailable root's existing access
actions. The sheet explains the registered name/path and asks the user to select
the directory that contains the same relative layout. Selection alone does not
start verification, persist a bookmark, change root status or start an import.

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
