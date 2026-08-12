# AniShelf Broadcast Time Feature Plan

Created: 2026-08-09
Updated: 2026-08-12

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

The feature uses one Boolean setting and is off by default. Enabling it affects
new and currently presented eligible details without changing library data.

## Eligibility

Eligibility uses two gates so AniShelf does not mistake a broad TMDb production
state for an active broadcast and does not waste TVMaze requests:

1. Persisted raw TMDb status is only a preliminary gate. `Returning Series`,
   `Planned`, and `In Production` may proceed; movies, missing or unrecognized
   statuses, `Ended`, `Canceled`, and `Pilot` stop locally.
2. AniShelf then fetches current TMDb series details and applies the
   authoritative scheduling predicate below. TVMaze resolution starts only
   after this live check passes.

A series passes the live check when its `nextEpisodeToAir.airDate` is today or
later, or its `firstAirDate` is today or later. A season passes when that next
episode belongs to the entry's season and airs today or later, or the matching
TMDb season summary has an `airDate` today or later. Dates use the device's
current calendar day. Keep TMDb date-only values as year/month/day components
so time-zone conversion cannot shift them to another day. A missing next episode
is not evidence of eligibility.

TMDb IDs do not participate in eligibility because every stored entry already
has valid TMDb identity. Watch status and display state are irrelevant. The
TVMaze schedule and saved TVMaze mapping are resolution results, not eligibility
evidence.

## Resolver Contract

The resolver exposes two operations:

1. **Automatic resolution:** derive the TMDb series ID, use a saved mapping or
   the TVDB and IMDb IDs supplied by the live eligibility result for TVMaze
   lookup, then fetch the full show with its embedded next episode. On an ID
   miss, return a user-assistance outcome without starting title search.
2. **User-initiated title fallback:** only after the validation sheet opens,
   search for the top TVMaze ID and fetch the same full show response.

Each operation returns a hydrated show or a resolution outcome. ID discovery
and show retrieval may be separate internally but are never exposed as caller-
orchestrated stages. Title fallback does not write the TMDb-to-TVMaze mapping;
confirmation does.

## Feature Boundaries

- A narrow TMDb broadcast-eligibility checker responsible for retrieving the
  current series scheduling fields and appended TVDB/IMDb IDs in one request,
  applying the series/season predicate, and carrying those IDs only when the
  entry is eligible.
- A TVMaze client responsible for ID lookup, top-result title search, and full
  show retrieval with the next episode embedded.
- A resolver responsible for the two workflows above.

Clients return dedicated types containing only fields the feature uses. They do
not expose raw JSON, dictionaries, or types with a `DTO` suffix.

## Detail State And Dependency Ownership

Create one `@MainActor @Observable` `EntryDetailBroadcastModel`, with a nested
equatable phase covering disabled, ineligible, idle, checking-eligibility,
resolving, resolved, requires-user-assistance, title-searching, title-candidate,
and failed states.
It owns the current phase, any hydrated show or candidate carried by that phase,
the in-flight task, its TMDb eligibility checker, and its `TVMazeResolver`.

`EntryDetailSession` owns one broadcast model for the lifetime of the presented
entry. Do not put broadcast data or its task in `EntryDetailView`, either detail
host, or `EntryDetailPresentationState`. `EntryDetailSessionStore` already
preserves the same session while a detail migrates between sheet and inspector,
so this ownership also preserves resolved data, candidates, failures, and
in-flight work through a resize. Existing nested-sheet dismissal behavior may
still close the validation sheet during host migration; its candidate remains
in the broadcast model and can be presented again.

Inject the production TMDb eligibility checker and TVMaze resolver into
`EntryDetailSessionStore`, which creates detail sessions. When the store creates
a session, it creates the broadcast model with those dependencies and passes the
model into `EntryDetailSession`. Tests can inject both at the store or model
initializer. Views observe the model and report setting changes, but never
construct or call either network dependency directly.

The broadcast model starts and owns automatic-resolution work. Repeated view
appearances for the same session are idempotent, so replacing the sheet host
with the inspector host neither cancels nor restarts a request. Disabling the
feature cancels active work and moves the model to disabled; destroying or
replacing the session cancels work for the old entry.

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
- Store the small mapping dictionary in UserDefaults through
  `TVMazeConfirmedMappingStore`.
- Retrieve TMDb scheduling fields and `external_ids` together through the TV
  details endpoint's `append_to_response` parameter. Do not repeat the
  external-ID request inside the TVMaze resolver.
- Use normal URL-session HTTP caching; no custom session is currently needed.

## Implementation Outline

1. **Complete:** Add narrow TMDb external-ID decoding, TVMaze models and client,
   and resolver.
2. **Complete:** Add the UserDefaults confirmed-mapping store, inject it into
   the resolver, save direct TVDB/IMDb matches, and expose explicit confirmation
   for title candidates.
3. **Complete:** Add the off-by-default preference, live TMDb scheduling
   eligibility checker, `EntryDetailBroadcastModel`, session ownership,
   dependency injection, and setting-gated automatic resolution.
4. Add the user-facing setting toggle, airtime section, and user-assistance
   action to the detail ellipsis menu.
5. Add the candidate-validation sheet and connect confirmation to the existing
   resolver seam.
6. Add focused state, lifecycle, menu, and validation tests as each slice is
   implemented.

## Open Decisions

- The final user-facing wording for the broadcast-time setting.
- The final metadata and visual layout used by the validation sheet.
