#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Adaptive Parameter Manager — Adjusts strategy parameters based on
rolling performance metrics from PerformanceTracker.

Adaptation is per (symbol, strategy_id).
Only standalone strategies are adapted: S01, S06, S07, S10, S14, S15, S16.
All adjustments are small, bounded steps — no ML required.

Cooldown: ADAPT_COOLDOWN seconds between adjustments per pair.
Minimum trades: ADAPT_MIN_TRADES before first adjustment.
"""

import time
from typing import Dict, Optional, Tuple

from .performance_tracker import PerformanceTracker


# ========================================================================
# STRATEGY DEFAULT PARAMETERS
# ========================================================================

STRATEGY_DEFAULTS: Dict[str, dict] = {
    "S01": {
        "S01_BETA":    1.0,
        "S01_PERIOD":  20,
        "S01_ENTRY_Z": 2.0,
        "S01_STOP_Z":  3.0,
    },
    "S06": {
        "S06_KAMA_PERIOD": 10,
        "S06_ER_THRESH":   0.3,
        "S06_TP_ATR":      3.0,
        "S06_SL_ATR":      1.0,
    },
    "S07": {
        "S07_RSI_PERIOD":   14,
        "S07_RSI_BUY":      30.0,
        "S07_RSI_SELL":     70.0,
        "S07_VOL_FILTER":   1.3,
        "S07_SL_ATR_MULT":  2.0,
        "S07_TP_ATR_MULT":  1.5,
    },
    "S10": {
        "S10_ENTRY_PERIOD":  20,
        "S10_EXIT_PERIOD":   20,
        "S10_MAX_UNITS":      4,
        "S10_UNIT_SPACING":  0.5,
        "S10_BREAKOUT_BUF":  0.1,
        "S10_RISK_PCT":      1.0,
    },
    "S14": {
        "S14_BB_PERIOD":    20,
        "S14_BB_DEV":        2.0,
        "S14_KC_PERIOD":    20,
        "S14_KC_ATR_MULT":   1.5,
        "S14_SQUEEZE_MIN":   6,
        "S14_BREAKOUT_MOM":  0.5,
        "S14_SL_ATR":        2.0,
        "S14_TP_ATR":        3.0,
    },
    "S15": {
        "S15_MAX_ORDERS":       10,
        "S15_BASE_STEP":       200.0,
        "S15_ELASTIC_FACTOR":    1.5,
        "S15_CONF_THRESHOLD":    0.65,
        "S15_ATR_RATIO":         0.8,
        "S15_SWAP_FILTER":       1.0,
    },
    "S16": {
        "S16_VELOCITY_THRESH":    2.5,
        "S16_SPREAD_THRESH":      1.5,
        "S16_VOLUME_THRESH":      2.0,
        "S16_MOMENTUM_THRESH":    0.5,
        "S16_VOLATILITY_THRESH":  1.5,
        "S16_DIRECTION_CONSIST":  0.7,
        "S16_PATTERN_SCORE_MIN": 70.0,
        "S16_ATR_SPIKE_MULT":     2.0,
        "S16_ATR_TP_MULT":        0.8,
        "S16_ATR_SL_MULT":        0.4,
        "S16_MAX_HOLD_SEC":     900,
    },
}

# ========================================================================
# PARAMETER BOUNDS  (min, max, step) — clamped after every adjustment
# ========================================================================

PARAM_BOUNDS: Dict[str, Tuple[float, float, float]] = {
    # S01
    "S01_BETA":    (0.5, 2.0, 0.1),
    "S01_PERIOD":  (10, 40, 2),
    "S01_ENTRY_Z": (1.0, 4.0, 0.1),
    "S01_STOP_Z":  (1.5, 5.0, 0.1),

    # S06
    "S06_KAMA_PERIOD": (5, 30, 1),
    "S06_ER_THRESH":   (0.1, 0.7, 0.05),
    "S06_TP_ATR":      (1.0, 6.0, 0.1),
    "S06_SL_ATR":      (0.5, 3.0, 0.1),

    # S07
    "S07_RSI_PERIOD":  (7, 28, 1),
    "S07_RSI_BUY":     (20.0, 40.0, 2.0),
    "S07_RSI_SELL":    (60.0, 80.0, 2.0),
    "S07_VOL_FILTER":  (1.0, 2.0, 0.1),
    "S07_SL_ATR_MULT": (1.0, 4.0, 0.1),
    "S07_TP_ATR_MULT": (0.5, 3.0, 0.1),

    # S10
    "S10_ENTRY_PERIOD":  (10, 40, 2),
    "S10_EXIT_PERIOD":   (5, 30, 2),
    "S10_MAX_UNITS":     (1, 4, 1),
    "S10_UNIT_SPACING":  (0.2, 1.0, 0.1),
    "S10_BREAKOUT_BUF":  (0.0, 0.3, 0.05),
    "S10_RISK_PCT":      (0.5, 2.0, 0.1),

    # S14
    "S14_BB_PERIOD":   (10, 40, 2),
    "S14_BB_DEV":      (1.0, 3.0, 0.1),
    "S14_KC_PERIOD":   (10, 40, 2),
    "S14_KC_ATR_MULT": (1.0, 3.0, 0.1),
    "S14_SQUEEZE_MIN": (3, 8, 1),
    "S14_BREAKOUT_MOM":(0.1, 1.0, 0.1),
    "S14_SL_ATR":      (1.0, 4.0, 0.1),
    "S14_TP_ATR":      (1.0, 6.0, 0.1),

    # S15
    "S15_MAX_ORDERS":      (2, 20, 2),
    "S15_BASE_STEP":       (80.0, 500.0, 20.0),
    "S15_ELASTIC_FACTOR":  (1.0, 3.0, 0.1),
    "S15_CONF_THRESHOLD":  (0.3, 0.9, 0.05),
    "S15_ATR_RATIO":       (0.4, 1.5, 0.1),
    "S15_SWAP_FILTER":     (0.0, 3.0, 0.5),

    # S16
    "S16_VELOCITY_THRESH":    (1.0, 5.0, 0.2),
    "S16_SPREAD_THRESH":      (0.5, 3.0, 0.1),
    "S16_VOLUME_THRESH":      (1.0, 4.0, 0.2),
    "S16_MOMENTUM_THRESH":    (0.1, 1.5, 0.1),
    "S16_VOLATILITY_THRESH":  (0.5, 3.0, 0.2),
    "S16_DIRECTION_CONSIST":  (0.4, 0.9, 0.05),
    "S16_PATTERN_SCORE_MIN":  (40.0, 95.0, 5.0),
    "S16_ATR_SPIKE_MULT":     (1.0, 4.0, 0.2),
    "S16_ATR_TP_MULT":        (0.3, 2.0, 0.1),
    "S16_ATR_SL_MULT":        (0.1, 1.5, 0.05),
    "S16_MAX_HOLD_SEC":       (300, 3600, 60),
}

# ========================================================================
# GLOBAL ADAPT SETTINGS
# ========================================================================

ADAPT_MIN_TRADES  = 20      # min trades before first adjustment
ADAPT_COOLDOWN    = 14400   # 4 hours between adjustments per (symbol, strategy)

# Strategies adapted by this module (standalone-capable only)
ADAPTED_STRATEGIES = {"S01", "S06", "S07", "S10", "S14", "S15", "S16"}


# ========================================================================
# ADAPTIVE PARAM MANAGER
# ========================================================================

class AdaptiveParamManager:
    """
    Maintains current parameter state per (symbol, strategy_id) and
    applies conservative rule-based adjustments when performance is poor.

    Not thread-safe — call only from the engine thread.
    """

    def __init__(self):
        # Current active params per pair; initialised from STRATEGY_DEFAULTS on first use
        self._params:        Dict[Tuple[str, str], dict] = {}
        # Timestamp of last successful adjustment per pair
        self._last_adjusted: Dict[Tuple[str, str], float] = {}

    # ------------------------------------------------------------------
    # PUBLIC API
    # ------------------------------------------------------------------

    def get_params(self, symbol: str, strategy_id: str) -> dict:
        """Return current params for the pair (copy of internal state)."""
        key = (symbol, strategy_id)
        if key not in self._params:
            defaults = STRATEGY_DEFAULTS.get(strategy_id, {})
            self._params[key] = dict(defaults)
        return dict(self._params[key])

    def update_if_needed(self, symbol: str, strategy_id: str,
                         perf: PerformanceTracker) -> Tuple[bool, dict]:
        """
        Check performance and apply parameter adjustments if warranted.

        Returns:
            (changed: bool, new_params: dict)  — new_params is only
            meaningful when changed=True.
        """
        if strategy_id not in ADAPTED_STRATEGIES:
            return False, {}

        key = (symbol, strategy_id)

        # Cooldown guard
        now = time.time()
        last = self._last_adjusted.get(key, 0.0)
        if now - last < ADAPT_COOLDOWN:
            return False, {}

        # Minimum-trade guard
        n = perf.get_trade_count(symbol, strategy_id)
        if n < ADAPT_MIN_TRADES:
            return False, {}

        # Ensure current params exist
        if key not in self._params:
            self._params[key] = dict(STRATEGY_DEFAULTS.get(strategy_id, {}))

        params = dict(self._params[key])  # working copy

        wr  = perf.get_win_rate(symbol, strategy_id)
        pf  = perf.get_profit_factor(symbol, strategy_id)
        dd  = perf.get_drawdown(symbol, strategy_id)
        cl  = perf.get_consecutive_losses(symbol, strategy_id)

        # Strategy-specific adaptation
        adapt_fn = {
            "S01": self._adapt_s01,
            "S06": self._adapt_s06,
            "S07": self._adapt_s07,
            "S10": self._adapt_s10,
            "S14": self._adapt_s14,
            "S15": self._adapt_s15,
            "S16": self._adapt_s16,
        }.get(strategy_id)

        if adapt_fn is None:
            return False, {}

        new_params = adapt_fn(symbol, wr, pf, dd, cl, params)

        # Check if anything actually changed
        changed = any(
            abs(new_params.get(k, v) - v) > 1e-9
            for k, v in params.items()
        )

        if changed:
            self._params[key] = new_params
            self._last_adjusted[key] = now
            print(f"[ADAPT] {symbol} {strategy_id} | "
                  f"WR={wr:.2f} DD={dd:.2f} PF={pf:.2f} CL={cl} | "
                  f"params updated: {_diff(params, new_params)}")

        return changed, new_params

    # ------------------------------------------------------------------
    # STRATEGY-SPECIFIC RULES
    # ------------------------------------------------------------------

    def _adapt_s01(self, sym, wr, pf, dd, cl, p: dict) -> dict:
        q = dict(p)
        if wr < 0.40:
            q["S01_ENTRY_Z"] = self._clamp("S01_ENTRY_Z", q["S01_ENTRY_Z"] + 0.1)
        return q

    def _adapt_s06(self, sym, wr, pf, dd, cl, p: dict) -> dict:
        q = dict(p)
        if wr < 0.40:
            q["S06_ER_THRESH"] = self._clamp("S06_ER_THRESH", q["S06_ER_THRESH"] + 0.05)
        if dd > 0.30:
            q["S06_SL_ATR"] = self._clamp("S06_SL_ATR", q["S06_SL_ATR"] - 0.1)
        return q

    def _adapt_s07(self, sym, wr, pf, dd, cl, p: dict) -> dict:
        q = dict(p)
        if wr < 0.45:
            q["S07_RSI_BUY"]  = self._clamp("S07_RSI_BUY",  q["S07_RSI_BUY"]  - 2.0)
            q["S07_RSI_SELL"] = self._clamp("S07_RSI_SELL", q["S07_RSI_SELL"] + 2.0)
        if dd > 0.25:
            q["S07_VOL_FILTER"] = self._clamp("S07_VOL_FILTER", q["S07_VOL_FILTER"] - 0.1)
        return q

    def _adapt_s10(self, sym, wr, pf, dd, cl, p: dict) -> dict:
        q = dict(p)
        if wr < 0.30:
            q["S10_ENTRY_PERIOD"] = self._clamp("S10_ENTRY_PERIOD",
                                                q["S10_ENTRY_PERIOD"] + 2)
        if wr > 0.55:
            q["S10_ENTRY_PERIOD"] = self._clamp("S10_ENTRY_PERIOD",
                                                q["S10_ENTRY_PERIOD"] - 2)
        if dd > 0.40:
            q["S10_MAX_UNITS"] = self._clamp("S10_MAX_UNITS",
                                             q["S10_MAX_UNITS"] - 1)
        if cl >= 5:
            q["S10_BREAKOUT_BUF"] = self._clamp("S10_BREAKOUT_BUF",
                                                q["S10_BREAKOUT_BUF"] + 0.05)
        return q

    def _adapt_s14(self, sym, wr, pf, dd, cl, p: dict) -> dict:
        q = dict(p)
        if wr < 0.40:
            q["S14_SQUEEZE_MIN"] = self._clamp("S14_SQUEEZE_MIN",
                                               q["S14_SQUEEZE_MIN"] + 1)
        return q

    def _adapt_s15(self, sym, wr, pf, dd, cl, p: dict) -> dict:
        q = dict(p)
        if dd > 0.35:
            q["S15_MAX_ORDERS"] = self._clamp("S15_MAX_ORDERS",
                                              q["S15_MAX_ORDERS"] - 2)
            q["S15_BASE_STEP"]  = self._clamp("S15_BASE_STEP",
                                              q["S15_BASE_STEP"] + 20.0)
        return q

    def _adapt_s16(self, sym, wr, pf, dd, cl, p: dict) -> dict:
        q = dict(p)
        if wr < 0.45:
            q["S16_PATTERN_SCORE_MIN"] = self._clamp("S16_PATTERN_SCORE_MIN",
                                                      q["S16_PATTERN_SCORE_MIN"] + 5.0)
            q["S16_VELOCITY_THRESH"]   = self._clamp("S16_VELOCITY_THRESH",
                                                      q["S16_VELOCITY_THRESH"] + 0.2)
        return q

    # ------------------------------------------------------------------
    # HELPERS
    # ------------------------------------------------------------------

    def _clamp(self, key: str, value: float) -> float:
        """Enforce PARAM_BOUNDS for the given key."""
        bounds = PARAM_BOUNDS.get(key)
        if bounds is None:
            return value
        lo, hi, _ = bounds
        return max(lo, min(hi, value))


# ========================================================================
# MODULE HELPER
# ========================================================================

def _diff(old: dict, new: dict) -> dict:
    """Return only keys whose value changed."""
    return {k: (old.get(k), new[k]) for k in new if abs(new[k] - old.get(k, new[k])) > 1e-9}
