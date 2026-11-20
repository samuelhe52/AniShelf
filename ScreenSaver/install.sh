#!/bin/bash
# 安装 / 升级：编译 -> 保留包内已有资源 -> 安装 -> 缺资源时导出 -> 签名 -> 装自动同步
# 资源只保留在 .saver 包内，不再在 Application Support 里放第二份。
set -euo pipefail
cd "$(dirname "$0")"

AUTO_SYNC=0
for a in "$@"; do
  [ "$a" = "--auto-sync" ] && AUTO_SYNC=1
  [ "$a" = "--no-auto-sync" ] && AUTO_SYNC=0
done

AUTO_SYNC=0
for a in "$@"; do
  [ "$a" = "--auto-sync" ] && AUTO_SYNC=1
  [ "$a" = "--no-auto-sync" ] && AUTO_SYNC=0
done

DEST="$HOME/Library/Screen Savers/AniShelfCovers.saver"
STORE="$HOME/Library/Containers/com.samuelhe.MyAnimeList/Data/Library/Application Support/DataProvider/mal.store"
LABEL="com.davidhua.anishelfCovers.sync"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

./build.sh

# 升级时把旧包里的封面/剧照/标志带过来，避免重复下载
if [ -d "$DEST/Contents/Resources" ]; then
  ditto "$DEST/Contents/Resources" "dist/AniShelfCovers.saver/Contents/Resources"
fi

# 同步用的两个脚本随包安装，之后即使挪走源码目录也能自己维护
cp tools/export_library.py tools/sync.sh "dist/AniShelfCovers.saver/Contents/Resources/"
chmod +x "dist/AniShelfCovers.saver/Contents/Resources/sync.sh"

mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DEST"
ditto "dist/AniShelfCovers.saver" "$DEST"

if [ ! -f "$DEST/Contents/Resources/library.json" ]; then
  echo "首次安装，导出资料库…"
  python3 tools/export_library.py --out "$DEST/Contents/Resources"
fi

codesign --force --sign - --timestamp=none "$DEST" >/dev/null 2>&1
killall legacyScreenSaver 2>/dev/null || true

# ---- 自动同步（可选）：资料库文件一变就增量更新屏保包 ----
if [ "$AUTO_SYNC" -eq 0 ]; then
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -f "$AGENT"
  echo "自动同步: 未开启（./install.sh --auto-sync 可开启，需要给 /bin/bash 完全磁盘访问权限）"
  echo "已安装: $DEST  ($(du -sh "$DEST" | cut -f1))"
  echo "系统设置 → 墙纸 → 屏幕保护程序 → 滚到底「其他」→ AniShelf Covers"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DEST/Contents/Resources/sync.sh</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$STORE</string>
        <string>$STORE-wal</string>
    </array>
    <key>RunAtLoad</key>        <true/>
    <key>ProcessType</key>      <string>Background</string>
    <key>LowPriorityIO</key>    <true/>
    <key>StandardOutPath</key>  <string>/tmp/anishelf-covers-sync.log</string>
    <key>StandardErrorPath</key><string>/tmp/anishelf-covers-sync.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$AGENT" 2>/dev/null || launchctl load -w "$AGENT" 2>/dev/null || true

echo "已安装: $DEST  ($(du -sh "$DEST" | cut -f1))"
echo "自动同步: ${AGENT} （资料库变动后约 4 秒增量更新）"
echo "系统设置 → 墙纸 → 屏幕保护程序 → 滚到底「其他」→ AniShelf Covers"
