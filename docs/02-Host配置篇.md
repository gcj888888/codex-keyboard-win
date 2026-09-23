# 02 · Host 篇 —— 电脑端怎么配置

> Host = 跑在 WSL2 里的 Rust 常驻服务，是整套系统的"大脑调度中心"。
> 本篇基于我们实际跑通的配置。

## 一、Host 是什么（先建立正确认知）

**Host 不做任何 AI 推理。** 很多人以为"Host 是服务器、负责算"——不是。

它只做**调度 + 记账**：

| Host 负责 | Host 不负责（外包给谁）|
|---|---|
| 谁在跑任务、跑到哪了 | 语音转文字 → 千问 ASR |
| 哪个槽该收到什么 | 执行任务 → 本地 Codex CLI |
| 谁听过、谁没听 | 语音合成 → 千问 TTS |
| 与板子的协议、加密、心跳 | 说话、放音 → 板子固件 |

它的全部价值在于**状态一致性**（这是 31,747 行代码的分量所在）。

## 二、规模（实测）

```
app/host/src/  = 23 个模块、31,747 行 Rust
最大文件：dashscope.rs(4452) store.rs(3882) spark_runner.rs(3297)
          rollout_observer.rs(3129) lan_voice.rs(2478)
```

**运行形态**：1 个主循环（约 10ms/轮）+ 4 个常驻线程 + N 个子进程。

| 线程 | 职责 | 频率 |
|---|---|---|
| `eci-lan-voice` | 收 UDP 包并分流 | 持续 |
| `eci-lan-asr` | 调千问 ASR | 按需 |
| 观察线程 | 读 Codex 流水账判断任务状态 | 20ms |
| 总结线程 | 生成总结 + TTS | 250ms |

> ⚠️ **观察线程或总结线程任一死掉 → Host 主动退出**。因为"半死不活"（能收包但灯不动、
> 总结不出）比直接挂掉难查得多。宁可让你看到它重启。

## 三、怎么编译

```bash
# 在 WSL 里
cd ~/codex-keyboard-win
bash scripts/wsl/apply-patches.sh
```

它做：应用 `patches/` 下的补丁 → `cargo build --locked --release -p easy-codex-host`。

产物：`target/release/easy-codex-host`（约 7.2MB）。

等价的手工命令：
```bash
cargo build --locked --release -p easy-codex-host --bin easy-codex-host
```

> 首次编译 3~8 分钟。Rust 版本不够就 `rustup update`。

## 四、怎么配置

### 必需项：API Key（放仓库外！）

Host 需要 `QWEN_API_KEY`（DashScope 北京区）。**绝不写进仓库**：

```bash
sudo tee -a /etc/environment >/dev/null <<'EOF'
QWEN_API_KEY=sk-你的key
EASY_CODEX_CLI=/usr/local/bin/codex
EOF
```

> **为什么放 `/etc/environment`**：用 systemd 启动的进程拿不到登录 shell 的环境变量，
> 会导致 Codex 子进程因缺 key 而秒退（症状：任务 0 秒失败）。我们给 Host 打了补丁
> 让它自己读这个文件。

### 可选项（都有默认值）

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `ECI_LAN_AUDIO_PORT` | 17333 | **必须与板子 NVS 里配的一致** |
| `HOME` / `ECI_WORKDIR` | `~/Library/Application Support/EasyCodexInput` | 数据目录 |

### 数据目录里有什么

```
~/Library/Application Support/EasyCodexInput/
├── state.sqlite3        ← 核心账本（8 张表）
├── device-secret.hex    ← 与板子共享的 32 字节密钥（0600）
└── host_service.log     ← 日志
```

**8 张表**：`bindings`(槽位绑定) / `jobs`(任务) / `completion_ledger`(完成记录) /
`summary_ledger`(总结账本) / `summary_playback_leases` / `summary_tts_attempts` /
`rollout_cursors`(读文件进度) / `sqlite_sequence`。

