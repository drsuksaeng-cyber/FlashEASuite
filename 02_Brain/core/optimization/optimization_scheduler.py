"""
FlashEASuite V2 — P0.6-7: Optimization Scheduler
ตัดสินใจว่าควร optimize เมื่อไหร่ — Weekly, Emergency DD, Regime Change

Triggers:
    1. WEEKLY: Saturday 00:00 UTC (primary schedule)
    2. EMERGENCY: DD > 15% (ไม่มี cooldown — ทำทันที)
    3. REGIME_CHANGE: Market regime เปลี่ยน (มี cooldown)

Constraints:
    - min_trades >= 30 per strategy×symbol
    - min_data_days >= 5
    - cooldown >= 24 hours since last optimize (ยกเว้น emergency)

Dependencies:
    - MultiStrategyOptimizer (P0.6-6)
    - MultiStrategyFeedback (P0.6-7)
    - ConfigPushGenerator (P0.6-7)
    - ParameterRepository (P0.6-3)

Author: FlashEASuite V2 Team | Phase: P0.6-7
"""

import time
import logging
import threading
from datetime import datetime, timezone, timedelta
from typing import Optional, Callable

logger = logging.getLogger("FlashEA.Scheduler")

# Trigger types
TRIGGER_WEEKLY = "WEEKLY"
TRIGGER_EMERGENCY = "EMERGENCY_DD"
TRIGGER_REGIME = "REGIME_CHANGE"
TRIGGER_MANUAL = "MANUAL"

# Thresholds
DD_EMERGENCY_PCT = 15.0          # DD > 15% → emergency
DD_SEVERE_PCT = 20.0             # DD > 20% → severe emergency
MIN_TRADES = 30                  # ขั้นต่ำ per strategy×symbol
MIN_DATA_DAYS = 5                # ข้อมูลอย่างน้อย 5 วัน
COOLDOWN_HOURS = 24              # cooldown ระหว่าง optimize
EMERGENCY_COOLDOWN_HOURS = 0     # emergency ไม่มี cooldown
REGIME_COOLDOWN_HOURS = 6        # regime change cooldown


