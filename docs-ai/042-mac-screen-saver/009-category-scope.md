# 042.009 — Custom categories as a screen saver scope

## Context

Samuel asked on 2026-11-20 that users can show one of their custom library categories
in the screen saver, not only Favorites, Watched, or All Library Entries. This was a
backlog row ("Category scope").

## Change

- `ScreenSaverSettings.Scope` gains `category(LibraryCategory.ID)`, stored as
  `category:<id>` under `screenSaverScope`; it matches entries whose `categoryIDs`
  contain the ID.
- The **Show** picker lists the built-in scopes, a divider, then the categories by name,
  when categories are on. A selected category stays listed when categories are later
  turned off; a deleted one stays listed as "Deleted Category", so the picker always
  has a valid selection.
- Deleting a category leaves its memberships on entries (IDs are never reused), so
  `ScreenSaverSnapshotBuilder` returns an empty draft when the selected category no
  longer exists, matching the backlog's "a deleted category gives an empty scope".
  `LibraryStore.categories` now notifies the publisher on change (macOS only), since
  editing category definitions saves no entry and would otherwise not rebuild the
  snapshot.

## Refs

- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSettings.swift`, `ScreenSaverSnapshotBuilder.swift`, `MacScreenSaverSettingsPage.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift` (`categories` `didSet`)
- Test: `ScreenSaverPublisherTests.scopeNeverWidensAndUsesTheVisiblePreferredRow` (category members, raw-value round trip, deleted category empty)
- Validation: `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'` (succeeded); `make build` (passed). The picker itself is not yet checked on screen.
