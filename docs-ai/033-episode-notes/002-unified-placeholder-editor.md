# 033.002 — Unified placeholder text editor

## Context

After episode notes shipped, the app had two multiline editors. The detail notes
editor used `ScrollIsolatedPlaceholderTextEditor`, which on iOS wrapped a `UITextView`.
It was added in `a9c7ae5` ("Stabilize note editor scrolling") to fix scrolling in the
detail page. The episode note sheet and TMDb Batch Add used `PlaceholderTextEditor`, a
SwiftUI `TextEditor` with a placeholder overlay. The maintainer asked for one editor.

The `UITextView` wrapper contained no explicit scroll-isolation logic. It also lacked
focus support, ignored the SwiftUI `.font` modifier, kept the binding it was created
with, and wrote the binding's value back into the view whenever the two differed.

## Change

`PlaceholderTextEditor` is now the only editor; `ScrollIsolatedPlaceholderTextEditor`
was removed.

- **iOS:** a `UITextView` subclass (`PlaceholderUITextView`) draws the placeholder as an
  internal `UILabel`. The label uses the text view's font and insets, so it stays lined
  up with the caret.
- **macOS:** `TextEditor` with a placeholder overlay, unchanged in substance. No Mac
  problem motivated an `NSTextView` bridge.
- **Explicit options** replace modifiers the bridge cannot read:
  - `isLiteralInput`: monospaced, with autocorrection, capitalization, spell checking,
    and smart punctuation off. Batch Add uses it on both platforms, so its iOS editor is
    now monospaced like the Mac one.
  - `autofocus`: focuses the editor when it appears. On iOS it calls
    `becomeFirstResponder` once the view is in a window. On macOS an internal
    `@FocusState` handles it. `EpisodeNoteEditor` dropped its own focus state.
- **Text sync:** `updateUIView` writes the binding's value into the view only when that
  value has changed since the last update, never while composition text is active, and
  refreshes the coordinator's binding. This sync was redesigned because the model can
  reject keystrokes: `updateEpisodeNote` stores whitespace-only text as empty. Echoing
  the model's value back would erase leading whitespace typed into an empty episode
  note. Skipping writes during typing also keeps the `UITextView` undo stack intact.

Rejected alternatives:

- Unifying on SwiftUI `TextEditor` would risk bringing back the scrolling problem that
  `a9c7ae5` fixed.
- Keeping the placeholder as a SwiftUI overlay above the bridge would let the
  placeholder and typed text use different fonts, because the bridge ignores the
  SwiftUI font environment.

## Refs

- Landed in the commit that adds this file.
- Files: `MyAnimeList/Sources/Views/Gadgets/PlaceholderTextEditor.swift`,
  `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`,
  `MyAnimeList/Sources/Views/Library/EntryDetail/EpisodeNoteEditor.swift`,
  `MyAnimeList/Sources/Views/SearchPage/TMDbBatchAddView.swift`.

## Validation

- `make build` and `make build-mac` succeeded.
- The maintainer manually tested all three iOS editors on the simulator and found them
  working.
- During testing, pasted text appeared as blank space in all iOS editors. The problem
  went away after the simulator was rebooted, so it was treated as a simulator quirk.
  If it shows up on a device, revisit it.
- The root cause of the original `TextEditor` scrolling problem was never identified.
