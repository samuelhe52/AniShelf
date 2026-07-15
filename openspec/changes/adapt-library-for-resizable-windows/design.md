## Context

AniShelf currently renders Gallery, List, and Grid inside one `NavigationStack`. Each mode owns entry-interaction sheet modifiers, and opening an entry stores an `AnimeEntry` in `LibraryEntryInteractionState.detailingEntry`, which directly drives a detail sheet. Gallery is a full-width horizontal pager, List uses the entire width for rich rows, and Grid grows an adaptive poster collection.

This structure preserves a strong phone experience but does not distinguish between a phone-sized scene, a nearly full iPad window, a narrow floating window, or the freely resizable iPhone-app environments introduced with iOS 27. A permanent master-detail conversion would create a different problem: it would reduce the useful width of all three library modes and turn Gallery's one-at-a-time focus experience into an inefficient master column.

The current App Store assets establish the intended product identity:

- Gallery is an immersive, artwork-first focus mode.
- List uses wide rows to expose synopsis and status information.
- Grid is the high-density scanning mode.
- Entry detail is currently an on-demand presentation over the library.

The implementation must preserve the current on-device iPhone experience exactly while allowing any sufficiently useful scene, regardless of idiom, to adopt richer composition.

## Goals / Non-Goals

**Goals:**

- Keep the library as the primary full-canvas surface in all three display modes.
- Always present Gallery entry detail in a genuine system sheet; in List and Grid, use a genuine sheet in horizontally compact environments and a system inspector in horizontally regular environments.
- Make Gallery more browsable in wide scenes without turning it into Grid or a narrow master column.
- Adapt content-heavy sheets by task type and available content area.
- Preserve state and active work through live scene resizing.
- Guarantee no visible or behavioral regression at current on-device iPhone sizes in portrait or landscape.
- Avoid device-idiom, device-model, and interface-orientation layout decisions.

**Non-Goals:**

- Adding a permanent app-navigation sidebar or a permanently visible detail column.
- Redesigning AniShelf around tabs or introducing new top-level destinations.
- Changing persisted library data, SwiftData schemas, sync behavior, or network APIs.
- Combining Library search and TMDb search into a new information architecture in this change.
- Adding multi-selection to Gallery.
- Predicting or special-casing foldable hardware, display hinges, or named future devices.
- Redesigning the visual language of entry cards, detail cards, or settings beyond changes required for responsive composition.

## Decisions

### 1. Use a full-canvas library with mode- and size-class-driven detail hosts

Gallery, List, and Grid continue to own the complete library canvas whenever entry detail is closed. Gallery always opens detail in a genuine SwiftUI sheet, regardless of size class, so presenting detail never narrows or occludes the neighboring shelf posters. List and Grid use a genuine sheet when the library root's horizontal size class is compact and a trailing SwiftUI inspector when it is regular. Both hosts render the same canonical detail presentation and `EntryDetailSession`.

A controlled A/B test on the same build replaced the compact inspector host with a plain sheet while leaving `EntryDetailView` and all app-owned styling unchanged. The genuine sheet restored the exact v1.95 Liquid Glass tint and card depth; the inspector's compact adaptation remained flatter and more opaque. Compact visual parity therefore requires the genuine sheet host rather than app-side material approximation.

The detail surface is never an always-visible empty column. Closing it restores the full library canvas. While an inspector is open in List or Grid, focusing another entry updates the inspector. Gallery remains the primary surface rather than becoming a sidebar.

The app reads `horizontalSizeClass` once at the library root instead of measuring window geometry or treating size class as a continuous width sensor. In horizontally regular List and Grid, a primary tap opens or updates the inspector immediately. Gallery and compact List/Grid continue to honor the user's existing single- versus double-tap preference and use the genuine sheet even when a phone-hosted scene becomes geometrically wide.

Sheet-versus-inspector is a discrete presentation-semantic decision derived from the active library mode and, for List/Grid, the root horizontal size class. During interactive resize, the app records the desired host and defers committing a host migration until resizing ends. Noninteractive size-class or display-mode changes commit immediately when safe. The host decision does not depend on the width remaining after an inspector opens, avoiding a presentation feedback loop.

This uses inspector semantics rather than master-detail navigation semantics: detail supplements selected library content and is dismissible. A permanent `NavigationSplitView` was rejected because its collapsed navigation behavior would change the current iPhone sheet interaction and because its leading column would constrain all three browsing modes even when detail is closed.

### 2. Choose the Gallery arrangement from content fit, not device identity

A Gallery-local `LibraryGalleryLayoutPolicy` evaluates Gallery's proposed size and Dynamic Type requirements. It does not participate in detail presentation and does not invalidate the root library hierarchy during continuous resizing.

