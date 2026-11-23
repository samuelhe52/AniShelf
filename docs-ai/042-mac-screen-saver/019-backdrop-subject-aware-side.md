# 042.019 — Backdrop text follows the subject

Implemented locally on 2026-11-22.

## Context

Backdrop always puts its logo or title and facts line in the lower-left corner
([006](006-preview-rows-and-details.md)). On some stills the subject (usually a
character) sits there, and the text covers it. [PR #28](https://github.com/samuelhe52/AniShelf/pull/28)
offered left, centred, or random alignment as a setting; the backlog set that aside
because random looks unstable and a setting is the wrong tool. Samuel chose a
content-aware rule instead: **when unsure, leave the text on the left; move it to the
right only when the subject confidently overlaps the left text block.**

## Detection and cache

The exporter uses `VNGenerateObjectnessBasedSaliencyImageRequest`, revision 1,
with an image capped at 512 pixels on its longest edge. In the comparison on
the published stills, objectness produced distinct foreground boxes with
varying confidences more often than attention saliency, which tended to group
the central activity into a single broad box. The snapshot stores Vision's
normalized, lower-left-origin bounds and rectangle confidences.
[Apple’s saliency guidance](https://developer.apple.com/documentation/vision/cropping-images-using-saliency),
[Vision request reference](https://developer.apple.com/documentation/vision/vngenerateobjectnessbasedsaliencyimagerequest).

New exports analyze a downsample of the bitmap already in memory on the
encoding worker. Existing HEICs get a one-time analysis from a local thumbnail.
The app stores results, including successful empty results, in
`<image>.saliency.json` beside the image. It checks the image modification date
and analysis revision before reusing the sidecar and prunes it with the artwork.
Vision failure leaves the artwork usable. The optional `backdropRegions` field
is omitted when there are no regions. Schema 3 snapshots saved before this
change decode with no regions and keep the left placement when the existing
build-ID check allows playback. This follows the
[snapshot version policy](014-single-snapshot-version.md) and uses the existing
[bounded export workers](005-export-speed-and-pane-revision.md).

## Placement

The layout projects the boxes through the display's centered aspect-fill crop
and clips them to the screen. It measures a frame around the drawn logo or
laid-out title and the facts line, then mirrors that frame horizontally. Each
overlap is measured as a share of the corresponding text frame's area.

| Condition for moving right | Threshold |
| --- | --- |
| Confidence of an individual box intersecting the left frame | At least 0.65 |
| Largest qualifying overlap with the left frame | At least 32% |
| Sum of all overlaps with the right frame, capped at 100% | At most 18% |
| Left coverage minus right coverage | At least 22 percentage points |

Counting all boxes on the right makes the check conservative even when a
secondary box has low confidence or when two boxes overlap. A 0.60 cutoff
allowed moves on crowded stills such as `series:153217` and the portrait crop of
`series:42500`, where the right corner could cover another character. Raising the
cutoff to 0.65 kept those on the left, along with the less certain
`series:271576`. Across 137 entries in the published snapshot, the final rule
moved five at 1920 × 1080 and one at 1080 × 1920. Missed subjects can still
affect the result on crowded artwork.

The selected side sets the direction of the side gradient and aligns the logo,
title, and facts for the life of the slide. The bottom gradient spans the width
as before and the [dwell zoom](018-opening-and-backdrop-zoom.md) runs behind the
fixed text. The in-memory Settings preview uses its own thumbnail sample and
falls back to the left when it has no snapshot regions.

## Setting

**Smart Text Placement** is an on-by-default toggle in the Backdrop controls
of the macOS Screen Saver settings pane. Off keeps the text on the left.
The preference is saved under `screenSaverBackdropSubjectAwareText` and
published as `backdropSubjectAwareText` in the manifest settings. Existing schema
3 snapshots that lack the key default to On. The label is translated into
Japanese (`ja`) and Simplified Chinese (`zh-Hans`).

The toggle uses the existing presentation update path, like the
[detail toggles](006-preview-rows-and-details.md). Export analysis and its cache
run in both modes. The live Settings preview analyzes Backdrop thumbnails when
they load and reuses those regions when the toggle changes, so the current
preview slide can reposition immediately. A playing saver reads the new
setting at its next slide boundary. The Demo exposes the toggle and its
offscreen diagnostic capture honors the saved value.

All 21 ScreenSaverKit tests and the native macOS build passed. Tests covered
the stored Off value, the default for older snapshots, and moving the text
right → left → right over the same in-memory artwork. An isolated defaults
check verified persistence across layout changes. A local publisher probe
confirmed that switching Off and back On republished the settings with
identical entries and no extra image exports. In an offscreen check of
Senryu Girl, Off matched the forced-left capture pixel for pixel and On
matched the existing right-side capture.

## Screenshots

The Demo drew 20 PNGs offscreen from the published snapshot at
`~/Pictures/AniShelf Screen Saver`, using its artwork and detail choices. This
snapshot predates the optional field, so `--analyze-missing` ran the same
export analysis in memory. Its manifest checksum was identical before and
after capture. The debug versions draw the visible regions with confidence
scores, the two text frames, and the coverage used to choose the side.

Files live under [`.build/backdrop-side-shots/`](../../.build/backdrop-side-shots/).
Each stem listed here has `.png` and `-debug.png` versions.

| Example | File stem(s) | Why |
| --- | --- | --- |
| Senryu Girl, landscape | `series-87445-1920x1080-{before-left,after-right}` | 74% left coverage and 0% right |
| Frieren, landscape | `series-209867-1920x1080-{before-left,after-right}` | 68% left coverage and 17% right |
| Summer Pockets, landscape | `series-271576-1920x1080-stays-left` | The left box has 0.62 confidence |
| K-On! The Movie, landscape | `movie-120811-1920x1080-stays-left` | The qualifying box covers 27% of the text frame |
| Senryu Girl, portrait | `series-87445-1080x1920-{before-left,after-right}` | 54% left coverage and 0% right |
| Frieren, portrait | `series-209867-1080x1920-stays-left` | The crop puts both text frames inside the box |
| Beyond the Boundary: Past, portrait | `movie-311056-1080x1920-stays-left` | The 0.66-confidence box intersects neither text frame |

```sh
swift run --package-path ScreenSaverKit ScreenSaverDemo \
  --capture .build/backdrop-side-shots --backdrop-sides --analyze-missing \
  --screens 1 --entry-ids series:87445,series:209867,series:271576,movie:120811
swift run --package-path ScreenSaverKit ScreenSaverDemo \
  --capture .build/backdrop-side-shots --backdrop-sides --analyze-missing \
  --screens 5 --entry-ids series:87445,series:209867,movie:311056
```

## Refs

- [BackdropSaliency.swift](../../ScreenSaverKit/Sources/ScreenSaverArtworkAnalysis/BackdropSaliency.swift)
  owns the Vision request. [ScreenSaverImageExporter.swift](../../MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverImageExporter.swift),
  [ScreenSaverSnapshotWriter.swift](../../MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSnapshotWriter.swift), and
  [ScreenSaverPublisher.swift](../../MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverPublisher.swift)
  carry the results through export, reuse, and publication.
- [ScreenSaverManifest.swift](../../ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift)
  defines the optional snapshot field.
  [BackdropPlacement.swift](../../ScreenSaverKit/Sources/ScreenSaverKit/BackdropPlacement.swift)
  owns the crop mapping and thresholds.
  [ScreenSaverLayouts.swift](../../ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverLayouts.swift)
  measures and presents the chosen layout.
- [DemoCapture.swift](../../ScreenSaverKit/Sources/ScreenSaverDemo/DemoCapture.swift)
  captures the still and overlays using the production layout.
  [ScreenSaverKitTests.swift](../../ScreenSaverKit/Tests/ScreenSaverKitTests/ScreenSaverKitTests.swift)
  tests the rule and compatibility.

## Validation

- `swift test --package-path ScreenSaverKit` passed all 20 tests, including
  legacy manifest decoding, confidence and overlap thresholds, the clearance
  margin, and portrait crop mapping.
- `make build-mac` passed with automatic provisioning updates disabled for this
  run. Binary inspection confirmed that the app links Vision and the embedded
  saver has no Vision linkage. The embedded saver passed strict code-signature
  verification.
- A local probe using the export and writer code with a copied still confirmed
  that both fresh and backfilled regions survive a writer restart, an image
  modification date change invalidates the sidecar, and pruning removes it.
  The cached lookup took 0.18 ms and the first uncached analysis including
  Vision startup took 295 ms. Existing HEIC thumbnail decode plus Vision took
  a median 69 ms across 134 distinct local images. Across 29 already-decoded
  bitmaps, downsampling plus Vision took a median 17 ms and p95 19 ms after
  model warm-up. These are local component timings.
- End-to-end publisher timing (M1 Pro, 137 entries, six workers, copies of the
  publisher, exporter and writer, two runs each, detection skipped vs enabled):
  the first export after updating, with 134 existing backdrops and no sidecars,
  went from about 0.5 s to about 4 s (+3.4 to +3.7 s, once). A fresh export
  (about 9.2 s, artwork served over localhost) and a warm re-export (about
  0.4 s) showed no difference beyond run-to-run noise. Excludes building the
  draft from the library and real network latency.
- Reviewed the clean and diagnostic renders offscreen in both presets. No
  system screen saver activation or screen lock was used. Samuel reviewed the
  diagnostic captures and a wider set of 22 and accepted the results. Checked all 20 PNG dimensions and pairs and confirmed the
  older snapshot renders left when the Demo's analysis override is omitted.
- Initial validation surfaced a Demo detail-list type mismatch, an Xcode object
  ID collision, and a test rectangle that gave more clearance than intended.
  Each was corrected and covered by the passing reruns above.
