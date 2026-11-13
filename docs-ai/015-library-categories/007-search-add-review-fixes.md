# 015.007 — Search add review corrections

## Context

On 2026-11-13 the maintainer authorized all six reviewed corrections: applying
the destination when restoring a hidden entry, following the chosen destination
after adding, consistent Mac/iOS batch visibility, shared category resolution,
one selected-category lookup in the picker, and shared settings menu-row layout.

## Planned changes

- Route hidden restoration through the fetch/recheck path and apply valid category
  membership before the restoration save. Visible duplicates retain memberships;
  scaffolding that remains hidden still receives none.
- Give post-add navigation its own request, retaining the destination across sheet
  dismissal. Revalidate it before navigation, follow it, and clear incompatible
  browse filters to reveal the result. Ordinary library-search jumps retain their
  existing behavior. A concurrent visible duplicate outside the destination uses
  All as a reveal fallback without modifying that duplicate.
- Put category resolution on LibraryStore, remove the pre-submit check, and resolve
  the picker's selected category once. Keep the write-side check after awaits.
- Show the Mac batch picker once, only with loaded, selected results, as on iOS.
- Share the settings menu-row shell among watch status, default filters, and add
  category defaults. Preserve the multi-select menu's stay-open behavior and the
  native Mac pickers. Keep the add-category setting last in its section.
- Extend focused in-memory tests for hidden restoration, duplicate races and
  deferred destination-aware navigation. Validate with simulator tests, a native
  Mac build, and simulator UI checks; no production library mutation or Git
  publication is authorized.

## Current state

Implemented locally on 2026-11-13. The maintainer subsequently authorized a local
commit after validation; pushing was not requested.

- `LibraryStore+Entries.swift` now fetches and rechecks both missing and hidden
  identities. Explicit restoration adds the valid destination before saving;
  concurrent visible duplicates retain their memberships. The unused alternate
  asynchronous hydration overload was removed.
- `LibraryBrowseState.swift` carries separate existing-entry and post-add jump
  requests, preserving the destination through sheet dismissal. Post-add jumps
  follow the still-valid destination, reset incompatible filters, and fall back
  to All for None, invalid destinations, or an unrelated concurrent duplicate.
- `LibraryStore+Categories.swift` owns category lookup and its ID projection.
  `LibraryBrowseScope` uses that policy; SearchPage forwards the session's raw
  choice. `SearchAddCategoryPicker` resolves the selected category once and uses
  it for selection, display text, and accessibility without a Set or empty-string
  stand-in.
- `TMDbBatchAddView.swift` declares the Mac picker once and only for loaded results
  with a nonzero selection, matching iOS.
- `LibraryProfileSettingsComponents.swift` supplies `LibraryProfileMenuRow` for
  the three settings rows in `LibraryProfilePreferenceSections.swift`. Native Mac
  pickers and the iOS multi-select menu's dismissal policy are preserved.

## Validation (2026-11-13)

- `make build-mac`: passed. The native Mac app was not launched.
- `make test-app-sim` with `APP_TEST_ONLY` selecting SearchAddCategoryTests,
  TMDbSearchServiceBatchTests, LibraryRelationshipAndConversionTests,
  LibrarySortingAndDeletionTests, and LibraryMetadataRefreshTests: passed.
  The result summary reports 83 tests / 90 executions, zero failures or skips.
- Extended in-memory tests cover initially hidden and concurrently generated
  hidden entries, category invalidation during both creation and restoration,
  concurrent visible duplicates during both paths, immediate/deferred A → B
  navigation through conflicting filters, deferred deletion/None fallback, and
  unchanged ordinary-search navigation.
- `make run-sim DEVICE_PROCESS_LAUNCH_ARGS='-library-fixture 42'`: passed on the
  already booted iPhone 18 Pro (iOS 27.2). Inspected settings layout screenshots;
  confirmed the category default remains last. In the isolated fixture, selecting
  the Movies default filter updated its checkmark while keeping the menu open;
  selecting All restored the fixture preference.
- `make launch-sim`: restored the normal simulator launch. Read-only Totoro/Ponyo
  batch searches produced two selected movies. Changed the destination to 音乐,
  deselected both movies and observed the footer disappear, then reselected both
  and observed the destination and footer return. Inspected the final screenshot
  and left the simulator on that preview. No normal-library entries were added
  or deleted; actual persistence and post-add navigation used in-memory tests.
- `git diff --check`: passed. Swift formatting checks reported one existing
  documentation-summary warning on an unchanged LibraryBrowseScope comment.

## Limits

Mac toolbar runtime and real multi-window UI interactions were not exercised;
Mac compilation and tests of the shared behavior passed. No physical device or
production-library write was performed. Existing copy and screenshot assets were
not changed by this review correction.
