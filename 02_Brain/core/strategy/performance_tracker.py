#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Performance Tracker — Per-symbol, per-strategy rolling trade statistics.

Tracks win rate, profit factor, drawdown, and consecutive losses.
Thread-safe (uses threading.Lock for all writes).

magic → strategy_id mapping: "S" + str(magic - 1000).zfill(2)
  e.g. magic=1010 → "S10"
"""

import threading
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Dict, Optional, Tuple


# ========================================================================
# DATA CLASSES
# ========================================================================

@dataclass
class TradeRecord:
    symbol:      str
    strategy_id: str    # "S01" – "S16"
    profit:      float
    is_win:      bool
    timestamp:   float  # epoch seconds


@dataclass
class StrategyPerf:
    trades:      deque = field(default_factory=lambda: deque(maxlen=50))
    equity_peak: float = 0.0   # running peak equity (sum of profits so far)
    equity_cur:  float = 0.0   # current equity


# ========================================================================
# PERFORMANCE TRACKER
# ========================================================================

class PerformanceTracker:
    """
    Rolling performance statistics per (symbol, strategy_id) pair.

    All public methods are thread-safe.
    """

    def __init__(self):
        self._lock  = threading.Lock()
        self._stats: Dict[Tuple[str, str], StrategyPerf] = {}

    # ------------------------------------------------------------------
    # WRITE
    # ------------------------------------------------------------------

    def record_trade(self, symbol: str, strategy_id: str,
                     profit: float, raw: dict = None) -> None:
        """
        Record one closed trade.

        :param symbol:      Normalised symbol ("XAUUSD", not "XAUUSD.tp")
        :param strategy_id: "S01"–"S16"
        :param profit:      Net P&L in account currency
        :param raw:         Original feedback dict (ignored here, reserved)
        """
        record = TradeRecord(
            symbol      = symbol,
            strategy_id = strategy_id,
            profit      = profit,
            is_win      = profit > 0,
            timestamp   = time.time()
        )

        key = (symbol, strategy_id)
        with self._lock:
            if key not in self._stats:
                self._stats[key] = StrategyPerf()
            perf = self._stats[key]

            perf.trades.append(record)
            perf.equity_cur += profit
            if perf.equity_cur > perf.equity_peak:
                perf.equity_peak = perf.equity_cur

    # ------------------------------------------------------------------
    # READ
    # ------------------------------------------------------------------

    def get_trade_count(self, symbol: str, strategy_id: str) -> int:
        with self._lock:
            perf = self._stats.get((symbol, strategy_id))
            return len(perf.trades) if perf else 0

    def get_win_rate(self, symbol: str, strategy_id: str) -> float:
        """Returns win rate in [0.0, 1.0]. Returns 0.0 if no trades."""
        with self._lock:
            perf = self._stats.get((symbol, strategy_id))
            if not perf or len(perf.trades) == 0:
                return 0.0
            wins = sum(1 for t in perf.trades if t.is_win)
            return wins / len(perf.trades)

    def get_profit_factor(self, symbol: str, strategy_id: str) -> float:
        """
        Gross profit / gross loss.
        Returns 1.0 if no losing trades (no loss to divide).
        """
        with self._lock:
            perf = self._stats.get((symbol, strategy_id))
            if not perf or len(perf.trades) == 0:
                return 1.0
            gross_profit = sum(t.profit for t in perf.trades if t.profit > 0)
            gross_loss   = sum(-t.profit for t in perf.trades if t.profit < 0)
            if gross_loss == 0:
                return gross_profit if gross_profit > 0 else 1.0
            return gross_profit / gross_loss

    def get_drawdown(self, symbol: str, strategy_id: str) -> float:
        """
        Current drawdown as a fraction of equity peak, in [0.0, 1.0].
        Returns 0.0 if peak == 0.
        """
        with self._lock:
            perf = self._stats.get((symbol, strategy_id))
            if not perf or perf.equity_peak <= 0:
                return 0.0
            dd = (perf.equity_peak - perf.equity_cur) / perf.equity_peak
            return max(0.0, dd)

    def get_consecutive_losses(self, symbol: str, strategy_id: str) -> int:
        """Count current streak of consecutive losses at tail of trade list."""
        with self._lock:
            perf = self._stats.get((symbol, strategy_id))
            if not perf or len(perf.trades) == 0:
                return 0
            streak = 0
            for trade in reversed(list(perf.trades)):
                if not trade.is_win:
                    streak += 1
                else:
                    break
            return streak

    def active_pairs(self):
        """Return list of (symbol, strategy_id) that have recorded trades."""
        with self._lock:
            return list(self._stats.keys())

    def get_summary(self) -> dict:
        """
        Return a snapshot dict for dashboard display.

        Structure: { (symbol, sid): {wr, pf, dd, trades, consec_loss} }
        """
        summary = {}
        with self._lock:
            for key, perf in self._stats.items():
                symbol, sid = key
                trades  = list(perf.trades)
                n       = len(trades)
                if n == 0:
                    continue

                wins   = sum(1 for t in trades if t.is_win)
                wr     = wins / n
                gp     = sum(t.profit for t in trades if t.profit > 0)
                gl     = sum(-t.profit for t in trades if t.profit < 0)
                pf     = gp / gl if gl > 0 else (gp if gp > 0 else 1.0)
                dd     = max(0.0,
                             (perf.equity_peak - perf.equity_cur) / perf.equity_peak
                             if perf.equity_peak > 0 else 0.0)

                streak = 0
                for t in reversed(trades):
                    if not t.is_win:
                        streak += 1
                    else:
                        break

                summary[key] = {
                    "wr":          round(wr, 4),
                    "pf":          round(pf, 4),
                    "dd":          round(dd, 4),
                    "trades":      n,
                    "consec_loss": streak,
                }
        return summary

    # ------------------------------------------------------------------
    # UTILITY
    # ------------------------------------------------------------------

    @staticmethod
    def magic_to_strategy_id(magic: int) -> Optional[str]:
        """Convert MT5 magic number to strategy ID string."""
        if 1001 <= magic <= 1016:
            return f"S{magic - 1000:02d}"
        return None
