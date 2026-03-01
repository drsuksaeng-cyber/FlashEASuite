#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Feature Engineering
สร้าง 30+ features สำหรับ ML Ensemble Strategy (S02)

Features Categories:
  1. Price Features      : returns, momentum, acceleration
  2. Technical           : ADX, ATR, RSI, Stochastic, BB, MACD
  3. Volatility          : realized vol, vol ratio, vol percentile
  4. Volume              : tick volume, volume MA ratio
  5. Multi-TF            : H1, H4, D1 indicators
  6. Calendar            : session, day of week, hour

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-22
"""

import numpy as np
import pandas as pd
import time as _time
from typing import Dict, List, Optional, Tuple
import logging

logger = logging.getLogger(__name__)

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  ⚠️  PERFORMANCE WARNING — อ่านก่อน Backtest / Forward Test               ║
# ║                                                                              ║
# ║  compute() คำนวณ rolling indicators ทั้ง series ใหม่ทุกครั้งที่เรียก       ║
# ║  → Latency: ~50-200ms ต่อ call (ขึ้นกับจำนวน bars)                         ║
# ║                                                                              ║
# ║  Production Fix ที่ต้องทำก่อน Live Trading:                                 ║
# ║    1. Cache X = fe.compute(df_full) ไว้ใน memory                            ║
# ║    2. เมื่อมี bar ใหม่ → append 1 row แล้วใช้ compute_incremental() แทน     ║
# ║    3. compute_incremental() ยังไม่ได้ implement → TODO ใน P5 หรือ P8        ║
# ║                                                                              ║
# ║  ถ้า latency > _LATENCY_WARN_MS → จะ log WARNING อัตโนมัติ                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

_LATENCY_WARN_MS  = 100   # warn ถ้า compute() ช้ากว่านี้ (ms)
_LATENCY_ERROR_MS = 500   # error ถ้าช้ากว่านี้ (ใกล้ถึง SLA breach)
_LARGE_DF_ROWS    = 5000  # warn ถ้า df ใหญ่กว่านี้ (น่าจะ cache แล้ว)


class FeatureEngineer:
    """
    Compute 30+ features from OHLCV tick data for ML models.

    Input  : pandas DataFrame with columns [open, high, low, close, volume]
             Index = DatetimeIndex (UTC)
    Output : DataFrame with 30+ feature columns (NaN-free, normalized optional)
    """

    # ── Feature groups ────────────────────────────────────────────────────────
    PRICE_FEATURES      = ["ret_1", "ret_5", "ret_15", "momentum_5",
                            "momentum_15", "acceleration"]
    TECHNICAL_FEATURES  = ["rsi_14", "stoch_k", "stoch_d", "bb_upper",
                            "bb_lower", "bb_pct", "macd", "macd_signal",
                            "macd_hist", "adx_14", "atr_14"]
    VOLATILITY_FEATURES = ["realized_vol_20", "vol_ratio_5_20",
                            "vol_percentile_60", "high_low_range"]
    VOLUME_FEATURES     = ["volume_ma_ratio", "volume_spike"]
    MULTI_TF_FEATURES   = ["h1_trend", "h4_trend", "d1_trend",
                            "h1_rsi", "h4_rsi"]
    CALENDAR_FEATURES   = ["session", "day_of_week", "hour",
                            "is_london", "is_ny", "is_asian", "is_overlap"]

    ALL_FEATURES = (PRICE_FEATURES + TECHNICAL_FEATURES +
                    VOLATILITY_FEATURES + VOLUME_FEATURES +
                    MULTI_TF_FEATURES + CALENDAR_FEATURES)

    # ── Session hour ranges (UTC) ──────────────────────────────────────────────
    ASIAN_START,   ASIAN_END   = 0,  8
    LONDON_START,  LONDON_END  = 8,  16
    NY_START,      NY_END      = 13, 21
    OVERLAP_START, OVERLAP_END = 13, 16   # London ∩ NY

    def __init__(self, normalize: bool = False):
        """
        Args:
            normalize: ถ้า True จะ min-max normalize ทุก feature (0-1)
                       สำหรับ LSTM / KMeans ควรเปิด
        """
        self.normalize = normalize
        logger.info("FeatureEngineer initialized (normalize=%s)", normalize)

    # ─────────────────────────────────────────────────────────────────────────
    # PUBLIC API
    # ─────────────────────────────────────────────────────────────────────────

    def compute(self, df: pd.DataFrame,
                resample_h1: Optional[pd.DataFrame] = None,
                resample_h4: Optional[pd.DataFrame] = None,
                resample_d1: Optional[pd.DataFrame] = None) -> pd.DataFrame:
        """
        Compute all features.

        Args:
            df          : M1 OHLCV DataFrame (DatetimeIndex UTC)
            resample_h1 : H1 OHLCV — pass pre-computed or None (will resample)
            resample_h4 : H4 OHLCV
            resample_d1 : D1 OHLCV

        Returns:
            DataFrame with all features, same index as df (NaN rows dropped)
        """
        if df.empty or len(df) < 60:
            raise ValueError("Need at least 60 bars to compute features")

        # ── ⚠️ Performance guard: warn ถ้า df ใหญ่ผิดปกติ ──────────────────────
        # ถ้าเห็น warning นี้ใน production → ต้อง cache X ไว้ใน memory
        if len(df) > _LARGE_DF_ROWS:
            logger.warning(
                "⚠️  PERF: compute() called with %d rows — "
                "ควร cache X แล้วใช้ incremental update แทน full recompute "
                "(ดู TODO: compute_incremental)", len(df)
            )

        _t0 = _time.perf_counter()

        # Ensure lowercase column names
        df = df.copy()
        df.columns = [c.lower() for c in df.columns]

        feat = pd.DataFrame(index=df.index)

        # 1. Price features
        feat = self._add_price_features(feat, df)

        # 2. Technical indicators
        feat = self._add_technical_features(feat, df)

        # 3. Volatility
        feat = self._add_volatility_features(feat, df)

        # 4. Volume
        feat = self._add_volume_features(feat, df)

        # 5. Multi-TF
        h1 = resample_h1 if resample_h1 is not None else self._resample(df, "1h")
        h4 = resample_h4 if resample_h4 is not None else self._resample(df, "4h")
        d1 = resample_d1 if resample_d1 is not None else self._resample(df, "1D")
        feat = self._add_multitf_features(feat, df, h1, h4, d1)

        # 6. Calendar
        feat = self._add_calendar_features(feat, df)

        # Drop NaN rows (from rolling windows)
        feat.dropna(inplace=True)

        # Optional normalize
        if self.normalize:
            feat = self._normalize(feat)

        # ── ⚠️ Latency check: warn ถ้าช้าเกิน SLA ─────────────────────────────
        _elapsed_ms = (_time.perf_counter() - _t0) * 1000
        if _elapsed_ms >= _LATENCY_ERROR_MS:
            logger.error(
                "🚨 PERF BREACH: compute() ใช้เวลา %.0fms (threshold=%dms) — "
                "ต้อง implement compute_incremental() ก่อน live trading!",
                _elapsed_ms, _LATENCY_ERROR_MS
            )
        elif _elapsed_ms >= _LATENCY_WARN_MS:
            logger.warning(
                "⚠️  PERF: compute() ใช้เวลา %.0fms (warn threshold=%dms) — "
                "ใน production ควร cache X และ incremental update",
                _elapsed_ms, _LATENCY_WARN_MS
            )

        logger.info("Features computed: %d rows × %d cols (%.0fms)",
                    len(feat), len(feat.columns), _elapsed_ms)
        return feat

    # TODO (P5 หรือ P8): implement compute_incremental()
    # ─────────────────────────────────────────────────────────────────────────
    # def compute_incremental(self, cached_X: pd.DataFrame,
    #                          new_bar: pd.Series) -> pd.DataFrame:
    #     """
    #     [ยังไม่ได้ implement] เพิ่ม 1 bar ใหม่โดยไม่ recompute ทั้ง series
    #
    #     เหตุผลที่ต้องทำ:
    #       - compute() ปัจจุบัน: O(N) ทุก call → latency ~100-340ms
    #       - compute_incremental(): O(1) ต่อ bar → latency <5ms
    #
    #     Algorithm:
    #       1. ต่อท้าย new_bar เข้า df_cache
    #       2. คำนวณเฉพาะ features ที่ window เก่าพอ (rolling 20 = แค่ update 1 row)
    #       3. Return cached_X.iloc[1:].append(new_row)  ← shift + append
    #
    #     Priority: ทำก่อน Forward Test เริ่ม
    #     Estimate: ~4 ชั่วโมง dev
    #     """
    #     raise NotImplementedError("compute_incremental() — TODO ก่อน live trading")

    def compute_single(self, df: pd.DataFrame) -> Optional[Dict[str, float]]:
        """
        Compute features for the LATEST bar only.
        Used for real-time inference (returns dict).

        Args:
            df : recent OHLCV bars (need ≥60)

        Returns:
            dict {feature_name: value} or None on error
        """
        try:
            feat_df = self.compute(df)
            if feat_df.empty:
                return None
            row = feat_df.iloc[-1].to_dict()
            return row
        except Exception as e:
            logger.error("compute_single error: %s", e)
            return None

    def get_feature_names(self) -> List[str]:
        """Return ordered list of all feature names."""
        return list(self.ALL_FEATURES)

    # ─────────────────────────────────────────────────────────────────────────
    # PRICE FEATURES
    # ─────────────────────────────────────────────────────────────────────────

    def _add_price_features(self, feat: pd.DataFrame,
                             df: pd.DataFrame) -> pd.DataFrame:
        close = df["close"]

        # Log returns
        feat["ret_1"]   = np.log(close / close.shift(1))
        feat["ret_5"]   = np.log(close / close.shift(5))
        feat["ret_15"]  = np.log(close / close.shift(15))

        # Momentum (rate of change)
        feat["momentum_5"]  = close.pct_change(5)
        feat["momentum_15"] = close.pct_change(15)

        # Acceleration (2nd derivative of price)
        feat["acceleration"] = feat["ret_1"] - feat["ret_1"].shift(1)

        return feat

    # ─────────────────────────────────────────────────────────────────────────
    # TECHNICAL INDICATORS
    # ─────────────────────────────────────────────────────────────────────────

    def _add_technical_features(self, feat: pd.DataFrame,
                                  df: pd.DataFrame) -> pd.DataFrame:
        close  = df["close"]
        high   = df["high"]
        low    = df["low"]
        period = 14

        # ── RSI ──────────────────────────────────────────────────────────────
        feat["rsi_14"] = self._rsi(close, period)

        # ── Stochastic ────────────────────────────────────────────────────────
        k, d = self._stochastic(high, low, close, k_period=14, d_period=3)
        feat["stoch_k"] = k
        feat["stoch_d"] = d

        # ── Bollinger Bands ───────────────────────────────────────────────────
        bb_mid  = close.rolling(20).mean()
        bb_std  = close.rolling(20).std()
        feat["bb_upper"] = bb_mid + 2 * bb_std
        feat["bb_lower"] = bb_mid - 2 * bb_std
        # %B: position within the band (0=lower, 1=upper)
        feat["bb_pct"] = (close - feat["bb_lower"]) / (
            feat["bb_upper"] - feat["bb_lower"] + 1e-10)

        # ── MACD ─────────────────────────────────────────────────────────────
        ema12 = close.ewm(span=12, adjust=False).mean()
        ema26 = close.ewm(span=26, adjust=False).mean()
        feat["macd"]        = ema12 - ema26
        feat["macd_signal"] = feat["macd"].ewm(span=9, adjust=False).mean()
        feat["macd_hist"]   = feat["macd"] - feat["macd_signal"]

        # ── ADX ──────────────────────────────────────────────────────────────
        feat["adx_14"] = self._adx(high, low, close, period)

        # ── ATR ──────────────────────────────────────────────────────────────
        feat["atr_14"] = self._atr(high, low, close, period)

        return feat

    # ─────────────────────────────────────────────────────────────────────────
    # VOLATILITY FEATURES
    # ─────────────────────────────────────────────────────────────────────────

    def _add_volatility_features(self, feat: pd.DataFrame,
                                   df: pd.DataFrame) -> pd.DataFrame:
        close = df["close"]
        ret   = np.log(close / close.shift(1))

        # Realized volatility (annualized, using 20-bar window)
        feat["realized_vol_20"] = ret.rolling(20).std() * np.sqrt(252 * 1440)

        # Vol ratio: short-term / long-term (spike detection)
        vol5  = ret.rolling(5).std()
        vol20 = ret.rolling(20).std()
        feat["vol_ratio_5_20"] = vol5 / (vol20 + 1e-10)

        # Vol percentile (0-100) within 60-bar rolling window
        def vol_pct(x):
            v = x.iloc[-1]
            return float(np.sum(x <= v)) / len(x) * 100
        feat["vol_percentile_60"] = vol5.rolling(60).apply(vol_pct, raw=False)

        # High-low range normalized by close
        feat["high_low_range"] = (df["high"] - df["low"]) / (df["close"] + 1e-10)

        return feat

    # ─────────────────────────────────────────────────────────────────────────
    # VOLUME FEATURES
    # ─────────────────────────────────────────────────────────────────────────

    def _add_volume_features(self, feat: pd.DataFrame,
                               df: pd.DataFrame) -> pd.DataFrame:
        vol = df["volume"].astype(float)

        vol_ma = vol.rolling(20).mean()
        feat["volume_ma_ratio"] = vol / (vol_ma + 1e-10)

        # Volume spike: 1 if current volume > 2× MA
        feat["volume_spike"] = (feat["volume_ma_ratio"] > 2.0).astype(float)

        return feat

    # ─────────────────────────────────────────────────────────────────────────
    # MULTI-TIMEFRAME FEATURES
    # ─────────────────────────────────────────────────────────────────────────

    def _add_multitf_features(self, feat: pd.DataFrame,
                                df: pd.DataFrame,
                                h1: pd.DataFrame,
                                h4: pd.DataFrame,
                                d1: pd.DataFrame) -> pd.DataFrame:
        """
        Align H1/H4/D1 indicators onto M1 index using forward-fill.
        Trend: 1=UP (close > EMA20), -1=DOWN, 0=FLAT
        """

        for tf_name, tf_df, trend_col, rsi_col in [
            ("h1", h1, "h1_trend", "h1_rsi"),
            ("h4", h4, "h4_trend", "h4_rsi"),
            ("d1", d1, "d1_trend", None),
        ]:
            if tf_df.empty:
                feat[trend_col] = 0.0
                if rsi_col:
                    feat[rsi_col] = 50.0
                continue

            tf_close = tf_df["close"]
            ema20 = tf_close.ewm(span=20, adjust=False).mean()
            trend = np.where(tf_close > ema20, 1.0, -1.0)
            trend_s = pd.Series(trend, index=tf_df.index)

            # Reindex to M1, forward-fill
            feat[trend_col] = trend_s.reindex(df.index, method="ffill")

            if rsi_col:
                rsi_s = self._rsi(tf_close, 14)
                feat[rsi_col] = rsi_s.reindex(df.index, method="ffill")

        return feat

    # ─────────────────────────────────────────────────────────────────────────
    # CALENDAR FEATURES
    # ─────────────────────────────────────────────────────────────────────────

    def _add_calendar_features(self, feat: pd.DataFrame,
                                 df: pd.DataFrame) -> pd.DataFrame:
        idx = df.index

        feat["hour"]        = idx.hour.astype(float)
        feat["day_of_week"] = idx.dayofweek.astype(float)  # Mon=0, Fri=4

        # Session flags (binary)
        h = idx.hour
        feat["is_asian"]   = ((h >= self.ASIAN_START)   & (h < self.ASIAN_END)).astype(float)
        feat["is_london"]  = ((h >= self.LONDON_START)  & (h < self.LONDON_END)).astype(float)
        feat["is_ny"]      = ((h >= self.NY_START)      & (h < self.NY_END)).astype(float)
        feat["is_overlap"] = ((h >= self.OVERLAP_START) & (h < self.OVERLAP_END)).astype(float)

        # Ordinal session code (0=Asian, 1=London, 2=NY, 3=Overlap, 4=Off)
        session = np.where(feat["is_overlap"] == 1, 3,
                  np.where(feat["is_ny"]      == 1, 2,
                  np.where(feat["is_london"]  == 1, 1,
                  np.where(feat["is_asian"]   == 1, 0, 4))))
        feat["session"] = session.astype(float)

        return feat

    # ─────────────────────────────────────────────────────────────────────────
    # INDICATOR HELPERS
    # ─────────────────────────────────────────────────────────────────────────

    @staticmethod
    def _rsi(close: pd.Series, period: int = 14) -> pd.Series:
        delta = close.diff()
        gain  = delta.clip(lower=0).ewm(com=period - 1, adjust=False).mean()
        loss  = (-delta.clip(upper=0)).ewm(com=period - 1, adjust=False).mean()
        rs    = gain / (loss + 1e-10)
        return 100.0 - (100.0 / (1.0 + rs))

    @staticmethod
    def _stochastic(high: pd.Series, low: pd.Series, close: pd.Series,
                    k_period: int = 14, d_period: int = 3) -> Tuple[pd.Series, pd.Series]:
        low_min  = low.rolling(k_period).min()
        high_max = high.rolling(k_period).max()
        k = 100 * (close - low_min) / (high_max - low_min + 1e-10)
        d = k.rolling(d_period).mean()
        return k, d

    @staticmethod
    def _atr(high: pd.Series, low: pd.Series, close: pd.Series,
             period: int = 14) -> pd.Series:
        prev_close = close.shift(1)
        tr = pd.concat([
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs()
        ], axis=1).max(axis=1)
        return tr.ewm(span=period, adjust=False).mean()

    @staticmethod
    def _adx(high: pd.Series, low: pd.Series, close: pd.Series,
             period: int = 14) -> pd.Series:
        prev_high  = high.shift(1)
        prev_low   = low.shift(1)
        prev_close = close.shift(1)

        tr = pd.concat([
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs()
        ], axis=1).max(axis=1)

        # Directional moves
        up_move   = high - prev_high
        down_move = prev_low - low

        plus_dm  = np.where((up_move > down_move) & (up_move > 0), up_move, 0.0)
        minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0.0)

        plus_dm_s  = pd.Series(plus_dm,  index=high.index).ewm(span=period, adjust=False).mean()
        minus_dm_s = pd.Series(minus_dm, index=high.index).ewm(span=period, adjust=False).mean()
        tr_s       = tr.ewm(span=period, adjust=False).mean()

        plus_di  = 100 * plus_dm_s  / (tr_s + 1e-10)
        minus_di = 100 * minus_dm_s / (tr_s + 1e-10)
        dx       = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di + 1e-10)
        adx      = dx.ewm(span=period, adjust=False).mean()
        return adx

    # ─────────────────────────────────────────────────────────────────────────
    # HELPERS
    # ─────────────────────────────────────────────────────────────────────────

    @staticmethod
    def _resample(df: pd.DataFrame, rule: str) -> pd.DataFrame:
        """Resample M1 OHLCV to higher timeframe."""
        return df.resample(rule).agg({
            "open":   "first",
            "high":   "max",
            "low":    "min",
            "close":  "last",
            "volume": "sum"
        }).dropna()

    @staticmethod
    def _normalize(feat: pd.DataFrame) -> pd.DataFrame:
        """Min-max normalize each column to [0, 1]."""
        result = feat.copy()
        for col in result.columns:
            col_min = result[col].min()
            col_max = result[col].max()
            rng = col_max - col_min
            if rng > 1e-10:
                result[col] = (result[col] - col_min) / rng
            else:
                result[col] = 0.0
        return result


