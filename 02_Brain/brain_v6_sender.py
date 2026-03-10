#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
brain_v6_sender.py
FlashEASuite V2 — Brain V6 Quick Fix Sender (Option A)
=======================================================
ส่ง CONFIG_PUSH (type 10) และ HEARTBEAT (type 13) ผ่าน ZMQ PUB port 7778
ในรูปแบบที่ Trader V6 (MQL5 ConfigReceiver) รอรับ

ปัญหาที่แก้:
  Brain main.py (V5) ส่ง type=2 (policy) → Trader V6 ignore ทิ้ง → Configs recv:0
  Script นี้ส่ง type=10 (CONFIG_PUSH) ที่ Trader V6 เข้าใจ → Configs recv > 0

Format ที่ MQL5 _ParseConfigPush() คาดหวัง (array, NOT dict):
  [
    10,                  # [0] msg_type = CONFIG_PUSH
    timestamp_ms,        # [1] int milliseconds
    regime_str,          # [2] string: "TRENDING","RANGING","VOLATILE","SQUEEZE"
    symbol_count,        # [3] int (redundant แต่ต้องมี)
    [                    # [4] symbols array
      [                  # each symbol entry
        symbol_name,     # [sym][0] string e.g. "USDJPY.tp"
        strat_count,     # [sym][1] int
        [                # [sym][2] strategies array
          [id_str, name_str, enabled, confidence, tf_str, mm_method],
          ...
        ]
      ],
      ...
    ]
  ]

Strategy IDs: "S01"-"S16" หรือ 0-based int "0"-"15"
  S06_KAMA    = "S06"  (0-based index 5)
  S14_SQUEEZE = "S14"  (0-based index 13)

HEARTBEAT format:
  [13, ts_ms, "SERVER", seq_int, 1]

INITIAL_CONFIG format (type 12):
  เหมือน CONFIG_PUSH ทุกอย่าง แต่ element[0] = 12
  Trader จะ print "INITIAL_CONFIG: ONLINE MODE" ใน Journal

Usage:
  python brain_v6_sender.py [--suffix .tp] [--regime TRENDING]

