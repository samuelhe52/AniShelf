# 031.006 — Folded inspector glass: accepted limitation

## Context

On 2026-10-23, the maintainer reported that detail cards and quick-action buttons
look flat gray on iPhone Duo's folded cover display, while the same inspector has
raised Liquid Glass surfaces on the unfolded inner display. This was investigated
after `b5cad7f` kept the native inspector mounted across folds (005).

## Decision

**Known and accepted limitation, accepted by the maintainer on 2026-10-23.** Leave
the current implementation and appearance as-is. Keep native inspector adaptation
and its continuity across folds. Further visual workarounds are not part of the
accepted scope; revisit only if the maintainer reopens the issue or platform
changes warrant another check.

Both the folded Duo grouped-background override and the `GlassEffectContainer`
experiment were removed; the maintainer explicitly requested reverting the
remaining background override after accepting the limitation. No source changes
from this investigation remain. This acceptance does not claim that the glass
appearance was fixed.

## Investigation and validation

Observed on the already-booted iPhone Duo simulator, iOS 27.1:

| Check | Observed result |
| --- | --- |
| Existing glass styling | Both poses use the same `.glassEffect(.regular, in:)` card modifier and `.glass` action-button style. The Mac-only grouped panel style is not selected. |
| Folded background override experiment | Used `systemGroupedBackground` for the compact, natively adapting inspector and its hero fade. Captured page background changed from white (`#FFFFFF`) to grouped (`#F2F2F7`); the cards remained flat. The override was subsequently reverted. |
| Standalone presentation probe | Identical card content rendered flat in a compact native inspector, with raised glass in an unfolded inspector and in an ordinary sheet. Changing presentation or content background colors did not restore the compact inspector's glass. |
| Explicit `GlassEffectContainer(spacing: 0)` around the app's quick actions and detail cards | Built and launched with `make run-sim`. Folded cards remained flat; unfolding restored depth. The experiment was removed. |
| Final state | Rebuilt and relaunched with `make run-sim` after removing the container. Subsequently reverted the background override at the maintainer's request; both source files match `HEAD`. `git diff --check` passed. No rebuild or relaunch after the final background-override revert. |

The evidence isolates a difference associated with the native inspector's compact
presentation. Its internal material/compositing mechanism remains an inference;
the investigation did not establish an Apple-confirmed Duo defect or a verified
public-API workaround. Physical hardware was not tested. Screenshots, probe code,
and build logs were local investigation artifacts and are not retained in this
record. No new unit tests were added for this visual experiment.

## Refs

- [Native inspector adaptation](005-native-inspector-adaptation.md)
- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Sources/Views/Gadgets/PopupDesignSystem.swift`
