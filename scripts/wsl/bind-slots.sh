#!/bin/bash
# 为四个槽位绑定 Codex 会话（每个槽 = 一个独立的 Codex thread）
#
# 用法：
#   bash scripts/wsl/bind-slots.sh                    # 绑全部 4 个槽
#   bash scripts/wsl/bind-slots.sh 1                  # 只绑槽 1
#   ECI_CODEX_CWD=~/projects/mydir bash scripts/wsl/bind-slots.sh
#
# 环境变量：
#   ECI_CODEX_CWD   Codex 工作目录（默认 $HOME）。任务会在这个目录里执行。
#                   注意：目录越大，Codex 每轮扫描越慢（实测 478MB 项目约 60s/任务）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/target/release/easy-codex-host"
CWD_DIR="${ECI_CODEX_CWD:-$HOME}"

if [ ! -x "$BIN" ]; then
  echo "❌ 找不到 $BIN —— 先跑 scripts/wsl/apply-patches.sh"
  exit 1
fi
command -v codex >/dev/null 2>&1 || { echo "❌ 找不到 codex CLI"; exit 1; }
[ -d "$CWD_DIR/.git" ] || echo "⚠️  $CWD_DIR 不是 git 仓库（Codex 要求受信任目录；加 --skip-git-repo-check 可绕过）"

slots=("$@")
if [ ${#slots[@]} -eq 0 ]; then slots=(1 2 3 4); fi

new_thread() {
  # 起一个全新 Codex 会话，从 --json 输出里取 thread_id
  local tid
  tid=$(cd "$CWD_DIR" && codex exec --json --skip-git-repo-check "你好" 2>/dev/null \
        | grep -o '"thread_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  echo "$tid"
}

for slot in "${slots[@]}"; do
  echo "════════ 绑定槽 $slot ════════"
  tid="$(new_thread)"
  if [ -z "$tid" ]; then
    echo "  ❌ 创建 Codex 会话失败（检查 codex 是否可用、认证是否配好）"
    continue
  fi
  echo "  新会话 thread_id = $tid"

  # 绑定时 Host 不应在跑（数据库独占写）
  sudo systemctl stop easy-codex-host.service 2>/dev/null || true
  sleep 1
  "$BIN" bind-slot "$slot" "$tid"
  sudo systemctl start easy-codex-host.service 2>/dev/null || true
  echo "  ✅ 槽 $slot 已绑定"
done

echo ""
echo "════════ 结果 ════════"
sleep 3
"$BIN" health 2>&1 | head -20 || true
echo ""
echo "现在可以按住 S1~S4 说话了。诊断：bash scripts/wsl/doctor.sh"
