# 032 — Mac detail header modes: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-23 |
| Origin | Maintainer asked to implement screenshot feedback requesting the earlier large artwork and logo header on Mac, with a switch between two modes. |
| Related | [020 native macOS](../020-native-macos/000-plan.md) |

## Background

The current `MacEntryDetailHeader` presents a small poster beside text and actions.
The feedback prefers the large background artwork and title logo still used on
iOS and iPadOS. Git history (`b080549^`) confirms Mac previously used the shared
`EntryDetailHeroSection`; the request is to offer both presentations.

## Goals

- Offer Compact and Cinematic headers in Settings → Appearance & Interaction → Entry Details.
- Retain Compact as the default and persist the selection locally on each Mac.
- Reuse the shared hero, including logo/title and missing-artwork fallbacks.
- Keep Mac tracking, action buttons, cards, selection, and scroll/session ownership intact.

## Design / approach

Add a Mac-only `MacEntryDetailHeaderStyle` beside `MacEntryDetailHeader`, a local
UserDefaults key, and an `@AppStorage` picker in the existing interface settings.
`EntryDetailView` will select the compact header or shared 420-point hero and keep
the existing grouped detail content below either. Activating Cinematic also asks
`EntryDetailViewModel` to refresh cached metadata missing a title logo, once per
successful request in the session, including when the service returns no logo.
Cinematic mode has no visible
poster, so it must clear the batch poster-flight source rather than animate a
poster from a stale rectangle. Add English, Simplified Chinese, and Japanese copy
and document the setting in the website guides.

During implementation, fixture runtime review also exposed portrait-fallback
artwork expanding the shared hero beyond its intended bounds. The shared hero now
uses the measured viewport width and explicit height; artwork and scrims render
as overlays within those bounds. See the action record for verification limits.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Keep Compact as default | Add the requested alternative without replacing the current Mac presentation for existing users. |
| Reuse the shared hero | Match the requested iOS/iPadOS artwork, logo, scrims, and fallback behavior without maintaining a second rendering. |
| Change only the header | The feedback concerns the top area; restoring mobile cards and controls would expand the request. |
| Local preference | This is a Mac presentation choice, so exclude it from backups and CloudKit settings. |
| Settings picker | Two named choices in the existing Entry Details section make the preference discoverable without adding permanent inspector chrome. |

## Validation and acceptance criteria

- Build the native Mac app and run focused preference tests.
- Build iOS to check the shared hero extraction and conditional compilation.
- Launch the fixture Mac app and inspect both modes, settings selection, narrow
  inspector layout, light/dark appearance, and selection/batch changes where possible.
- Check localization structure, Swift formatting, and website check/build.
- State manual verification gaps explicitly; builds do not establish visual acceptance.

## Amendments

### 1. Mac hero fade and logo-refetch simplification (2026-10-23)

Maintainer review of the Cinematic screenshots found the fade and layout broken.
The colored fade targeted white `platformSystemBackground`, but the Mac inspector
draws a gray system material, leaving a seam; black scrim into white fade read as
haze; the iOS toolbar scrim darkened a toolbar-free Mac edge; 420 points pushed
tracking controls below the fold. On the Mac, the artwork and text scrim now fade
to transparent through a mask over the lower 30 percent, which the metadata and
genre lines overlap as on iOS. The hero runs under the window toolbar, as on iOS,
with a lighter top scrim (0.25) for the glass toolbar controls; it is 412 points
tall including the roughly 52 points under the toolbar. The quick
actions are centered and pulled 20 points up into the fade, as on iOS. Rejected: matching the material's
color, which cannot track translucency or dark mode; and keeping the text above
the fade, which needed a shorter hero and hid more of the artwork.

The library fixture (docs-ai 026) could not show any of this: series stored a bare
`en-US` detail that never matches a `Language` raw value, movies had none, and the
fetch hit TMDb with a placeholder key. Fixture entries now get deterministic full
details (subtitle, metadata, genres, stats, studio, cast, staff), landscape
backdrops on three in four, and generated transparent logos on every other entry,
served by the default detail loader in place of TMDb. The stored seed stays
minimal (plus a backdrop path) so benchmark stores gain no detail graphs.

The platform-wide `refetchesForMissingLogo` switch duplicated the per-call
`includesTitleLogo`; only the per-call flag remains, and iOS passes `true`.
