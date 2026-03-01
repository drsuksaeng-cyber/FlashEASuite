#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Main Orchestrator (V2.1 — with Emergency + Dashboard)
Program B: The Brain

เพิ่ม Phase 0-3:
- EmergencySystem: ป้องกัน 8 เงื่อนไขอันตราย
- SystemMonitor: ติดตาม CPU/Memory/Latency
- LiveDashboard: แสดงสถานะ real-time

Architecture:
  Worker 1: Ingestion    (ZMQ SUB 7777) → ingestion_queue
  Worker 2: Strategy     (ingestion_queue → signal_queue → ZMQ PUB 7778)
  Worker 3: Execution    (ZMQ PULL 7779 → feedback_queue)
  Worker 4: Emergency    (background monitor, check every 1s)
  Worker 5: Dashboard    (background refresh, display every 1s)
  Worker 6: SysMonitor   (background collect, collect every 1s)

Author: Dr. Suksaeng Kukanok
Version: 2.1.0 (Phase 0-3: Emergency + Dashboard)
Date: 2026-02-18
"""

import threading
import queue
import signal
import sys
import time
import logging
from typing import Optional

# Existing workers
from core.ingestion import create_ingestion_worker_threaded
from core.strategy import create_strategy_engine_threaded
from core.execution_listener import create_execution_listener_threaded

# Phase 0-3: New components
from core.emergency_system import (
    create_emergency_system, EmergencySystem,
    EmergencyLevel, EmergencyEvent
)
from core.system_monitor import create_system_monitor, SystemMonitor
from dashboard import create_dashboard, LiveDashboard

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

EMERGENCY_CONFIG = {
    "max_drawdown_pct":           20.0,
    "daily_loss_pct":              5.0,
    "consecutive_losses_max":      5,
    "volatility_multiplier":       3.0,
    "system_cpu_threshold":       90.0,
    "system_mem_threshold":       90.0,
    "correlation_threshold":       0.80,
    "consecutive_loss_pause_mins": 60,
    "news_pause_mins":             15,
    "connection_timeout_secs":    30.0,
    "check_interval_secs":         1.0,
}

ZMQ_ADDRESSES = {
    "feeder_sub":  "tcp://127.0.0.1:7777",  # รับ tick จาก Feeder
    "brain_pub":   "tcp://127.0.0.1:7778",  # ส่ง policy ไป Trader
    "trader_pull": "tcp://127.0.0.1:7779",  # รับ results จาก Trader
}

DASHBOARD_ENABLED  = True   # ตั้ง False ถ้าไม่ต้องการ UI
DASHBOARD_REFRESH  = 1.0    # วินาที


# ─────────────────────────────────────────────────────────────────────────────
# MAIN BRAIN CLASS
# ─────────────────────────────────────────────────────────────────────────────

class FlashEABrain:
    """
    Main orchestrator for FlashEA Brain

    V2.1 เพิ่ม:
    - EmergencySystem: หยุดเทรดอัตโนมัติเมื่อพบความเสี่ยง
    - SystemMonitor: ติดตาม CPU/Memory/Latency
    - LiveDashboard: Terminal dashboard แบบ real-time

    Backward compatible: workers เดิมยังทำงานเหมือนเดิม
    """

    def __init__(self):
        # Threading infrastructure
        self.shutdown_event  = threading.Event()
        self.ingestion_queue = queue.Queue()
        self.signal_queue    = queue.Queue()
        self.feedback_queue  = queue.Queue()
        self.threads         = []

        # Phase 0-3: New components
        self.emergency: Optional[EmergencySystem] = None
        self.monitor:   Optional[SystemMonitor]   = None
        self.dashboard: Optional[LiveDashboard]   = None

        self._print_banner()

    def _print_banner(self) -> None:
        print("=" * 80)
        print("FlashEASuite V2 — Program B (The Brain) 🧠")
        print("High-Frequency Hybrid Trading System")
        print("Version: 2.1.0 (Phase 0-3: Emergency Safety + Live Dashboard)")
        print("=" * 80)
        print(f"  ZMQ Feeder:    {ZMQ_ADDRESSES['feeder_sub']}")
        print(f"  ZMQ Brain:     {ZMQ_ADDRESSES['brain_pub']}")
        print(f"  ZMQ Trader:    {ZMQ_ADDRESSES['trader_pull']}")
        print(f"  Emergency:     {'✅ ENABLED' if True else '❌ DISABLED'}")
        print(f"  Dashboard:     {'✅ ENABLED' if DASHBOARD_ENABLED else '❌ DISABLED'}")
        print("=" * 80)
        print()

    # ─── SETUP ────────────────────────────────────────────────────────────

    def _setup_emergency_system(self) -> None:
        """สร้างและตั้งค่า Emergency System"""

        def on_emergency_level_change(level: EmergencyLevel, event: Optional[EmergencyEvent]):
            """Callback เมื่อ emergency level เปลี่ยน"""
            if level == EmergencyLevel.HALT:
                logger.critical(f"🚨 TRADING HALTED: {event.message if event else 'Manual'}")
                # TODO: ส่ง COMMAND message ไปยัง Trader ผ่าน ZMQ
                # self._send_halt_command()
                if self.dashboard:
                    self.dashboard.add_alert(
                        f"⛔ HALT: {event.message if event else 'Manual halt'}",
                        "HALT"
                    )

            elif level == EmergencyLevel.PAUSE:
                logger.warning(f"⚠️ Trading PAUSED: {event.message if event else ''}")
                if self.dashboard:
                    self.dashboard.add_alert(
                        f"⚠️ PAUSE: {event.message if event else ''}",
                        "WARNING"
                    )

            elif level == EmergencyLevel.WARNING:
                logger.warning(f"⚡ Warning: {event.message if event else ''}")
                if self.dashboard:
                    self.dashboard.add_alert(
                        f"⚡ WARNING: {event.message if event else ''}",
                        "WARNING"
                    )

            elif level == EmergencyLevel.NORMAL:
                logger.info("✅ Trading RESUMED — all clear")
                if self.dashboard:
                    self.dashboard.add_alert("✅ Trading resumed — all clear", "INFO")

        self.emergency = create_emergency_system(
            on_level_change=on_emergency_level_change,
            **EMERGENCY_CONFIG
        )
        logger.info("✅ Emergency System configured")

    def _setup_system_monitor(self) -> None:
        """สร้าง System Monitor"""
        self.monitor = create_system_monitor(sample_window=200)
        self.monitor.set_queues(
            self.ingestion_queue,
            self.signal_queue,
            self.feedback_queue
        )
        logger.info("✅ System Monitor configured")

    def _setup_dashboard(self) -> None:
        """สร้าง Live Dashboard"""
        if not DASHBOARD_ENABLED:
            return

        self.dashboard = create_dashboard(
            emergency=self.emergency,
            monitor=self.monitor,
            refresh_rate=DASHBOARD_REFRESH
        )
        logger.info("✅ Dashboard configured")

    def _setup_signal_handlers(self) -> None:
        """Setup graceful shutdown"""
        def signal_handler(signum, frame):
            print("\n\n⚠️ Shutdown signal received. Stopping gracefully...")
            self.shutdown_event.set()

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

    # ─── START WORKERS ────────────────────────────────────────────────────

    def _start_workers(self) -> bool:
        """เริ่ม worker threads ทั้งหมด"""
        try:
            print("🚀 Starting worker threads...")

            # ── Worker 1: Ingestion ───────────────────────────────────────
            ingestion_thread = create_ingestion_worker_threaded(
                ingestion_queue=self.ingestion_queue,
                shutdown_event=self.shutdown_event,
                zmq_sub_address=ZMQ_ADDRESSES["feeder_sub"]
            )
            ingestion_thread.daemon = True
            ingestion_thread.start()
            self.threads.append(('IngestionWorker', ingestion_thread))
            print(f"  ✅ Ingestion Worker  → {ZMQ_ADDRESSES['feeder_sub']}")
            time.sleep(0.5)

            # ── Worker 2: Strategy Engine ─────────────────────────────────
            strategy_thread = create_strategy_engine_threaded(
                ingestion_queue=self.ingestion_queue,
                signal_queue=self.signal_queue,
                feedback_queue=self.feedback_queue,
                shutdown_event=self.shutdown_event,
                zmq_pub_address=ZMQ_ADDRESSES["brain_pub"]
            )
            strategy_thread.daemon = True
            strategy_thread.start()
            self.threads.append(('StrategyEngine', strategy_thread))
            print(f"  ✅ Strategy Engine   → {ZMQ_ADDRESSES['brain_pub']}")
            time.sleep(0.5)

            # ── Worker 3: Execution Listener ──────────────────────────────
            execution_thread = create_execution_listener_threaded(
                feedback_queue=self.feedback_queue,
                shutdown_event=self.shutdown_event,
                zmq_pull_address=ZMQ_ADDRESSES["trader_pull"]
            )
            execution_thread.daemon = True
            execution_thread.start()
            self.threads.append(('ExecutionListener', execution_thread))
            print(f"  ✅ Execution Listener← {ZMQ_ADDRESSES['trader_pull']}")
            time.sleep(0.5)

            # ── Worker 4: Emergency System ────────────────────────────────
            self.emergency.start()
            print(f"  ✅ Emergency Monitor (check every {EMERGENCY_CONFIG['check_interval_secs']:.1f}s)")

            # ── Worker 5: System Monitor ──────────────────────────────────
            self.monitor.start()
            print(f"  ✅ System Monitor    (interval 1.0s)")

            # ── Worker 6: Dashboard ───────────────────────────────────────
            if self.dashboard:
                self.dashboard.start(blocking=False)
                print(f"  ✅ Dashboard         (refresh {DASHBOARD_REFRESH:.1f}s)")
                self.dashboard.add_alert("🚀 FlashEASuite V2 Brain started", "INFO")
                self.dashboard.update_connection(
                    feeder=True, trader=False,
                    strategy="Initializing...", regime="UNKNOWN"
                )

            print(f"\n✅ All {len(self.threads)} worker threads started")
            print("=" * 80)
            print("🎯 System is running!")
            print("   📥 Receiving tick data from Feeder (7777)")
            print("   🧠 Generating trading signals")
            print("   📤 Sending policies to Trader (7778)")
            print("   🔄 Feedback loop active (7779)")
            print("   🚨 Emergency safety system active")
            if DASHBOARD_ENABLED:
                print("   📊 Live dashboard running")
            print("=" * 80)
            print("Press Ctrl+C to stop.")
            print()

            return True

        except Exception as e:
            print(f"❌ Error starting workers: {e}")
            import traceback
            traceback.print_exc()
            return False

    # ─── MONITOR LOOP ─────────────────────────────────────────────────────

    def _monitor_threads(self) -> None:
        """Main thread: ตรวจสอบ thread health + update dashboard"""
        while not self.shutdown_event.is_set():
            time.sleep(5)

            # Check thread health
            for name, thread in self.threads:
                if not thread.is_alive():
                    logger.warning(f"⚠️ Thread {name} died!")
                    if self.dashboard:
                        self.dashboard.add_alert(f"⚠️ Thread {name} died!", "WARNING")

            # อัปเดต connection status ไป dashboard
            if self.dashboard:
                # TODO: ตรวจสอบ connection จาก ZMQ heartbeat จริงๆ
                # ตอนนี้ assume connected ถ้า threads ยังทำงาน
                ingestion_alive = any(
                    t.is_alive() for n, t in self.threads if n == 'IngestionWorker'
                )
                execution_alive = any(
                    t.is_alive() for n, t in self.threads if n == 'ExecutionListener'
                )
                self.dashboard.update_connection(
                    feeder=ingestion_alive,
                    trader=execution_alive
                )

            # Log queue sizes ถ้าใหญ่เกินไป
            q_sizes = {
                "Ingestion": self.ingestion_queue.qsize(),
                "Signal":    self.signal_queue.qsize(),
                "Feedback":  self.feedback_queue.qsize()
            }
            for name, size in q_sizes.items():
                if size > 100:
                    logger.warning(f"⚠️ Queue {name} depth={size}")
                    self.emergency.update_connection_status(
                        feeder_connected=True,
                        trader_connected=True
                    )

    # ─── CLEANUP ──────────────────────────────────────────────────────────

    def _cleanup(self) -> None:
        """Graceful shutdown ทุก component"""
        print("\n🧹 Shutting down components...")

        # หยุด workers
        self.shutdown_event.set()

        # หยุด Phase 0-3 components
        if self.dashboard:
            self.dashboard.stop()
            print("  ✅ Dashboard stopped")

        if self.monitor:
            self.monitor.stop()
            print("  ✅ System Monitor stopped")

        if self.emergency:
            self.emergency.stop()
            print("  ✅ Emergency System stopped")

        # รอ worker threads
        print("⏳ Waiting for workers...")
        for name, thread in self.threads:
            thread.join(timeout=3.0)
            status = "✅" if not thread.is_alive() else "⚠️ (timeout)"
            print(f"  {status} {name}")

        # Drain queues
        for q in [self.ingestion_queue, self.signal_queue, self.feedback_queue]:
            while not q.empty():
                try:
                    q.get_nowait()
                except queue.Empty:
                    break

        print("✅ Cleanup complete")

    # ─── MAIN RUN ─────────────────────────────────────────────────────────

    def run(self) -> None:
        """Main entry point"""
        try:
            self._setup_signal_handlers()
            self._setup_emergency_system()
            self._setup_system_monitor()
            self._setup_dashboard()

            if not self._start_workers():
                print("❌ Failed to start. Exiting.")
                return

            self._monitor_threads()

        except KeyboardInterrupt:
            print("\n\n⚠️ Keyboard interrupt")

        except Exception as e:
            print(f"\n❌ Unexpected error: {e}")
            import traceback
            traceback.print_exc()

        finally:
            self._cleanup()
            print("\n👋 FlashEA Brain stopped")


# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S"
    )
    brain = FlashEABrain()
    brain.run()


if __name__ == "__main__":
    main()
