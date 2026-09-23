# Windows 复现指南

> 目标：在一台 **Windows 11 电脑**上，把 Codex 任务电台完整跑起来 ——
> 板子按住说话 → 电脑上的 Codex 执行任务 → 总结语音回到板子播放。
>
> 本指南基于**实测跑通**的流程编写（2026-09-23）。原项目只支持 macOS，
> 我们补了 Linux 适配并证明了 Windows（WSL2）完全可行。

---

## 0. 为什么用 WSL2 这条路

原项目的 Host 是给 macOS 写的（用 LaunchAgent 开机自启、用 Unix domain socket 通信）。
直接搬到 Windows 原生跑不通。我们选的路是：

```
Windows 11
  └─ WSL2 (Ubuntu)          ← Host 跑在这里，用 systemd 管理
       ├─ Codex CLI         ← 本地执行任务（脑子在云端 Qwen）
       └─ UDP 17333         ← 与板子通信（Wi-Fi）
板子 (ESP32-S3 EasyInput V2)  ← 烧一次固件，之后全程 Wi-Fi
```

**关键点**：WSL2 是完整的 Linux 内核，macOS 的那些系统调用都有等价物。
实测：板子、Wi-Fi、UDP、Codex、ASR/TTS 全部正常。

### 那"管理 App"呢？

原项目的 Tauri 桌面 App **只支持 macOS**，而且它用 Unix socket 连 Host ——
Windows 原生程序进不了 WSL 的内部通道，**移植代价极大**。
我们用命令行（`bind-slot`）替代了 App 的绑槽位功能，够用。

## 1. 前置条件

| 项 | 要求 | 怎么确认 |
|---|---|---|
| 系统 | Windows 11（build ≥ 22000） | `winver` |
| 硬件 | EasyInput V2 键盘（ESP32-S3 / 8MB PSRAM / 16MB Flash） | 板子背面丝印 |
| 网络 | 2.4GHz Wi-Fi（板子只支持 2.4G）；电脑与板子必须同一网段且互通 | 路由器后台 |
| WSL2 | Ubuntu 发行版 | `wsl -l -v` |
| Rust | 工具链（建议 1.75+） | `cargo --version` |
| Node.js | 只在需要烧固件时装 ESP-IDF 用到 | — |
| Codex CLI | `@openai/codex` | `codex --version` |
| Qwen API Key | DashScope 北京区 key（ASR/TTS/总结都用它） | 阿里云百炼控制台 |
| usbipd-win | **烧录固件时才需要** | `usbipd --version` |

> **不需要**：macOS、Tauri App、LaunchAgent、Keychain。

## 2. 快速检查环境

```powershell
# 在 Windows PowerShell 里（仓库根目录）
powershell -ExecutionPolicy Bypass -File scripts\windows\setup-wsl.ps1
```

它会检查 WSL / CPU / 内存 / 磁盘 / 板子 USB / usbipd / `.wslconfig`，并给出下一步。

### 防止 WSL 被空闲回收（重要）

WSL2 发行版空闲后会被回收，**Host 会跟着一起消失**。在 `%USERPROFILE%\.wslconfig` 写：

```ini
[wsl2]
instanceIdleTimeout=-1
```

> 实测这个设置**并不总能生效**，所以仓库还提供 `scripts/windows/keepalive.vbs`
> —— 每 5 分钟戳一下 WSL 保活。把它放进启动目录（`Win+R` → `shell:startup`）即可。

## 3. 落地步骤

### 步骤 1 · 克隆 + 打补丁 + 编译 Host

```bash
# 在 WSL 里
cd ~/codex-keyboard-win         # 或你的仓库路径
bash scripts/wsl/apply-patches.sh
```

这一步做三件事：应用 `patches/*.patch` → `cargo build --release` → 输出 `target/release/easy-codex-host`。

> 首次编译约 3~8 分钟（依赖多）。若报 Rust 版本不够，先 `rustup update`。

### 步骤 2 · 配置 API Key

Host 需要 `QWEN_API_KEY`（DashScope 北京区）。**不要把 key 写进仓库**。

```bash
# 写到仓库外（例如 ~/.config/eci/env），然后让 Host 能读到
sudo tee -a /etc/environment >/dev/null <<'EOF'
QWEN_API_KEY=sk-你的key
EASY_CODEX_CLI=/usr/local/bin/codex
EOF
```

> Host 已打补丁会自动加载 `/etc/environment`（因为 systemd 进程拿不到登录 shell 的环境）。
> key 只存在于本机这个文件里，**不会进仓库、不进日志**。

### 步骤 3 · 装 systemd 服务

```bash
bash scripts/wsl/install-service.sh
```

装了 `easy-codex-host.service`（Host 本体）+ `easy-codex-clean.timer`（每 2 分钟清僵尸总结）。

**端口默认 17333**，必须与板子 NVS 里配的一致。想换端口：

```bash
ECI_LAN_AUDIO_PORT=17334 bash scripts/wsl/install-service.sh
```

### 步骤 4 · 配网（让板子连上 Wi-Fi 并记住 Host 地址）

