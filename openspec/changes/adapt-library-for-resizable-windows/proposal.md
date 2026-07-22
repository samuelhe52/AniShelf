## Why

AniShelf currently scales its phone-oriented library and modal presentations into larger or freely resizable windows without changing their structure, which can waste available space or produce poorly proportioned sheets. The app needs a content-driven adaptive model now that iPad windows and iOS 27 iPhone-app environments can resize across a continuous range, while the established on-device iPhone experience must remain behaviorally and visually unchanged.

## What Changes

- Keep Gallery, List, and Grid as full-canvas library modes by default instead of placing them permanently in a navigation sidebar.
- Always present Gallery entry detail in a genuine system sheet so the shelf retains its neighboring posters. In List and Grid, use a genuine sheet in horizontally compact environments and a trailing system inspector in horizontally regular environments.
- Adapt Gallery into a horizontally browsable shelf as space grows, revealing neighboring entries without turning Gallery into a narrow master column.
- Let List continue using additional width for rich rows and let Grid add adaptive columns; neither mode loses space to an empty persistent detail pane.
- Select Gallery arrangements from Gallery's available content area and minimum viable card geometry, not from device idiom, orientation, or named device families.
- Preserve the current iPhone library layout, gestures, toolbars, transitions, and sheet behavior at all existing on-device iPhone sizes.
- Preserve focused entry, scroll position, selection, detail session, and root-owned workflows across live window resizing. Root-owned Search, profile/settings, and context-menu workflows take precedence over detail and leave prior inspector detail dormant rather than revealing a compact detail sheet; detail-owned poster selection and sharing dismiss when their parent detail host changes.
- Classify and adapt content-heavy sheets using semantic presentation sizes and responsive internal layouts, while retaining system alerts, confirmation dialogs, popovers, and full-screen media previews where they already fit their purpose.
- Add a resizable-window and current-iPhone regression matrix covering all library modes and modal destinations.

## Capabilities

### New Capabilities

- `adaptive-library-experience`: Content-fit-driven Gallery layout, mode- and size-class-driven on-demand detail presentation, state preservation during resizing, and exact compatibility with the current iPhone detail-sheet experience.
- `adaptive-modal-presentations`: Purpose-based sizing and responsive composition for AniShelf's content-heavy sheets and nested modal workflows.

### Modified Capabilities

None.

## Impact

- Affects the library shell, Gallery/List/Grid views, entry interaction and presentation state, entry detail composition, and library toolbars.
- Affects Search/Add Anime, poster selection, sharing, profile/settings, API configuration, Support, About, and What's New presentations.
- Requires one canonical detail presentation and session shared by distinct system sheet and inspector hosts, plus enum-driven workflow sheets.
- Requires no data-model, persistence-schema, network API, or third-party dependency changes.
- Adds layout-focused previews or UI coverage and current-iPhone regression validation.
