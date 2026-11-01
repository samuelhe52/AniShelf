# 021.002 — Reduce work during Mac List selection

## Context

On 2026-10-31 the maintainer reported delayed arrow-key selection in the Mac
List. Sampling the already-running Debug app with its 800-entry fixture library
and the inspector hidden showed `EntryDetailViewModel.load` saving fetched
details, `LibraryStore.refreshLibrary` invalidating the browse cache, and
`LibraryBrowseScope.display` rebuilding row snapshots during arrow navigation.
This establishes unnecessary hidden-inspector work; the capture does not measure
key-to-highlight latency or establish its share of the reported delay.

## Change

Gated the inspector's selection content and presented detail identity on
`isPresented`. Closing it removes the detail view and clears its session;
opening it resolves the current selection again. Keep the inspector toolbar
outside the gate so Show Inspector remains available while collapsed.

Retain native List keyboard selection and synchronous selection state. Adding
a keyboard debounce would delay feedback and leave the underlying work intact.
The List also avoids redundant focus writes when it already has focus.

The maintainer confirmed the delay occurs with the inspector both open and
hidden. A second capture found `MacLibraryList.rowContent` building the row's
content and swipe actions inside `NSTableView` arrow-key selection handling.
Extracted that content into a private `MacLibraryListRow` view so the data closure
constructs a small view value with a stable body boundary. Keep the native
selection tag on the data closure's result. Each row owns its Open In alert
request; its content and actions no longer capture the whole List value.

Source: `MyAnimeList/Sources/Mac/MacLibraryInspector.swift` and
`MyAnimeList/Sources/Mac/MacLibraryList.swift`.

## Validation

- `make build-mac` passed.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/MacLibrarySelectionTests MyAnimeListTests/EntryDetailSessionTests'`
  passed: 4 selection tests and 8 session tests.
- After the maintainer authorized relaunching, `make launch-mac` opened the
  updated Debug app with 800 generated fixture entries on macOS 27.2.
- Native UI checks confirmed arrow navigation with the inspector hidden and
  open, Shift-arrow range selection with the batch inspector, collapse back to
  one entry, reopening the inspector on the current selection, and Return
  opening the inspector after selection moved while it was hidden. A screenshot
  confirmed the selected row and the reopened inspector rendered together.
- In a 12-second capture of four alternating Down/Up presses with the inspector
  hidden, the updated app had no sampled `EntryDetailViewModel.load`,
  `LibraryStore.handleLibrarySaveNotification`, or `LibraryBrowseScope.display`
  stacks. All three appeared in the corresponding pre-change capture. The
  updated capture also contained less native arrow-handler work, with its data
  closure constructing `MacLibraryListRow` values rather than full row content.
- With the inspector open, the updated app still loads details and rebuilds the
  browse cache when those loads save metadata. This work remains; the row
  extraction reduces synchronous native selection work in both visibility states.

## Open-inspector follow-up

The maintainer confirmed that the first patch improves the hidden-inspector
case but leaves the open-inspector delay. The save-classification redesign,
unchanged-response guard, staff-jobs persistence repair, cancellation lifecycle,
and final validation are recorded separately in
[039 — Library membership changes drive save refreshes](../039-library-save-invalidation/000-plan.md).

## First-patch validation limits

These are sampled Debug fixture runs, not key-to-highlight latency measurements
or real-library acceptance. The automation's accessibility reads add work and
its key injection adds elapsed time; neither tool-call duration nor sample counts
are an end-to-end latency benchmark. The first longer automation sequence timed
out, so the comparison used a separate four-key capture.

The extracted rows still expose Edit, Share, Delete, and Open accessibility
actions. Attempts to open the pointer context menu did not surface a menu in
the automation, so context-menu interaction remains unverified. Trackpad swipe
gestures and category dragging were not exercised. That first runtime check ended with the fixture inspector hidden. No new regression tests were added for
the view wiring; the runtime checks above supplement existing state tests.
