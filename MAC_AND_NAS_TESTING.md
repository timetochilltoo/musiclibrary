# Mac, NAS, and iPad Real-World Test Guide

This guide covers the remaining acceptance checks for Phase 3 (player and playlists) and Phase 5 (snapshot distribution and the read-only iPad client). It does not change or write tags in your music files.

Use copies or a small test folder first. Do not begin with your only copy of a rare album.

## 1. Launch the packaged Mac app

1. In Finder, open the project folder.
2. Open the newest sequential package, currently `build/Music Library 0.45.app`. An older `/Applications/Music Library.app` installation is not automatically updated by packaging.
3. If macOS blocks the first launch, Control-click the app, choose **Open**, then choose **Open** again.
4. The app opens a catalogue in its Application Support folder. It does not use a SQLite database on the NAS.
5. Keep the app open while following the tests below. If anything unexpected happens, take a screenshot and note the exact action just before it happened.

## 2. Safe test material

1. Make a small test folder containing at least two albums and six to ten audio tracks. Include one format you use often, such as FLAC or ALAC.
2. Ideally include a second format or sample rate, for example a CD-quality album and a high-resolution album.
3. If possible, make that folder available through the same NAS/SMB path you will later use normally.
4. Do not move, rename, or edit the original media during this guide.

## 3. Phase 3 — Mac player and playlists

### R7 playlist identity/ordering acceptance (0.45)

Use disposable data. Add one track twice with a different track between them; playing the second duplicate must start at that entry, not the first, and keep the existing forward queue order/CUE boundaries. Include an unavailable track before the selected row and confirm the resolved starting index; selecting an unavailable or removed entry must show an error rather than start another copy. Soft-deleted playlists cannot be started. In Organize, first Earlier and last Later are disabled according to visible order. Remove a temporary catalogue track to create a position gap, then move adjacent remaining entries both ways: numbering/order must be contiguous after movement. Concurrently alter contents to test stale command rejection without revision changes, then Refresh Contents and retry. Test duplicate entries, wrong-playlist/nonadjacent requests, busy failures and modal cancellation. Pure plan/integration tests are not real-audio/native race proof; see HANDOFF for exact native coverage.

### R7 in-place Add Tracks acceptance (0.44)

Use the disposable navigation fixture (three synthetic, audio-free tracks in Fixture Album 240) or an isolated test catalogue. Create a playlist, open Add Tracks and search by title, album or album artist, including after restricting the global Albums search. Select a row; Cancel leaves contents unchanged, Add Selected Track closes the sheet and refreshes the playlist count/album/album-artist/duration. Reopen and add the same track: two distinct entries remain. Unknown duration is omitted, not invented. Search with a hidden selection cannot add that hidden row. Test no-match recovery, deleted targets, repeat clicks, busy dismissal and refresh failure; retry must keep the same entry UUID and not duplicate a committed add. The picker is single-selection; cover collage, track-specific credits/availability and Shuffle are pending. Native evidence is recorded in HANDOFF, separately from integration and real-audio acceptance.

### R7 playlist foundation acceptance (0.43)

Use disposable catalogue data. Create playlists with long/same names, an empty playlist and duplicate entries for one track. Search by name; no-match offers Clear Search. Counts include each entry, not unique tracks, and do not inherit global album search. Open an empty playlist: its header and controls stay visible above the empty state. Normal listening hides reorder/remove controls; Organize reveals them. Move a duplicate entry and remove one only: the other stays, and catalogue tracks/audio are untouched. Cancel removal, test repeat submissions/slow failures and confirm busy feedback. Adding/removing from album context or restoring a playlist must refresh the shared contents; switching playlists must not show the previous reader's results. Playback behavior is unchanged and real-audio acceptance remains separate. Cover collage, detailed track metadata/availability and in-place Add Tracks are not implemented in this foundation. See HANDOFF for current native evidence.

### R7 box-set acceptance (0.42)

