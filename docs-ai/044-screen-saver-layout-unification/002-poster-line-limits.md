# 044.002 — Poster line limits

## Context

The unified Poster mode needs configurable text caps for both Focus and Fusion.

## Change

Only the overview has a configurable cap: 3–8 lines or no limit, defaulting to 4. The Cover Wall fallback uses the same setting. The cap is saved locally and passed in the screen saver snapshot; the Demo offers the same control. Title and facts retain their fixed caps, and other layouts keep their own typography. This corrects the initial implementation, which exposed title and facts caps too.

## Refs

- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSettings.swift`
- `MyAnimeList/Sources/Mac/ScreenSaver/MacScreenSaverSettingsPage.swift`
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift`
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverLayouts.swift`
