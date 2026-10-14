# 020.008 — Mac-native UI

## Context

After the four slices and the boundary refactor ([007](007-platform-boundary-refactor.md)),
the maintainer asked where the Mac UI still felt ported from mobile. Claude, working
from source and the slice screenshots, and a Codex session (GPT-6.1 Sol), working
from source, answered separately. Their findings were merged into one 24-item
list, and both agreed on the set below on 2026-10-16, before any code changed.
The maintainer then reviewed several snapshot builds by hand. This record covers
the agreed set, the follow-ups from those reviews, the window-sizing decisions,
and the Mac app-info windows added after
[021](../021-mac-selection-model/000-plan.md).

This record replaces three earlier amendments: the UI pass, an inspector and
settings follow-up, and a system window sizing record. Their review-round detail
is condensed here. The approaches they tried and rejected are kept in the
decision tables.

## Agreed set

Mac only; iOS behavior and layout stay as they were.

| # | Item | Mac design |
| --- | --- | --- |
| 1 | Compact inspector | `MacEntryDetailHeader`: a small poster with title, metadata, and genres replaces the 420pt hero, with the actions in one row of small buttons. Stats are label/value rows, and section cards render as grouped sections (`PopupPanelStyle.grouped`, set inside the inspector's scroll view only). No Done button. |
| 2 | Episode controls | An editable episode number with a stepper, plus Reset Progress and Mark Season Watched in a menu. These are the operations behind the iOS long presses. Clicking an episode row opens its preview. |
| 3 | Inline Find, TMDb-only Add | Each window has a toolbar search field (⌘F) that filters the current scope with `LibrarySearchMatcher.matcher(for:)`, the search page's predicates. The Add sheet (⌘N) searches TMDb only, with a redesigned Batch Add: one bordered editor, actions in the sheet bar. |
| 4 | Batch actions in the inspector | During a batch selection the toolbar keeps its browsing controls, and the inspector shows the batch panel. Its current form is the multi-item inspector of [021](../021-mac-selection-model/001-action.md). |
| 5 | Compact List rows | About 64pt rows: a small poster, title, a date/episodes line, and badges. The list uses the inset selection style. |
| 6 | Settings | Grouped `Form` pages through `LibraryProfileSettingsGroup` (a Form section on the Mac, the existing card on iOS), native Pickers, description rows with push buttons, an inline reminder list with a timing menu per reminder, and a compact custom-timing form. The Overview page is `MacSettingsOverview`. |
| 7 | No Gallery | The Mac offers List and Grid (⌘1, ⌘2). A stored Gallery preference shows as Grid. Added at the maintainer's suggestion. |

## Decisions

| Choice | Reason and rejected alternative |
| --- | --- |
| No Done in the Mac inspector | Inspector edits are written as they are made. Done's only Mac-specific effect was discarding rewritten notes, which is now an inline Revert Notes button that restores notes only. A first build put Discard Changes in the header: it overflowed the 340pt inspector and restored all of `originalUserInfo`, not just notes. |
| Batch actions in the inspector, not the toolbar | A wide toolbar caused the layout loop recorded in [004](004-slice-2-mac-shell.md). The inspector already reserves a column. |
| Settings as grouped forms | A chevrons-only cleanup was tried first. The maintainer found the pages still read as mobile, with small text and loose spacing. |
| `KFImageView` starts from a synchronous memory-cache lookup | Lazy grids recreate cells while a window resizes, and posters flashed back to placeholders. This applies on iOS too (`9be901a`). |
| Let AppKit size the window when the inspector opens | The default `NSSplitViewItem.collapseBehavior` grows the window so sibling panes keep their size, and keeps it on screen (macOS 27 SDK header). SwiftUI does not expose the property, and reaching SwiftUI's private `NSSplitViewController` was rejected as just a sturdier workaround. Three earlier countermeasures were removed: `keepWindowWidthForInspector()`, which reset the width after timed delays; collapsing the sidebar when the window was narrower than the sidebar plus 720pt; and the 720pt inspector-open column minimum. The library column now has a fixed 520pt minimum. |
| Drop the inspector-open column minimum | It guarded against the toolbar layout loop from 004. With the minimum removed, Claude shrank a window to its 808pt minimum with the inspector restored and open (Japanese UI), and the maintainer reported that the crash no longer reproduces. The likely reason, not verified, is that the toolbar is smaller now: the browse menu became glyph-only in [006](006-slice-4-polish.md), and Gallery and the Search button were removed here. 004's bisection found that fewer toolbar items avoided the loop. |

Rejected after maintainer review, and superseded by [021](../021-mac-selection-model/000-plan.md):

| Attempt | Why it failed |
| --- | --- |
| Pinning the clicked grid card with corrective `scrollTo` calls, and disabling the grid's reflow animation | Jitter remained. The grid went back to the iPad's scoped reflow animation (`f2ef101`). |
| A computed inspector binding that read batch visibility live, then a stored binding reconciled with detail and batch state | Opening a batch from an inspected entry still failed intermittently. SwiftUI's own dismissal callback could not be told apart from a content swap. 021 made inspector visibility a window setting. |
| Measuring the browser width outside the inspector's animated host and pinning the grid to it | A drafted fix for the grid jitter, discarded before commit for a clean baseline. |

Deferred: notes autosave behavior, sheet chrome, a poster popover, haptics and
context-menu previews, blanket hover effects, swipe actions, the date-picker
style, and category drag-and-drop.

## Mac app-info windows

Added after 021, at the maintainer's request (`f9b327e`):

- AniShelf ▸ About AniShelf opens a fixed-size About window (`MacAboutView`).
- AniShelf ▸ Support AniShelf… opens a Support window (`MacSupportView`) with the
  tips as form rows.
- Help ▸ What's New in AniShelf presents `MacWhatsNewView` in the front library
  window, or opens one. It is a sheet, as the automatic post-update presentation
  already is.
- The Settings Overview has no App Info rows.

Each is a separate Mac view. The iOS sheets keep their designs, and the logic and
copy both platforms use are shared types: `AboutAniShelfContent`,
`SupportAniShelfCopy`, `SupportPurchaseFlow`, `SupportThankYouView`, and the
What's New components. A first version put the Mac layouts in `#if os(macOS)`
branches inside the iOS views; the maintainer preferred separate views.

## Validation

- Each commit builds for iOS and the Mac. Focused tests passed on the booted
  iPad simulator and on the Mac: `LibraryEntryInteractionStateTests`,
  `LibraryProfileSettingsLayoutPolicyTests`, `LibraryGalleryLayoutPolicyTests`,
  `LibraryMetadataRefreshTests`, and `WhatsNewAndRefreshTests`.
- Codex inspected snapshot builds with computer use in rounds `u1`–`u3`, and the
  maintainer checked later rounds by hand. Screenshots were local and not
  retained.
- Not verified at runtime: the app-info windows and the What's New layout.

## Open issues

- The grid's `AXScrollToBottom` accessibility action crashed a snapshot once
  (`EXC_BREAKPOINT` in lazy-layout `ForEach` frames). Not reproduced.
- The "past the screen edge" widening that 004 measured conflicts with the SDK
  header's on-screen guarantee. It was not re-measured.

## Refs

- Commits: `3a71bb7` (this pass, including window sizing), `9be901a` (poster
  cache), `f9b327e` (app-info windows).
- `MyAnimeList/Sources/Mac/MacEntryDetailHeader.swift`,
  `MyAnimeList/Sources/Mac/MacSettingsOverview.swift`,
  `MyAnimeList/Sources/Mac/MacAiringReminderSettings.swift`,
  `MyAnimeList/Sources/Mac/MacAboutView.swift`,
  `MyAnimeList/Sources/Mac/MacSupportView.swift`,
  `MyAnimeList/Sources/Mac/MacWhatsNewView.swift`,
  `MyAnimeList/Sources/Mac/LibraryView+Mac.swift`.
