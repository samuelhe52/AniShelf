## ADDED Requirements

### Requirement: Device-independent Gallery layout policy
Gallery SHALL select its arrangement from its own proposed content size and viable card geometry. It MUST NOT use device idiom, named device model, fold state, or interface orientation as the structural layout decision. Gallery entry detail SHALL always use a sheet. List and Grid entry detail SHALL use the library root's horizontal size class for discrete system-host selection instead of participating in this geometry policy.

#### Scenario: Gallery gains useful shelf space
- **WHEN** Gallery's proposed size can show a viable focused card and neighboring content
- **THEN** Gallery uses the shelf arrangement without checking device identity

#### Scenario: Gallery loses useful shelf space
- **WHEN** Gallery's proposed width or height cannot support the shelf geometry
- **THEN** Gallery returns to its single-page arrangement without changing the detail presentation route

### Requirement: Full-canvas library modes
The system SHALL give Gallery, List, and Grid the complete library canvas whenever entry detail is not presented. The system MUST NOT reserve an empty permanent detail column.

#### Scenario: Detail is closed
- **WHEN** the user closes or has not opened entry detail
- **THEN** the active library mode expands to all available library content space

#### Scenario: User changes display mode
- **WHEN** the user switches among Gallery, List, and Grid
- **THEN** the newly selected mode becomes the primary full-canvas library without being placed in a navigation sidebar

### Requirement: Adaptive Gallery shelf
The system SHALL preserve the current one-entry-per-page Gallery at current on-device iPhone sizes and SHALL reveal neighboring Gallery entries when additional usable space can display them at the required card size. Gallery MUST remain a large-card horizontal focus experience and MUST NOT become a narrow master column or gain multi-selection.

#### Scenario: Current iPhone Gallery
- **WHEN** Gallery runs at any supported current on-device iPhone portrait or landscape geometry
- **THEN** it retains the current full-width single-card paging, gestures, overlays, and detail-opening behavior

#### Scenario: Wide Gallery has surplus horizontal space
- **WHEN** Gallery can show the focused card at its viable size with horizontal space remaining
- **THEN** at least part of a neighboring entry is visible and scrolling remains aligned to a focused entry

#### Scenario: Gallery opens entry detail
- **WHEN** the user opens detail from Gallery at any size class
- **THEN** detail appears in a genuine sheet and Gallery retains its full proposed width, shelf arrangement, and neighboring posters behind the presentation

### Requirement: On-demand adaptive entry detail
The system SHALL present entry detail only after an explicit open-detail action. Gallery SHALL always use a genuine SwiftUI sheet. List and Grid SHALL use a genuine SwiftUI sheet when the library root horizontal size class is compact and a SwiftUI inspector when it is regular. The app MUST NOT use root geometry, device idiom, device model, or interface orientation to choose between these hosts.

#### Scenario: Detail opens in a spacious List or Grid
- **WHEN** the user opens an entry from List or Grid while the library root horizontal size class is regular
- **THEN** a dismissible trailing inspector appears while the library remains the primary surface

#### Scenario: Primary tap targets an entry in regular width
- **WHEN** the horizontal environment is regular and the user taps a List or Grid entry once
- **THEN** that explicit tap opens or updates the inspector regardless of the constrained-layout tap preference

#### Scenario: Compact environment opens a genuine sheet
- **WHEN** the user opens an entry from List or Grid while the library root horizontal size class is compact
- **THEN** a genuine SwiftUI sheet presents the canonical detail session with the v1.95 system surface, Liquid Glass compositing, navigation behavior, and dismissal behavior

#### Scenario: Regular Gallery still opens a genuine sheet
- **WHEN** the user opens an entry from Gallery while the library root horizontal size class is regular
- **THEN** a genuine SwiftUI sheet appears and no inspector is introduced into Gallery

#### Scenario: Wide phone-hosted environment remains compact
- **WHEN** a geometrically wide phone-hosted scene still reports a compact horizontal size class
- **THEN** entry detail remains in the genuine sheet host and the app does not infer regular presentation semantics from width