Host 通过 **USB HID** 把「Wi-Fi 名字 + 密码 + Host IP + 端口」下发给板子。

```bash
# 板子插 USB，然后：
host_ip=$(hostname -I | awk '{print $1}')     # WSL 在镜像网络模式下的 IP
./target/release/easy-codex-host provision-lan "你的WiFi名" "$host_ip" 17333
```

> ⚠️ **Host IP 会变**（重启/换网络）。原项目文档里记录过"键盘 NVS 里存的是旧 IP
> → 重启后失联"的经典故障。建议：路由器里给电脑固定 IP，或每次换网络后重新配网。

### 步骤 5 · 绑定四个槽位

每个槽位 = 一个独立的 Codex 会话。

```bash
bash scripts/wsl/bind-slots.sh          # 绑全部 4 个槽
# 或只绑某个：bash scripts/wsl/bind-slots.sh 1
```

> 可选：`ECI_CODEX_CWD=<目录>` 指定 Codex 的工作目录。
> **目录越大，每轮扫描越慢**（实测 478MB 项目约 60 秒/任务，小目录可降到 20~30 秒）。

### 步骤 6 · 烧录固件（板子已有固件则跳过）

⚠️ **只在需要时做**。板子出厂已带官方固件，但官方固件没有"任务电台"功能——
要用电台，必须烧本仓库的固件。

```bash
# 1) Windows 侧：把板子 USB 共享给 WSL
usbipd list                              # 找到 ESP32 的 BUSID
usbipd attach --wsl --busid <BUSID>

# 2) 板子进下载模式：开机状态「短按一次 BOOT 松开」（不是按住）
# 3) WSL 里编译+烧录：
IDF_DIR=/root/esp-idf-local bash scripts/wsl/flash-firmware.sh
```

**烧录铁律**（本仓库脚本已遵守）：
- **只写 0x0 / 0x8000 / 0x10000 三个区，绝不 `erase_flash`**
- `nvs` 区里有 Wi-Fi 密码和配网信息，擦掉要全部重配
- 烧完抓包确认板子恢复发心跳（`sudo tcpdump -nn -i any udp port 17333`，看 80 字节包）

### 步骤 7 · 验证

```bash
bash scripts/wsl/doctor.sh      # 一键诊断
```

然后按板子：

| 按键 | 动作 | 预期 |
|---|---|---|
| 按住 **S1** 说"1+1 等于几"，松手 | 投递给槽 1 | 几秒后**第 5 颗灯变黄**（有任务在跑）|
| 等 30~60 秒 | Codex 执行 + 生成总结 | 第 5 颗灯回绿；**第 1 颗灯亮**（有未读总结）|
| 按 **S5** | 播放槽 1 总结 | 听到语音答复；播完第 1 颗灯灭 |
| 按住 **S1** 连说两条 | 同一槽严格按序 | 两条都执行；总结可能**合并成一条**（设计如此）|

## 4. 故障排查

按「由外向内」的顺序查，别一上来就怀疑代码：

| 现象 | 先查 | 常见原因 |
|---|---|---|
| 第 5 颗灯永不变黄 | 抓包看板子有没有发心跳到 17333 | **端口不匹配**（Host 和板子配的端口不一致）|
| 按键没反应 | `ss -lunp \| grep 17333` | Host 没跑（发行版被回收）|
| 板子"突然不理人" | 是不是拔了 USB 闲置 30 分钟 | 电池供电下会**深睡**（按任意键唤醒）|
| 播放没声音 | `summary_ledger.state` 是不是 `unheard` | 总结被"听过"了 / 卡在 `generating` |
| 总结永远出不来 | 有没有僵尸 `generating` | 跑 `tools/clean_interrupted.py` |
| 任务秒失败 | rollout 里的 error | 缺 `QWEN_API_KEY` / 会话用坏了 |

详细排查手册见 `flow/踩坑记录.md`。

## 5. 已知限制（诚实清单）

| 限制 | 说明 |
|---|---|
| 管理界面 | 无 GUI，用命令行（`bind-slot` 等）。Tauri App 仅 macOS，未移植 |
| 播报要手动按键 | 任务完成不会自动念，需按 S5~S8 |
| 总结合并累积 | 连问多条时，未听的总结会被下一条合并（一个答案不会丢）|
| 不能播任意音乐 | 下行音频通路只接 TTS，放不了外部音频 |
| 快捷键功能 | 电台固件下 S1~S8 全被语音占用，官方固件的快捷键（复制/粘贴）不生效 |
| 数据目录 | 仍沿用 macOS 风格路径 `~/Library/Application Support/EasyCodexInput/`（能用，不改，改要迁移数据）|

> 想要"语音 + 快捷键"两全，需要做**双模式固件**（旋钮切换模式）——
> 见 `flow/decisions.md` 里的讨论。

## 6. 下一步

- 想复现开发过程 → 读 `flow/进展.md`（顶部是最新交接）
- 想少踩坑 → 读 `flow/踩坑记录.md`
- 想知道为什么这么设计 → 读 `docs/总体方案.md`、`docs/端到端架构.md`（作者原文）