Use disposable catalogue data. Search boxes by title, edition and full location path; no-match has Clear Search. The default navigation fixture has one box with 12 members. Its header should show inherited location/count; first-member artwork is labelled Member cover, not claimed as separate box artwork. Open an album and Back: box/scroll/Organize state remains. Enable Organize: first Earlier and last Later are disabled; moving a middle row changes order/count stays fixed. Remove requires a location or explicit unknown, cancelling preserves membership, and completing changes only placement (album stays active). Add Existing Album searches the full catalogue even after a global Albums search, excludes current members and requires confirmation when moving from another box. Test save/read failure, repeat clicks, switching route while reordering, stale contents and deleted-member gaps. Stale/nonadjacent reorder must refuse changes and offer Refresh Contents. Check empty/no-cover/same-name/long-title boxes, compact/wide, keyboard, VoiceOver and light/dark. No source audio should change. Current evidence/limits are in HANDOFF.

### R7 location acceptance (0.41)

Use a disposable catalogue only. Locations shows hierarchy and exact-location counts; the default safe navigation fixture has 228 standalone albums, one box set and 12 boxed albums. Open its shelf, inspect header and standalone rows, expand the box, open an album and Back: location, scroll and box expansion should remain. Search a full path, try no-match and Clear Search. Create nested rooms/cabinets/shelves using Add Location; child cards and ancestor breadcrumbs must navigate correctly. Parent counts do not include children. Rename/move a location and verify paths/contents refresh; move choices exclude self/descendants. Deleting a location with children/albums/boxes must show the existing refusal rather than changing placement. Test empty locations/empty boxes, same-name shelves, long paths, narrow/wide layout, keyboard, VoiceOver and light/dark. Use only disposable data for mutation checks. Current native evidence and pending checks are in HANDOFF; automated fixtures do not prove personal-library or NAS behavior.

### R7 contributor acceptance (0.40)

Use disposable catalogue data with composer/conductor/performer album and track credits, repeated credits within an album, unused contributors and two separate same-name identities. Contributors should show initials, readable roles and unique active album counts. Combine name/sort-name search and role filter; no-match has Clear Search and Role. Open a contributor: header groups name/sort name/roles/count; role choices show unique counts and cover rows identify their credit roles. Track-only credits must be included; repeated tracks and album+track copies of one role must not duplicate albums. Open a row, then Back: contributor identity and selected role remain; Back to Contributors retains browser search/role. Global Albums search must not narrow contributor counts. Shared Edit must retain its scope warning and update all uses of that identity, not merge another same-name contributor or write source tags. Delete/restore an album in disposable data and verify summaries refresh; disappearing roles clear from selection. Test long names, sparse/no-cover/uncredited entries, compact/wide layout, keyboard, VoiceOver, light/dark and rapid contributor changes. Native journey/appearance checks remain pending; fixture tests are not visual proof.

### R6 responsive player acceptance (0.39)

For **0.39 timed lyrics**, use disposable media and saved LRC such as `[00:01]First`, `[00:03]Second`, `[00:05]` (blank boundary), and `[00:07]Last`. Confirm highlighting follows playback, holds on Pause, moves backward/forward after seek, and clears while loading or stopped. Follow Playback scrolls to changed cues; turn it off to inspect/select another passage without automatic repositioning. Original LRC preserves every saved timestamp/tag; returning to Timed Lyrics follows the current position. Switch languages/versions/tracks rapidly and edit/save: no previous timeline should remain visible. Test repeated stamps, translations at one timestamp, fractional times and signed offsets. Positive offset advances cues, negative delays them. Unsupported/malformed/mixed text must show complete original text with an explanatory caption, not partially parsed lyrics. For a CUE track starting well into a source file, `[00:01]` must highlight one second after that segment's start; seek before/after its bounds must clear highlighting. Existing whole-file seek/progress behavior is unchanged. Check DSF/loading/Stop, resize, light/dark, keyboard, text selection and Reduce Motion. No line click seeks, network lookup, timer or automatic save is introduced. Native and audible acceptance remains pending.

For **0.38 manual lyrics editor**, use disposable catalogue tracks only. Open Lyrics from Album and Now Playing. Edit a saved plain/LRC version: text, language and kind must load; Save Changes replaces that version rather than adding a duplicate; unchanged Save is disabled. New Lyrics adds a separate version. Whitespace-only text cannot save; language is trimmed. Change playback while editing: Save/Delete remain bound to the original track. Dirty Close/New/Edit offers Discard/Keep Editing; keeping preserves the draft. Delete requires confirmation and removes only that version; cancelling leaves it intact. Exercise read failure/Retry and save/delete failure: errors stay visible, drafts survive, repeat clicks are blocked while pending, and retry does not duplicate a committed version. Confirm busy/dirty sheet dismissal, resizing, keyboard and light/dark behavior. No source tags or internet requests occur. Native checks remain pending; unit fixtures do not prove them.

