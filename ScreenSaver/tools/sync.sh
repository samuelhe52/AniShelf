#!/bin/bash
# 由 LaunchAgent 在 AniShelf 资料库变化时调用：增量同步到屏保包内
# 注意：macOS 会拦截非本 App 进程读取 ~/Library/Containers/<App>，
# 需要把 /bin/bash（或本脚本）加入「完全磁盘访问权限」才能自动读到资料库。
set -uo pipefail

RES="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$(cd "$RES/../.." && pwd)"
LOCKDIR="$RES/.syncing"
STATUS="$RES/.sync-status"
STORE="$HOME/Library/Containers/com.samuelhe.MyAnimeList/Data/Library/Application Support/DataProvider/mal.store"

# 目录锁，已有一个在跑就直接退出
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

# 合并短时间内的连续写入
sleep 4

PY=/usr/bin/python3
[ -x "$PY" ] || PY="$(command -v python3)"
[ -x "$PY" ] || { echo "$(date) 找不到 python3" > "$STATUS"; exit 0; }

LOG="$(mktemp)"
"$PY" "$RES/export_library.py" --out "$RES" --skip-images >"$LOG" 2>&1
RC=$?

if [ $RC -ne 0 ] && grep -q "Operation not permitted" "$LOG"; then
    # 读不到容器：给出可执行的提示，而不是反复重试
    cat > "$STATUS" <<EOF
$(date "+%Y-%m-%d %H:%M")
自动同步失败：macOS 不允许后台进程读取 AniShelf 的资料库。
两种解决方式（任选其一）：
  1) 系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 添加 /bin/bash，然后重新登录
  2) 不用自动同步：每次改完资料库手动执行 ./refresh.sh
EOF
    echo "自动同步被系统拦截，详见 $STATUS" >> /tmp/anishelf-covers-sync.log
    rm -f "$LOG"
    exit 0
fi

cat "$LOG" >> /tmp/anishelf-covers-sync.log 2>/dev/null
rm -f "$LOG"
echo "$(date "+%Y-%m-%d %H:%M") 同步完成 rc=$RC" > "$STATUS"

codesign --force --sign - --timestamp=none "$BUNDLE" >/dev/null 2>&1 || true
