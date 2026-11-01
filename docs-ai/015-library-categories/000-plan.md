# 015 — Library categories: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-13 |
| Origin | Maintainer request on 2026-10-13 (custom categories with a Telegram-style switcher); decisions taken through an interactive HTML plan the same day |
| Related | [005-adaptive-library](../005-adaptive-library/000-plan.md), [009-cloud-sync-correctness](../009-cloud-sync-correctness/000-plan.md), [014-multiselect-invariants](../014-multiselect-invariants/000-plan.md), [002-image-path-storage](../002-image-path-storage/000-plan.md) |

## Background

Users can narrow the library only by the built-in status and type filters. The
maintainer wants user-defined categories ("Isekai", "Rewatch Later") and a quick
way to switch between All and each category, modeled on Telegram chat folders.
Many users will never use categories, so the feature must stay out of the way.

## Goals

- An opt-in **Library Categories** setting, off by default. When off, no category
  control appears anywhere; turning it off keeps all category data.
- Add selected anime to categories from the existing List/Grid multi-selection
  bar. The same menu suggests creating a category from the selection.
- Switch All / category from a chip strip that stays hidden until the user pulls
  past the top of List or Grid, and hides again on scroll down. The navigation
  title capsule names the active category and also works as a switch menu (the
  only switcher in Gallery).
- Long-press a chip for Rename / Edit Categories… / Delete. Chips can be
  reordered by drag in the strip.
- A management sheet, opened from Settings, to create empty categories, rename,
  delete (swipe), and reorder.

### Non-goals

- No quick "add anime" flow inside the management sheet; multi-selection is the
  only way to fill a category.
- No Gallery multi-selection, no category controls in entry detail or the entry
  context menu, no category column in exports, no smart (rule-based) categories,
  icons, or colors.

## Design / approach

**Data.** `SchemaV2_8_3.AnimeEntry` (proposed) adds `categoryIDs: [String]` and a
dedicated sync clock `categoriesUpdatedAt: Date?`; a lightweight stage migrates
from V2_8_2. Category definitions are a plain `LibraryCategory` value list
(`id`, `name`, `createdAt`) stored as JSON in UserDefaults; array order is display
order. An anime can belong to any number of categories.

**Sync.** `LibraryEntrySyncSnapshot` carries `categoryIDs`/`categoriesUpdatedAt`
and merges them by their own clock. The definitions list travels in the existing
settings record as a new `LibrarySettingsSyncSnapshot.Value` case holding an array
of JSON objects.

**Deletion.** Deleting a category removes only its definition. Entries keep the
stale ID; reads ignore unknown IDs and the next membership write on that entry drops
them. This avoids rewriting and re-uploading many entries.

**UI.** `LibraryBatchAction.category(id, isMember:)` reuses the multi-selection
batch path. `LibraryStore.activeCategoryID` (shared across windows like `filters`)
narrows entries in `filterAndSort` before the existing filters (AND semantics).
`LibraryView` refreshes the multi-selection snapshot when the active category
changes (see [014](../014-multiselect-invariants/000-plan.md)).

Key files: `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`,
`MyAnimeList/Sources/Views/Library/LibraryBatchAction.swift`,
`MyAnimeList/Sources/ViewModels/Library/LibraryStore+Filtering.swift`,
`MyAnimeList/Sources/ViewModels/Library/LibraryPreferences.swift`,
`DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`,
`DataProvider/Sources/LibrarySync/LibrarySettingsSyncSnapshot.swift`,
`DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift`,
`DataProvider/Sources/DataProvider/MigrationPlan.swift`. New views live under the
proposed `MyAnimeList/Sources/Views/Library/Categories/`.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Opt-in, default off | Maintainer requirement: users who do not need categories must not see them. |
| Add via existing multi-selection; creation suggested from the selection menu | Maintainer preference. A quick-add flow inside the management sheet was rejected as redundant. |
| Many categories per anime | Chosen (Telegram-folder model). Single membership ("Move to") was rejected. |
| Strip hidden until a pull at the top | Chosen to save vertical space. Rejected: always-visible strip (Telegram style, costs a row) and Safari-style reveal on any upward scroll (more motion). |
| Reorder in the sheet and by drag in the strip | Maintainer chose strip drag in addition to the sheet. If the chip context menu and drag cannot share one long press, the fallback is a "Reorder" mode from the chip menu. |
| Membership on each entry (schema bump) | Gives per-entry last-writer-wins sync, like other entry state. Rejected: storing entry IDs inside each category, which avoids a schema bump but makes the whole list last-writer-wins across devices. Cost: about 7 copied model files, as in the V2_8_2 bump (`b3cd028`). |
| Own clock `categoriesUpdatedAt` | Older builds never send it, so their uploads cannot clear `categoryIDs`. Sharing `libraryUpdatedAt` would let an older build's library write win the merge with no category data. |
| Old builds and unknown CloudKit keys | Records are fresh `CKRecord`s saved with `.allKeys`; keys a writer does not carry stay unchanged on the server. The `customPosterPath` shim already relies on this (see 002 historical review 2026-06-14, F1). |
| Definitions in the settings record as an object array | Chosen over one CloudKit record per category. Older builds rebuild the settings payload from their own key list, so a plain string key would be erased by them; an object-array value decodes as `.unknown` there, so they skip settings export instead (their other settings stop uploading until they update). A per-category record type was rejected because older builds would quarantine those records and the transport work is larger. |
| Lazy cleanup of deleted IDs | Avoids a mass entry rewrite and sync storm on delete. IDs are UUIDs and never reused. |

## Validation and acceptance criteria

- DataProvider tests: snapshot merge and Codable round-trip of `categoryIDs` with
  its own clock; record encode/decode; settings value decoding of the object array;
  V2_8_2 → V2_8_3 migration keeps entries.
- App tests: filtering by active category combined with filters; batch membership
  add/remove; category store create/rename/delete/move and name validation;
  settings payload round trip.
- `make build`, focused `make test-dataprovider` / `make test-app-sim` runs, and a
  simulator run of the strip reveal, chip context menu, and strip drag when a
  simulator is already booted.

## Amendments

- Updated 2026-10-13: Optional always-visible category strip for List and Grid — see [002-sticky-category-strip.md](002-sticky-category-strip.md)
- Updated 2026-10-13: In-place animated tab reordering, upper-right Done, and long-press menus disabled during multi-selection — see [003-interactive-tab-reordering.md](003-interactive-tab-reordering.md)
- Updated 2026-10-30: Selection highlight moved off `matchedGeometryEffect`, which broke view-style page transitions; 002's matched-geometry wording corrected — see [004-selection-highlight-without-matched-geometry.md](004-selection-highlight-without-matched-geometry.md)
- Updated 2026-10-31: 004 corrected in place — its fix is incomplete; with the strip shown, the incoming page still pops in when switching right after a scroll — see [004-selection-highlight-without-matched-geometry.md](004-selection-highlight-without-matched-geometry.md#current-state-corrected-2026-10-31)
- Updated 2026-10-31: Strip isolated from view-style animations, so the incoming page no longer pops in — see [005-page-insertion-after-scrolling.md](005-page-insertion-after-scrolling.md)
