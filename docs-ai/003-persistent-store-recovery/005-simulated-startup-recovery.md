# 003.005 — Simulating startup recovery in DEBUG builds

## Context

Before this change, the only way to see `StartupRecoveryView` was to corrupt the real
store. On 2026-10-15, after `-simulate-newer-library-store` was added (see
[004-newer-schema-store.md](004-newer-schema-store.md)), the maintainer asked for a
matching launch argument for the recovery screen.

## Change

DEBUG builds accept the launch argument `-simulate-startup-recovery`. For example:
`xcrun simctl launch booted com.samuelhe.MyAnimeList -simulate-startup-recovery`.
It can also be added to the scheme's launch arguments in Xcode.

- `DataProvider.simulatedRecoveryBootstrap()` writes a junk `mal.store` to
  `<tmp>/AniShelf-Simulated-Recovery/` and quarantines it with the real
  `quarantinePersistentStore`. That produces a genuine recovery folder, manifest, and
  acknowledgement marker, so both exports work end to end. It returns an in-memory
  provider. Each launch replaces the previous simulated folder. The real store is
  never opened, because `DataProvider.startupBootstrap` is a lazy `static let` that
  never gets read.
- `MyAnimeListApp` marks the launch simulated (`isSimulatedStartup`). This keeps
  `isLibraryBlocked` true for the whole launch, so launch and foreground sync, What's
  New, and the review counter stay off.
- In a simulated launch, "Continue" only acknowledges the recovery and dismisses the
  screen. It skips `prepareLibraryCloudSyncAfterPersistentStoreRecovery()`, which
  resets real CloudKit change tokens and sets the real sync status to bootstrap again.
  It also skips airing-reminder pruning, which would drop real subscriptions against
  an empty library. The activity gate stays blocked, so pushes return `.noData`.

Rejected: passing Continue's work into the view as an injected action. Only the
simulation needs that seam, so a flag in the app was simpler.

Settings changed in the empty library after Continue still write to the real
preferences. Library edits go to the in-memory store and are lost on relaunch.

## Refs

- `DataProvider/Sources/DataProvider/DataProvider+StartupRecovery.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`
- Test: `simulatedRecoveryStaysInTemporaryFolder` in
  `DataProvider/Tests/DataProviderTests/DataProviderTests.swift`

## Validation (2026-10-15)

- `make test-dataprovider DATAPROVIDER_TEST_FILTER='startupBootstrap|startupRecovery|simulatedRecovery'`:
  4 tests passed.
- On the booted iPhone simulator with `-simulate-startup-recovery`, the recovery
  screen appeared. The real `DataProvider/` folder in the app container had no new
  `Recovery/` folder, and the simulated one was under the container's `tmp/`.
- Not checked by hand: tapping Continue or the export buttons.
