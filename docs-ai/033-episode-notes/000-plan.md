# 033 — Episode notes with scope chips: Plan

| Field | Value |
| --- | --- |
| Status | Implemented — production sync and full native macOS interaction coverage unverified |
| Anchor date | 2026-10-26 |
| Origin | Maintainer selected design A from the interactive notes prototypes and requested direct implementation with incremental commits. |
| Related | [Selective sync](../001-selective-library-sync/000-plan.md), [Rewatch tracking](../012-rewatch-tracking/000-plan.md) |

## Background
The existing Notes section edits one overall note. Episode annotations must coexist with it without adding another navigation hierarchy or an expanding list in the Mac inspector.

## Goals
- Keep the existing inline editor and its approximate height; use one row of scrolling Overall and populated episode chips with a suggested episode and Other fixed on the trailing side.
- Open on All when nonempty episode notes exist, otherwise on Overall. Show later episodes first in the inline overview and strip. Overview sections select an editor; provide an expanded reading sheet.
- Offer episode-row note access without requiring watched status or progress tracking.
- Share episode notes between series and season entries, retain specials and metadata-orphaned notes, and preserve them through conversions.
- Sync independently per episode, retain clocked empty deletion markers, and include notes in exports and user-info snapshots.

### Non-goals
Per-viewing journals, arbitrary tags, recent-note feeds, cross-library episode-note search, and website edits.

