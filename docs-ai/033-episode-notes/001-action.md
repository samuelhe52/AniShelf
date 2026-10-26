# 033 — Episode notes with scope chips: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-26 | Record design A and the persistence/sync acceptance criteria before implementation. | `4b0898c` |
| 2026-10-26 | Add the V2.8.5 schema, independently clocked episode-note values, sync, user snapshots, export, conversion/duplicate preservation, and note statistics. Review corrections are folded in. | `b9c2cf1` |
| 2026-10-26 | Replace the two existing notes sections with shared scope chips; add the overview, picker, note moves, swipe-to-edit episode rows, the episode-note sheet, translations, and local fixture episode rows. Review corrections are folded in. | `d0f74e9` |
| 2026-10-26 | Keep sibling seasons linked to the new hidden parent when a series converts to a season. | `c67cba1` |
| 2026-10-26 | Open on All, shorten and reverse the episode strip, pin creation controls, and resolve the macOS fade-mask rendering regression. | Same commit as [003 amendment](003-compact-strip-and-macos-fade.md) |
| 2026-10-27 | Default to Overall when no nonempty episode notes remain, including after deleting the last episode note; reconcile existing documentation in [004 amendment](004-overall-default-without-episode-notes.md). | Same commit as 004 amendment |
| 2026-10-27 | Add iOS swipe navigation between scopes; follow up on reported skipping in All by replacing its simultaneous drag with discrete swipes. | Same commit as [005 amendment](005-swipe-scope-navigation.md) and [006 amendment](006-return-to-all.md) |
| 2026-10-27 | Add a small All return button at the bottom-right of inline episode and Global/Overall editors on iOS and macOS for entries supporting episode notes. | [006 amendment](006-return-to-all.md) |

## Outcome and current state (as of 2026-10-27)

- Overall notes keep their original entry-specific meaning. Movies retain the overall editor alone.
- Series and season views share one evolving note per season/episode anchor. Season zero and episodes absent from metadata remain valid. Empty text is retained as a timestamped deletion marker. Note changes do not advance the unrelated tracking-field clock.
- The inline Notes section keeps a bounded content area and one chip row. It opens on All only when the entry supports episode notes and has at least one nonempty episode note, otherwise on Overall. The same default applies when entry identity changes or the selected episode note is deleted. If the last nonempty episode note disappears while viewing All, the selection switches to Overall; a selected empty episode draft stays open while typing. Selection is local to the view, with no per-entry preference persistence. All remains manually selectable for entries supporting episode notes. All, Overall, and populated episodes scroll horizontally; the suggestion and Other… stay fixed on the trailing side. Episode chips use compact `E13` / `S2E13` labels and descending season/episode order. A 16-point gradient mask fades the scroller; only macOS disables capsule-background vibrancy to prevent black `.fill.tertiary` fills. See [003 amendment](003-compact-strip-and-macos-fade.md) and the [default-scope correction](004-overall-default-without-episode-notes.md).
- Inline All shows populated Overall first, followed by episodes in descending season/episode order. An empty All offers an Overall placeholder that opens the editor. Selecting a section returns to the editor; Expand opens the existing larger reader, whose ordering was not changed by the strip follow-up.
- On iOS, left/right swipes inside the inline content advance/go back one displayed scope, stopping at either end. The suggested-note and Other… creation controls are excluded. The All overview correction uses discrete swipes that cancel row taps and directly target Overall on a left swipe; its runtime behavior remains unverified. See [005 amendment](005-swipe-scope-navigation.md).
- Episode and Global/Overall editors on iOS and macOS show a small All button at the bottom-right when episode-note support makes All available, matching the overview's Expand position. It selects All directly and reuses the existing localized title. Movie editors retain their existing layout. See [006 amendment](006-return-to-all.md).
- Episode chips and reader sections offer Move to Episode… and Delete Note. A move writes the new anchor and leaves a deletion marker on the old one; an occupied target asks before combining. Once episode metadata has loaded, a note whose episode is missing from it shows a "Not in Episode List · Move…" hint.
- Episode rows offer Add/Edit Note as a swipe action on iOS, a context menu on macOS, and an accessibility action. Long press stays the iOS preview gesture; the preview shows existing note text and hands off to a separate editor sheet after the popover closes. Cancel leaves the saved text unchanged; Save and Delete Note update the shared note, and a whitespace-only draft for a new note saves as a no-op. Open note sheets block detail-host migration.
- A season whose parent series link is missing hides every episode-note entry point. Opening its detail runs a silent single-entry metadata refresh once per launch that relinks or recreates the parent; when the owner appears, the Discard baseline adopts its existing notes.
- Pasting user info never changes the target's episode notes, and the paste-overwrite confirmation ignores them; copied text still carries them.
- Revert restores only the selected note. The existing detail Discard action restores the season-scoped episode-note snapshot as well as the overall note. Restoring changed episode text advances its clock so already-synced edits cannot override the revert.
- JSON exports contain structured notes, tabular exports append an `episode_notes` JSON column, and plain-text exports label episode notes. A season-only export includes its parent-owned notes for that season. The With Notes statistic includes entries with episode notes.

