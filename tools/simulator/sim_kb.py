#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""无板子模拟器 —— 用 Python 扮演那块 ESP32-S3 板子，验证 Host 是否正常工作。

不需要真板子，就能测：心跳握手（EIHB→EIMB）、防重放（篡改包被丢弃）。
协议来源：app/host/src/lan_voice.rs（Host 是权威实现）。

用法：
    python3 tools/simulator/sim_kb.py
    python3 tools/simulator/sim_kb.py --host 127.0.0.1 --port 17333
    ECI_WORKDIR=~/myworkdir python3 tools/simulator/sim_kb.py

环境变量：
    ECI_WORKDIR   Host 数据目录（内含 device-secret.hex），默认 ~/Library/Application Support/EasyCodexInput
"""
import argparse
import hashlib
import hmac
import os
import socket
import struct
import sys
import time

HEARTBEAT_CTX = b"EasyInput/EISD/v1"
AUTH_TAG = 16
DEFAULT_WORKDIR = os.path.join(
    os.path.expanduser("~"), "Library", "Application Support", "EasyCodexInput"
)


def load_key(workdir):
    path = os.path.join(workdir, "device-secret.hex")
    if not os.path.exists(path):
        print("❌ 找不到设备密钥：%s" % path)
        print("   （Host 首次运行或配网后会生成它）")
        sys.exit(1)
    key = bytes.fromhex(open(path).read().strip())
    if len(key) != 32:
        print("❌ 密钥必须是 32 字节，实际 %d" % len(key))
        sys.exit(1)
    return key


def build_heartbeat(key, seq, streaming=False, audio_ready=True):
    p = bytearray(80)
    p[0:4] = b"EIHB"
    p[4] = 1
    flags = 0
    if streaming:
        flags |= 0x01
    if audio_ready:
        flags |= 0x02
    p[5] = flags
    struct.pack_into("<I", p, 16, seq)
    p[20:24] = b"EISD"
    p[24] = 1
    p[25] = 60
    struct.pack_into("<H", p, 26, 0x0002)
    mac = hmac.new(key, HEARTBEAT_CTX + bytes(p[:64]), hashlib.sha256).digest()
    p[64:80] = mac[:AUTH_TAG]
    return bytes(p)


def parse_mailbox(pkt, key):
    if len(pkt) != 32 or pkt[:4] != b"EIMB":
        return None
    expect = hmac.new(key, pkt[:16], hashlib.sha256).digest()[:AUTH_TAG]
    if not hmac.compare_digest(expect, pkt[16:32]):
        return None
    return {
        "version": pkt[4],
        "unread_slots": pkt[5],
        "running_tasks": pkt[6],
        "seq": struct.unpack_from("<I", pkt, 8)[0],
        "coverage": list(pkt[12:16]),
    }


def describe(mb):
    slots = [i + 1 for i in range(4) if mb["unread_slots"] & (1 << i)]
    colors = {0: "绿", 1: "黄", 2: "橙", 3: "紫", 4: "红"}
    mask = format(mb["unread_slots"], "04b")
    return ("未读槽位=%s(掩码0b%s)  运行任务=%d(%s)  coverage=%s  回显seq=%d"
            % (slots if slots else "无", mask, mb["running_tasks"],
               colors.get(mb["running_tasks"], "?"), mb["coverage"], mb["seq"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1", help="Host 地址（默认 127.0.0.1）")
    ap.add_argument("--port", type=int, default=int(os.environ.get("ECI_LAN_AUDIO_PORT", "17333")))
    ap.add_argument("--workdir", default=os.environ.get("ECI_WORKDIR", DEFAULT_WORKDIR))
    ap.add_argument("--count", type=int, default=3, help="发几个心跳")
    args = ap.parse_args()

    key = load_key(args.workdir)
    print("device secret 已载入：%d 字节" % len(key))

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.settimeout(3.0)
    print("本机模拟端口 = %s" % (sock.getsockname(),))
    print("目标 Host = %s:%d" % (args.host, args.port))
    print("-" * 62)

    for seq in range(1, args.count + 1):
        sock.sendto(build_heartbeat(key, seq), (args.host, args.port))
        try:
            data, _ = sock.recvfrom(2048)
        except socket.timeout:
            print("seq=%-3d  无应答（超时）—— Host 没在监听？端口对吗？" % seq)
            continue
        mb = parse_mailbox(data, key)
        if mb is None:
            print("seq=%-3d  收到 %d 字节但不是合法 EIMB：%s" % (seq, len(data), data[:16]))
        else:
            print("seq=%-3d  ✅ %s" % (seq, describe(mb)))
        time.sleep(0.4)

    # 负向测试：故意改坏一个字节，Host 必须静默丢弃（防重放/防篡改）
    print("-" * 62)
    bad = bytearray(build_heartbeat(key, 99))
    bad[30] ^= 0xFF
    sock.sendto(bytes(bad), (args.host, args.port))
    try:
        data, _ = sock.recvfrom(2048)
        print("篡改包 -> 竟然收到应答（%d 字节）：不应该！" % len(data))
    except socket.timeout:
        print("篡改包 -> 无应答 ✅（Host 正确静默丢弃）")

    sock.close()
    print("-" * 62)
    print("心跳握手测试结束")


if __name__ == "__main__":
    sys.exit(main())
