# 042.006 — True-scale preview, Cover Wall rows, and slide details

## Context

Samuel's review of the pane on 2026-11-20, comparing it with Apple's own thumbnail of
the saver in System Settings and with Apple's Album Artwork saver options:

- The Settings preview showed 2 rows of large posters while the real saver (and
  Apple's thumbnail) showed 4. Cause: `CoverWallGrid` derived its row count from the
  viewport it was drawn into, so the ~205 pt preview got `max(2, round(205 / 260))`.
- Cover Wall needs a row control, like Album Artwork's Rows slider.
- Poster Focus showed only a title floating in the middle of the right half, on a flat
  average-colour wash; it "doesn't look carefully designed".
- Hero Still showed too much by default (year, three genres including "Animation",
  status, logo or title, season).
- What text a slide shows must be configurable.

## Change

| Choice | Decision and rejected alternative |
| --- | --- |
| Preview scale | The preview lays the scene out at the main screen's point size and scales it down (`ScreenSaverRenderer.resize(to:scale:layoutSize:)`), so rows, tile size, and text sizes match the saver for every layout. Rejected: tuning the preview's own row formula (would drift from the saver). |
| Rows | A Cover Wall-only slider, 2–8 with tick marks, default 4 (what `round(height / 260)` gave on Samuel's 982 pt display). It replaces the automatic row count; tile size follows from screen height and rows, columns still fill the width. Look-only: no image re-export. |
| Details | Each entry carries `title`, `season`, `year`, `genres`, `status` as separate fields (replacing `subtitle` and the pre-joined `meta` line). A **Details** section in the pane has one toggle per detail; Poster Focus and Hero Still keep separate selections. Text is always exported, so a toggle applies instantly. Defaults: Poster Focus title, season, year, genres; Hero Still title and year. Show Titles is gone. Rejected for now: reorder or relayout controls; each layout has one designed order. |
| Cover Wall fallback | With fewer than 4 posters Cover Wall falls back to Poster Focus and uses the Poster Focus selection. |
| Animation genre | TMDb genre 16 is dropped from the snapshot: nearly every entry has it (the backlog's "hide the Animation genre" row, now done). |
| Poster Focus design | Background is the poster itself, downscaled, Gaussian-blurred, slightly saturated, and darkened. The poster (72% of screen height, rounded corners, soft shadow) and its text block form one group centred on screen; with no details on, the poster is centred alone. Text hierarchy: year and status as a small tracked heading, then a bold title (up to 3 lines), the season, and genres. Portrait screens stack poster above centred text. |
| Hero Still design | The still is left untouched unless some text is on; then only the lower-left is shaded. Logo (or a bold title when there is no logo) sits above one meta line of the enabled details (season, year, first two genres, status). Text and logo get a soft shadow. |
| Layout name | Hero Still is shown as **Backdrop** (ja 背景画像, zh-Hans 背景图): it is TMDb's term for the image on screen. The old ja name キービジュアル meant the main promotional art, which is the poster, so it read like Poster Focus; the zh-Hans 主视觉静帧 was a literal translation. The internal name follows: layout raw value `backdrop`, `ScreenSaverSettings.backdropDetails` (key `screenSaverBackdropDetails`). No compatibility path: the feature has not shipped. |
| Versions | `rendererVersion` 3; saver build number 3. An older installed saver shows its update message. |

Implementation split: Codex (thread `screensaver-revision`) built the true-scale
preview and the rows setting; Samuel then asked Claude to take over, and Claude removed
Codex's review-only debug hooks and built the details model, the Details section, and
both layout redesigns. The Flip Wall idea (Album Artwork-style flipping tiles) went to
[backlog.md](backlog.md).

## Refs

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift` (`Detail`, `Settings.details`, `coverWallRows`)
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverLayouts.swift`, `ScreenSaverSceneLoader.swift` (blurred background), `ScreenSaverRenderer.swift`, `CoverWall.swift`
- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSettings.swift`, `ScreenSaverSnapshotBuilder.swift`, `ScreenSaverPublisher.swift`, `ScreenSaverPreviewView.swift`, `MacScreenSaverSettingsPage.swift`
- Validation: `swift test --package-path ScreenSaverKit` (10 passed); `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'` (succeeded); `make build-mac` and `make build` (passed). Codex's in-process comparison before the redesign: 4-row miniature and full-size render matched tile for tile (40/40 images, frame error < 1e-13 pt). Visual pass of the redesigned layouts is Samuel's.
