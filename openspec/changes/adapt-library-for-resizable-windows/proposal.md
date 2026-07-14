## Why

AniShelf currently scales its phone-oriented library and modal presentations into larger or freely resizable windows without changing their structure, which can waste available space or produce poorly proportioned sheets. The app needs a content-driven adaptive model now that iPad windows and iOS 27 iPhone-app environments can resize across a continuous range, while the established on-device iPhone experience must remain behaviorally and visually unchanged.

## What Changes

- Keep Gallery, List, and Grid as full-canvas library modes by default instead of placing them permanently in a navigation sidebar.
- Introduce an on-demand detail presentation that can coexist beside the library as a trailing inspector when both surfaces remain useful, and otherwise preserves the current sheet experience.
- Adapt Gallery into a horizontally browsable shelf as space grows, revealing neighboring entries without turning Gallery into a narrow master column.
- Let List continue using additional width for rich rows and let Grid add adaptive columns; neither mode loses space to an empty persistent detail pane.
- Select layouts from the available content area and the minimum viable geometry of the active mode, not from device idiom, orientation, or named device families.
- Preserve the current iPhone library layout, gestures, toolbars, transitions, and sheet behavior at all existing on-device iPhone sizes.
- Preserve focused entry, scroll position, selection, and active workflows across live window resizing without dismissing or resetting an in-progress task as its presentation adapts.
- Classify and adapt content-heavy sheets using semantic presentation sizes and responsive internal layouts, while retaining system alerts, confirmation dialogs, popovers, and full-screen media previews where they already fit their purpose.
- Add a resizable-window and current-iPhone regression matrix covering all library modes and modal destinations.

## Capabilities

### New Capabilities

- `adaptive-library-experience`: Content-fit-driven library layouts, Gallery shelf behavior, on-demand detail inspection, state preservation during resizing, and exact compatibility with the current iPhone experience.
- `adaptive-modal-presentations`: Purpose-based sizing and responsive composition for AniShelf's content-heavy sheets and nested modal workflows.

### Modified Capabilities

None.

## Impact

- Affects the library shell, Gallery/List/Grid views, entry interaction and presentation state, entry detail composition, and library toolbars.
- Affects Search/Add Anime, poster selection, sharing, profile/settings, API configuration, Support, About, and What's New presentations.
- Requires centralizing presentation intent that is currently distributed across multiple view-local sheet modifiers.
- Requires no data-model, persistence-schema, network API, or third-party dependency changes.
- Adds layout-focused previews or UI coverage and current-iPhone regression validation.