Author: Dr. Suksaeng Kukanok
Date: 2026-03-10
"""

import time
import zmq
import msgpack
import sys
import argparse
import signal

# ─────────────────────────────────────────────────────────────────────
# DEFAULT CONFIG — ปรับตามสภาพแวดล้อมจริง
# ─────────────────────────────────────────────────────────────────────

PUB_PORT               = 7778   # ZMQ PUB (Trader SUB ต่อมา)
CONFIG_PUSH_INTERVAL   = 30     # ส่ง CONFIG_PUSH ทุก N วินาที
HEARTBEAT_INTERVAL     = 10     # ส่ง HEARTBEAT ทุก N วินาที

# Strategies เปิดใช้งาน (ปรับ enabled=False เพื่อปิด)
# id_str: "S06","S14" → _MapStratIDToIndex รู้จักทั้ง "S06" และ "0"-"15"
DEFAULT_STRATEGIES = [
    {
        "symbol_base": "USDJPY",
        "strategies": [
            # [id_str, name_str, enabled, confidence, tf_str, mm_method]
            ["S06", "KAMA", True, 1.0, "H4", "MM01"],
        ]
    },
    {
        "symbol_base": "XAUUSD",
        "strategies": [
            ["S14", "BBSqueeze", True, 1.0, "H1", "MM01"],
        ]
    },
    {
        "symbol_base": "GBPUSD",
        "strategies": [
            ["S14", "BBSqueeze", True, 1.0, "H1", "MM01"],
        ]
    },
]


# ─────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────

def now_ms() -> int:
    return int(time.time() * 1000)


def build_symbols_array(symbol_suffix: str, strategies_def: list) -> list:
    """สร้าง symbols array ตาม format ที่ MQL5 คาดหวัง"""
    symbols = []
    for sym_cfg in strategies_def:
        full_sym = sym_cfg["symbol_base"] + symbol_suffix
        strats = sym_cfg["strategies"]
        sym_entry = [
            full_sym,          # [0] symbol name (with suffix)
            len(strats),       # [1] strat_count
            strats,            # [2] strategies: [[id,name,enabled,conf,tf,mm], ...]
        ]
        symbols.append(sym_entry)
    return symbols


def build_config_push(regime: str, symbol_suffix: str, strategies_def: list) -> bytes:
    """
    สร้าง CONFIG_PUSH (type 10) packed bytes
    Format: [10, ts_ms, regime, sym_count, [symbols]]
    """
    symbols_array = build_symbols_array(symbol_suffix, strategies_def)
    msg = [
        10,                       # [0] msg_type = CONFIG_PUSH
        now_ms(),                 # [1] timestamp_ms
        regime,                   # [2] regime string
        len(symbols_array),       # [3] symbol_count (int, redundant แต่ต้องมี)
        symbols_array,            # [4] symbols array
    ]
    return msgpack.packb(msg, use_bin_type=True)


def build_initial_config(regime: str, symbol_suffix: str, strategies_def: list) -> bytes:
    """
    สร้าง INITIAL_CONFIG (type 12) packed bytes
    Format เหมือน CONFIG_PUSH ทุกอย่าง แต่ element[0] = 12
    Trader จะ print "[V6] ✅ INITIAL_CONFIG: ONLINE MODE | 16 strategies registered"
    """
    symbols_array = build_symbols_array(symbol_suffix, strategies_def)
    msg = [
        12,                       # [0] msg_type = INITIAL_CONFIG
        now_ms(),                 # [1] timestamp_ms
        regime,                   # [2] regime string
        len(symbols_array),       # [3] symbol_count
        symbols_array,            # [4] symbols array
    ]
    return msgpack.packb(msg, use_bin_type=True)


def build_heartbeat(seq: int) -> bytes:
    """
    สร้าง HEARTBEAT (type 13) packed bytes
    Format: [13, ts_ms, "SERVER", seq_int, 1]
    """
    msg = [13, now_ms(), "SERVER", seq, 1]
    return msgpack.packb(msg, use_bin_type=True)


# ─────────────────────────────────────────────────────────────────────
# MAIN SENDER LOOP
# ─────────────────────────────────────────────────────────────────────

def run(regime: str, symbol_suffix: str, strategies_def: list):
    print("=" * 65)
    print("FlashEASuite V2 — Brain V6 Quick Fix Sender")
    print(f"  ZMQ PUB port    : {PUB_PORT}")
    print(f"  Regime          : {regime}")
    print(f"  Symbol suffix   : {symbol_suffix}")
    print(f"  CONFIG interval : {CONFIG_PUSH_INTERVAL}s")
    print(f"  HEARTBEAT int   : {HEARTBEAT_INTERVAL}s")
    print("  Symbols:")
    for s in strategies_def:
        full = s["symbol_base"] + symbol_suffix
        ids = [x[0] for x in s["strategies"]]
        print(f"    {full:15s} → {ids}")
    print("=" * 65)

    # ZMQ setup
    ctx = zmq.Context()
    pub = ctx.socket(zmq.PUB)
    pub.setsockopt(zmq.SNDHWM, 1000)
    pub.setsockopt(zmq.LINGER, 0)
    pub.bind(f"tcp://*:{PUB_PORT}")
    print(f"[Sender] ZMQ PUB bound to tcp://*:{PUB_PORT}")
    time.sleep(0.5)  # ให้ Trader SUB มีเวลา connect

    # Graceful shutdown
    _stop = [False]
    def _sig(sig, frame):
        _stop[0] = True
    signal.signal(signal.SIGINT, _sig)
    signal.signal(signal.SIGTERM, _sig)

    last_config = 0.0
    last_hb     = 0.0
    hb_seq      = 0
    cfg_count   = 0
    hb_count    = 0

    # ── ส่ง INITIAL_CONFIG ทันทีเพื่อ trigger ONLINE MODE ──────────────
    init_bytes = build_initial_config(regime, symbol_suffix, strategies_def)
    pub.send(init_bytes)
    print(f"[INIT] INITIAL_CONFIG sent ({len(init_bytes)} bytes) → Trader จะเปลี่ยน → ONLINE MODE")
    last_config = time.time()
    cfg_count += 1

    print("[Sender] Running... (Ctrl+C to stop)")
    print()

    while not _stop[0]:
        now = time.time()

        # ── HEARTBEAT ──────────────────────────────────────────────────
        if now - last_hb >= HEARTBEAT_INTERVAL:
            hb_seq += 1
            hb_bytes = build_heartbeat(hb_seq)
            pub.send(hb_bytes)
            hb_count += 1
            print(f"[HB]  Heartbeat #{hb_seq} sent ({len(hb_bytes)} bytes) "
                  f"| {time.strftime('%H:%M:%S')}")
            last_hb = now

        # ── CONFIG_PUSH ────────────────────────────────────────────────
        if now - last_config >= CONFIG_PUSH_INTERVAL:
            cfg_bytes = build_config_push(regime, symbol_suffix, strategies_def)
            pub.send(cfg_bytes)
            cfg_count += 1
            print(f"[CFG] CONFIG_PUSH #{cfg_count} sent ({len(cfg_bytes)} bytes) "
                  f"| regime={regime} | {time.strftime('%H:%M:%S')}")
            last_config = now

        time.sleep(0.1)

    # ── Shutdown ───────────────────────────────────────────────────────
    print(f"\n[Sender] Stopping... (sent {cfg_count} configs, {hb_count} heartbeats)")
    pub.close()
    ctx.term()
    print("[Sender] ZMQ context terminated. Bye.")


# ─────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(
        description="FlashEASuite V2 — Brain V6 Quick Fix Sender"
    )
    p.add_argument(
        "--suffix",
        default=".tp",
        help='Broker symbol suffix (default: ".tp"). Use "" for no suffix.'
    )
    p.add_argument(
        "--regime",
        default="TRENDING",
        choices=["TRENDING", "RANGING", "VOLATILE", "SQUEEZE", "UNKNOWN"],
        help="Market regime to broadcast (default: TRENDING)"
    )
    p.add_argument(
        "--disable-s06",
        action="store_true",
        help="Disable S06 KAMA"
    )
    p.add_argument(
        "--disable-s14",
        action="store_true",
        help="Disable S14 BBSqueeze"
    )
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()

    # Apply disable flags
    strategies = []
    for sym_cfg in DEFAULT_STRATEGIES:
        strats = []
        for strat in sym_cfg["strategies"]:
            s = list(strat)  # copy
            if args.disable_s06 and s[0] == "S06":
                s[2] = False
            if args.disable_s14 and s[0] == "S14":
                s[2] = False
            strats.append(s)
        strategies.append({"symbol_base": sym_cfg["symbol_base"], "strategies": strats})

    run(
        regime=args.regime,
        symbol_suffix=args.suffix,
        strategies_def=strategies,
    )
