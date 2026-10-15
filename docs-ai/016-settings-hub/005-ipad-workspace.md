# 016.005 — Expanded workspace on iPad

## Context

On 2026-10-13 Samuel decided to keep the old settings design for iPad. The hub
solved iPhone's long scroll; at regular width the pre-hub two-column workspace
already fit on screen, so pushing pages only added taps there.

## Change

| Choice | Decision and alternative |
| --- | --- |
| Layout policy | `LibraryProfileSettingsLayoutPolicy.layout(...)` returns `.hub` or `.workspace`, replacing `hubColumns`. Regular width at non-accessibility Dynamic Type gets `.workspace`; compact width and accessibility sizes keep the hub, as the old policy kept the compact card there. |
| Workspace content | A "Settings" title over two columns, as in the retired `LibraryProfileSettingsCard.workspaceGrid`. Left: language, Library & Tracking, Airing & Reminders, Appearance & Interaction. Right: Sync & Data, Metadata & Images, App Info. Each group renders the same `destinationContent(_:)` the pushed page uses, with that destination's tint in `libraryProfilePageTint`. Each group is titled with the destination name (secondary subheadline, header trait), so the guides' "Settings › Sync & Data" paths and the tutorial's five groups hold on iPad too. Rejected: rewording the in-app tutorials and three website guide locales per device. The language panel needs no title; its row already reads "Anime Info Language". Rejected: restoring the deleted card file (it duplicated cloud-sync state that now lives at the root, and lacked the categories, broadcast, and palette changes made since). |
| Hub | The two-column hub branch is removed; the hub is single-column only. App Info moved into `LibraryProfileAppInfoCard`, shared by both layouts: a titled card on the hub (`.card`), and on iPad an inset panel under an "App Info" group title (`.panel`), matching the other workspace groups. Samuel asked for this after the full card's large title looked out of place beside the grey group titles. |
| Navigation | The root `NavigationStack` and path stay on all sizes. If a window widens while a page is pushed, the page stays until Back. |

## Validation

- `make build` passed; `LibraryProfileSettingsLayoutPolicyTests` passed (2 tests).
- `swift format lint` reported no issues in the changed files.
- `make run-sim` built, installed, and launched on the booted iPad Pro 13-inch (M5).
  The workspace was not inspected visually: no UI automation is available to open Settings.
