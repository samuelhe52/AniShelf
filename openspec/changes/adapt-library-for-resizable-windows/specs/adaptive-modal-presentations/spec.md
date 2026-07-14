## ADDED Requirements

### Requirement: Purpose-based presentation sizing
The system SHALL classify content-heavy presentations by task purpose and apply semantic spacious sizing while preserving the current constrained presentation behavior.

#### Scenario: Page-oriented workflow in a spacious scene
- **WHEN** Search/Add Anime, poster selection, sharing, Support, or What's New is presented with sufficient space
- **THEN** the workflow uses page-appropriate presentation sizing and a readable internal content width

#### Scenario: Form-oriented workflow in a spacious scene
- **WHEN** API key configuration or About is presented with sufficient space
- **THEN** the workflow uses form-appropriate or content-fitted sizing rather than an arbitrary fractional height

#### Scenario: Content-heavy workflow in a constrained scene
- **WHEN** the same destination is presented without spacious capacity
- **THEN** its existing phone sheet behavior, controls, and dismissal semantics are preserved

### Requirement: Responsive entry detail composition
Entry-detail content SHALL render within both sheet and inspector hosts without duplicating its data-loading or editing behavior. Its hero and readable content region SHALL adapt to the host's proposed size.

#### Scenario: Entry detail appears in an inspector
- **WHEN** entry detail is hosted in the trailing inspector
- **THEN** all required entry actions and information remain reachable without horizontal clipping, the inspector uses a coherent surface with the library, and its hero proportions respond to the inspector width

#### Scenario: Entry detail appears in the current phone sheet
- **WHEN** entry detail is hosted in the constrained sheet
- **THEN** its current visual structure, navigation behavior, drag indicator, and unsaved-change protection are preserved

### Requirement: Responsive sharing composition
The sharing workflow SHALL arrange preview and controls side by side when both regions fit and SHALL use the current vertical composition otherwise.

#### Scenario: Sharing has sufficient horizontal space
- **WHEN** the preview and controls both meet their minimum viable widths in the presented page
- **THEN** the preview and controls appear in adjacent regions with the share action remaining accessible

#### Scenario: Sharing is constrained
- **WHEN** the preview and controls cannot coexist at viable widths
- **THEN** they appear in the current vertical order without changing sharing behavior

### Requirement: Poster workflow adaptation
Poster selection SHALL use available page width for its existing adaptive grid, while the full-resolution poster preview SHALL remain a full-screen media experience.

#### Scenario: Poster selection opens in a spacious scene
- **WHEN** the user opens poster selection with page-sized capacity
- **THEN** the grid adds columns according to available width without stretching posters beyond their viable size

#### Scenario: Poster preview opens
- **WHEN** the user opens an individual poster preview
- **THEN** the preview remains full screen with paging and selection confirmation intact

### Requirement: Nested workflow containment
A substep belonging to an active modal workflow SHALL use that workflow's navigation context when practical instead of layering an unrelated full-screen or sheet presentation.

#### Scenario: Change poster from Sharing
- **WHEN** the user chooses Change Poster inside the sharing workflow
- **THEN** poster selection remains within the sharing navigation workflow and returns to the same sharing state after selection or cancellation

### Requirement: Preserve contextual system presentations
Alerts, confirmation dialogs, small anchored tips, episode previews, and full-screen media previews SHALL retain their current system presentation category unless their content purpose changes.

#### Scenario: Contextual tip opens
- **WHEN** a user opens an info tip or episode preview in a spacious scene
- **THEN** it remains anchored to its source rather than becoming a page-sized modal

#### Scenario: Confirmation is required
- **WHEN** a destructive or state-confirming action requires confirmation
- **THEN** the system alert or confirmation dialog remains the presentation mechanism

### Requirement: Stable modal routing
Mutually exclusive modal destinations SHALL be represented by enum-driven presentation state owned above responsive layout branches. A resize MUST NOT create duplicate or stacked copies of the same workflow.

#### Scenario: Window resizes with a modal open
- **WHEN** an active content-heavy modal remains presented while the scene changes size
- **THEN** the same destination and workflow state adapt in place without dismissal or duplicate presentation

#### Scenario: Modal is replaced intentionally
- **WHEN** the user completes or dismisses one modal workflow and explicitly opens another
- **THEN** exactly one destination is presented by the owning route state

### Requirement: Idiom-independent share presentation
System sharing SHALL anchor and present from the active scene and presentation context without relying on the device user-interface idiom.

#### Scenario: Sharing runs in a resized phone-idiom scene
- **WHEN** the activity controller is presented from a phone-idiom app in a large or resizable scene
- **THEN** it receives valid presentation anchoring and does not assume phone-only presentation behavior

### Requirement: Modal accessibility and input support
Adaptive modal content SHALL remain usable with accessibility Dynamic Type, keyboard navigation, pointer input, and reduced motion.

#### Scenario: Accessibility text enlarges modal content
- **WHEN** an accessibility Dynamic Type size makes a side-by-side internal layout unsuitable
- **THEN** the modal reflows to a readable stacked layout with all actions reachable

#### Scenario: Pointer dismisses a system presentation
- **WHEN** a user interacts with a sheet or inspector through iPhone Mirroring or an iPad pointing device
- **THEN** standard system scrolling and dismissal behavior remains available