The policy exposes one semantic result: `galleryArrangement`, which is either single-page or shelf.

Minimum sizes are Gallery design tokens derived from poster geometry and visible chrome, not device-width breakpoints. Gallery detail always uses a sheet; List/Grid detail selection remains an independent root size-class policy.

The first implementation will validate and tune these tokens using resizable previews/simulators and the regression matrix rather than embedding device names or idiom checks.

### 3. Adapt Gallery as a height-informed horizontal shelf

The compact Gallery remains byte-for-byte equivalent in interaction and visually equivalent in layout to the current one-entry-per-page carousel.

When the scene can display additional horizontal content, Gallery stops forcing every wrapper to the full container width. Card width is derived from the usable height and the poster's 2:3 aspect ratio, subject to readable minimum and maximum sizes. The focused card remains dominant and aligned to a scroll target while neighboring cards are partially or fully visible.

The shelf preserves the difference between modes:

- Gallery: large cards, horizontal movement, focused artwork, dates and poster overlays.
- Grid: small cards, vertical movement, many entries visible simultaneously.
- List: rich textual rows, vertical movement, synopsis and status scanning.

The shelf does not gain Gallery multi-selection and does not become a detail master column. Gallery never presents entry detail in an inspector, so opening detail cannot reduce the shelf's proposed width or cut off neighboring posters.

### 4. Separate focused selection, detail presentation, and active workflows

The current `detailingEntry` state conflates selection with presentation. A scene-owned observation model will instead track lightweight identifiers and mutually exclusive presentation destinations:

- `focusedEntryID`: the entry currently focused by Gallery, List, or Grid.
- `presentedDetailEntryID`: an explicitly opened detail presentation.
- `activeWorkflow`: poster selection, sharing, Search/Add, or another explicit modal task.
- Existing multi-selection IDs, scroll state, highlight state, and display mode.

Views resolve identifiers through `LibraryStore` rather than storing heavy views or long-lived presentation models in route values. Entry editing is requested within the canonical detail presentation, while mutually exclusive workflow sheets use enum-driven state.

Presentation state is owned above Gallery's responsive layout branch so changing scene geometry does not reset selection or dismiss work. A canonical detail route and session remain stable while transient host presentations migrate between sheet and inspector. Active editing and modal workflows retain their identity, model state, and unsaved-change protection.

### 5. Separate entry-detail content from presentation chrome

`EntryDetailView` keeps reusable content and session state independent from both presentation containers. The same detail session survives sheet-to-inspector and inspector-to-sheet migration without duplicating business logic.

The sheet preserves the v1.95 system presentation surface and Liquid Glass compositing. The inspector uses a coherent system column surface. In either host, hero height is derived from the proposed width and dense statistic regions reduce their column count before their content becomes cramped.

Both host modifiers remain attached at stable positions in the library hierarchy, but only the committed host is presented. Host-generation identifiers ensure a delayed dismissal callback from the outgoing sheet or inspector cannot clear the canonical detail route or the incoming host. Host migration is also deferred while a nested detail workflow cannot be safely rehosted.

If the complete episode, character, and staff experience proves unsuitable at the minimum inspector width during the visual spike, the inspector may use a condensed summary followed by an “Open Full Details” action. This is an implementation fallback, not the default contract; the first prototype uses the complete detail content.

### 6. Classify modal presentations by purpose

Presentation type is selected by task semantics and then adapted to available space:

| Destination | Spacious presentation | Constrained presentation | Internal adaptation |
| --- | --- | --- | --- |
| Entry detail/edit in List/Grid | System inspector column | Genuine system sheet | Shared session, adaptive hero, and readable content width |
| Entry detail/edit in Gallery | Genuine system sheet | Genuine system sheet | Preserve the full-width shelf and neighboring posters |
| Search/Add Anime | Page-sized sheet | Existing full-width sheet | Preserve current search modes and behavior |
| Poster selection | Page-sized sheet | Existing sheet | Existing adaptive poster grid |
| Poster preview | Full-screen cover | Full-screen cover | Preserve media-focused paging |
| Sharing | Page-sized sheet | Existing sheet | Preview/control columns when viable, vertical stack otherwise |
| Change API key | Form-sized sheet | Existing sheet | Single readable form column |
| Support | Page-sized sheet | Existing sheet | Centered readable content |
| About | Form-sized sheet | Existing sheet | Content-fitted readable column |
| What's New | Page-sized sheet | Existing sheet | Centered readable content |
| Info tips and episode previews | Popover | Existing compact adaptation | Preserve anchored context |
| Alerts and confirmations | System alert/dialog | System alert/dialog | No custom layout |

