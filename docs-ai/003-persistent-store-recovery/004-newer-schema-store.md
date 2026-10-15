# 003.004 — Stores written by a newer schema are not quarantined

## Context

On 2026-10-13 and 2026-10-15, a CloudKit silent push made macOS launch an older
installed AniShelf (1.102.0 build 12, which only knows `SchemaV2_8_2`) in the
background. A dev build had already migrated the store to 2.8.3. The older build got
`SwiftDataError.unknownDataStoreSchema`, and startup recovery quarantined the whole
store into `Recovery/<timestamp>/` and started an empty library. No user was present.
Evidence came from the recovery manifest (`appBuild` 12), the quarantined store's
metadata (`NSStoreModelVersionIdentifiers = ["2.8.3"]`), and the unified log
(content-available push, then a LaunchServices background launch). Recovery treated
a downgrade as corruption.

## Change

Planned and implemented on 2026-10-15:

- `DataProvider.bootstrap` reads the store's Core Data metadata before it opens the
  store. If `NSStoreModelVersionIdentifiers` names a version newer than every schema
  in `MigrationPlan.schemas`, bootstrap creates no real container. It leaves the store
  files and sync state untouched and returns an in-memory placeholder provider with
  the status `requiresNewerApp(storeVersion:)`.
- Unreadable metadata, or a version the app knows, falls through to the existing
  open → quarantine path, so genuinely unreadable stores still recover as before.
- The app reuses `StartupRecoveryActivityGate`, blocked and never unblocked in this
  state, so the push handler returns `.noData` and launch, foreground, What's New,
  review, and reminder-pruning work stays off. Every window shows
  `NewerLibraryStoreView`, a blocking view styled like `StartupRecoveryView` with no
  "Continue" button. It shows the app version and the store's schema version and
  offers "Open App Store" as its only action.
- DEBUG builds accept the launch argument `-simulate-newer-library-store`. With it,
  `MyAnimeListApp` skips `DataProvider.startupBootstrap` (a lazy `static let`, so the
  real store is never opened) and uses `newerStorePlaceholderBootstrap` with store
  version 99.0.0. Everything after detection then runs as in the real case. To use it,
  pass the argument after the bundle ID, for example
  `xcrun simctl launch booted com.samuelhe.MyAnimeList -simulate-newer-library-store`,
  or add it to the scheme's launch arguments in Xcode. Release builds ignore it.
  `StartupRecoveryView` later got a matching override; see
  [005-simulated-startup-recovery.md](005-simulated-startup-recovery.md).

| Choice | Reason and rejected alternative |
| --- | --- |
| Check metadata before opening | The open attempt also runs the legacy V2.6.0 bridge measure against the file. Checking first means a newer store is never handed to any older schema. The rejected alternative was to inspect `unknownDataStoreSchema` after failure, which ties the logic to an error case SwiftData does not document. |
| Compare against every known schema, not `CurrentSchema` | The decision is "newer than anything this binary can read", so it should not depend on which schema is current. |
| In-memory placeholder provider | `LibraryStore` and the app need a provider. An in-memory one also skips sync scheduling and the cloud-preferences monitor. A real replacement store was rejected because it would create files next to the newer store. |
| Custom blocking view instead of `.alert` | Maintainer decision: an alert can be dismissed into an empty, unusable app. The view matches the existing recovery screen and shows in every window. |
| No "Continue" option | Continuing would need a real store, which means quarantining or overwriting the newer data. The only safe fix is updating the app. |

## Refs

- `DataProvider/Sources/DataProvider/DataProvider+StartupRecovery.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`
- `MyAnimeList/Sources/Views/NewerLibraryStoreView.swift`
- Test: `startupBootstrapLeavesNewerSchemaStoreInPlace` in
  `DataProvider/Tests/DataProviderTests/DataProviderTests.swift`

## Validation (2026-10-15)

- `make test-dataprovider`: 69 tests passed. The suite includes the new test and the
  legacy V2.6.0 loader tests, whose store is stamped 2.5.9 and still opens.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryBackupRestoreTests'`: passed.
- Launching on a booted iPhone simulator with `-simulate-newer-library-store` showed the block
  view with app version 1.102.0 (1) and store version 99.0.0.
- Not verified: an actual push-triggered background launch against a newer store, and
  the "Open App Store" link on Mac Catalyst.
