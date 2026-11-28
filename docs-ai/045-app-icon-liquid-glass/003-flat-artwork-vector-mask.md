# 045.003 — Flat artwork and vector-traced tinted mask

## Context

Two problems surfaced while reviewing the first version in PR #32:

1. **Glass subject edges.** Icon Composer derives Liquid Glass highlights from each glass layer's alpha contour. With the character cut out as a glass layer, the exposed silhouette caught specular light along the chin and on every fine hair strand against the sky, so light and dark read as a glossy cutout rather than the illustration. The Vision foreground mask behind that cutout was also soft and dropped thin strands.
2. **Fuzzy tinted edges.** `mono.png` carries the same silhouette. Its edges reproduced the source art's 3–6 px soft ramps (the illustration is upscaled) plus 1 px burrs from the grainy sky, so the tinted icon looked as if an edge detector had produced it — which it had.

## Change

**Icon document.** The `Subject` group and `subject-light.png` / `subject-dark.png` are removed. `icon.json` now holds a single non-specular, shadowless `Artwork` group: `light.png` and `dark.png` with `glass: false`, and `mono.png` for the tinted appearance. Light and dark render pixel-identical to the original flat illustrations, which are the same blobs that `main` shipped in `MacAppIcon.icon`.

**Tinted mask.** `mono.png` keeps the interior tones from [002-tinted-contrast.md](002-tinted-contrast.md) and drops its rim light. Its silhouette was rebuilt in stages:

- Mask refinement against the original artwork: crown, neck gaps, crossing petal and lock contours, plus recovery of thin flyaway strands that the Vision mask had lost. Petals that only touch the sky stay excluded; petals overlapping the figure stay in.
- Vectorization of every exposed edge: sub-pixel iso-lines of a coverage field (locks normalized by a wide local peak, so soft ramps cannot flatten themselves; thin strands normalized by their own peak, so faint flyaways stay faint), smoothed along arc length with sharp turns — hair tips, notches — protected, then filled even-odd with 8× supersampled coverage. Each edge becomes a 1 px antialiased curve instead of an iso-line of noisy pixels.
- A hand pass over the 4× mask in Pixelmator Pro (Pen tool and hard brush), mostly tapering blunt strand ends, recomposed into `mono.png` with strand opacity and interior tones taken from the vectorized state.

The scripts and intermediates live in the untracked `.build/icon-mask-refinement/` working directory (`sharp/vectorize.py`, `sharp/recompose.py`); they are not part of the repository.

**Rejected alternatives**

| Choice | Reason and alternative |
| --- | --- |
| Drop the glass subject | Rim highlights along the face and strands made the illustration look like a sticker, and the requirement is that light/dark reproduce the original art. Alternative: keep glass with a cleaner mask; any exposed contour still gets a highlight. |
| Vector paths over sharper iso-contours | Two raster passes (local retracing, then supersampled iso-contours) made edges crisper but kept their pixel-scale wobble. Smoothing the path itself is what removes it. |
| Algorithmic curves plus a human pass, not model hand-tracing | Coordinates read from images are only accurate to 2–3 px, and earlier per-patch knot placement produced patchy contours. The curves come from the algorithm; judgment calls (taper a tip, drop a stub) come from a person editing the 4× mask. |

## Current state

- `MyAnimeList/Resources/AppIcon.icon/icon.json`: one `Artwork` group, `specular: false`, shadow `none`.
- `MyAnimeList/Resources/AppIcon.icon/Assets/light.png`, `dark.png`: original flat illustrations.
- `MyAnimeList/Resources/AppIcon.icon/Assets/mono.png`: tinted artwork with the vector-traced, hand-touched silhouette on a near-black field.

Clear renditions still derive from `mono.png` (see [002-tinted-contrast.md](002-tinted-contrast.md)). They now render as a flat grayscale of the figure with no glass subject.

## Refs

- Validation (2026-11-28): `ictool` rendered `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark` for `iOS` and `macOS` without errors. iOS `Default` and `Dark` are pixel-identical to a flat document built from the original artwork. Tinted renders match the reviewed candidate pixel for pixel.
- `make build-mac` and `make build` both succeeded (2026-11-28). The compiled `Assets.car` contains only the `AppIcon/Artwork` group, with `UIAppearanceLight`/`UIAppearanceDark`/`ISAppearanceTintable` renditions on iOS and `NSAppearanceNameAqua`/`NSAppearanceNameDarkAqua`/`ISAppearanceTintable` on macOS.
- Not verified: on-device appearance switching. The renditions above come from `ictool` and the compiled catalogs.
