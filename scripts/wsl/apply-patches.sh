#!/bin/bash
# 应用 patches/ 下的全部补丁，并编译 Host（Linux/WSL 版）
#
# 用法： bash scripts/wsl/apply-patches.sh
# 依赖： rust 工具链（cargo）、patch
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "════════ 1. 应用补丁 ════════"
shopt -s nullglob
patches=(patches/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
  echo "  (patches/ 下没有补丁，跳过)"
else
  for p in "${patches[@]}"; do
    if patch -p1 -l --dry-run <"$p" >/dev/null 2>&1; then
      patch -p1 -l <"$p"
      echo "  ✅ 已应用 $p"
    elif patch -p1 -l -R --dry-run <"$p" >/dev/null 2>&1; then
      echo "  ⏭  $p 已经应用过，跳过"
    else
      echo "  ❌ $p 无法应用（可能基线已变），请检查"
      exit 1
    fi
  done
fi

echo ""
echo "════════ 2. 编译 Host ════════"
cargo build --locked --release -p easy-codex-host --bin easy-codex-host

echo ""
echo "════════ 3. 产物 ════════"
ls -lh "$ROOT/target/release/easy-codex-host"
echo ""
echo "下一步：bash scripts/wsl/install-service.sh   # 装 systemd 服务"