For **0.37 saved lyrics**, use disposable tracks with plain and LRC entries in multiple languages, an instrumental track and a track without lyrics. Open Now Playing: Lyrics must match the playing track rather than the browsed album. Choose each version; plain text and raw LRC timestamps must remain readable/selectable (timed highlighting is not implemented). Empty/instrumental states are neutral, not errors, and offer Add Lyrics. Manage Lyrics opens the existing editor inside the panel. Change playback while editing: the editor title/save target must remain the track originally opened; Save updates only that track and refreshes the panel through catalogue revision. Rapid Queue selection and revisions must never show an older track's text/error. Exercise Retry for a disposable read failure, deleted/missing-track state, nested editor Close/reopen, keyboard/light-dark and compact/wide scrolling. Close/reopen never saves or changes playback. No online lookup or source tag write occurs.

For **0.36 expanded player**, use disposable catalogue/media. Start playback and choose Open Now Playing (expand arrows) beside Queue. Confirm large cover/full title, artist/album, elapsed/duration, format/loading feedback and shared controls. Opening, Close and Escape must not alter playback or queue; reopen and confirm the latest selection. Exercise inline Queue, shuffle/repeat, seek/volume, Pause/Stop and rapid loading selections. Confirm Queue is beside the card at wide widths and below it at compact widths, with scrolling and an always-reachable Close. Audio Details must open/close within the panel without closing Now Playing or leaving stale modal state. Open Album should dismiss the panel and preserve Back to origin. Test missing covers/unknown album, source-open failure/error dismissal, DSF progress, keyboard focus and light/dark appearance. Lyrics are not yet present. Asset-free navigation fixtures cannot establish these audio checks.

For **0.35 Queue selection**, open Queue from a disposable album/playlist and select a non-current entry. Confirm playback starts from that track's beginning (its segment start for CUE), the current indicator moves, and Next follows the displayed order. Under Shuffle/Repeat One/Repeat All, select another entry and confirm order/preferences remain unchanged; selecting the current entry restarts it. Select again while loading a slow file/DSF, including two positions of a repeated track: only the latest title/artwork/progress/error may win. Stop during loading must prevent late callbacks from restarting playback. Unresolved rows are disabled; source-open failure uses existing playback error and permits another selection/retry without deleting membership. Close/reopen Queue must not play anything, and app relaunch restores selection/preferences without autoplay. Test keyboard activation and compact/wide layouts. Queue editing/Play Next is not implemented. Earlier read-only-row expectations below apply only to 0.33/0.34.

For **0.34 identity/navigation**, play tracks from two differently covered albums in a disposable playlist. Browse/search an unrelated album while playing: mini-player cover, artist and album must still match the current track. Rapidly advance across albums during slow cover/loading reads; no older cover or identity may overwrite the latest selection. Click cover/title from Albums, Contributors, Box Sets, Imports, Settings, Playlists and Locations; confirm the correct active album opens without restarting/changing playback, and Back restores the origin. Resize while doing so. Missing artwork uses a placeholder but retains navigation when the album exists; a deleted/unknown album disables navigation. Stop/relaunch must retain selection without autoplay. Light/dark and keyboard/VoiceOver checks remain required; synthetic navigation fixtures without assets cannot establish playback identity acceptance.

Using a disposable catalogue and audio fixtures, play a multi-track album. Resize between wide and minimum supported window widths: the compact player must show identity/transport/Queue/Options above full-width progress, with no clipped controls. Open Options and exercise volume, shuffle, repeat, metadata and Stop; Pause stays directly available. Check keyboard navigation, labels, light/dark appearance and clearance below the last album track. Seek and elapsed/duration should remain correct. With a disposable DSF fixture, retain percentage/time estimate and cancellation behavior while resizing. Queue must show actual shuffled order, count and current-entry indicator, scroll to the current entry when opened/advanced, and never begin playback merely by opening it. Rows are deliberately read-only; no selection/reorder commands are claimed. Stop retains the queue; reopening the app must not autoplay. A fixture without digital assets cannot establish these audio acceptance checks. Do not use the personal catalogue/media for automated checks.

