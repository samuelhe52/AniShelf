# 042 — Mac screen saver: Idea backlog

Living document. Ideas deliberately left out of the first version of the Mac screen
saver ([000-plan.md](000-plan.md)), mostly from
[PR #28](https://github.com/samuelhe52/AniShelf/pull/28) (davidch81-tech) and the
2026-11-20 review. Each row keeps the idea, why it was deferred, and what doing it
right would take. Move a row to an amendment of this entry (or a new entry) when it is
picked up, and delete it here.

## Layouts

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| **Deck**: a fanned stack, one poster at a time, title underneath | PR #28 | The fan hides most of each poster; Poster Focus covers the single-entry case. The PR version also had queue/caption desync and stale-callback bugs. | First candidate for a fourth layout. Drive the card queue and caption from one model; tie every delayed step to the session token. |
| **Flip Wall**: a still grid where single tiles flip over to show another poster, like Apple's Album Artwork saver (rows and flip delay as options) | Samuel, 2026-11-20 | v1 Cover Wall drifts instead of flipping; Samuel expects to add a similar design later. | A separate layout, not a Cover Wall option. Reuse the Cover Wall rows setting; drive flips from one timer tied to the session token; never flip the same tile twice in a row or show a poster already on screen. |
| **Cover Fusion**: full-height poster on one side, inner edge feathered into a heavy blur of itself, text in the rest | PR #28 (edge rebuilt in `d6293e96`: sharp to ~72% width, then a medium blur, gradient baked into pixels) | Overlaps Poster Focus and crops the art. Text width goes negative on portrait displays (1080×1920). | Could become a Poster Focus style option. Size the poster from the shorter screen edge; stack on portrait. The baked-gradient technique is worth reusing. |

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
| TMDb vote average on Hero Still | PR #28 | Keeps v1 metadata to year, genres, status. | Add to the meta line; one decimal. |
| Watch status (watching / watched / planned / dropped) on Hero Still | PR #28 `d6293e96` (opt-in toggle) | A screen saver is visible to others; personal tracking stays off it. | Opt-in, off by default, in the AniShelf pane. |
| Synopsis on Hero Still, shrunk to fit (down to 72% size) | PR #28 `c6c267f1` | Long text at small size is not readable from a distance. | If added, cap at 2–3 lines at a fixed size, never shrink. |
| A saver-specific language menu | PR #28 | Duplicates and can contradict Anime Info Language. | Only if users want the saver in a different language from the app. |

## Content and scope

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| Category scope (show one library category) | Codex review | Favorites / Watched / All cover v1. | Add `category(id)` scope; a deleted category gives an empty scope. |
| Episode stills | PR #28 (exported but unused) | No layout uses them. | Only with a layout designed for stills. |

## Distribution and setup

| Idea | Source | Why deferred | To do it right |
| --- | --- | --- | --- |
| Separate notarized download of the saver | Both reviews | v1 embeds the saver in the App Store app. | The fallback if App Review rejects the embedded saver: Developer ID signing, notarization, a download link on the site. |
| Photo-folder mode for Apple's built-in photo screen saver | Codex review | The snapshot folder already holds plain images; no extra work needed now. | Document it in the pane or the guide if the custom saver is unavailable. |
| A saver Options sheet | PR #28 | Options live in AniShelf; Options sheets are unreliable on recent macOS. | A sheet that only points to AniShelf Settings. |
