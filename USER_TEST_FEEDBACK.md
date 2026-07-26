# User Test Feedback

## 26 July 2026 — first Mac/NAS smoke test

Test source: `/Volumes/PSNasP1/Music/testing` (77 audio files, zero scan errors).

### Observed

1. The MusicBrainz lookup sheet has a broken/clipped macOS layout. It must be redesigned before metadata lookup is considered ready for ordinary use. Deferred at the user's request.
2. Some source files have incomplete embedded tags. The original importer used the disc-folder name as an album title and the filename (including number and `.flac`) as the track title. The fallback parser now derives a clean title/track number, album name, artist folder, and disc number from conventional `Artist/Album [Disc 1]/01 Track.flac` paths. It applies on future metadata reads/proposals; it does not rewrite existing catalogue records or source files.
3. Switching tracks on the NAS can take five seconds or more. This is recorded as a real-world performance problem; verify after the queue fixes, then profile/prebuffer separately if it remains.
4. The volume control works.
5. Shuffle had no visible state and did not reorder the actual playback items. Fixed in the queue/controller: it now reorders the real queue while keeping the current track, has an explicit **Shuffle On** state, and can be turned off.
6. Repeat-one worked during the session, but after a relaunch the queue was not rehydrated into playable URLs, so its state was effectively invisible/unusable. Fixed by rehydrating reachable saved queue tracks after the catalogue opens; playback remains paused after relaunch and resumes only when the user presses Play.
7. Soft-deleting the first test albums retained their unique registered root-relative asset paths, correctly enabling restore but blocking creation from a corrected re-import. Fixed with a deliberately separate **Permanently Remove…** action in Settings → Recently Deleted. It is confirmation-gated, works only for already deleted albums, removes catalogue tracks/assets/references, and never touches NAS files.
8. Next-track changes over SMB took five seconds or more. The player now best-effort opens and prepares exactly the next queued audio file on a background queue while the current track plays. If preparation completes, manual Next and automatic advance reuse it; if the NAS is slow/unavailable or the user changes queue first, the player safely falls back to its normal open path. Re-test this on the NAS; actual improvement depends on the SMB server, file size, and network.

### Follow-up test after the next package

1. Use a new small test folder or a new import batch, then choose **Read Embedded Metadata**. Verify a two-disc folder creates one proposal with two discs and titles omit file extensions/leading numbers.
2. Start album playback, turn on shuffle, and confirm the control reads **Shuffle On** and Next chooses a reordered track.
3. Set Repeat All or Repeat One, quit, reopen the app, and confirm the bottom player appears with the restored queue. Press Play to resume manually.
4. Record the real NAS next-track delay again. The current change fixes an incorrect queue mapping but does not pretend a slow SMB file open is solved without measurement.
