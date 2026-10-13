# 015.002 — Optional sticky category strip

## Context

The first delivery removed the category strip (see [001-action.md](001-action.md)):
a strip hidden until a pull felt non-linear, and an always-visible strip was
rejected as the default. On 2026-10-13 the maintainer chose to offer an
always-visible strip as an option, modeled on Telegram's chat folder tabs.

## Change (planned)

Decisions taken by the maintainer on 2026-10-13:

| Choice | Decision and alternative |
| --- | --- |
| Where | List and Grid only. Gallery keeps the title capsule menu. |
| Setting | A plain on/off toggle under "Library Categories" in Settings › General, shown only when categories are on, off by default, cloud-synced like the other library preferences. |
| Placement | Pinned under the navigation bar, always visible while on. No pull-to-reveal; that interaction was the reason the first strip was removed. |
| Tab style | Telegram text tabs: "All" first, then categories in display order, scrolling sideways, with a tinted underline that slides to the selected tab. Capsule chips were rejected. No counts on tabs. |
| Long press | Telegram menu: a category tab gives Reorder, Rename, Edit Categories…, Delete; "All" gives Reorder and Edit Categories…. Reorder makes the tabs draggable until Done; "All" stays first. "Menu only" was rejected. |
| Swipe content | No. Sideways swipes on the List or Grid do not switch category; they would compete with List swipe actions. |
| Title capsule | While the strip shows (List or Grid with the option on), the capsule shows the plain title with no category name and no menu. Gallery and strip-off keep the capsule menu. |
| Multi-selection | The strip hides during multi-selection, like the capsule menu, because switching category would drop selected anime outside the view. |

## Refs

To be filled in after implementation.
