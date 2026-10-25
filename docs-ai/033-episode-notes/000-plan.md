# 033 — Episode notes with scope chips: Plan

| Field | Value |
| --- | --- |
| Status | In progress |
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
- A season reads its parent's notes filtered to its season. Missing parent relationships may temporarily use local storage. Conversion and duplicate repair must preserve the series payload.
- Empty text is a deletion marker. Inline editing retains a selected empty draft and offers scoped revert; existing detail Discard must restore episode notes as well as overall notes. Reverts advance note clocks.
- Extend `LibraryEntrySyncSnapshot` and `CloudLibrarySyncClient` with normalized note values, independent merge, and newest-clock accounting. New records use a new sync version so older builds cannot overwrite unknown state.
- Proposed shared UI: `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`. Use local or session-owned selection, native pickers, semantic colors, and platform-appropriate sheets. The episode number remains visible while editing. Overall is initially selected; selection persists within the detail session.
- Export structured episode notes in JSON, an additional serialized column in tabular formats, and labeled sections in Markdown.

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
None yet.
