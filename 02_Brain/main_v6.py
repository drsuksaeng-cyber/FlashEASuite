#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
main_v6.py
FlashEASuite V2 — Brain V6 Main (Option B: Full Integration)
=============================================================
Brain ที่รองรับ Trader V6 อย่างสมบูรณ์

แตกต่างจาก brain_v6_sender.py (Option A):
  - รับ tick จาก FeederEA (port 7777) → ตรวจ regime จริง
  - ส่ง CONFIG_PUSH V6 พร้อม regime ที่ตรวจได้จาก tick data
  - รับ feedback จาก Trader (port 7779) → log trade reports
  - แทนที่ทั้ง brain_v6_sender.py + main.py (V5) ในอนาคต

แตกต่างจาก main.py (V5):
  - ส่ง type=10 array format (ไม่ใช่ type=2 policy dict)
  - Trader V6 รับและประมวลผลได้ → Configs recv > 0, ONLINE MODE

ZMQ Ports:
  7777  PULL — รับ tick จาก FeederEA
  7778  PUB  — ส่ง CONFIG_PUSH + HEARTBEAT ไป Trader
  7779  PULL — รับ feedback จาก Trader (optional log)

CONFIG_PUSH Format (MQL5 array format):
  [10, ts_ms, regime_str, sym_count, [[sym, strat_cnt, [[id,name,en,conf,tf,mm]...]]...]]

Regime Detection (ADX-based, simple):
  TRENDING : ADX > 25
  SQUEEZE  : ATR/SMA < 0.003
  RANGING  : everything else
  VOLATILE : spread spike or ATR spike

Usage:
  python 02_Brain/main_v6.py
  python 02_Brain/main_v6.py --no-feeder   (ไม่รอ FeederEA, ใช้ default regime)

