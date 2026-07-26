# Mac, NAS, and iPad Real-World Test Guide

This guide covers the remaining acceptance checks for Phase 3 (player and playlists) and Phase 5 (snapshot distribution and the read-only iPad client). It does not change or write tags in your music files.

Use copies or a small test folder first. Do not begin with your only copy of a rare album.

## 1. Launch the packaged Mac app

1. In Finder, open the project folder.
2. Open `build/Music Library.app`.
3. If macOS blocks the first launch, Control-click the app, choose **Open**, then choose **Open** again.
4. The app opens a catalogue in its Application Support folder. It does not use a SQLite database on the NAS.
5. Keep the app open while following the tests below. If anything unexpected happens, take a screenshot and note the exact action just before it happened.

## 2. Safe test material

1. Make a small test folder containing at least two albums and six to ten audio tracks. Include one format you use often, such as FLAC or ALAC.
2. Ideally include a second format or sample rate, for example a CD-quality album and a high-resolution album.
3. If possible, make that folder available through the same NAS/SMB path you will later use normally.
4. Do not move, rename, or edit the original media during this guide.

## 3. Phase 3 — Mac player and playlists

### A. Basic playback

1. In **Settings**, add the test music folder under **Music Folders** and allow the macOS folder-access prompt.
2. In **Import Inbox**, scan that folder, review a small proposal, and explicitly create a catalogue album from it.
3. Open the album, then start a track.
4. Confirm the bottom playback bar shows the correct title and a runtime format line such as `FLAC · 44.1 kHz · 2 ch`.
5. Test **Pause**, **Play**, **Previous**, **Next**, **Stop**, the volume slider, shuffle, and each repeat mode.
6. Close and reopen the app. Confirm the queue selection and repeat mode were retained. A saved queue does not guarantee a track will still be reachable if its NAS root is disconnected.

### B. Playlist behaviour

1. Create a playlist and add at least three tracks.
2. Reorder tracks, remove one, rename the playlist, then play it.
3. Confirm **Next** follows playlist order when shuffle is off.
4. Turn shuffle on and confirm it changes only playback order, not the playlist's stored order.
5. Delete the playlist, restore it from **Recently Deleted**, and confirm its ordered items return.

### C. Media keys and Now Playing

1. While a track is playing, use your Mac keyboard's Play/Pause, Next, and Previous media keys (or the corresponding Control Centre controls if present).
2. Confirm they control Music Library rather than unexpectedly starting another player.
3. Pause and resume from the media key. Confirm the app's bottom bar stays in sync.

### D. Reliability checks

Do these one at a time and write down the result.

1. Play continuously for at least one hour; preferably repeat the test for several hours later.
2. Start a track, put the Mac to sleep for a few minutes, wake it, and try Pause/Play/Next.
3. If you use an external DAC or headphones, begin playback, disconnect the output device, reconnect it, then try playback again.
4. While a NAS-hosted track is playing, temporarily disconnect the SMB share or network. The app should stop safely and show a local playback error; it must not delete or alter catalogue records.
5. Reconnect the NAS/share and play the same track again.
6. Test at least two formats/sample rates. Record what the bottom format line reports and whether playback is audible and stable.

## 4. Phase 5 — Mac snapshot publication

1. On the Mac, open **Settings** and choose an empty test folder on the NAS as the snapshot destination. Do not use the live master-database backup folder for this test.
2. Press **Publish Snapshot**. Confirm the status reports success and the destination now has a manifest plus a revisioned catalogue JSON file.
3. Make one small catalogue-only test change, such as adding a temporary note or test album, then wait at least ten seconds. Confirm the app publishes automatically after the five-second quiet period.
4. Press Publish again without making a change. Confirm it does not create an unnecessary newer revision.
5. Repeat with four small test changes. Confirm the destination retains the current snapshot and three earlier revision payloads.
6. Do not manually edit a live published manifest. The checksum and fallback tests below use a separate copy.

## 5. Phase 5 — iPad snapshot and SMB test

The iPad app is read-only. It can browse a verified local snapshot and play only files reachable through a device-local SMB mapping. It does not modify the Mac catalogue.

1. Build and install `MusicLibraryPad` from Xcode on your iPad using your Development Team.
2. In the iPad app, choose the NAS snapshot folder using **Choose snapshot source**.
3. Press **Refresh snapshot**. Confirm that the app reports a verified local snapshot, shows an album count and revision, and lists your albums.
4. Close the iPad app, disconnect from the NAS, and reopen it. Confirm the previously verified catalogue remains browseable offline.
5. Reconnect to the NAS. Make and publish a small change on the Mac, return the iPad app to the foreground, and confirm it reports that a newer published snapshot is available.
6. Press **Refresh snapshot** and confirm the revised album list appears. The current safe design notifies first and requires this explicit refresh; it does not silently replace the cache.
7. Add an SMB root mapping on iPad: enter the published root ID shown by the catalogue, choose the corresponding SMB music folder, then open an album and play a mapped track.
8. Confirm an unmapped or disconnected root shows an error rather than trying an unsafe Mac/NAS path.
9. Favourite an album, play a track, pause part-way through, and return later. Confirm favourites, recent plays, play counts, and resume positions remain only on that iPad after a snapshot refresh.

## 6. Interrupted and corrupt-download fallback

Use a disposable copy of the snapshot folder for this test.

1. Start with an iPad that has already refreshed and can browse a valid local snapshot.
2. On the NAS, copy the published snapshot folder to a temporary test folder.
3. In the copied folder, modify or replace the revision JSON file without updating its manifest checksum.
4. On iPad, choose that copied folder as the snapshot source and press **Refresh snapshot**.
5. Confirm refresh fails with a verification message and the prior locally verified catalogue remains browseable.
6. Restore the normal snapshot source and refresh successfully.

## 7. What to report back

For every failed check, report:

- the guide section and step number;
- Mac, iPadOS, and app version;
- whether music was local or on SMB/NAS;
- the exact visible error message and a screenshot;
- whether the app remained responsive; and
- whether the catalogue, existing snapshot cache, or media files changed unexpectedly.

The expected safe outcome for any failure is: media files are untouched, the Mac catalogue remains intact, and the iPad retains its last verified local snapshot.
