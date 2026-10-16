# 020.008 — Mac-native UI pass

## Context

The maintainer asked where the Mac UI still feels ported from mobile. Claude
(working from source and the slice screenshots) and a Codex session (GPT-6.1 Sol,
working from source) answered separately. Their findings were merged into a
24-item list. After `71ab52f` the maintainer asked both to recheck the list
against HEAD (`47fbfe5`), discuss it, and agree on the most critical items.
Codex rechecked every item and inspected a snapshot build with computer use
(round `u1`; its screenshots were local and not retained). The two
agreed on the set below on 2026-10-16, before any code changed.

Status: **Implemented and committed** (`b6ebfe9`..`c62364b`, listed under
Commits). The maintainer's visual pass of the last build (round `u6`) was still
in progress when the work was committed; its findings will be follow-ups.

## Agreed set

Everything here is Mac-only; iOS behavior and layout must not change. The items
are in implementation order.

| # | Item | Mac design |
| --- | --- | --- |
| 1 | Compact inspector | A small poster with title, metadata, and genres beside it replaces the 420pt hero. Actions sit in one row of small buttons. Stat tiles become a compact label/value row. Section cards render as plain labelled sections. The inspector's Done button is removed (see the decisions below). |
| 2 | Episode controls | Episode progress gets an editable number field with a stepper and an explicit menu with Reset Progress and Mark Season Watched. These reuse the operations that the iOS long presses trigger. Clicking an episode row, or its context-menu Preview item, opens the preview; long press stays iOS-only. |
| 3 | Inline Find, TMDb-only Add | Each window gets a toolbar search field that filters the current scope with the same matching as `LibrarySearchService`; ⌘F focuses it. The Add sheet drops its Library mode, gets a wide search field at the top, and makes Batch Add a secondary action. |
| 4 | Batch selection in the inspector | During a batch selection the toolbar keeps its browsing controls. The inspector shows an "N Selected" panel with the batch actions. Escape or a click on empty space ends the selection; there is no Done. |
| 5 | Compact List row | Rows are about 64pt: small poster, title, date/episodes line, status/progress/score badges, no synopsis. |
| 6 | Settings command rows | Rows that run a command lose the navigation chevron and get tighter padding. Chevrons stay only on rows that navigate. |
| 7 | No Gallery on the Mac | Added 2026-10-16 at the maintainer's suggestion. The Mac offers List and Grid; ⌘1 and ⌘2 select them. A stored Gallery preference shows as Grid on the Mac, and iOS keeps Gallery. |

## Decisions

| Choice | Reason and alternative |
| --- | --- |
| Remove Done from the Mac inspector | Inspector edits are written to the entry as they are made. Done → `closePresentation()` keeps them, and switching entries or toggling the inspector keeps them too. Its only extra on the Mac is Discard for notes that were rewritten rather than appended (`shouldConfirmBeforeSaving`). An inline Revert Notes button in that state keeps the Discard path without changing how edits persist. Changing the notes autosave behavior itself was deferred. |
| Batch actions in the inspector, not the toolbar | The toolbar's width caused the AppKit layout loop recorded in [004](004-slice-2-mac-shell.md). Adding batch controls next to the browsing controls risks that loop again. The inspector already reserves a column. |
| Merge Codex's "Add composition" item into Inline Find | Once Find is inline, the Library mode in the Add sheet has no purpose on the Mac. |
| Settings: chevrons only, not a form restyle | Reversed after the maintainer's round-`u4` check: the pages still read as mobile, with small text and loose spacing. Settings now use grouped Forms (see the maintainer feedback round below). |

Deferred: notes autosave behavior, sheet chrome, a poster popover, detents,
haptics and context-menu previews, blanket hover effects, removing swipe
actions, the date-picker style, category drag-and-drop or removing the manager,
toasts and target sizes.

Codex also caught a crash during round `u1`: invoking the grid's `AXScrollToBottom`
accessibility action crashed the snapshot with `EXC_BREAKPOINT`
(`AccessibilityNode.scrollToBeginning()` and lazy-layout `ForEach` frames). It was
observed once. It is tracked separately from this pass.

