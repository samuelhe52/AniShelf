# 044 — Screen saver layout unification: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-21 | Groundwork: text fitting split from drawing, interval clamped in the manifest settings, one slide loop | `2ba1fcd3` |
| 2026-11-21 | Plan written; Codex (`gpt-6.2-sol`, high effort) implemented it; Claude Code reviewed it, wrote these docs, and committed | this commit |

## Outcome and current state (as of 2026-11-21)

There are no draft layouts. `ScreenSaverManifest.Layout` lists all ten layouts, and AniShelf's Screen Saver settings, the installed saver, and the Screen Saver Demo play every one of them through the same scene loader.

- `ScreenSaverManifest.Settings` carries the former draft options: flip delay, drift rate, deck and pile depth, Timeline hold, date source, and date precision. `init` clamps them, and decoding requires every key.
- `Layout.controls` and `Detail.available(for:)` describe which controls and details each layout uses. AniShelf's settings page and the Demo sidebar both draw their controls from them. For Cover Wall below four posters, both show the Poster Focus fallback's controls.
- AniShelf stores detail selections per layout under `screenSaver<Layout>Details` keys, which keeps the existing Poster Focus and Backdrop keys. Cover Wall uses Poster Focus's selection.
- `ScreenSaverPlaybackOptions` (entry limit, seed, time scale) replaces `ScreenSaverDraft` for the Demo. The renderer takes optional settings that override the snapshot's.
- The draft sources moved out of `Drafts/`, changing only how they read their options.
- The live preview in AniShelf picks Timeline's sample from entries that have the selected date.

Key files:

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift`
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverSceneLoader.swift`
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverPlaybackOptions.swift`
- `ScreenSaverKit/Sources/ScreenSaverKit/Deck.swift`, `FlipWall.swift`, `Timeline.swift`, `DepthDrift.swift`, `CoverFusionAndEditorial.swift`
- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSettings.swift`
- `MyAnimeList/Sources/Mac/ScreenSaver/MacScreenSaverSettingsPage.swift`
- `ScreenSaverKit/Sources/ScreenSaverDemo/DemoViews.swift`

The design rules for the former drafts moved from the 042 backlog to [layout-notes.md](layout-notes.md).

## Deviations from plan

- **Timeline also omits Overview.** Its stage never reads the overview, so the plan's table ("all but year") was wrong. The control table offers neither Year nor Overview for Timeline.
- **Backdrop's fallback.** Backdrop shows no flowing-background control, but an entry with a missing or unreadable backdrop falls back to a Poster Focus slide drawn over the wash, as before. Its controls follow its primary layout.
- **Demo capture** gained `--snapshot <folder>`, and frame names use the layout's raw value.
- **File name.** The Cover Fusion and Editorial Cover drawing code (formerly `Drafts/DraftSlides.swift`) is now `CoverFusionAndEditorial.swift`.

## Validation

- Claude Code: `swift test --package-path ScreenSaverKit`, 17 tests passed. `make build-mac` succeeded. Reviewed the diff, including the moved layout sources, which change only how options are read, plus formatting in `DepthDrift.swift`.
- Codex, as reported: `make test-app-mac APP_TEST_ONLY=MyAnimeListTests/ScreenSaverPublisherTests`, 12 tests passed. Demo captures of two frames per layout, compared by eye with captures from before the change, showed no drawing changes apart from animation phase. It also checked the three-poster Cover Wall fallback and Timeline watch dates.
- Not done: the visual pass of AniShelf's settings page, which Samuel does.

## Open questions

- The hosted macOS app tests republished the live screen saver snapshot (from 17 to 137 entries, with the same display settings), because the test host runs AniShelf's publisher. Running app tests should not overwrite the user's snapshot.
- An installed saver from before this change has a different build ID and asks to be reinstalled.
