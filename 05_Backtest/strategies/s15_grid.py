"""
S15 Immortal Grid -- Python replica of S15_Grid.mqh core logic.
Simplified for backtesting: no hidden TP/SL, no trailing, no MM manager.
Core: place BUY below price, SELL above price at grid levels.
Grid spacing = base_step * elastic_factor (ATR-adjusted).
"""
import numpy as np
import pandas as pd

from strategies.base import BaseStrategy
from strategies import indicators as ind


class S15Grid(BaseStrategy):
    name = "S15_Grid"

    def default_params(self) -> dict:
        return {
            "max_levels": 10,
            "base_step_pips": 200,     # Grid step in points
            "elastic_factor": 1.5,     # ATR multiplier for dynamic spacing
            "atr_period": 14,
            "tp_pips": 150,            # TP per grid order in points
            "sl_pips": 500,            # SL per grid order in points
            "conf_threshold": 0.65,    # Min confidence to place grid
            "atr_ratio_thresh": 0.8,   # ATR ratio protection
        }

    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        """
        Grid strategy signal generation.
        In bar-based backtest: generate alternating BUY/SELL signals
        when price moves grid_step away from last entry.
        """
        p = {**self.default_params(), **params}

        close = df["close"].values.astype(float)
        high = df["high"]
        low = df["low"]

        atr_s = ind.atr(high, df["low"], df["close"], p["atr_period"])

        n = len(df)
        signal = np.zeros(n, dtype=int)
        sl_dist = np.zeros(n)
        tp_dist = np.zeros(n)
        confidence = np.zeros(n)

        last_grid_price = 0.0
        grid_count = 0
        warmup = p["atr_period"] + 5

        for i in range(warmup, n):
            a = atr_s.iloc[i]
            if np.isnan(a) or a < 1e-10:
                continue

            price = close[i]
            grid_step = a * p["elastic_factor"]

            # ATR ratio protection
            if i > p["atr_period"] + 20:
                atr_prev = atr_s.iloc[i - 20:i].mean()
                if atr_prev > 0 and a / atr_prev > 1.0 / p["atr_ratio_thresh"]:
                    continue  # Skip during volatile spikes

            if last_grid_price == 0.0:
                last_grid_price = price
                continue

            dist = price - last_grid_price

            # Place BUY when price drops grid_step, SELL when rises grid_step
            if dist <= -grid_step and grid_count < p["max_levels"]:
                signal[i] = 1  # BUY at lower grid level
                sl_dist[i] = grid_step * 2.5
                tp_dist[i] = grid_step * 0.75
                confidence[i] = min(abs(dist) / (grid_step * 2), 1.0)
                last_grid_price = price
                grid_count += 1
            elif dist >= grid_step and grid_count < p["max_levels"]:
                signal[i] = -1  # SELL at upper grid level
                sl_dist[i] = grid_step * 2.5
                tp_dist[i] = grid_step * 0.75
                confidence[i] = min(abs(dist) / (grid_step * 2), 1.0)
                last_grid_price = price
                grid_count += 1

            # Reset grid count periodically (simulate grid profit-taking)
            if grid_count > 0 and abs(dist) < grid_step * 0.3:
                grid_count = max(0, grid_count - 1)

        return pd.DataFrame({
            "signal": signal,
            "sl_dist": sl_dist,
            "tp_dist": tp_dist,
            "confidence": confidence,
        }, index=df.index)