## Design / approach
- Overall notes remain the existing `AnimeEntry.notes` string on each entry.
- A new immutable shipped schema version will add an optional encoded episode-note payload to the series entry. A shared plain Codable note value carries season, episode, text, and a per-note sync clock; no fetched metadata is persisted in it. Proposed source: `DataProvider/Sources/DataProvider/Models/Other/EpisodeNote.swift`.
- Only series rows store episode notes. A season reads and writes its parent's notes filtered to its season. A season whose parent relationship is missing offers only the overall note until metadata refresh restores the parent; opening its detail runs a silent single-entry refresh once per launch to do so. There is no season-local fallback storage and no user prompt about the hidden parent. Conversion and duplicate repair must preserve the series payload.
- Empty text is a deletion marker. Inline editing retains a selected empty draft and offers scoped revert; existing detail Discard must restore episode notes as well as overall notes. Reverts advance note clocks.
- Extend `LibraryEntrySyncSnapshot` and `CloudLibrarySyncClient` with normalized note values, independent merge, and newest-clock accounting. New records use a new sync version so older builds cannot overwrite unknown state.
- Proposed shared UI: `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`. Use native pickers and semantic colors. The episode number remains visible while editing. On iOS, editing started from an episode row uses its own sheet, never one stacked on the episode preview popover. Native macOS layout is deferred to a later pass.
- Keep scope selection local to the view; open on All only when the entry supports episode notes and has at least one nonempty episode note, otherwise on Overall. Apply the same default when entry identity changes or the selected episode note is deleted. If the last nonempty episode note disappears while viewing All, switch to Overall; retain a selected empty episode draft while typing. All has no chip and shows with no chip selected; tapping the selected scope chip or the editor's All button returns to it. The compact-strip follow-up supersedes the earlier per-entry device memory. Use descending season/episode order and compact `E13` / `S2E13` strip labels across languages. Keep the suggestion and Other outside the scroller, with a 16-point trailing gradient fade. On macOS only, disable vibrant rendering on the `.fill.tertiary` capsule background to avoid black fills under the mask; iOS keeps default vibrancy. See [003-compact-strip-and-macos-fade.md](003-compact-strip-and-macos-fade.md) and the [default-scope correction](004-overall-default-without-episode-notes.md).
- Moving a note to another episode has no permanent control. Offer "Move to Episode…" beside "Delete Note" in the context menu of episode chips and of note sections in All and Expand, reusing the episode picker. When episode metadata has loaded and a note's episode is absent from it, the editor label shows a quiet "Not in episode list · Move…" hint; never show it before metadata loads. A move writes the new anchor and leaves a deletion marker on the old one. If the target already has a note, ask before combining; never overwrite silently.
- On iOS, horizontal swipes in the inline content step through All (no selected chip), Overall, and the displayed episode chips: left advances, right goes back, and neither wraps. All swipes must exclude row-tap selection while preserving vertical scrolling. Creation controls remain separate. See [005-swipe-scope-navigation.md](005-swipe-scope-navigation.md) for the implementation, reported skipping, correction, and runtime-validation limit.
- On iOS and macOS, episode and Global/Overall editors offer a small All button in their bottom-right footer when episode-note support makes All available, matching the overview's Expand placement and returning directly to the All scope. See [006-return-to-all.md](006-return-to-all.md).
- Copy/paste of user info: copying carries episode notes in both the app payload and the plain-text representation, so they survive pasting into other apps. Pasting into an entry never changes its episode notes (notes are already shared within a show, and another show's numbering does not apply), and the paste-overwrite confirmation ignores the target's episode notes.
- Export structured episode notes in JSON, an additional serialized column in tabular formats, and labeled sections in plain text.

## Alternatives & decisions
| Choice | Reason and alternative |
| --- | --- |
| Scope chips | Maintainer chose prototype A; strips and a notebook sheet change the primary editing layout more. |
| One evolving note per episode | Follows supplied discussion; per-viewing history would introduce a different interaction model. |
| Series ownership | A season and its series should show the same annotation. Overall notes remain entry-specific. |
| Typed number anchor | Works offline, supports specials, and survives missing TMDb metadata. |
| Encoded optional payload | Additive SwiftData migration and independent value-level sync without another relationship graph. |

## Validation and acceptance criteria
- Focused tests cover per-episode merge, deletion, series/season ownership, user snapshot restore, persistence migration, conversion, and export.
- Build native macOS with `make build-mac`; use the already booted iPhone simulator for app tests and `make run-sim` runtime inspection.
- Check chips, direct editing, Other picker, All navigation, expanded reading, episode entry points, and narrow layouts. Record actual validation separately from implementation claims.

## Amendments
- 2026-10-26 — Review against the originating design discussion before the UI rework. Corrected in place: removed season-local fallback storage for a missing parent; replaced session-scoped chip selection with per-entry AppStorage memory; added the note-move, iOS sheet, and copy/paste rules; deferred native macOS layout; status returned to In progress. The data-layer fixes (fallback removal, paste preservation, plain-text copy and export) were folded into the data commit.
- 2026-10-26 — Post-implementation review. A parentless season offered episode-note entry points whose save silently failed; they are now gated on note ownership. Rather than waiting for Refresh All, opening such a season's detail runs one silent single-entry metadata refresh through the existing refresher, which restores the parent. When the owner appears while the detail is open, its Discard baseline adopts the restored episode notes so Discard cannot delete them.
- Updated 2026-10-26: Unified the note and Batch Add editors on one UIKit-backed `PlaceholderTextEditor` — see [002-unified-placeholder-editor.md](002-unified-placeholder-editor.md)
- Updated 2026-10-26: Replaced persisted scope selection and ascending inline ordering with All-on-open, a compact single-row strip, fixed creation controls, and a macOS-only fade/vibrancy workaround; corrected the corresponding plan and action text — see [003-compact-strip-and-macos-fade.md](003-compact-strip-and-macos-fade.md)
- Updated 2026-10-27: Default to Overall when no nonempty episode notes remain; corrected the plan, action, and compact-strip descriptions — see [004-overall-default-without-episode-notes.md](004-overall-default-without-episode-notes.md)
- Updated 2026-10-27: Add iOS swipe navigation and record the All overview gesture-conflict correction, with build-only validation of that correction — see [005-swipe-scope-navigation.md](005-swipe-scope-navigation.md)
- Updated 2026-10-27: Add a bottom-right All return button to inline episode and Global/Overall editors on both platforms — see [006-return-to-all.md](006-return-to-all.md)
- Updated 2026-10-27: Remove the All chip, show the overview with no selected chip, and let selected-chip taps return to All — see [007-unselected-overview.md](007-unselected-overview.md)
