# 019 — App Intents and Spotlight: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-14 |
| Origin | Maintainer request on 2026-10-14: add App Intents (mainly for Shortcuts) and Spotlight integration through `AppEntity` and `EntityQuery`; Siri and Apple Intelligence are not the focus. Decisions were settled through an interactive HTML plan the same day. |
| Related | [005 adaptive library](../005-adaptive-library/000-plan.md) · [008 multi-window presentation](../008-multi-window-presentation/000-plan.md) · [009 cloud sync correctness](../009-cloud-sync-correctness/000-plan.md) · [012 rewatch tracking](../012-rewatch-tracking/000-plan.md) |

## Background

AniShelf has no App Intents, App Entities, Core Spotlight indexing, user activities,
or URL handling. A source search on 2026-10-14 found no `AppIntent`, `AppEntity`,
`EntityQuery`, `CoreSpotlight`, `NSUserActivity`, or `onOpenURL` use. Users can only
reach library entries and tracking actions from inside the app.

Facts about the current source that shape the design, verified by reading it on
2026-10-14:

- **One process, one container.** The app is a single iOS 26 target with no
  extensions and no app group (`MyAnimeList/MyAnimeList.entitlements`). The store
  lives at `applicationSupportDirectory/DataProvider/mal.store`
  (`DataProvider/Sources/DataProvider/DataProvider.swift`). Intents therefore must
  run in the app process.
- **Stable identity exists.** `LibraryEntryIdentity.rawID`
  (`DataProvider/Sources/DataProvider/Models/Other/LibraryEntryIdentity.swift`) is
  derived from the entry type plus TMDb IDs, so it is the same on every device and
  survives backup restore, reinstall, and sync. SwiftData `PersistentIdentifier`
  does not survive a restore.
- **Clocked mutators exist.** `updateWatchStatus`, `updateScore`, `updateFavorite`
  (`DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift`) and
  `updateEpisodeProgress(seasonNumber:watchedThroughEpisode:at:)`
  (`DataProvider/Sources/DataProvider/Models/Other/AnimeEntryEpisodeProgressHelpers.swift`)
  advance the sync clocks that conflict resolution uses.
- **Saves already reach sync and the UI.** `LibrarySyncChangeRecorder`
  (`MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift`) turns
  `ModelContext.didSave` into dirty-queue entries, and
  `LibraryStore.handleLibrarySaveNotification()`
  (`MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`) refreshes the
  library on the same notification. Both use `ModelContextSaveObserver`
  (`MyAnimeList/Sources/Utils/ModelContextSaveObserver.swift`).
- **Activity gates live in the app struct.** `MyAnimeListApp`
  (`MyAnimeList/Sources/App/MyAnimeListApp.swift`) blocks library work while
  startup recovery is pending (`StartupRecoveryActivityGate`), while duplicate
  repair is required (`LibraryStore.requiresDuplicateRepair`), and while no TMDb key
  is set.
- **Detail presentation is per window.** `LibraryView` owns
  `@State var interaction = LibraryEntryInteractionState()`
  (`MyAnimeList/Sources/Views/Library/LibraryView.swift`), and
  `LibraryEntryInteractionState.openDetails(for:)`
  (`MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`) opens a
  detail keyed by `LibraryEntryIdentity`.
- **An open detail holds a soft-undo baseline.** `EntryDetailSession` captures
  `originalUserInfo` and `originalTrackingUpdatedAt` when the session is created,
  that is, when the detail opens
  (`MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`).
  `EntryDetailView.saveUserEdits()` resets the baseline. `isEditingDetails` only
  expands the editing section; quick controls and the editing section both mutate
  the live `AnimeEntry` while the detail is open. "Discard Changes" calls
  `EntryDetailView.discardUserEdits()`
  (`MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`). Done
  offers it only after a notes change that is not an append. It writes the baseline
  back, which would revert any change another writer saved while the detail was
  open. The detail and any other writer share the same `AnimeEntry`
  in `mainContext` (`DataProvider/Sources/DataProvider/DataHandler.swift`), which
  autosaves by default, so the baseline is an undo point, not an isolated draft.
  Sessions live in a per-window `EntryDetailSessionStore`.
