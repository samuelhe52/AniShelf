# 042 — Mac screen saver: Idea backlog

Living document. Ideas deliberately left out of the first version of the Mac screen
saver ([000-plan.md](000-plan.md)), mostly from
[PR #28](https://github.com/samuelhe52/AniShelf/pull/28) (davidch81-tech) and the
2026-11-20 review. Each row keeps the idea, why it was deferred, and what doing it
right would take. Move a row to an amendment of this entry (or a new entry) when it is
picked up, and delete it here. The ideas were chosen from throwaway HTML sketches, which
are not kept as a spec: their motion and layout do not carry over to the Core Animation
implementation, so only the ideas are recorded here.

## Layouts

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| **Deck**: cards as a stack, one poster at a time, title underneath. Two sub-styles: **Fan** (the front card is dealt off, the rest fan behind it) and **Pile** (a tall pile seen head-on, each card peeking above the one in front, the whole pile leaning slightly and a little more with depth; the top card is tossed toward the viewer and the pile moves up; a soft colour wash from the top posters behind; title and library count in a corner) | PR #28; Pile from Samuel's reference image, 2026-11-21 | Picked for a later layout. Poster Focus covers the single-entry case, so this earns its place through the motion. The PR version had queue/caption desync and stale-callback bugs. | Drive the cards and the caption from one model; let the leaving card animate on its own so no step waits on another; tie every delayed step to the session token. Pile must stay orderly: one shared lean, not random twists per card. |
| **Flip Wall**: a still grid where single tiles flip over to show another poster, like Apple's Album Artwork saver (rows and flip delay as options) | Samuel, 2026-11-20 | Picked for a later layout. v1 Cover Wall drifts instead of flipping. | A separate layout, not a Cover Wall option. Reuse the Cover Wall rows setting. Flips should be rare and calm: a sketch that flipped every second or two felt frantic, so default to several seconds and keep it configurable. One timer tied to the session token; never flip the same tile twice in a row or show a poster already on screen. |
| **Cover Fusion**: full-height poster on one side, inner edge feathered into a heavy blur of itself, text in the rest | PR #28 (edge rebuilt in `d6293e96`: sharp to ~72% width, then a medium blur, gradient baked into pixels) | Picked, as a Poster Focus style rather than a layout. It overlaps Poster Focus and crops the art. Text width goes negative on portrait displays (1080×1920). | Size the poster from the shorter screen edge; stack on portrait. Make the blurred wash smooth, not a bright blob at the poster edge. The baked-gradient technique is worth reusing. |
| **Season Timeline**: a slow pan along a line of posters, alternating above and below, with the poster at the centre emphasised and named. The line can mean when it **aired**, when the user **started watching**, or when they **finished** | Brainstorm, 2026-11-21 | Picked for a later layout. The manifest carries season and year as text only; the other dates exist in the library but are not exported. | Export the dates the chosen mode needs. Leave out entries that lack that date (a planned entry has no start or finish) and say how many. Space posters evenly by order so a busy month does not pile up; labels carry the real date. Reserve room for the caption so posters never cover it; size posters from the available height. A small library needs the row repeated. |
| **Depth Drift**: posters float slowly upward at different depths, soft and large up close, small and slow far away, a few sharp at the focus plane; no text | Brainstorm, 2026-11-21 | Picked for a later layout. | The most ambient option. Live blur on many layers is costly, so prepare a few blur levels per poster ahead of time and choose by depth. Cap the layer count. |
| **Editorial Cover**: a magazine cover. The title set huge and ghosted in the poster's colour, the poster overlapping it at a slight angle, and the score, genres and status typeset beside it | Brainstorm, 2026-11-21 | Picked for a later layout. | Needs an accent colour per entry from the poster. Titles must be fitted for very long and CJK names. Do not let the poster hide the end of the title. Could use Hero Still's logo art in place of the ghost text. |

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
| Hero Still text alignment: left, centred, random | PR #28 | One designed alignment; random looks unstable. | A fixed choice per screen orientation if users ask. |
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