Key source files:

- `DataProvider/Sources/DataProvider/Models/Other/EpisodeNote.swift`
- `DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift`
- `DataProvider/Sources/DataProvider/Models/V2/SchemaV2_8_5.swift`
- `DataProvider/Sources/DataProvider/MigrationPlan.swift`
- `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSheets.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EpisodeNoteEditor.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore+Entries.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryEntryConverter.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryDuplicateRepair.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift`
- `MyAnimeList/Sources/Utils/LibraryExportManager.swift`

## Deviations from plan

- Chip selection first used per-entry scene storage; the initial 2026-10-26 plan amendment replaced it with device-wide per-entry memory before the UI rework. The later [compact-strip amendment](003-compact-strip-and-macos-fade.md) removed that memory in favor of local view state and All-on-open. The [2026-10-27 correction](004-overall-default-without-episode-notes.md) uses Overall when no nonempty episode notes remain.
- Added local episode summaries to the existing library fixture. Its generated series IDs cannot resolve on TMDb; local rows enabled actual episode-note interaction checks without credentials or real library data.
- Visual inspection caught missing visible labels on the numeric episode picker. Explicit Season/Episode labels were added and rechecked in the simulator.
- A deletion-clock review found that a season tombstone must inspect the concrete row's note clocks rather than the shared parent's notes. Corrected and covered by a focused test.
- Post-implementation reviews found and corrected, each folded into the commit it fixes:
  - The dirty-queue revision was the newest field clock, so an edit made behind a note with a future clock left the queue entry unchanged and an in-flight export could dequeue it. Each detected edit now outranks the queued upsert (regression test in `LibrarySyncCoordinatorTests+Export.swift`).
  - Series-to-season conversion replayed a pre-fetch snapshot through `restoreEpisodeNotes`, reverting note edits received while TMDb loaded. It now keeps the parent's current notes (extended conversion test).
  - Each per-anchor lookup decoded and sorted the whole payload, which made rendering quadratic in note count. The last decoded payload and an anchor index are now cached by payload bytes, outside the SwiftData model.
  - Parentless seasons offered note entry points whose save silently failed; see the ownership bullet above and the plan amendment.
  - The editor kept a whitespace-only new note open, because Save stayed enabled but the normalized save was a no-op.
- Series-to-season conversion deleted the old series row while sibling seasons still pointed at it, leaving them without a parent, its metadata, or their episode notes. This predates episode notes; it is fixed separately in `c67cba1`, with rollback coverage.

## Validation

