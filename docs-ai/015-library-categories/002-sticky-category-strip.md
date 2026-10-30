# 015.002 — Optional sticky category strip

## Context

The first delivery removed the category strip (see [001-action.md](001-action.md)):
a strip hidden until a pull felt non-linear, and an always-visible strip was
rejected as the default. On 2026-10-13 the maintainer chose to offer an
always-visible strip as an option, modeled on Telegram's chat folder tabs.

## Change

Decisions taken by the maintainer on 2026-10-13. The tab surface and selection
treatment were revised after the same-day visual review, as recorded below:

| Choice | Decision and alternative |
| --- | --- |
| Where | List and Grid only. Gallery keeps the title capsule menu. |
| Setting | A plain on/off toggle under "Library Categories" in Settings › General, shown only when categories are on, off by default, cloud-synced like the other library preferences. |
| Placement | Pinned under the navigation bar, always visible while on. No pull-to-reveal; that interaction was the reason the first strip was removed. |
| Tab style | "All" first, then categories in display order, scrolling sideways. After visual review: one inset floating glass capsule, with tinted selected text and a softly filled capsule that slides behind it. No counts on tabs. The original text-tab underline decision was superseded by this review. |
| Long press | Telegram menu: a category tab gives Reorder, Rename, Edit Categories…, Delete; "All" gives Reorder and Edit Categories…. Reorder makes the tabs draggable until Done; "All" stays first. "Menu only" was rejected. |
| Swipe content | No. Sideways swipes on the List or Grid do not switch category; they would compete with List swipe actions. |
| Title capsule | While the strip shows (List or Grid with the option on), the capsule shows the plain title with no category name and no menu. Gallery and strip-off keep the capsule menu. |
| Multi-selection | Originally hidden during multi-selection, like the capsule menu. Superseded the same day: both stay available while selecting (see [Multi-selection revision](#multi-selection-revision)). |

Initially implemented as a full-width `.bar` material surface in a top safe-area
inset. The visual revision uses an inset `.glassEffect(.regular, in: .capsule)`
surface and a sliding selection capsule behind the text (matched geometry until
[004](004-selection-highlight-without-matched-geometry.md)). It scrolls the
active tab into view on selection, definition/order changes, and reorder-mode changes.
The inset and the title capsule share one visibility condition. Neither the
selection snapshot pipeline nor the List row gesture mask changes.

`LibraryCategoryStripEnabled` defaults to false and follows the existing library
preference path: store reload/save, backup allowlist, cloud allowlist, and bool
settings payload. Settings shows the toggle only while categories are enabled;
disabling categories retains the strip preference. Rename and Delete reuse the
existing category dialogs, and Edit Categories opens the existing manager sheet.

### Implementation choices and deviations

- The visual review supersedes the original flat text-tab/underline treatment
  with a floating glass surface and a sliding selection capsule. The setting,
  placement, and category behavior decisions remain in force.
- The initial reorder implementation used native SwiftUI `draggable` and
  `dropDestination` on category tabs only. Dropping onto another tab calls
  `store.moveCategory`; the destination is highlighted during hover. Order commits
  on drop instead of changing during hover, so cancellation leaves order intact
  and moving drop targets cannot oscillate beneath the pointer. A per-reorder-mode
  token rejects unrelated text and drags from another window or an earlier mode.
  All has no drag source or drop destination; Done exits the mode. Superseded by
  [003-interactive-tab-reordering.md](003-interactive-tab-reordering.md): the
  current strip uses a short-hold gesture with live local rearrangement and edge
  scrolling, plus a wiggle and Done in the upper-right toolbar.
- Native horizontal dragging was chosen over a custom pan recognizer to leave
  horizontal scrolling with the system and avoid competing gestures. Its actual
  edge scrolling and feel remain for the maintainer's UI checks; no manual drag
  walkthrough was performed.
- The original delivery's removal history remains in `001-action.md`; its stale
  next-step note now links here. The index links this amendment.

### Visual revision after maintainer review

After seeing the strip in AniShelf, the maintainer asked for a more fitting design
and then supplied a current Telegram screenshot with a shared glass folder control,
asking for a more floating feel. This replaces the earlier visual reference and
the original rejection of a separate floating surface. The revision uses one
native glass capsule with 16-point side margins, a soft neutral selection fill,
and the existing `.snappy` matched-geometry movement (since replaced by a single
sliding capsule; see [004](004-selection-highlight-without-matched-geometry.md)). Unselected labels use medium
weight; the selected label keeps semibold weight and the app tint. Tab hit targets
remain at least 44 points high, and the drop-hover highlight is rounded to match.
The new surface stays in the existing safe-area inset; no scroll-driven visibility
or sideways content gesture was added.

A second visual review asked for less vertical space and for a small number of
categories to fill the row. The compact revision reduces the standard strip from
64 to 48 points including its outer spacing: a 36-point selection fill inside a
44-point button/rail, plus 4 points below. It removes the extra outer top gap and
vertical rail padding. Dynamic Type can still increase the content height.
The strip measures only its horizontal viewport and gives every tab an equal
minimum share of the available width (after padding and gaps). Short names fill
the row, including All plus two categories; longer names retain their intrinsic
width and overflow scrolls horizontally. The initial reorder mode accounted for
the width occupied by Done; amendment [003](003-interactive-tab-reordering.md)
moves Done to the upper toolbar, leaving the full rail width available. Viewport
changes keep the selected tab visible.

The next screenshot showed library titles and poster detail competing with the
category labels through the glass. The readability revision changes inactive labels
from secondary to primary text and gives the sliding selection a 14% app-tint fill
instead of an 8% neutral fill. The compact geometry, native `.glassEffect(.regular)`
surface, and category interactions are unchanged.

Two alternatives were tried and rejected during the same review. A `.regularMaterial`
base beneath the glass improved contrast but lost the glass look, which the
maintainer said readability must retain; no surface is layered under the glass.
Lighter typography (medium selected tab and Done, regular inactive tabs) was also
tried; the maintainer preferred the original weights, so the selected tab and Done
stay semibold and inactive tabs stay medium at subheadline size.

### Multi-selection revision

The strip and the capsule menu were first hidden during multi-selection because
switching category drops selected anime that the new category does not show. The
maintainer then pointed out (2026-10-13) that users expect a selection to belong to
the current view, as in Photos albums or Files folders, so a category switch
narrowing it is unsurprising. Both controls now stay available while selecting.

Switching relies on the existing `activeCategoryID` observer, which refreshes the
selection snapshot and intersects the selection with the newly displayed entries.
Anime that are still visible stay selected, matching other view changes during
selection; clearing the whole selection was considered and not chosen. Keeping
hidden selections across categories was rejected: batch delete and status
changes would reach anime that are off screen, and the count would no longer
match the view. Keeping the strip visible also removes the 48-point content shift
when entering or leaving selection. The capsule label is unchanged: it still shows
the selection count without a category name.

The `activeCategoryID` observer wraps the snapshot refresh in `withAnimation(.snappy)`.
While selecting, the list renders the snapshot rather than the live display items,
and `onChange` did not reliably inherit the strip's animated transaction, so the
maintainer saw some switches jump without animation.

Validation: `make build`, `swift format lint` on the two changed views, and
`git diff --check` passed; `make run-sim` launched on the already-booted iPhone 18
Pro simulator (PID 21014; PID 24137 after the animation fix). No tests were added, because the change only removes a
visibility condition and the pruning path is unchanged. No manual walkthrough was
performed; switching categories while selecting remains for the maintainer to check.

## Refs

- Implementation change: `yksllrss` (`feat: Add an optional sticky category strip`).
- Visual revision change: `ztonoopp` (`style: Refine the category strip into a compact glass capsule`).
  Covers the floating glass, compact layout, and readability reviews above. Only
  `LibraryCategoryStrip.swift` and this record changed.
  - Each review round passed a fresh `make build` and `make run-sim` on the same
    already-booted iPhone 18 Pro simulator; the final source launched as PID 36459.
    The rejected material backing and lighter typography were each built and launched
    before being reverted. No UI walkthrough was performed.
  - `swift format lint MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryStrip.swift`
    and `git diff --check`: passed. No unit tests added or repeated for visual-only
    changes; the 106 passing tests below belong to the feature implementation.
  - Maintainer verification remains for compact height, equal tab widths, long-name
    overflow, Dynamic Type, and glass appearance and text contrast over posters,
    including dark appearance.
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

### Animated first appearance

The maintainer found (2026-10-13) that with the strip enabled and no categories,
creating the first one from the selection menu's "New Category…" made the strip
appear abruptly. `showsCategoryStrip` hides the strip until a category exists, and
that path called `createCategory` outside an animation transaction; the manager
sheet's create path already used `withAnimation`. `LibraryView` now applies
`.animation(.snappy, value: showsCategoryStrip)` at the strip's safe-area inset, so
every path animates, including a first category arriving through sync and deleting
the last one. Rejected: wrapping only the selection-menu call, which leaves the
sync and deletion paths abrupt.

Validation: `make run-sim` built, installed, and launched on the booted iPhone 18
Pro simulator. The maintainer confirmed the animation on 2026-10-13.

## Open questions

- Maintainer UI checks passed (2026-10-13): glass integration, selection
  capsule/scrolling, long-press dialogs, reordering, Dynamic Type, and
  transitions into/out of multi-selection.