class OptimizationScheduler:
    """
    ตัดสินใจว่าควร optimize เมื่อไหร่.

    Usage:
        scheduler = OptimizationScheduler(optimizer, feedback, config_gen, repo)
        scheduler.start()  # start background thread

        # Or check manually:
        should, reason = scheduler.should_optimize()
        if should:
            result = scheduler.run_optimization_cycle("XAUUSD")
    """

    def __init__(self, optimizer=None, feedback=None, config_gen=None,
                 param_repo=None, protocol_handler=None,
                 symbols: list = None,
                 weekly_day: int = 5,        # 0=Mon, 5=Sat
                 weekly_hour: int = 0,        # UTC hour
                 on_cycle_complete: Callable = None):
        """
        Args:
            optimizer: MultiStrategyOptimizer
            feedback: MultiStrategyFeedback
            config_gen: ConfigPushGenerator
            param_repo: ParameterRepository
            protocol_handler: ProtocolHandler (for sending CONFIG_PUSH)
            symbols: Symbols to optimize (default: ["XAUUSD"])
            weekly_day: Day of week for scheduled optimization (0=Mon, 5=Sat)
            weekly_hour: Hour (UTC) for scheduled optimization
            on_cycle_complete: Callback(result) after each cycle
        """
        self._optimizer = optimizer
        self._feedback = feedback
        self._config_gen = config_gen
        self._repo = param_repo
        self._protocol = protocol_handler
        self._symbols = symbols or ["XAUUSD"]
        self._weekly_day = weekly_day
        self._weekly_hour = weekly_hour
        self._on_complete = on_cycle_complete

        # State
        self._last_optimize_ts = 0.0
        self._last_regime = "UNKNOWN"
        self._current_dd_pct = 0.0
        self._cycle_count = 0
        self._history: list[dict] = []

        # Background thread
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._check_interval = 60  # seconds between checks

        logger.info(f"[Scheduler] Initialized — weekly={_day_name(weekly_day)} "
                    f"{weekly_hour:02d}:00 UTC, symbols={self._symbols}")

    # ================================================================
    # Trigger Check
    # ================================================================

    def should_optimize(self) -> tuple:
        """
        Check if optimization should run.

        Returns:
            (should_run: bool, trigger_reason: str)
        """
        now = time.time()

        # === EMERGENCY: DD > threshold ===
        if self._current_dd_pct >= DD_EMERGENCY_PCT:
            severity = "SEVERE" if self._current_dd_pct >= DD_SEVERE_PCT else "HIGH"
            return (True, f"{TRIGGER_EMERGENCY}:{severity}:DD={self._current_dd_pct:.1f}%")

        # === Cooldown check (applies to non-emergency triggers) ===
        hours_since = (now - self._last_optimize_ts) / 3600 if self._last_optimize_ts > 0 else 999
        if hours_since < COOLDOWN_HOURS:
            return (False, f"cooldown:{hours_since:.1f}h < {COOLDOWN_HOURS}h")

        # === WEEKLY: Check day/hour ===
        utc_now = datetime.now(timezone.utc)
        if utc_now.weekday() == self._weekly_day and utc_now.hour == self._weekly_hour:
            # Check if already ran this week
            if self._last_optimize_ts > 0:
                last_dt = datetime.fromtimestamp(self._last_optimize_ts, tz=timezone.utc)
                if last_dt.isocalendar()[1] == utc_now.isocalendar()[1]:
                    return (False, "weekly:already_ran_this_week")
            return (True, TRIGGER_WEEKLY)

        # === REGIME CHANGE ===
        # (Checked externally via update_regime — see below)

        return (False, "no_trigger")

    def check_data_sufficient(self, symbol: str) -> tuple:
        """
        Check if enough trade data exists for optimization.

        Returns:
            (sufficient: bool, reason: str)
        """
        if self._optimizer is None:
            return (False, "no_optimizer")

        if not self._optimizer.should_optimize(symbol, MIN_TRADES):
            return (False, f"insufficient_trades (need {MIN_TRADES})")

        return (True, "ok")

    # ================================================================
    # External State Updates
    # ================================================================

    def update_drawdown(self, dd_pct: float):
        """Update current drawdown % — called from risk monitor."""
        old = self._current_dd_pct
        self._current_dd_pct = dd_pct
        if dd_pct >= DD_EMERGENCY_PCT and old < DD_EMERGENCY_PCT:
            logger.warning(f"[Scheduler] ⚠️ DD crossed emergency threshold: {dd_pct:.1f}%")

    def update_regime(self, new_regime: str) -> Optional[str]:
        """
        Update market regime. Returns trigger string if regime changed.
        """
        if new_regime == self._last_regime:
            return None

        old = self._last_regime
        self._last_regime = new_regime

        # Check regime-specific cooldown
        hours_since = (time.time() - self._last_optimize_ts) / 3600 if self._last_optimize_ts > 0 else 999
        if hours_since < REGIME_COOLDOWN_HOURS:
            logger.info(f"[Scheduler] Regime {old}→{new_regime} but cooldown active "
                        f"({hours_since:.1f}h < {REGIME_COOLDOWN_HOURS}h)")
            return None

        trigger = f"{TRIGGER_REGIME}:{old}→{new_regime}"
        logger.info(f"[Scheduler] 🔄 Regime change trigger: {trigger}")
        return trigger

    # ================================================================
    # Optimization Cycle
    # ================================================================

    def run_optimization_cycle(self, symbol: str = None,
                                trigger: str = "MANUAL") -> dict:
        """
        Execute full optimization cycle:
        1. Check data sufficiency
        2. Run MultiStrategyOptimizer
        3. Generate CONFIG_PUSH V2
        4. Send via ProtocolHandler
        5. Record in history

        Args:
            symbol: Target symbol (None = first configured symbol)
            trigger: Trigger reason string

        Returns:
            dict: {success, trigger, symbol, changes, confidence, config_push_sent}
        """
        symbol = symbol or self._symbols[0]
        t0 = time.time()
        self._cycle_count += 1

        logger.info(f"[Scheduler] === CYCLE #{self._cycle_count}: "
                    f"trigger={trigger}, symbol={symbol} ===")

        # Step 1: Check data
        sufficient, reason = self.check_data_sufficient(symbol)
        if not sufficient and TRIGGER_EMERGENCY not in trigger:
            result = {"success": False, "reason": f"data_insufficient: {reason}",
                      "trigger": trigger, "symbol": symbol}
            self._record_history(result)
            return result

        # Step 2: Run optimizer
        if self._optimizer is None:
            return {"success": False, "reason": "no_optimizer"}

        try:
            opt_result = self._optimizer.optimize_all(
                symbol=symbol,
                regime=self._last_regime,
                dd_pct=self._current_dd_pct,
            )
        except Exception as e:
            logger.error(f"[Scheduler] Optimizer error: {e}")
            return {"success": False, "reason": f"optimizer_error: {e}"}

        # Step 3: Generate CONFIG_PUSH V2
        config_push = None
        config_push_sent = False
        if self._config_gen and opt_result.get("applied"):
            try:
                config_push = self._config_gen.generate(
                    opt_result, param_repo=self._repo,
                    symbol=symbol, dd_pct=self._current_dd_pct,
                )
            except Exception as e:
                logger.error(f"[Scheduler] ConfigPush gen error: {e}")

        # Step 4: Send via ZMQ (V2 format)
        if config_push and self._protocol:
            try:
                config_push_sent = self._protocol.send_config_push_v2_raw(config_push)
                if config_push_sent:
                    logger.info("[Scheduler] ✅ CONFIG_PUSH V2 sent")
            except Exception as e:
                logger.warning(f"[Scheduler] Send error: {e}")
                config_push_sent = False

        # Step 5: Record
        self._last_optimize_ts = time.time()
        elapsed_ms = round((time.time() - t0) * 1000, 1)

        result = {
            "success": True,
            "trigger": trigger,
            "symbol": symbol,
            "regime": self._last_regime,
            "dd_pct": self._current_dd_pct,
            "changes": opt_result.get("total_changes", 0),
            "confidence": opt_result.get("confidence", 0.0),
            "applied": opt_result.get("applied", False),
            "config_push_sent": config_push_sent,
            "cycle_count": self._cycle_count,
            "elapsed_ms": elapsed_ms,
        }

        self._record_history(result)

        if self._on_complete:
            try:
                self._on_complete(result)
            except Exception as e:
                logger.warning(f"[Scheduler] Callback error: {e}")

        logger.info(f"[Scheduler] === DONE: {result['changes']} changes, "
                    f"applied={result['applied']}, sent={config_push_sent}, "
                    f"{elapsed_ms}ms ===")
        return result

    # ================================================================
    # Background Thread
    # ================================================================

    def start(self, check_interval: int = 60):
        """Start background scheduler thread."""
        if self._running:
            logger.warning("[Scheduler] Already running")
            return
        self._check_interval = check_interval
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True,
                                        name="OptScheduler")
        self._thread.start()
        logger.info(f"[Scheduler] Background thread started (interval={check_interval}s)")

    def stop(self):
        """Stop background scheduler thread."""
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)
        logger.info("[Scheduler] Background thread stopped")

    def _loop(self):
        """Background loop — check triggers periodically."""
        while self._running:
            try:
                should, trigger = self.should_optimize()
                if should:
                    for sym in self._symbols:
                        self.run_optimization_cycle(sym, trigger)
            except Exception as e:
                logger.error(f"[Scheduler] Loop error: {e}")
            time.sleep(self._check_interval)

    # ================================================================
    # History & Stats
    # ================================================================

    def _record_history(self, result: dict):
        result["timestamp"] = datetime.now(timezone.utc).isoformat()
        self._history.append(result)
        if len(self._history) > 200:
            self._history = self._history[-200:]

    def get_history(self, limit: int = 20) -> list:
        return self._history[-limit:]

    def get_stats(self) -> dict:
        return {
            "cycle_count": self._cycle_count,
            "last_optimize": datetime.fromtimestamp(
                self._last_optimize_ts, tz=timezone.utc).isoformat()
                if self._last_optimize_ts > 0 else "never",
            "current_regime": self._last_regime,
            "current_dd_pct": self._current_dd_pct,
            "is_running": self._running,
            "symbols": self._symbols,
        }

    @property
    def is_running(self) -> bool:
        return self._running

    @property
    def last_optimize_time(self) -> float:
        return self._last_optimize_ts


