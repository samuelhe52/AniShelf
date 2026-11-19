#!/bin/bash
# 安装 / 升级：编译 -> 保留包内已有资源 -> 安装 -> 缺资源时导出 -> 签名
# 资源只保留在 .saver 包内，不再在 Application Support 里放第二份。
set -euo pipefail
cd "$(dirname "$0")"

DEST="$HOME/Library/Screen Savers/AniShelfCovers.saver"

./build.sh

# 升级时把旧包里的封面/剧照/标志带过来，避免重复下载
if [ -d "$DEST/Contents/Resources" ]; then
  ditto "$DEST/Contents/Resources" "dist/AniShelfCovers.saver/Contents/Resources"
fi

mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DEST"
ditto "dist/AniShelfCovers.saver" "$DEST"

if [ ! -f "$DEST/Contents/Resources/library.json" ]; then
  echo "首次安装，导出资料库…"
  python3 tools/export_library.py --out "$DEST/Contents/Resources"
fi

codesign --force --sign - --timestamp=none "$DEST" >/dev/null 2>&1
killall legacyScreenSaver 2>/dev/null || true

echo "已安装: $DEST  ($(du -sh "$DEST" | cut -f1))"
echo "系统设置 → 墙纸 → 屏幕保护程序 → 滚到底「其他」→ AniShelf Covers"
