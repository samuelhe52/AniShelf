# 042.013 — Your Score detail

## Context

Samuel asked for the user-given star score to be an option in the screen saver. The saver already had **TMDb Score** (`Detail.score`, TMDb's community average); the user's own 1–5 star score was missing.

## Change

| Choice | Decision and rejected alternative |
| --- | --- |
| Name | New `Detail.userScore`, titled **Your Score**. The existing TMDb option keeps its name and raw value `score`, so stored selections stay valid. |
| Placement | Last item of the facts line, after Watch Status: `2023 · Adventure, Drama · TMDb 8.4 · Watched · ★ 4.5`. The two personal items sit together at the end, after the public facts. It is also the last toggle before Overview in the Details list. Rejected: a separate line or five-star glyphs; a single `★ 4.5` item fits the existing one-line facts and wraps as one unit. |
| Text | `★ 4.5` or `★ 5`, from `EntryScore.formatted` (current locale). Entries without a score show nothing. Both slide layouts draw it; Cover Wall's small-library fallback inherits Poster Focus. |
| Scoring off | With "scoring" turned off in the app, the builder leaves the score out and the toggle is hidden in the Details list. The publisher watches the preference, so flipping it republishes. |
| Defaults | Off in both layouts, as with the other opt-in details. |
| Versions | Originally `rendererVersion` 5. Under the [current version policy](014-single-snapshot-version.md), the build-ID check requests a reinstall before decoding settings. An older settings decoder does not ignore unknown detail values. |

## Refs

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift` (`Detail.userScore`, `Entry.userScore`), `ScreenSaverLayouts.swift` (`factsLine`)
- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSnapshotBuilder.swift`, `ScreenSaverPublisher.swift`, `ScreenSaverPreviewView.swift`, `MacScreenSaverSettingsPage.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift` (passes the scoring preference to the builder)
- Validation: `swift test --package-path ScreenSaverKit` (12 passed); `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests'` (passed); `make build-mac` (passed). Offscreen renders of Poster Focus (English and Japanese) and Backdrop checked by eye. Not run: the live saver in System Settings after reinstall.
