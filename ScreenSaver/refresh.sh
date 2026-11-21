#!/bin/bash
# 资料库有变动后：直接导出到屏保包内（唯一一份资源），再重新签名。
set -euo pipefail
cd "$(dirname "$0")"

DEST="$HOME/Library/Screen Savers/AniShelfCovers.saver"

if [ ! -d "$DEST" ]; then
  echo "屏保尚未安装，先跑 ./install.sh"
  exit 1
fi

python3 tools/export_library.py --out "$DEST/Contents/Resources" "$@"
codesign --force --sign - --timestamp=none "$DEST" >/dev/null 2>&1
killall legacyScreenSaver 2>/dev/null || true
echo "已更新包内资源: $DEST"
