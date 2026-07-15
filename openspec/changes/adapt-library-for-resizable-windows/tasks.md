## 1. Baseline and Layout Policy

- [x] 1.1 Add representative current-iPhone portrait and landscape regression coverage for Gallery, List, Grid, entry detail, and entry editing before changing presentation structure
- [x] 1.2 Add a resizable preview or test harness that exercises narrow, nearly full, full-screen, very wide, and very short content areas with configurable Dynamic Type
- [x] 1.3 Prototype and name the minimum viable geometry tokens for the wide Gallery card sizing range
- [x] 1.4 Implement a device-independent `LibraryGalleryLayoutPolicy` that derives Gallery arrangements from Gallery's proposed size and accessibility requirements
- [x] 1.5 Add focused Gallery policy tests covering wide, narrow, very short, and accessibility Dynamic Type layouts

## 2. Stable Library Presentation State

- [x] 2.1 Refactor `LibraryEntryInteractionState` to distinguish focused entry, explicitly presented detail, multi-selection, and enum-driven active workflow state using stable entry identifiers
- [x] 2.2 Move presentation ownership above responsive layout branches and resolve route identifiers through the library store without retaining view instances in routes
- [x] 2.3 Consolidate mutually exclusive library workflow sheets into one route-driven host while entry detail uses one system inspector (superseded by the confirmed host policy in Section 9)
- [x] 2.4 Add interaction-state tests proving that Gallery focus does not implicitly open detail, List and Grid multi-selection remains independent, and stale presentation callbacks do not dismiss current state

## 3. Reusable Entry Detail and On-Demand Inspector

- [x] 3.1 Separate reusable entry-detail content and session state from the system inspector container and presentation generation
- [x] 3.2 Make the entry-detail hero, sections, and readable content width respond to the host proposal while keeping all current actions and information reachable
- [x] 3.3 Use the system inspector's standard compact sheet adaptation for current iPhone and other compact environments (superseded by the confirmed compact-sheet parity decision in Section 9)
- [x] 3.4 Attach one dismissible system inspector without root geometry measurement or application-owned host switching (superseded by the confirmed compact-sheet parity decision in Section 9)
- [x] 3.5 Update an open inspector when the focused entry changes and reclaim the complete library canvas when it closes
- [x] 3.6 Preserve the detail session, scroll state, and unsaved editing state while the system inspector adapts during live resizing (superseded by explicit host migration in Section 9)
- [x] 3.7 Keep a stable root navigation hierarchy, reject delayed callbacks from replaced detail generations, use regular-width single-tap activation, and tune inspector surface and hero proportions (single-tap host semantics superseded by the Gallery exception in Section 9)

## 4. Adaptive Gallery Shelf

- [x] 4.1 Preserve the existing full-width one-entry-per-page Gallery code path for all supported current on-device iPhone portrait and landscape geometries
- [x] 4.2 Implement the spacious Gallery shelf using height-informed 2:3 card widths, focused scroll targets, and partial or complete neighboring-card visibility
- [x] 4.3 Keep Gallery gestures, overlays, dates, focus state, and detail-opening behavior consistent across single-page and shelf arrangements without adding multi-selection
- [x] 4.4 Preserve the focused entry and scroll alignment while resizing between Gallery arrangements and while opening or closing the system inspector (Gallery inspector behavior superseded by Section 9)
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

- [x] 8.1 Run the targeted app tests for Gallery layout policy, interaction state, detail routing, Gallery behavior, and modal routing
- [x] 8.2 Visually compare Gallery, List, Grid, detail, editing, Search, sharing, and poster workflows against the current iPhone portrait and landscape baselines
- [ ] 8.3 Sweep narrow, nearly full, full-screen, very wide, and very short iPad scenes in every library mode with detail closed and open
- [ ] 8.4 Resize while detail, editing, sharing, poster selection, Search, and settings content are active and confirm that state is retained and no presentation is duplicated
- [x] 8.5 Run `make format`, the smallest relevant lint/build commands, and `make test-sim`, resolving all regressions before completing the change

## 9. Mode-Aware Genuine Detail Sheet Hosts

- [x] 9.1 Run a controlled same-build A/B test with unchanged `EntryDetailView` content and styling, confirming that a genuine sheet restores the exact v1.95 Liquid Glass appearance while the compact inspector host does not
- [x] 9.2 Add a library-root detail-host policy that always maps Gallery to a genuine sheet and maps List/Grid to a sheet in compact horizontal size class or an inspector in regular horizontal size class, without root geometry or idiom checks
- [x] 9.3 Keep sheet and inspector modifiers at stable hierarchy positions, present only the committed host, and defer resize-driven migration until interactive resizing ends while applying safe display-mode changes immediately
- [x] 9.4 Preserve the canonical detail route and `EntryDetailSession` across host migration, use host-generation identifiers to reject stale dismissals, and defer migration while an unsafe nested detail presentation is active
- [x] 9.5 Add focused tests proving Gallery never uses an inspector, List/Grid follow the compact/regular policy, Gallery retains user-preference activation, regular List/Grid use single-tap activation, mode changes preserve detail state, interactive migration is deferred, noninteractive migration is immediate, wide phone-hosted compact behavior remains sheet-based, the detail session stays continuous, and stale host callbacks cannot dismiss the current host
- [ ] 9.6 Re-run the same-entry visual comparison and the pending resize matrix with detail, editing, sharing, and poster workflows active, confirming v1.95 sheet parity and uncropped Gallery side posters without duplicate or lost presentations