#### Scenario: Selection changes while inspector is open
- **WHEN** the user focuses another entry in List or Grid while the inspector is visible
- **THEN** the inspector updates to the newly focused entry without creating another presentation

#### Scenario: Detail host closes
- **WHEN** the user dismisses the active sheet or inspector
- **THEN** the active library mode immediately reclaims the complete library canvas

### Requirement: Separate focus and presentation state
The system SHALL distinguish the focused library entry, an explicitly presented detail entry, its transient system host, multi-selection, and an active modal workflow. Presentation routes MUST carry lightweight stable identifiers rather than view instances. The canonical detail route and session MUST remain independent from sheet and inspector host lifecycles.

#### Scenario: Gallery focus moves without opening detail
- **WHEN** the user pages to another Gallery card without invoking the open-detail gesture
- **THEN** the focused entry changes and no detail sheet or inspector is presented

#### Scenario: Multi-selection begins
- **WHEN** the user enters List or Grid multi-selection
- **THEN** focused-entry state does not replace or corrupt the set of selected entry identifiers

### Requirement: Non-destructive live resizing
The system SHALL preserve display mode, focused entry, scroll position, multi-selection, presented destination, and active workflow state while the scene resizes. Resizing MUST NOT dismiss or reset unsaved work.

#### Scenario: Interactive resize crosses the host boundary
- **WHEN** the library root horizontal size class changes while the scene is being interactively resized and detail is presented
- **THEN** the system records the desired host, keeps the current host stable during the gesture, and migrates once interactive resizing ends

#### Scenario: Noninteractive trait change crosses the host boundary
- **WHEN** the library root horizontal size class changes outside an interactive resize and detail is presented
- **THEN** the system migrates to the matching host without losing the selected entry or detail session state

#### Scenario: Display mode changes with detail presented
- **WHEN** the active mode changes between Gallery and List or Grid while detail remains presented
- **THEN** the system migrates to the host required by the new mode and root size class without losing the selected entry or detail session state

#### Scenario: Outgoing host finishes a delayed dismissal
- **WHEN** an outgoing sheet or inspector reports dismissal after another host generation has been committed
- **THEN** the callback is rejected without clearing the canonical detail route or dismissing the incoming host

#### Scenario: Nested detail workflow is active during migration
- **WHEN** a host change is requested while detail owns a nested presentation that cannot be safely rehosted
- **THEN** the canonical detail and nested workflow state remain intact and host migration waits until the unsafe transition has ended

#### Scenario: Editing during resize
- **WHEN** the scene resizes while entry edits are unsaved
- **THEN** the editing session remains presented with its changes and dismissal safeguards intact

#### Scenario: Library resizes with no detail open
- **WHEN** the scene crosses a layout boundary while the user is browsing
- **THEN** the focused entry and scroll position remain stable and no modal appears solely because of resizing

### Requirement: Current iPhone experience compatibility
At all supported current on-device iPhone portrait and landscape sizes, the system SHALL preserve the existing library composition and detail-opening semantics while using a genuine system sheet for entry detail.

#### Scenario: Current iPhone uses any library mode
- **WHEN** Gallery, List, or Grid is used on a current on-device iPhone geometry
- **THEN** its composition, toolbars, gestures, transitions, and selection behavior match the pre-change experience

#### Scenario: Current iPhone opens detail or edit
- **WHEN** the user opens entry detail or editing on a current on-device iPhone geometry
- **THEN** the genuine sheet matches the v1.95 page tint and Liquid Glass card depth while preserving navigation, session state, editing, and dismissal safeguards

### Requirement: Adaptive accessibility capacity
The Gallery layout policy SHALL account for Dynamic Type and accessibility requirements when deciding whether the shelf remains viable.

#### Scenario: Larger text makes the shelf unusable
- **WHEN** the current accessibility configuration causes Gallery cards or chrome to exceed the shelf's viable content size
- **THEN** Gallery uses the single-page arrangement without truncating essential controls
