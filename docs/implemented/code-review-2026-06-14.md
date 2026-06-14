# Code Review — 2026-06-14

Branch: `main`
Scope: the url → path change since `7661f05` (range `7661f05~1..HEAD`) — schema
`V2.7.9 → V2.8.0` image-path migration, `TMDbImagePath` / `TMDbImageURLResolver`,
the `customPosterURL` legacy dual-write shim, `PosterImageSize` extraction, and the
`KingfisherVariantImagePrefetcher` concurrency refactor.

This review follows up on `code-review-2026-06-13.md`, whose F1/F2 (CloudKit and
Codable dual-write of `customPosterURL`) were **resolved** by the commits in this
range. The findings below are new and build on that resolved state. All findings
are **Open** unless noted. Ranked most-severe first; reference by number ("F1"…).

---

## Correctness

### F1 — Decoder unconditionally prefers `customPosterPath`, letting a stale path shadow a newer legacy `customPosterURL`

**Status:** Resolved
**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift` line ~560
**Severity:** High

`customPosterPath(from:)` takes the `customPosterPath` field whenever the key is
present and only falls back to `customPosterURL` when it is absent. CloudKit saves
records with `savePolicy: .allKeys` from freshly-constructed `CKRecord`s
(`CloudLibrarySyncDatabase.swift:135`), and a still-installed pre-V2.8 build writes
**only** `customPosterURL` — it does not know the `customPosterPath` key, so the
server retains whatever path the new build last wrote.

Sequence:

1. New build syncs `{customPosterPath: /A.jpg, customPosterURL: …/original/A.jpg}`.
2. User changes the custom poster on a pre-V2.8 device → it uploads a fresh record
   carrying `customPosterURL = …/B.jpg`; the unknown `customPosterPath` key is absent
   from the upload, so the server keeps `/A.jpg`.
3. New build re-reads, hits the `if let value = record[Field.customPosterPath]`
   branch → returns `/A.jpg`, silently discarding the newer `/B.jpg` selection.

The new device never picks up the old build's poster change — the exact cross-version
data loss the dual-write shim was meant to prevent, now in the opposite direction.

**Fix:** Reconcile both fields instead of blindly preferring the path — e.g. when both
are present and the URL round-trips to a different path, prefer the one backed by the
newer write clock, or treat a present-but-divergent `customPosterURL` as authoritative
during the compat window.

---

### F2 — `AnimeEntryDetail.heroImageURL` silently jumps from `w1280` to `original`

**Status:** Resolved
**File:** `MyAnimeList/Sources/Network/TMDbImageURLResolver.swift` line ~79
**Severity:** Medium–High

`heroImageURL` is now `entry?.backdropURL`, which the resolver builds with the default
`idealWidth: .max`. The TMDb size selector (`ImagesConfiguration+URLs.swift`) maps
`.max` to the `original` rendition. The pre-change detail hero was built explicitly at
`idealWidth: 1_280` (old `InfoFetcher+Series.swift` detail flow: `heroImageURL:
imagesConfiguration.backdropURL(for:…, idealWidth: 1_280)`).

Consequences:

- The Kingfisher cache key is URL-derived, so on the first detail open after upgrade the
  `w1280` entry is a miss and the app downloads the `original` (often 3840px+) backdrop.
- This is not a one-time cost: every detail hero now loads full-size originals instead of
  `w1280`, a standing bandwidth/memory increase.

**Fix:** Resolve the hero with an explicit `idealWidth` (e.g. 1280) so it reuses the
existing cache and avoids fetching originals.

---

### F3 — Detail refetch fallback removed; cached details lacking imagery never refresh

**Status:** Resolved
**File:** `MyAnimeList/Sources/ViewModels/Library/EntryDetailViewModels.swift` line ~197
**Severity:** Medium

The guard that fell through to a network refetch when a cached detail had no
logo/hero imagery was deleted:

```swift
if let detail = entry.detail, detail.language == language.rawValue {
    apply(detail: detail, entry: entry, language: language)
-   if detail.logoImageURL != nil || detail.heroImageURL != nil {
-       isLoading = false
-       return
-   }
+   isLoading = false
+   return
}
```

Any cached same-language detail now short-circuits unconditionally. An entry whose
`logoImagePath` is `nil` (saved by an older build before logos were captured, or
migrated) never fetches the logo on open and stays blank until the language or schema
changes.

**Fix:** If the unconditional return is intentional, document why and add a test
asserting the narrowed behavior. Otherwise restore the fall-through when key imagery is
absent.

---

### F4 — `resolveLibraryDisplayFaultsBeforeDeletion` does not fault `customPosterPath` / `usingCustomPoster`

**Status:** Resolved
**File:** `MyAnimeList/Sources/Extensions/AnimeEntry+Extensions.swift` line ~124
**Severity:** Medium

The fault-resolver touches `posterPath` and `backdropPath` but not `customPosterPath`
or `usingCustomPoster`. Yet `entry.posterURL` resolves through `selectedPosterPath`,
which reads `customPosterPath` when `usingCustomPoster` is true. For a custom-poster
entry being deleted, the deletion-time UI snapshot faults the deleting object's
`customPosterPath` attribute → blank poster (or a fault-after-delete warning) during the
deletion animation. Pre-change code faulted the single `posterURL` field that held the
custom poster, so the path split introduced this gap.

**Fix:** Add `_ = customPosterPath` and `_ = usingCustomPoster` to the resolver.

---

### F5 — Migration nils the base `posterPath` for custom-poster entries

**Status:** Resolved
**File:** `DataProvider/Sources/DataProvider/Models/V2/AnimeEntryV2_8_0.swift` line ~91
(mirrored in `AnimeEntryMigrationBridgeV2_8_0.swift` line ~40)
**Severity:** Medium

Both the convenience init and the migration bridge set
`posterPath = usingCustomPoster ? nil : resolvedPosterPath`, so a custom-poster entry
ends up with no canonical base poster — defeating the new schema's separate
`posterPath` / `customPosterPath` slots. V2.7.9 conflated both into one `posterURL`
field; the migration carries that conflation forward instead of resolving it.

If `usingCustomPoster` is later cleared without a metadata refresh, `selectedPosterPath`
→ `posterPath == nil` → blank poster until the next successful TMDb fetch. The init's
`customPosterPath = resolvedCustomPosterPath ?? resolvedPosterPath` fallback also quietly
promotes a supplied base poster into the custom slot, masking a missing custom poster.

**Fix:** Preserve the base TMDb `posterPath` alongside `customPosterPath` so toggling the
custom poster off restores the original without a network round-trip.

---

## Performance

### F6 — Inner prefetch task group fans out unbounded full-size decodes

**Status:** Open
**File:** `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift` line ~385
**Severity:** Medium

The refactored `prefetch(_:)` opens a `withThrowingTaskGroup` with one task per missing
target size, and each task calls `Self.downsample(originalData, …)` on the same full-size
original via the static `.concurrent` `processingQueue`. The queue has no width limit, so
with 5 download workers × up to 3 poster sizes, ~15 multi-MB originals decode to
uncompressed bitmaps simultaneously, where the old loop decoded sequentially per work item.

On a cold-cache refresh of a large library this is a memory spike + GCD thread explosion
that can trigger jetsam/termination on older devices.

Note: concurrent `cache.store(...)` for the same `cacheKey` with different processor
identifiers is **safe** — Kingfisher keys disk/memory by `computedKey(with:identifier)`,
so the variants land in distinct entries. The issue is decode concurrency, not storage.

**Fix:** Cap the inner concurrency (1–2), or decode the largest size once and derive
smaller variants from it rather than re-decoding the original per size.

---

### F7 — Per-size cache probes serialized in `missingProcessors`

**Status:** Open
**File:** `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift` line ~429
**Severity:** Low

`missingProcessors` is now `async` and `await`s `cache.imageCachedTypeAsync(...)` in a
sequential `for` loop — one suspension per target size — where it was previously a
synchronous `.filter`. The probes are independent, so each work item issues up to 3 serial
hops to Kingfisher's I/O queue before any download begins; across a several-hundred-entry
prefetch that is hundreds of added serialized round-trips on the critical path.
`workItem.url.cacheKey` is also recomputed inside the loop.

**Fix:** Probe all sizes via a `withTaskGroup` so suspensions overlap; hoist `cacheKey`
out of the loop.

---

## Altitude / Cleanup

### F8 — `tmdbStandardFallback` hardcodes TMDb's size catalog for the display path

**Status:** Open
**File:** `MyAnimeList/Sources/Network/TMDbImageURLResolver.swift` line ~55
**Severity:** Low–Medium

The resolver uses a static `ImagesConfiguration` that mirrors TMDb's size catalog "as
represented by the pinned package fixture," while the fetch path uses live
`/configuration`. The same `file_path` can therefore resolve through two different
base URLs / size lists. If TMDb changes its `secureBaseURL` or size catalog (it has
historically), persisted-entry display URLs keep using the stale hardcoded values while
freshly-fetched metadata uses the live config — old entries' images 404 while new lookups
succeed, a partial breakage that compiles cleanly and has no test coverage. The static
fallback is a deliberate choice to keep persistence reads synchronous; the cost is that
drift is silent.

**Fix:** At minimum, add a test pinning the fallback to the package fixture so drift is
caught; ideally seed it from a cached live configuration when one is available.

---

### F9 — `apply(dto:)` hand-rolls path-precedence instead of the new helper

**Status:** Open
**File:** `DataProvider/Sources/DataProvider/Models/V2/AnimeEntryDetailBridgeV2_8_0.swift` line ~66
**Severity:** Low

`logoImagePath = dto.logoImagePath ?? TMDbImagePath.storagePath(from: dto.logoImageURL)`
is the one path-precedence site not converted to `storagePath(from:fallback:)`, and the
fallback is redundant since `AnimeEntryDetailDTO.init` already folds `logoImageURL` into
`logoImagePath`. If the helper's precedence/trimming rule changes, this site silently
diverges.

**Fix:** Use `TMDbImagePath.storagePath(from: dto.logoImagePath, fallback: dto.logoImageURL)`,
or just `dto.logoImagePath` since the DTO already resolved it.

---

### F10 — `heroImagePath` is dead across the DTO layer

**Status:** Open
**File:** `DataProvider/Sources/DataProvider/Models/Other/AnimeEntryDetailDTO.swift` line ~19
**Severity:** Low

`heroImagePath` is computed via `TMDbImagePath.storagePath` by all three `InfoFetcher`
flows and threaded through both DTO structs, but the V2.8.0 `AnimeEntryDetail` model has
no hero field and nothing reads `heroImagePath` (hero is derived from `entry.backdropURL`,
see F2). Every detail fetch runs `storagePath()` to compute a value that is dropped at
model-build time, and V2.7.9's independent stored `heroImageURL` is dropped on migration.
The dead field misleads maintainers into thinking detail owns an independent hero image.

**Fix:** Remove `heroImagePath`/`heroImageURL` from the DTOs (and the fetcher writes), or
persist a real hero field if per-detail hero selection is intended to differ from the
entry backdrop.

---

### F11 — Residual `posterTargetSize` wrapper after `PosterImageSize` extraction

**Status:** Open
**File:** `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift` line ~257
**Severity:** Low

`posterTargetSize(width:)` now only forwards to `PosterImageSize.targetSize(width:)`.
This file calls the wrapper while `KFImageView` calls `PosterImageSize.targetSize`
directly, so two spellings of the identical call coexist — exactly the duplication the
extraction was meant to remove.

**Fix:** Inline the wrapper's call sites to `PosterImageSize.targetSize` and delete it.

---

## Test Coverage

### F12 — Dedicated V279→V280 migration test seeds `detail: nil`

**Status:** Open
**File:** `DataProvider/Tests/DataProviderTests/MigrationTests.swift` line ~570
**Severity:** Low

The test targeting the V279→V280 image-path migration seeds `detail: nil`, so
`AnimeEntryDetailMigrationBridgeV2_7_9`'s URL→path conversion (hero/logo/profile/poster/
still) and the V2.8.0 child rebuild are never exercised through the actual V279 stage —
only the multi-hop V2.6.0 test touches them. A regression in the V279-specific detail
bridge (e.g. dropping `logoImagePath` or character `profilePath`) would pass this test.

**Fix:** Add a V279 source entry with a populated detail (characters/staff/seasons/
episodes with TMDb URLs) and assert the resulting paths after migration.

---

### F13 — `disablingCustomPosterClearsStaleCustomPosterURL` asserts on a never-set value

**Status:** Open
**File:** `DataProvider/Tests/LibrarySyncTests/LibraryEntrySyncTests.swift` line ~378
**Severity:** Low

The test seeds the custom poster via a non-TMDb `example.com` URL, which the url→path
init converts to `customPosterPath == nil` (host mismatch). The post-disable assertion
`customPosterPath == nil` is therefore vacuously true — the clearing logic could be
entirely broken and the test would still pass.

**Fix:** Seed with a TMDb-hosted URL (or a `/path.jpg` string) so a non-nil
`customPosterPath` actually exists to be cleared.

---

## Refuted candidates (recorded to avoid re-flagging)

- **Codable snapshot "stale path shadows newer URL"** (mirror of F1 for
  `LibraryEntrySyncSnapshot`): refuted. `Codable` encodes whole objects; there is no
  CloudKit-style per-field merge, so the `.allKeys` partial-update vector does not apply.
- **Non-TMDb custom poster dropped on migration**: refuted. Custom posters always
  originate from `imagesConfiguration.posterURL(for:)` (TMDb-hosted), so
  `storagePath(from: URL)` extracts them correctly. The non-TMDb-host concern is real only
  for hand-crafted/foreign data, which does not occur in practice.
- **Concurrent `cache.store` for same cacheKey racing**: refuted (see F6 note).
- **`withCheckedContinuation` double/never-resume in `downsample`**: refuted — resumes
  exactly once on the queue.