> **真相源规则**：任务完成看 Codex 的 rollout 文件；听没听看板子回执；
> 有没有未读看 `summary_ledger.state = 'unheard'`。

## 五、怎么装服务（systemd）

```bash
bash scripts/wsl/install-service.sh
```

装了：
- `easy-codex-host.service` —— Host 本体（含"端口被占就让位"）
- `easy-codex-clean.timer` —— 每 2 分钟清僵尸总结

**为什么用 systemd 而不是 LaunchAgent**：原项目的开机自启是 macOS 专属
（`launch_agent.rs` 在 Linux 下是空桩）。WSL 里用 systemd，效果等价且更好查。

### 日常运维

```bash
systemctl status easy-codex-host      # 状态
sudo systemctl restart easy-codex-host # 重启
journalctl -u easy-codex-host -n 50   # 日志
ss -lunp | grep 17333                 # 确认端口在监听
```

## 六、怎么绑槽位

**每个槽位 = 一个独立的 Codex 会话**（各自有 conversation 上下文）。

```bash
bash scripts/wsl/bind-slots.sh          # 绑 4 个槽
bash scripts/wsl/bind-slots.sh 1        # 只绑槽 1
```

原理：创建一个全新 Codex 会话取 `thread_id` → 停服务 → `easy-codex-host bind-slot <槽> <thread_id>` → 启服务。

> **可选**：`ECI_CODEX_CWD=<目录>` 指定 Codex 工作目录。
> **目录越大每轮越慢**（实测 478MB 项目约 60 秒/任务，小目录可降到 20~30 秒）。

### Host 的完整命令

| 命令 | 用途 |
|---|---|
| `daemon` | 跑守护进程（systemd 调这个）|
| `health` | 健康检查 |
| `bind-slot <slot> <task_id>` | 绑定槽位 |
| `provision-lan <ssid> <host> <port>` | 配网（把 Wi-Fi+Host 地址下发到板子）|
| `codex-catalog-status` | 查 Codex 可用会话 |
| `asr-import-model <path>` | 导入本地 ASR 模型 |

## 七、关键常量（排障必查）

| 常量 | 值 | 位置 |
|---|---|---|
| `LAN_AUDIO_PORT` | **17333** | `lan_voice.rs` |
| `FRAME_SAMPLES` / `FRAME_BYTES` | 320 / 640 | 上行 20ms/帧 |
| `MIN_CAPTURE_FRAMES` | 10（200ms）| 太短则拒收 |
| `MAX_CAPTURE_GAP_FRAMES` | 10（200ms）| 缺口容忍，超了才丢 |
| `MAX_GLOBAL_RUNNING_JOBS` | 4 | 并发上限（与 4 槽对应）|
| `PLAYBACK_SEND_WINDOW_CHUNKS` | 6 | 下发窗口（板子 UDP 邮箱就 6 个包）|
| `CHUNK_BYTES` | 1024 | 播放分包大小 |
| 心跳周期 | 2s（空闲 4s）| 板子侧 |
| `MAX_RETIRED_SESSIONS` | 128 | 防重放窗口 |
| `AUTH_RELOAD_INTERVAL` | 250ms | 密钥热重载 |

## 八、Host 的核心机制（三个最值得学的设计）

1. **真相源唯一** —— 不许猜。任务完成看 rollout 文件，听没听看板子回执。
   代价是慢（每次确认都要等下一环回话），换来的是"灯不会骗你"。
2. **两段式声明（claim generation）** —— 像酒店房卡，退房就作废旧卡。
   防重复发布、防重放。
3. **失败必须显式** —— 总结流水线有 8 处 `abandon`。特别是 TTS：**钱花了但结果没存好
   → 整条作废，绝不重试**（否则重复扣费）。

---

**上一篇**：[01 · 板子固件篇](01-板子固件篇.md) ｜ **下一篇**：[03 · 云端配置篇](03-云端配置篇.md)
