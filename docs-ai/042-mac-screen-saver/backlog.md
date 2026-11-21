# 042 — Mac screen saver: Idea backlog

Living document. Ideas deliberately left out of the first version of the Mac screen
saver ([000-plan.md](000-plan.md)), mostly from
[PR #28](https://github.com/samuelhe52/AniShelf/pull/28) (davidch81-tech) and the
2026-11-20 review. Each row keeps the idea, why it was deferred, and what doing it
right would take. Move a row to an amendment of this entry (or a new entry) when it is
picked up, and delete it here. The ideas were chosen from throwaway HTML sketches, which
are not kept as a spec: their motion and layout do not carry over to the Core Animation
implementation, so only the ideas are recorded here.

The layout ideas that were built (Deck, Flip Wall, Cover Fusion, Timeline, Depth Drift, and
Editorial Cover) ship since [044](../044-screen-saver-layout-unification/000-plan.md); their
design rules moved to [044's layout notes](../044-screen-saver-layout-unification/layout-notes.md).

## Considered and set aside

Sketched in the 2026-11-21 brainstorm and not picked. Kept so they are not re-proposed from scratch.

| Idea | Why set aside |
| --- | --- |
| **Spine Shelf**: the library as book spines on a shelf; one slides out and shows its poster | Needs an accent colour per entry and tiny vertical text. Charming but not chosen. |
| **Coverflow**: one poster facing the viewer, the rest fanned away in perspective | Familiar but dated. |
| **Scatter Table**: posters tossed onto a dark table, a tag on the newest | Feels like a physical collection rather than a display. Not chosen. |

## Motion and presentation options

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| Slide transition as an alternative to cross-fade | PR #28 | One more setting every layout must support. | A per-layout transition enum in the manifest settings. |
| Drift styles: horizontal, diagonal, "breathing", static | PR #28 | Diagonal drift cuts rows at the top and bottom. | Keep full rows: diagonal only with vertical wrap; "breathing" as a slow scale on Poster Focus. |
| Backdrop text alignment as a setting: left, centred, random | PR #28 | Random flips the text every slide and looks unstable; a centred logo lands on the subject. The side now follows the subject instead ([019](019-backdrop-subject-aware-side.md)). | Centred needs only a conditional side gradient and centred x positions; add it only if users ask. |
| Different content per display on multi-monitor setups | Review | v1 renders each display independently from the same snapshot. | Offset the shuffle seed per screen. |

## Metadata

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| Country | PR #28 | The PR derived it from original language (English → United States). The app stores no country today. | Store TMDb `origin_country` / `production_countries` (schema change), then localize with `Locale`. |
| Tagline | PR #28 | `AnimeEntryDetail.subtitle` holds one language only, the one fetched. | Tag the stored tagline with its language, or fetch per language; show only on a language match. |
| A saver-specific language menu | PR #28 | Duplicates and can contradict Anime Info Language. | Only if users want the saver in a different language from the app. |

## Content and scope

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| Episode stills | PR #28 (exported but unused) | No layout uses them. | Only with a layout designed for stills. |

## Distribution and setup

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| Separate notarized download of the saver | Both reviews | v1 embeds the saver in the App Store app. | The fallback if App Review rejects the embedded saver: Developer ID signing, notarization, a download link on the site. |
| Photo-folder mode for Apple's built-in photo screen saver | Codex review | The snapshot folder already holds plain images; no extra work needed now. | Document it in the pane or the guide if the custom saver is unavailable. |
| A saver Options sheet | PR #28 | Options live in AniShelf; Options sheets are unreliable on recent macOS. | A sheet that only points to AniShelf Settings. |
