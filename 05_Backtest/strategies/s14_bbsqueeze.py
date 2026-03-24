"""
S14 BB Squeeze Breakout — Python replica of S14_BBSqueeze.mqh
Exact logic parity with MQL5 version.
"""
import numpy as np
import pandas as pd

from strategies.base import BaseStrategy
from strategies import indicators as ind


class S14BBSqueeze(BaseStrategy):
    name = "S14_BBSqueeze"
    max_positions = 1
    param_space = {
        "bb_period":     ("int", 15, 60),
        "bb_deviation":  ("float", 1.5, 3.0),
        "kc_period":     ("int", 10, 40),
        "kc_atr_mult":   ("float", 0.8, 2.0),
        "squeeze_min":   ("int", 3, 12),
        "breakout_mom":  ("float", 0.05, 0.5),
        "sl_atr_mult":   ("float", 1.5, 5.0),
        "tp_atr_mult":   ("float", 1.5, 6.0),
        "atr_period":    ("int", 10, 20),
        "lr_period":     ("int", 8, 20),
    }

    def default_params(self) -> dict:
        return {
            "bb_period": 25,
            "bb_deviation": 2.0,
            "kc_period": 20,
            "kc_atr_mult": 1.15,
            "squeeze_min": 6,
            "breakout_mom": 0.1,
            "sl_atr_mult": 3.4,
            "tp_atr_mult": 3.4,
            "atr_period": 14,
            "lr_period": 14,
        }

    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        p = {**self.default_params(), **params}

        close = df["close"]
        high = df["high"]
        low = df["low"]

        # Indicators (vectorized)
        atr_s = ind.atr(high, low, close, p["atr_period"])
        _, bb_upper, bb_lower = ind.bollinger_bands(close, p["bb_period"], p["bb_deviation"])
        bb_width = bb_upper - bb_lower
        kc_width = ind.keltner_channel_width(atr_s, p["kc_atr_mult"])
        lr_slope = ind.linear_regression_slope(close, p["lr_period"], atr_s)

        # Squeeze detection: BB inside KC
        in_squeeze = (bb_width < kc_width) & (kc_width > 1e-10)

        # Bar-by-bar squeeze state (stateful — must loop)
        n = len(df)
        signal = np.zeros(n, dtype=int)
        sl_dist = np.zeros(n)
        tp_dist = np.zeros(n)
        confidence = np.zeros(n)

        squeeze_bars = 0
        was_in_squeeze = False

        for i in range(max(p["bb_period"], p["lr_period"], p["atr_period"]), n):
            if np.isnan(in_squeeze.iloc[i]) or np.isnan(lr_slope.iloc[i]):
                continue

            # Squeeze state machine (matches MQL5 Analyze bar-close guard)
            if in_squeeze.iloc[i]:
                squeeze_bars += 1
                was_in_squeeze = False
            else:
                was_in_squeeze = (squeeze_bars >= p["squeeze_min"])
                squeeze_bars = 0

            # Signal on squeeze release
            slope = lr_slope.iloc[i]
            if was_in_squeeze and abs(slope) >= p["breakout_mom"]:
                a = atr_s.iloc[i]
                if a > 1e-10:
                    sig = 1 if slope > 0 else -1
                    signal[i] = sig
                    sl_dist[i] = p["sl_atr_mult"] * a
                    tp_dist[i] = p["tp_atr_mult"] * a
                    confidence[i] = min(abs(slope), 1.0)

        result = pd.DataFrame({
            "signal": signal,
            "sl_dist": sl_dist,
            "tp_dist": tp_dist,
            "confidence": confidence,
        }, index=df.index)

        return result
