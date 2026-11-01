# 036 — Image variant catalog: Plan

| Field | Value |
| --- | --- |
| Status | Implemented; runtime pass and release What's New entry pending |
| Anchor date | 2026-10-30 |
| Origin | Maintainer request (2026-10-30) after the category review cells missed the library poster cache (fixed in `ab73916d`); the per-size caching layers had become too easy to get wrong |
| Related | [023-library-display-cache](../023-library-display-cache/000-plan.md), [026-library-performance-benchmarks](../026-library-performance-benchmarks/000-plan.md), [035-single-entry-categories](../035-single-entry-categories/000-plan.md) |

## Background

A TMDb image shown in AniShelf passes through three size decisions:

1. **Rendition** — the TMDb size segment in the URL (`w342`, `w500`, `original`).
2. **Decoded variant** — the bitmap Kingfisher downsamples to and stores. Kingfisher keys
   its caches on *URL + processor identifier*, so this layer depends on layer 1.
3. **Display** — the frame the view lays the bitmap into.

Today each call site supplies layers 1 and 2 independently: it resolves a URL
(`TMDbImageURLResolver.url(for:role:idealWidth:)`, `posterURL(for: TMDbPosterDisplayType)`,
or a bare `posterURL`) and separately passes `targetSize:` or `targetWidth:` to
`KFImageView`. A cache hit requires both to agree with what
`LibraryImageCacheService` prefetched, and nothing enforces that.

Observed consequences (as of `ab73916d`):

| Site | Problem |
| --- | --- |
| `CategoryDraftPosterCell`, `CategoryDraftSieve` | Grid `targetSize` with the original-size URL; every cell re-downloaded the full poster. Fixed in `ab73916d` by switching to `posterURL(for: .grid)`. |
| `MacEntryDetailHeader` (via `EntryDetailView`) | Receives `entry.posterURL` (the `original` rendition) and downsamples to 192×288. Every inspector open fetches the full poster and stores a variant nothing prefetches. |
| `MacBatchSelectionPanel`, `MacInspectorPosterFlight` | Grid URL with the literal `targetWidth: 360`; matches the grid variant by coincidence. |
| Episode and season-episode cards | `idealWidth: 500` for stills; the still catalog stops at `w300`, so the rule falls through to `original`. Decoded with poster geometry (500×750) for a 126×74 pt frame. |
| Character/staff cards | `w185` rendition, decoded to a 240-wide target. |
| Hero fallback in `EntryDetailViewModels` | `entry.backdropURL ?? entry.posterURL`; the fallback is the original poster at the backdrop's decode size. |
| `LibraryImageCacheService.cachedImageProcessorIdentifiers` | A hand-maintained size list used for cache removal; any variant missing from it leaks on entry deletion. |
| `TMDbPosterDisplayType.targetSize` | `#if os(macOS)` special case: Mac list rows reuse the `w342` URL but decode to 120 wide. |

Two facts make the current numbers misleading:

- `idealWidth` is rounded **up** to the first catalog size at least that wide
  (`ImagesConfiguration.imageSizePathComponent` in the TMDb package): list 240 → `w342`,
  grid 360 → `w500`, gallery 1000 → `original`, still 500 → `original`.
- `DownsamplingImageProcessor` uses only `max(width, height) × scaleFactor` as the
  ImageIO thumbnail limit, and AniShelf never sets `scaleFactor`, so the default of 1
  applies. A target "size" is effectively one max-pixel-dimension number; the
  2:3 geometry in `PosterImageSize` has no effect.

## Goals

- One place defines every cached TMDb image variant: its role, its exact TMDb
  rendition, and its decoded max pixel dimension.
- Call sites name a variant. They cannot pair a URL from one variant with a decode
  size from another.
- Prefetch, display, and cache removal all derive URL and processor from the same
  catalog; no hand-kept size or identifier lists.
- Fewer poster variants: list and grid share one.
- Prompt existing users in the release's What's New entry to clear the image cache,
  which is now orphaned.

### Non-goals

- Disk-expiration policy (`StorageExpiration` at call sites, the long-term gallery
  setting). Expiration is not part of the cache key; it stays where it is.
- Images that are not library-tracked and never prefetched: search results
  (`TMDbSearchClient`, `MovieResultItem`, `SeriesResultItem`), the poster picker
  (`PosterBrowserView`, `PosterGridView`, `PosterSlides`), broadcast search/validation,
  and sharing-card export, which needs the full-resolution poster.
