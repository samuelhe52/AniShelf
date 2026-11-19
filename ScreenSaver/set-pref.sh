#!/bin/bash
# 当「选项…」面板不灵时的备用改配置方式。
# 用法： ./set-pref.sh mode 4        样式 0墙 1牌堆 2大剧照 3聚焦 4融合
#         ./set-pref.sh interval 12  切换间隔（6/9/12/20/30 秒）
#         ./set-pref.sh effect 1     切换特效 0 淡入淡出 1 平移
#         ./set-pref.sh align 1      大剧照布局 0 左 1 居中 2 随机
#         ./set-pref.sh cols 8       每屏列数 0 自动
#         ./set-pref.sh drift 1      漂移 0 横 1 斜 2 呼吸 3 静止
#         ./set-pref.sh scope 1      范围 0 全部 1 收藏 2 看完
set -euo pipefail

KEY="${1:-}"; VAL="${2:-}"
case "$KEY" in
  mode)     K="mode" ;;
  interval) K="bigInterval" ;;
  effect)   K="bigTransition" ;;
  align)    K="bigAlign" ;;
  cols)     K="cols" ;;
  drift)    K="drift" ;;
  scope)    K="scope" ;;
  *) echo "未知设置项: $KEY（可用: mode/interval/effect/align/cols/drift/scope）"; exit 1 ;;
esac
[ -z "$VAL" ] && { echo "缺少取值"; exit 1; }

COUNT=0
for PLIST in "$HOME/Library/Preferences/ByHost/com.davidhua.anishelfCovers."*.plist \
             "$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/com.davidhua.anishelfCovers."*.plist \
             "$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver.x86-64/Data/Library/Preferences/ByHost/com.davidhua.anishelfCovers."*.plist; do
  [ -f "$PLIST" ] || continue
  /usr/libexec/PlistBuddy -c "Set :$K $VAL" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$K integer $VAL" "$PLIST" 2>/dev/null || true
  echo "  $K=$VAL → $(basename "$PLIST")"
  COUNT=$((COUNT+1))
done

killall cfprefsd 2>/dev/null || true
killall legacyScreenSaver 2>/dev/null || true
[ "$COUNT" -eq 0 ] && echo "没找到偏好文件，先在系统设置里选一次该屏保。" || echo "已写入 $COUNT 个偏好文件，下次进入屏保生效。"