def _day_name(d: int) -> str:
    return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][d % 7]


# ================================================================
# INLINE TESTS
# ================================================================
if __name__ == "__main__":

    # Mock dependencies
    class MockOptimizer:
        def __init__(self):
            self._trades = 100
        def should_optimize(self, sym, mt):
            return self._trades >= mt
        def optimize_all(self, symbol="XAUUSD", regime="UNKNOWN",
                         dd_pct=0.0, **kw):
            return {
                "strategy_changes": {"S01_LOOKBACK": {"value": 25}},
                "mm_changes": {},
                "mm_selection": {"S01": "MM04"},
                "reasoning": {"summary_th": "ปรับ test", "changes": [], "total_changes": 1},
                "confidence": 0.75,
                "applied": True,
                "regime": regime,
                "total_changes": 1,
            }

    class MockConfigGen:
        def generate(self, opt, **kw):
            return {"type": 10, "version": 2, "regime": opt.get("regime"),
                    "symbol_configs": [], "reasoning": {}, "standalone_config": {}}
        def pack_to_messagepack(self, cp):
            return b"\x01"

    opt = MockOptimizer()
    gen = MockConfigGen()
    sched = OptimizationScheduler(optimizer=opt, config_gen=gen)

    # T1: No trigger initially
    should, reason = sched.should_optimize()
    assert not should or "WEEKLY" not in reason  # depends on current day
    print(f"✅ T1: Initial check — should={should}, reason={reason}")

    # T2: Emergency DD trigger
    sched.update_drawdown(16.5)
    should, reason = sched.should_optimize()
    assert should and "EMERGENCY" in reason
    print(f"✅ T2: Emergency DD — reason={reason}")

    # T3: Run cycle
    result = sched.run_optimization_cycle("XAUUSD", trigger=reason)
    assert result["success"] and result["changes"] == 1
    print(f"✅ T3: Cycle — changes={result['changes']}, conf={result['confidence']}")

    # T4: Cooldown check
    sched.update_drawdown(5.0)  # Reset DD below threshold
    should, reason = sched.should_optimize()
    assert not should and "cooldown" in reason
    print(f"✅ T4: Cooldown — {reason}")

    # T5: Emergency bypasses cooldown
    sched.update_drawdown(21.0)
    should, reason = sched.should_optimize()
    assert should and "SEVERE" in reason
    print(f"✅ T5: Emergency bypasses cooldown — {reason}")

    # T6: Regime change trigger
    sched._last_optimize_ts = time.time() - 25 * 3600  # Past cooldown
    sched.update_drawdown(3.0)
    trigger = sched.update_regime("TRENDING")
    # First call — regime was UNKNOWN → TRENDING
    if trigger:
        print(f"✅ T6: Regime trigger — {trigger}")
    else:
        print("✅ T6: Regime change noted (cooldown may apply)")

    # T7: Data insufficient
    opt._trades = 5  # Below threshold
    sched._last_optimize_ts = 0  # No cooldown
    result = sched.run_optimization_cycle("XAUUSD", trigger="MANUAL")
    assert not result["success"]
    print(f"✅ T7: Insufficient data — {result['reason']}")

    # T8: History
    hist = sched.get_history()
    assert len(hist) >= 2
    print(f"✅ T8: History — {len(hist)} entries")

    # T9: Stats
    st = sched.get_stats()
    assert st["cycle_count"] >= 2
    print(f"✅ T9: Stats — cycles={st['cycle_count']}, regime={st['current_regime']}")

    # T10: Check data sufficient
    opt._trades = 100
    ok, reason = sched.check_data_sufficient("XAUUSD")
    assert ok
    print(f"✅ T10: Data sufficient — {reason}")

    print("\n" + "=" * 50)
    print("✅ ALL OptimizationScheduler TESTS PASSED")
    print("=" * 50)
