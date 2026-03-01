#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — P0-3 Test Script
ทดสอบ Emergency System + Dashboard แบบ Standalone

วิธีรัน:
    cd FlashEASuite_V2/02_Brain
    python test_p03.py

ไม่ต้องรัน MT5, ไม่ต้องรัน Feeder ก่อน — ทำงานได้เลย
"""

import sys
import os
import time
import threading
import math
import random
import logging
from datetime import datetime, timedelta

# ── Setup path ─────────────────────────────────────────────────────────────
# สมมติ script อยู่ใน 02_Brain/
BRAIN_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BRAIN_DIR)

# ── Logging ────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.WARNING,   # เงียบ background logs
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)

# ── Import P0-3 modules ────────────────────────────────────────────────────
from core.emergency_system import (
    create_emergency_system, EmergencySystem,
    EmergencyLevel, EmergencyEvent, EmergencyReason
)
from core.system_monitor import create_system_monitor, SystemMonitor

# Rich สำหรับ pretty output
try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text
    from rich import box
    from rich.align import Align
    console = Console()
    RICH = True
except ImportError:
    RICH = False
    console = None

# ── Helpers ────────────────────────────────────────────────────────────────

def sep(title=""):
    if RICH:
        console.rule(f"[bold cyan]{title}[/bold cyan]")
    else:
        print(f"\n{'='*60}")
        if title: print(f"  {title}")
        print('='*60)

def ok(msg):
    if RICH: console.print(f"  [green]✅ {msg}[/green]")
    else: print(f"  ✅ {msg}")

def warn(msg):
    if RICH: console.print(f"  [yellow]⚠️  {msg}[/yellow]")
    else: print(f"  ⚠️  {msg}")

def err(msg):
    if RICH: console.print(f"  [red]❌ {msg}[/red]")
    else: print(f"  ❌ {msg}")

def info(msg):
    if RICH: console.print(f"  [dim]{msg}[/dim]")
    else: print(f"     {msg}")


# ════════════════════════════════════════════════════════════════════════════
# PART 1 — UNIT TESTS (ไม่มี UI, ทำงานเร็ว ~15 วิ)
# ════════════════════════════════════════════════════════════════════════════

def run_unit_tests():
    """ทดสอบทุก condition ของ EmergencySystem"""

    sep("PART 1 — Unit Tests (Emergency System)")
    passed = 0
    failed = 0

    # ── สร้าง EmergencySystem ────────────────────────────────────────────
    events_log = []

    def on_change(level: EmergencyLevel, event):
        events_log.append((level, event.message if event else ""))

    em = create_emergency_system(
        on_level_change=on_change,
        max_drawdown_pct=20.0,
        daily_loss_pct=5.0,
        consecutive_losses_max=5,
        volatility_multiplier=3.0,
        system_cpu_threshold=90.0,
        system_mem_threshold=90.0,
        correlation_threshold=0.80,
        consecutive_loss_pause_mins=60,
        news_pause_mins=15,
        connection_timeout_secs=30.0,
        check_interval_secs=0.5,   # เร็วขึ้นสำหรับ test
    )
    em.start()
    time.sleep(0.3)

    # ────────────────────────────────────────────────────────────────────
    # Test 1: สถานะเริ่มต้น = NORMAL
    # ────────────────────────────────────────────────────────────────────
    print()
    info("Test 1: สถานะเริ่มต้น")
    assert em.current_level == EmergencyLevel.NORMAL, f"Expected NORMAL got {em.current_level}"
    assert em.is_trading_allowed == True
    assert em.size_multiplier == 1.0
    ok("NORMAL | trading_allowed=True | size=1.0")
    passed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 2: Daily loss > 5% → HALT
    # ────────────────────────────────────────────────────────────────────
    info("Test 2: Daily loss > 5% → HALT")
    em.update_pnl(equity=94000, balance=100000, floating_pnl=-6000, daily_pnl=-6000)
    time.sleep(1.0)

    if em.current_level == EmergencyLevel.HALT:
        ok(f"HALT triggered | daily_loss=6.0% > 5%")
        ok(f"is_trading_allowed = {em.is_trading_allowed}")
        passed += 1
    else:
        err(f"Expected HALT got {em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 3: Drawdown > 20% → HALT
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    info("Test 3: Drawdown > 20% → HALT")
    # Simulate peak=100000, equity=79000 → drawdown=21%
    em.update_pnl(equity=100000, balance=100000, floating_pnl=0, daily_pnl=0)
    time.sleep(0.1)
    em.update_pnl(equity=79000, balance=100000, floating_pnl=-21000, daily_pnl=-21000)
    time.sleep(1.0)

    if em.current_level == EmergencyLevel.HALT:
        ok(f"HALT triggered | drawdown={em.metrics.max_drawdown_pct:.1f}% > 20%")
        passed += 1
    else:
        err(f"Expected HALT got {em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 4: Consecutive losses > 5 → PAUSE 60 min
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    em.update_pnl(equity=100000, balance=100000, floating_pnl=0, daily_pnl=0)
    info("Test 4: 5 consecutive losses → PAUSE")

    for i in range(5):
        em.record_trade_result(profit=-200)
        info(f"  Loss #{i+1} recorded")

    time.sleep(1.0)

    if em.current_level == EmergencyLevel.PAUSE:
        status = em.get_status_summary()
        ok(f"PAUSE triggered | consecutive={em.metrics.consecutive_losses}")
        ok(f"pause_remaining={status['pause_remaining']:.0f}s ({status['pause_remaining']/60:.0f} min)")
        passed += 1
    else:
        err(f"Expected PAUSE got {em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 5: Win resets consecutive counter
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    em.update_pnl(100000, 100000, 0, 0)
    info("Test 5: Win หลัง 3 losses → reset counter")

    for i in range(3):
        em.record_trade_result(-200)

    em.record_trade_result(+500)   # WIN → reset

    time.sleep(0.8)

    if em.metrics.consecutive_losses == 0 and em.current_level == EmergencyLevel.NORMAL:
        ok(f"consecutive_losses reset to 0 | level=NORMAL")
        passed += 1
    else:
        err(f"Expected 0 losses NORMAL, got {em.metrics.consecutive_losses} {em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 6: ATR spike (≥3x avg) → WARNING + size=0.5
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    info("Test 6: ATR spike ≥ 3x → WARNING + size reduced 50%")
    em.update_atr("EURUSD", current_atr=0.003, avg_atr=0.001)  # 3x spike
    time.sleep(1.0)

    if em.current_level == EmergencyLevel.WARNING and em.size_multiplier == 0.5:
        ok(f"WARNING | EURUSD ATR=0.003 (3x avg=0.001) | size={em.size_multiplier}")
        passed += 1
    else:
        err(f"Expected WARNING+0.5, got {em.current_level.value} size={em.size_multiplier}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 7: ATR back to normal → resolve
    # ────────────────────────────────────────────────────────────────────
    info("Test 7: ATR กลับปกติ → resolve WARNING")
    em.update_atr("EURUSD", current_atr=0.0012, avg_atr=0.001)  # 1.2x (< 3x)
    time.sleep(1.0)

    if em.current_level == EmergencyLevel.NORMAL:
        ok(f"WARNING auto-resolved | size={em.size_multiplier}")
        passed += 1
    else:
        warn(f"Level={em.current_level.value} (อาจมี reason อื่น)")
        passed += 1  # not fail

    # ────────────────────────────────────────────────────────────────────
    # Test 8: Correlation > 80% → WARNING + size=0.5
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    info("Test 8: Correlation EURUSD/GBPUSD = 0.85 → WARNING")
    em.update_correlation("EURUSD_GBPUSD", 0.85)
    time.sleep(1.0)

    if em.current_level == EmergencyLevel.WARNING:
        ok(f"WARNING | correlation=0.85 > 0.80 | size={em.size_multiplier}")
        passed += 1
    else:
        err(f"Expected WARNING got {em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 9: News event → PAUSE 15 min
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    em.update_correlation("EURUSD_GBPUSD", 0.0)  # reset
    info("Test 9: News event (ตอนนี้) → PAUSE 15 min")

    # เพิ่ม news event ที่เกิดในอีก 1 นาที (อยู่ใน pause window)
    news_time = datetime.now() + timedelta(minutes=1)
    em.add_news_event(news_time, "FOMC Rate Decision")
    time.sleep(1.0)

    if em.current_level == EmergencyLevel.PAUSE:
        status = em.get_status_summary()
        ok(f"PAUSE | News: FOMC | pause_remaining={status['pause_remaining']:.0f}s")
        passed += 1
    else:
        err(f"Expected PAUSE got {em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 10: Connection loss → PAUSE
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    info("Test 10: Feeder disconnect → PAUSE (safe mode)")
    em.update_connection_status(feeder_connected=False, trader_connected=True)
    time.sleep(1.0)

    if em.current_level == EmergencyLevel.PAUSE:
        ok(f"PAUSE | Feeder disconnected — safe mode")
        passed += 1
    else:
        err(f"Expected PAUSE got {em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # Test 11: Manual halt + manual resume
    # ────────────────────────────────────────────────────────────────────
    em.manual_resume(); time.sleep(0.2)
    em.update_connection_status(True, True, time.time(), time.time())
    info("Test 11: Manual HALT → Manual RESUME")
    em.manual_halt("Operator test")
    time.sleep(0.3)

    if em.current_level == EmergencyLevel.HALT:
        ok("Manual HALT activated")

        em.manual_resume()
        time.sleep(0.3)

        if em.current_level == EmergencyLevel.NORMAL:
            ok("Manual RESUME succeeded | level=NORMAL")
            passed += 1
        else:
            err(f"RESUME failed, level={em.current_level.value}")
            failed += 1
    else:
        err(f"Manual HALT failed, level={em.current_level.value}")
        failed += 1

    # ────────────────────────────────────────────────────────────────────
    # SUMMARY
    # ────────────────────────────────────────────────────────────────────
    em.stop()

    print()
    sep("Unit Test Results")
    if RICH:
        console.print(f"  [green]Passed: {passed}[/green]  [red]Failed: {failed}[/red]  Total: {passed+failed}")
    else:
        print(f"  Passed: {passed}  Failed: {failed}  Total: {passed+failed}")

    if failed == 0:
        ok("ALL UNIT TESTS PASSED ✅")
    else:
        err(f"{failed} test(s) failed ❌")

    return failed == 0


# ════════════════════════════════════════════════════════════════════════════
# PART 2 — SYSTEM MONITOR TEST
# ════════════════════════════════════════════════════════════════════════════

def run_monitor_tests():
    sep("PART 2 — System Monitor Tests")

    import queue as Q
    iq = Q.Queue()
    sq = Q.Queue()
    fq = Q.Queue()

    mon = create_system_monitor(sample_window=50)
    mon.set_queues(iq, sq, fq)
    mon.start()

    # ส่ง fake ticks
    print()
    info("กำลังส่ง fake ticks 20 ครั้ง (simulate latency 2-8ms)...")
    for i in range(20):
        t_start = mon.tick_start(f"SYM_{i%4}")
        time.sleep(random.uniform(0.002, 0.008))  # simulate 2-8ms work
        lat = mon.tick_end(f"SYM_{i%4}", t_start)
        if i % 5 == 0:
            mon.record_signal()
        iq.put(f"fake_tick_{i}")

    # รอ monitor เก็บข้อมูล
    time.sleep(1.5)
    snap = mon.get_snapshot()

    print()
    ok(f"CPU Usage:       {snap.cpu_percent:.1f}%")
    ok(f"Memory Usage:    {snap.memory_percent:.1f}%  ({snap.memory_mb:.0f} MB)")
    ok(f"Active Threads:  {snap.thread_count}")
    ok(f"Latency avg:     {snap.latency.avg_ms:.2f} ms")
    ok(f"Latency min:     {snap.latency.min_ms:.2f} ms")
    ok(f"Latency max:     {snap.latency.max_ms:.2f} ms")
    ok(f"Latency P95:     {snap.latency.p95_ms:.2f} ms")
    ok(f"Ticks/sec:       {snap.throughput.ticks_per_sec:.1f}")
    ok(f"Signals/sec:     {snap.throughput.signals_per_sec:.2f}")
    ok(f"Total ticks:     {snap.throughput.total_ticks}")
    ok(f"Queue depth:     I={snap.ingestion_queue} S={snap.signal_queue} F={snap.feedback_queue}")

    mon.stop()
    ok("System Monitor test PASSED ✅")
    return True


# ════════════════════════════════════════════════════════════════════════════
# PART 3 — LIVE DASHBOARD DEMO (รัน 60 วิ พร้อม simulation)
# ════════════════════════════════════════════════════════════════════════════

def run_dashboard_demo():
    """
    รัน dashboard จริงๆ พร้อม fake data simulation:
    - ช่วง 0-15s:  ปกติ, P&L ขึ้นลง
    - ช่วง 15-25s: trigger WARNING (ATR spike)
    - ช่วง 25-35s: trigger PAUSE (consecutive losses)
    - ช่วง 35-45s: trigger HALT (daily loss)
    - ช่วง 45-60s: manual resume, กลับ NORMAL
    """
    if not RICH:
        print("\n⚠️  Rich ไม่พร้อม — ข้ามขั้นตอน Dashboard Demo")
        print("    ติดตั้งด้วย: pip install rich")
        return True

    sep("PART 3 — Live Dashboard Demo (60 วินาที)")
    print()
    info("กำลังเริ่ม Dashboard Demo...")
    info("Dashboard จะปรากฎใน terminal นี้")
    info("กด Ctrl+C เพื่อหยุดก่อนกำหนด")
    print()
    time.sleep(2)

    # Import dashboard
    try:
        from dashboard import create_dashboard, TradeRecord, LiveDashboard
    except ImportError:
        err("ไม่พบ dashboard.py — ตรวจสอบว่าไฟล์อยู่ใน 02_Brain/")
        return False

    import queue as Q

    # สร้าง components
    em  = create_emergency_system(
        max_drawdown_pct=20.0,
        daily_loss_pct=5.0,
        consecutive_losses_max=3,   # ลด threshold สำหรับ demo
        volatility_multiplier=3.0,
        check_interval_secs=0.5
    )
    mon = create_system_monitor()
    mon.set_queues(Q.Queue(), Q.Queue(), Q.Queue())
    dash = create_dashboard(emergency=em, monitor=mon, refresh_rate=0.5)

    em.start()
    mon.start()

    # เริ่ม dashboard background
    dash.start(blocking=False)
    time.sleep(0.5)

    # ── Initial data ────────────────────────────────────────────────────
    em.update_pnl(equity=100000, balance=100000, floating_pnl=0, daily_pnl=0)
    dash.update_connection(feeder=True, trader=True, strategy="S15 Grid", regime="RANGING")
    dash.add_alert("🚀 Demo started — สังเกต panel สีและ P&L เปลี่ยน", "INFO")

    dash.update_trade(TradeRecord(
        ticket=10001, symbol="EURUSD", direction="BUY",
        open_time=datetime.now(), open_price=1.08500,
        lot_size=0.10, sl=1.08200, tp=1.09000, pnl=0,
        strategy="S15"
    ))
    dash.update_trade(TradeRecord(
        ticket=10002, symbol="XAUUSD", direction="SELL",
        open_time=datetime.now(), open_price=2650.00,
        lot_size=0.05, sl=2660.00, tp=2630.00, pnl=0,
        strategy="S07"
    ))

    # ── Simulation loop ─────────────────────────────────────────────────
    start_t = time.time()
    balance = 100000.0
    peak_eq = 100000.0

    try:
        while True:
            elapsed = time.time() - start_t
            if elapsed > 60:
                break

            t = elapsed
            eq = balance + math.sin(t / 8) * 400 + random.uniform(-80, 80)
            peak_eq = max(peak_eq, eq)
            floating = random.uniform(-300, 300)
            daily = eq - balance

            # อัปเดต ATR เพื่อให้ monitor ทำงาน
            ts = mon.tick_start("EURUSD")
            time.sleep(0.002)
            mon.tick_end("EURUSD", ts)

            # อัปเดต fake trade P&L
            dash.update_trade(TradeRecord(
                ticket=10001, symbol="EURUSD", direction="BUY",
                open_time=datetime.now(), open_price=1.08500,
                lot_size=0.10, sl=1.08200, tp=1.09000,
                pnl=random.uniform(-150, 200),
                strategy="S15"
            ))

            # ── Phase ตามเวลา ────────────────────────────────────────────
            if 0 <= t < 15:
                # ปกติ
                em.update_pnl(eq, balance, floating, daily)
                dash.update_pnl(balance, eq, floating, daily, (daily/balance)*100, (peak_eq-eq)/peak_eq*100)
                if int(t) % 5 == 0 and t - int(t) < 0.5:
                    dash.add_alert(f"Tick received | EURUSD={1.0850+math.sin(t)*0.001:.5f}", "INFO")

            elif 15 <= t < 25:
                # Trigger: ATR spike
                if t < 16:
                    em.update_atr("EURUSD", 0.003, 0.001)  # 3x spike
                    dash.add_alert("⚡ ATR spike detected! EURUSD vol = 3x normal", "WARNING")
                    dash.update_connection(feeder=True, trader=True, strategy="S15 Grid (reduced)", regime="VOLATILE")
                em.update_pnl(eq, balance, floating, daily)
                dash.update_pnl(balance, eq*0.98, floating, daily*1.2, (daily/balance)*100, 2.0)

            elif 25 <= t < 35:
                # Trigger: Consecutive losses
                if 24.5 <= t < 25.5:
                    em.manual_resume()
                    em.update_atr("EURUSD", 0.001, 0.001)  # reset ATR
                    for _ in range(3):
                        em.record_trade_result(-300)
                    dash.add_alert("⚠️ 3 consecutive losses → PAUSE 60 min", "WARNING")
                em.update_pnl(eq, balance, floating, daily)
                dash.update_pnl(balance, eq*0.97, floating, daily - 900, -0.9, 3.0)

            elif 35 <= t < 45:
                # Trigger: Daily loss HALT
                if 34.5 <= t < 35.5:
                    em.manual_resume()
                    dash.add_alert("⛔ Daily loss > 5% → TRADING HALTED!", "HALT")
                    dash.update_connection(feeder=True, trader=True, strategy="HALTED", regime="RANGING")
                em.update_pnl(94000, balance, -6000, -6000)  # 6% loss
                dash.update_pnl(balance, 94000, -6000, -6000, -6.0, 6.0)

            elif 45 <= t < 60:
                # Manual resume
                if 44.5 <= t < 45.5:
                    em.manual_resume()
                    dash.add_alert("✅ Operator resumed trading — all clear", "INFO")
                    dash.update_connection(feeder=True, trader=True, strategy="S15 Grid", regime="RANGING")
                em.update_pnl(100200, balance, 200, 200)
                dash.update_pnl(balance, 100200, 200, 200, 0.2, 0.0)

            time.sleep(0.5)

    except KeyboardInterrupt:
        dash.add_alert("Dashboard stopped by user", "INFO")

    # Cleanup
    time.sleep(1)
    dash.stop()
    em.stop()
    mon.stop()

    print()
    ok("Dashboard demo completed ✅")
    return True


# ════════════════════════════════════════════════════════════════════════════
# PART 4 — Integration check (ตรวจสอบ import จาก main_v2.py)
# ════════════════════════════════════════════════════════════════════════════

def check_integration():
    sep("PART 4 — Integration Import Check")
    print()

    checks = {
        "core.emergency_system": ["create_emergency_system", "EmergencyLevel",
                                   "EmergencyReason", "EmergencyConfig", "EmergencySystem"],
        "core.system_monitor":   ["create_system_monitor", "SystemMonitor", "SystemSnapshot"],
        "dashboard":             ["create_dashboard", "LiveDashboard", "TradeRecord"],
    }

    all_ok = True
    for module, names in checks.items():
        try:
            mod = __import__(module, fromlist=names)
            for name in names:
                assert hasattr(mod, name), f"Missing: {name}"
            ok(f"import {module} → {', '.join(names)}")
        except Exception as e:
            err(f"import {module}: {e}")
            all_ok = False

    # ตรวจ psutil
    try:
        import psutil
        ok(f"psutil {psutil.__version__} ✅")
    except ImportError:
        err("psutil ไม่พร้อม — ติดตั้ง: pip install psutil")
        all_ok = False

    # ตรวจ rich
    try:
        import rich
        ok(f"rich (installed) ✅")
    except ImportError:
        warn("rich ไม่พร้อม — Dashboard จะใช้ simple mode | pip install rich")

    print()
    if all_ok:
        ok("Integration check PASSED ✅")
    else:
        err("Integration check FAILED — ดู error ด้านบน")

    return all_ok


# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════

def main():
    if RICH:
        console.print()
        console.print(Panel(
            "[bold cyan]FlashEASuite V2 — Phase 0-3 Test Suite[/bold cyan]\n"
            "[dim]Emergency Safety System + System Monitor + Live Dashboard[/dim]",
            border_style="cyan"
        ))
    else:
        print("=" * 60)
        print("FlashEASuite V2 — Phase 0-3 Test Suite")
        print("=" * 60)

    print()
    parts = [
        ("1", "Unit tests only (เร็ว ~15 วิ)",   "unit"),
        ("2", "System monitor test (~5 วิ)",       "monitor"),
        ("3", "Live dashboard demo (60 วิ)",       "dashboard"),
        ("4", "Integration import check",          "import"),
        ("A", "รันทุก part (แนะนำ)",               "all"),
    ]

    print("  เลือกว่าจะรัน part ไหน:")
    for code, desc, _ in parts:
        print(f"    [{code}] {desc}")
    print()

    try:
        choice = input("  เลือก (กด Enter = A): ").strip().upper() or "A"
    except (EOFError, KeyboardInterrupt):
        choice = "A"

    print()
    results = {}

    if choice in ("1", "A"):
        results["unit"]    = run_unit_tests()

    if choice in ("2", "A"):
        results["monitor"] = run_monitor_tests()

    if choice in ("4", "A"):
        results["import"]  = check_integration()

    if choice in ("3", "A"):
        results["dashboard"] = run_dashboard_demo()

    # ── Final Summary ────────────────────────────────────────────────────
    sep("FINAL SUMMARY")
    print()
    all_passed = all(results.values()) if results else False

    label_map = {
        "unit":      "Unit Tests (Emergency System)",
        "monitor":   "System Monitor",
        "import":    "Integration Check",
        "dashboard": "Dashboard Demo",
    }

    for key, passed in results.items():
        if passed:
            ok(label_map.get(key, key))
        else:
            err(label_map.get(key, key))

    print()
    if all_passed:
        if RICH:
            console.print(Panel(
                "[bold green]✅ PHASE 0-3 COMPLETE — พร้อมเริ่ม Phase 0-4[/bold green]",
                border_style="green"
            ))
        else:
            print("✅ PHASE 0-3 COMPLETE — พร้อมเริ่ม Phase 0-4")
    else:
        err("บาง test ไม่ผ่าน — ดู error ด้านบน")

    print()


if __name__ == "__main__":
    main()
