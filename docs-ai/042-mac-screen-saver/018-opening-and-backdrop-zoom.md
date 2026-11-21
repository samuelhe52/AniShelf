# 042.018 — Opening and Backdrop zoom

## Context

Inspired by [PR #28](https://github.com/samuelhe52/AniShelf/pull/28), the Swift renderer uses a black overlay for the opening. The wash is a separate view behind the artwork, so fading the scene itself would leave the wash visible.

## Change

- In published playback, a black layer covers the artwork and the wash for the first second, then fades out over 0.9 seconds. Decode runs during the hold; a slower decode extends black rather than revealing an unfinished scene. The first scene's configured duration starts after the fade. Setup and reinstall notices bypass the opening, and the in-memory settings preview remains immediate.
- Backdrop opens on the first readable slide in the shuffled order, using the entry's poster when its backdrop is unavailable.
- Every Backdrop photo scales from 1.0 to 1.045 over its full dwell after the opening fade or slide crossfade. The settings preview zooms too, without a black opening. The vignette, text, and logo stay fixed; poster fallbacks do not zoom.
- Opening state belongs to a playback activation, not to a viewport recomposition or snapshot generation. A resize during the opening preserves the fade deadline and initial selection; republishing does not restart the opening.

## Refs

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverRenderer.swift` — activation, curtain and timing.
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverLayouts.swift` — separate backdrop photo layer.
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverSceneLoader.swift` — readable-slide selection.

## Validation

- `make build-mac` and four focused ScreenSaverKit tests passed.
- Screen Saver Demo captures showed the black opening and fade, followed by artwork zoom under stationary titles on two successive Backdrop slides.
