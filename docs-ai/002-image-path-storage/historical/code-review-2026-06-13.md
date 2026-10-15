# Code Review — 2026-06-13

Branch: `main` (working-tree + upstream diff)  
Scope: image-path migration (V2.7.9 → V2.8.0), `BasicInfo` → `EntryMetadata` rename, `KingfisherVariantImagePrefetcher`, CloudKit custom-poster field migration.

Findings are ranked most-severe first. Reference them by number (e.g. "F1", "F2").

---

## Correctness

### F1 — CloudKit encoder writes only `customPosterPath`; old builds read only `customPosterURL`

**Status:** Resolved

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift` line ~130  
**Severity:** High

The new `record(from snapshot:)` writes `record[Field.customPosterPath]` and never writes `record[Field.customPosterURL]`. Any device still on the previous build reads only `Field.customPosterURL`, finds it absent, decodes `nil`, and the entry shows a blank poster with `usingCustomPoster = true`.

The old and new field names are completely disjoint — there is no overlap period where both are written. The tombstone clear of `customPosterURL` is for deletion only and does not help here.

**Fix:** Write both fields during the transition window — `record[Field.customPosterURL] = url?.absoluteString` alongside `record[Field.customPosterPath]` — until the old build is retired.

---

### F2 — Custom `encode(to:)` omits `customPosterURL`, breaking any Codable-based sync path on old builds

**Status:** Resolved

**File:** `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift` line ~571  
**Severity:** High

The new hand-written `encode(to:)` writes `customPosterPath` but never `customPosterURL`. If `LibraryEntrySyncSnapshot` is serialized to JSON anywhere (backup/restore, iCloud Drive, test fixtures), an old build's synthesized decoder only reads `customPosterURL`, gets `nil`, and drops the user's custom poster selection. Unlike the CloudKit path there is no field-level override to protect it.

**Fix:** Add `try container.encodeIfPresent(customPosterPath.map { TMDbImagePath.fullURL(for: $0) }, forKey: .customPosterURL)` until backward compat is no longer required, or document that the Codable path is not used for cross-version interchange.

---

### F3 — `resolveLibraryDisplayFaultsBeforeDeletion` no longer accesses `detail.heroImagePath`, leaving the stored field un-faulted before context deletion

**Status:** Invalid

---

## Performance

### F4 — `missingProcessors(for:)` calls synchronous `imageCachedType(forKey:processorIdentifier:)` on a cooperative thread pool thread

**Status:** Resolved

**File:** `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift` line ~403  
**Severity:** Low–Medium

`imageCachedType(forKey:processorIdentifier:)` is a synchronous Kingfisher method that falls through to a disk `stat` when the memory cache misses. It is called inside an unstructured `withTaskGroup` task — not actor-isolated. On a cold cache, a 200-entry library prefetch with 3 sizes each issues ~600 synchronous disk checks across concurrent workers, potentially stalling cooperative threads and starving UI or network work.

**Fix:** Move the cache-check loop to a `Task.detached(priority: .background)` context, or use Kingfisher's async `retrieveImageInDiskCache(forKey:options:)` if available.

---

### F5 — Per-image variant `cache.store(...)` calls are serialized; they are independent and could overlap

**Status:** Resolved

**File:** `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift` line ~371  
**Severity:** Low

After downloading a single image, each downsampled size variant is stored with `await cache.store(...)` in a sequential `for` loop. The three writes per image (240, 360, 1000 wide) are fully independent — all derived from the same already-in-memory `originalData`. On a 200-entry refresh this serializes potentially hundreds of CPU + disk operations unnecessarily.

**Fix:** Replace the sequential loop with a nested `withTaskGroup` to overlap the per-variant process-and-store calls.

---

## Code Quality

### F6 — `posterTargetSize(width:)` duplicated in `KFImageView` and `LibraryImageCacheService` with no shared constant

**Status:** Resolved

**File:** `MyAnimeList/Sources/Views/Gadgets/KFImageView.swift` line ~122 and `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift` line ~261  
**Severity:** Low

Both types define an identical `posterTargetSize(width:) -> CGSize` that returns `CGSize(width: w, height: w * 1.5)`. `LibraryImageCacheService` names the constant `posterHeightRatio`; `KFImageView` hardcodes `1.5`. If the ratio ever changes, both must be updated in sync — missing one causes prefetch cache misses (images stored at one size not found at display time, forcing redundant re-downloads).

**Fix:** Extract to a shared file, e.g. `ImageSizeConstants.posterHeightRatio: CGFloat = 1.5` and a free function `posterTargetSize(width:)` both can import.

---

### F7 — `TMDbImagePath.storagePath(from: path) ?? TMDbImagePath.storagePath(from: url)` copy-pasted across 6+ DTO initialisers

**Status:** Resolved

**File:** `DataProvider/Sources/DataProvider/Models/Other/AnimeEntryDetailDTO.swift` lines ~60, ~96, ~199, ~235, ~311, ~355 and others  
**Severity:** Low

The path-then-URL fallback pattern:

```swift
self.xyzPath =
    TMDbImagePath.storagePath(from: xyzPath)
    ?? TMDbImagePath.storagePath(from: xyzURL)
```

appears in at least 6 DTO inits. Any change to the fallback logic (scheme normalization, logging, etc.) requires touching all sites. A single helper — e.g. `TMDbImagePath.storagePath(from path: String?, fallback url: URL?) -> String?` — would centralize the precedence rule.

---

### F8 — `imagePrefetchWorkItems(from:)` sorts by URL string on every production call to satisfy test-determinism

**Status:** Resolved

**File:** `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift` line ~254  
**Severity:** Low

The work-item array is sorted by `url.absoluteString` in the production implementation solely so test assertions can compare against a fixed order. On a 200-entry library refresh this adds an O(n log n) sort for no runtime benefit.

**Fix:** Remove the sort from the production path; sort the result in the test assertion instead.

---

### F9 — `LibraryEntrySyncSnapshot` `URL`-overload init is easy to misuse: a relative path string wrapped in `URL(string:)` silently becomes `nil`

**Status:** Invalid
