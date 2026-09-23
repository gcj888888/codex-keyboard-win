#!/bin/bash
# 安装 Codex Keyboard Host 的 systemd 服务 + 定时僵尸清理
#
# 用法：
#   ECI_LAN_AUDIO_PORT=17333 bash scripts/wsl/install-service.sh
#
# 环境变量（都有默认值）：
#   ECI_LAN_AUDIO_PORT  监听端口，默认 17333（必须与板子 NVS 里配的一致）
#   ECI_WORKDIR         Host 数据目录，默认 $HOME/Library/Application Support/EasyCodexInput
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/target/release/easy-codex-host"
PORT="${ECI_LAN_AUDIO_PORT:-17333}"
WORKDIR="${ECI_WORKDIR:-$HOME/Library/Application Support/EasyCodexInput}"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"

if [ ! -x "$BIN" ]; then
  echo "❌ 找不到 $BIN —— 先跑 bash scripts/wsl/apply-patches.sh 编译"
  exit 1
fi
mkdir -p "$WORKDIR"

echo "════════ 渲染 service（端口 $PORT）════════"
sudo tee /etc/systemd/system/easy-codex-host.service >/dev/null <<EOF
[Unit]
Description=Codex Keyboard Host (Linux/WSL, UDP $PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$WORKDIR
Environment=HOME=$WORKDIR
Environment=CODEX_HOME=$CODEX_HOME_DIR
Environment=ECI_LAN_AUDIO_PORT=$PORT
# 端口被占（例如别的 Host 在跑）就让位，不抢
ExecStartPre=/bin/bash -c 'SS=\$(command -v ss || echo /usr/bin/ss); if \$SS -lun 2>/dev/null | grep -q ":$PORT "; then echo "[service] $PORT 已被占用，本次让位"; exit 1; fi; exit 0'
# 启动前清理「僵尸总结生成」
ExecStartPre=-/usr/bin/python3 $ROOT/tools/clean_interrupted.py
ExecStart=$BIN daemon
Restart=always
RestartSec=15
KillSignal=SIGTERM
TimeoutStopSec=10
StandardOutput=append:$WORKDIR/host_service.log
StandardError=append:$WORKDIR/host_service.log

[Install]
WantedBy=multi-user.target
EOF

echo "════════ 安装定时僵尸清理（每 2 分钟）════════"
sudo tee /etc/systemd/system/easy-codex-clean.service >/dev/null <<EOF
[Unit]
Description=Clean interrupted summary generations

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $ROOT/tools/clean_interrupted.py
EOF

sudo tee /etc/systemd/system/easy-codex-clean.timer >/dev/null <<EOF
[Unit]
Description=Run summary cleaner every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now easy-codex-host.service
sudo systemctl enable --now easy-codex-clean.timer

echo ""
echo "════════ 状态 ════════"
sleep 4
systemctl is-active easy-codex-host.service || true
ss -lunp 2>/dev/null | grep ":$PORT" || echo "(⚠️ 端口未监听，看日志：journalctl -u easy-codex-host -n 50)"
echo ""
echo "下一步：bash scripts/wsl/bind-slots.sh   # 绑定四个槽位的 Codex 会话"
