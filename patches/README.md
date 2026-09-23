# patches/ —— Windows 复现所需的代码改动

本目录存放让这个项目**在 Windows（WSL2）上跑起来**所需的全部代码改动，以 unified diff 形式提供。

- **上游基线**：`Larkspur-Wang/Codex_Keyboard` tag `v0.1.0-local-training`
  （作者原版只在 macOS 上验证过；Linux 分支写了一半、从未跑通）
- **补丁规模**：13 个文件、约 697 行增删
- **已自检**：`patch -p1 --dry-run` 全部 clean，可干净应用

## 怎么用

```bash
cd <仓库根目录>
patch -p1 < patches/01-host-linux-port.patch
patch -p1 < patches/02-firmware-fixes.patch
```

或者用 git：

```bash
git apply patches/01-host-linux-port.patch
git apply patches/02-firmware-fixes.patch
```

> 注意：补丁基于**原始 CRLF 行尾**生成。如果你的副本已被编辑器改成 LF，
> 加 `--ignore-whitespace`（git apply）或 `-l`（patch）容错。

---

## 01-host-linux-port.patch（12 文件 / +368 -291）

### A 组 · Linux 移植适配（让 macOS-only 的 Host 在 WSL 跑起来）

| 文件 | 改了什么 | 为什么 |
|---|---|---|
| `spark_runner.rs` | ① 空 `auth.json` 兜底 ② arg0 白名单加 `codex-linux-sandbox` ③ arg0 target 校验放宽 ④ `--output-schema` 与文件名之间被插 `--config` 的顺序问题 ⑤ `runtime_file_limit()` 补 `-journal` ⑥ `skills` 目录空目录要求 ⑦ `SummaryDocument` 的 `facts/pending/decisions/schema` 改 `#[serde(default)]` | macOS 版 Codex 与新版 Linux Codex 的参数/沙箱约定不同；7 处都会导致总结链路直接失败 |
| `lib.rs` | 新增 `time_stamp()` / `local_datetime_human()` / `local_weekday_cn()` / `elog!` 宏 | **原版 Host 日志完全没有时间戳**（2709 行里只有 118 行带时间，还都是别的进程的）。排查"卡了几分钟"必须靠时间 |
| `main.rs` | 新增 `load_environment_defaults()` —— 让守护进程自己读 `/etc/environment` | systemd 启动的进程拿不到登录 shell 的环境变量，否则 Codex 子进程会因缺 `QWEN_API_KEY` 秒退 |
| `codex_runner.rs` | ① Linux 分支补齐 ② `classify_stderr` 的 `contains("401")` 裸数字匹配修复 ③ 新增 `augment_prompt()` 注入本机时间 | ①是移植；②任何含 "401" 的文本都被误判成认证失败（曾致 7 个任务全失败）；③Codex 上下文里只有日期没有时刻，被问"现在几点"时会答"我无法获取" |
| `health.rs` | Linux 分支补齐 | 健康检查接口的 Unix socket 部分 |
| `lan_voice.rs` | Linux 适配 | 收包线程 |
| `dashscope.rs` | macOS 系统代理读取加非 mac 回退 | 否则 Linux 下取代理配置会 panic |
| `summary.rs` | `SummaryDocument` 字段 `#[serde(default)]` | 千问返回的 JSON 偶尔省略可选字段，硬解析会失败 |
| `examples/m4_spark_gate.rs` | 示例同步适配 | 保持示例可编译 |

### B 组 · 缺陷修复（原项目遗留，跨平台都存在）

| 文件 | 改了什么 | 修的是哪个 bug |
|---|---|---|
| `store.rs` | `summary_work_tasks_after` 的 SQL 加 `AND task_id IN (SELECT task_id FROM bindings)` | **毒药死循环**：任务换绑后遗留的 completion 永远总结不出，worker 无限重试（实测 3.8 小时刷 137 条 abandoned） |
| `summary_orchestrator.rs` | 发布失败时补 `self.abandon(&claim)`（2 处） | **僵尸总结锁**：`publish_summary` 失败后不释放锁，留下 `generating` 僵尸，后续全部撞锁（实测卡 168 分钟、刷 336 次 "already running"） |
| `summary_worker.rs` | 失败重试间隔 30s→5s；新增连续失败 5 次熔断 10 分钟 | 偶发失败恢复更快；同时防止毒药任务烧钱 |

---

## 02-firmware-fixes.patch（1 文件 / +27 -11）

| 文件 | 改了什么 | 为什么 |
|---|---|---|
| `main/platform/keyboard_audio.cpp` | ① `kAudioCaptureQueueFrames` 64→256 帧（1.28s→5.12s 缓冲）② 新增 `kAudioMaxToleratedGapFrames=10`，缺口 ≤10 帧不再作废整句 | **Wi-Fi 抖动吃句子**：录音队列溢出 → 丢帧 → 序号缺口 → 固件立刻 `request_stop` 作废整句话。原版是"缺口即丢弃"，改后与 Host 侧 `MAX_CAPTURE_GAP_FRAMES=10` 对齐，小额缺口交给 Host 补静音 |

---

## 这些改动经过什么验证

- 宿主测试：`firmware/host_test` **57/57 通过**（纯逻辑，无需真机）
- Host 端到端：无板子模拟器跑通全链路（心跳握手 / ASR / 任务 / 总结 / TTS / 播放 100%）
- 真机验证：S1 说话 → 云端 → 第 5 颗灯变色 → S5 播报，全链路成功；固件改动已编译烧录并抓包确认心跳正常
- 补丁自检：`patch -p1 --dry-run` 对 13 个文件全部 clean

详细踩坑过程见 `flow/踩坑记录.md`，复现步骤见 `docs/Windows复现指南.md`。
