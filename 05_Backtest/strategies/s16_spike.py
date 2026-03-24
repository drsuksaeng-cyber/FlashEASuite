"""
S16 Spike Hunter -- Python replica of S16_Spike.mqh / Strategy_Spike.mqh core logic.
Simplified for bar-based backtesting.
Spike detection: ATR velocity + ROC momentum + volume surge.
Score >= 70 -> entry. Max hold = 15 bars (approximation of 900s).
"""
import numpy as np
import pandas as pd

from strategies.base import BaseStrategy
from strategies import indicators as ind


class S16Spike(BaseStrategy):
    name = "S16_Spike"

    def default_params(self) -> dict:
        return {
            "atr_period": 14,
            "velocity_thresh": 2.5,    # ATR spike multiplier
            "roc_period": 10,
            "roc_thresh": 0.5,         # ROC % threshold
            "volume_thresh": 2.0,      # Volume vs MA multiplier
            "volume_period": 20,
            "score_min": 70.0,         # Min pattern score for entry
            "sl_atr_mult": 0.4,        # SL = 0.4 * ATR (tight)
            "tp_atr_mult": 0.8,        # TP = 0.8 * ATR
            "max_hold_bars": 15,       # Force close after N bars (~900s at M1)
        }

    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        p = {**self.default_params(), **params}

        close = df["close"].values.astype(float)
        high = df["high"]
        low = df["low"]
        volume = df["tick_volume"].values.astype(float)

        atr_s = ind.atr(high, df["low"], df["close"], p["atr_period"])
        atr_arr = atr_s.values

        # Rate of Change (ROC)
        roc_period = p["roc_period"]

        # Volume MA
        vol_ma = pd.Series(volume).rolling(p["volume_period"]).mean().values

        n = len(df)
        signal = np.zeros(n, dtype=int)
        sl_dist = np.zeros(n)
        tp_dist = np.zeros(n)
        confidence = np.zeros(n)

        warmup = max(p["atr_period"], p["roc_period"], p["volume_period"]) + 5

        for i in range(warmup, n):
            a = atr_arr[i]
            if np.isnan(a) or a < 1e-10:
                continue

            # ATR velocity: current bar range vs ATR
            bar_range = high.iloc[i] - low.iloc[i]
            atr_velocity = bar_range / a if a > 0 else 0.0

            # ROC
            if i >= roc_period:
                prev_close = close[i - roc_period]
                roc = abs(close[i] - prev_close) / prev_close * 100.0 if prev_close > 0 else 0.0
            else:
                roc = 0.0

            # Volume surge
            vm = vol_ma[i]
            vol_ratio = volume[i] / vm if vm > 0 else 0.0

            # Spike score (matches Strategy_Spike.mqh CalculateSpikeScore)
            # 40% ATR velocity + 30% ROC + 10% volume + 20% direction consistency
            score_atr = min(atr_velocity / p["velocity_thresh"], 1.0) * 40.0
            score_roc = min(roc / p["roc_thresh"], 1.0) * 30.0 if roc > 0 else 0.0
            score_vol = min(vol_ratio / p["volume_thresh"], 1.0) * 10.0

            # Direction consistency (simplified: use last 5 bars)
            if i >= 5:
                up_count = sum(1 for j in range(i - 4, i + 1) if close[j] > close[j - 1])
                dir_score = abs(up_count - 2.5) / 2.5 * 20.0  # 0-20
            else:
                dir_score = 10.0

            total_score = score_atr + score_roc + score_vol + dir_score

            if total_score >= p["score_min"]:
                # Direction from price movement
                if close[i] > close[i - 1]:
                    sig = 1
                elif close[i] < close[i - 1]:
                    sig = -1
                else:
                    continue

                signal[i] = sig
                sl_dist[i] = p["sl_atr_mult"] * a
                tp_dist[i] = p["tp_atr_mult"] * a
                confidence[i] = min(total_score / 100.0, 1.0)

        return pd.DataFrame({
            "signal": signal,
            "sl_dist": sl_dist,
            "tp_dist": tp_dist,
            "confidence": confidence,
        }, index=df.index)
