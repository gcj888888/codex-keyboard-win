#!/bin/bash
# 编译并烧录固件到 ESP32-S3（EasyInput V2）
#
# 前置条件：
#   1) WSL 里已装 ESP-IDF（v5.x）。装在哪都行 —— 用 IDF_DIR 指过去即可，
#      常见位置：$HOME/esp/esp-idf、/opt/esp-idf
#   2) 板子 USB 已通过 usbipd 共享给 WSL，出现 /dev/ttyACM*
#   3) 板子已进入下载模式（开机状态短按一次 BOOT 松开）
#
# 用法：
#   bash scripts/wsl/flash-firmware.sh
#   IDF_DIR=$HOME/esp/esp-idf ESP_PORT=/dev/ttyACM0 bash scripts/wsl/flash-firmware.sh
#
# ⚠️ 只写 0x0 / 0x8000 / 0x10000 三个区，绝不 erase 全片
#    （nvs 里有 Wi-Fi 密码与配网信息，擦掉要重新配网）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IDF_DIR="${IDF_DIR:-${IDF_PATH:-$HOME/esp/esp-idf}}"
PORT="${ESP_PORT:-/dev/ttyACM0}"
FW="$ROOT/firmware"

if [ ! -d "$IDF_DIR" ]; then
  echo "❌ 找不到 ESP-IDF：$IDF_DIR（用 IDF_DIR=... 指定）"
  exit 1
fi
if [ ! -e "$PORT" ]; then
  echo "❌ 找不到串口 $PORT"
  echo "   Windows 侧先执行：usbipd attach --wsl --busid <BUSID>"
  echo "   再确认板子已进下载模式（短按一次 BOOT）"
  exit 1
fi

# ESP-IDF 环境（绕过 export.sh：它要求 riscv 工具链，ESP32-S3 用不到）
export IDF_PATH="$IDF_DIR"
export IDF_TOOLS_PATH="${IDF_TOOLS_PATH:-$HOME/.espressif}"
XTENSA_BIN="$(ls -d "$IDF_TOOLS_PATH"/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin 2>/dev/null | head -1 || true)"
PYENV_BIN="$(ls -d "$IDF_TOOLS_PATH"/python_env/*/bin 2>/dev/null | head -1 || true)"
[ -n "$PYENV_BIN" ] && export PATH="$PYENV_BIN:$PATH"
[ -n "$XTENSA_BIN" ] && export PATH="$XTENSA_BIN:$PATH"

echo "════════ 1. 编译固件 ════════"
cd "$FW"
# 给 git 一个空 commit（cmake 的 git_describe 需要 .git/refs/heads/master 存在）
if [ -d "$ROOT/.git" ] && ! git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  git -C "$ROOT" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -m "init-for-fw-build" >/dev/null 2>&1 || true
fi
python "$IDF_DIR/tools/idf.py" build

echo ""
echo "════════ 2. 烧录 ════════"
python -m esptool --chip esp32s3 --port "$PORT" -b 460800 \
  --before default_reset --after hard_reset write_flash \
  --flash_mode dio --flash_size 16MB --flash_freq 80m \
  0x0 build/bootloader/bootloader.bin \
  0x8000 build/partition_table/partition-table.bin \
  0x10000 build/easy_codex_input.bin

echo ""
echo "════════ 3. 闭环验证建议 ════════"
echo "   烧录 exit 0 不等于新固件在跑。请在 Host 侧抓包确认板子恢复发心跳："
echo "   sudo timeout 10 tcpdump -nn -i any udp port 17333"
echo "   看到「板子IP:port > HostIP:17333 UDP 80 字节」成对往返即成功。"
