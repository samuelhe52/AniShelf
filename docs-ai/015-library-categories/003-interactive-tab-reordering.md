# 015.003 — Interactive category tab reordering

## Context and intended change

On 2026-10-13 the maintainer supplied Telegram screenshots and requested a separate
Reorder section, the classic edit-mode wiggle, and Done in the upper toolbar.
The existing strip uses SwiftUI system drag/drop, changing order only on drop.

Before implementation, the replacement is planned as an in-place hold-and-pan:
after a short hold, the tab follows the finger and neighboring tabs slide into
new positions. All remains first. A local order previews the move; release saves
it once and cancellation discards it. Edge scrolling exposes offscreen tabs.
Normal horizontal swipes continue to scroll; a short hold distinguishes moving
a tab from scrolling. VoiceOver gets explicit move actions.

Telegram's public `ChatListFilterTabContainerNode.swift` was inspected at
[the upstream source](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Components/ChatList/ChatListFilterTabContainerNode/Sources/ChatListFilterTabContainerNode.swift).
It uses a 0.2-second gesture delay, live local reordering, shaking, and edge
scrolling. This establishes the reference interaction, not an obligation to copy
Telegram's rendering architecture. System drag/drop is rejected because its
lifted preview and drop-target interaction do not match the requested behavior.

The library owns reorder-mode state so the upper toolbar can show Done. Leaving
the strip, entering selection, opening settings/management, or searching ends
the mode. The maintainer's follow-up also disables category long-press menus
during multi-selection; tap-to-switch remains available through plain buttons.
No deletion affordance is added to the tabs in this amendment.

## Validation plan

- Format/lint changed Swift files and check the diff.
- Build, install, and launch using `make run-sim` on the already-booted simulator.
- Run the existing category move/delete tests if persistence code changes.
- Exercise menu grouping, wiggle, hold/pan, edge scrolling, and Done when native
  simulator UI automation is available; identify anything not exercised.

## Outcome

The strip now uses a short-hold UIKit gesture bridged into SwiftUI. The held tab
tracks the finger without a drag preview, neighboring tabs preview the new local
order, and release saves through the existing `moveCategory` path. Cancellation,
an external definition change, or leaving the mode clears the draft. A 28-point
edge zone scrolls the rail while holding a tab. All stays first. VoiceOver offers
localized Move Left / Move Right actions.

Reorder Tabs occupies its own final menu section. Reorder-mode category tabs
wiggle by ±1.2 degrees; the held tab stops wiggling. Done lives in the upper-right
toolbar and replaces the ordinary Select/settings controls during reordering.

The maintainer reported that interactive reordering mostly worked, requested a
snappier/bouncier animation, and moved Done from upper left to upper right.
Neighbor movement and release use SwiftUI's default `.bouncy`, chosen by the
maintainer after reviewing the custom spring and Telegram's 0.25-second
ease-in-out animation. During multi-selection, All and category tabs use plain
buttons, preserving switching without exposing their long-press action menus.

## Validation

- `make run-sim`: built, installed, and launched on the already-booted iPhone 18
  Pro simulator. No additional simulator was booted.
- The maintainer reported that interactive reordering mostly worked. This is
  maintainer-observed evidence, not an agent UI walkthrough.
- Final `make build`: passed after the spring, toolbar placement, and
  multi-selection menu changes.
- Changed Swift files passed `swift format lint`; `git diff --check` passed.
- The final default `.bouncy` change passed `make run-sim`, targeted Swift format
  lint, and `git diff --check`; no manual animation walkthrough was performed.
- The follow-up animation, toolbar placement, and multi-selection menu gating are
  left for the maintainer's visual checks at their request.
- The persistence implementation is unchanged; no redundant unit tests added.
- Catalog changes replace two obsolete strings and add the two accessibility
  actions, with Japanese and Simplified Chinese translations. Feature names and
  public screenshots are unchanged, so no website update is needed.
