# 042.012 — Reshuffle slideshow passes

## Context

Poster Focus and Backdrop played a shuffled order once and then looped it unchanged. Cover Wall's spatial weighting does not apply to a single visible slide, but the fixed slideshow order can still become predictable in a small scope.

## Change

- Preserve the seeded initial order in the installed saver and the current entry when the in-memory preview restarts. At the end of a pass, reshuffle the same entries without replacement.
- If the previous pass's last entry comes up before another readable entry, defer it within the new pass. This avoids a duplicate at the seam even if some artwork is unreadable. With one playable entry it can repeat; with two they alternate.
- Apply the same ordering to Cover Wall only when it falls back to Poster Focus. The wall's distance-weighted draws and the per-entry Backdrop fallback are unchanged.

## Refs

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverSceneLoader.swift` (`ScreenSaverSlideOrder`), `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverRenderer.swift` (preview starting index).
- `swift test --package-path ScreenSaverKit --filter 'slideshowReshuffles|layoutFallback|repeatedWallArtwork|sessionShuffle|inMemoryPreview'`: five tests passed.
- Offscreen renderer smoke: observed three full passes of four entries in each slideshow layout, with a changed order and no repeated entry at a pass boundary.
- `make build-mac`: passed.
