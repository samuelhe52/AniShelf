# 033 — Episode notes with scope chips: Plan

| Field | Value |
| --- | --- |
| Status | Implemented — production sync and native macOS interaction unverified |
| Anchor date | 2026-10-26 |
| Origin | Maintainer selected design A from the interactive notes prototypes and requested direct implementation with incremental commits. |
| Related | [Selective sync](../001-selective-library-sync/000-plan.md), [Rewatch tracking](../012-rewatch-tracking/000-plan.md) |

## Background
The existing Notes section edits one overall note. Episode annotations must coexist with it without adding another navigation hierarchy or an expanding list in the Mac inspector.

## Goals
- Keep the existing inline editor and its approximate height; add horizontally scrolling scope chips for Overall, populated episodes, All, a suggested episode, and Other.
- Make All a chronological reading overview whose sections select an editor; provide an expanded reading sheet.
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
- Remember the last selected chip per entry on the device (AppStorage-backed dictionary keyed by entry identity, storing only non-Overall choices, size-capped). SceneStorage is rejected: it is lost when the scene is discarded and is per window, while this is a per-entry preference. Fall back to Overall when the remembered note no longer exists.
- Moving a note to another episode has no permanent control. Offer "Move to Episode…" beside "Delete Note" in the context menu of episode chips and of note sections in All and Expand, reusing the episode picker. When episode metadata has loaded and a note's episode is absent from it, the editor label shows a quiet "Not in episode list · Move…" hint; never show it before metadata loads. A move writes the new anchor and leaves a deletion marker on the old one. If the target already has a note, ask before combining; never overwrite silently.
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
