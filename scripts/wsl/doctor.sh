#!/bin/bash
# 一键诊断：Host 服务 / 端口 / 板子心跳 / 灯状态 / 僵尸总结
#
# 用法： bash scripts/wsl/doctor.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${ECI_LAN_AUDIO_PORT:-17333}"
WORKDIR="${ECI_WORKDIR:-$HOME/Library/Application Support/EasyCodexInput}"
LOG="$WORKDIR/host_service.log"

echo "══ 1. 发行版是否被回收（PID1 存活时间）══"
ps -o etime= -p 1 2>/dev/null | sed 's/^/   发行版已运行: /'

echo ""
echo "══ 2. Host 服务 ══"
echo "   状态: $(systemctl is-active easy-codex-host.service 2>/dev/null)"
echo "   端口: $(ss -lunp 2>/dev/null | grep ":$PORT" || echo '❌ 未监听')"

echo ""
echo "══ 3. 板子心跳（抓包 8 秒）══"
echo "   （经 UDP $PORT；需要 tcpdump 与权限）"
sudo timeout 8 tcpdump -nn -i any "udp port $PORT" 2>/dev/null | head -8 || echo "   (无输出或权限不足)"

echo ""
echo "══ 4. 僵尸总结 ══"
python3 "$ROOT/tools/clean_interrupted.py" --dry-run 2>/dev/null || echo "   (tools/clean_interrupted.py 缺失)"

echo ""
echo "══ 5. 日志尾部 ══"
tail -6 "$LOG" 2>/dev/null || echo "   (无日志)"

echo ""
echo "══ 6. 最近错误计数 ══"
for k in "summary_worker=failed" "already running" "lan_voice_rejected"; do
  n=$(grep -c "$k" "$LOG" 2>/dev/null || echo 0)
  echo "   $k: $n"
done
