# 020.010 — Poster cache alignment for list and grid

## Context

On 2026-10-20 the maintainer reported poor macOS list and grid performance,
especially in the list, and suspected that its sized posters were not cached.
This amendment records the implemented fix after source investigation; it was
written after implementation at the maintainer's request.

Source inspection confirmed a prefetch mismatch: compact Mac rows requested a
120×180 processed poster, while `LibraryImageCacheService` warmed 240×360.
Both used the same `w342` TMDb URL, but Kingfisher also includes the processor
identifier in the cache key. The smaller variant was cached after display;
prefetching did not supply that variant. The grid's 360×540 variant already
matched its prefetch target.

## Change and decisions

- `TMDbPosterDisplayType.targetSize` now owns processed poster sizes. List rows,
  grid cards, and prefetch use that policy: 120×180 for the Mac list, 240×360
  for the iOS list, and 360×540 for the grid. Gallery remains 1000×1500.
  Server rendition selection remains separate through `idealWidth`.
- Keep the compact list's smaller bitmap instead of increasing display to
  240×360 merely to match the old prefetch target. This preserves its existing
  image size while correcting cache warming.
- Cache cleanup now includes the 120×180 processor identifier and retains the
  previous sizes so existing variants can still be removed.
- `KFImageView` enables Kingfisher's `.asyncCacheTypeCheck`. After a memory
  miss, disk existence probes run on Kingfisher's I/O queue. The synchronous
  memory lookup used to avoid placeholder flashes remains intact. This shared
  loader change applies on iOS as well as macOS.

The existing disk cache is not migrated or cleared. Missing small variants are
populated by subsequent display or image prefetch. Prefetch continues to store
processed variants on disk without retaining the full library in memory.

## Validation and limits

During this implementation session:

```sh
make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibraryMetadataRefreshTests MyAnimeListTests/TMDbImageAndTranslationTests'
```

All 48 tests passed. The existing default-prefetch test now checks the
platform-specific list size and grid size. The suites also cover gallery cache
policy, prefetch grouping, related image URLs, and display URL resolution.
An initial method-level test filter selected zero tests; the suite-level run
above supplied the actual validation. Scoped `swift format lint` and
`git diff --check` passed.

No scrolling benchmark, runtime UI check, or iOS test run was performed for this
change. The mismatch is a verified cache defect, but its contribution to the
reported list lag remains unmeasured. The earlier investigation's suggestion
that disk probes necessarily ran on the main thread was not established:
Kingfisher's async API can switch executors. Moving probes to the I/O queue
does not by itself prove a scrolling improvement.

## Refs

- `MyAnimeList/Sources/Network/TMDbImageURLResolver.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift`
- `MyAnimeList/Sources/Views/Gadgets/AnimeEntryListRow.swift`
- `MyAnimeList/Sources/Views/Gadgets/KFImageView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryGridItem.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryMetadataRefreshTests+ImageCache.swift`
- [Original memory-cache start decision](008-mac-native-ui.md)
- [Library fixture and benchmarks](../026-library-performance-benchmarks/000-plan.md)
