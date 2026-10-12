# 015 — Library categories: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-13 | Interactive HTML plan reviewed. Maintainer kept four defaults and chose drag reorder in the strip. | — |
| 2026-10-13 | `SchemaV2_8_3`, entry/record/settings sync fields, and DataProvider tests. | `pzzpuvtw` |
| 2026-10-13 | App feature: preferences, store operations, selection-bar Category menu, title capsule menu, browse-menu Category picker, manager sheet, settings rows, localization, app tests. | `lwopslvt` |
| 2026-10-13 | Maintainer review rounds, folded into `lwopslvt`: settings rows moved to the end of General and animated at the settings card (like the language and episode-progress options); selection menu labels aligned, the create item shortened, and the menu kept open after a pick; a pull-to-reveal strip was built, found non-linear, rebuilt as a content-embedded strip, then removed; an always-visible capsule chevron was rejected; the browse-menu Category picker joined the first section, renamed from "Group By" to "View", to save height. | `lwopslvt` |

## Outcome and current state (as of 2026-10-13)

- `AnimeEntry` (`SchemaV2_8_3`) has `categoryIDs` and `categoriesUpdatedAt`; a
  lightweight stage migrates from V2_8_2. The seven V2_8_3 model files are
  mechanical copies of the V2_8_2 files.
- `LibraryEntrySyncSnapshot` carries both fields, merges them by their own clock
  with the canonical-value tie-break, and feeds the clock into `latestSyncClock`,
  `latestUserStateClock`, and tombstone comparison. `CloudLibrarySyncClient`
  writes `categoryIDs` (omitted when empty) and `categoriesUpdatedAt`, and clears
  both on tombstones.
- `LibrarySyncChangeRecorder` and the bootstrap dirty clock watch
  `categoriesUpdatedAt`, so membership edits queue uploads.
- `LibrarySettingsSyncSnapshot.Value.objectArray` carries the definitions list
  under `LibraryCategories`; `LibraryCategoriesEnabled` syncs as a bool. Both keys
  are in the backup and cloud-synced key lists.
- UI: Settings › General toggle and "Manage Categories" row; selection-bar
  "Category" menu (checkmark / dash / blank icon per category, so names align)
  that stays open after a pick and keeps the selection, plus "New Category…";
  the title capsule names the active category (with a chevron) and switches
  category in every view style; the bottom browse menu has a Category picker
  under Group By in its "View" section; manager sheet for create, rename, delete, and reorder.

Key files:
`DataProvider/Sources/DataProvider/Models/V2/AnimeEntryV2_8_3.swift`,
`DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`,
`DataProvider/Sources/LibrarySync/LibrarySettingsSyncSnapshot.swift`,
`MyAnimeList/Sources/Models/Library/LibraryCategory.swift`,
`MyAnimeList/Sources/ViewModels/Library/LibraryStore+Categories.swift`,
`MyAnimeList/Sources/Views/Library/LibraryBrowseSummaryMenu.swift`,
`MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryManagerSheet.swift`,
`MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`.

## Deviations from plan

- No category strip ships. After the content-embedded strip, the maintainer
  chose to drop it: the title capsule already works as a menu, and a strip
  costs space. The plan's strip, chip long-press actions, and drag reorder in
  the strip (decision `reorder=strip`) are gone; reorder lives in the manager
  sheet. The strip history below is kept as the reason for this choice.

- Strip reveal: the plan's sketch toggled a top inset when the scroll offset
  crossed thresholds. The maintainer found it non-linear. Neither SwiftUI nor
  UIKit has a hide-until-pull header except the search field (and its UIKit
  scope bar), and Apple forum requests for one are unanswered. Telegram-iOS
  (`ChatListNavigationBar.applyScroll`, `ChatListControllerNode`) lays its
  header out from the list's own offset, starts with `initialScrollingOffset`
  past it, and snaps at half the height when scrolling ends. The removed
  second strip followed that: a scroll-content row, a `scrollTo` the first entry
  on appear, and an `onScrollPhaseChange` snap on `.idle`. A `ScrollTargetBehavior`
  snap was rejected because `List` ignores it (Apple forum 732006). The
  maintainer rejected an always-visible strip as the default; an opt-in sticky
  strip is the planned next step.

- `LibraryCategory` lives in the app target (`id`, `name` only), not in a package;
  the plan sketch also had `createdAt`, which nothing needed.
- `UserEntryInfo` does not carry memberships: it models tracking state for edit
  replay, and the tracking editor does not edit categories.
- The manager sheet is presented with local sheet state from Settings and the
  library, not through a new `LibraryProfileSettingsSheet` case, because the
  library view also opens it.
- The capsule menu is unavailable during multi-selection, because switching
  category then would drop selected anime outside the new view.
- Category-related menu strings avoid inflection markup; "anime" does not
  inflect in English and the catalog has no inflected entries.

## Validation

- `make build`: succeeded.
- `make test-dataprovider`: 61 LibrarySync and 68 DataProvider tests passed,
  including the four new category tests.
- `make test-app-sim` with `LibrarySortingAndDeletionTests`,
  `LibrarySyncRecorderBehaviorTests`, `LibrarySyncCoordinatorTests`, and
  `UserEntryInfoAndLibraryStatsTests`: passed.
- `make test-sim` (full simulator run): app tests succeeded; DataProvider suites passed.
- `make run-sim` on the maintainer's simulator: the existing 133-entry store
  migrated to V2_8_3 and the library opened.
- A temporary XCUITest probe ran once: a single pull did not reveal the strip
  because the list opened at a restored scroll position, not at the top. The
  probe was stopped and deleted before a retry finished; strip behavior is not
  verified by this record.

- After the strip removal and the browse-menu picker: `make build` succeeded,
  and `make test-app-sim` with `LibrarySortingAndDeletionTests`,
  `LibrarySyncCoordinatorTests`, and `LibrarySyncRecorderBehaviorTests` passed.

## Open questions

- Next step (maintainer, 2026-10-13): a setting that lets users choose a
  persistent sticky category strip. Not started.

- Manual UI checks are pending (maintainer): capsule menu, bottom-menu
  Category picker, selection menu staying open with live checkmarks, manager
  sheet editing. Discoverability of the capsule menu in All mode is an open
  design concern; the bottom-menu picker is the fallback.
- Whether an open SwiftUI menu refreshes its checkmark/dash labels after a
  pick with `.menuActionDismissBehavior(.disabled)` is unverified at runtime.
- The selection menu's blank icon relies on menus reserving a column when
  every row has an image; unverified at runtime.
- Older builds pause settings export while the server holds a non-empty
  category list. This is the intended trade-off, not observed on a device.