## 3.0 Catalogue cleanup and complete archive

Use ordinary test records only for this section. None of these actions should touch source audio.

1. In **Settings > Catalogue Maintenance**, press **Review Safe Cleanup…**. Confirm the review separately counts old completed scan history, unlinked contributors, and unused physical locations. Untick one category and confirm the selected total changes.
2. Press **Create Recovery Archive and Clean Up**. Confirm the status reports how many rows were removed and names a local recovery archive. Confirm albums, tracks, playlists, registered music folders, linked contributors/locations, covers, and playback still work. Reopen the review and confirm removed categories now show zero.
3. Press **Export Complete Catalogue Archive…**, choose an empty test destination, and confirm one `.musiclibraryarchive` folder appears. It must contain `manifest.json`, `MusicLibrary.sqlite`, and an `Artwork` folder. It must not contain audio files from registered local/NAS music folders.
4. Make one obvious disposable catalogue-only change after export, such as adding a test album. Choose **Restore Complete Catalogue Archive…**, select the archive folder, and approve restore. Confirm the post-export test change disappears, the archived albums and managed covers return, registered roots reopen, and source media remain unchanged.
5. To test corruption refusal, duplicate the archive, change or delete one copied artwork file, then try to restore the damaged duplicate. Confirm verification fails before the live catalogue changes; the currently open catalogue and artwork must remain usable.
6. Test **Reset Catalogue…** only if you intentionally want to clear the test catalogue. Confirm the button remains disabled until `RESET` is typed exactly. After reset, albums/import history/managed covers are gone but registered music folders remain and can be rescanned. The status must identify the automatic pre-reset recovery archive. Do not run reset against a catalogue you have not backed up and intend to retain.

## 3A. Library Changes rescan choices

1. Open **Library Changes** and select a completed batch for a registered folder.
2. Press **Retry Scan**. Confirm a fresh batch is selected immediately and its status/counts update without selecting the folder again. Confirm that already-catalogued files remain in **Scan diagnostics**, not in a new metadata proposal.
3. If the scan reports **New audio files**, press **Read Metadata for New Files**. Confirm proposals appear only after this explicit action; the catalogue and source files remain unchanged until you press **Create New Edition** or complete **Attach to Existing Edition**.
4. Repeat with **Rescan and Read Metadata for New Files**. Confirm the app selects the new batch, waits while it scans, and then automatically performs the metadata pass once the scan completes. Confirm the resulting proposals are the same new-file-only proposals that the two separate actions would produce.
5. Repeat the combined action on a folder with no new files. Confirm it completes without creating duplicate proposals. If the scan is cancelled or fails, confirm metadata is not read automatically and the user can retry explicitly.

### A. Basic playback

1. In **Settings**, add the test music folder under **Music Folders** and allow the macOS folder-access prompt.
2. In **Library Changes**, use **Rescan and Review New Files**, review a small proposal, and press **Create New Edition** once. Confirm the album is created without a separate **Approve for Later** step and the proposal shows its created state.
3. Open the album, then start a track.
4. Confirm the bottom playback bar shows the correct title and a runtime format line such as `FLAC · 44.1 kHz · 2 ch`.
5. Test **Pause**, **Play**, **Previous**, **Next**, **Stop**, the volume slider, shuffle, and each repeat mode.
6. Close and reopen the app. Confirm the queue selection and repeat mode were retained. A saved queue does not guarantee a track will still be reachable if its NAS root is disconnected.

### A0. Manual physical album