## Implementation notes

What was built, where it differs from the agreed designs, and what the reviews changed:

- **Item 1:** `PopupPanelStyle` (`.glass`, `.grouped`) is an environment value
  read by `PopupSectionCard`, `PopupDisclosureCard`, `popupGlassPanel`,
  `DetailStatCard`, and the quick-action buttons. `EntryDetailView.macInspectorContent`
  sets `.grouped` inside the scroll view only, so sheets presented from the
  inspector keep their own styling. The header is `MacEntryDetailHeader`. On the
  Mac, stats are label/value rows in one box: three tiles truncated "TMDb Score"
  at the 340pt inspector minimum (Codex, round `u2`).
- **Revert Notes, not Discard Changes.** The first build put Discard Changes in
  the header. It overflowed the 340pt inspector and restored the whole
  `originalUserInfo` (status, score, progress, and dates), not just notes (Codex,
  `u2`). It is now Revert Notes beside the Notes label, and it restores notes
  only.
- **Item 2:** the episode preview synopsis needed `fixedSize(vertical:)` on the
  Mac; the popover proposed a one-line height.
- **Item 3:** `LibrarySearchService.matcher(for:)` shares the search page's
  predicates. The predicates were moved into one ordered list, keeping the
  ranking. An explicit reveal (Add, or jumping to a duplicate) clears the
  window's Find text when that text hides the entry.
- **Item 4:** the batch panel is `MacBatchSelectionPanel`, shown through the
  existing inspector modifier. On the Mac, batch actions no longer end the
  selection, because Finder-style selections persist. A filter or scope change
  that leaves one entry inspects it, and one that leaves none ends the batch.
  Escape ends a batch anywhere in the window. These three came from Codex's
  `u3` review. Show Inspector during a batch now toggles the panel; it no
  longer narrows the batch to one entry as [004](004-slice-2-mac-shell.md)
  recorded.
- **Item 7:** `MacGalleryPager` (hover arrows and ←/→ paging) was deleted. The
  Mac-only `supportsMultiSelection` guards in the selection code are gone,
  because every Mac view style now supports selection.

## Maintainer feedback round (`u4`)

While Codex reviewed items 3–6, the maintainer checked the snapshot by hand and
reported these problems, some outside the agreed set. All were fixed:

- **Add sheet:** the empty state was not centered, and the Batch Add placeholder
  did not line up with the cursor. Batch Add was redesigned for the Mac: one
  bordered editor, actions in the sheet bar, no nested panels.
- **Inspector animation:** opening the inspector, and switching entries while
  it was open, slid content in from the leading edge. Diagnosed from source, not
  from recordings: `.id(session.instanceID)` with an animated `.transition`
  inserted the new content at zero width. The Mac drops the transition and
  animation and uses `.geometryGroup()` instead; the batch panel gets
  `.geometryGroup()` too.
- **Batch panel:** a second ⌘-click sometimes failed to open it, because SwiftUI
  wrote `false` to the inspector binding while detail gave way to the panel. The
  binding now ignores `false` while the panel is showing. Its action buttons
  became full-width rows, and posters added to the stack animate in.
- **Resize:** posters reloaded while the window resized. `KFImageView` now starts
  from a synchronous Kingfisher memory-cache lookup with the processor-aware
  key; this also applies to iOS.
- **List selection:** the edge-to-edge highlight was too prominent; the Mac list
  uses the inset style.
- **Inspector width:** the 1000pt inspector-open minimum from
  [004](004-slice-2-mac-shell.md) was too restrictive, and opening the inspector
  from a narrow window made it jump wider. Codex bisected the minimum with a
  temporary launch override (round `u5`): every value from 1000 down to 680pt
  survived inspector toggles, an expanded Find field, and relaunch with the
  inspector restored, with no hang or `NSGenericException`. At 680pt Add and
  Hide Inspector fell into the toolbar's overflow menu, so the minimum was set
  to 720pt, which also held in Japanese. (Removed in
  [010](010-system-window-sizing.md).) A lower minimum alone still widened a
  narrow window (711pt to 910pt), so a window narrower than the sidebar plus
  720pt collapsed the sidebar when the inspector opened and restored it when
  the inspector closed. (Removed in [010](010-system-window-sizing.md); the
  window now widens as AppKit decides.)
