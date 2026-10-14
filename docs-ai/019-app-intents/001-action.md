# 019 — App Intents and Spotlight: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-14 | Committed the plan. | `60c03c3` |
| 2026-10-14 | Extracted the tiered library search matcher (`LibrarySearchMatcher`) from `LibrarySearchService` so the search sheet and intents share one ranking. | `d555e16` |
| 2026-10-14 | Added the entity, queries, Open Entry intent, tracking actions, App Shortcuts, Spotlight indexer, detail baseline rebase, localization, and tests. | `80c8479` |

## Outcome and current state (as of 2026-10-14)

- **Entity.** `LibraryEntryEntity` is an `AppEntity` and `IndexedEntity` whose ID is
  `LibraryEntryIdentity.rawID`. It exposes name, watch status, favorite, score, date
  saved, entry type, season number, and episodes watched as properties. The subtitle
  reuses `LibraryEntrySnapshot` labels ("Season 1 · Watching · EP12"). The poster is
  read from the downsampled list or grid file Kingfisher already cached and falls back
  to the TMDb list-size URL.
- **Queries.** `LibraryEntryQuery` is an `EntityStringQuery` and an
  `EntityPropertyQuery`. All logic is in `AppIntentLibraryContext` extensions so tests
  call it directly. String search uses `LibrarySearchMatcher.metadataTiers` (names,
  translations, parent series, overviews; no notes or dates). Suggestions list Watching
  entries by latest tracking change, then the rest by date saved, capped at 50. The
  native Find action filters status (equal/not equal), favorite, score (≥), and name
  (contains), and sorts by name or date saved.
- **Gates.** `AppIntentLibraryContext.requireUsableLibrary()` throws
  `LibraryIntentError` for pending recovery, required duplicate repair, and a missing
  TMDb key. Every query and action checks it. `MyAnimeListApp.init()` registers the
  context with `AppDependencyManager`.
- **Open Entry.** `OpenLibraryEntryIntent` is an `OpenIntent` and
  `TargetContentProvidingIntent`. `libraryWindowBehaviors` handles it with
  `.onAppIntentExecution`, sharing the root's `openRoutedEntry` with the
  airing-reminder route. macOS has no `TargetContentProvidingIntent`, so the intent and
  its App Shortcut are iOS-only; the Mac app has the tracking and Find actions but no
  Open Entry. (Rebase onto native macOS, 2026-10-18.)
- **Tracking actions.** Set Watch Status, Mark Next Episode Watched, Set Episode
  Progress, Toggle Favorite, and Set Score return the updated entity and a dialog. They
  call the clocked mutators, save the main context, and post a
  `LibraryEntryTrackingChange` only when user info actually changed.
- **Baseline rebase.** `LibraryEntryTrackingChange` diffs user info before and after
  the change (per field, and per season for episode progress). Each
  `EntryDetailSession` observes it through a Combine subscription that ends with the
  session, and `rebaseBaseline(after:)` copies only those fields plus the new tracking
  clock. "Discard Changes" now calls `EntryDetailSession.restoreBaseline()`.
- **Spotlight.** `LibraryStore.refreshLibrary()` calls
  `LibrarySpotlightIndexer.scheduleReconcile()` (1 s debounce). The indexer diffs
  in-memory fingerprints, indexes in batches of 100, and serializes passes. It also
  refreshes App Shortcut parameters after each pass that changed something. The
  attribute set adds alternate names and indexes the overview as `textContent`.
- **App Shortcuts.** `AniShelfShortcuts` provides Open Entry, Watched Next Episode, Set
  Status, and Find Entries. Find Entries runs a new `FindLibraryEntriesIntent`
  (filter by one status).
- **Localization.** New strings are in `Localizable.xcstrings` with ja and zh-Hans,
  including the `${param}` parameter-summary keys and `%@` marked do-not-translate.
  Phrases are in the new `AppShortcuts.xcstrings`.

Key files:

- `MyAnimeList/Sources/Intents/AppIntentLibraryContext.swift`
- `MyAnimeList/Sources/Intents/LibraryEntryEntity.swift`
- `MyAnimeList/Sources/Intents/LibraryEntryQuery.swift`
- `MyAnimeList/Sources/Intents/WatchStatusAppEnum.swift`
- `MyAnimeList/Sources/Intents/OpenLibraryEntryIntent.swift`
- `MyAnimeList/Sources/Intents/LibraryTrackingIntents.swift`
- `MyAnimeList/Sources/Intents/AniShelfShortcuts.swift`
- `MyAnimeList/Sources/Intents/LibrarySpotlightIndexer.swift`
- `MyAnimeList/Sources/Models/Library/LibraryEntryTrackingChange.swift`
- `MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`
- `MyAnimeList/Sources/ViewModels/Search/LibrarySearchService.swift`
- `MyAnimeList/Resources/AppShortcuts.xcstrings`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryAppIntentsTests.swift`

## Deviations from plan

- **Extra refusals.** The plan listed five error cases. The implementation adds three:
  `episodeTrackingDisabled` and `scoringDisabled` refuse when the matching setting hides
  that control in the app, and `allEpisodesWatched` refuses a next episode past the last
  known one. These were implementation choices, not maintainer decisions.
- **Next episode on a series.** It uses the season the detail slider would show first
  (latest changed, else first). If that season is complete, it moves to the next
  unfinished season. The plan only said "the entry's writable season".
- **Set Episode Progress** takes an optional season, used only by series.
- **Set Score** takes 0–5, where 0 removes the score.
- **Find Entries App Shortcut.** App Shortcuts need a concrete intent, and the Find
  action that `EntityPropertyQuery` generates is not one. A small
  `FindLibraryEntriesIntent` was added; the proposed file list did not include it.
- **Entry type and season number** are extra entity properties, and "Episodes Watched"
  is an added property. The plan listed only the entry type.
- **Spotlight first pass** deletes all indexed entities of this type before indexing.
  Without that, items for entries deleted while the app was closed would stay in
  Spotlight, because the fingerprint map starts empty.
- **Poster data.** The cached poster is passed as image data rather than a file URL.
  Another process may not be able to read a file URL in the app container (inference).
  The iOS 27 lazy-image `DisplayRepresentation` initializer was not used, because the
  deployment target is iOS 26.
- **Not ported to intents.** Status changes from intents do not show the rewatch prompt
  (Watched → Watching does not start a rewatch), do not record app-review events, and
  do not change status when progress is added to a non-Watching entry.
- **Swift 6 workarounds.** `LibraryEntryQuery.properties` and `sortingOptions` are
  `nonisolated(unsafe) static let`: the metadata processor requires stored builder
  syntax, and the builder types are not `Sendable`. `LibraryEntryTrackingChange` is
  `@unchecked Sendable` because `UserEntryInfo` does not declare `Sendable`.

## Validation

- `make build`: succeeded. The built app's `Metadata.appintents/extract.actionsdata`
  lists all seven actions, `LibraryEntryEntity`, the property query, and four App
  Shortcuts. `ja.lproj` and `zh-Hans.lproj` contain `AppShortcuts.strings` and
  `nlu.appintents`.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryAppIntentsTests MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/LibraryMetadataRefreshTests'`:
  passed after one fix. The first run failed one assertion because the booted simulator
  is in Japanese and the test expected an English season label. The test now compares
  against `LibraryEntrySnapshot`'s localized label instead.
- `make test-app-sim` (full app suite on the booted iPhone 18 Pro, iOS 27.0
  simulator): 446 tests passed, 0 failed.
- `swift format lint` on the changed Swift files: no findings.
- Not run by the agent: the manual simulator checks in the plan (Shortcuts app,
  phrases, Spotlight tap, two-window iPad open, discard after an intent, sync). The
  maintainer is doing UI validation.

## Open questions

- Whether `.onAppIntentExecution` delivers Open Entry to exactly one scene with two
  iPad windows, and whether it is handled on a cold launch, is unverified.
- Whether Shortcuts shows posters passed as `DisplayRepresentation.Image(data:)`, and
  whether Spotlight shows `thumbnailData`, is unverified.
- `TypeDisplayRepresentation(numericFormat:)` is extracted as `%lld library entries` by
  the compiler but appears as `${int} library entries` in the metadata. Only the
  `%lld` key was localized; check its ja and zh-Hans output.
- The parameter-summary keys (`Open ${target}` and others) were added by hand in the
  format the metadata uses. Xcode's catalog sync may rewrite them.
- An action that runs while the app is in the background saves locally, but sync
  depends on the existing scheduler getting time to run. Whether the change uploads
  before the app is suspended was not checked.
- Website: if the maintainer ships this as a named feature, `../anishelf-site` may need
  an update.
