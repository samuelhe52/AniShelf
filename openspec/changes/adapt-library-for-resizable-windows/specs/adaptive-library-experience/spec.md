## ADDED Requirements

### Requirement: Device-independent layout policy
The system SHALL select the library and detail composition from the available content area and the minimum viable geometry of the active library mode. The system MUST NOT use device idiom, named device model, fold state, or interface orientation as the structural layout decision.

#### Scenario: Nearly full iPad window has useful coexistence space
- **WHEN** a window has enough usable width and height for the active library mode and entry detail to coexist
- **THEN** the system offers entry detail beside the full-canvas library even if a size-class axis is compact

#### Scenario: Resizable phone app gains a large scene
- **WHEN** a phone-idiom app runs in a scene that satisfies the same coexistence requirements
- **THEN** the system offers the same spacious composition without checking the phone idiom

#### Scenario: Available geometry cannot support both surfaces
- **WHEN** either the library mode or detail would fall below its minimum viable geometry
- **THEN** the system retains the single-canvas library and uses the constrained detail presentation

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

#### Scenario: Inspector would compromise Gallery
- **WHEN** opening detail beside Gallery would reduce Gallery below its minimum viable width or height
- **THEN** detail uses the sheet presentation and Gallery does not become a narrow sidebar

### Requirement: On-demand adaptive entry detail
The system SHALL present entry detail only after an explicit open-detail action. It SHALL use a trailing inspector when detail and the active library mode can coexist usefully, and SHALL otherwise use the existing sheet experience.

#### Scenario: Detail opens in a spacious List or Grid
- **WHEN** the user opens an entry and the active mode plus detail satisfy coexistence requirements
- **THEN** a dismissible trailing inspector appears while the library remains the primary surface

#### Scenario: Primary tap targets an inspector-capable entry
- **WHEN** the available geometry selects the trailing inspector presentation and the user taps an entry once
- **THEN** that explicit tap opens or updates the inspector regardless of the constrained-layout tap preference

#### Scenario: Detail opens without coexistence capacity
- **WHEN** the user opens an entry and coexistence requirements are not satisfied
- **THEN** the current detail sheet presentation appears

#### Scenario: Selection changes while inspector is open
- **WHEN** the user focuses another entry in List, Grid, or Gallery while the inspector is visible
- **THEN** the inspector updates to the newly focused entry without creating another presentation

#### Scenario: Inspector closes
- **WHEN** the user dismisses the inspector
- **THEN** the active library mode immediately reclaims the complete library canvas

### Requirement: Separate focus and presentation state
The system SHALL distinguish the focused library entry, an explicitly presented detail entry, multi-selection, and an active modal workflow. Presentation routes MUST carry lightweight stable identifiers rather than view instances.

#### Scenario: Gallery focus moves without opening detail
- **WHEN** the user pages to another Gallery card without invoking the open-detail gesture
- **THEN** the focused entry changes and no detail sheet or inspector is presented

#### Scenario: Multi-selection begins
- **WHEN** the user enters List or Grid multi-selection
- **THEN** focused-entry state does not replace or corrupt the set of selected entry identifiers

### Requirement: Non-destructive live resizing
The system SHALL preserve display mode, focused entry, scroll position, multi-selection, presented destination, and active workflow state while the scene resizes. Resizing MUST NOT dismiss or reset unsaved work.

#### Scenario: Passive detail crosses the layout boundary
- **WHEN** the scene resizes between inspector-capable and sheet-only geometry while passive detail is presented
- **THEN** the presentation adapts without losing the selected entry or detail session state

#### Scenario: Outgoing host finishes dismissal after migration
- **WHEN** the previous sheet or inspector reports its asynchronous dismissal after detail has migrated to the other host
- **THEN** the system consumes that host dismissal without clearing the canonical detail route

#### Scenario: Editing during resize
- **WHEN** the scene resizes while entry edits are unsaved
- **THEN** the editing session remains presented with its changes and dismissal safeguards intact

#### Scenario: Library resizes with no detail open
- **WHEN** the scene crosses a layout boundary while the user is browsing
- **THEN** the focused entry and scroll position remain stable and no modal appears solely because of resizing

### Requirement: Current iPhone experience compatibility
At all supported current on-device iPhone portrait and landscape sizes, the system SHALL preserve the existing library and detail experience without visible or behavioral changes.

#### Scenario: Current iPhone uses any library mode
- **WHEN** Gallery, List, or Grid is used on a current on-device iPhone geometry
- **THEN** its composition, toolbars, gestures, transitions, and selection behavior match the pre-change experience

#### Scenario: Current iPhone opens detail or edit
- **WHEN** the user opens entry detail or editing on a current on-device iPhone geometry
- **THEN** the current sheet, detent, drag, navigation, and dismissal behavior is preserved

### Requirement: Adaptive accessibility capacity
The layout policy SHALL account for Dynamic Type and accessibility requirements when deciding whether surfaces can coexist.

#### Scenario: Larger text makes coexistence unusable
- **WHEN** the current accessibility configuration causes the library or detail surface to fall below its viable content size
- **THEN** the system selects the single-canvas library and constrained detail presentation without truncating essential controls