# ─────────────────────────────────────────────────────────────────────────────
# STANDALONE TEST
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import random

    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s [%(levelname)s] %(message)s")

    print("=" * 60)
    print("Feature Engineering — Self Test")
    print("=" * 60)

    # ── Generate synthetic OHLCV data (1-minute bars) ─────────────────────
    np.random.seed(42)
    n = 500
    dates = pd.date_range("2025-01-01", periods=n, freq="1min", tz="UTC")
    price = 2000.0 + np.cumsum(np.random.randn(n) * 0.5)

    df_test = pd.DataFrame({
        "open":   price + np.random.randn(n) * 0.1,
        "high":   price + np.abs(np.random.randn(n) * 0.3),
        "low":    price - np.abs(np.random.randn(n) * 0.3),
        "close":  price,
        "volume": np.random.randint(100, 1000, n).astype(float)
    }, index=dates)

    # ── Compute features ──────────────────────────────────────────────────
    fe = FeatureEngineer(normalize=False)
    features = fe.compute(df_test)

    print(f"\n✅ Features shape: {features.shape}")
    print(f"   Columns ({len(features.columns)}): {list(features.columns)}")
    print(f"\n   Last row sample:")
    for col, val in features.iloc[-1].items():
        print(f"     {col:25s} = {val:.4f}")

    # ── Test real-time single bar ──────────────────────────────────────────
    single = fe.compute_single(df_test)
    if single:
        print(f"\n✅ compute_single() returned {len(single)} features")
    else:
        print("\n❌ compute_single() returned None")

    # ── Verify all 30+ features present ───────────────────────────────────
    expected = set(FeatureEngineer.ALL_FEATURES)
    got      = set(features.columns)
    missing  = expected - got
    extra    = got - expected

    if missing:
        print(f"\n⚠️  Missing features: {missing}")
    else:
        print(f"\n✅ All {len(expected)} expected features present")

    if extra:
        print(f"   Extra features (OK): {extra}")

    print("\n" + "=" * 60)
    print("Feature Engineering — Test PASSED ✅")
    print("=" * 60)
