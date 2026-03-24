"""
S07 Mean Reversion (Volatility-Filtered) -- Python replica of S07_MeanReversion.mqh
Entry Long:  RSI < 30 AND Stochastic < 20
Entry Short: RSI > 70 AND Stochastic > 80
Vol Filter:  ATR < VolFilter * MA(ATR,20)
TP: BB middle band | SL: 2 * ATR
"""
import numpy as np
import pandas as pd

from strategies.base import BaseStrategy
from strategies import indicators as ind


def _rsi(close: pd.Series, period: int = 14) -> pd.Series:
    """RSI matching MQL5 iRSI (Wilder's smoothing)."""
    delta = close.diff()
    gain = delta.clip(lower=0)
    loss = (-delta).clip(lower=0)
    avg_gain = gain.ewm(alpha=1.0 / period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1.0 / period, adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0, 1e-10)
    return 100.0 - (100.0 / (1.0 + rs))


def _stochastic(high: pd.Series, low: pd.Series, close: pd.Series,
                k_period: int = 14, d_period: int = 3, slowing: int = 3) -> tuple:
    """Stochastic %K and %D matching MQL5 iStochastic(STO_LOWHIGH, MODE_SMA)."""
    lowest = low.rolling(k_period).min()
    highest = high.rolling(k_period).max()
    raw_k = 100.0 * (close - lowest) / (highest - lowest).replace(0, 1e-10)
    # Slowing (SMA of raw %K)
    k = raw_k.rolling(slowing).mean()
    # %D = SMA of %K
    d = k.rolling(d_period).mean()
    return k, d


class S07MeanReversion(BaseStrategy):
    name = "S07_MeanReversion"

    def default_params(self) -> dict:
        return {
            "rsi_period": 14,
            "rsi_buy": 30.0,
            "rsi_sell": 70.0,
            "stoch_k": 14,
            "stoch_d": 3,
            "stoch_slow": 3,
            "stoch_buy": 20.0,
            "stoch_sell": 80.0,
            "atr_period": 14,
            "atr_ma": 20,
            "vol_filter": 1.3,
            "bb_period": 20,
            "bb_dev": 2.0,
            "sl_atr_mult": 2.0,
            "tp_atr_mult": 1.5,
        }

    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        p = {**self.default_params(), **params}

        close = df["close"]
        high = df["high"]
        low = df["low"]

        # Indicators
        rsi = _rsi(close, p["rsi_period"])
        stoch_k, _ = _stochastic(high, low, close, p["stoch_k"], p["stoch_d"], p["stoch_slow"])
        atr_s = ind.atr(high, low, close, p["atr_period"])
        atr_ma = atr_s.rolling(p["atr_ma"]).mean()
        bb_mid, _, _ = ind.bollinger_bands(close, p["bb_period"], p["bb_dev"])

        n = len(df)
        signal = np.zeros(n, dtype=int)
        sl_dist = np.zeros(n)
        tp_dist = np.zeros(n)
        confidence = np.zeros(n)

        warmup = max(p["rsi_period"], p["stoch_k"], p["atr_period"], p["bb_period"], p["atr_ma"]) + 5

        for i in range(warmup, n):
            r = rsi.iloc[i]
            sk = stoch_k.iloc[i]
            a = atr_s.iloc[i]
            am = atr_ma.iloc[i]
            bm = bb_mid.iloc[i]

            if np.isnan(r) or np.isnan(sk) or np.isnan(a) or np.isnan(am):
                continue
            if a < 1e-10:
                continue

            # Volatility filter
            vol_ratio = a / am if am > 0 else 0.0
            if vol_ratio > p["vol_filter"]:
                continue

            sig = 0
            # Long: RSI oversold + Stoch oversold
            if r < p["rsi_buy"] and sk < p["stoch_buy"]:
                sig = 1
            # Short: RSI overbought + Stoch overbought
            elif r > p["rsi_sell"] and sk > p["stoch_sell"]:
                sig = -1

            if sig != 0:
                price = close.iloc[i]
                # TP: distance to BB middle band, fallback to ATR-based
                tp_bb = abs(bm - price) if not np.isnan(bm) else 0.0
                tp = tp_bb if tp_bb > a * 0.5 else p["tp_atr_mult"] * a

                # Confidence
                rsi_z = abs(r - 50.0) / 50.0
                stoch_conf = 0.0
                if sk < p["stoch_buy"]:
                    stoch_conf = (p["stoch_buy"] - sk) / p["stoch_buy"]
                elif sk > p["stoch_sell"]:
                    stoch_conf = (sk - p["stoch_sell"]) / (100.0 - p["stoch_sell"])

                vol_factor = 1.0
                if vol_ratio <= 1.0:
                    vol_factor = 1.0
                elif vol_ratio <= p["vol_filter"]:
                    vol_factor = 1.0 - (vol_ratio - 1.0) / (p["vol_filter"] - 1.0) * 0.3

                conf = (rsi_z * 0.5 + stoch_conf * 0.5) * vol_factor
                conf = max(0.0, min(1.0, conf))

                signal[i] = sig
                sl_dist[i] = p["sl_atr_mult"] * a
                tp_dist[i] = tp
                confidence[i] = conf

        return pd.DataFrame({
            "signal": signal,
            "sl_dist": sl_dist,
            "tp_dist": tp_dist,
            "confidence": confidence,
        }, index=df.index)