Author: Dr. Suksaeng Kukanok
Version: 6.0.0
Date: 2026-03-10
"""

import zmq
import msgpack
import time
import threading
import signal
import logging
import argparse
import sys
from collections import deque, defaultdict
from typing import Optional

# Windows terminal UTF-8
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S"
)
logger = logging.getLogger("BrainV6")


# ─────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────

PORT_FEEDER    = 7777
PORT_PUB       = 7778
PORT_FEEDBACK  = 7779

CONFIG_PUSH_INTERVAL   = 30    # ส่ง CONFIG_PUSH ทุก N วินาที
HEARTBEAT_INTERVAL     = 10    # ส่ง HEARTBEAT ทุก N วินาที
REGIME_UPDATE_INTERVAL = 60    # ประเมิน regime ใหม่ทุก N วินาที

SYMBOL_SUFFIX = ".tp"          # ปรับตาม broker

# P3-12: risk_mult clamp bounds
RISK_MULT_MIN = 0.3
RISK_MULT_MAX = 2.0

def _clamp_risk_mult(v: float) -> float:
    """P3-12: Clamp risk_mult to [0.3, 2.0]."""
    return max(RISK_MULT_MIN, min(RISK_MULT_MAX, float(v)))

# P3-13: Config version counter
_config_version = 0

# Strategies ที่ deploy
# Entry format: [id_str, name_str, enabled, confidence, tf_str, mm_method, risk_mult]
SYMBOL_STRATEGIES = [
    {
        "symbol_base": "USDJPY",
        "strategies": [
            ["S06", "KAMA", True, 1.0, "H4", "MM01", 1.0],
        ]
    },
    {
        "symbol_base": "XAUUSD",
        "strategies": [
            ["S14", "BBSqueeze", True, 1.0, "H1", "MM01", 1.0],
        ]
    },
    {
        "symbol_base": "GBPUSD",
        "strategies": [
            ["S14", "BBSqueeze", True, 1.0, "H1", "MM01", 1.0],
        ]
    },
]

# Strategy → regime mapping (enable/disable based on regime)
STRATEGY_REGIMES = {
    "S06": ["TRENDING"],
    "S14": ["SQUEEZE", "RANGING"],
}


# ─────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────

def now_ms() -> int:
    return int(time.time() * 1000)


def build_symbols_array(regime: str, symbol_suffix: str) -> list:
    """สร้าง symbols array โดยปรับ enabled ตาม regime และ clamp risk_mult"""
    symbols = []
    for sym_cfg in SYMBOL_STRATEGIES:
        full_sym = sym_cfg["symbol_base"] + symbol_suffix
        strats = []
        for s in sym_cfg["strategies"]:
            strat = list(s)  # copy
            # ปรับ enabled ตาม regime
            sid = strat[0]
            allowed_regimes = STRATEGY_REGIMES.get(sid, [])
            if allowed_regimes and regime not in allowed_regimes:
                strat[2] = False  # disable
            # P3-12: clamp risk_mult (index 6) if present
            if len(strat) > 6:
                strat[6] = _clamp_risk_mult(strat[6])
            strats.append(strat)
        symbols.append([full_sym, len(strats), strats])
    return symbols


def pack_config_push(regime: str, symbol_suffix: str, msg_type: int = 10) -> bytes:
    """Pack CONFIG_PUSH (10) หรือ INITIAL_CONFIG (12) — P3-13: includes config_version"""
    global _config_version
    _config_version += 1
    symbols = build_symbols_array(regime, symbol_suffix)
    msg = [msg_type, now_ms(), regime, len(symbols), symbols, _config_version]
    return msgpack.packb(msg, use_bin_type=True)


def pack_heartbeat(seq: int) -> bytes:
    """Pack HEARTBEAT (13)"""
    return msgpack.packb([13, now_ms(), "SERVER", seq, 1], use_bin_type=True)


# ─────────────────────────────────────────────────────────────────────
# REGIME DETECTOR (ADX-based, simple)
# ─────────────────────────────────────────────────────────────────────

class RegimeDetector:
    """
    ตรวจ market regime จาก tick data

    TRENDING : high momentum (high/low range expanding)
    SQUEEZE  : low ATR relative to price (BBSqueeze condition)
    RANGING  : sideways, moderate ATR
    VOLATILE : ATR spike
    """

    def __init__(self, window: int = 200):
        self._prices   = deque(maxlen=window)
        self._spreads  = deque(maxlen=50)
        self._regime   = "UNKNOWN"
        self._lock     = threading.Lock()
        self._tick_cnt = 0

    def update(self, bid: float, ask: float) -> None:
        mid = (bid + ask) / 2
        spread = ask - bid
        with self._lock:
            self._prices.append(mid)
            self._spreads.append(spread)
            self._tick_cnt += 1

    def detect(self) -> str:
        with self._lock:
            prices = list(self._prices)
            spreads = list(self._spreads)

        if len(prices) < 50:
            return "UNKNOWN"

        # ATR proxy (average of recent high-low bars, estimated from tick range)
        recent = prices[-50:]
        price_range = max(recent) - min(recent)
        mid_price = sum(recent) / len(recent)
        atr_ratio = price_range / mid_price if mid_price > 0 else 0

        # Directional movement proxy
        half = len(prices) // 2
        first_half_avg = sum(prices[:half]) / half
        second_half_avg = sum(prices[half:]) / (len(prices) - half)
        direction_strength = abs(second_half_avg - first_half_avg) / mid_price if mid_price > 0 else 0

        # Spread spike check
        avg_spread = sum(spreads) / len(spreads) if spreads else 0
        spread_spike = avg_spread > (mid_price * 0.001)  # spread > 0.1% of price

        # Regime logic
        if spread_spike and atr_ratio > 0.015:
            regime = "VOLATILE"
        elif direction_strength > 0.003:
            regime = "TRENDING"
        elif atr_ratio < 0.003:
            regime = "SQUEEZE"
        else:
            regime = "RANGING"

        with self._lock:
            self._regime = regime

        return regime

    @property
    def current(self) -> str:
        with self._lock:
            return self._regime

    @property
    def tick_count(self) -> int:
        with self._lock:
            return self._tick_cnt


# ─────────────────────────────────────────────────────────────────────
# BRAIN V6
# ─────────────────────────────────────────────────────────────────────

class BrainV6:
    """
    Brain V6 — Full integration
    - รับ tick จาก Feeder (7777)
    - ตรวจ regime
    - ส่ง CONFIG_PUSH V6 + HEARTBEAT ไป Trader (7778)
    - รับ feedback จาก Trader (7779)
    """

    def __init__(self, symbol_suffix: str = SYMBOL_SUFFIX, no_feeder: bool = False):
        self._suffix     = symbol_suffix
        self._no_feeder  = no_feeder
        self._regime     = "TRENDING"  # default ก่อนมี tick
        self._detector   = RegimeDetector()
        self._stop       = threading.Event()

        # ZMQ
        self._ctx             = None
        self._pub             = None   # PUB → Trader (7778)
        self._feeder_pull     = None   # PULL ← Feeder (7777)
        self._feedback_pull   = None   # PULL ← Trader (7779)

        # Stats
        self._hb_seq      = 0
        self._cfg_count   = 0
        self._tick_count  = 0
        self._feedback_count = 0

    # ─────────────────────────────────────────────────────────────────
    # ZMQ Setup
    # ─────────────────────────────────────────────────────────────────

    def _setup_zmq(self) -> bool:
        try:
            self._ctx = zmq.Context()

            # PUB → Trader
            self._pub = self._ctx.socket(zmq.PUB)
            self._pub.setsockopt(zmq.SNDHWM, 1000)
            self._pub.setsockopt(zmq.LINGER, 0)
            self._pub.bind(f"tcp://*:{PORT_PUB}")
            logger.info(f"[ZMQ] PUB bound to tcp://*:{PORT_PUB}")

            if not self._no_feeder:
                # PULL ← Feeder
                self._feeder_pull = self._ctx.socket(zmq.PULL)
                self._feeder_pull.setsockopt(zmq.LINGER, 0)
                self._feeder_pull.setsockopt(zmq.RCVTIMEO, 100)
                self._feeder_pull.bind(f"tcp://127.0.0.1:{PORT_FEEDER}")
                logger.info(f"[ZMQ] PULL (Feeder) bound to tcp://127.0.0.1:{PORT_FEEDER}")

            # PULL ← Trader feedback
            self._feedback_pull = self._ctx.socket(zmq.PULL)
            self._feedback_pull.setsockopt(zmq.LINGER, 0)
            self._feedback_pull.setsockopt(zmq.RCVTIMEO, 100)
            self._feedback_pull.bind(f"tcp://127.0.0.1:{PORT_FEEDBACK}")
            logger.info(f"[ZMQ] PULL (Feedback) bound to tcp://127.0.0.1:{PORT_FEEDBACK}")

            time.sleep(0.3)  # warm-up
            return True

        except zmq.ZMQError as e:
            logger.error(f"[ZMQ] Setup failed: {e}")
            logger.error("  TIP: kill old Brain process → netstat -ano | findstr :7778")
            return False

    def _teardown_zmq(self) -> None:
        for sock in [self._pub, self._feeder_pull, self._feedback_pull]:
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass
        if self._ctx:
            try:
                self._ctx.term()
            except Exception:
                pass
        logger.info("[ZMQ] Sockets closed")

    # ─────────────────────────────────────────────────────────────────
    # Send Helpers
    # ─────────────────────────────────────────────────────────────────

    def _send(self, data: bytes) -> bool:
        try:
            self._pub.send(data, zmq.NOBLOCK)
            return True
        except zmq.ZMQError as e:
            logger.warning(f"[PUB] Send failed: {e}")
            return False

    def _send_initial_config(self) -> None:
        data = pack_config_push(self._regime, self._suffix, msg_type=12)
        self._send(data)
        self._cfg_count += 1
        logger.info(f"[INIT] INITIAL_CONFIG sent ({len(data)}B) regime={self._regime}")

    def _send_config_push(self) -> None:
        data = pack_config_push(self._regime, self._suffix, msg_type=10)
        self._send(data)
        self._cfg_count += 1
        logger.info(f"[CFG]  CONFIG_PUSH #{self._cfg_count} ({len(data)}B) regime={self._regime}")

    def _send_heartbeat(self) -> None:
        self._hb_seq += 1
        data = pack_heartbeat(self._hb_seq)
        self._send(data)
        logger.debug(f"[HB]   Heartbeat #{self._hb_seq}")

    # ─────────────────────────────────────────────────────────────────
    # Worker Threads
    # ─────────────────────────────────────────────────────────────────

    def _feeder_worker(self) -> None:
        """รับ tick จาก FeederEA → update RegimeDetector"""
        logger.info("[Feeder] Worker started")
        while not self._stop.is_set():
            if self._feeder_pull is None:
                break
            try:
                raw = self._feeder_pull.recv()
                arr = msgpack.unpackb(raw, raw=False)
                if isinstance(arr, list) and len(arr) >= 5 and arr[0] == 1:
                    # TickDataMsg: [1, ts_ms, symbol, bid, ask, ...]
                    bid = float(arr[3])
                    ask = float(arr[4])
                    self._detector.update(bid, ask)
                    self._tick_count += 1
            except zmq.Again:
                pass
            except Exception as e:
                if not self._stop.is_set():
                    logger.debug(f"[Feeder] {e}")

    def _feedback_worker(self) -> None:
        """รับ feedback จาก Trader → log เท่านั้น"""
        logger.info("[Feedback] Worker started")
        while not self._stop.is_set():
            if self._feedback_pull is None:
                break
            try:
                raw = self._feedback_pull.recv()
                arr = msgpack.unpackb(raw, raw=False)
                self._feedback_count += 1
                if isinstance(arr, list) and len(arr) > 0:
                    msg_type = arr[0]
                    if msg_type == 20:  # TRADE_REPORT
                        logger.info(f"[Feedback] TRADE_REPORT: {arr}")
                    elif msg_type == 11:  # CLIENT_HELLO
                        logger.info(f"[Feedback] CLIENT_HELLO: {arr}")
                    elif msg_type == 22:  # PERFORMANCE_METRICS
                        logger.debug(f"[Feedback] PERF: {arr}")
            except zmq.Again:
                pass
            except Exception as e:
                if not self._stop.is_set():
                    logger.debug(f"[Feedback] {e}")

    # ─────────────────────────────────────────────────────────────────
    # Main Loop
    # ─────────────────────────────────────────────────────────────────

    def run(self) -> None:
        print("=" * 65)
        print("FlashEASuite V2 — Brain V6 (Full Integration)")
        print(f"  PUB  port : {PORT_PUB}  (→ Trader)")
        if not self._no_feeder:
            print(f"  PULL port : {PORT_FEEDER}  (← Feeder)")
        print(f"  PULL port : {PORT_FEEDBACK}  (← Trader feedback)")
        print(f"  Suffix    : {self._suffix}")
        print(f"  Strategies: S06 KAMA (USDJPY), S14 BBSqueeze (XAUUSD+GBPUSD)")
        print("=" * 65)

        if not self._setup_zmq():
            return

        # Signal handlers
        signal.signal(signal.SIGINT,  lambda s, f: self._stop.set())
        signal.signal(signal.SIGTERM, lambda s, f: self._stop.set())

        # Start worker threads
        threads = []
        if not self._no_feeder and self._feeder_pull:
            t_feeder = threading.Thread(target=self._feeder_worker, daemon=True)
            t_feeder.start()
            threads.append(t_feeder)
            logger.info("[Main] Feeder worker started")

        t_fb = threading.Thread(target=self._feedback_worker, daemon=True)
        t_fb.start()
        threads.append(t_fb)
        logger.info("[Main] Feedback worker started")

        # Send INITIAL_CONFIG immediately
        time.sleep(0.5)
        self._send_initial_config()

        last_cfg    = time.time()
        last_hb     = time.time()
        last_regime = time.time()
        last_status = time.time()

        logger.info("[Main] Running... (Ctrl+C to stop)")

        while not self._stop.is_set():
            now = time.time()

            # HEARTBEAT
            if now - last_hb >= HEARTBEAT_INTERVAL:
                self._send_heartbeat()
                last_hb = now

            # Regime re-detection
            if now - last_regime >= REGIME_UPDATE_INTERVAL:
                if self._detector.tick_count >= 50:
                    new_regime = self._detector.detect()
                    if new_regime != self._regime and new_regime != "UNKNOWN":
                        old = self._regime
                        self._regime = new_regime
                        logger.info(f"[Regime] {old} → {new_regime} (ticks={self._detector.tick_count})")
                last_regime = now

            # CONFIG_PUSH
            if now - last_cfg >= CONFIG_PUSH_INTERVAL:
                self._send_config_push()
                last_cfg = now

            # Status log every 60s
            if now - last_status >= 60:
                logger.info(
                    f"[Status] regime={self._regime} | "
                    f"configs={self._cfg_count} | hb={self._hb_seq} | "
                    f"ticks={self._tick_count} | feedback={self._feedback_count}"
                )
                last_status = now

            time.sleep(0.1)

        # Shutdown
        logger.info("[Main] Stopping...")
        self._teardown_zmq()
        logger.info("[Main] Brain V6 stopped")


# ─────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description="FlashEASuite V2 — Brain V6")
    p.add_argument("--suffix",     default=".tp",     help='Symbol suffix (default: ".tp")')
    p.add_argument("--no-feeder",  action="store_true", help="Skip Feeder PULL socket (no regime detection)")
    args = p.parse_args()

    brain = BrainV6(symbol_suffix=args.suffix, no_feeder=args.no_feeder)
    brain.run()


if __name__ == "__main__":
    main()