`presentationSizing(.page)` and `.form` express spacious intent. Existing phone detents, drag indicators, dismissal rules, and full-screen media behavior remain unchanged. Nested substeps, such as poster selection from Sharing, prefer navigation within the owning modal workflow instead of stacking unrelated modal containers.

The profile/settings root transition is not converted to a new sheet in this change. Its nested API key, Support, About, and What's New destinations receive adaptive presentation sizing.

### 7. Treat current iPhone behavior as a compatibility contract

At all current on-device iPhone portrait and landscape geometries, the implementation preserves:

- One full-canvas library mode at a time.
- Existing Gallery one-card paging.
- Existing List and Grid composition.
- Existing single/double-tap detail preference.
- Existing bottom and top toolbar placement.
- Existing genuine detail/edit sheet appearance, Liquid Glass compositing, interaction semantics, and dismissal safeguards.
- Existing sheet and full-screen workflows for Search, sharing, and poster selection.

This guarantee is enforced with regression scenarios, not `userInterfaceIdiom == .phone`. A resizable iPhone-app scene uses a sheet in Gallery and the root size class's detail host in List/Grid, alongside Gallery's content-fit sizing rules. If the phone-hosted trait environment remains compact at a wide geometry, entry detail intentionally remains a sheet in every mode.

The existing idiom check in `ShareSheetPresenter` will be replaced with presentation-context anchoring that works in any idiom and scene size.

### 8. Validate the continuum rather than a device list

Validation includes current iPhones for compatibility and a continuous resize sweep for adaptivity. Representative checks cover:

- Every Gallery/List/Grid mode with detail closed and open.
- Current iPhone portrait and landscape sizes.
- Narrow, nearly full, and full-screen iPad windows.
- Very wide and very short windows.
- Resizing while detail, editing, sharing, poster selection, Search, or settings content is presented.
- Same-entry screenshot comparison between the compact genuine sheet and the v1.95 sheet baseline.
- Dynamic Type through accessibility sizes, reduced motion, pointer input, and keyboard navigation.

Screenshots and previews assert layout invariants at representative sizes, while behavioral tests assert state preservation and route selection.

## Risks / Trade-offs

- **[Risk] Content-derived thresholds still feel like arbitrary breakpoints.** → Define them as named minimum widths/heights owned by the relevant surfaces, validate them visually across a resize sweep, and avoid device-specific values.
- **[Risk] A full `EntryDetailView` is too dense for an inspector.** → Adapt hero/content composition first; fall back to a condensed inspector with an explicit full-detail action only if the prototype proves necessary.
- **[Risk] Host migration resets editing, scroll state, or nested presentation state.** → Keep the canonical detail route and `EntryDetailSession` above both hosts, defer migration until interactive resize and unsafe nested presentation transitions end, and test resizing during active work.
- **[Risk] An outgoing host reports dismissal after the incoming host appears.** → Give each transient host presentation a generation identifier and reject stale callbacks without clearing canonical detail state.
- **[Risk] Gallery shelf becomes visually indistinguishable from Grid.** → Preserve large card scale, horizontal paging, focus alignment, dates, and poster overlays; never use the small vertical grid composition.
- **[Risk] Centralizing sheets causes subtle iPhone regressions.** → Land state-routing refactors separately from visual adaptations and gate progress on the current-iPhone regression matrix.
- **[Decision] Gallery detail never uses an inspector.** → Preserve the full shelf width and neighboring posters by presenting Gallery detail in a genuine sheet at every size class.
- **[Trade-off] Modes do not share one identical wide-window structure.** → Accept the difference because Gallery is a focus mode while List and Grid are scanning modes; shared state and presentation policy maintain consistency.

## Migration Plan

1. Add regression coverage for the current iPhone library and detail workflows before structural refactoring.
2. Introduce scene-owned focus, canonical detail presentation, and enum-driven workflow state.
3. Extract reusable entry-detail content and session state shared by sheet and inspector hosts.
4. Attach stable genuine-sheet and inspector hosts, always select the sheet for Gallery, select the List/Grid host from the library root horizontal size class, and preserve the canonical session through deferred host migration.
5. Add the wide Gallery shelf while leaving the compact Gallery implementation unchanged.
6. Apply semantic sizing and internal responsive composition to content-heavy modal destinations in small groups.
7. Replace the share presenter idiom check with scene/presentation-context behavior.
8. Run the complete resize and current-iPhone validation matrix before removing transitional code.

Each step is independently reversible. Data rollback and schema migration are not required because the change affects presentation state only.

## Open Questions

- At the minimum inspector width, does the complete entry-detail document remain usable, or is a condensed inspector plus “Open Full Details” necessary?
- Should wide Gallery show one focused card with neighboring peeks or multiple complete cards? The specification requires neighboring visibility but leaves the exact amount to visual tuning.
