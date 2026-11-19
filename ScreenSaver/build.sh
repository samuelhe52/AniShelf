#!/bin/bash
# 编译并打包 AniShelfCovers.saver
set -euo pipefail
cd "$(dirname "$0")"

NAME="AniShelfCovers"
BUNDLE_ID="${BUNDLE_ID:-com.davidhua.anishelfCovers}"
DISPLAY_NAME="${DISPLAY_NAME:-AniShelf Covers}"
BUNDLE="dist/${NAME}.saver"
SDK="$(xcrun --show-sdk-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

clang -fobjc-arc -bundle \
  -framework Cocoa -framework ScreenSaver -framework QuartzCore -framework CoreImage \
  -mmacosx-version-min=12.0 -arch arm64 -arch x86_64 \
  -isysroot "$SDK" \
  -o "$BUNDLE/Contents/MacOS/${NAME}" \
  Sources/AniShelfCoversView.m

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>AniShelf Covers</string>
    <key>CFBundleDisplayName</key>     <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>AniShelfCovers</string>
    <key>CFBundlePackageType</key>     <string>BNDL</string>
    <key>CFBundleVersion</key>         <string>0.1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>NSPrincipalClass</key>        <string>AniShelfCoversView</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>NSHumanReadableCopyright</key><string>Personal use. Poster data by TMDb.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null 2>&1 || true
echo "已生成 $BUNDLE"
lipo -archs "$BUNDLE/Contents/MacOS/${NAME}" 2>/dev/null || true