- A live or persisted TMDb `/configuration` snapshot; `ImagesConfiguration.tmdbStandardFallback`
  stays the base.

## Design / approach

### Catalog

Proposed new file `MyAnimeList/Sources/Network/TMDbImageVariant.swift`:

```swift
enum TMDbImageVariant: CaseIterable, Hashable, Sendable {
    case posterThumbnail
    case posterFull
    case backdrop
    case logo
    case profile
    case still

    var role: TMDbImageRole { … }
    /// Exact TMDb size segment; must exist in `tmdbStandardFallback` for `role`.
    var rendition: String { … }
    /// Longest edge, in pixels, of the decoded and cached bitmap.
    var maxPixelDimension: CGFloat { … }
}

/// A persisted TMDb path paired with the variant it is displayed as.
struct TMDbImage: Hashable, Sendable {
    let path: String
    let variant: TMDbImageVariant

    var url: URL? { … }                        // rendition-resolved; SVG logos use `original`
    var processor: any ImageProcessor { … }    // Downsampling, or SVGImageProcessor for .svg
}
```

Proposed values — these preserve current renditions except where noted:

| Variant | Rendition | Max px | Replaces | Change |
| --- | --- | --- | --- | --- |
| `posterThumbnail` | `w500` | 540 | `.list` (`w342`/360, Mac 180), `.grid` (`w500`/540), season posters (`w342`), Mac header, batch panel, poster flight, category cells | List and Mac list merge into grid |
| `posterFull` | `original` | 1500 | `.gallery`; hero fallback | Hero fallback gets a cacheable variant |
| `backdrop` | `w1280` | 1200 | backdrop 1280 / 1200×675 | None |
| `logo` | `w500` (SVG: `original`) | 500 | logo 500 / 500×500 | None |
| `profile` | `w185` | 278 | profile 185 / 240-wide target | Decode cap matches the source (`w185` posters are 185×278) |
| `still` | `w300` | 300 | still `original` / 500×750 | Stops downloading full-resolution stills |

`TMDbImageURLResolver.url(for:role:idealWidth:)` becomes private to the catalog for
these roles. The rendition is chosen by name, not by rounding a width.
`TMDbPosterDisplayType` and `MyAnimeList/Sources/Utils/PosterImageSize.swift` are deleted.

### Model accessors

Replace URL accessors with `TMDbImage` accessors where the image is library-displayed:

- `AnimeEntry.posterImage(_:)`, `LibraryEntrySnapshot.displayPosterImage(_:)`,
  `EntryMetadata.posterImage(_:)` (take `.posterThumbnail` / `.posterFull`).
- `AnimeEntry.backdropImage`, `AnimeEntryDetail.logoImage`, and `image` properties on
  the character, staff, season, and episode summaries and their DTO counterparts
  (the DTOs keep the legacy-URL fallback through the raw-URL path below).
- `EntryDetailViewModels` stores `TMDbImage?` for hero, logo, and card images instead
  of `URL?`.

`AnimeEntry.posterURL` (the `original` URL) stays for sharing export and
`LibraryEntryConverter`; it is no longer passed to `KFImageView`.

### KFImageView

Two initializers:

- `KFImageView(image: TMDbImage?, …)` — the library path; URL and processor come from
  the variant.
- `KFImageView(url: URL?, maxPixelDimension: CGFloat? = nil, …)` — for the non-goal
  sites above. Its doc comment states it is not prefetched or tracked for removal.

The `targetWidth:`/`targetSize:` parameters go away. `cacheOriginalImage` and the
memory-cache seeding in `init` stay.

### LibraryImageCacheService

- `ImagePrefetchTarget` becomes `TMDbImage`; work items still group by URL, so one
  download feeds every variant of that URL.
- Targets: `posterThumbnail` always, plus `posterFull` when long-term gallery caching
  is enabled; `backdrop`; `logo`.
- `relatedImageURLs` / `removeCachedImages(for:)` become `relatedCacheKeys(for:)` /
  `removeCachedImages(_:)` over `CachedImageKey` (URL + processor identifier). Each
  image contributes its processor entry plus the unprocessed entry (`""`) for its URL;
  posters cover every poster variant of both stored paths and their original-size
  URLs. `cachedImageProcessorIdentifiers` is deleted.

