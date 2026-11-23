# 042.020 — Tagline detail

Status: implemented; maintainer accepted the final design and defaults.

## Context

The [idea backlog](backlog.md) originally deferred the tagline from
[PR #28](https://github.com/samuelhe52/AniShelf/pull/28) because
"`AnimeEntryDetail.subtitle` holds one language only". That reason no longer holds.
`AnimeEntryDetail` records the `language` it was fetched in, and the entry detail screen
uses a stored detail only on a language match (`EntryDetailViewModel`). For movies and
series, `subtitle` is TMDb's `tagline` in the requested language. TMDb leaves it empty
rather than falling back to another language, so a language-matched tagline is always in
the Anime Info Language. No schema change is needed.

The 2026-11-22 assessment also found that the snapshot builder reads
`entry.detail?.overview` without that check. After an Anime Info Language change, the
saver can show an overview in the previous language until the detail is fetched again.

Samuel decided: seasons use their parent series' tagline. The tagline is an optional
detail with its own toggle. An entry without a tagline renders exactly as it does today.

## Change

### Data: `ScreenSaverSnapshotBuilder`

| Entry type | Tagline source |
| --- | --- |
| Movie, TV series | `entry.detail?.subtitle` |
| Season | `entry.parentSeriesEntry?.detail?.subtitle`. Never the season's own `detail.subtitle`, which holds the season name (`InfoFetcher+Season.swift`) |

- Use a detail only when `detail.language == language.rawValue`. Otherwise there is no tagline.
- Trim whitespace. An empty result is `nil`.
- Apply the same language check to the overview: use `entry.detail?.overview` only on a
  language match, and otherwise fall back to `entry.displayOverview` as today.
- The builder always includes the tagline, like every other text detail, so toggling it
  needs no new artwork.

### Manifest: `ScreenSaverManifest`

- Add `Detail.tagline`, placed just before `.overview` in the enum. `normalized` keeps
  selections in declaration order.
- Add `tagline: String?` to `ScreenSaverManifest.Entry` and to
  `ScreenSaverSnapshotDraft.Entry.manifestEntry`.
- No `schemaVersion` bump: the screen saver has not shipped, and the build ID asks for a
  reinstall ([014](014-single-snapshot-version.md)). [013](013-user-score-detail.md) added
  `userScore` the same way.

### Availability and defaults

| Layout | Offered | Default | Placement |
| --- | --- | --- | --- |
| Backdrop | Yes | On | Under the logo or title, above the facts line |
| Editorial Cover | Yes | On | A subheadline under the headline, above the overview excerpt and the metadata column |
| Poster Focus, Cover Fusion (and Cover Wall's small-library Poster Focus fallback) | Yes | On | Between the title block and the facts line |
| Deck · Fan, Deck · Pile | Yes | On | Below the title block in the existing caption ([021](021-tagline-caption-layouts.md)) |
| Timeline | Yes | Off | Below the title and above the date and facts |
| Cover Wall, Flip Wall, Depth Drift | No | — | These show no text |

Stored selections (`ScreenSaverSettings`, one `screenSaver…Details` key per layout) are
not migrated. New defaults apply only to layouts without a saved selection.

### Rendering

General rules for every layout that offers the tagline:

- **Clean fallback.** With the tagline off, or with no tagline, the layout produces exactly
  today's frames: no reserved space, no extra gap.
- **Typography.** Smaller than the title, at regular or medium weight and
  [65% opacity in every layout](021-tagline-caption-layouts.md). Cap it at two
  lines and end longer text with an ellipsis. There is no line-limit setting.
- **Priority.** The title keeps first claim on space. The tagline takes space before the
  overview, and the overview shrinks first when space runs out.

Per layout:

- **Poster Focus / Cover Fusion** (`posterFocusLines` in `ScreenSaverLayouts.swift`): a new
  `Line` between the title and the facts. The overview cap from
  [044.002](../044-screen-saver-layout-unification/002-poster-line-limits.md) is unchanged.
- **Backdrop** (`backdrop` in `ScreenSaverLayouts.swift`): the tagline goes between the
  logo or title and the facts, at the same text width. The corner shade extends
  with the taller block. The [subject-aware side rule](019-backdrop-subject-aware-side.md)
  includes the tagline in the measured text frame and mirrors it with the rest of the block.
- **Editorial Cover** (`editorialCover` and `editorialHeadline` in
  `CoverFusionAndEditorial.swift`): the subheadline sits under the last headline line at
  the column width, tinted like the metadata column rather than the headline accent. Count
  its height in the headline and overview reservation, so the poster fitting and tilt
  clearance from [044's layout notes](../044-screen-saver-layout-unification/layout-notes.md)
  still apply.

### Settings, Demo, localization

- `MacScreenSaverSettingsPage.swift`: the detail label `"Tagline"`.
- `MyAnimeList/Resources/Localizable.xcstrings`: `ja` キャッチコピー, `zh-Hans` 宣传语.
  Add the key by hand: CLI builds do not extract strings.
- Screen Saver Demo (`ScreenSaverKit/Sources/ScreenSaverDemo/DemoModel.swift`):
  the toggle follows the app’s per-layout tagline defaults. Demo snapshots
  without taglines exercise the fallback.

The tagline is no longer in the idea backlog. Placement and priority are
recorded in [044's layout notes](../044-screen-saver-layout-unification/layout-notes.md).

## Tests

Extended the existing suites:

- `ScreenSaverPublisherTests.seasonUsesParentTitleSelectedPosterAndInfoLanguage`: a season
  gets its parent's tagline, not the season name. A parent detail in another language gives
  no tagline. A detail in another language also leaves the overview at `displayOverview`.
- `ScreenSaverKitTests.manifestRoundTrip`: include a tagline.
- Layout output is checked by rendering, not by unit tests.

## Validation

- `swift test --package-path ScreenSaverKit`: 21 passed.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests'`:
  14 passed. The first run caught a stale Timeline assertion that omitted the
  existing Your Score default; the regression now checks that unsupported
  details are rejected.
- `make build-mac`: passed.
- Reviewed 48 offscreen **layout stress tests** in English and Japanese at
  1920 × 1080 and 1080 × 1920. The short and long taglines were synthetic
  strings placed over real artwork, not the actual taglines of the films
  shown. Long strings end after two lines with an ellipsis. 64 comparisons
  against the pre-change renderer were pixel-identical with no tagline or
  with the toggle off.
- Cross-checked both films' Japanese taglines in the local library and
  published manifest. In particular, 超かぐや姫！ publishes
  `まだ誰も見たことがない「かぐや姫」の物語。`, matching the detail screen.
  [Corrected Demo captures](../../.build/tagline-real-shots/) show the real
  taglines in all four layouts, landscape and portrait. Backdrop used archived
  artwork for the same films because the current manifest lacked their
  backdrop paths. Only temporary copies were modified for capture.
- The pre-change snapshot reader returned `requiresUpdate` for a newer
  snapshot selecting `.tagline`. The reader checks the build ID before the
  strict details decoder; [013](013-user-score-detail.md) previously misstated
  that unknown details were ignored.
  The [installed stale saver](../../.build/tagline-shots/reinstall.png) also
  drew the reinstall notice in an offscreen preview host against the existing
  newer snapshot. The system saver and published snapshot were left unchanged.
- A read-only local-library check found five hidden parent series linked from
  visible seasons. All five had stored detail; four had nonblank taglines
  before language matching. This confirms that hidden parents can supply
  taglines, not that refresh always populates them.
