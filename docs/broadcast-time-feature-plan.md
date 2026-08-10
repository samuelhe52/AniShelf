# AniShelf Broadcast Time Feature Plan

Created: 2026-08-09

This document records the current direction for adding TVMaze broadcast-time
information to AniShelf. It is an outline rather than a final technical design.

## Goal

Allow AniShelf to fetch and present a series' recurring broadcast time from
TVMaze when the user opens its detail view.

The feature is on-demand and setting-gated. Broadcast information will not be
added to the SwiftData schema.

## User Experience

- Start resolving broadcast information when an eligible detail view opens and
  the feature's preconditions are met.
- Keep the result out of the main detail content. Present it from the existing
  ellipsis menu.
- When AniShelf finds a direct match, show its broadcast weekday and time in a
  clearly labelled airtime section in that menu.
- When the identifier-based lookup cannot produce a match, show an action in
  the menu asking the user to validate a title-based result.
- Present title-based candidates in a sheet with enough returned metadata for
  the user to decide whether an entry is correct.
- After the user confirms a candidate, use that match for the current entry and
  remember it for later detail sessions.

Notification booking may be added later, but it is not part of this work.

## Resolution Direction

The runtime flow is:

1. Resolve the relevant TMDb series ID from the AniShelf entry.
2. Check for a previously recorded TMDb-to-TVMaze mapping.
3. If a mapping exists, use its TVMaze ID to fetch the current show and schedule
   information.
4. Otherwise, request the series' TVDB and IMDb identifiers from TMDb.
5. Use those identifiers to look for a direct TVMaze match.
6. If the identifier path does not match, make title-based candidates available
   for user validation.
7. Record a user-confirmed TMDb-to-TVMaze mapping so later detail sessions can
   skip the TMDb external-ID request.

## Feature Boundaries

The business logic should be divided into three small parts:

- A narrow TMDb external-ID provider responsible only for retrieving the TVDB
  and IMDb identifiers needed by this feature.
- A TVMaze client responsible for the limited lookup, search, and show requests
  used by the feature.
- A resolver responsible for mapping an AniShelf entry through those providers
  and returning either a match with schedule information or an outcome that
  requires user validation.

The clients must return dedicated, typed data structures. They must not expose
raw JSON or dictionary-based results. These types should have descriptive names
without a `DTO` suffix and should contain only fields the feature uses.

## Storage And Caching

- Do not persist broadcast schedules or TVMaze response data in SwiftData.
- Persist only the small mapping from a TMDb series ID to a confirmed TVMaze
  show ID.
- The final storage location for this map remains open: UserDefaults and a small
  dedicated file are both candidates.
- Use normal URL-session HTTP caching for network responses. A separately
  configured custom URL session is not required by the current direction.

## Settings

The feature will be controlled through settings. The exact set of options and
their wording still need to be finalized.

## Implementation Outline

1. Add the narrow typed models, TMDb external-ID provider, TVMaze client, and
   resolver.
2. Add the persistent TMDb-to-TVMaze mapping store.
3. Start resolution from the detail-view lifecycle when the feature is enabled
   and the entry is eligible.
4. Add the airtime section and validation action to the detail ellipsis menu.
5. Add the candidate-validation sheet and connect confirmation to the mapping
   store.
6. Add the finalized settings controls and focused tests for the accepted
   resolution paths.

## Open Decisions

- Whether the mapping should live in UserDefaults or a dedicated file.
- The exact settings options, wording, and defaults.
- The final metadata and visual layout used by the validation sheet.
- The precise presentation and formatting of broadcast weekday and time.
