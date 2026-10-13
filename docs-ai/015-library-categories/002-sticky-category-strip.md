# 015.002 — Optional sticky category strip

## Context

The first delivery removed the category strip (see [001-action.md](001-action.md)):
a strip hidden until a pull felt non-linear, and an always-visible strip was
rejected as the default. On 2026-10-13 the maintainer chose to offer an
always-visible strip as an option, modeled on Telegram's chat folder tabs.

## Change

Decisions taken by the maintainer on 2026-10-13:

| Choice | Decision and alternative |
| --- | --- |
| Where | List and Grid only. Gallery keeps the title capsule menu. |
| Setting | A plain on/off toggle under "Library Categories" in Settings › General, shown only when categories are on, off by default, cloud-synced like the other library preferences. |
| Placement | Pinned under the navigation bar, always visible while on. No pull-to-reveal; that interaction was the reason the first strip was removed. |
| Tab style | Telegram text tabs: "All" first, then categories in display order, scrolling sideways, with a tinted underline that slides to the selected tab. Capsule chips were rejected. No counts on tabs. |
| Long press | Telegram menu: a category tab gives Reorder, Rename, Edit Categories…, Delete; "All" gives Reorder and Edit Categories…. Reorder makes the tabs draggable until Done; "All" stays first. "Menu only" was rejected. |
| Swipe content | No. Sideways swipes on the List or Grid do not switch category; they would compete with List swipe actions. |
| Title capsule | While the strip shows (List or Grid with the option on), the capsule shows the plain title with no category name and no menu. Gallery and strip-off keep the capsule menu. |
| Multi-selection | The strip hides during multi-selection, like the capsule menu, because switching category would drop selected anime outside the view. |

Implemented as a full-width `.bar` material surface in a top safe-area inset.
The strip uses text buttons, a matched-geometry underline, and scrolls the active
tab into view on selection, definition/order changes, and reorder-mode changes.
The inset and the title capsule share one visibility condition. Neither the
selection snapshot pipeline nor the List row gesture mask changes.

`LibraryCategoryStripEnabled` defaults to false and follows the existing library
preference path: store reload/save, backup allowlist, cloud allowlist, and bool
settings payload. Settings shows the toggle only while categories are enabled;
disabling categories retains the strip preference. Rename and Delete reuse the
existing category dialogs, and Edit Categories opens the existing manager sheet.

### Implementation choices and deviations

- No product-decision deviations. Reorder uses native SwiftUI `draggable` and
  `dropDestination` on category tabs only. Dropping onto another tab calls
  `store.moveCategory`; the destination is highlighted during hover. Order commits
  on drop instead of changing during hover, so cancellation leaves order intact
  and moving drop targets cannot oscillate beneath the pointer. A per-reorder-mode
  token rejects unrelated text and drags from another window or an earlier mode.
  All has no drag source or drop destination; Done exits the mode.
- Native horizontal dragging was chosen over a custom pan recognizer to leave
  horizontal scrolling with the system and avoid competing gestures. Its actual
  edge scrolling and feel remain for the maintainer's UI checks; no manual drag
  walkthrough was performed.
- The original delivery's removal history remains in `001-action.md`; its stale
  next-step note now links here. The index links this amendment.

## Refs

- Implementation change: `yksllrss` (`feat: Add an optional sticky category strip`).
- Key files:
  - `MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryStrip.swift`
  - `MyAnimeList/Sources/Views/Library/LibraryView.swift`
  - `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`
  - `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfilePreferenceSections.swift`
  - `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsView.swift`
  - `MyAnimeList/Sources/ViewModels/Library/LibraryPreferences.swift`
  - `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`
  - `MyAnimeList/Sources/Extensions/String+Extensions.swift`
  - `MyAnimeList/Resources/Localizable.xcstrings`
  - `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests+Settings.swift`
- Validation on 2026-10-13:
  - `make build`: passed, including a final rerun after constraining the horizontal
    scroll view to its content height.
  - `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySyncCoordinatorTests MyAnimeListTests/LibraryCloudSyncPreferencesTests MyAnimeListTests/LibrarySortingAndDeletionTests'`:
    passed, 106 tests. The existing category settings test now checks default-off,
    true/false bool payload round trips, the backup allowlist, and a legacy payload
    with the new key absent. The existing category move/delete tests also passed.
    Compilation reported the pre-existing `namespace` capture warning in
    `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests+OrdinarySync.swift:87`.
  - `make run-sim`: built, installed, and launched successfully on the already-booted
    iPhone 18 Pro simulator (`A06216D2-8EA3-4101-9BC5-9F45356CCA35`, PID 96978).
    No additional simulator was booted and no manual UI walkthrough was performed.
  - `swift format lint MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryStrip.swift`:
    clean after fixing the documentation-comment spacing.
  - `git diff --check`: passed.
- Catalog comparison: exactly four new keys, all with Japanese and Simplified
  Chinese translations; existing entries are unchanged.

## Open questions

- Maintainer UI checks remain: material integration, selection underline/scrolling,
  long-press dialogs, native drag/drop including offscreen targets, Dynamic Type,
  and transitions into/out of multi-selection. Validation here is limited to
  building, focused non-UI tests, and launching the already-booted simulator.
- Cloud transport between devices and backup-file restore were not exercised;
  the option reuses the existing allowlists and settings payload path.