| Check | Result |
| --- | --- |
| `make test-dataprovider` | Passed: 68 LibrarySync tests and 72 DataProvider tests, including V2.8.4 migration and store reopen. Recovery tests intentionally emit diagnostics for invalid fixture stores. |
| `make test-dataprovider DATAPROVIDER_TEST_FILTER='EpisodeNoteTests'` | Passed: 5 tests after adding the shared-parent/season-deletion regression case. |
| `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryExportManagerTests MyAnimeListTests/LibraryRelationshipAndConversionTests MyAnimeListTests/LibrarySyncRecorderBehaviorTests MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/UserEntryInfoAndLibraryStatsTests'` | Passed: 54 cases. |
| `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/EntryDetailSessionTests'` | Passed: 27 cases, including duplicate annotation preservation. |
| `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/UserEntryInfoAndLibraryStatsTests MyAnimeListTests/EntryDetailViewModelTests'` | Passed: 53 cases after the final picker and fixture changes. Counts overlap earlier runs. |
| `make build-mac` | Passed, including a final build of the complete UI and picker-label fix. Mac app was not launched. |
| Post-review runs (after the UI rework and review fixes) | `make test-dataprovider DATAPROVIDER_TEST_FILTER='EpisodeNoteTests\|LibrarySyncTests'` passed 69 tests. `make build-mac` passed. On the simulator, `LibraryRelationshipAndConversionTests`, `EntryDetailViewModelTests`, and `LibraryMetadataRefreshTests` passed; `LibrarySyncCoordinatorTests` passed except `categoryDefinitionsRoundTripThroughSettingsPayload`, which fails on its first category-default assertion even in isolation and is unrelated to this work. The conversion regression test was confirmed to fail with its fix reverted. |
| `make run-sim DEVICE_PROCESS_LAUNCH_ARGS='-library-fixture 24'`, followed by `make launch-sim` after final test builds | Passed on the already booted iPhone 18 Pro / iOS 27.0 simulator. |
| `sim-use` interaction and screenshot checks | Verified suggested-chip selection, Unicode note entry, All, expanded overview, selection back into the editor, another season through Other, final picker labels, episode-row Add/Edit marker, preview-to-editor handoff, Cancel, and saving/reopening the detail. Screenshots were inspected locally and are not retained in Git. |
| Localization and diff checks | All new keys have Japanese and Simplified Chinese translations; `git diff --check` passed. |
| Later compact-strip and macOS fade follow-up | Multiple `make run-mac` builds and fixture launches succeeded. The maintainer confirmed removing the mask restored badge appearance, rejected the overlay/native-edge experiments, and accepted the gradient mask with capsule vibrancy disabled. The final macOS-only guard was not rebuilt. Full evidence and iOS limits are recorded in [003 amendment](003-compact-strip-and-macos-fade.md); the earlier test results above are not fresh validation of this follow-up. |
| 2026-10-27 default-scope correction | `make build-mac` and `make run-sim` passed. On the already booted iPhone 18 Pro simulator, `sim-use` confirmed an entry with an overall note and no episode notes opened with the Overall editor. Last-note deletion and entry-switch behavior were checked in source, not exercised in the UI. No automated tests were added or run for this fix. |
| 2026-10-27 scope swipes and All correction | The initial swipe implementation passed `make run-sim` and `make build-mac` after fixing an initial compilation failure. Limited simulator interaction and initial maintainer acceptance were followed by a report of skipping in All. Its correction passed `make build`, `make build-mac`, and the diff check; no further runtime checks or automated tests were run. See [005 amendment](005-swipe-scope-navigation.md) for evidence and limits. |
| 2026-10-27 return-to-All button | `make build` and `make build-mac` passed, including reruns after extending the button to Overall; diff and documentation-link checks passed. No runtime checks or automated tests were run for this local UI wiring change. See [006 amendment](006-return-to-all.md). |

Initial incremental package attempts failed to compile. Rerunning without `--quiet` exposed missing `try` and use of app-only user-info convenience helpers in the new package tests; these were corrected before the successful runs above. The simulator's Japanese IME altered an initial hardware-keyboard test string; native Paste then entered and verified the intended Unicode text. A transient edit-menu readiness error was resolved by targeting the editor's native menu. These automation failures were not app crashes.

## Open questions and release follow-ups

- The All overview swipe correction is present in source but has no post-fix runtime acceptance; the competing-row-tap explanation is inferred from source rather than an observed event trace. See [005 amendment](005-swipe-scope-navigation.md).
- Production CloudKit sync and two-device convergence were not exercised. Verify/promote the new `LibraryEntry.episodeNotes` Bytes field in the release environment before distribution; sync schema version 4 causes older clients to quarantine new snapshots rather than overwrite note state.
- The initial feature validation compiled native macOS without launching it. The later [compact-strip follow-up](003-compact-strip-and-macos-fade.md) built and launched the Mac fixture repeatedly and obtained maintainer visual acceptance of the fade fix before its final platform guard. Complete pointer/keyboard interaction and narrow-inspector acceptance remain unverified. No device was booted and no physical device was used for that follow-up.
- Host-migration blocking is implemented; a fold/unfold interaction while a notes draft is open was not exercised.
- The simulator interaction checks above predate the swipe-to-edit rework; validation of the reworked UI was not recorded here. The parent-restore and Discard-baseline paths have no automated coverage and were not exercised in the running app.
- Update episode-note feature copy and, when selected, refreshed screenshots in `../anishelf-site`. That repository was not edited.
- No commits were pushed and no release or production schema deployment was performed.
