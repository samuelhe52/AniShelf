## 1. Baseline and Layout Policy

- [x] 1.1 Add representative current-iPhone portrait and landscape regression coverage for Gallery, List, Grid, entry detail, and entry editing before changing presentation structure
- [x] 1.2 Add a resizable preview or test harness that exercises narrow, nearly full, full-screen, very wide, and very short content areas with configurable Dynamic Type
- [x] 1.3 Prototype and name the minimum viable geometry tokens for each library mode, entry detail, and modal content region, including the wide Gallery card sizing range
- [x] 1.4 Implement a device-independent `LibraryPresentationPolicy` that derives semantic detail, Gallery, and modal arrangements from content size, active mode, and accessibility requirements
- [x] 1.5 Add focused policy tests covering a nearly full iPad window with a compact axis, a large resizable phone-idiom scene, insufficient coexistence geometry, very short scenes, and accessibility Dynamic Type

## 2. Stable Library Presentation State

- [x] 2.1 Refactor `LibraryEntryInteractionState` to distinguish focused entry, explicitly presented detail, multi-selection, and enum-driven active workflow state using stable entry identifiers
- [x] 2.2 Move presentation ownership above responsive layout branches and resolve route identifiers through the library store without retaining view instances in routes
- [x] 2.3 Consolidate mutually exclusive library sheet modifiers into one route-driven presentation host while preserving every current iPhone destination, gesture, detent, transition, and dismissal safeguard
- [x] 2.4 Add interaction-state tests proving that Gallery focus does not implicitly open detail, List and Grid multi-selection remains independent, and resizing does not duplicate or dismiss an active route

## 3. Reusable Entry Detail and On-Demand Inspector

- [x] 3.1 Separate reusable entry-detail content and session state from sheet-specific drag indicators, dismissal behavior, toolbar placement, and presentation chrome
- [x] 3.2 Make the entry-detail hero, sections, and readable content width respond to the host proposal while keeping all current actions and information reachable
- [x] 3.3 Retain the existing sheet host unchanged for current iPhone and other constrained geometries
- [x] 3.4 Add a dismissible trailing inspector host that is selected only when the active library mode and detail both satisfy their minimum viable geometry
- [x] 3.5 Update an open inspector when the focused entry changes, reclaim the complete library canvas when it closes, and fall back to a sheet whenever the remaining Gallery surface would be compromised
- [x] 3.6 Preserve the detail session, scroll state, and unsaved editing state when live resizing changes the selected presentation, with tests for passive detail and active editing transitions
- [x] 3.7 Replace the manual split with the platform inspector, consume delayed host-migration dismissals, use single-tap activation in inspector-capable geometry, and tune inspector surface and hero proportions

## 4. Adaptive Gallery Shelf

- [x] 4.1 Preserve the existing full-width one-entry-per-page Gallery code path for all supported current on-device iPhone portrait and landscape geometries
- [x] 4.2 Implement the spacious Gallery shelf using height-informed 2:3 card widths, focused scroll targets, and partial or complete neighboring-card visibility
- [x] 4.3 Keep Gallery gestures, overlays, dates, focus state, and detail-opening behavior consistent across single-page and shelf arrangements without adding multi-selection
- [x] 4.4 Preserve the focused entry and scroll alignment while resizing between Gallery arrangements and while opening or closing an eligible inspector
- [x] 4.5 Add layout and interaction coverage confirming that Gallery remains a large-card horizontal focus mode and never becomes a narrow master column or small vertical grid

## 5. Content-Heavy Modal Adaptation

- [x] 5.1 Apply page-oriented spacious sizing and readable-width constraints to Search/Add Anime while preserving its current constrained sheet behavior
- [x] 5.2 Apply page-oriented sizing to poster selection, retain its adaptive grid, and preserve full-screen poster preview paging and confirmation
- [x] 5.3 Refactor Sharing to use preview-and-controls columns when viable and its current vertical composition when constrained
- [x] 5.4 Keep poster selection launched from Sharing inside the sharing navigation workflow and restore the same sharing state after selection or cancellation
- [x] 5.5 Apply semantic form or page sizing to API key configuration, Support, About, and What's New without changing the profile/settings root transition
- [x] 5.6 Preserve alerts, confirmation dialogs, anchored tips, episode previews, and full-screen media in their existing system presentation categories
- [x] 5.7 Add modal routing and resize tests proving active workflow identity, entered data, navigation position, and dismissal safeguards survive layout changes without duplicate presentation

## 6. Scene-Aware System Sharing

- [x] 6.1 Replace the `ShareSheetPresenter` device-idiom branch with anchoring derived from the active scene and presentation context
- [ ] 6.2 Verify system sharing from the library, Sharing workflow, profile export, and startup recovery in both constrained and spacious resizable scenes

## 7. Accessibility and Input Validation

- [x] 7.1 Verify library and modal layouts through accessibility Dynamic Type sizes, including automatic fallback from side-by-side to single-surface or stacked composition
- [ ] 7.2 Verify keyboard navigation, pointer scrolling and dismissal, reduced-motion transitions, and VoiceOver reachability for the Gallery shelf, inspector, and adapted modals
- [x] 7.3 Add accessibility labels or focus-order fixes required by the new inspector and shelf controls without altering current iPhone control semantics

## 8. Regression and Resize Matrix

- [x] 8.1 Run the targeted app tests for presentation policy, interaction state, detail routing, Gallery behavior, and modal routing
- [x] 8.2 Visually compare Gallery, List, Grid, detail, editing, Search, sharing, and poster workflows against the current iPhone portrait and landscape baselines
- [ ] 8.3 Sweep narrow, nearly full, full-screen, very wide, and very short iPad scenes in every library mode with detail closed and open
- [ ] 8.4 Resize while detail, editing, sharing, poster selection, Search, and settings content are active and confirm that state is retained and no presentation is duplicated
- [x] 8.5 Run `make format`, the smallest relevant lint/build commands, and `make test-sim`, resolving all regressions before completing the change
