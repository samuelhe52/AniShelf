# 042.017 — Depth Drift density and focus

## Context

The demo could prepare more posters than its 48-layer stage would accept. A rejected focus poster could still change the wash. The opening also picked planes by their start rates rather than by how long each plane stays on screen, overrepresenting the short-lived foreground. Foreground posters could then cover the sharp artwork.

## Change

- Each plane schedules its own starts. Its period is the larger of the requested interval divided by the plane’s weight and the crossing time divided by its slot count. The two background planes have 24 and 18 slots, focus has four, and foreground has two. The director picks the next scheduled start before loading artwork; the stage replaces only the named slot if an old Core Animation completion is late. No queue of rejected posters or catch-up burst is needed.
- The opening reconstructs the still-active starts from the same schedules, with staggered phases. Long-lived planes naturally account for more of the scene. Only the most recent opening focus poster supplies a palette; subsequent focus starts update the wash as they enter.
- Sharp posters vary their position within the center half of the display. Foreground posters alternate sides and keep their padded inner edges outside that band. Wide foreground posters scale down before being tucked against the edge, so the band works in portrait as well as landscape. A fixed foreground count alone would still allow a single near poster to cover the focus artwork.

## Refs

- [Depth Drift director and stage](../../ScreenSaverKit/Sources/ScreenSaverKit/Drafts/DepthDrift.swift)
- [Default-rate and saturated-rate regression](../../ScreenSaverKit/Tests/ScreenSaverKitTests/ScreenSaverKitTests.swift)

## Validation

- `swift test --package-path ScreenSaverKit --filter depthDriftPreparesOnlyActiveSlots` passed at the default and maximum requested rates. The first two attempts failed to compile the test fixture; the corrected fixture passed both cases.
- Captured and inspected the native demo at 1920 × 1080 and 1080 × 1920. At both sampled times, the blurred foreground stayed clear of the central sharp posters.