### Release migration

Changing renditions and decode sizes orphans most of the existing disk cache until
it expires (up to 90 days for long-term entries). It is not migrated. Instead, the
release's What's New entry (`WhatsNewRegistry` in `MyAnimeList/Sources/Models/WhatsNewModels.swift`)
explains this and offers an action:

- New `WhatsNewEntry.Action.Kind.clearImageCache`, handled by `WhatsNewActionRunner`.
  It calls `LibraryProfileSettingsActions.clearImageCacheAndPrefetch()`, which awaits
  Kingfisher's `clearCache()` and then runs `prefetchAllImages()`, so the library is
  warm again under the new variants. The clear must finish first: prefetch skips
  variants it still finds on disk.
- The new copy is added to `Localizable.xcstrings` with `ja` and `zh-Hans`.

The release version is set when the entry is written, at release time.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Closed variant enum owning rendition + decode size | Makes a mismatched pair unrepresentable and lets prefetch/removal enumerate `allCases`. Alternative: keep `TMDbPosterDisplayType` and add lint/tests for call sites — still allows the mismatch, only detects it. |
| Merge list and grid into `posterThumbnail` (maintainer-approved 2026-10-30) | Halves poster downloads and prefetch work, removes the Mac special case, and gives the Mac header/batch/flight/category sites an obvious choice. Cost: list rows decode about 540 px instead of 360 px (~0.8 MB vs ~0.35 MB each), negligible for visible rows. |
| Explicit rendition strings instead of `idealWidth` | The round-up rule hid `w342`/`w500`/`original` behind 240/360/1000 and sent stills to `original`. A unit test asserts every rendition exists in `tmdbStandardFallback`. |
| One `maxPixelDimension` instead of `CGSize` | Matches what `DownsamplingImageProcessor` actually uses; the 2:3 height was dead information. |
| Keep downsampling (do not cache raw renditions) | `posterFull` is `original` (often 2000×3000), and scroll performance from [026](../026-library-performance-benchmarks/000-plan.md) depends on small decoded bitmaps. Dropping the processor would make the cache key URL-only but regress memory. |
| Orphaned cache: What's New prompt to clear (maintainer decision 2026-10-30) | Simple and user-visible. Alternative: a silent one-time `clearDiskCache()` on first launch — rejected by the maintainer in favor of a suggestion. Kingfisher expiry would also reclaim the space eventually. |
| `still` at `w300` | The 126×74 pt card needs about 378 px at 3×; `w300` is slightly soft there, `original` is many times larger. Inference: transient episode images do not justify full-resolution downloads. Revisit if stills look soft on device. |
| Raw-URL `KFImageView` initializer retained | Search, the poster picker, and broadcast images are not TMDb library images or not prefetched; forcing them into the catalog adds variants with no cache benefit. |

## Validation and acceptance criteria

- `rg 'targetWidth:|targetSize:|TMDbPosterDisplayType|PosterImageSize'` over
  `MyAnimeList/Sources` finds nothing outside `SVGImageProcessor`.
- No library-displayed `KFImageView` uses the raw-URL initializer (review the
  remaining raw-URL sites against the non-goal list).
- Tests, extending existing files rather than adding parallel ones:
  - `TMDbImageAndTranslationTests+ImageURLResolution.swift`: each variant resolves to
    its rendition, and every rendition exists in `tmdbStandardFallback`; custom-poster
    and missing-poster behavior is kept.
  - `LibraryMetadataRefreshTests+ImageCache.swift`: default and gallery-enabled
    prefetch targets, URL-level work-item grouping, and related-image collection
    updated to `TMDbImage`.
  - What's New action routing is one-line wiring; no test (no existing runner tests).
- `make test-app-mac APP_TEST_ONLY=…` for those suites (the simulator was in use by
  another agent), `make build`, and `make build-mac`.
- Runtime: with a warm cache after prefetch, scroll the library grid and list, open
  the gallery, open the Mac inspector, and open the category sieve; no poster should
  show a spinner. This requires the maintainer's visual pass on Mac.

## Amendments
- Updated 2026-10-30: removal is keyed by `CachedImageKey` rather than `TMDbImage`, and
  `TMDbImage` gained `init(fallbackURL:variant:)` for legacy DTO URLs; tests run on
  macOS instead of the simulator. Corrected in place — see [001-action.md](001-action.md)
