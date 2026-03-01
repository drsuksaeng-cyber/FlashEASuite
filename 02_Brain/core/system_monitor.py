#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - System Performance Monitor
Program B (Brain) — Phase 0-3

ติดตาม system metrics สำหรับ Dashboard และ Emergency System:
- CPU / Memory usage
- ZMQ message latency (tick-to-signal)
- Throughput (ticks/sec, signals/sec)
- Queue depths
- Thread health

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-18
"""

import threading
import time
import logging
import psutil
from collections import deque
from dataclasses import dataclass, field
from typing import Dict, Deque, Optional

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# DATA STRUCTURES
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class LatencyStats:
    """สถิติ latency"""
    current_ms:  float = 0.0
    avg_ms:      float = 0.0
    min_ms:      float = float('inf')
    max_ms:      float = 0.0
    p95_ms:      float = 0.0   # 95th percentile
    sample_count: int  = 0


@dataclass
class ThroughputStats:
    """สถิติ throughput"""
    ticks_per_sec:    float = 0.0
    signals_per_sec:  float = 0.0
    trades_per_min:   float = 0.0
    total_ticks:      int   = 0
    total_signals:    int   = 0
    total_trades:     int   = 0


@dataclass
class SystemSnapshot:
    """ภาพรวม system ณ เวลาหนึ่ง"""
    timestamp:          float  = field(default_factory=time.time)
    cpu_percent:        float  = 0.0
    memory_percent:     float  = 0.0
    memory_mb:          float  = 0.0
    thread_count:       int    = 0
    ingestion_queue:    int    = 0
    signal_queue:       int    = 0
    feedback_queue:     int    = 0
    latency:            LatencyStats = field(default_factory=LatencyStats)
    throughput:         ThroughputStats = field(default_factory=ThroughputStats)


# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM MONITOR CLASS
# ─────────────────────────────────────────────────────────────────────────────

class SystemMonitor:
    """
    ติดตาม system performance metrics แบบ real-time

    ทำงานเป็น background thread อ่านค่า psutil + คำนวณ latency/throughput

    Usage:
        monitor = SystemMonitor()
        monitor.set_queues(ingestion_q, signal_q, feedback_q)
        monitor.start()

        # บันทึก latency
        t_start = monitor.tick_start("EURUSD")
        # ... process tick ...
        monitor.tick_end("EURUSD", t_start)

        # ดู snapshot
        snap = monitor.get_snapshot()
    """

    def __init__(self, sample_window: int = 100):
        """
        Args:
            sample_window: จำนวน samples สำหรับ rolling statistics
        """
        self._sample_window = sample_window
        self._lock = threading.RLock()

        # Latency tracking
        self._latency_samples: Deque[float] = deque(maxlen=sample_window)
        self._tick_timestamps: Dict[str, float] = {}  # symbol → start time

        # Throughput tracking
        self._tick_times:    Deque[float] = deque(maxlen=1000)
        self._signal_times:  Deque[float] = deque(maxlen=1000)
        self._trade_times:   Deque[float] = deque(maxlen=1000)
        self._total_ticks    = 0
        self._total_signals  = 0
        self._total_trades   = 0

        # Queue references
        self._ingestion_queue  = None
        self._signal_queue     = None
        self._feedback_queue   = None

        # Latest snapshot
        self._snapshot = SystemSnapshot()

        # Background thread
        self._shutdown_event  = threading.Event()
        self._monitor_thread: Optional[threading.Thread] = None
        self._update_interval = 1.0  # seconds

        # Historical snapshots (สำหรับ graphs)
        self._history: Deque[SystemSnapshot] = deque(maxlen=300)  # 5 minutes @ 1sec

        logger.info("✅ SystemMonitor initialized")

    def set_queues(self, ingestion_q, signal_q, feedback_q) -> None:
        """ผูก queue references สำหรับ depth monitoring"""
        self._ingestion_queue = ingestion_q
        self._signal_queue    = signal_q
        self._feedback_queue  = feedback_q

    def start(self) -> None:
        """เริ่ม background monitoring"""
        self._shutdown_event.clear()
        self._monitor_thread = threading.Thread(
            target=self._monitor_loop,
            name="SystemMonitor",
            daemon=True
        )
        self._monitor_thread.start()
        logger.info("✅ SystemMonitor started")

    def stop(self) -> None:
        """หยุด monitoring"""
        self._shutdown_event.set()
        if self._monitor_thread and self._monitor_thread.is_alive():
            self._monitor_thread.join(timeout=3.0)

    # ─── LATENCY TRACKING ─────────────────────────────────────────────────

    def tick_start(self, symbol: str) -> float:
        """เริ่มนับเวลา tick processing — คืน timestamp"""
        t = time.perf_counter()
        with self._lock:
            self._tick_timestamps[symbol] = t
            self._tick_times.append(time.time())
            self._total_ticks += 1
        return t

    def tick_end(self, symbol: str, start_time: float) -> float:
        """สิ้นสุด tick processing — คำนวณ latency (ms)"""
        elapsed_ms = (time.perf_counter() - start_time) * 1000.0
        with self._lock:
            self._latency_samples.append(elapsed_ms)
            self._tick_timestamps.pop(symbol, None)
        return elapsed_ms

    def record_signal(self) -> None:
        """บันทึกว่าส่ง signal หนึ่งตัว"""
        with self._lock:
            self._signal_times.append(time.time())
            self._total_signals += 1

    def record_trade(self) -> None:
        """บันทึกว่ามี trade execution"""
        with self._lock:
            self._trade_times.append(time.time())
            self._total_trades += 1

    # ─── QUERY ────────────────────────────────────────────────────────────

    def get_snapshot(self) -> SystemSnapshot:
        """คืน snapshot ล่าสุด (thread-safe copy)"""
        with self._lock:
            return self._snapshot

    def get_history(self, n: int = 60) -> list:
        """คืน history snapshots สำหรับ graph"""
        with self._lock:
            return list(self._history)[-n:]

    def get_latency_stats(self) -> LatencyStats:
        """คำนวณ latency statistics"""
        with self._lock:
            return self._compute_latency_stats()

    # ─── BACKGROUND LOOP ──────────────────────────────────────────────────

    def _monitor_loop(self) -> None:
        logger.info("SystemMonitor loop started")
        process = psutil.Process()

        while not self._shutdown_event.is_set():
            try:
                snap = self._collect_snapshot(process)
                with self._lock:
                    self._snapshot = snap
                    self._history.append(snap)
            except Exception as e:
                logger.debug(f"SystemMonitor error: {e}")

            self._shutdown_event.wait(self._update_interval)

        logger.info("SystemMonitor loop ended")

    def _collect_snapshot(self, process: psutil.Process) -> SystemSnapshot:
        """เก็บ metrics ทั้งหมดใน snapshot เดียว"""
        snap = SystemSnapshot()
        snap.timestamp = time.time()

        # CPU / Memory
        try:
            snap.cpu_percent    = psutil.cpu_percent(interval=None)
            mem_info            = process.memory_info()
            snap.memory_mb      = mem_info.rss / (1024 * 1024)
            snap.memory_percent = psutil.virtual_memory().percent
        except Exception:
            pass

        # Thread count
        try:
            snap.thread_count = threading.active_count()
        except Exception:
            pass

        # Queue depths
        try:
            if self._ingestion_queue:
                snap.ingestion_queue = self._ingestion_queue.qsize()
            if self._signal_queue:
                snap.signal_queue    = self._signal_queue.qsize()
            if self._feedback_queue:
                snap.feedback_queue  = self._feedback_queue.qsize()
        except Exception:
            pass

        # Latency + Throughput (ต้องการ lock)
        with self._lock:
            snap.latency    = self._compute_latency_stats()
            snap.throughput = self._compute_throughput()

        return snap

    def _compute_latency_stats(self) -> LatencyStats:
        stats = LatencyStats()
        samples = list(self._latency_samples)

        if not samples:
            return stats

        stats.sample_count = len(samples)
        stats.current_ms   = samples[-1]
        stats.avg_ms       = sum(samples) / len(samples)
        stats.min_ms       = min(samples)
        stats.max_ms       = max(samples)

        # P95
        sorted_samples = sorted(samples)
        p95_idx = int(len(sorted_samples) * 0.95)
        stats.p95_ms = sorted_samples[min(p95_idx, len(sorted_samples) - 1)]

        return stats

    def _compute_throughput(self) -> ThroughputStats:
        stats = ThroughputStats()
        now   = time.time()
        window_secs = 10.0  # คำนวณ rate ใน 10 วินาทีที่ผ่านมา

        stats.total_ticks   = self._total_ticks
        stats.total_signals = self._total_signals
        stats.total_trades  = self._total_trades

        # Ticks/sec
        recent_ticks = [t for t in self._tick_times if now - t <= window_secs]
        stats.ticks_per_sec = len(recent_ticks) / window_secs

        # Signals/sec
        recent_signals = [t for t in self._signal_times if now - t <= window_secs]
        stats.signals_per_sec = len(recent_signals) / window_secs

        # Trades/min
        recent_trades = [t for t in self._trade_times if now - t <= 60.0]
        stats.trades_per_min = len(recent_trades)

        return stats


# ─────────────────────────────────────────────────────────────────────────────
# FACTORY
# ─────────────────────────────────────────────────────────────────────────────

def create_system_monitor(sample_window: int = 100) -> SystemMonitor:
    """สร้าง SystemMonitor พร้อมใช้งาน"""
    return SystemMonitor(sample_window=sample_window)
