"""
Vectorized Indicators — exact MQL5 parity
All functions take pandas Series and return pandas Series/ndarray.
"""
import numpy as np
import pandas as pd


def atr(high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14) -> pd.Series:
    """Wilder's ATR (matches MQL5 iATR — uses EWM smoothing, not SMA)."""
    prev_close = close.shift(1)
    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)
    # Wilder's smoothing = EWM with alpha=1/period
    return tr.ewm(alpha=1.0 / period, adjust=False).mean()


def ema(series: pd.Series, period: int) -> pd.Series:
    """EMA matching MQL5 iMA(MODE_EMA)."""
    return series.ewm(span=period, adjust=False).mean()


def sma(series: pd.Series, period: int) -> pd.Series:
    """Simple Moving Average."""
    return series.rolling(period).mean()


def bollinger_bands(close: pd.Series, period: int = 20, deviation: float = 2.0):
    """Returns (middle, upper, lower) matching MQL5 iBands."""
    mid = sma(close, period)
    std = close.rolling(period).std(ddof=0)  # MQL5 uses population std
    upper = mid + deviation * std
    lower = mid - deviation * std
    return mid, upper, lower


def keltner_channel_width(atr_series: pd.Series, kc_atr_mult: float) -> pd.Series:
    """KC width = 2 * ATR * multiplier (matches S14 _CalcKCWidth)."""
    return 2.0 * atr_series * kc_atr_mult


def donchian(high: pd.Series, low: pd.Series, period: int):
    """
    Donchian channel using bars 1..period (excludes current bar 0).
    Returns (channel_high, channel_low).
    Matches MQL5: CopyHigh(symbol, tf, 1, period, ...)
    """
    ch_high = high.shift(1).rolling(period).max()
    ch_low = low.shift(1).rolling(period).min()
    return ch_high, ch_low


def linear_regression_slope(close: pd.Series, period: int, atr_series: pd.Series) -> pd.Series:
    """
    LR slope normalized by ATR.
    Matches S14 _CalcLRSlope() exactly:
      x = 0..n-1, y = closes oldest->newest (reversed from ArraySetAsSeries)
    """
    slopes = pd.Series(np.nan, index=close.index)
    close_arr = close.values
    atr_arr = atr_series.values
    n = period

    for i in range(n, len(close_arr)):
        # closes[i-n+1 .. i] oldest to newest (like MQL5 reversed array)
        y = close_arr[i - n + 1: i + 1].astype(float)
        x = np.arange(n, dtype=float)
        sx = x.sum()
        sy = y.sum()
        sxy = (x * y).sum()
        sxx = (x * x).sum()
        denom = n * sxx - sx * sx
        if abs(denom) < 1e-10:
            slopes.iloc[i] = 0.0
        else:
            slope = (n * sxy - sx * sy) / denom
            a = atr_arr[i]
            slopes.iloc[i] = slope / a if a > 1e-10 else 0.0

    return slopes


def kama(close: pd.Series, period: int = 10, fast: int = 2, slow: int = 30) -> pd.Series:
    """
    Kaufman Adaptive Moving Average.
    Matches S06 _UpdateKAMA() exactly:
      ER = |close[0] - close[n]| / sum(|close[i] - close[i+1]|)
      SC = (ER * (FastSC - SlowSC) + SlowSC)^2
      KAMA[i] = KAMA[i-1] + SC * (close[i] - KAMA[i-1])
    """
    close_arr = close.values.astype(float)
    kama_arr = np.full(len(close_arr), np.nan)
    fast_sc = 2.0 / (fast + 1.0)
    slow_sc = 2.0 / (slow + 1.0)

    # Seed with first available close after enough bars
    if len(close_arr) <= period:
        return pd.Series(kama_arr, index=close.index)

    kama_arr[period] = close_arr[period]

    for i in range(period + 1, len(close_arr)):
        net_change = abs(close_arr[i] - close_arr[i - period])
        volatility = 0.0
        for j in range(period):
            volatility += abs(close_arr[i - j] - close_arr[i - j - 1])
        er = min(net_change / volatility, 1.0) if volatility > 1e-10 else 0.0
        sc = (er * (fast_sc - slow_sc) + slow_sc) ** 2
        kama_arr[i] = kama_arr[i - 1] + sc * (close_arr[i] - kama_arr[i - 1])

    return pd.Series(kama_arr, index=close.index)


def efficiency_ratio(close: pd.Series, period: int) -> pd.Series:
    """ER = |close[i] - close[i-n]| / sum(|close[j] - close[j-1]|, j=i-n+1..i)"""
    close_arr = close.values.astype(float)
    er_arr = np.full(len(close_arr), np.nan)

    for i in range(period, len(close_arr)):
        net = abs(close_arr[i] - close_arr[i - period])
        vol = 0.0
        for j in range(period):
            vol += abs(close_arr[i - j] - close_arr[i - j - 1])
        er_arr[i] = min(net / vol, 1.0) if vol > 1e-10 else 0.0

    return pd.Series(er_arr, index=close.index)
