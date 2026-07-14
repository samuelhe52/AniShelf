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
- Present entry detail beside the library only on demand and only when both surfaces satisfy mode-specific minimum viable geometry.
- Preserve the existing detail sheet path when simultaneous library and detail surfaces do not fit.
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

### 1. Use a full-canvas library with an on-demand detail inspector

Gallery, List, and Grid continue to own the complete library canvas whenever entry detail is closed. Opening detail chooses one of two renderings of the same presentation intent:

- A trailing inspector when the active library mode and detail surface can coexist usefully.
- The existing sheet experience when they cannot.

The detail surface is never an always-visible empty column. Closing it restores the full library canvas. While an inspector is open in List or Grid, focusing another entry updates the inspector. Gallery remains the primary surface rather than becoming a sidebar.

The spacious composition uses SwiftUI's platform inspector host instead of a manually divided and independently animated `HStack`. In inspector-capable geometry, a primary tap is the explicit open-detail action and opens or updates the inspector immediately. Constrained geometry continues to honor the user's existing single- versus double-tap preference exactly.

This uses inspector semantics rather than master-detail navigation semantics: detail supplements selected library content and is dismissible. A permanent `NavigationSplitView` was rejected because its collapsed navigation behavior would change the current iPhone sheet interaction and because its leading column would constrain all three browsing modes even when detail is closed.

### 2. Choose presentation from content fit, not device identity

A centralized `LibraryPresentationPolicy` evaluates the scene's available content size, the active library mode, Dynamic Type requirements, and the minimum viable size of the detail surface. Size classes may inform the policy but SHALL NOT map directly to named product modes such as “phone” or “iPad.” In particular, one compact axis SHALL NOT automatically force the legacy layout.

The policy exposes semantic results such as:

- `detailPresentation`: sheet or inspector.
- `galleryArrangement`: single-page or shelf.
- `modalSizing`: automatic, form, or page.

Minimum sizes are design tokens derived from the actual content surfaces, not device-width breakpoints. Gallery may require more retained library width than List or Grid. A minimum usable height prevents a current landscape iPhone from receiving a compromised two-surface layout, while a nearly full but vertically constrained iPad window can still qualify when its actual geometry is sufficient.

The first implementation will validate and tune these tokens using resizable previews/simulators and the regression matrix rather than embedding device names or idiom checks.

### 3. Adapt Gallery as a height-informed horizontal shelf

The compact Gallery remains byte-for-byte equivalent in interaction and visually equivalent in layout to the current one-entry-per-page carousel.

When the scene can display additional horizontal content, Gallery stops forcing every wrapper to the full container width. Card width is derived from the usable height and the poster's 2:3 aspect ratio, subject to readable minimum and maximum sizes. The focused card remains dominant and aligned to a scroll target while neighboring cards are partially or fully visible.

The shelf preserves the difference between modes:

- Gallery: large cards, horizontal movement, focused artwork, dates and poster overlays.
- Grid: small cards, vertical movement, many entries visible simultaneously.
- List: rich textual rows, vertical movement, synopsis and status scanning.

The shelf does not gain Gallery multi-selection and does not become a detail master column. When the detail inspector opens, the shelf recomputes within the remaining primary width; if that would make the primary surface unusable, the policy selects a sheet instead.

### 4. Separate focused selection, detail presentation, and active workflows

The current `detailingEntry` state conflates selection with presentation. A scene-owned observation model will instead track lightweight identifiers and mutually exclusive presentation destinations:

- `focusedEntryID`: the entry currently focused by Gallery, List, or Grid.
- `presentedDetailEntryID`: an explicitly opened detail presentation.
- `activeWorkflow`: edit, poster selection, sharing, Search/Add, or other modal task.
- Existing multi-selection IDs, scroll state, highlight state, and display mode.

Views resolve identifiers through `LibraryStore` rather than storing heavy views or long-lived presentation models in route values. Mutually exclusive sheet destinations use one enum-driven route instead of multiple optional entries and stacked sheet modifiers.

Presentation state is owned above the responsive layout branch so changing scene geometry does not reset selection or dismiss work. Passive detail may adapt between inspector and sheet as capacity changes. An active editing or modal workflow retains its identity, model state, and unsaved-change protection throughout the transition.

### 5. Separate entry-detail content from presentation chrome

`EntryDetailView` currently assumes sheet-specific behavior such as a drag indicator and a fixed 420-point hero. Its reusable content will be separated from its host presentation so the same detail experience can render in a sheet or inspector without duplicating business logic.

The sheet host retains current phone dismissal behavior. The inspector host owns inspector-specific dismissal and toolbar placement. Entry-detail content adapts its hero height and readable content width to the proposed container while preserving all current sections and actions.

