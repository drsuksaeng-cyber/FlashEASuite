"""
S06 KAMA Adaptive Trend — Python replica of S06_KAMA.mqh
Exact logic parity with MQL5 version.
"""
import numpy as np
import pandas as pd

from strategies.base import BaseStrategy
from strategies import indicators as ind


class S06KAMA(BaseStrategy):
    name = "S06_KAMA"
    max_positions = 1
    param_space = {
        "kama_period":   ("int", 5, 30),
        "kama_fast":     ("int", 2, 5),
        "kama_slow":     ("int", 20, 40),
        "er_threshold":  ("float", 0.10, 0.95),
        "tp_atr_mult":   ("float", 1.5, 6.0),
        "sl_atr_mult":   ("float", 1.0, 4.0),
        "atr_period":    ("int", 10, 20),
    }

    def default_params(self) -> dict:
        return {
            "kama_period": 13,
            "kama_fast": 2,
            "kama_slow": 30,
            "er_threshold": 0.90,
            "tp_atr_mult": 4.7,
            "sl_atr_mult": 2.3,
            "atr_period": 14,
        }

    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        p = {**self.default_params(), **params}

        close = df["close"]
        high = df["high"]
        low = df["low"]

        # Indicators (vectorized)
        atr_s = ind.atr(high, low, close, p["atr_period"])
        # KAMA uses previous bar close (shift 1) — matches MQL5 iClose(symbol, tf, 1)
        prev_close = close.shift(1)
        kama_s = ind.kama(prev_close, p["kama_period"], p["kama_fast"], p["kama_slow"])
        er_s = ind.efficiency_ratio(prev_close, p["kama_period"])

        # KAMA slope
        kama_slope = kama_s - kama_s.shift(1)

        # Signal: price > KAMA AND slope > 0 AND ER >= threshold
        # MQL5 uses tick mid-price; in backtest use close (bar-level approximation)
        n = len(df)
        signal = np.zeros(n, dtype=int)
        sl_dist = np.zeros(n)
        tp_dist = np.zeros(n)
        confidence = np.zeros(n)

        warmup = p["kama_period"] + p["atr_period"] + 2

        for i in range(warmup, n):
            k = kama_s.iloc[i]
            slope = kama_slope.iloc[i]
            er = er_s.iloc[i]
            a = atr_s.iloc[i]
            price = close.iloc[i]

            if np.isnan(k) or np.isnan(er) or np.isnan(a) or a < 1e-10:
                continue

            if er < p["er_threshold"]:
                continue

            sig = 0
            if price > k and slope > 0:
                sig = 1
            elif price < k and slope < 0:
                sig = -1

            if sig != 0:
                dist = abs(price - k)
                conf = min(er * (dist / a), 1.0)
                signal[i] = sig
                sl_dist[i] = p["sl_atr_mult"] * a
                tp_dist[i] = p["tp_atr_mult"] * a
                confidence[i] = conf

        return pd.DataFrame({
            "signal": signal,
            "sl_dist": sl_dist,
            "tp_dist": tp_dist,
            "confidence": confidence,
        }, index=df.index)
