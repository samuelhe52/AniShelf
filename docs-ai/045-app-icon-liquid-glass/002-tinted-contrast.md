# 045 — App icon Liquid Glass appearances: Tinted contrast amendment

## Symptom

Maintainer feedback after the first landing: in the dark tinted appearance the character was hard to read. The tinted artwork from [000-plan.md](000-plan.md) put the sharp cutout on top of a blurred, darkened copy of the illustration, so the figure and leftover scene structure sat in the same narrow band of tones once the system applied a dark tint.

## Cause

Sampling the same document through `ictool` shows how the two tinted renditions map the artwork's luminance (measured with the first version of `mono.png`):

| mono luminance | TintedLight render | TintedDark render |
| --- | --- | --- |
| 0.12 (blurred background) | 0.58 | 0.14 |
| 0.62 | 0.80 | 0.30 |
| 1.00 (figure highlight) | 0.96 | 0.41 |

Both renditions preserve the ordering of the source (correlation ≈ 0.99), but the dark rendition squeezes the icon into roughly 0.13–0.41. The figure's own shadows landed at 0.13–0.16, indistinguishable from the leftover background and from the dark surround, so the subject lost its contour exactly where a dark tint compresses hardest.

A second measurement shaped the fix: the clear renditions are derived from the tinted artwork as well. Replacing `mono.png` with a uniform white or uniform black image leaves `Default` byte-identical but moves `ClearLight` by a mean of 108/255. The tinted artwork therefore has to carry both the tinted and the clear appearances, and cannot be tuned for tinted alone.

## Change

Reworked `MyAnimeList/Resources/AppIcon.icon/Assets/mono.png` only; the icon document, the light/dark artwork, and the glass subject layers are untouched.

- Background: a flat near-black field (about 0.01) instead of a blurred copy of the illustration, so no scene structure competes with the figure.
- Figure: luminance sent through a median-filtered, unsharp-masked source and remapped into 0.42–0.97, so even the figure's darkest shading starts above the background and the silhouette stays continuous, while line art, eye, profile, and hair masses remain separated.
- Edge: a faint rim light from the cutout alpha (about 85 % of a 2 px edge) keeps hair strands away from the background.

Measured result in the dark tinted rendition: background at 0.10, figure from 0.23 to 0.43 — the whole figure now sits above the surround instead of sharing its darkest tones, and the light rendition spans 0.53–0.98 with visible line art.

## Validation

- `ictool` renders all six renditions from the updated document on `macOS` (and the same document renders on `iOS`).
- `actool` compiles `Assets.xcassets` and `AppIcon.icon` for `macosx` (deployment 26.0) and `iphoneos` (deployment 18.1) with no errors or warnings, producing the same products as before.
- Tonal mapping re-measured after the change: `TintedDark` 0.10–0.43, `TintedLight` 0.53–0.98; `Default` and `Dark` unchanged.

Not re-run: full Xcode builds after this asset swap. The icon document and build settings did not change, and the earlier signed-out iOS and macOS builds already proved the resource is picked up; `actool` is the step that consumes the new PNG.

## Known trade-off

Because the clear renditions read the tinted artwork, raising the figure's tones also makes `ClearLight` and `ClearDark` lighter than before. The alternative — keeping the tinted artwork dark for the clear look — reintroduces the unreadable dark tinted icon, so the tinted reading wins. If the clear style needs its own material weight later, it has to come from the glass layers (subject specular/shadow/translucency) rather than from the mono artwork.