The inspector uses a coherent system surface rather than carrying the sheet-only grouped background beside the library. Its hero height is derived from the proposed inspector width, and dense statistic regions reduce their column count before their content becomes cramped. The canonical detail route remains independent of either host's asynchronous dismissal lifecycle so a completed host migration cannot close the newly presented destination.

If the complete episode, character, and staff experience proves unsuitable at the minimum inspector width during the visual spike, the inspector may use a condensed summary followed by an “Open Full Details” action. This is an implementation fallback, not the default contract; the first prototype uses the complete detail content.

### 6. Classify modal presentations by purpose

Presentation type is selected by task semantics and then adapted to available space:

| Destination | Spacious presentation | Constrained presentation | Internal adaptation |
| --- | --- | --- | --- |
| Entry detail/edit | On-demand inspector when viable | Existing sheet | Adaptive hero and readable content width |
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
- Existing detail/edit sheet presentation, detents, drag behavior, transitions, and dismissal safeguards.
- Existing sheet and full-screen workflows for Search, sharing, and poster selection.

This guarantee is enforced with regression scenarios, not `userInterfaceIdiom == .phone`. A large resizable iPhone-app scene may use the richer inspector or Gallery shelf whenever its content area satisfies the same policy as any other scene.

The existing idiom check in `ShareSheetPresenter` will be replaced with presentation-context anchoring that works in any idiom and scene size.

### 8. Validate the continuum rather than a device list

Validation includes current iPhones for compatibility and a continuous resize sweep for adaptivity. Representative checks cover:

- Every Gallery/List/Grid mode with detail closed and open.
- Current iPhone portrait and landscape sizes.
- Narrow, nearly full, and full-screen iPad windows.
- Very wide and very short windows.
- Resizing while detail, editing, sharing, poster selection, Search, or settings content is presented.
- Dynamic Type through accessibility sizes, reduced motion, pointer input, and keyboard navigation.

Screenshots and previews assert layout invariants at representative sizes, while behavioral tests assert state preservation and route selection.

## Risks / Trade-offs

- **[Risk] Content-derived thresholds still feel like arbitrary breakpoints.** → Define them as named minimum widths/heights owned by the relevant surfaces, validate them visually across a resize sweep, and avoid device-specific values.
- **[Risk] A full `EntryDetailView` is too dense for an inspector.** → Adapt hero/content composition first; fall back to a condensed inspector with an explicit full-detail action only if the prototype proves necessary.
- **[Risk] Switching between inspector and sheet resets editing or scroll state.** → Own detail session and presentation state above the responsive branch and test resizing during active work.
- **[Risk] Gallery shelf becomes visually indistinguishable from Grid.** → Preserve large card scale, horizontal paging, focus alignment, dates, and poster overlays; never use the small vertical grid composition.
- **[Risk] Centralizing sheets causes subtle iPhone regressions.** → Land state-routing refactors separately from visual adaptations and gate progress on the current-iPhone regression matrix.
- **[Risk] Inspector reduces Gallery to one card while open.** → Treat the inspector as dismissible, on-demand supplementation; use a sheet whenever remaining Gallery width falls below its minimum viable surface.
- **[Trade-off] Modes do not share one identical wide-window structure.** → Accept the difference because Gallery is a focus mode while List and Grid are scanning modes; shared state and presentation policy maintain consistency.

## Migration Plan

1. Add regression coverage for the current iPhone library and detail workflows before structural refactoring.
2. Introduce scene-owned focus and enum-driven presentation state while preserving the current sheet outputs.
3. Extract presentation-neutral entry-detail content and retain the current phone sheet host.
4. Add the content-fit policy and on-demand inspector behind the existing detail action.
5. Add the wide Gallery shelf while leaving the compact Gallery implementation unchanged.
6. Apply semantic sizing and internal responsive composition to content-heavy modal destinations in small groups.
7. Replace the share presenter idiom check with scene/presentation-context behavior.
8. Run the complete resize and current-iPhone validation matrix before removing transitional code.

Each step is independently reversible. Data rollback and schema migration are not required because the change affects presentation state only.

## Open Questions

- What exact named minimum geometry tokens produce the best transition for Gallery, List, Grid, and full entry detail? Resolve with a resizable visual spike before enabling inspector presentation.
- At the minimum inspector width, does the complete entry-detail document remain usable, or is a condensed inspector plus “Open Full Details” necessary?
- Should wide Gallery show one focused card with neighboring peeks or multiple complete cards? The specification requires neighboring visibility but leaves the exact amount to visual tuning.
