# 042.011 — Cover Wall shuffle bag

## Context

With a small scope, the wall filled several rows by looping through the same once-shuffled order. The horizontal and vertical neighbor checks prevented touching duplicates but left long runs of covers repeating diagonally.

## Change

- Draw each distinct poster path once per pass through a seeded bag. Exclude matches directly above or to the left. If the remaining bag is blocked, borrow an eligible poster from the used part without resetting the pass. Matching neighbors are allowed only when no other artwork is available for that position.
- Favor paths whose nearest repeat is farther away, measuring in tile pitches across the last three columns and the current column. This is a soft weight: choosing only the farthest path can create a different regular pattern. A plain shuffle bag breaks the fixed order but leaves more nearby duplicates.
- Carry the bag, its random state, and recent placements in the scene cursor so each recycled column continues the same sequence. Decode only selected paths and remove unreadable paths from the bag. The scope, Rows slider, drift, and Poster Focus fallback below four readable poster entries are unchanged.

## Refs

- `ScreenSaverKit/Sources/ScreenSaverKit/CoverWall.swift` (`CoverWallShuffleBag`), `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverSceneLoader.swift` (`Cursor`, `loadWall`).
- `swift test --package-path ScreenSaverKit --filter 'repeatedWallArtwork|wallRowsFill|layoutFallback|sessionShuffle'`: four tests passed, including four- and eleven-poster walls with a shared path and a missing file, across 24 recycled columns.
- `make build-mac`: passed.
- Offscreen preview smoke: rendered all eleven covers from the reported screenshot and checked that the next column entered at the right without an edge match. The first probe read Core Animation's sublayer order rather than on-screen column positions; the position-based check passed.