- **Some tracking behavior lives only in the UI.** The detail view offers a date
  suggestion on status change (`dateUpdateSuggestion(forTargetStatus:)` in
  `MyAnimeList/Sources/Extensions/AnimeEntry+DateUpdateSuggestions.swift`) and a
  "mark as watched" prompt when progress reaches the last episode
  (`episodeProgressCompletionPrompt(forSeason:previousWatchedThroughEpisode:)`).
- **`WatchStatus` lives in DataProvider.** `AnimeEntry.WatchStatus` is declared in
  the package; its localized names are in
  `MyAnimeList/Sources/Extensions/UserEntryInfo+Localization.swift`.
- **Library search ranking exists.** `LibrarySearchService.searchInLibrary`
  (`MyAnimeList/Sources/ViewModels/Search/LibrarySearchService.swift`) matches
  display names, translations, parent series, overviews, and notes in priority
  order, visible entries only.

## Goals

- Shortcuts can pick any visible library entry by name, with a poster, a subtitle
  that tells seasons apart, and suggested entries.
- Spotlight lists visible library entries; tapping a result opens that entry's
  detail.
- An "Open Entry" intent opens an entry's detail in exactly one window.
- Shortcuts actions set watch status, mark the next episode watched, set episode
  progress, toggle favorite, and set score. Each action returns the changed entity.
- A native "Find Library Entries" action filters by status, favorite, score, and
  name, with sorting and a limit.
- A small `AppShortcutsProvider` set (Open Entry, Next Episode, Set Status, Find
  Entries) works without user setup, localized in en, zh-Hans, and ja.
- Intents refuse with a clear, localized reason when the library is blocked.
- A change from an intent survives "Discard Changes" in a detail that was open on
  the same entry.

### Non-goals

- No app group, widgets, Control Center controls, or other extensions. Intents run
  in the app process; moving the store would be a separate, larger change.
- No Apple Intelligence or Siri schema adoption (`@AppIntent(schema:)`,
  `@AppEntity(schema:)`).
- No "Add to Library" from TMDb search in this entry; it needs network access and
  the search flow (maintainer decision 2026-10-14).
- No category entity, so no category filter in Find Entries.
- No URL scheme or universal links.
- No change to the sync pipeline, the SwiftData schema, or `DataProvider`.

## Design / approach

All new source goes in a proposed `MyAnimeList/Sources/Intents/` folder in the app
target. Proposed files:

| Proposed file | Content |
| --- | --- |
| `Intents/AppIntentLibraryContext.swift` | Shared context and `LibraryIntentError` |
| `Intents/LibraryEntryEntity.swift` | `LibraryEntryEntity` (`AppEntity`, `IndexedEntity`) |
| `Intents/LibraryEntryQuery.swift` | `EntityStringQuery` + `EntityPropertyQuery` |
| `Intents/WatchStatusAppEnum.swift` | `AppEnum` mirror of `AnimeEntry.WatchStatus` |
| `Intents/OpenLibraryEntryIntent.swift` | `OpenIntent`, `TargetContentProvidingIntent` |
| `Intents/LibraryTrackingIntents.swift` | Status, next episode, progress, favorite, score |
| `Intents/AniShelfShortcuts.swift` | `AppShortcutsProvider` |
| `Intents/LibrarySpotlightIndexer.swift` | Core Spotlight reconciliation |
| `Resources/AppShortcuts.xcstrings` | Localized App Shortcut phrases |

### Shared context and gates

`AppIntentLibraryContext` (`@MainActor`) holds the `LibraryStore`, the
`StartupRecoveryActivityGate`, and a TMDb-key check.
`MyAnimeListApp.init()` registers it with `AppDependencyManager.shared`; intents
read it through `@Dependency`. Every intent and query calls
`requireUsableLibrary()` first, which throws `LibraryIntentError`:

- `recoveryPending`, `duplicateRepairRequired`, `setupIncomplete` for the app-level
  gates;
- `entryNotFound` when a saved shortcut names an entry that no longer exists;
- `notEpisodic` when a progress action targets a movie.

