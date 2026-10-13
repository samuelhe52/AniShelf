# 016.003 — Inline anime info language

## Context

Samuel asked on 2026-10-13 that the info settings appear directly on the hub
instead of on their own page. "Info settings" was read as the Anime Info
Language destination: the App Info rows already open their sheets directly.
A first pass placed the existing language card above the Settings card; Samuel
corrected that it should stay inside the Settings card, just inline.

## Change

| Choice | Decision and alternative |
| --- | --- |
| Language placement | `LibraryProfileLanguageSettingsRow` is the first row of the Settings card, full width above the destination rows at both column counts. It uses the hub row's icon and height, with the Follow System toggle trailing; turning it off reveals the segmented picker below, spanning the full row so it stays centered in the card (a first pass indented it to the row text, which read as off-center). It replaces `LibraryProfileLanguageSettingsSection`, which was only used by the pushed page. Rejected: a separate card outside Settings (Samuel's correction). The Follow System toggle and segmented picker are short, so a push added a tap without saving space. |
| Removed | The `.language` destination, its status summary (`System (%@)`), and the section subtitle "Choose the language used for future metadata fetches." (both removed from the catalog). |
| Hub columns | Five destinations remain; regular width splits them column-major 3 + 2. |
| Tint | The language row keeps spectrum step 0 through `LibraryProfileSettingsPalette.language`, so the hub still reads teal first, then the destinations from step 1. |

The app tutorials' step 9 now describe the inline language setting and five
groups. The website guides only say "open Settings … under Anime Info
Language", which still holds, so they were not changed.

## Validation

- `make build` / `make run-sim` built cleanly; `swift format lint` reported no
  issues in the changed files.
- `make run-sim` installed and launched on the booted iPhone 18 Pro. The hub was
  not inspected visually: no UI automation is available to open Settings.
