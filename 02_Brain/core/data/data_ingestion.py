#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Data Ingestion
02_Brain/core/data/data_ingestion.py

Bridges FeederEA → InfluxDB → ML Pipeline:
1. receive_from_feeder()  — Parse TICK_DATA/OHLC_DATA/INDICATOR_DATA messages
2. store_to_influxdb()    — Write parsed data to InfluxDB
3. calculate_derived_indicators() — ADX, ATR, RSI, BB from raw OHLC
4. get_feature_dataframe() — Ready-for-ML DataFrame

Message Formats from FeederEA (MessagePack arrays):
  TICK_DATA (type=1):      [1, seq_id, timestamp_ms, symbol, bid, ask, flags]
  OHLC_DATA (type=2):      [2, seq_id, timestamp_ms, symbol, tf, open, high, low, close, volume]
  INDICATOR_DATA (type=3):  [3, seq_id, timestamp_ms, symbol, tf, {indicator_dict}]

Author: Dr. Suksaeng Kukanok
Version: 1.0.2 (Fixed imports for 02_Brain/core/data/ location)
Date: 2025-12-06
"""

import sys
import os
import logging
from typing import Optional, Dict, Any, List, Tuple

import numpy as np
import pandas as pd

# ===========================================================================
# PATH FIX: Add 02_Brain/ to sys.path so 'import config' works
# This file is at: 02_Brain/core/data/data_ingestion.py
# config.py is at:  02_Brain/config.py
# So we go up 2 levels: core/data/ → core/ → 02_Brain/
# ===========================================================================
_brain_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
if _brain_dir not in sys.path:
    sys.path.insert(0, _brain_dir)

from config import (
    MSG_TICK_DATA, MSG_OHLC_DATA, MSG_INDICATOR_DATA,
    MEASUREMENT_TICKS, MEASUREMENT_OHLC, MEASUREMENT_INDICATORS,
    SYMBOLS, TIMEFRAMES,
    INDICATOR_RSI_PERIOD, INDICATOR_ATR_PERIOD,
    INDICATOR_ADX_PERIOD, INDICATOR_BB_PERIOD, INDICATOR_BB_STD,
    INFLUXDB_DEFAULT_LOOKBACK_BARS,
)
from core.data.influxdb_client import InfluxDBClient

logger = logging.getLogger("FlashEA.DataIngestion")


class DataIngestion:
    """
    Data ingestion pipeline: FeederEA → InfluxDB → ML features.
    
    Usage:
        db = InfluxDBClient()
        db.connect()
        ingestion = DataIngestion(db)
        
        # In ingestion worker loop:
        msg = msgpack.unpackb(raw_data)
        parsed = ingestion.receive_from_feeder(msg)
        ingestion.store_to_influxdb(parsed)
        
        # For ML pipeline:
        df = ingestion.get_feature_dataframe("XAUUSD", lookback_bars=500)
    """

    def __init__(self, db_client: InfluxDBClient):
        self._db = db_client

        # Stats
        self._ticks_ingested = 0
        self._ohlc_ingested = 0
        self._indicators_ingested = 0
        self._parse_errors = 0

    @property
    def stats(self) -> Dict[str, int]:
        return {
            "ticks_ingested": self._ticks_ingested,
            "ohlc_ingested": self._ohlc_ingested,
            "indicators_ingested": self._indicators_ingested,
            "parse_errors": self._parse_errors,
        }

    # =========================================================================
    # 1. Receive from Feeder — Parse MessagePack messages
    # =========================================================================

    def receive_from_feeder(self, msg: Any) -> Optional[Dict[str, Any]]:
        """
        Parse a deserialized MessagePack message from FeederEA.
        
        Args:
            msg: Deserialized MessagePack data (list or dict).
                 TICK:      [1, seq, ts_ms, symbol, bid, ask, flags]
                 OHLC:      [2, seq, ts_ms, symbol, tf, o, h, l, c, vol]
                 INDICATOR: [3, seq, ts_ms, symbol, tf, {dict}]
        
        Returns:
            Parsed dict with 'type' key, or None if invalid.
        """
        try:
            if not isinstance(msg, (list, tuple)) or len(msg) < 4:
                self._parse_errors += 1
                return None

            msg_type = int(msg[0])

            if msg_type == MSG_TICK_DATA:
                return self._parse_tick(msg)
            elif msg_type == MSG_OHLC_DATA:
                return self._parse_ohlc(msg)
            elif msg_type == MSG_INDICATOR_DATA:
                return self._parse_indicator(msg)
            else:
                return None

        except Exception as e:
            self._parse_errors += 1
            if self._parse_errors % 100 == 1:
                logger.error(f"receive_from_feeder error ({self._parse_errors}): {e}")
            return None

    def _parse_tick(self, msg: list) -> Optional[Dict[str, Any]]:
        """Parse TICK_DATA: [1, seq_id, timestamp_ms, symbol, bid, ask, flags]"""
        if len(msg) < 7:
            self._parse_errors += 1
            return None

        parsed = {
            "type": MSG_TICK_DATA,
            "seq_id": int(msg[1]),
            "timestamp_ms": int(msg[2]),
            "symbol": str(msg[3]),
            "bid": float(msg[4]),
            "ask": float(msg[5]),
            "volume": float(msg[6]),
        }

        if parsed["bid"] <= 0 or parsed["ask"] <= 0:
            self._parse_errors += 1
            return None
        if parsed["ask"] < parsed["bid"]:
            self._parse_errors += 1
            return None

        self._ticks_ingested += 1
        return parsed

    def _parse_ohlc(self, msg: list) -> Optional[Dict[str, Any]]:
        """Parse OHLC_DATA: [2, seq_id, timestamp_ms, symbol, tf, o, h, l, c, vol]"""
        if len(msg) < 10:
            self._parse_errors += 1
            return None

        parsed = {
            "type": MSG_OHLC_DATA,
            "seq_id": int(msg[1]),
            "timestamp_ms": int(msg[2]),
            "symbol": str(msg[3]),
            "timeframe": str(msg[4]),
            "open": float(msg[5]),
            "high": float(msg[6]),
            "low": float(msg[7]),
            "close": float(msg[8]),
            "volume": float(msg[9]),
        }

        if parsed["high"] < parsed["low"]:
            self._parse_errors += 1
            return None
        if parsed["open"] <= 0:
            self._parse_errors += 1
            return None

        self._ohlc_ingested += 1
        return parsed

    def _parse_indicator(self, msg: list) -> Optional[Dict[str, Any]]:
        """Parse INDICATOR_DATA: [3, seq_id, timestamp_ms, symbol, tf, {dict}]"""
        if len(msg) < 6:
            self._parse_errors += 1
            return None

        indicators = msg[5]
        if not isinstance(indicators, dict):
            self._parse_errors += 1
            return None

        parsed = {
            "type": MSG_INDICATOR_DATA,
            "seq_id": int(msg[1]),
            "timestamp_ms": int(msg[2]),
            "symbol": str(msg[3]),
            "timeframe": str(msg[4]),
            "indicators": {k: float(v) for k, v in indicators.items() if v is not None},
        }

        self._indicators_ingested += 1
        return parsed

    # =========================================================================
    # 2. Store to InfluxDB
    # =========================================================================

    def store_to_influxdb(self, parsed: Optional[Dict[str, Any]]) -> bool:
        """
        Store a parsed message to InfluxDB.
        
        Args:
            parsed: Output from receive_from_feeder()
            
        Returns:
            True if stored successfully.
        """
        if parsed is None:
            return False

        msg_type = parsed["type"]

        if msg_type == MSG_TICK_DATA:
            return self._db.write_tick(
                symbol=parsed["symbol"],
                bid=parsed["bid"],
                ask=parsed["ask"],
                volume=parsed["volume"],
                timestamp_ms=parsed["timestamp_ms"],
            )

        elif msg_type == MSG_OHLC_DATA:
            return self._db.write_ohlc(
                symbol=parsed["symbol"],
                tf=parsed["timeframe"],
                o=parsed["open"],
                h=parsed["high"],
                l=parsed["low"],
                c=parsed["close"],
                vol=parsed["volume"],
                timestamp_ms=parsed["timestamp_ms"],
            )

        elif msg_type == MSG_INDICATOR_DATA:
            return self._db.write_indicators(
                symbol=parsed["symbol"],
                tf=parsed["timeframe"],
                indicators_dict=parsed["indicators"],
                timestamp_ms=parsed["timestamp_ms"],
            )

        return False

    def ingest_message(self, msg: Any) -> bool:
        """
        Convenience: parse + store in one call.
        
        Args:
            msg: Raw deserialized MessagePack data
            
        Returns:
            True if message was valid and stored.
        """
        parsed = self.receive_from_feeder(msg)
        return self.store_to_influxdb(parsed)

    # =========================================================================
    # 3. Calculate Derived Indicators from OHLC
    # =========================================================================

    def calculate_derived_indicators(
        self,
        symbol: str,
        timeframe: str = "M15",
        lookback_bars: int = 200,
    ) -> Optional[Dict[str, float]]:
        """
        Calculate ADX, ATR, RSI, Bollinger Bands from latest OHLC data.
        
        Queries OHLC from InfluxDB, calculates indicators, writes back,
        and returns the latest values.
        
        Args:
            symbol:        e.g. "XAUUSD"
            timeframe:     e.g. "M15"
            lookback_bars: Number of OHLC bars to query (must be > max period)
            
        Returns:
            Dict of latest indicator values, or None if insufficient data.
        """
        min_bars = max(INDICATOR_RSI_PERIOD, INDICATOR_ATR_PERIOD,
                       INDICATOR_ADX_PERIOD, INDICATOR_BB_PERIOD) + 10

        df = self._db.query_latest(
            symbol=symbol,
            measurement=MEASUREMENT_OHLC,
            n_points=max(lookback_bars, min_bars),
            timeframe=timeframe,
        )

        if df.empty or len(df) < min_bars:
            logger.warning(
                f"Insufficient OHLC data for {symbol}/{timeframe}: "
                f"got {len(df)}, need {min_bars}"
            )
            return None

        for col in ("open", "high", "low", "close"):
            if col not in df.columns:
                logger.error(f"Missing column '{col}' in OHLC data")
                return None

        indicators = {}

        # RSI
        rsi = self._calc_rsi(df["close"], INDICATOR_RSI_PERIOD)
        if rsi is not None:
            indicators["rsi"] = rsi

        # ATR
        atr = self._calc_atr(df["high"], df["low"], df["close"], INDICATOR_ATR_PERIOD)
        if atr is not None:
            indicators["atr"] = atr

        # ADX
        adx = self._calc_adx(df["high"], df["low"], df["close"], INDICATOR_ADX_PERIOD)
        if adx is not None:
            indicators["adx"] = adx

        # Bollinger Bands
        bb = self._calc_bollinger(df["close"], INDICATOR_BB_PERIOD, INDICATOR_BB_STD)
        if bb is not None:
            indicators.update(bb)

        # Write calculated indicators back to InfluxDB
        if indicators and not df.empty:
            last_ts = df.index[-1]
            ts_ms = int(last_ts.timestamp() * 1000) if hasattr(last_ts, 'timestamp') else 0
            if ts_ms > 0:
                self._db.write_indicators(symbol, timeframe, indicators, ts_ms)

        return indicators if indicators else None

    # =========================================================================
    # 4. Get Feature DataFrame for ML
    # =========================================================================

    def get_feature_dataframe(
        self,
        symbol: str,
        lookback_bars: int = INFLUXDB_DEFAULT_LOOKBACK_BARS,
        timeframe: str = "M15",
    ) -> pd.DataFrame:
        """
        Build a feature DataFrame ready for ML model input.
        
        Combines OHLC + indicators into a single aligned DataFrame.
        Adds derived features: returns, log_returns, volatility, etc.
        
        Args:
            symbol:        e.g. "XAUUSD"
            lookback_bars: Number of bars
            timeframe:     e.g. "M15"
            
        Returns:
            DataFrame with columns:
                open, high, low, close, volume,
                rsi, atr, adx, bb_upper, bb_middle, bb_lower,
                returns, log_returns, volatility_20, hl_range, body_ratio
        """
        ohlc_df = self._db.query_latest(
            symbol=symbol,
            measurement=MEASUREMENT_OHLC,
            n_points=lookback_bars,
            timeframe=timeframe,
        )

        if ohlc_df.empty:
            logger.warning(f"No OHLC data for {symbol}/{timeframe}")
            return pd.DataFrame()

        ind_df = self._db.query_latest(
            symbol=symbol,
            measurement=MEASUREMENT_INDICATORS,
            n_points=lookback_bars,
            timeframe=timeframe,
        )

        if not ind_df.empty:
            feature_df = ohlc_df.join(ind_df, how="left", rsuffix="_ind")
            dup_cols = [c for c in feature_df.columns if c.endswith("_ind")]
            feature_df = feature_df.drop(columns=dup_cols, errors="ignore")
        else:
            feature_df = ohlc_df.copy()

        if "close" in feature_df.columns:
            feature_df = self._add_derived_features(feature_df)

        feature_df = feature_df.ffill().dropna()

        return feature_df

    def _add_derived_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Add derived ML features to OHLC DataFrame."""
        close = df["close"]

        df["returns"] = close.pct_change()
        df["log_returns"] = np.log(close / close.shift(1))
        df["volatility_20"] = df["returns"].rolling(window=20).std()

        if "high" in df.columns and "low" in df.columns:
            df["hl_range"] = (df["high"] - df["low"]) / close

        if all(c in df.columns for c in ("open", "high", "low")):
            hl_diff = df["high"] - df["low"]
            hl_diff = hl_diff.replace(0, np.nan)
            df["body_ratio"] = (df["close"] - df["open"]).abs() / hl_diff

        if "rsi" not in df.columns:
            rsi_series = self._calc_rsi_series(close, INDICATOR_RSI_PERIOD)
            if rsi_series is not None:
                df["rsi"] = rsi_series

        if "atr" not in df.columns and "high" in df.columns and "low" in df.columns:
            atr_series = self._calc_atr_series(
                df["high"], df["low"], close, INDICATOR_ATR_PERIOD
            )
            if atr_series is not None:
                df["atr"] = atr_series

        if "bb_upper" not in df.columns:
            sma = close.rolling(window=INDICATOR_BB_PERIOD).mean()
            std = close.rolling(window=INDICATOR_BB_PERIOD).std()
            df["bb_upper"] = sma + INDICATOR_BB_STD * std
            df["bb_middle"] = sma
            df["bb_lower"] = sma - INDICATOR_BB_STD * std
            bb_width = df["bb_upper"] - df["bb_lower"]
            bb_width = bb_width.replace(0, np.nan)
            df["bb_position"] = (close - df["bb_lower"]) / bb_width

        return df

    # =========================================================================
    # Indicator Calculation Helpers
    # =========================================================================

    @staticmethod
    def _calc_rsi(close: pd.Series, period: int = 14) -> Optional[float]:
        """Calculate RSI — return latest value only."""
        if len(close) < period + 1:
            return None
        delta = close.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta).where(delta < 0, 0.0)
        avg_gain = gain.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
        last_loss = avg_loss.iloc[-1]
        if last_loss == 0:
            return 100.0
        rs = avg_gain.iloc[-1] / last_loss
        return round(100.0 - (100.0 / (1.0 + rs)), 2)

    @staticmethod
    def _calc_rsi_series(close: pd.Series, period: int = 14) -> Optional[pd.Series]:
        """Calculate RSI — return full series."""
        if len(close) < period + 1:
            return None
        delta = close.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta).where(delta < 0, 0.0)
        avg_gain = gain.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
        rs = avg_gain / avg_loss.replace(0, np.nan)
        return 100.0 - (100.0 / (1.0 + rs))

    @staticmethod
    def _calc_atr(
        high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14
    ) -> Optional[float]:
        """Calculate ATR — return latest value only."""
        if len(close) < period + 1:
            return None
        prev_close = close.shift(1)
        tr = pd.concat([
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ], axis=1).max(axis=1)
        atr = tr.ewm(span=period, min_periods=period, adjust=False).mean()
        return round(float(atr.iloc[-1]), 6)

    @staticmethod
    def _calc_atr_series(
        high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14
    ) -> Optional[pd.Series]:
        """Calculate ATR — return full series."""
        if len(close) < period + 1:
            return None
        prev_close = close.shift(1)
        tr = pd.concat([
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ], axis=1).max(axis=1)
        return tr.ewm(span=period, min_periods=period, adjust=False).mean()

    @staticmethod
    def _calc_adx(
        high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14
    ) -> Optional[float]:
        """Calculate ADX — return latest value only."""
        if len(close) < period * 2:
            return None

        prev_high = high.shift(1)
        prev_low = low.shift(1)
        prev_close = close.shift(1)

        tr = pd.concat([
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ], axis=1).max(axis=1)

        plus_dm = high - prev_high
        minus_dm = prev_low - low
        plus_dm = plus_dm.where((plus_dm > minus_dm) & (plus_dm > 0), 0.0)
        minus_dm = minus_dm.where((minus_dm > plus_dm) & (minus_dm > 0), 0.0)

        atr = tr.ewm(span=period, min_periods=period, adjust=False).mean()
        plus_di = 100 * (
            plus_dm.ewm(span=period, min_periods=period, adjust=False).mean() / atr
        )
        minus_di = 100 * (
            minus_dm.ewm(span=period, min_periods=period, adjust=False).mean() / atr
        )

        dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan)
        adx = dx.ewm(span=period, min_periods=period, adjust=False).mean()

        val = adx.iloc[-1]
        return round(float(val), 2) if pd.notna(val) else None

    @staticmethod
    def _calc_bollinger(
        close: pd.Series, period: int = 20, std_mult: float = 2.0
    ) -> Optional[Dict[str, float]]:
        """Calculate Bollinger Bands — return latest values."""
        if len(close) < period:
            return None
        sma = close.rolling(window=period).mean()
        std = close.rolling(window=period).std()
        upper = sma + std_mult * std
        lower = sma - std_mult * std

        if pd.isna(sma.iloc[-1]):
            return None

        return {
            "bb_upper": round(float(upper.iloc[-1]), 6),
            "bb_middle": round(float(sma.iloc[-1]), 6),
            "bb_lower": round(float(lower.iloc[-1]), 6),
        }
