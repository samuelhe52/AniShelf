# 033.003 — Compact episode strip and macOS fade rendering

## Context

The maintainer wanted recent episodes and note-creation controls reachable without
scrolling to the end of the strip. The existing strip restored its last selection,
listed saved episodes in ascending order, and placed the suggested episode and
Other… after all saved episodes. A second row was rejected to preserve vertical
space in the notes box.

This amendment records the implemented follow-up and its observed rendering
failures on 2026-10-26.

## Change

- Entries supporting episode notes open on All. Selection lives in local view
  state and resets when entry identity changes. `EntryNoteScopeMemory` and its
  `entryNotes.lastScopes` reads/writes were removed. Entries without episode-note
  support retain the overall editor.
- Keep one row: All, Overall, and saved episode chips scroll horizontally; the
  suggestion and Other… remain fixed on the trailing side outside the scroller.
- Saved episode chips and episode sections in the inline All overview sort by
  descending season and episode number, rather than by last-edit time. Overall
  remains first in the overview when populated. The expanded reader's ordering is
  unchanged by this follow-up.
- Use compact `E13` or `S2E13` strip labels across languages, including Japanese
  and Simplified Chinese. Series specials use season zero, for example `S0E3`.
  Full localized episode descriptions remain in accessibility labels, editor
  headings, and reader sections.
- All remains available when no episode notes exist. If all notes are empty, its
  Overall placeholder opens the editor. Deleting the selected episode note returns
  to All; deleting the last note while viewing All keeps that overview selected.
- A trailing gradient mask fades the scrollable strip over 16 points. Matching
  trailing content margin lets the last chip scroll fully clear of the fade.

### macOS-only vibrancy workaround

On macOS, the mask caused otherwise unchanged `.fill.tertiary` capsule backgrounds
to render black. Removing only the mask restored their appearance, as confirmed by
the maintainer. The accepted fix restores the actual gradient mask and disables
vibrant rendering only on each capsule's system-fill background:

```swift
Capsule()
    .fill(.fill.tertiary)
    #if os(macOS)
        .environment(\.backgroundMaterial, nil)
    #endif
```

Apple explicitly documents `backgroundMaterial = nil` as a way to disable vibrant
rendering. The fill remains system-defined; its material-blended variant is
intentionally disabled on macOS. This is not a promise of pixel-identical output
to the former vibrant fill. iOS keeps its default rendering because the maintainer
reported that the mask worked there without this workaround. The selected tint
and label styling are unchanged.

The comparison isolates the mask as the trigger in this layout. The exact internal
SwiftUI compositing failure was not independently established.

### Alternatives rejected during this follow-up

| Approach | Reason rejected |
| --- | --- |
| Two strip rows | Adds vertical space to the bounded notes section. |
| `Color.primary.opacity(0.08)` capsule fill | A guessed approximation, not an equivalent of the system tertiary fill; reverted. |
| Separate 16-point masked material overlay | Preserved badge appearance but left a hard clipping boundary visible in the maintainer's screenshot. |
| Horizontal `safeAreaBar` with `.scrollEdgeEffectStyle(.soft, for: .trailing)` | Built and launched, but the maintainer reported a transparent edge rather than the required fade. Removed. |
| Disable capsule vibrancy on both platforms | Narrowed to macOS at the maintainer's request; iOS did not exhibit the issue. |

## Refs

- Implementation: `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`.
- Compact Japanese and Simplified Chinese labels:
  `MyAnimeList/Resources/Localizable.xcstrings`.
- Expanded reader, unchanged by this follow-up:
  `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSheets.swift`.
- [Apple: backgroundMaterial](https://developer.apple.com/documentation/swiftui/environmentvalues/backgroundmaterial).
- [Apple: soft scroll edge effect](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/soft).
- Implementation and localization changes accompany this amendment in the same commit.

## Validation and current state

| Check | Result |
| --- | --- |
| Initial strip changes | Builds and checks were initially skipped at the maintainer's request. The maintainer then supplied the black-capsule screenshot. |
| Mask-disabled comparison | `make run-mac` built and launched successfully with the default 800-entry fixture. The maintainer confirmed the original badge appearance returned. |
| Material-overlay and native-edge experiments | Each `make run-mac` built and launched successfully; maintainer visual checks found the hard boundary and transparent edge described above. Neither experiment remains in the final code. |
| Gradient mask plus capsule `backgroundMaterial = nil` | `make run-mac` built and launched successfully. The maintainer confirmed, "It works now." This check preceded the final platform guard. |
| Final macOS-only guard | Applied and Swift-formatted; no subsequent build or runtime check was run. |
| iOS | Maintainer reported the original mask worked without the workaround. No new iOS build, simulator run, or automated test was performed for this strip follow-up. |

The visual evidence was supplied in this conversation and is not retained in Git.
Agent-side native UI inspection did not yield a reliable visual comparison; the
visual acceptance above is maintainer-reported.
The successful builds emitted an Xcode warning about selecting the first matching
macOS architecture destination; they did not report compilation or launch failure.
These checks do not establish complete pointer/keyboard or narrow-layout acceptance
for all episode-note interactions, and do not change the production-sync validation
limits in the action record.