1. Open **Albums** and choose **+**. Confirm the single **Add Physical Album** workspace opens at Find with a visible **Enter Manually** fallback.
2. Search MusicBrainz by title and optional artist, select the correct release/pressing, and review its label, catalogue number, barcode, media format, disc count, cover, and track listing. Press **Use Selected Release** and confirm those returned fields plus the primary artist contributor fill Review. Confirm the cover preview and **Save cover with album** option appear; leave the option on to test managed cover import, or turn it off to add the album without artwork. Confirm location, notes, and additional role credits remain unchanged; no album is created yet.
3. Enter or correct edition/release data as needed. Add at least one contributor and choose its role. Use **Add Contributor** to add a composer/performer/conductor, and try **Use Existing** for a catalogue name already present.
4. Continue to **Your Copy**. Under **Physical Location**, test each explicit placement type: choose an existing location; create and select a new nested location; choose an existing box set; and choose **Set location later**. The final Add button must remain disabled until title, meaningful credits, years and selected placement are valid.
5. Add physical and catalogue notes, then save. Confirm the album appears with CD availability, its contributor appears under Contributors, and its location or inherited box location is shown. Search for it by contributor, barcode, and location.
6. Confirm the new physical-only record has no digital play controls or queue entry. If **Save cover with album** was enabled, confirm the selected MusicBrainz front cover appears in the album artwork and Library Health no longer reports missing front artwork. Add local artwork or optional manual disc/track details from Album Detail if desired; no source folder or player file should be touched.

#### R4a physical-entry workspace acceptance

Use the disposable real-shell fixture described below, not the personal catalogue. Add Physical Album opens Find; Enter Manually opens Review. Enter a title and named credit, leave an extra default credit blank, and check that it does not block Continue. Invalid years such as `1993x` must show a visible requirement and block Continue; blank years are valid. Go to Your Copy, choose Set location later and add notes/rating. Back must retain everything. Add Album must show progress, prevent duplicate clicks, close the workspace and open the saved physical-only album. Cancel a changed draft must offer Keep Editing/Discard Draft. Creating a location is an explicit immediate write and survives draft cancellation.

For online acceptance, search/select a release, return to Find, and select another: confirm replacement warns about changed fields and clears missing values without losing copy notes or extra role credits. Test unavailable service/manual fallback and failed cover download followed by retry or explicit Save without cover. Barcode/URL lookup and track-list creation are not part of R4a. Check the sheet at its 720×560 minimum and larger sizes, including long titles, dense credits, light/dark appearance and keyboard navigation.

#### R4b lookup modes

In Find, use **Barcode** with a leading-zero barcode (digits only), **Catalogue Number** with an optional artist, and **Release URL** with an exact `https://musicbrainz.org/release/<UUID>` link. Only Search triggers lookup; no catalogue data is saved until Add Album. Switch modes during a slow request: old results/errors must not appear under the new mode. Switching back retains that mode's input. Check empty and invalid inputs, no matches, offline failure, and matching-pressing review. Release-group/artist/untrusted-host/credentialed/malformed URLs must fail without fetching the pasted address. A failed lookup must not claim a successful zero-match search. Compare provider fields and cover against the selected pressing. Physical-entry release references, duplicate suggestions and optional structured tracks are available as described below.

#### R4b duplicate suggestions and release references

In a fresh disposable navigation fixture, enter `Fixture Album 001`, album artist `Fixture Orchestra`, and barcode `0077` manually. Review must show the existing album with barcode/title/artist evidence and block Continue until **Add Separate Edition** is chosen. **Open Existing Album** must confirm draft discard, then open the original without creating another record. Repeat and choose Add Separate Edition, Set location later, Save: the new record opens without changing the original. Title alone or a different artist must not produce this fallback suggestion. Changing the evidence/suggestions resets the separate-edition choice.

On disposable online data, select a real MusicBrainz release, disable its cover if desired, and save. Check the Album Detail release link, reload, then select the same release again: exact-ID evidence must take priority even if local title/artist were changed. Both deliberately separate records may retain the same ID. Clearing the selected release before Save must not persist that reference. No merge or audio/tag write is permitted. Migration, rollback and delete/restore behavior are covered by automated temporary fixtures; do not run destructive acceptance on the personal catalogue.

#### R4b optional structured tracks