The error conforms to `CustomLocalizedStringResourceConvertible` and every message
is added to `Localizable.xcstrings`.

### Entity and query

`LibraryEntryEntity.id` is `LibraryEntryIdentity.rawID`. The entity is a value
snapshot, not a model reference: name (the season uses the parent series name, as
in `displayName`), a subtitle such as "Season 1 · Watching · Ep 12", status as
`WatchStatusAppEnum`, favorite, score, date saved, entry type, and a poster URL. The
poster is the cached Kingfisher file when one exists, otherwise the TMDb URL.

`WatchStatusAppEnum` mirrors `AnimeEntry.WatchStatus` because App Intents metadata
extraction reads types declared in the app target; a retroactive `AppEnum`
conformance on the package enum is not relied on.

`LibraryEntryQuery`:

- `entities(for:)` parses each `rawID` with `LibraryEntryIdentity(rawID:)` and looks
  it up in `store.library` (visible entries only).
- `entities(matching:)` uses the name, translation, parent-series, and overview
  tiers of library search. The tier matcher is extracted from
  `LibrarySearchService.searchInLibrary` so both callers share one ranking.
  Intents skip the notes tier, matching the Spotlight decision below.
- `suggestedEntities()` returns Watching entries first, then recently saved ones.
- The `EntityPropertyQuery` conformance supplies the native Find action:
  status (equal/not equal), favorite (equal), score (≥), name (contains); sort by
  name or date saved.

### Spotlight

`LibraryEntryEntity` conforms to `IndexedEntity`. Its attribute set contains names,
translations, and overview, but not notes. `LibrarySpotlightIndexer` (`@MainActor`)
is scheduled from `LibraryStore.refreshLibrary()` with a short debounce. It keeps an
in-memory map from `rawID` to a hash of the indexed fields. It calls
`indexAppEntities` for new or changed entities and `deleteAppEntities` for removed
IDs. Restore, recovery, `reloadDataStore()`, remote sync merges, and duplicate
repair all end in `refreshLibrary()`, so no extra hooks are planned. The indexer does
nothing while the recovery gate blocks library activity. The first reconcile after
launch is a full pass, because the in-memory map starts empty.

A Spotlight tap runs `OpenLibraryEntryIntent` for the entity.

### Opening an entry

`OpenLibraryEntryIntent` is an `OpenIntent` and a `TargetContentProvidingIntent`
(iOS 26). `LibraryView` handles it with `.onAppIntentExecution`, resolves the
entity to an `AnimeEntry`, and calls `interaction.openDetails(for:)`. The scene
handles the routing, so one window opens the detail. An app-level "pending open"
request was rejected: every window would observe it, which is the multi-window
failure mode recorded in [008](../008-multi-window-presentation/000-plan.md).

### Tracking actions

Each action resolves the entry, checks the gates, calls the clocked mutator, saves
the main context, and posts the detail-baseline rebase below. The existing save
observers then refresh the library, queue the change for sync, and update
Spotlight.

- **Set Watch Status** calls `updateWatchStatus`, then applies
  `dateUpdateSuggestion(forTargetStatus:)` if it returns one (decision below).
- **Mark Next Episode Watched** and **Set Episode Progress** call
  `updateEpisodeProgress` for the entry's writable season and throw `notEpisodic`
  for movies. If `episodeProgressCompletionPrompt` reports completion, the action
  also sets status to Watched and applies the finish-date suggestion (decision
  below). A completion while rewatching counts the rewatch through
  `updateWatchStatus`, as in the prompt.
- **Toggle Favorite** and **Set Score** call `updateFavorite` and `updateScore`.

### Detail baseline rebase

After a tracking intent saves, it posts one main-actor notification that carries
the entry identity, the set of fields it changed, and the entry's new values for
those fields. The fields are watch status, start and finish dates, rewatch marker
and count, episode progress, favorite, and score. Each `EntryDetailSession` (all
windows, sheet or inspector) observes the notification. If the identity matches,
it copies those fields from the entry into `originalUserInfo` and sets
`originalTrackingUpdatedAt` to the entry's current value. Fields the intent did not
touch keep their baseline, so "Discard Changes" still undoes the user's own edits
and keeps the intent's change.

