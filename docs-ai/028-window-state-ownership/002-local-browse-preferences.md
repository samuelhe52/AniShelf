# 028.002 — Keep sort and group preferences off iCloud

## Context

The 028 plan kept sort, group and sort direction in the iCloud-synced settings,
because the original settings sync (`3e0ba85`, June 2026) already carried them.
Nobody argued for that choice when 028 made these values per-window. After 028, the
synced value only seeds new windows. The last sort or group change made in any
window, on any device, decided how new windows opened on every other device.

On 2026-10-18 the maintainer called syncing these "really strange" and approved
removing them.

## Change

- `String.cloudSyncedPreferenceKeys`
  (`MyAnimeList/Sources/Extensions/String+Extensions.swift`) no longer lists
  `libraryGroupStrategy`, `librarySortStrategy` or `librarySortReversed`. They stay
  in `allPreferenceKeys`, so backups still carry them. View style was already
  device-local.
- The bool export case in `LibraryPreferences.cloudSyncedSettingsPayload()` no
  longer lists `librarySortReversed`.
- Tests that used `saveSortReversed` to make the settings payload non-empty now use
  `saveHideDroppedByDefault`. The allowlist export test also checks that
  `librarySortReversed` is left out.

## Compatibility

- A new build that imports an older snapshot ignores these keys, because
  `applyCloudSyncedSettingsSnapshot` only visits allowlisted keys.
- An older build that imports a new snapshot finds the keys missing and removes its
  local values, so it goes back to the defaults: date started, reversed, no
  grouping. This happens each time a new-build device uploads settings, until every
  device has updated. The maintainer accepted this, since it only affects how new
  windows open.

## Rejected alternative

- Keep syncing them as the "latest choice" default. This was rejected because
  per-window browse state makes a cross-device default surprising, and nothing
  depends on it.

## Validation

- 2026-10-18: `make test-app-sim` passed on the iPad Pro 13-inch (M5) simulator for
  `LibraryCloudSyncPreferencesTests`, `LibrarySyncCoordinatorTests`,
  `LibraryPreferenceDefaultsTests` and `AnimeSharingTests`.
- Not done: a runtime check of settings sync between two devices.
