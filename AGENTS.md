# Music Library agent guidance

## Resume and source of truth

- Read [`HANDOFF.md`](HANDOFF.md) first when resuming work. It is the canonical operational handoff and records the current next slice, validation status, and blockers.
- For architecture, schema, and invariants, use [`IMPLEMENTATION_SPEC.md`](IMPLEMENTATION_SPEC.md). Use [`BUILD_PLAN.md`](BUILD_PLAN.md) for product scope and acceptance goals.
- Check `git status --short --branch` and recent history before editing. Preserve existing user changes and do not copy historical progress into this file.

## Project invariants

- macOS is the sole catalogue writer. The iPad/client targets are read-only and may keep only device-local preferences.
- The live SQLite catalogue stays on the Mac. Never open it directly from SMB/NAS; publish verified snapshots instead.
- Keep SQLite access in `MusicDatabase` and application use cases in `LibraryStore`/services. SwiftUI views must not compose SQL or mutate the database directly.
- Scanning, matching, catalogue corrections, artwork migration, and relinking must not move, rename, delete, upload, or retag source audio automatically. The explicit FLAC tag-write workflow is opt-in and must retain its backup/journal protections.
- Preserve root-relative asset paths and offline references. A disconnected NAS root must not cause assets to be marked missing or deleted.
- Cleanup, reset, and archive restore are safety-sensitive: preview first where supported, create the required verified recovery archive, preserve registered storage roots on reset, and require the exact typed reset confirmation. Complete archives contain the catalogue database and managed artwork, not source audio.
- Automated validation must use temporary fixtures. Do not open, reset, delete, or rewrite the user’s Application Support catalogue or source media during development checks. Use disposable data for destructive acceptance tests.

## Build and test

Run these from the repository root:

```bash
swift test
swift test -c release
swift build
git diff --check
```

Add focused domain/persistence/application tests for new behaviour. For functional slices, update the relevant implementation/status documentation and the next action in `HANDOFF.md`; do not turn this file into a changelog.

The project is a Swift package with macOS and iOS targets. Regenerate `MusicLibraryPad.xcodeproj` with `xcodegen generate` only when its generator inputs change. When a user-facing Mac app artifact is requested, use `Scripts/package-mac-app.sh`; its version comes from `Packaging/MusicLibraryMac-Info.plist`, and the resulting bundle should be checked with `plutil -lint` and strict `codesign` verification. Do not add release archives, notarization, or extra architectures unless requested.

## Delivery discipline

- Keep changes incremental and review the final diff for unintended files, secrets, user data, `.build`, derived data, SQLite WAL/SHM files, and local media before any checkpoint.
- Do not silently expand deferred scope such as automatic relinking, non-FLAC tag write-back, internet lyrics providers, AI modules, live NAS endurance, or iPad device validation; resolve those choices explicitly and record them in the handoff.
