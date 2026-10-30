# 035.002 — Maintainer review fixes

## Context
The maintainer's first pass found three problems: in the iOS context menu a
toggle's checkmark pushed the category name out of line with New Category…;
the Mac tracking row listed every category and widened the inspector; and the
iOS category line under the quick actions did not fit the detail sheet ("find a
better place or remove it"). The Mac context menu and drag were confirmed
working.

## Change
- iOS menu rows are Buttons whose icon is a checkmark or a blank image of the
  same size, the batch menu's technique. Its `Membership` enum moved out of
  `LibraryToolbar.swift` as the shared `LibraryCategoryMembership`. Mac keeps
  native toggles, which have their own checkmark column.
- The Mac row's label is capped at 220 pt with the full list as a tooltip. A
  `ViewThatFits` shows the whole list when it fits, otherwise "<first> and N
  more" (new key `%@ and %lld more`), truncating only if even that overflows.
- The iOS line was removed; the quick actions' More menu gained a Categories
  submenu after Change Poster (iOS only, since the Mac card has the row). A
  shared `entryNewCategoryPrompt` modifier hosts New Category… for the More
  menu, the Mac row, and the context menu. The unused "Add to Category" string
  was removed.
- `LibraryStore.addDroppedEntries` returns nothing: the sidebar resolves to the
  `dropDestination` overload whose action returns `Void`.

Rejected: placing categories in the iOS Tracking disclosure (collapsed by
default) or as a separate card (too heavy for a secondary attribute).

## Refs
- `MyAnimeList/Sources/Views/Library/Categories/EntryCategoryMenu.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`
