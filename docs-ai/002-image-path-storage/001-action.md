# 002 — Image-path storage and bounded rendering: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-13 | Persist TMDb image paths | `7661f05` |
| 2026-06-13–14 | Preserve legacy custom poster writes and precedence | `6adb5c1`, `86595cc` |
| 2026-06-14 | Bound hero rendition and image decode concurrency | `a47201a`, `05bdca9` |
| 2026-06-14 | Resolve remaining image-path review findings | `2c212f1` |
| 2026-09-05 | Preserve records during image-path migration | `1143fa4` |

## Outcome and current state (as of 2026-10-07)

The model/network boundary separates path storage from display URL resolution.
The migration chain contains V2.7.9-to-V2.8.0 image bridges. Historical compatibility
and performance reports are attached to this feature rather than scattered under
an undifferentiated implemented-docs directory.

Key source files:

- `DataProvider/Sources/DataProvider/Models/Other/TMDbImagePath.swift`
- `DataProvider/Sources/DataProvider/Models/V2/ImagePathMigrationBridgeV2_8_0.swift`
- `MyAnimeList/Sources/Network/TMDbImageURLResolver.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryImageCacheService.swift`

## Deviations from plan

The source reviews contain both resolved and rejected findings. Retaining them
does not accept every proposed fix or reopen all historical concerns.

## Open questions

The June 14 review marks its fallback-size-catalog concern open. Its current
relevance needs a fresh focused investigation before changing the resolver.
