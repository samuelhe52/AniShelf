# 016.006 — Lighter palette muting

## Context

On 2026-10-15 Samuel reviewed the muted hub palette from
[004-section-palette.md](004-section-palette.md) on iPhone and asked about the
desaturation strength. After trying 0.2, no muting, and 0.1, Samuel set it to 0.15.

## Change

| Choice | Decision and alternative |
| --- | --- |
| Muting strength | `LibraryProfileSettingsPalette.muted(_:)` now mixes each hue 15% toward `.gray` (was 30%). The helper, the per-section hues, and the muted destructive red from 004 are unchanged. Rejected: removing muting entirely (tried, then reverted to keep the muted palette); 0.2 and 0.1 were tried before Samuel chose 0.15. |

## Refs

- `MyAnimeList/Sources/Models/Library/LibraryProfileSettingsModels.swift`
- `make build` passed at 0.15 on 2026-10-15. The agent did not inspect the recolored hub visually.
