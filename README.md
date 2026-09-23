# Codex Keyboard · Windows 复现版

把 EasyInput V2 键盘变成**Codex 任务电台**：按住 `S1~S4` 用语音下指令，电脑上的 Codex
执行任务，完成后按 `S5~S8` 听语音总结。全程走局域网 Wi-Fi，不用公网、不用手机 App。

> 原项目 [`Larkspur-Wang/Codex_Keyboard`](https://github.com/Larkspur-Wang/Codex_Keyboard)
> **只支持 macOS**（Host 用 LaunchAgent、Keychain、Unix socket）。
> 本仓是**在 Windows 11 + WSL2 上实测跑通**的复现版，含全部适配补丁、部署脚本、
> 诊断工具和踩坑记录 —— 让没有 Mac 的人也能复现这套东西。

## 🚀 快速开始（Windows 11）

三步（完整步骤见 **[docs/Windows复现指南.md](docs/Windows复现指南.md)**）：

```bash
# 在 WSL2 (Ubuntu) 里执行
bash scripts/wsl/apply-patches.sh     # 1) 打补丁 + 编译 Host
bash scripts/wsl/install-service.sh   # 2) 装 systemd 服务（含僵尸清理定时器）
bash scripts/wsl/bind-slots.sh        # 3) 绑定四个槽位
```

之后按住 `S1` 说句话试试。一键诊断：`bash scripts/wsl/doctor.sh`。

Windows 侧环境自检（PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\setup-wsl.ps1
```

## 它是怎么工作的

```
板子 (ESP32-S3)                    Windows 电脑
┌──────────────────┐    Wi-Fi     ┌──────────────────────────────┐
│ S1-S4 按住录音   │ ──UDP:17333─▶│ WSL2: Host (Rust, systemd)   │
│ 麦克风 16k PCM   │              │  ├─ Qwen ASR 语音转文字      │
│ 5 颗 WS2812 灯   │ ◀──UDP───────│  ├─ Codex CLI 执行任务       │
│ 扬声器 48k ADPCM │              │  ├─ Qwen TTS 生成总结语音    │
└──────────────────┘              │  └─ SQLite 状态账本          │
     5V 电池供电                   └──────────────────────────────┘
```

- `S1-S4`：按住说话，松开后 Host 调 Qwen ASR 转文字，按任务 FIFO 投递给 Codex。
- `S5-S8`：播放对应槽位最新的未读总结。
- 旋钮：逆时针降低音量、顺时针提高；短按播报当前音量，长按 3 秒进配置模式。
- 状态灯：左起四灯对应槽 1-4（未听总结越多越亮，听完熄灭）；第 5 颗显示 0-4 个运行任务
  （绿/黄/橙/紫/红）。

**职责边界**：Host 不做 AI 推理 —— 它只做调度和记账（谁在跑、跑到哪、谁该听）。
ASR/TTS 交给 Qwen，任务执行交给本地 Codex CLI。

## Windows 与原版的差异

| 方面 | 原版（macOS） | 本仓（Windows / WSL2） |
|---|---|---|
| Host 运行 | macOS 原生进程，LaunchAgent 开机自启 | WSL2 Ubuntu，**systemd** 管理 |
| 管理界面 | Tauri 2 桌面 App | **命令行**（`bind-slot` / `health` 等），无需 App |
| 密钥存储 | macOS Keychain | `/etc/environment`（仓库外，权限 0600）|
| 通信 | Unix domain socket（App↔Host） | Host 只需 UDP + systemd，无内部 socket 依赖 |
| 代码改动 | — | `patches/`：13 个文件、约 697 行 |
| 平台支持 | macOS 已验证 | Windows(WSL2) 已验证；macOS 分支原样保留 |

## 目录

| 路径 | 内容 |
|---|---|
| `patches/` | **我们对上游的全部改动**（Linux 适配 + 缺陷修复 + 固件修复）|
| `scripts/windows/` | Windows 侧脚本（环境自检、WSL 保活）|
| `scripts/wsl/` | WSL 侧脚本（打补丁、装服务、绑槽位、烧固件、诊断）|
| `systemd/` | systemd 服务模板（`install-service.sh` 会渲染安装）|
| `tools/` | 诊断工具（**无板子模拟器**、僵尸总结清理）|
| `app/host/` | Rust Host（已含补丁）|
| `firmware/` | ESP32-S3 固件（已含补丁）|
| `docs/Windows复现指南.md` | **从零到跑通的完整步骤** |
| `docs/总体方案.md` 等 | 作者原文（产品边界、架构、协议）|
| `flow/` | 进展日志、踩坑记录、决策、计划 |

## 已修复的原项目缺陷

复现过程中发现并修好的问题（细节见 [flow/踩坑记录.md](flow/踩坑记录.md)）：

| 缺陷 | 症状 | 修法 |
|---|---|---|
| 总结锁无超时回收 | 一次失败后卡死数小时，刷 336 次 "already running" | 发布失败即释放锁 |
| 孤儿任务毒药循环 | 换绑后遗留的 completion 被无限重试（实测 3.8 小时刷 137 条）| SQL 只选「仍绑定」的任务 + 连续失败熔断 |
| `contains("401")` 裸数字误判 | 任何含 "401" 的文本被判认证失败 | 精确匹配错误码 |
| Host 日志无时间戳 | 无法判断"卡了几分钟" | 111 处日志加时间戳 |
| 固件录音队列溢出 | Wi-Fi 抖动导致整句被丢弃 | 队列 64→256 帧 + 缺口容忍 |

## 已知限制

- **无图形管理界面**：用命令行。Tauri App 仅 macOS，未移植（代价大、收益小）。
- **播报需手动按键**：任务完成不会自动念。
- **总结会合并累积**：连问多条时，未听的总结会被合并（答案不会丢，只是合成一条）。
- **不能播任意音乐**：下行音频通路只接 TTS。
- **快捷键功能不生效**：电台固件下 `S1~S8` 全被语音占用。

## 来源与许可

- 上游：`Larkspur-Wang/Codex_Keyboard`（tag `v0.1.0-local-training`），Apache-2.0。
- 本仓为**派生版本**，保留上游 LICENSE 与版权声明；新增的适配代码同样以 Apache-2.0 提供。
- 密钥/密码**一律不进仓库**：`QWEN_API_KEY` 放仓库外的 `/etc/environment`，
  Wi-Fi 密码由配网命令直接写入板子 NVS。
