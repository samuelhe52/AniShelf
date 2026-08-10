# AniShelf Broadcast Time Feature Plan

Created: 2026-08-09

## Scope

Allow AniShelf to fetch and present a series' recurring broadcast time from
TVMaze when the user opens its detail view. The feature is on-demand,
setting-gated, and does not add broadcast data to the SwiftData schema.

## User Experience

- Resolve eligible entries when their detail views open. Present successful
  results in an airtime section of the existing ellipsis menu, not in the main
  detail content.
- If identifier lookup fails, offer a button asking the user to help confirm a
  match. Tapping it opens the validation sheet and starts title fallback.
- Show one hydrated candidate with enough metadata and next-airing information
  to make a decision. Remember it only after explicit user confirmation.

## Resolver Contract

The resolver exposes two operations:

1. **Automatic resolution:** derive the TMDb series ID, use a saved mapping or
   retrieve its TVDB and IMDb IDs for TVMaze lookup, then fetch the full show
   with its embedded next episode. On an ID miss, return a user-assistance
   outcome without starting title search.
2. **User-initiated title fallback:** only after the validation sheet opens,
   search for the top TVMaze ID and fetch the same full show response.

Each operation returns a hydrated show or a resolution outcome. ID discovery
and show retrieval may be separate internally but are never exposed as caller-
orchestrated stages. Title fallback does not write the TMDb-to-TVMaze mapping;
confirmation does.

## Feature Boundaries

- A narrow TMDb external-ID provider responsible only for retrieving the TVDB
  and IMDb IDs.
- A TVMaze client responsible for ID lookup, top-result title search, and full
  show retrieval with the next episode embedded.
- A resolver responsible for the two workflows above.

Clients return dedicated types containing only fields the feature uses. They do
not expose raw JSON, dictionaries, or types with a `DTO` suffix.

## Schedule Representation

- Keep the provider-local schedule and its `TimeZone` as the canonical source.
- Derive device-local weekdays and display times for presentation. Preserve
  late-night broadcast notation where useful, such as Thursday `24:30`, rather
  than presenting it as an apparently unrelated Friday slot.
- Keep the next episode's `airstamp` as a `Date`.
- Expose provider-zone `DateComponents` for future repeating notifications;
  booking those notifications remains out of scope.

## Persistence And Networking

- Persist only confirmed TMDb-to-TVMaze mappings, not schedules or TVMaze
  responses.
- The final storage location for this map remains open: UserDefaults and a small
  dedicated file are both candidates.
- Use normal URL-session HTTP caching; no custom session is currently needed.

## Implementation Outline

1. Complete the plumbing with the TMDb external-ID provider and resolver around
   the TVMaze models and client.
2. Add the confirmed-mapping store.
3. Integrate resolution, the airtime menu, the validation sheet, and settings
   with the detail-view lifecycle.
4. Add focused tests for the accepted resolution paths.

## Open Decisions

- Whether the mapping should live in UserDefaults or a dedicated file.
- The exact settings options, wording, and defaults.
- The final metadata and visual layout used by the validation sheet.
