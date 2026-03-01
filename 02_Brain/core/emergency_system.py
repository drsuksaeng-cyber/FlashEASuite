#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Emergency Safety System
Program B (Brain) — Phase 0-3

ระบบความปลอดภัยแบบ real-time สำหรับป้องกันความเสียหายจากการเทรด
- ตรวจจับ 8 เงื่อนไขอันตราย
- ส่ง EMERGENCY_HALT command ผ่าน ZMQ ไปยัง Trader
- Thread-safe ทำงานร่วมกับ existing queue architecture

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-18
"""

import threading
import time
import logging
import psutil
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Callable, Tuple
from dataclasses import dataclass, field
from enum import Enum, auto

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# ENUMS & CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

class EmergencyLevel(Enum):
    """ระดับความรุนแรงของ emergency"""
    NORMAL    = "NORMAL"      # ปกติ
    WARNING   = "WARNING"     # เตือน ลด size
    PAUSE     = "PAUSE"       # หยุดชั่วคราว (ตามเวลา)
    HALT      = "HALT"        # หยุดเทรดทั้งหมด
    SHUTDOWN  = "SHUTDOWN"    # ปิด system ทันที


class EmergencyReason(Enum):
    """สาเหตุของ emergency"""
    MAX_DRAWDOWN         = auto()   # Drawdown > 20%
    DAILY_LOSS_LIMIT     = auto()   # Daily loss > 5%
    CONSECUTIVE_LOSSES   = auto()   # Losses > 5 ครั้งติด
    VOLATILITY_SPIKE     = auto()   # ATR > 3x normal
    NEWS_EVENT           = auto()   # Major news event
    CONNECTION_LOSS      = auto()   # Server disconnect
    CORRELATION_OVERLOAD = auto()   # Correlation > 80%
    SYSTEM_OVERLOAD      = auto()   # CPU/Memory > 90%
    MANUAL_HALT          = auto()   # Operator manual halt (ไม่ auto-resolve)


@dataclass
class EmergencyEvent:
    """บันทึก emergency event"""
    timestamp:   datetime
    level:       EmergencyLevel
    reason:      EmergencyReason
    message:     str
    value:       float       # ค่าที่ trigger (เช่น drawdown %)
    threshold:   float       # threshold ที่กำหนด
    resolved:    bool = False
    resolved_at: Optional[datetime] = None
    duration_secs: float = 0.0  # ระยะเวลา halt/pause


@dataclass
class RiskMetrics:
    """สถิติ risk แบบ real-time"""
    # Account metrics
    balance:             float = 100000.0  # Starting balance
    equity:              float = 100000.0
    floating_pnl:        float = 0.0
    daily_pnl:           float = 0.0
    daily_pnl_pct:       float = 0.0      # % ของ balance
    max_drawdown_pct:    float = 0.0      # Peak-to-trough %
    peak_equity:         float = 100000.0

    # Trade metrics
    consecutive_losses:  int   = 0
    total_trades_today:  int   = 0
    winning_trades:      int   = 0
    losing_trades:       int   = 0

    # Market metrics
    current_atr:         Dict[str, float] = field(default_factory=dict)
    avg_atr:             Dict[str, float] = field(default_factory=dict)
    correlation_matrix:  Dict[str, float] = field(default_factory=dict)

    # System metrics
    cpu_percent:         float = 0.0
    memory_percent:      float = 0.0
    latency_ms:          float = 0.0

    # Connection
    last_feeder_ping:    float = 0.0
    last_trader_ping:    float = 0.0
    is_feeder_connected: bool  = True
    is_trader_connected: bool  = True

    # Timestamps
    last_update:         datetime = field(default_factory=datetime.now)
    session_start:       datetime = field(default_factory=datetime.now)


@dataclass
class EmergencyConfig:
    """การตั้งค่า Emergency System"""
    # Thresholds
    max_drawdown_pct:       float = 20.0   # % halt ถ้า drawdown เกิน
    daily_loss_pct:         float = 5.0    # % halt ถ้า daily loss เกิน
    consecutive_losses_max: int   = 5      # ครั้งที่ pause
    volatility_multiplier:  float = 3.0    # ATR x เท่า = spike
    system_cpu_threshold:   float = 90.0   # %
    system_mem_threshold:   float = 90.0   # %
    correlation_threshold:  float = 0.80   # max correlation

    # Durations
    consecutive_loss_pause_mins:  int   = 60    # pause กี่นาที
    news_pause_mins:              int   = 15    # หยุดก่อน/หลัง news
    connection_timeout_secs:      float = 30.0  # ถือว่า disconnect

    # Size reduction (ไม่ halt แต่ลด position size)
    volatility_size_factor:      float = 0.5   # ลดเหลือ 50% เมื่อ vol spike
    correlation_size_factor:     float = 0.5   # ลดเหลือ 50% เมื่อ correlation สูง

    # Monitoring interval
    check_interval_secs: float = 1.0


# ─────────────────────────────────────────────────────────────────────────────
# MAIN EMERGENCY SYSTEM CLASS
# ─────────────────────────────────────────────────────────────────────────────

class EmergencySystem:
    """
    Emergency Safety System — ป้องกันความเสียหายจากการเทรดแบบ real-time

    ทำงานเป็น background thread ตรวจสอบทุก check_interval_secs
    เมื่อพบความผิดปกติ → ส่ง callback → Brain ส่ง COMMAND ไปยัง Trader

    Usage:
        emergency = EmergencySystem(config, on_halt_callback)
        emergency.start()
        emergency.update_pnl(equity=99000, floating=-1000)
        emergency.record_trade_result(profit=-500)  # negative = loss
    """

    def __init__(
        self,
        config: Optional[EmergencyConfig] = None,
        on_level_change: Optional[Callable[[EmergencyLevel, EmergencyEvent], None]] = None
    ):
        self.config = config or EmergencyConfig()
        self.on_level_change = on_level_change  # callback เมื่อ level เปลี่ยน

        # State
        self._lock           = threading.RLock()
        self._current_level  = EmergencyLevel.NORMAL
        self._active_reasons: Dict[EmergencyReason, EmergencyEvent] = {}
        self._event_history: List[EmergencyEvent] = []
        self._metrics        = RiskMetrics()

        # Pause/halt timers
        self._pause_until:     Optional[datetime] = None
        self._halt_active:     bool               = False
        self._size_multiplier: float              = 1.0  # 1.0 = normal, <1.0 = reduced

        # Background monitor thread
        self._shutdown_event = threading.Event()
        self._monitor_thread: Optional[threading.Thread] = None

        # Alerts (ไม่ส่ง alert ซ้ำในเวลาสั้นๆ)
        self._last_alert: Dict[EmergencyReason, datetime] = {}
        self._alert_cooldown_secs = 60.0

        # News events
        self._news_events: List[Tuple[datetime, str]] = []  # (time, description)

        logger.info("✅ EmergencySystem initialized")

    # ─── START / STOP ──────────────────────────────────────────────────────

    def start(self) -> None:
        """เริ่ม background monitoring thread"""
        self._shutdown_event.clear()
        self._monitor_thread = threading.Thread(
            target=self._monitor_loop,
            name="EmergencyMonitor",
            daemon=True
        )
        self._monitor_thread.start()
        logger.info(f"🚨 EmergencySystem monitor started (interval={self.config.check_interval_secs}s)")

    def stop(self) -> None:
        """หยุด monitoring"""
        self._shutdown_event.set()
        if self._monitor_thread and self._monitor_thread.is_alive():
            self._monitor_thread.join(timeout=5.0)
        logger.info("EmergencySystem stopped")

    # ─── PUBLIC UPDATE METHODS ─────────────────────────────────────────────

    def update_pnl(
        self,
        equity: float,
        balance: float,
        floating_pnl: float,
        daily_pnl: float
    ) -> None:
        """อัปเดต P&L metrics — เรียกจาก strategy engine ทุกครั้งที่ได้รับ POSITION_UPDATE"""
        with self._lock:
            m = self._metrics
            m.equity       = equity
            m.balance      = balance
            m.floating_pnl = floating_pnl
            m.daily_pnl    = daily_pnl
            m.last_update  = datetime.now()

            # Daily P&L %
            if balance > 0:
                m.daily_pnl_pct = (daily_pnl / balance) * 100.0

            # Peak equity tracking
            if equity > m.peak_equity:
                m.peak_equity = equity

            # Drawdown calculation
            if m.peak_equity > 0:
                drawdown = ((m.peak_equity - equity) / m.peak_equity) * 100.0
                m.max_drawdown_pct = max(m.max_drawdown_pct, drawdown)

    def record_trade_result(self, profit: float, symbol: str = "") -> None:
        """
        บันทึกผล trade
        profit > 0 = กำไร, profit < 0 = ขาดทุน
        """
        with self._lock:
            m = self._metrics
            m.total_trades_today += 1

            if profit < 0:
                m.losing_trades      += 1
                m.consecutive_losses += 1
                logger.debug(f"Loss recorded: {profit:.2f} | Consecutive: {m.consecutive_losses}")
            else:
                m.winning_trades     += 1
                m.consecutive_losses  = 0  # reset เมื่อชนะ

    def update_atr(self, symbol: str, current_atr: float, avg_atr: float) -> None:
        """อัปเดต ATR สำหรับ volatility spike detection"""
        with self._lock:
            self._metrics.current_atr[symbol] = current_atr
            self._metrics.avg_atr[symbol]     = avg_atr

    def update_correlation(self, symbol_pair: str, correlation: float) -> None:
        """อัปเดต correlation ระหว่าง symbol pairs"""
        with self._lock:
            self._metrics.correlation_matrix[symbol_pair] = abs(correlation)

    def update_connection_status(
        self,
        feeder_connected: bool,
        trader_connected: bool,
        feeder_ping: float = 0.0,
        trader_ping: float = 0.0
    ) -> None:
        """อัปเดต connection status"""
        with self._lock:
            m = self._metrics
            m.is_feeder_connected = feeder_connected
            m.is_trader_connected = trader_connected
            if feeder_connected:
                m.last_feeder_ping = time.time()
            if trader_connected:
                m.last_trader_ping = time.time()

    def add_news_event(self, event_time: datetime, description: str) -> None:
        """เพิ่ม news event เพื่อหยุดเทรดชั่วคราว"""
        with self._lock:
            self._news_events.append((event_time, description))
            logger.info(f"📰 News event added: {description} at {event_time}")

    def manual_halt(self, reason: str = "Manual override") -> None:
        """หยุดเทรดโดย operator (ไม่ auto-resolve ต้อง manual_resume เท่านั้น)"""
        event = EmergencyEvent(
            timestamp=datetime.now(),
            level=EmergencyLevel.HALT,
            reason=EmergencyReason.MANUAL_HALT,
            message=f"Manual halt: {reason}",
            value=0.0,
            threshold=0.0
        )
        with self._lock:
            self._trigger_emergency(EmergencyLevel.HALT, EmergencyReason.MANUAL_HALT, event)

    def manual_resume(self) -> None:
        """เปิดเทรดต่อโดย operator"""
        with self._lock:
            self._halt_active                    = False
            self._pause_until                    = None
            self._size_multiplier                = 1.0
            self._active_reasons.clear()
            self._current_level                  = EmergencyLevel.NORMAL
            self._metrics.consecutive_losses     = 0   # reset counter
            self._metrics.max_drawdown_pct       = 0.0 # reset drawdown
            self._metrics.peak_equity            = self._metrics.equity  # reset peak
            self._metrics.daily_pnl              = 0.0
            self._metrics.daily_pnl_pct          = 0.0
            self._news_events.clear()            # clear news queue
        logger.info("✅ EmergencySystem: Manual resume — trading ENABLED")
        if self.on_level_change:
            self.on_level_change(EmergencyLevel.NORMAL, None)

    # ─── STATUS QUERIES ────────────────────────────────────────────────────

    @property
    def is_trading_allowed(self) -> bool:
        """True ถ้าอนุญาตให้เทรดได้"""
        with self._lock:
            if self._halt_active:
                return False
            if self._pause_until and datetime.now() < self._pause_until:
                return False
            return True

    @property
    def size_multiplier(self) -> float:
        """0.0-1.0 ตัวคูณ position size"""
        with self._lock:
            return self._size_multiplier

    @property
    def current_level(self) -> EmergencyLevel:
        with self._lock:
            return self._current_level

    @property
    def metrics(self) -> RiskMetrics:
        with self._lock:
            return self._metrics

    def get_status_summary(self) -> Dict:
        """สรุปสถานะสำหรับ Dashboard"""
        with self._lock:
            m = self._metrics
            active_reasons = list(self._active_reasons.keys())
            pause_remaining = 0
            if self._pause_until:
                remaining = (self._pause_until - datetime.now()).total_seconds()
                pause_remaining = max(0, remaining)

            return {
                "level":            self._current_level.value,
                "trading_allowed":  self.is_trading_allowed,
                "size_multiplier":  self._size_multiplier,
                "active_reasons":   [r.name for r in active_reasons],
                "pause_remaining":  pause_remaining,
                "drawdown_pct":     m.max_drawdown_pct,
                "daily_pnl_pct":    m.daily_pnl_pct,
                "consecutive_loss": m.consecutive_losses,
                "cpu_percent":      m.cpu_percent,
                "memory_percent":   m.memory_percent,
                "recent_events":    len(self._event_history[-10:])
            }

    def get_recent_events(self, n: int = 20) -> List[EmergencyEvent]:
        with self._lock:
            return list(self._event_history[-n:])

    # ─── BACKGROUND MONITOR LOOP ───────────────────────────────────────────

    def _monitor_loop(self) -> None:
        """Main monitoring loop — ทำงาน background"""
        logger.info("EmergencySystem monitor loop started")

        while not self._shutdown_event.is_set():
            try:
                self._check_all_conditions()
            except Exception as e:
                logger.error(f"EmergencySystem monitor error: {e}")

            self._shutdown_event.wait(self.config.check_interval_secs)

        logger.info("EmergencySystem monitor loop ended")

    def _check_all_conditions(self) -> None:
        """ตรวจสอบทุกเงื่อนไข — เรียกทุก check_interval_secs"""
        with self._lock:
            self._update_system_metrics()
            self._check_drawdown()
            self._check_daily_loss()
            self._check_consecutive_losses()
            self._check_volatility_spikes()
            self._check_news_events()
            self._check_connection_loss()
            self._check_correlation_overload()
            self._check_system_overload()
            self._auto_resolve_pauses()
            self._recalculate_level()

    def _update_system_metrics(self) -> None:
        """อัปเดต CPU/Memory metrics"""
        try:
            self._metrics.cpu_percent    = psutil.cpu_percent(interval=None)
            self._metrics.memory_percent = psutil.virtual_memory().percent
        except Exception:
            pass

    # ─── CONDITION CHECKS ─────────────────────────────────────────────────

    def _check_drawdown(self) -> None:
        """ตรวจสอบ Max Drawdown > 20%"""
        dd = self._metrics.max_drawdown_pct
        threshold = self.config.max_drawdown_pct

        if dd >= threshold:
            if EmergencyReason.MAX_DRAWDOWN not in self._active_reasons:
                event = EmergencyEvent(
                    timestamp=datetime.now(),
                    level=EmergencyLevel.HALT,
                    reason=EmergencyReason.MAX_DRAWDOWN,
                    message=f"⛔ Drawdown {dd:.2f}% เกิน limit {threshold:.1f}% — หยุดเทรดทันที!",
                    value=dd,
                    threshold=threshold,
                    duration_secs=0  # permanent halt
                )
                self._trigger_emergency(EmergencyLevel.HALT, EmergencyReason.MAX_DRAWDOWN, event)
        else:
            self._resolve_reason(EmergencyReason.MAX_DRAWDOWN)

    def _check_daily_loss(self) -> None:
        """ตรวจสอบ Daily loss > 5%"""
        loss_pct = abs(min(0.0, self._metrics.daily_pnl_pct))
        threshold = self.config.daily_loss_pct

        if loss_pct >= threshold:
            if EmergencyReason.DAILY_LOSS_LIMIT not in self._active_reasons:
                event = EmergencyEvent(
                    timestamp=datetime.now(),
                    level=EmergencyLevel.HALT,
                    reason=EmergencyReason.DAILY_LOSS_LIMIT,
                    message=f"⛔ Daily loss {loss_pct:.2f}% เกิน limit {threshold:.1f}% — หยุดเทรดวันนี้!",
                    value=loss_pct,
                    threshold=threshold,
                    duration_secs=0
                )
                self._trigger_emergency(EmergencyLevel.HALT, EmergencyReason.DAILY_LOSS_LIMIT, event)
        else:
            self._resolve_reason(EmergencyReason.DAILY_LOSS_LIMIT)

    def _check_consecutive_losses(self) -> None:
        """ตรวจสอบ Consecutive losses > 5 → pause 1hr"""
        n_losses   = self._metrics.consecutive_losses
        max_losses = self.config.consecutive_losses_max

        if n_losses >= max_losses:
            if EmergencyReason.CONSECUTIVE_LOSSES not in self._active_reasons:
                pause_secs = self.config.consecutive_loss_pause_mins * 60
                pause_until = datetime.now() + timedelta(seconds=pause_secs)
                self._pause_until = pause_until

                event = EmergencyEvent(
                    timestamp=datetime.now(),
                    level=EmergencyLevel.PAUSE,
                    reason=EmergencyReason.CONSECUTIVE_LOSSES,
                    message=f"⚠️ {n_losses} losses ติดต่อกัน — หยุด {self.config.consecutive_loss_pause_mins} นาที",
                    value=float(n_losses),
                    threshold=float(max_losses),
                    duration_secs=pause_secs
                )
                self._trigger_emergency(EmergencyLevel.PAUSE, EmergencyReason.CONSECUTIVE_LOSSES, event)
        # ถ้าหยุดครบเวลา auto_resolve จะ resolve

    def _check_volatility_spikes(self) -> None:
        """ตรวจสอบ ATR spike > 3x → ลด size"""
        multiplier = self.config.volatility_multiplier
        spike_found = False

        for symbol, current in self._metrics.current_atr.items():
            avg = self._metrics.avg_atr.get(symbol, 0.0)
            if avg > 0 and current >= (multiplier * avg):
                spike_found = True
                if EmergencyReason.VOLATILITY_SPIKE not in self._active_reasons:
                    event = EmergencyEvent(
                        timestamp=datetime.now(),
                        level=EmergencyLevel.WARNING,
                        reason=EmergencyReason.VOLATILITY_SPIKE,
                        message=f"⚡ {symbol} ATR={current:.5f} เกิน {multiplier:.0f}x avg={avg:.5f} — ลด position size",
                        value=current / avg if avg > 0 else 0.0,
                        threshold=multiplier
                    )
                    self._size_multiplier = min(
                        self._size_multiplier,
                        self.config.volatility_size_factor
                    )
                    self._trigger_emergency(EmergencyLevel.WARNING, EmergencyReason.VOLATILITY_SPIKE, event)
                break

        if not spike_found:
            self._resolve_reason(EmergencyReason.VOLATILITY_SPIKE)

    def _check_news_events(self) -> None:
        """ตรวจสอบ major news events → pause"""
        now = datetime.now()
        pause_delta = timedelta(minutes=self.config.news_pause_mins)
        active_news = None

        # ทำความสะอาด events เก่า
        self._news_events = [
            (t, d) for (t, d) in self._news_events
            if t + pause_delta * 2 > now
        ]

        for event_time, description in self._news_events:
            # Pause ช่วง news_pause_mins ก่อน และหลัง event
            if (event_time - pause_delta) <= now <= (event_time + pause_delta):
                active_news = (event_time, description)
                break

        if active_news:
            if EmergencyReason.NEWS_EVENT not in self._active_reasons:
                pause_until = active_news[0] + pause_delta
                self._pause_until = pause_until
                pause_secs = (pause_until - now).total_seconds()

                event = EmergencyEvent(
                    timestamp=now,
                    level=EmergencyLevel.PAUSE,
                    reason=EmergencyReason.NEWS_EVENT,
                    message=f"📰 News event: {active_news[1]} — หยุดเทรด {self.config.news_pause_mins} นาที",
                    value=0.0,
                    threshold=0.0,
                    duration_secs=pause_secs
                )
                self._trigger_emergency(EmergencyLevel.PAUSE, EmergencyReason.NEWS_EVENT, event)
        else:
            self._resolve_reason(EmergencyReason.NEWS_EVENT)

    def _check_connection_loss(self) -> None:
        """ตรวจสอบ connection loss → safe mode"""
        now = time.time()
        timeout = self.config.connection_timeout_secs
        feeder_lost = not self._metrics.is_feeder_connected
        trader_lost = not self._metrics.is_trader_connected

        # ตรวจสอบ ping timeout
        if self._metrics.last_feeder_ping > 0:
            feeder_lost = feeder_lost or (now - self._metrics.last_feeder_ping > timeout)
        if self._metrics.last_trader_ping > 0:
            trader_lost = trader_lost or (now - self._metrics.last_trader_ping > timeout)

        if feeder_lost or trader_lost:
            if EmergencyReason.CONNECTION_LOSS not in self._active_reasons:
                who = []
                if feeder_lost: who.append("Feeder")
                if trader_lost: who.append("Trader")

                event = EmergencyEvent(
                    timestamp=datetime.now(),
                    level=EmergencyLevel.PAUSE,
                    reason=EmergencyReason.CONNECTION_LOSS,
                    message=f"🔌 Connection lost: {', '.join(who)} — เข้า safe mode",
                    value=0.0,
                    threshold=0.0
                )
                self._trigger_emergency(EmergencyLevel.PAUSE, EmergencyReason.CONNECTION_LOSS, event)
        else:
            self._resolve_reason(EmergencyReason.CONNECTION_LOSS)

    def _check_correlation_overload(self) -> None:
        """ตรวจสอบ correlation > 80% → ลด positions"""
        threshold = self.config.correlation_threshold
        high_corr_found = False

        for pair, corr in self._metrics.correlation_matrix.items():
            if corr > threshold:
                high_corr_found = True
                if EmergencyReason.CORRELATION_OVERLOAD not in self._active_reasons:
                    event = EmergencyEvent(
                        timestamp=datetime.now(),
                        level=EmergencyLevel.WARNING,
                        reason=EmergencyReason.CORRELATION_OVERLOAD,
                        message=f"🔗 Correlation {pair}={corr:.2f} เกิน {threshold:.0%} — ลด positions",
                        value=corr,
                        threshold=threshold
                    )
                    self._size_multiplier = min(
                        self._size_multiplier,
                        self.config.correlation_size_factor
                    )
                    self._trigger_emergency(EmergencyLevel.WARNING, EmergencyReason.CORRELATION_OVERLOAD, event)
                break

        if not high_corr_found:
            self._resolve_reason(EmergencyReason.CORRELATION_OVERLOAD)

    def _check_system_overload(self) -> None:
        """ตรวจสอบ CPU/Memory > 90% → throttle"""
        cpu = self._metrics.cpu_percent
        mem = self._metrics.memory_percent
        cpu_t = self.config.system_cpu_threshold
        mem_t = self.config.system_mem_threshold

        if cpu >= cpu_t or mem >= mem_t:
            if EmergencyReason.SYSTEM_OVERLOAD not in self._active_reasons:
                event = EmergencyEvent(
                    timestamp=datetime.now(),
                    level=EmergencyLevel.WARNING,
                    reason=EmergencyReason.SYSTEM_OVERLOAD,
                    message=f"💻 System overload: CPU={cpu:.1f}% MEM={mem:.1f}% — throttle mode",
                    value=max(cpu, mem),
                    threshold=max(cpu_t, mem_t)
                )
                self._trigger_emergency(EmergencyLevel.WARNING, EmergencyReason.SYSTEM_OVERLOAD, event)
        else:
            self._resolve_reason(EmergencyReason.SYSTEM_OVERLOAD)

    # ─── HELPER METHODS ────────────────────────────────────────────────────

    def _trigger_emergency(
        self,
        level: EmergencyLevel,
        reason: EmergencyReason,
        event: EmergencyEvent
    ) -> None:
        """Trigger emergency — ต้องเรียกใน _lock context"""
        # บันทึก event
        self._active_reasons[reason] = event
        self._event_history.append(event)

        # Update halt state
        if level == EmergencyLevel.HALT:
            self._halt_active = True

        old_level = self._current_level
        self._recalculate_level()

        logger.warning(f"🚨 EMERGENCY [{level.value}]: {event.message}")

        # ส่ง callback ถ้า level เปลี่ยน
        if self._current_level != old_level and self.on_level_change:
            try:
                # เรียก callback นอก lock เพื่อป้องกัน deadlock
                threading.Thread(
                    target=self.on_level_change,
                    args=(self._current_level, event),
                    daemon=True
                ).start()
            except Exception as e:
                logger.error(f"Emergency callback error: {e}")

    def _resolve_reason(self, reason: EmergencyReason) -> None:
        """ยกเลิก emergency reason (ต้องเรียกใน _lock context)"""
        if reason in self._active_reasons:
            event = self._active_reasons.pop(reason)
            event.resolved    = True
            event.resolved_at = datetime.now()
            logger.info(f"✅ Emergency resolved: {reason.name}")

    def _auto_resolve_pauses(self) -> None:
        """Auto-resolve pause เมื่อหมดเวลา"""
        now = datetime.now()

        # Check pause_until expired
        if self._pause_until and now >= self._pause_until:
            self._pause_until = None
            # Resolve pause-type reasons
            for reason in [EmergencyReason.CONSECUTIVE_LOSSES, EmergencyReason.NEWS_EVENT]:
                self._resolve_reason(reason)
            # Reset consecutive losses counter
            self._metrics.consecutive_losses = 0
            logger.info("✅ Pause period expired — trading RESUMED")

    def _recalculate_level(self) -> None:
        """คำนวณ level สูงสุดจาก active reasons"""
        if not self._active_reasons:
            self._current_level   = EmergencyLevel.NORMAL
            self._halt_active     = False
            self._size_multiplier = 1.0
            return

        # หา level สูงสุด
        level_priority = {
            EmergencyLevel.NORMAL:   0,
            EmergencyLevel.WARNING:  1,
            EmergencyLevel.PAUSE:    2,
            EmergencyLevel.HALT:     3,
            EmergencyLevel.SHUTDOWN: 4
        }

        max_level = EmergencyLevel.NORMAL
        for event in self._active_reasons.values():
            if level_priority[event.level] > level_priority[max_level]:
                max_level = event.level

        self._current_level = max_level


# ─────────────────────────────────────────────────────────────────────────────
# FACTORY FUNCTION
# ─────────────────────────────────────────────────────────────────────────────

def create_emergency_system(
    on_level_change: Optional[Callable] = None,
    **kwargs
) -> EmergencySystem:
    """
    สร้าง EmergencySystem พร้อมใช้งาน

    Args:
        on_level_change: callback(level, event) เมื่อ level เปลี่ยน
        **kwargs: override config values เช่น max_drawdown_pct=15.0

    Returns:
        EmergencySystem instance (ยังไม่ได้ start)
    """
    config = EmergencyConfig(**kwargs) if kwargs else EmergencyConfig()
    return EmergencySystem(config=config, on_level_change=on_level_change)
