# 045 — App icon Liquid Glass appearances: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-28 |
| Origin | Maintainer report that the AniShelf icon only had light and dark artwork, with no Liquid Glass appearance variants |
| Related | [020-native-macos](../020-native-macos/000-plan.md) |

## Background

The app shipped two independent icon sources:

- `AppIcon.appiconset` for iOS carried a light 1024 px image, a dark 1024 px image, and an empty `tinted` appearance slot.
- `MacAppIcon.icon`, an Icon Composer document used only for the Mac app, contained two flat full-bleed layers, `glass: false`, `specular: false`, and no tinted artwork.

Nothing described the tinted appearance, and nothing described layered artwork with Liquid Glass material. The system therefore synthesized the tinted and clear renditions from the light photograph: the tinted home-screen icon looked like a washed, low-contrast tint of the illustration, and the clear style had no glass subject to work with. The icon only read as designed in light and dark.

## Goals

- Provide all four icon appearances — light, dark, tinted light, tinted dark — plus a purposeful clear rendition.
- Keep the existing light and dark artwork as the visual source, so those appearances do not become a redesign.
- Use one Icon Composer document for both iOS and macOS so the appearance work cannot drift between platforms.

### Non-goals

- Redrawing the brand illustration.
- Changing in-app brand surfaces (`app-icon.imageset`, marketing assets).

## Design / approach

Replace both sources with a single `MyAnimeList/Resources/AppIcon.icon` Icon Composer document, set as the app icon for every SDK via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (the macOS-specific `MacAppIcon` override is removed).

The document contains two groups, front to back:

1. **Subject** — `subject-light.png` and `subject-dark.png`, foreground cutouts of the illustrated character with transparent backgrounds, `glass: true`, group `specular: true`, neutral shadow at 0.35, individual lighting. Hidden in the tinted appearance.
2. **Artwork** — `light.png` and `dark.png` (the existing 1024 px art), plus `mono.png`, a high-contrast monochrome rendering used only in the tinted appearance. The background group carries no specular and no shadow.

`hidden-specializations` select artwork per appearance: the light layer is visible by default and hidden in dark and tinted, the dark layer is hidden everywhere except dark, and the mono layer is hidden everywhere except tinted. `supported-platforms.squares` lists both `iOS` and `macOS`.

Derivation of the new raster assets:

- Foreground cutouts come from the system Vision foreground-instance mask over each 1024 px artwork, so the mask follows the character rather than a hand-drawn shape.
- `mono.png` is the light artwork desaturated and contrast-stretched around its 3rd–97th luminance percentiles, with the sharp cutout composited over a flattened near-black background and a faint rim light at the cutout edge. It reads as a two-tone template in tinted mode and keeps a face and silhouette that survive the system tint. The first version used a blurred, darkened copy of the artwork as that background; see [002-tinted-contrast.md](002-tinted-contrast.md) for why it was replaced.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| One shared Icon Composer document | A single source of truth; Xcode compiles it into an iOS catalog with `UIAppearanceAny`/`UIAppearanceDark`/`ISAppearanceTintable` renditions plus legacy PNGs, and into a macOS `.icns` with Aqua/DarkAqua/tintable renditions. Alternative: keep the appiconset for iOS and only add tinted artwork, which would leave iOS 26 clear icons without glass layers. |
| Designed mono artwork for tinted | The system's tinted rendering applies the user's tint to icon luminance, so a low-contrast photograph always washes out. Alternative: hand-tint the illustration toward one color, which fights whatever tint the user picks. |
| Glass cutout subject layer | Gives the clear style a real glass object with specular highlight and shadow instead of a desaturated photograph, and changes light/dark only by a faint sheen (measured mean channel difference below 2/255 against the previous light rendering). Alternative: a fully flat document, which leaves clear style as a bare grayscale conversion. |
| Keep light/dark art untouched | Composing the same pixels above the same background means the recognizable appearance does not change. Alternative: a full layered redesign with an inpainted background, rejected as a brand change the maintainer did not ask for. |

## Validation and acceptance criteria

- `ictool` renders all six renditions (`Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`) from the document, for both `iOS` and `macOS` platforms, without errors.
- `actool` compiles the document together with `Assets.xcassets` for `macosx` and `iphoneos` with no errors or warnings, producing `Assets.car` plus the platform icon products.
- The compiled iOS catalog contains 1024 px `UIAppearanceAny`, `UIAppearanceDark`, and `ISAppearanceTintable` renditions, and icon groups for each appearance.
- The compiled macOS catalog contains `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`, and `ISAppearanceTintable` renditions, and the app bundle's `Info.plist` resolves `CFBundleIconName` to `AppIcon`.
- Light and dark renders stay visually indistinguishable at icon sizes from the previous document.
- A full Xcode build produces the app with the icon from the new document.

## Amendments

- Updated 2026-11-28: the tinted artwork's dark rendition read poorly because its blurred background competed with the figure; replaced with a flat-background, rim-lit template — see [002-tinted-contrast.md](002-tinted-contrast.md)
