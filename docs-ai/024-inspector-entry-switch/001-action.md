# 024 — Mac inspector entry switch without a flash: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-17 | Diagnosed the flash from the maintainer's recording (inspector brightness per frame) and from source. | — |
| 2026-10-17 | Step 1: a new session fills its view model from the stored detail synchronously. | `c4cab57` |
| 2026-10-17 | Plan written; steps 2–4 implemented: no switch fade on macOS, no logo-only refetch on macOS, revision-keyed fade for fetched details. | `c4cab57` |

## Outcome and current state (as of 2026-10-17)

- `EntryDetailViewModel.prepare(for:language:)` resets the fields and applies the
  stored same-language detail. It is idempotent per request key
  (`preparedRequestKey`). `load(for:language:)` calls it, returns when the stored
  detail is current, and otherwise fetches. A retry no longer blanks the fields;
  it still clears `loadError` before fetching.
- `EntryDetailSession.init` calls `prepare` with
  `Language.resolvedAnimeInfoLanguage()`, so a detail renders complete on its first
  frame.
- A stored detail without a logo counts as current where
  `refetchesForMissingLogo` is false: the default on macOS
  (`EntryDetailViewModel.platformRefetchesForMissingLogo`). iOS keeps refetching to
  backfill logos for its hero.
- `fetchedDetailRevision` increments when a fetched detail is applied.
  `EntryDetailView` animates its scroll content on that revision
  (`.smooth(duration: 0.25)`).
- `entryReplacementAnimation` is `nil` on macOS and the 0.18 s ease-in-out on iOS.

Key files:

- `MyAnimeList/Sources/ViewModels/Library/EntryDetailViewModels.swift`
- `MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Tests/MyAnimeListTests/EntryDetailSessionTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/EntryDetailViewModelTests+Loading.swift`

## Deviations from plan

- The logo policy became an initializer parameter (`refetchesForMissingLogo`,
  defaulting to the platform value) rather than a private constant.
  `testEntryDetailRestoresPersistedDetailAndRetriesAfterSaveFailure` uses a
  logo-less stored detail to force a fetch, and keeps testing save rollback on the
  Mac by opting in.
- The missing-logo test became
  `testEntryDetailRefetchesMissingLogoOnlyWhereTheLogoIsShown`, with expectations per
  platform, instead of a new Mac-only test.

## Validation

- `make test-mac APP_TEST_ONLY='MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/EntryDetailViewModelTests'`:
  passed. The first run after step 3 failed 9 expectations in the save-failure test;
  the fix is described under Deviations.
- `make test-app-sim` with the same filter on the booted iPad Pro 13-inch (M5)
  simulator: passed.
- `make lint`: no warnings in the changed lines. The indentation warnings at
  `EntryDetailView.swift:75` onward predate this work.
- `make run-mac`: build succeeded and the app launched. The maintainer approved
  entry switching after a visual pass.

## Open questions

- The material-flattening explanation for the dark frames is inferred from frame
  timing, not instrumented.
- A fetched detail that inserts sections (for example stat cards for an entry with no
  stored detail) fades them in. Whether material cards darken during that short fade
  has not been checked visually.
- iPad keeps its opacity cross-fade over the same kind of material cards. Whether it
  shows the same darkening is unchecked.