- **Settings:** the pages did not feel designed for the desktop. They are now
  grouped Forms on the Mac, through `LibraryProfileSettingsGroup` (a Form
  `Section` on the Mac, the existing card on iOS), and the Overview page is a
  form (`MacSettingsOverview`).

An independent Codex review (GPT-6.1 Sol, built-in reviewer) of the full diff
found two P2 bugs, both fixed: the batch snapshot was not refreshed after an
action that keeps the selection, so badges went stale and entries the action
moved out of the filter stayed selected; and a context-menu Edit during a batch
did nothing, because the batch panel kept covering the inspector. Opening or
editing one entry now ends the batch.

## Maintainer feedback round (`u6`)

**2026-10-16 correction:** Subsequent maintainer testing found grid jitter and batch
inspector opening still broken. The iPad scroll-position explanation below was
unsupported. See [009](009-inspector-and-settings-follow-up.md).

The maintainer's pass over the committed build found more problems. Follow-up
fixes were attempted from source and two supplied recordings:

- **Grid reflow on inspector open:** the earlier change disabled Mac reflow
  animation and tried to pin the clicked card with `scrollTo`. The maintainer
  found jitter remained; 009 removes this workaround and restores the scoped
  animation used on iPad. The sidebar collapse was also given an animation.
- **Batch from one inspected entry:** the earlier change made the computed
  inspector binding read batch visibility live and shared the column container.
  This did not resolve opening in the maintainer's testing; 009 replaces the
  computed Mac presentation binding with stored presentation state.
- **Poster stack:** it followed layout order and showed only the first four,
  so new selections landed anywhere or not at all. It now follows selection
  order, newest on top.
- **Inspector controls:** the status picker's empty label clipped its first
  segment; dates are label/value rows; notes use a bordered text area; person
  cards use the window background so they show in light mode.
- **Sidebar and toolbar:** New Category moved to the sidebar foot; the browse
  menu shows one filter glyph instead of the iOS capsule.
- **Settings:** the reminder list is inline in the form, with a timing menu per
  reminder (the timing sheet remains for custom offsets); Backup & Restore and
  Manage Categories use description rows with push buttons.

## Commits

| Commit | Scope |
| --- | --- |
| `b6ebfe9` | Compact inspector (item 1), Revert Notes, inspector animation fix |
| `11904fe` | Episode progress controls and click-to-preview (item 2) |
| `19a5ccc` | Compact List rows and inset selection (item 5) |
| `6079ef8` | Poster memory-cache start (`KFImageView`, both platforms) |
| `bca7085` | No Gallery on the Mac (item 7) |
| `1c6782d` | Inline Find (item 3, first half) |
| `aae9766` | TMDb-only Add sheet and Batch Add redesign (item 3, second half) |
| `ee58829` | Batch actions in the inspector (item 4) and the review fixes |
| `c42440c` | 720pt inspector-open minimum and sidebar collapse |
| `c62364b` | Settings grouped Forms (item 6 and the restyle) |

## Validation

- Each commit's tree was built on its own for iOS (`make build`) and the
  Mac (`xcodebuild`).
- Focused app tests passed on the booted simulator and on the Mac:
  `LibraryMetadataRefreshTests`, `LibraryEntryInteractionStateTests`,
  `LibraryGalleryLayoutPolicyTests`, and `LibraryProfileSettingsLayoutPolicyTests`.
  They ran before the two review fixes and were not rerun after them.
- Codex visual rounds `u1`–`u3` covered items 1–6; the maintainer checked
  rounds `u4` and `u6` by hand. Codex stopped doing visual passes after `u5`,
  at the maintainer's request.

## Refs

- Merged findings: `~/Desktop/AniShelf-macOS-mobile-carryovers.md` (outside the repo)
- Codex thread `01a14321-e9b9-76c3-825b-f664cd5594c3`
