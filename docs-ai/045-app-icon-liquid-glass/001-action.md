# 045 — App icon Liquid Glass appearances: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-28 | Added `MyAnimeList/Resources/AppIcon.icon` with light, dark, and mono artwork plus a glass subject group; removed `AppIcon.appiconset` and `MacAppIcon.icon`; dropped the macOS-only `MacAppIcon` app-icon override | PR #32 |
| 2026-11-28 | Reworked tinted contrast in `mono.png` ([002](002-tinted-contrast.md)) | PR #32 |
| 2026-11-28 | Removed the glass Subject group and cutouts; rebuilt the tinted silhouette as vector-traced, hand-touched edges ([003](003-flat-artwork-vector-mask.md)) | PR #32 |

## Outcome and current state (as of 2026-11-28)

One Icon Composer document is now the app icon for every target and SDK. `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` applies to both iOS and macOS builds; the former `"ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*]" = MacAppIcon` lines are gone.

Key paths:

- `MyAnimeList/Resources/AppIcon.icon/icon.json` — one `Artwork` group (the Subject group was removed in [003](003-flat-artwork-vector-mask.md)), `supported-platforms.squares = ["iOS", "macOS"]`.
- `MyAnimeList/Resources/AppIcon.icon/Assets/light.png`, `dark.png` — the unchanged 1024 px illustrations, now duplicated only here for the icon.
- `MyAnimeList/Resources/AppIcon.icon/Assets/mono.png` — high-contrast monochrome artwork shown only in the tinted appearance; the current file keeps the flat-background tones from [002-tinted-contrast.md](002-tinted-contrast.md) with the vector-traced silhouette from [003-flat-artwork-vector-mask.md](003-flat-artwork-vector-mask.md).
- `MyAnimeList.xcodeproj/project.pbxproj` — app-icon build settings for both configurations.
- `MyAnimeList/Resources/Assets.xcassets/` — now only `AccentColor.colorset`, `app-icon.imageset`, and `Contents.json`; the app icon is no longer an image set here.

The in-app brand surfaces (`app-icon.imageset` used by the About sheet, About view, and TMDb onboarding) are untouched, and the marketing poster still uses its own `app-icon.png` copy.

Renditions the document produces (verified with `ictool`, platform `macOS`):

- `Default` and `Dark` render the flat illustrations (pixel-identical on iOS since [003](003-flat-artwork-vector-mask.md); the original landing added a faint specular sheen from the subject group).
- `TintedLight` and `TintedDark` show `mono.png`; the system applies the user's tint to its luminance.
- `ClearLight` and `ClearDark` render a grayscale of `mono.png` (originally the cutout subject as a glass object; see [003](003-flat-artwork-vector-mask.md)).

## Deviations from plan

None known. The build verification used `xcodebuild` directly with signing disabled because this session runs under a file sandbox and the CommandLineTools developer directory; `make build-mac` itself was not used.

## Validation

All commands run from `anishelf/` on 2026-11-28 with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (Xcode 27.3 beta, macOS 27.3).

- Icon document rendering — `ictool` exported `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark` for both `--platform macOS` and `--platform iOS`: exit 0 for all renditions, all four appearances visibly distinct.
- Resource compilation (macOS) — `actool Assets.xcassets AppIcon.icon --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon`: exit 0 with no errors or warnings; emitted `Assets.car` and `AppIcon.icns`.
- Resource compilation (iOS) — same inputs with `--platform iphoneos --minimum-deployment-target 18.1 --target-device iphone --target-device ipad`: exit 0 with no errors or warnings; emitted `Assets.car`, `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, and a partial plist with `CFBundleIconName = AppIcon`.
- macOS app build — `xcodebuild -project MyAnimeList.xcodeproj -scheme MyAnimeList -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`: `BUILD SUCCEEDED`. The built `AniShelf.app` contains `Contents/Resources/AppIcon.icns` and `Assets.car` with `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`, and `ISAppearanceTintable` renditions plus `AppIcon/Artwork` and `AppIcon/Subject` groups; its `Info.plist` carries `CFBundleIconFile` and `CFBundleIconName` both set to `AppIcon`.
- iOS app build — same scheme with `-destination 'generic/platform=iOS'`, unsigned: `BUILD SUCCEEDED`. The built `AniShelf.app` contains `Assets.car` with 1024 px `UIAppearanceAny`, `UIAppearanceDark`, and `ISAppearanceTintable` renditions plus `AppIcon/Artwork` and `AppIcon/Subject` groups, the two legacy icon PNGs, and `CFBundleIconName = AppIcon` in `Info.plist`.

Not verified:

- On-device appearance switching on an iPhone or on a macOS desktop; no iOS device is attached to this session and no simulator was booted, so the renditions above are Icon Composer/`actool` renderings rather than screen captures.
- App Store / TestFlight processing of the new icon.
- iOS 18.x install behavior of an Icon Composer icon. `actool` accepts the document at deployment target 18.1 and emits the available/dark/tintable catalog renditions, but no iOS 18 runtime was exercised.