The Debug navigation fixture now uses a deterministic synthetic metadata provider, not live MusicBrainz. Any entered lookup returns **Synthetic two-disc release**. Select it and verify separate Original/Bonus disc groups, A1/A2/B1 printed positions and 2:03/1:02/3:00 durations. Use Selected Release, disable Save cover with album (thumbnail display still requests the normal cover service), and confirm Include track listing is initially off. Expand Review discs and tracks; enable inclusion and confirm disc count is fixed at two. Continue/Back must retain the choice; changing/clearing release must reset it. Save with Set location later: the new detail must contain two discs and three tracks, with no Play/queue action or digital copy. Repeat without inclusion and confirm no tracks are created. Check compact and wide layout, scrolling, keyboard and light/dark appearance. For live-provider/cover recovery acceptance use a separately composed disposable store with the production provider; this synthetic lookup does not establish online correctness.
7. Edit the album and confirm label, barcode, remaster year, media format, physical note, general notes, and location remain correctable. Contributor credits are edited from Album Detail.

### A1. Dock icon and slow NAS/DSF loading

1. Confirm the packaged **Music Library** app shows the vinyl/CD/library icon in Finder, the app switcher, and the Dock rather than a generic executable icon.
2. Start an ordinary local track, then select a large DSF track on the NAS.
3. Confirm the old track stops promptly and the player displays `Now Loading “song title”…`. During an uncached DSF conversion, confirm it shows a determinate progress bar, percentage, and (after a short measurement period) an approximate time remaining. The window must remain interactive and should not show a sustained rainbow pinwheel.
4. When the conversion reaches 100%, confirm the message changes to **DSF conversion complete — preparing playback** before playback begins. This final stage has no percentage because AVFoundation does not expose its byte progress. Replaying the same DSF may skip the visible conversion because the private PCM cache already exists.
5. While that track is still loading, select a different playable track. Confirm the newest selection is the one that eventually plays; the older slow request must not take over later.
6. Repeat once with the NAS disconnected. Confirm loading ends with a local playback error and no catalogue record, source file, or queue membership is deleted.

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
## Isolated UI navigation checks

For development, run `Scripts/run-navigation-fixture.sh` from the repository root. It explicitly builds Debug, resolves the current binary path, and launches a separately identified temporary app with `--navigation-fixture`. Never substitute a historical cached executable: old binaries can ignore fixture flags and start the normal catalogue. Current launch routing recognizes fixture bundle identifiers on argument-free reopen; Release refuses fixture bundles/flags. Regression tests cover both paths. Avoid asking UI tools to inspect a quit app unless explicitly testing relaunch: they may launch it again.

The fixture runs the actual Mac shell over a newly generated temporary SQLite catalogue: 240 **Fixture Album** records, **Fixture Orchestra**, **Fixture collected editions**, and **Fixture shelf**. It contains no source-media roots or digital assets, and background publication/backup resolution is disabled. Verify these synthetic names before interacting. Its app identifier isolates browse/player preferences from the normal app. Do not select personal folders, contact providers, or use reset/restore/FLAC/cache-maintenance actions during these navigation checks.

Check contributor → album → Back after scrolling; box-set → member → Back with the Add Existing Album toolbar restored; Settings Advanced → health album → Back with the same category; and sidebar changes during detail without stale album resurrection. Exercise grid/list, long-title search, no matches, and filter clearing at the 980-point minimum content width. Quit only the fixture when finished. Its database and app are temporary; this is not a live NAS, artwork-decode, or measured frame-time performance test.

### R5a disposable import-review acceptance

Album-origin acceptance: open **Fixture Album 001** → Attach Digital Files → choose the synthetic import batch and a pending candidate. Confirm the target is fixed, its pairing is shown, and Attach requires acknowledgment. Close before saving: no changes should occur. Reopen, acknowledge and attach; Done must return to the same album with the new catalogue track and no playable source file, no new album, preserved metadata/credits and no source writes. Added/skipped candidates must not appear. Test missing target, batch switching, no pending candidates and stale previews. On disposable media separately, explicitly Scan Registered Folder, verify start-click guarding and progress/Cancel, then explicitly Read Metadata before selecting a candidate. Closing must retain the scan/proposals in Imports. No new folder registration should occur here; unregistered/outside-root album folders must fail safely. Mismatch alternatives must go to Imports without writing. Do not scan/export real media in the synthetic offline fixture. Native/appearance/keyboard and live scanner acceptance remain pending.

