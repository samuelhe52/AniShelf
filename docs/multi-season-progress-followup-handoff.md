# Multi-Season Episode Progress Follow-Up Handoff

## Goal

After the TMDb package migration lands (which landed in the last commit), fix multi-season episode progress by using parent `series` detail only.

Do **not** rely on hidden child season entries for visible series.

## Desired Behavior

- The progress label stays unchanged.
  - It should still describe the latest changed season only.
- The detail tracking control stays season-specific.
  - For multi-season entries, the selected season should default to the last changed season.
- The badge / inline indicator / poster overlay fraction for multi-season series should be computed against the aggregated numbered-season episode count of the whole series.
- Specials must be excluded from that aggregated fraction. Store episodeCount for specials if available, but do not include them in the aggregate fraction denominator or numerator.

## Root Cause

Current parent-series detail persists only thin season summaries:

- `id`
- `seasonNumber`
- `title`
- `posterURL`

There is no stored per-season `episodeCount`, so:

- `episodeProgressLimit(forSeason:)` cannot resolve limits for true multi-season `series`
- multi-season sliders disappear when `summary.episodeCount == nil`
- the series progress fraction cannot form a denominator

Once the package migration lands, `tvSeries.details(...)` should already expose `season.episodeCount`, which removes the need for extra season-detail requests.

## Recommended Implementation

1. Add `episodeCount: Int?` to persisted season summaries:
   - `AnimeEntrySeasonSummaryDTO`
   - `AnimeEntrySeasonSummary`
   - legacy bridge payloads as needed
2. Bump the SwiftData schema from `2.7.7` to `2.7.8`.
3. Use a lightweight migration from `2.7.7` to `2.7.8`.
   - migrated season summaries start with `nil` counts until refreshed
4. Update [MyAnimeList/Sources/Network/InfoFetcher+Series.swift](../MyAnimeList/Sources/Network/InfoFetcher+Series.swift):
   - pass `TVSeason.episodeCount` through `makeSeasonSummaries(...)`
5. Update `episodeProgressLimit(forSeason:)` in `AnimeEntryEpisodeProgressHelpers.swift`:
   - for `series`, read the per-season limit from parent `detail.seasons`
   - do not use `childSeasonEntries` as the primary data source for visible series
   - keep the existing single-numbered-season fallback to parent `detail.episodeCount` so older pre-refresh entries degrade reasonably
6. Update the library fraction calculation in [MyAnimeList/Sources/Views/Library/LibraryEntrySnapshot.swift](../MyAnimeList/Sources/Views/Library/LibraryEntrySnapshot.swift):
   - numerator = sum of watched-through episodes across numbered seasons
   - denominator = sum of numbered-season episode counts
   - specials excluded from both
   - if any required numbered-season count is still unknown, return `nil` fraction instead of a partial aggregate
7. Keep the detail editor season-specific.
   - The last-changed-season selection sync in `EntryDetailTrackingComponents.swift` is directionally correct and can be preserved if it still matches the final implementation.

## Important Non-Goals

- Do not introduce hidden child-season hydration for visible series.
- Do not require extra per-season TMDb requests if `season.episodeCount` is already available from `tvSeries.details(...)`.
- Do not change the displayed progress label format as part of this task.

## Verification

- `make build`
- add/update `DataProvider` tests proving series season limits come from parent `detail.seasons`
- add/update `MyAnimeList` tests proving:
  - multi-season aggregate fraction uses numbered seasons only
  - specials do not contribute
  - label still reflects latest changed season only
  - multi-season fraction becomes available once refreshed parent detail has season counts

## Acceptance Criteria

- badges and poster overlays show the aggregated numbered-season fraction
- specials remain excluded from aggregate completion
