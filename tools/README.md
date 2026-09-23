# tools/ —— 诊断与验证工具

不依赖真板子，就能验证 Host 是否正常。所有脚本都可用环境变量覆盖路径/端口，
不含任何硬编码的密钥或内网地址。

## 目录

| 工具 | 用途 | 依赖 |
|---|---|---|
| `simulator/sim_kb.py` | **无板子模拟器**：扮演 ESP32 板子发心跳（EIHB），验证 Host 应答 + 防篡改 | Python 3 |
| `clean_interrupted.py` | **僵尸总结清理**：把卡住的 `generating/interrupted` 总结标成 abandoned | Python 3 |

## 用法

### 1. 模拟器（验证 Host 活着）

```bash
# Host 必须在跑，且数据目录里有 device-secret.hex
python3 tools/simulator/sim_kb.py
```

正常输出：

```
seq=1    ✅ 未读槽位=无(掩码0b0000)  运行任务=0(绿)  coverage=[0, 0, 0, 0]  回显seq=1
...
篡改包 -> 无应答 ✅（Host 正确静默丢弃）
```

- 看到 `✅` = Host 心跳链路正常
- 看到「无应答（超时）」= 检查 Host 是否在跑、端口是否一致（`ss -lunp | grep 17333`）

### 2. 僵尸清理

```bash
python3 tools/clean_interrupted.py --dry-run   # 只看不动
python3 tools/clean_interrupted.py             # 实际清理
```

正常情况下它**不输出任何内容**（没有僵尸就安静退出）。
systemd 的 `easy-codex-clean.timer` 每 2 分钟自动跑一次。

## 为什么需要这些

- **没有真板子时**：模拟器让 Host 链路可测（心跳、协议、防重放），不必等人守着板子按键。
- **僵尸总结**：Host 的总结生成锁异常中断后不会被回收（原项目缺陷），
  需要外部看门狗定期清理，否则总结永远出不来、灯永远不变。详见 `flow/踩坑记录.md`。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `ECI_WORKDIR` | `~/Library/Application Support/EasyCodexInput` | Host 数据目录（内含数据库与密钥）|
| `ECI_LAN_AUDIO_PORT` | `17333` | Host 监听端口 |
| `ECI_STALE_SECONDS` | `180` | 判定僵尸的秒数 |
