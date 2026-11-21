# 044 — Screen saver layout unification: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-21 |
| Origin | Samuel, 2026-11-21, after a survey of the screen saver code found that demo-only draft layouts change the saver's build ID |
| Related | [042-mac-screen-saver](../042-mac-screen-saver/000-plan.md), [042.014 single snapshot version](../042-mac-screen-saver/014-single-snapshot-version.md), [042.016 Timeline date options](../042-mac-screen-saver/016-timeline-date-options.md) |

## Background

ScreenSaverKit has two kinds of layout. Shipped layouts (`ScreenSaverManifest.Layout`: Cover Wall, Poster Focus, Backdrop) are chosen in AniShelf's settings and written to the snapshot. Draft layouts (`ScreenSaverDraftLayout`: Deck · Fan, Deck · Pile, Flip Wall, Cover Fusion, Timeline, Depth Drift, Editorial Cover) play only in the Screen Saver Demo, through `ScreenSaverDraft` overrides.

The drafts live in `ScreenSaverKit/Sources/ScreenSaverKit/Drafts/`, inside the folder the saver's build ID hashes (the build phase in `MyAnimeList.xcodeproj/project.pbxproj`). Every tweak to a draft therefore changes the build ID and makes an installed saver ask to be reinstalled, although the saver can never play a draft. The scene loader and renderer also carry draft-only branches.

The Demo's controls do not match what each layout reads. For example, it offers Overview for the Deck layouts, which drop it, and for Backdrop, which ignores it. It decides per layout by hand instead of from `ScreenSaverManifest.Detail.available(for:)`.

## Goals

- Remove the draft mechanism. Every draft becomes a shipped layout that AniShelf's Screen Saver settings offer and the installed saver plays.
- One rule for controls, in AniShelf's settings and in the Demo: a control appears only when the selected layout reads that field. A detail toggle appears only when the layout draws that detail.
- Keep every layout's drawing and motion unchanged.

### Non-goals

- Redesigning any layout, or merging layouts (Cover Fusion stays its own layout rather than a Poster Focus style).
- Changing the snapshot schema version: the build ID already refuses snapshots from other builds ([042.014](../042-mac-screen-saver/014-single-snapshot-version.md)).
- Keeping the Demo's ability to try unsettled layouts. A future experiment can live on a branch.

## Design / approach

### Layouts and settings

- `ScreenSaverManifest.Layout` gains `deckFan`, `deckPile`, `flipWall`, `coverFusion`, `timeline`, `depthDrift`, and `editorialCover`. `ScreenSaverDraftLayout` goes away.
- `ScreenSaverManifest.Settings` gains the options the drafts read from `ScreenSaverDraft` today, with their current defaults and ranges: flip delay (3 s, 1–120), drift rate (4 per 10 s, 1–30), deck depth (5, 2–12), pile depth (7, 2–12), Timeline hold (7 s, 2–120), Timeline date source (air date), and Timeline date precision (full date). Like the existing fields, `init` clamps them and decoding requires every key.
- Directors read these from the settings instead of the draft. `ScreenSaverDraftContext` becomes a plain stage context.
- The draft files move out of `Drafts/` into the regular sources. The scene loader routes every layout through one path; `prepareDraft` and the draft branches go away.

### What each layout reads

From the current code; the implementer must verify each row while wiring it:

| Layout | Details drawn | Interval | Rows | Flowing background | Own options |
| --- | --- | --- | --- | --- | --- |
| Cover Wall | none (falls back to Poster Focus below 4 entries) | no | yes | no | — |
| Poster Focus | all | yes | no | yes | — |
| Backdrop | all but overview | yes | no | no | — |
| Deck · Fan | all but overview | yes | no | yes | deck depth |
| Deck · Pile | all but overview | yes | no | yes | pile depth |
| Flip Wall | none | no | yes | no | flip delay |
| Cover Fusion | all | yes | no | yes | — |
| Timeline | all but year | no (uses hold) | no | yes | hold, date source, precision |
| Depth Drift | none | no | no | yes | drift rate |
| Editorial Cover | all | yes | no | yes | — |

`Detail.available(for:)` and `Detail.defaults(for:)` cover every layout, and both AniShelf and the Demo build their controls from one description of this table in ScreenSaverKit, not from separate hand-written lists.

### AniShelf

- `ScreenSaverSettings` stores detail selections per layout. Cover Wall keeps sharing Poster Focus's selection for its fallback. Existing stored selections for Poster Focus and Backdrop keep working.
- The new options are persisted in `UserDefaults` alongside the existing ones and written to the manifest.
- `MacScreenSaverSettingsPage` offers every layout and shows only the controls the table allows.
- New user-facing strings get `ja` and `zh-Hans` translations in `MyAnimeList/Resources/Localizable.xcstrings`.

### Demo

- The Demo plays shipped settings directly. `ScreenSaverDraft` shrinks to playback-only options (entry limit, seed, time scale); proposed name `ScreenSaverPlaybackOptions`.
- Its sidebar follows the same rule as AniShelf.
- `--capture` keeps working for every layout.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Ship every draft | Samuel's decision. The alternative, a separate draft target linked only by the Demo, keeps drafts out of the saver but needs package access across targets and a draft hook in the scene loader and renderer. |
| Per-layout detail selections | Each layout draws a different subset, so one shared list would turn details on and off unexpectedly when switching layouts. The existing Poster Focus and Backdrop keys stay valid. |
| One table in ScreenSaverKit drives both UIs | The Demo's hand-written checks drifted from what layouts read; a single source keeps the two in step. |
| No schema version bump | New fields are refused by build ID before decoding, as in 042.014. |

## Validation and acceptance criteria

- `swift test --package-path ScreenSaverKit` passes, including manifest round trips with the new settings.
- `make build-mac` succeeds, and focused `ScreenSaverPublisherTests` pass with `make test-app-mac`.
- `ScreenSaverDemo --capture` produces frames for every layout without changes to drawing; spot-check against frames from before the change.
- For each layout, the settings page and the Demo show exactly the controls in the table. Samuel does the visual pass of the settings page.
- Older stored Poster Focus and Backdrop detail selections survive.

## Amendments

None yet.
