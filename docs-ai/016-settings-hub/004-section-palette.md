# 016.004 — Muted section palette

## Context

On 2026-10-13 Samuel reviewed the hub on iPhone and said the spectrum colors
looked messy, asking to reference the pre-hub palette. Nine evenly stepped hues
(teal through rose) put a different color on every hub row. After the original
palette was restored, Samuel asked to keep it but desaturate it a bit.

## Change

| Choice | Decision and alternative |
| --- | --- |
| Destination tints | Each destination takes the hue its sections used before the hub: language blue, Library & Tracking mint, Appearance & Interaction teal, Airing & Reminders orange, Metadata & Images cyan (the old TMDb card), Sync & Data indigo (the old iCloud card). `LibraryProfileSettingsPalette.step(_:)` is removed. |
| App Info rows | What's New, Support, and About share the old maintenance-list accent (`LibraryProfileSettingsPalette.appInfo`, sky blue) instead of continuing the spectrum into pink and rose. |
| Saturation | `LibraryProfileSettingsPalette.muted(_:)` mixes each hue toward `.gray` (originally 30%, 15% since [006-palette-strength.md](006-palette-strength.md)) with `Color.mix(with:by:)`, so system colors keep their light and dark variants. Rejected: a desaturated spectrum (fixed HSB values; Samuel wanted the section palette, not the spectrum), and hand-picked HSB values per hue (lose the system dark-mode variants). |
| Destructive actions | Restore, Delete All Animes, and Remove All reminders use `LibraryProfileSettingsPalette.destructive` (red muted the same way). Full-saturation red beside the muted indigo on Sync & Data read as two clashing accents. Error and sync-failure status text stays full `.red`, since it signals state rather than decorating an action. |
| Pages | Each pushed page still uses one tint for all its cards, so the 002 concern (several unrelated hues on one page) does not return; Backup & Restore now reads indigo with the rest of Sync & Data instead of its old orange. |

## Validation

- `make run-sim` built, installed, and launched on the booted iPhone 18 Pro. The
  recolored hub was not inspected visually by the agent.