This is a field copy, not a merge. If the user had an unsaved edit to the same
field, the intent has already overwritten it on the shared live entry, and the
rebased baseline matches what the detail shows. No app-level registry of open
sessions is needed: a session that is not open does not observe, so nothing must
register or unregister.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Entity ID is `LibraryEntryIdentity.rawID` | It survives restore, reinstall, and sync, so saved shortcuts and Spotlight items stay valid. `PersistentIdentifier` changes on restore. |
| Intents in the app target, no extension | The store is in the app container. An extension needs an app group and a store move (rejected for this scope). |
| Spotlight indexes names, translations, and overview, not notes | Maintainer decision 2026-10-14. Notes are personal text; indexing them would show them in system search. Names-only was the other option. |
| Status change applies the date suggestion | Maintainer decision 2026-10-14. Matches the detail view's suggested answer; an intent cannot ask mid-run. Rejected: an "Update dates" parameter, status-only change. |
| Last episode marks Watched with the finish date | Maintainer decision 2026-10-14. Matches "Yes" in the completion prompt. Rejected: change progress only and mention it in the result. |
| Rebase an open detail's baseline after an intent change | Maintainer decision 2026-10-14. The HTML plan first recorded "refuse with 'Entry is being edited'". Source review then showed the baseline is captured when the detail opens, not when edit mode starts. A refusal keyed on `isEditingDetails` would still lose the intent change on a later Discard. Refusing whenever the detail is open would block shortcuts while an iPad inspector stays on an entry. Refusal also needed an app-level registry of open sessions across windows. The rebase copies only the fields the intent changed and uses a broadcast, so it needs no registry. |
| No "Add to Library" from TMDb in this entry | Maintainer decision 2026-10-14; deferred to a later change. |
| Scene-targeted open intent | Avoids a shared request that every window would observe. Rejected: app-level pending request; URL scheme. |
| App-target `WatchStatusAppEnum` mirror | Avoids depending on retroactive `AppEnum` conformance across a package boundary. Rejected: marking `DataProvider` as an `AppIntentsPackage`. |
| Reuse the library search tiers | One ranking for the search sheet and Shortcuts. Rejected: a separate predicate-based query. |

## Validation and acceptance criteria

- Focused unit tests (new file proposed:
  `MyAnimeList/Tests/MyAnimeListTests/LibraryAppIntentsTests.swift`; add it to both
  test `membershipExceptions` lists in `MyAnimeList.xcodeproj/project.pbxproj`):
  - entity mapping: ID round trip, season name and subtitle, hidden parent series
    excluded;
  - query: `entities(for:)` with unknown and deleted IDs, matching order, property
    filters;
  - tracking rules: date suggestion applied, completion marks Watched with a finish
    date, `notEpisodic` for movies, the gate errors.
- Baseline rebase: extend `MyAnimeList/Tests/MyAnimeListTests/EntryDetailSessionTests.swift`
  so an intent change followed by Discard keeps the intent's fields and restores
  the user's other edits; a session for a different entry is unchanged.
- Spotlight indexer diff logic tested in isolation if the hash/diff step can be
  separated from `CSSearchableIndex`; the index calls themselves are checked
  manually.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryAppIntentsTests'`, then
  `make build`.
- Manual simulator checks with `make run-sim` (only on an already booted simulator):
  run each action from the Shortcuts app; use App Shortcut phrases; search Spotlight
  and tap a result; open an entry with two windows on iPad; run an action while the
  detail is open, then rewrite (not append to) the notes so Done offers
  Discard Changes, discard, and see the intent change remain;
  confirm the change syncs.
- Localization: every new user-facing string in `Localizable.xcstrings` and
  `AppShortcuts.xcstrings` has en, zh-Hans, and ja values, with no manual CJK–Latin
  spaces.
- Website check: if the change ships as a user-facing feature name, update
  `../anishelf-site` as the project instructions require.

## Amendments

- Updated 2026-10-14: Spotlight subtitle and keywords set explicitly, and App Shortcut phrases no longer take an entry — see [002-spotlight-results.md](002-spotlight-results.md)
