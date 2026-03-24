"""
S01 Statistical Arbitrage (Pairs Trading) -- Python replica of S01_StatArb.mqh
Spread = Price_A - Beta * Price_B
Z-Score = (Spread - MA) / StdDev
Entry: Long @ Z < -EntryZ, Short @ Z > +EntryZ
Exit: Z -> 0 or |Z| > StopZ
"""
import numpy as np
import pandas as pd

from strategies.base import BaseStrategy


class S01StatArb(BaseStrategy):
    name = "S01_StatArb"
    max_positions = 1
    param_space = {
        "period":        ("int", 10, 40),
        "entry_z":       ("float", 1.5, 3.0),
        "stop_z":        ("float", 2.5, 4.0),
        "beta":          ("float", 0.5, 1.5),
        "sl_atr_mult":   ("float", 1.0, 3.0),
        "tp_atr_mult":   ("float", 1.0, 3.0),
        "atr_period":    ("int", 10, 20),
    }

    def default_params(self) -> dict:
        return {
            "period": 20,
            "entry_z": 2.0,
            "stop_z": 3.0,
            "beta": 1.0,
            "sl_atr_mult": 2.0,
            "tp_atr_mult": 1.5,
            "atr_period": 14,
        }

    def compute_signals(self, df: pd.DataFrame, params: dict,
                        df_pair2: pd.DataFrame | None = None) -> pd.DataFrame:
        """
        For single-symbol backtesting: uses close as spread directly
        (no pair2 available). Z-score on price deviations from rolling mean.
        If df_pair2 provided: Spread = close_A - beta * close_B.
        """
        p = {**self.default_params(), **params}
        close = df["close"].values.astype(float)
        high = df["high"]
        low = df["low"]

        from strategies import indicators as ind
        atr_s = ind.atr(high, df["low"], df["close"], p["atr_period"])

        # Compute spread
        if df_pair2 is not None and len(df_pair2) == len(df):
            close_b = df_pair2["close"].values.astype(float)
            spread = close - p["beta"] * close_b
        else:
            # Single-symbol mode: use price deviation from SMA as "spread"
            spread = close.copy()

        # Rolling Z-Score
        period = p["period"]
        n = len(df)
        signal = np.zeros(n, dtype=int)
        sl_dist = np.zeros(n)
        tp_dist = np.zeros(n)
        confidence = np.zeros(n)

        # Circular buffer Z-score (matches MQL5)
        buf = np.zeros(period)
        buf_pos = 0
        buf_full = False

        in_long = False
        in_short = False

        for i in range(n):
            # Push spread to buffer
            buf[buf_pos] = spread[i]
            buf_pos = (buf_pos + 1) % period
            if buf_pos == 0:
                buf_full = True

            count = period if buf_full else buf_pos
            if count < period:
                continue

            mean = buf[:count].mean()
            std = buf[:count].std()
            if std < 1e-6:
                std = 1e-6
            z = (spread[i] - mean) / std

            a = atr_s.iloc[i] if not np.isnan(atr_s.iloc[i]) else 0.0
            if a < 1e-10:
                continue

            # Exit conditions
            if in_long and (abs(z) < 0.5 or z > p["stop_z"]):
                in_long = False
            if in_short and (abs(z) < 0.5 or z < -p["stop_z"]):
                in_short = False

            # Entry conditions
            if not in_long and not in_short:
                if z < -p["entry_z"]:
                    signal[i] = 1  # Long spread (buy A)
                    in_long = True
                    sl_dist[i] = p["sl_atr_mult"] * a
                    tp_dist[i] = p["tp_atr_mult"] * a
                    confidence[i] = min(abs(z) / p["stop_z"], 1.0)
                elif z > p["entry_z"]:
                    signal[i] = -1  # Short spread (sell A)
                    in_short = True
                    sl_dist[i] = p["sl_atr_mult"] * a
                    tp_dist[i] = p["tp_atr_mult"] * a
                    confidence[i] = min(abs(z) / p["stop_z"], 1.0)

        return pd.DataFrame({
            "signal": signal,
            "sl_dist": sl_dist,
            "tp_dist": tp_dist,
            "confidence": confidence,
        }, index=df.index)
