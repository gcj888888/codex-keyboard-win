#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""清理「僵尸总结生成」。

背景：某个 summary 生成被中断（TTS 超时 / Host 重启 / 发布失败）后会留下
state='generating' 或 'interrupted' 的记录。若不清理，后续每轮总结都会撞上
"another summary generation is already running"，新的总结永远出不来 ——
表现为信箱灯不亮、按 S5 没声音。

本脚本把「超过 STALE_SECONDS 秒没动过」的 generating/interrupted 改成 abandoned，
Host 会自动重新总结它们。

用法：
    python3 tools/clean_interrupted.py            # 实际清理
    python3 tools/clean_interrupted.py --dry-run  # 只看不动

环境变量：
    ECI_WORKDIR         Host 数据目录（默认 ~/Library/Application Support/EasyCodexInput）
    ECI_STALE_SECONDS   判定僵尸的秒数（默认 180）

本脚本永远返回 0 —— 它挂在 systemd ExecStartPre 上，绝不能失败导致服务起不来。
"""
import os
import sqlite3
import sys
import time

WORKDIR = os.environ.get("ECI_WORKDIR") or os.path.join(
    os.path.expanduser("~"), "Library", "Application Support", "EasyCodexInput"
)
DB = os.path.join(WORKDIR, "state.sqlite3")
STALE_SECONDS = int(os.environ.get("ECI_STALE_SECONDS", "180"))
LOG = os.path.join(WORKDIR, "host_service.log")
DRY_RUN = "--dry-run" in sys.argv


def log(msg):
    if DRY_RUN:
        print("[clean_interrupted] %s" % msg)
        return
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("[clean_interrupted] %s\n" % msg)
    except Exception:
        pass


def main():
    if not os.path.exists(DB):
        log("数据库不存在，跳过（%s）" % DB)
        return 0

    try:
        con = sqlite3.connect(DB, timeout=15)
    except Exception as exc:
        log("连接数据库失败：%s" % exc)
        return 0

    try:
        cur = con.cursor()
        cutoff = int(time.time()) - STALE_SECONDS
        cur.execute(
            "SELECT task_id, generation, state, updated_at FROM summary_ledger "
            "WHERE state IN ('generating','interrupted')"
        )
        rows = cur.fetchall()

        if not rows:
            # 安静退出：本脚本每 2 分钟跑一次，没事还写日志会把日志淹掉
            return 0

        stale = [r for r in rows if r[3] <= cutoff]
        fresh = [r for r in rows if r[3] > cutoff]

        if fresh:
            log("保留 %d 条较新的（可能是正在跑的）：%s"
                % (len(fresh), [(r[0][:8], r[1], r[2]) for r in fresh]))

        if not stale:
            return 0

        if DRY_RUN:
            log("【dry-run】将清理 %d 条僵尸：%s"
                % (len(stale), [(r[0][:8], r[1], r[2]) for r in stale]))
            return 0

        cur.execute(
            "UPDATE summary_ledger "
            "SET state='abandoned', claim_id=NULL, cache_object=NULL, updated_at=? "
            "WHERE state IN ('generating','interrupted') AND updated_at <= ?",
            (int(time.time()), cutoff),
        )
        con.commit()
        log("已清理 %d 条僵尸总结（超过 %d 秒未更新）" % (cur.rowcount, STALE_SECONDS))
    except Exception as exc:
        log("清理过程出错：%s" % exc)
    finally:
        try:
            con.close()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
