#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Live Dashboard  v3.1 (P9-5 Update)
Program B (Brain) — Phase 0-3

การแก้ไข v3.1 (P9-5):
- Refresh rate default เปลี่ยนเป็น 5 วินาที (ตาม P9-5 spec)
- เพิ่ม last_config_push field ใน DashboardState
- เพิ่ม update_config_push() method
- System panel แสดง Last Config Push timestamp

การแก้ไข v3:
- Adaptive layout: terminal < 120 cols → vertical stack (no side-by-side)
- terminal >= 120 cols → wide side-by-side layout
- ลบ no_wrap=True ออกจาก panel columns → ไม่มี "..." อีก
- แก้ duplicate alerts ในตอน demo
- Header แสดงครบแม้ terminal แคบ

Author: Dr. Suksaeng Kukanok
Version: 3.1.0
Date: 2026-02-26
"""

import shutil
import threading
import time
import os
import math
import random
from datetime import datetime, timedelta
from typing import Optional, List
from dataclasses import dataclass, field

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.layout import Layout
    from rich.live import Live
    from rich.text import Text
    from rich.align import Align
    from rich import box
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False

# ── Emergency + Monitor imports ────────────────────────────────────────────
try:
    from .emergency_system import EmergencySystem, EmergencyLevel
    from .system_monitor import SystemMonitor, SystemSnapshot
except ImportError:
    import sys as _sys, os as _os
    _sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), 'core'))
    from emergency_system import EmergencySystem, EmergencyLevel
    from system_monitor import SystemMonitor, SystemSnapshot

import logging
logger = logging.getLogger(__name__)

# ── Layout breakpoints ─────────────────────────────────────────────────────
WIDE_MIN   = 140   # >= 140 → wide 3-column layout
MEDIUM_MIN = 100   # 100-139 → medium 2-column layout
# < 100 → narrow single-column vertical stack


# ─────────────────────────────────────────────────────────────────────────────
# DATA STRUCTURES
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class TradeRecord:
    ticket:      int
    symbol:      str
    direction:   str          # "BUY" | "SELL"
    open_time:   datetime
    open_price:  float
    lot_size:    float
    sl:          float
    tp:          float
    pnl:         float = 0.0
    close_time:  Optional[datetime] = None
    close_price: float = 0.0
    is_open:     bool  = True
    strategy:    str   = ""


@dataclass
class AlertRecord:
    timestamp: datetime
    level:     str
    message:   str


@dataclass
class DashboardState:
    balance:          float = 100000.0
    equity:           float = 100000.0
    floating_pnl:     float = 0.0
    daily_pnl:        float = 0.0
    daily_pnl_pct:    float = 0.0
    max_drawdown_pct: float = 0.0
    active_trades:    List[TradeRecord] = field(default_factory=list)
    closed_today:     List[TradeRecord] = field(default_factory=list)
    feeder_connected: bool  = False
    trader_connected: bool  = False
    active_strategy:  str   = "---"
    regime:           str   = "UNKNOWN"
    alerts:           List[AlertRecord] = field(default_factory=list)
    session_start:    datetime = field(default_factory=datetime.now)
    last_update:      datetime = field(default_factory=datetime.now)
    last_config_push: Optional[str] = None   # ISO timestamp of last CONFIG_PUSH sent
    last_config_cycle: str = "---"           # optimization_cycle label


# ─────────────────────────────────────────────────────────────────────────────
# LIVE DASHBOARD
# ─────────────────────────────────────────────────────────────────────────────

class LiveDashboard:
    """
    Terminal dashboard แบบ real-time
    - Wide (≥140):   Emergency | Account  ||  Trades        ||  System
    - Medium (≥100): Emergency+Account    ||  Trades+System
    - Narrow (<100): Vertical stack (ทุก panel ซ้อนกัน)
    """

    def __init__(
        self,
        emergency:    Optional[EmergencySystem] = None,
        monitor:      Optional[SystemMonitor]   = None,
        refresh_rate: float = 1.0
    ):
        self.emergency    = emergency
        self.monitor      = monitor
        self.refresh_rate = refresh_rate
        self._state       = DashboardState()
        self._lock        = threading.RLock()
        self._shutdown    = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._console: Optional[Console] = Console() if RICH_AVAILABLE else None
        logger.info("LiveDashboard v3 initialized")

    # ─── START / STOP ──────────────────────────────────────────────────────

    def start(self, blocking: bool = False) -> None:
        if not RICH_AVAILABLE:
            self._start_simple(blocking); return
        self._shutdown.clear()
        if blocking:
            self._run()
        else:
            self._thread = threading.Thread(target=self._run, name="Dashboard", daemon=True)
            self._thread.start()

    def stop(self) -> None:
        self._shutdown.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3.0)

    # ─── STATE API ─────────────────────────────────────────────────────────

    def update_pnl(self, balance, equity, floating_pnl, daily_pnl, daily_pnl_pct, drawdown_pct):
        with self._lock:
            s = self._state
            s.balance = balance; s.equity = equity
            s.floating_pnl = floating_pnl; s.daily_pnl = daily_pnl
            s.daily_pnl_pct = daily_pnl_pct; s.max_drawdown_pct = drawdown_pct
            s.last_update = datetime.now()

    def update_trade(self, trade: TradeRecord):
        with self._lock:
            existing = next((t for t in self._state.active_trades if t.ticket == trade.ticket), None)
            if existing:
                existing.pnl = trade.pnl
                if not trade.is_open:
                    self._state.active_trades.remove(existing)
                    self._state.closed_today.append(trade)
            elif trade.is_open:
                self._state.active_trades.append(trade)

    def update_connection(self, feeder: bool, trader: bool, strategy: str = "", regime: str = ""):
        with self._lock:
            self._state.feeder_connected = feeder
            self._state.trader_connected = trader
            if strategy: self._state.active_strategy = strategy
            if regime:   self._state.regime = regime

    def update_config_push(self, cycle_id: str = "", timestamp: Optional[str] = None):
        """เรียกทุกครั้งที่ Brain ส่ง CONFIG_PUSH สำเร็จ"""
        with self._lock:
            self._state.last_config_push = timestamp or datetime.now().strftime("%H:%M:%S")
            if cycle_id:
                self._state.last_config_cycle = cycle_id

    def add_alert(self, message: str, level: str = "INFO"):
        with self._lock:
            # ป้องกัน duplicate: ถ้า message เดียวกันใน 2 วิที่แล้ว ข้ามไป
            if self._state.alerts:
                last = self._state.alerts[-1]
                if (last.message == message and
                        (datetime.now() - last.timestamp).total_seconds() < 2.0):
                    return
            self._state.alerts.append(AlertRecord(datetime.now(), level, message))
            if len(self._state.alerts) > 50:
                self._state.alerts = self._state.alerts[-50:]

    # ─── RENDER LOOP ───────────────────────────────────────────────────────

    def _run(self):
        try:
            with Live(
                renderable=self._render(),
                console=self._console,
                refresh_per_second=max(1, int(1 / self.refresh_rate)),
                screen=True,
            ) as live:
                while not self._shutdown.is_set():
                    try:
                        live.update(self._render())
                    except Exception as e:
                        logger.debug(f"Render: {e}")
                    time.sleep(self.refresh_rate)
        except Exception as e:
            logger.error(f"Dashboard fatal: {e}")

    def _terminal_width(self) -> int:
        try:
            return shutil.get_terminal_size().columns
        except Exception:
            return 80

    def _render(self):
        """เลือก layout ตาม terminal width อัตโนมัติ"""
        w = self._terminal_width()
        if w >= WIDE_MIN:
            return self._layout_wide()
        elif w >= MEDIUM_MIN:
            return self._layout_medium()
        else:
            return self._layout_narrow()

    # ─── LAYOUT: WIDE (≥140) ───────────────────────────────────────────────

    def _layout_wide(self):
        layout = Layout()
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body",   ratio=1),
            Layout(name="alerts", size=10),
            Layout(name="footer", size=1),
        )
        layout["body"].split_row(
            Layout(name="col1", ratio=1),   # Emergency + Account
            Layout(name="col2", ratio=2),   # Trades
            Layout(name="col3", ratio=1),   # System
        )
        layout["col1"].split_column(
            Layout(name="emergency", ratio=1),
            Layout(name="account",   ratio=1),
        )
        layout["header"].update(self._panel_header())
        layout["emergency"].update(self._panel_emergency())
        layout["account"].update(self._panel_account())
        layout["col2"].update(self._panel_trades(wide=True))
        layout["col3"].update(self._panel_system())
        layout["alerts"].update(self._panel_alerts())
        layout["footer"].update(self._panel_footer())
        return layout

    # ─── LAYOUT: MEDIUM (100-139) ──────────────────────────────────────────

    def _layout_medium(self):
        layout = Layout()
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body",   ratio=1),
            Layout(name="alerts", size=9),
            Layout(name="footer", size=1),
        )
        layout["body"].split_row(
            Layout(name="left",  ratio=1),
            Layout(name="right", ratio=2),
        )
        layout["left"].split_column(
            Layout(name="emergency", ratio=1),
            Layout(name="account",   ratio=1),
        )
        layout["right"].split_column(
            Layout(name="trades", ratio=3),
            Layout(name="system", ratio=2),
        )
        layout["header"].update(self._panel_header())
        layout["emergency"].update(self._panel_emergency())
        layout["account"].update(self._panel_account())
        layout["trades"].update(self._panel_trades(wide=False))
        layout["system"].update(self._panel_system())
        layout["alerts"].update(self._panel_alerts())
        layout["footer"].update(self._panel_footer())
        return layout

    # ─── LAYOUT: NARROW (<100) — vertical stack ────────────────────────────

    def _layout_narrow(self):
        """
        Vertical stack — แต่ละ panel วางซ้อนกัน เห็นค่าทุกอย่าง
        ไม่มี side-by-side เลย
        """
        layout = Layout()
        layout.split_column(
            Layout(name="header",    size=3),
            Layout(name="emergency", size=10),
            Layout(name="account",   size=11),
            Layout(name="trades",    size=8),
            Layout(name="system",    size=10),
            Layout(name="alerts",    size=8),
            Layout(name="footer",    size=1),
        )
        layout["header"].update(self._panel_header_narrow())
        layout["emergency"].update(self._panel_emergency())
        layout["account"].update(self._panel_account())
        layout["trades"].update(self._panel_trades(wide=False))
        layout["system"].update(self._panel_system())
        layout["alerts"].update(self._panel_alerts())
        layout["footer"].update(self._panel_footer())
        return layout

    # ─── PANELS ────────────────────────────────────────────────────────────

    def _panel_header(self) -> Panel:
        with self._lock:
            feeder = self._state.feeder_connected
            trader = self._state.trader_connected
            strat  = self._state.active_strategy
            regime = self._state.regime

        r_col = {"TRENDING": "green", "RANGING": "cyan",
                  "VOLATILE": "red",  "SQUEEZE": "yellow"}.get(regime, "white")
        t = Text(justify="center")
        t.append("⚡ FlashEASuite V2", style="bold cyan")
        t.append("  │  ", style="dim")
        t.append(datetime.now().strftime("%H:%M:%S"), style="bold white")
        t.append("  │  ", style="dim")
        t.append(regime, style=f"bold {r_col}")
        t.append("  │  ", style="dim")
        t.append(strat[:18], style="white")
        t.append("  │  ", style="dim")
        t.append("●", style="green" if feeder else "red")
        t.append(" Feeder  ", style="dim")
        t.append("●", style="green" if trader else "red")
        t.append(" Trader", style="dim")
        return Panel(t, style="on grey15", padding=(0, 0))

    def _panel_header_narrow(self) -> Panel:
        """Header สั้นสำหรับ narrow terminal"""
        with self._lock:
            feeder = self._state.feeder_connected
            trader = self._state.trader_connected
            regime = self._state.regime

        r_col = {"TRENDING": "green", "RANGING": "cyan",
                  "VOLATILE": "red",  "SQUEEZE": "yellow"}.get(regime, "white")
        t = Text(justify="center")
        t.append("⚡ FlashEASuite V2", style="bold cyan")
        t.append(f"  {datetime.now().strftime('%H:%M:%S')}", style="dim")
        t.append("  ", style="")
        t.append("●F", style="green" if feeder else "red")
        t.append(" ", style="")
        t.append("●T", style="green" if trader else "red")
        t.append(f"  {regime}", style=f"bold {r_col}")
        return Panel(t, style="on grey15", padding=(0, 0))

    def _panel_emergency(self) -> Panel:
        if self.emergency:
            em       = self.emergency.get_status_summary()
            lv       = em["level"]
            draw     = em["drawdown_pct"]
            daily    = em["daily_pnl_pct"]
            consec   = em["consecutive_loss"]
            size_x   = em["size_multiplier"]
            trading  = em["trading_allowed"]
            reasons  = em["active_reasons"]
            pause    = em.get("pause_remaining", 0)
        else:
            with self._lock:
                s = self._state
            lv = "NORMAL"; draw = s.max_drawdown_pct; daily = s.daily_pnl_pct
            consec = 0; size_x = 1.0; trading = True; reasons = []; pause = 0

        lmap = {
            "NORMAL":   ("green",  "● NORMAL",   "green"),
            "WARNING":  ("yellow", "● WARNING",  "yellow"),
            "PAUSE":    ("orange1","● PAUSED",   "orange1"),
            "HALT":     ("red",    "● HALT",     "red"),
            "SHUTDOWN": ("red",    "● SHUTDOWN", "red"),
        }
        lcol, llabel, border = lmap.get(lv, lmap["NORMAL"])

        t = Table(show_header=False, box=None, padding=(0, 1), expand=True)
        t.add_column("K", style="dim", ratio=2)
        t.add_column("V", ratio=3)

        t.add_row("Status",   Text(llabel, style=f"bold {lcol}"))
        t.add_row("Drawdown", Text(f"{draw:.2f}%",
            style="red" if draw >= 20 else "yellow" if draw >= 10 else "green"))
        t.add_row("Daily",    Text(f"{daily:+.2f}%",
            style="red" if daily <= -5 else "yellow" if daily <= -2 else "green"))
        t.add_row("Consec",   Text(str(consec),
            style="red" if consec >= 5 else "yellow" if consec >= 3 else "green"))
        t.add_row("Size ×",   Text(f"{size_x:.2f}",
            style="red" if size_x < 1.0 else "green"))

        if not trading and pause > 0:
            t.add_row("Resume in", Text(f"{int(pause//60)}m {int(pause%60)}s", style="yellow"))

        for r in reasons[:2]:
            t.add_row("⚠", Text(r.replace("_", " "), style="yellow"))

        return Panel(t, title=f"[{lcol}]🚨 Emergency[/{lcol}]",
                     border_style=border, padding=(0, 0))

    def _panel_account(self) -> Panel:
        with self._lock:
            s = self._state

        wins   = sum(1 for tr in s.closed_today if tr.pnl > 0)
        losses = sum(1 for tr in s.closed_today if tr.pnl < 0)
        wr     = (wins / max(1, wins + losses)) * 100
        sess_m = int((datetime.now() - s.session_start).total_seconds() / 60)

        t = Table(show_header=False, box=None, padding=(0, 1), expand=True)
        t.add_column("K", style="dim", ratio=2)
        t.add_column("V", ratio=3)

        t.add_row("Balance", Text(f"${s.balance:,.0f}", style="white"))
        t.add_row("Equity",  Text(f"${s.equity:,.0f}",
            style="green" if s.equity >= s.balance else "red"))
        t.add_row("Float",   Text(f"${s.floating_pnl:+,.0f}",
            style="green" if s.floating_pnl >= 0 else "red"))
        t.add_row("Daily $", Text(f"${s.daily_pnl:+,.0f}",
            style="green" if s.daily_pnl >= 0 else "red"))
        t.add_row("Daily %", Text(f"{s.daily_pnl_pct:+.2f}%",
            style="green" if s.daily_pnl_pct >= 0 else "red"))
        t.add_row("Max DD",  Text(f"{s.max_drawdown_pct:.2f}%",
            style="red" if s.max_drawdown_pct > 10 else
                  "yellow" if s.max_drawdown_pct > 5 else "green"))
        t.add_row("W/L",     Text(f"{wins}W {losses}L {wr:.0f}%",
            style="green" if wr >= 50 else "red"))
        t.add_row("Session", Text(f"{sess_m}m", style="dim"))

        return Panel(t, title="[cyan]💰 Account[/cyan]",
                     border_style="cyan", padding=(0, 0))

    def _panel_trades(self, wide: bool = False) -> Panel:
        with self._lock:
            trades = list(self._state.active_trades)

        t = Table(
            box=box.SIMPLE,
            show_header=True,
            header_style="bold dim",
            expand=True,
            padding=(0, 1),
        )

        if wide:
            # Wide: แสดง SL/TP ด้วย
            t.add_column("#",      width=7,  justify="right")
            t.add_column("Symbol", width=8)
            t.add_column("Dir",    width=5,  justify="center")
            t.add_column("Lot",    width=5,  justify="right")
            t.add_column("Open",   width=10, justify="right")
            t.add_column("SL",     width=10, justify="right")
            t.add_column("TP",     width=10, justify="right")
            t.add_column("P&L",    width=10, justify="right")
            t.add_column("Strat",  ratio=1)
        else:
            # Medium/Narrow: compact
            t.add_column("#",      width=7,  justify="right")
            t.add_column("Symbol", width=7)
            t.add_column("Dir",    width=5,  justify="center")
            t.add_column("Lot",    width=5,  justify="right")
            t.add_column("Open",   width=9,  justify="right")
            t.add_column("P&L",    width=9,  justify="right")
            t.add_column("Strat",  ratio=1)

        if not trades:
            cols = 9 if wide else 7
            row  = ["—"] * (cols - 1) + [Text("No active trades", style="dim")]
            t.add_row(*row)
        else:
            for tr in trades:
                d_col = "green" if tr.direction == "BUY" else "red"
                p_col = "green" if tr.pnl >= 0 else "red"
                if wide:
                    t.add_row(
                        str(tr.ticket), tr.symbol,
                        Text(tr.direction, style=d_col),
                        f"{tr.lot_size:.2f}",
                        f"{tr.open_price:.4f}",
                        f"{tr.sl:.4f}" if tr.sl else "—",
                        f"{tr.tp:.4f}" if tr.tp else "—",
                        Text(f"${tr.pnl:+.1f}", style=p_col),
                        tr.strategy[:10],
                    )
                else:
                    t.add_row(
                        str(tr.ticket), tr.symbol,
                        Text(tr.direction, style=d_col),
                        f"{tr.lot_size:.2f}",
                        f"{tr.open_price:.4f}",
                        Text(f"${tr.pnl:+.1f}", style=p_col),
                        tr.strategy[:8],
                    )

        n         = len(trades)
        total_pnl = sum(tr.pnl for tr in trades)
        title     = Text()
        title.append("📊 Trades ", style="cyan")
        title.append(f"({n})", style="bold cyan")
        if n > 0:
            title.append("  Float: ", style="dim")
            title.append(f"${total_pnl:+.1f}",
                         style="green" if total_pnl >= 0 else "red")
        return Panel(t, title=title, border_style="cyan", padding=(0, 0))

    def _panel_system(self) -> Panel:
        snap = self.monitor.get_snapshot() if self.monitor else SystemSnapshot()

        with self._lock:
            last_push  = self._state.last_config_push or "---"
            last_cycle = self._state.last_config_cycle
            feeder_ok  = self._state.feeder_connected
            trader_ok  = self._state.trader_connected

        t = Table(show_header=False, box=None, padding=(0, 1), expand=True)
        t.add_column("K",   style="dim",      width=9)
        t.add_column("Num", justify="right",  width=9)
        t.add_column("Bar", ratio=1)

        def row(label, val_str, pct, max_v=100, crit=90, warn=70):
            col = "red" if pct >= crit else "yellow" if pct >= warn else "green"
            return label, Text(val_str, style=col), self._bar(pct, max_v)

        t.add_row(*row("CPU",     f"{snap.cpu_percent:.1f}%",       snap.cpu_percent))
        t.add_row(*row("Memory",  f"{snap.memory_percent:.1f}%",    snap.memory_percent))
        t.add_row(*row("Latency", f"{snap.latency.avg_ms:.1f}ms",   snap.latency.avg_ms,  50, 20, 10))
        t.add_row(*row("P95",     f"{snap.latency.p95_ms:.1f}ms",   snap.latency.p95_ms,  50, 30, 15))
        t.add_row(*row("Ticks/s", f"{snap.throughput.ticks_per_sec:.1f}",
                                  min(snap.throughput.ticks_per_sec, 100)))

        qi = snap.ingestion_queue; qs = snap.signal_queue; qf = snap.feedback_queue
        qmax = max(qi, qs, qf, 1)
        t.add_row("Queues",
                  Text(f"I:{qi} S:{qs} F:{qf}",
                       style="red" if qmax > 100 else "yellow" if qmax > 50 else "green"),
                  Text(""))
        t.add_row("Threads", Text(str(snap.thread_count), style="dim"), Text(""))

        # ZMQ status
        zmq_col = "green" if feeder_ok and trader_ok else "yellow" if feeder_ok or trader_ok else "red"
        zmq_str = f"{'●' if feeder_ok else '○'}F  {'●' if trader_ok else '○'}T"
        t.add_row("ZMQ",  Text(zmq_str, style=zmq_col), Text(""))

        # Last config push
        t.add_row("CfgPush", Text(last_push, style="cyan"), Text(""))
        if last_cycle != "---":
            t.add_row("Cycle", Text(last_cycle[:12], style="dim"), Text(""))

        return Panel(t, title="[cyan]⚡ System[/cyan]",
                     border_style="cyan", padding=(0, 0))

    def _panel_alerts(self) -> Panel:
        with self._lock:
            alerts = list(self._state.alerts[-7:])

        t = Table(
            box=None, show_header=True,
            header_style="bold dim",
            expand=True, padding=(0, 1),
        )
        t.add_column("Time",    width=8, no_wrap=True)
        t.add_column("Level",   width=8, no_wrap=True)
        t.add_column("Message", ratio=1)   # ← ratio แทน fixed width → ไม่มี "..."

        lmap = {"INFO": "dim", "WARNING": "yellow", "HALT": "bold red", "ERROR": "red"}

        if not alerts:
            t.add_row("—", "—", Text("No alerts yet", style="dim"))
        else:
            for a in reversed(alerts):
                sty = lmap.get(a.level, "white")
                t.add_row(
                    Text(a.timestamp.strftime("%H:%M:%S"), style="dim"),
                    Text(a.level, style=sty),
                    Text(a.message, style=sty),   # ← จะ wrap อัตโนมัติถ้าแคบ ไม่ตัด
                )

        return Panel(t, title="[yellow]🔔 Alerts[/yellow]",
                     border_style="yellow", padding=(0, 0))

    def _panel_footer(self) -> Text:
        t = Text(justify="center")
        t.append("[Q]", style="bold cyan");  t.append(" Quit  ", style="dim")
        t.append("[H]", style="bold red");   t.append(" Halt  ", style="dim")
        t.append("[R]", style="bold green"); t.append(" Resume  ", style="dim")
        t.append(f"Updated: {datetime.now().strftime('%H:%M:%S')}", style="dim")
        return t

    # ─── HELPERS ───────────────────────────────────────────────────────────

    def _bar(self, value: float, max_value: float, width: int = 10) -> Text:
        pct    = min(value / max_value, 1.0) if max_value > 0 else 0.0
        filled = int(pct * width)
        col    = "red" if pct >= 0.9 else "yellow" if pct >= 0.7 else "green"
        bar    = Text()
        bar.append("█" * filled,          style=col)
        bar.append("░" * (width - filled), style="dim")
        return bar

    # ─── SIMPLE FALLBACK (no Rich) ─────────────────────────────────────────

    def _start_simple(self, blocking: bool):
        fn = self._simple_loop
        if blocking: fn()
        else:
            self._thread = threading.Thread(target=fn, daemon=True)
            self._thread.start()

    def _simple_loop(self):
        while not self._shutdown.is_set():
            os.system('cls' if os.name == 'nt' else 'clear')
            with self._lock:
                s = self._state
            print(f"=== FlashEASuite V2  {datetime.now():%H:%M:%S} ===")
            print(f"Balance: ${s.balance:,.0f}  Equity: ${s.equity:,.0f}")
            print(f"Daily: ${s.daily_pnl:+,.0f} ({s.daily_pnl_pct:+.2f}%)  DD: {s.max_drawdown_pct:.2f}%")
            print(f"Trades: {len(s.active_trades)}")
            if self.emergency:
                st = self.emergency.get_status_summary()
                print(f"Emergency: {st['level']}  Trading: {'YES' if st['trading_allowed'] else 'NO'}")
            time.sleep(self.refresh_rate)


# ─────────────────────────────────────────────────────────────────────────────
# FACTORY
# ─────────────────────────────────────────────────────────────────────────────

def create_dashboard(
    emergency:    Optional[EmergencySystem] = None,
    monitor:      Optional[SystemMonitor]   = None,
    refresh_rate: float = 5.0   # P9-5 spec: 5-second refresh
) -> LiveDashboard:
    return LiveDashboard(emergency=emergency, monitor=monitor, refresh_rate=refresh_rate)


# ─────────────────────────────────────────────────────────────────────────────
# STANDALONE DEMO  python dashboard.py
# ─────────────────────────────────────────────────────────────────────────────

def _demo():
    """Demo 90 วิ — Scenario อัตโนมัติ: NORMAL → WARNING → PAUSE → HALT → RESUME"""
    import queue as Q

    try:
        from core.emergency_system import create_emergency_system
        from core.system_monitor import create_system_monitor
    except ImportError:
        import sys, os
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'core'))
        from emergency_system import create_emergency_system
        from system_monitor import create_system_monitor

    em  = create_emergency_system(
        max_drawdown_pct=20.0, daily_loss_pct=5.0,
        consecutive_losses_max=3, check_interval_secs=0.5
    )
    mon = create_system_monitor()
    mon.set_queues(Q.Queue(), Q.Queue(), Q.Queue())
    dash = create_dashboard(em, mon, refresh_rate=5.0)   # P9-5: 5-second refresh

    em.start(); mon.start()
    dash.start(blocking=False)
    time.sleep(0.5)

    # Initial state
    em.update_pnl(100000, 100000, 0, 0)
    dash.update_connection(True, True, "S15 Grid", "RANGING")
    dash.update_pnl(100000, 100000, 0, 0, 0.0, 0.0)
    dash.add_alert("🚀 Demo started", "INFO")
    dash.update_trade(TradeRecord(
        ticket=10001, symbol="EURUSD", direction="BUY",
        open_time=datetime.now(), open_price=1.08500,
        lot_size=0.10, sl=1.08200, tp=1.09000, pnl=0, strategy="S15"
    ))
    dash.update_trade(TradeRecord(
        ticket=10002, symbol="XAUUSD", direction="SELL",
        open_time=datetime.now(), open_price=2650.00,
        lot_size=0.05, sl=2660.00, tp=2630.00, pnl=0, strategy="S07"
    ))

    balance  = 100000.0
    peak_eq  = 100000.0
    start_t  = time.time()
    # Flags ป้องกัน trigger ซ้ำ
    did_warning = did_pause = did_halt = did_resume = False

    try:
        while True:
            elapsed = time.time() - start_t
            if elapsed > 90: break

            t       = elapsed
            eq      = balance + math.sin(t / 10) * 500 + random.uniform(-80, 80)
            peak_eq = max(peak_eq, eq)
            daily   = eq - balance
            flt     = random.uniform(-200, 200)
            dd_pct  = max(0, (peak_eq - eq) / peak_eq * 100)

            # Simulate latency
            ts = mon.tick_start("EU")
            time.sleep(0.003 + random.uniform(0, 0.007))
            mon.tick_end("EU", ts)

            # Update trade P&L
            dash.update_trade(TradeRecord(
                ticket=10001, symbol="EURUSD", direction="BUY",
                open_time=datetime.now(), open_price=1.08500,
                lot_size=0.10, sl=1.08200, tp=1.09000,
                pnl=flt * 0.65, strategy="S15"
            ))
            dash.update_trade(TradeRecord(
                ticket=10002, symbol="XAUUSD", direction="SELL",
                open_time=datetime.now(), open_price=2650.00,
                lot_size=0.05, sl=2660.00, tp=2630.00,
                pnl=flt * 0.35, strategy="S07"
            ))

            # ── Phases ─────────────────────────────────────────────────────
            if t < 20:
                # NORMAL
                em.update_pnl(eq, balance, flt, daily)
                dash.update_pnl(balance, eq, flt, daily, (daily/balance)*100, dd_pct)

            elif t < 35:
                # → WARNING: ATR spike (trigger once)
                if not did_warning:
                    em.update_atr("EURUSD", 0.003, 0.001)
                    dash.add_alert("⚡ EURUSD ATR spike 3× — Size ลดเหลือ 50%", "WARNING")
                    dash.update_connection(True, True, "S15 (50%)", "VOLATILE")
                    did_warning = True
                em.update_pnl(eq, balance, flt, daily)
                dash.update_pnl(balance, eq, flt, daily, (daily/balance)*100, dd_pct)

            elif t < 50:
                # → PAUSE: consecutive losses (trigger once)
                if not did_pause:
                    em.manual_resume()
                    em.update_atr("EURUSD", 0.001, 0.001)
                    for _ in range(3): em.record_trade_result(-400)
                    dash.add_alert("⚠️  3 losses → PAUSE 60 min", "WARNING")
                    dash.update_connection(True, True, "PAUSED", "RANGING")
                    did_pause = True
                em.update_pnl(balance - 1200, balance, -1200, -1200)
                dash.update_pnl(balance, balance - 1200, -1200, -1200, -1.2, 1.2)

            elif t < 65:
                # → HALT: daily loss (trigger once)
                if not did_halt:
                    em.manual_resume()
                    dash.add_alert("⛔ Daily loss > 5% → TRADING HALTED", "HALT")
                    dash.update_connection(True, True, "HALTED", "RANGING")
                    did_halt = True
                em.update_pnl(94000, balance, -6000, -6000)
                dash.update_pnl(balance, 94000, -6000, -6000, -6.0, 6.0)

            else:
                # → RESUME (trigger once)
                if not did_resume:
                    em.manual_resume()
                    dash.add_alert("✅ Operator resumed — all clear", "INFO")
                    dash.update_connection(True, True, "S15 Grid", "TRENDING")
                    did_resume = True
                eq2 = balance + (t - 65) * 25 + random.uniform(-50, 50)
                em.update_pnl(eq2, balance, eq2 - balance, eq2 - balance)
                dash.update_pnl(balance, eq2, eq2 - balance, eq2 - balance,
                                (eq2 - balance) / balance * 100, 0.0)

            time.sleep(1.0)   # ← 1s ระหว่าง iteration (ไม่ตรง trigger window)

    except KeyboardInterrupt:
        pass
    finally:
        dash.stop(); em.stop(); mon.stop()


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    _demo()
