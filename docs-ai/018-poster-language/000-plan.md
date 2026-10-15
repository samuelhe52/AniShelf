# 018 — Default poster language and onboarding language step: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-15 |
| Origin | User email (David, 2026-10-15) forwarded by the maintainer; interactive plan drafted by Codex and revised in review (`~/.codex/artifacts/anishelf-poster-language-20261015/plan.v2.html`, local only) |
| Related | [016-settings-hub](../016-settings-hub/000-plan.md), [inline language row](../016-settings-hub/003-inline-language.md) |

## Background

The default poster for a new or refreshed entry is chosen by
`TMDbImageSelection.posterMatchRules()`: original language first, then the Anime
Info Language, then a no-language poster (seasons finally fall back to the
season's own `poster_path`). A user who reads metadata in Chinese therefore sees
the Japanese poster for a Japanese anime even when TMDb has a Chinese one.

The user asked for (1) an option to prefer posters in the Anime Info Language,
falling back to the original language, and (2) a language step in first-run
setup right after the TMDB API key, so the choice is made before the library
fills up. The maintainer replied that both would be considered.

## Goals

- Add a **Default Poster** preference with two modes: *Prefer Original Language*
  (today's behavior) and *Follow Anime Info Language*.
- Apply the mode in every path that writes an entry's default poster: add,
  hydrate, metadata refresh, backup conversion/restore, CloudKit hydration of a
  missing entry, and parent-series creation.
- Show the Anime Info Language and Default Poster controls as a fourth
  onboarding step, after the key validates and before the library opens.
- Let existing users opt in from Settings and offer to refresh existing entries.

### Non-goals

- No Simplified/Traditional Chinese choice. TMDb `ImageMetadata` exposes only
  `languageCode` (no region), and image requests are limited to `ja`, `en`,
  `zh`, and null, so a `zh` poster may be Traditional.
- No change to search-result thumbnails, logos, backdrops, SwiftData schema, or
  stored path formats. Custom posters always win.
- No separate poster-only refresh path.

## Design / approach

**Preference.** Proposed `MyAnimeList/Sources/Models/PosterLanguagePreference.swift`:
`enum PosterLanguagePreference: String { case originalLanguage, animeInfoLanguage }`
stored under a new `UserDefaults` key `.defaultPosterLanguage`. Absent or unknown
values resolve to `.originalLanguage` for everyone, so upgrades and fresh
installs behave as today until the user opts in. The key joins
`allPreferenceKeys` (backup) and `cloudSyncedPreferenceKeys` (iCloud settings).

**Selection.** `TMDbImageSelection.preferredPosterPath` and
`posterLanguagePriority` take the mode; `.animeInfoLanguage` swaps the first two
rules (metadata language, then original language, then no-language). Duplicate
codes collapse as today.

**Plumbing.** The InfoFetcher methods that build `EntryMetadata` for library
writes (`latestInfo`, `fetchInfoFromTMDB`, `movieInfo`, `tvSeriesInfo`,
`tvSeasonInfo` and their `latest*` variants) gain a required
`posterLanguage:` parameter, so the compiler finds every caller. Search-only
lookups (`animeMovieInfo`, `animeTVSeriesInfo`) keep original-first.
`LibraryStore.posterLanguage` reads the preference from its injected
`LibraryPreferences`; refresh, conversion, sync hydration, and parent-series
creation read it once per operation and pass it down.

**Onboarding.** `TMDbAPIOnboardingView.Step` gains `.languages`. In onboarding,
`TMDbAPIKeyEntryViewModel` validates the key but holds it instead of saving;
the view advances to the language step, whose primary button saves the key via
`TMDbAPIKeyStorage.saveKey`. Because the root in `MyAnimeListApp` already
switches to `LibraryView` when a key exists, saving last needs no new gate. The
settings sheet (`TMDbAPIConfigurator`) keeps save-on-validate. The step reuses
`LibraryProfileLanguageSettingsRow`, extended with the poster control.

**Settings.** The inline language row in the hub and workspace layouts shows the
Default Poster menu. Changing the mode triggers the existing language-change
refresh alert (copy generalized to cover posters), which reuses
`refreshInfos()`; the refresh already preserves custom posters
(`LibraryMetadataRefresher` passes `preservingCustomPoster`). The manual poster
browser sorts with the same mode so the default poster stays first.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Default *Prefer Original Language* for new and existing users | Maintainer decision. No new/existing split is needed; absent key means today's behavior. Rejected: default new users to *Follow Anime Info Language*. |
| Defer the key save to the language step | Avoids a persisted "pending setup" flag, restart resume, and cross-window state. Quitting before Start just restarts at the key step. Rejected: save the key first and gate the root on a pending flag (Codex draft). |
| Required `posterLanguage:` parameter | Compiler-enforced coverage of every write path, including CloudKit hydration and parent-series creation that the first draft missed. Rejected: defaulted parameter (silent misses) or a mutable fetcher property. |
| Reuse full metadata refresh | One progress flow; titles/descriptions also refresh. Rejected: separate poster-only refresh. |
| Reuse the existing language-change alert | It already exists in Settings for metadata-language changes. |

## Validation and acceptance criteria

- Unit: `TMDbImageAndTranslationTests` covers Follow mode choosing the metadata
  language, falling back to original then no-language, and original mode
  unchanged. Extend existing mapping/refresh tests only where a distinct path is
  otherwise unprotected.
- Preferences: absent value resolves to original; key is in backup and cloud
  allowlists.
- `make build`, focused `make test-app-sim` suites; `make run-sim` for the
  onboarding step and settings row if a simulator is already booted.
- Manual: Change API Key keeps save-on-validate and shows no language step.

## Amendments

- Updated 2026-10-15: Language moved back to its own settings page; Japanese copy shortened. This supersedes the "inline language row" wording in Design above — see [002-language-page.md](002-language-page.md)