R5b inline attachment: in a fresh import fixture, select a pending candidate → Link to Existing Album → search/select **Fixture Album 001**. Verify every imported file and its new-track mapping; Attach stays disabled until the pairing acknowledgment is checked. Change target after acknowledging: preview and acknowledgment must clear, and an older response must not restore them. Cancel must leave the album count and proposal unchanged. Acknowledge/Attach to the empty fixture album, then confirm Linked/Open Album, Back to the retained review, and Added category membership without a new album. Retry must not create another asset/revision. Populating an empty album may update its modification timestamp and disc structure, but existing identity/credits/edition/artwork remain preserved. On disposable populated targets, verify mismatch disables Attach and offers matching review or separate-album return; stale compatibility/path conflicts must fail without partial writes. Exercise search/no matches, source-path disclosures, minimum/wide layout and keyboard/appearance. Native automation is still blocked; this checklist is not yet a visual pass.

R5b shared inline lookup: use Find on MusicBrainz on a pending fixture candidate. Check that lookup expands in place, offers all four modes and displays synthetic full release details after Search. Choose for Comparison should close lookup and reveal unchecked field comparison, leaving proposal fields and album count unchanged. Its three synthetic MusicBrainz tracks versus one imported track must disable track-title application. Close lookup during search or switch candidates: old results must not populate another candidate. Choosing a release should block Add/Skip/candidate changes until the fetch/save finishes; failure should permit retry. Repeat physical entry's Find to guard its shared-component behavior. Native inspection remains pending because of the automation-helper crash. The fixture's synthetic lookup returns the same deterministic release for all modes; trusted input validation and provider dispatch use the automated transport tests, not this UI fixture. Do not export/download covers during offline fixture acceptance. Separately test live provider failure, replacement, compact controls and explicit Save Cover JPEG (a chosen copy only, not catalogue approval).

R5b inline field-review addition: the fixture now seeds one explicitly synthetic MusicBrainz selection on the Needs Review candidate, without contacting any provider. Select it and confirm the comparison appears in the review area with every toggle off and Apply disabled. Check only Album title, Apply, and confirm the proposal title changes without creating an album or changing artist/disc count. Choices should clear; Add remains separate. Expand the track comparison, exercise field choices at narrow/wide widths, and check keyboard/appearance. The fixture has no managed artwork store, so cover Apply produces an inline error: choices must remain available, and unchecking cover must permit applying other selected fields. Do not contact a live provider in these isolated checks. Live-provider release replacement and real cover download/retry remain separate acceptance items. The user reports R5a works; automation still fails opening this screen, so R5b visual acceptance is not yet verified.

Run `Scripts/run-navigation-fixture.sh --import-review-fixture` to create a fresh isolated import variant. Verify synthetic album names before interaction, then Imports → **Synthetic import review — no source audio files**. Unlike the default fixture, this variant has one empty temporary offline root, four synthetic file references and 241 albums (one candidate was already added). No audio files exist. Never select personal folders, rescan real media or enable maintenance actions. Argument-free fixture relaunch creates the default isolated catalogue, not the import variant or personal catalogue.

1. Confirm All has four candidates and Needs Review, Ready, Added and Skipped initially have one each. Ready must still require explicit Add/Link.
2. At minimum width and wide width, switch candidates/categories; check title, summary, grouped tracks and non-overlapping controls. Expand source Details and Scan and File Details; collapse them to restore a focused review area.
3. Skip Needs Review, verify advancement and Skipped membership; Return to Review restores it without creating an album.
4. Add a pending candidate, verify success/Open Album and advancement. Back returns to the batch with the category/candidate retained. Reopening an added candidate offers Open Album, not another Add. Confirm retry does not create duplicates.
5. Change sidebar and return; verify selection/category restoration. Check empty categories, keyboard navigation and light/dark appearance. Reading metadata must block candidate mutations until completion.
6. Link still opens the existing pairing dialog; verify cancel is non-mutating and incompatible targets are refused. MusicBrainz still opens its existing lookup/comparison dialogs and must remain explicitly invoked. Online comparison integration and album-origin attachment are pending R5b, not acceptance of this slice.

Automated fixture tests verify the source root stays empty after explicit Add/Skip/retry. Native checks are currently incomplete: the UI automation helper crashes when traversing Search results or opening Import Review (see HANDOFF.md). A failed inspection is not a passed layout check. Perform manual acceptance on this disposable fixture if automation remains unavailable.
