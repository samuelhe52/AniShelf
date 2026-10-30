# 036 — Image variant catalog: Action record

## Timeline
| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-30 | Plan written; maintainer approved merging list and grid posters and a What's New prompt to clear the orphaned cache | [000-plan.md](000-plan.md) |
| 2026-10-30 | Catalog, call-site migration, prefetch/removal rewrite, What's New action kind, tests | Branch `feat/image-variant-catalog` (commit "refactor: Derive image cache variants from one catalog") |

## Outcome and current state (as of 2026-10-30)

- `TMDbImageVariant` holds the six cached variants with an exact `ImageSize` rendition and
  a `maxPixelDimension`. `TMDbImage` (URL + variant) is the only input to library
  `KFImageView`s; its processor is derived from the variant.
- URLs resolve through the TMDb package's `…URL(for:size:)`, which returns `nil` for a size
  missing from the catalog, so a bad rendition fails visibly rather than rounding.
- `TMDbPosterDisplayType`, `PosterImageSize`, `idealWidth` resolution for persisted paths,
  and the hand-kept removal identifier list are gone. `TMDbImageURLResolver` keeps
  `originalURL(for:role:)` for sharing export and conversion.
- `KFImageView` has `init(image:)` for catalog images and `init(url:maxPixelDimension:)`
  for search, poster picker, and broadcast images.
- Prefetch targets and work items are `TMDbImage`-based; removal uses `CachedImageKey`.
- `WhatsNewEntry.Action.Kind.clearImageCache` exists and is wired, but no registry entry
  uses it yet: release notes are written at release time.

Key files:
- `MyAnimeList/Sources/Network/TMDbImageVariant.swift`
- `MyAnimeList/Sources/Network/TMDbImageURLResolver.swift`
- `MyAnimeList/Sources/Extensions/SVGImageProcessor.swift` (`LibraryImageProcessorFactory`)
- `MyAnimeList/Sources/Views/Gadgets/KFImageView.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift`
- `MyAnimeList/Sources/ViewModels/Gadgets/WhatsNewActionRunner.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryProfileSettingsActions.swift`

## Deviations from plan

- Removal is keyed by `CachedImageKey` (URL + processor identifier) instead of
  `TMDbImage`, because original-size poster URLs (cached unprocessed, for example by
  sharing) have no variant.
- `TMDbImage(fallbackURL:variant:)` wraps legacy DTO URLs; the plan routed those through
  the raw-URL `KFImageView` initializer.
- Logos keep a square 500 bound and backdrops move from 1200×675 to a 1200 longest edge;
  backdrops are 16:9, so the decoded size is unchanged, but the processor identifier
  changes.

## Validation

- `make build` (iOS): succeeded.
- `make build-mac`: succeeded.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibraryMetadataRefreshTests MyAnimeListTests/TMDbImageAndTranslationTests MyAnimeListTests/EntryDetailViewModelTests MyAnimeListTests/WhatsNewAndRefreshTests'`: all four suites passed.
- `make test-app-mac` (full app suite): one failure,
  `LibrarySyncCoordinatorTests/categoryDefinitionsRoundTripThroughSettingsPayload`
  (expects `categoriesEnabled`/`categoryStripEnabled` false, reads true). The diff does
  not touch category settings; not checked against `main`.
- Acceptance grep for `targetWidth:|targetSize:|TMDbPosterDisplayType|PosterImageSize`
  outside `SVGImageProcessor`: no matches.
- Not run: simulator tests (simulator in use by another agent), any runtime or visual
  pass.

## Open questions

- Runtime check from the plan (warm cache: no spinners in grid, list, gallery, Mac
  inspector, category sieve) is pending the maintainer's visual pass.
- `still` at `w300` may look soft on 3× screens.
- The release's What's New entry must add a `.clearImageCache` action and its
  `ja`/`zh-Hans` copy.
