# 018 — Default poster language and onboarding language step: Action record

## Timeline
| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-15 | Preference, poster selection, fetch plumbing, poster browser ordering, tests | `eaac7e0` |
| 2026-10-15 | Language settings page with Default Poster and refresh prompt (replaced a first inline row; see [002](002-language-page.md)) | `944dfda` |
| 2026-10-15 | Onboarding language step with deferred key save; this record | commit `feat: Ask for language preferences during onboarding` |

## Outcome and current state (as of 2026-10-15)

- `PosterLanguagePreference` (`originalLanguage` / `animeInfoLanguage`) is stored under
  `DefaultPosterLanguage`; absent or unknown values resolve to `originalLanguage`. The
  key is in `allPreferenceKeys` and `cloudSyncedPreferenceKeys`.
- `TMDbImageSelection.posterMatchRules` swaps the first two rules in
  `animeInfoLanguage` mode. Low-level selection APIs default to `originalLanguage`.
- InfoFetcher methods that build library `EntryMetadata` (`latestInfo`,
  `fetchInfoFromTMDB`, `movieInfo`, `tvSeriesInfo`, `tvSeasonInfo`, `seasonInfos`, and
  the `latest*` variants) require `posterLanguage:`. The search-only lookups
  `animeMovieInfo` and `animeTVSeriesInfo` pass `.originalLanguage`.
- `LibraryStore.posterLanguage` reads the preference through `LibraryPreferences` on
  each access. Add, hydrate, refresh (including parent-series updates), CloudKit
  `hydrateMissingEntry`, parent-series generation, and season/series conversion pass it.
- In onboarding, `TMDbAPIKeyEntryViewModel(savesKeyOnValidation: false)` holds the
  validated key. A fourth step, `.languages`, shows `LibraryProfileLanguageSettingsSections`,
  and **Start Using AniShelf** saves the key, which lets the existing root switch to
  the library. If the save fails, the step shows an inline error. The settings sheet
  `TMDbAPIConfigurator` keeps saving as soon as validation succeeds.
- The Language settings page (hub destination and iPad workspace group; see
  [002-language-page.md](002-language-page.md)) holds the Anime Info Language and Default Poster cards.
  When the mode changes and the library is not empty, a **Refresh Default Posters?**
  alert offers the existing `refreshInfos()`, which already preserves custom posters.
- `PosterBrowserView` sorts manual poster choices with the same mode.

Key files:
- `MyAnimeList/Sources/Models/PosterLanguagePreference.swift`
- `MyAnimeList/Sources/Network/TMDbImageSelection.swift`
- `MyAnimeList/Sources/Network/InfoFetcher.swift` and `InfoFetcher+{Movie,Series,Season}.swift`
- `MyAnimeList/Sources/ViewModels/Gadgets/TMDbAPIKeyEntryViewModel.swift`
- `MyAnimeList/Sources/Views/Gadgets/TMDbAPIOnboardingView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfilePreferenceSections.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsView.swift`

## Deviations from plan

- **Separate alert instead of a shared one.** The plan said to reuse the
  language-change alert with broader wording. Instead, poster-mode changes get their
  own **Refresh Default Posters?** alert that calls the same `refreshInfos()`. This
  leaves the existing language alert's wording unchanged. Only the poster alert skips
  empty libraries.
- **Explicit parameter instead of a struct.** The plan said to replace `language:` with
  a single preferences value. I added a required `posterLanguage:` parameter next to
  `language:` instead, because detail, credits, and search calls still need `language`
  on its own. The compiler still enforces coverage.
- **Unused methods updated anyway.** `fetchInfoFromTMDB`, `movieInfo`, `tvSeasonInfo`,
  and `seasonInfos` have no callers in the app today. They still got the parameter, to
  stay consistent.

## Validation

- `make build`: succeeded, both before and after formatting.
- `swift format lint` on the changed files: clean.
- `make test-app-sim` passed in these runs:
  - `TMDbImageAndTranslationTests`, `LibraryPreferenceDefaultsTests`, and
    `LibraryRelationshipAndConversionTests`
  - `LibraryMetadataRefreshTests` and `LibraryBackupRestoreTests`
  - `LibrarySyncCoordinatorTests`, run alone
  - `LibraryCloudSyncPreferencesTests`, `LibraryProfileSettingsStateTests`,
    `WhatsNewAndRefreshTests`, and `LibrarySyncRecorderBehaviorTests`
- New tests: `testAnimeInfoLanguageModePrefersMetadataLanguagePoster` and
  `testPosterLanguageDefaultsToOriginalAndSyncs`.
- **One run stalled.** A first combined run of all six suites, including
  `LibrarySyncCoordinatorTests`, stalled for more than 10 minutes with the host app idle,
  and I killed it. The same suites passed when run in smaller batches.
- `make run-sim`: the app installed and launched. The maintainer is reviewing the
  onboarding step and settings UI.

## Open questions

- Why did the combined test run stall? It didn't reproduce in batches.
- `@AppStorage` `onChange` would also fire if iCloud settings sync wrote
  `DefaultPosterLanguage` while Settings is open, which would show the refresh alert.
  The existing language alert has the same exposure. Neither was observed.
- A `zh` poster may be Traditional Chinese, because TMDb image metadata has no region.
