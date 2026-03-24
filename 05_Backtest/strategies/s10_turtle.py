"""
S10 Turtle Trading (Modernized) — Python replica of S10_Turtle.mqh
Exact logic parity with MQL5 version.
Stateful: pyramiding requires bar-by-bar loop.
"""
import numpy as np
import pandas as pd

from strategies.base import BaseStrategy
from strategies import indicators as ind


class S10Turtle(BaseStrategy):
    name = "S10_Turtle"

    def default_params(self) -> dict:
        return {
            "entry_period": 10,
            "exit_period": 30,
            "atr_period": 20,
            "breakout_buf": 0.15,
            "max_units": 3,
            "unit_spacing": 0.5,
            "risk_pct": 0.2,
        }

    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        p = {**self.default_params(), **params}

        close = df["close"].values.astype(float)
        high = df["high"].values.astype(float)
        low = df["low"].values.astype(float)

        # Indicators (vectorized)
        atr_s = ind.atr(df["high"], df["low"], df["close"], p["atr_period"])
        entry_high, entry_low = ind.donchian(df["high"], df["low"], p["entry_period"])
        exit_high, exit_low = ind.donchian(df["high"], df["low"], p["exit_period"])

        atr_arr = atr_s.values
        eh = entry_high.values
        el = entry_low.values
        xh = exit_high.values
        xl = exit_low.values

        n = len(df)
        signal = np.zeros(n, dtype=int)
        sl_dist = np.zeros(n)
        tp_dist = np.zeros(n)  # Turtle: no fixed TP
        confidence = np.zeros(n)

        # Pyramid state
        direction = 0  # 1=long, -1=short, 0=flat
        unit_count = 0
        last_entry_price = 0.0
        last_signal_bar = -1  # same-bar guard

        warmup = max(p["entry_period"], p["exit_period"], p["atr_period"]) + 2

        for i in range(warmup, n):
            a = atr_arr[i]
            if np.isnan(a) or a < 1e-10:
                continue
            if np.isnan(eh[i]) or np.isnan(el[i]):
                continue

            price = close[i]

            # EXIT takes priority
            if direction != 0:
                exit_triggered = False
                if direction == 1 and price <= xl[i]:
                    exit_triggered = True
                elif direction == -1 and price >= xh[i]:
                    exit_triggered = True

                if exit_triggered:
                    signal[i] = 0  # exit signal (handled by backtester)
                    direction = 0
                    unit_count = 0
                    last_entry_price = 0.0
                    last_signal_bar = -1
                    continue

            # PYRAMID — add unit if already in trade
            if direction != 0:
                spacing = p["unit_spacing"] * a
                can_add = False
                if unit_count < p["max_units"]:
                    if direction == 1 and price >= last_entry_price + spacing:
                        can_add = True
                    elif direction == -1 and price <= last_entry_price - spacing:
                        can_add = True

                if can_add:
                    last_entry_price = price
                    unit_count += 1
                    signal[i] = direction
                    sl_dist[i] = 2.0 * a
                    confidence[i] = self._calc_confidence(
                        price, direction, eh[i], el[i], a,
                        close[max(0, i - p["entry_period"]):i]
                    )
                continue

            # BREAKOUT ENTRY
            sig = 0
            if price > eh[i] + p["breakout_buf"] * a:
                sig = 1
            elif price < el[i] - p["breakout_buf"] * a:
                sig = -1

            if sig != 0:
                # Same-bar guard
                if i == last_signal_bar:
                    continue
                last_signal_bar = i

                direction = sig
                unit_count = 1
                last_entry_price = price
                signal[i] = sig
                sl_dist[i] = 2.0 * a
                confidence[i] = self._calc_confidence(
                    price, sig, eh[i], el[i], a,
                    close[max(0, i - p["entry_period"]):i]
                )

        return pd.DataFrame({
            "signal": signal,
            "sl_dist": sl_dist,
            "tp_dist": tp_dist,
            "confidence": confidence,
        }, index=df.index)

    @staticmethod
    def _calc_confidence(price, direction, entry_high, entry_low, atr_val, recent_closes):
        """Matches S10 _CalcConfidence."""
        if atr_val < 1e-10:
            return 0.0
        if direction == 1:
            strength = price - entry_high
        elif direction == -1:
            strength = entry_low - price
        else:
            return 0.0

        # Trend consistency
        if len(recent_closes) < 2:
            consistency = 0.5
        else:
            same_dir = 0
            for j in range(len(recent_closes) - 1):
                rising = recent_closes[j + 1] > recent_closes[j]
                if direction == 1 and rising:
                    same_dir += 1
                elif direction == -1 and not rising:
                    same_dir += 1
            consistency = same_dir / (len(recent_closes) - 1)

        raw = (strength / atr_val) * consistency
        return min(max(raw, 0.0), 1.0)
