#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - InfluxDB Client
02_Brain/core/data/influxdb_client.py

Handles all InfluxDB 2.x read/write operations for:
- Tick data (raw bid/ask/volume)
- OHLC data (M1-D1 candles)
- Indicator data (RSI, ATR, ADX, BB, etc.)

Uses batched writes for HFT performance.
Flux queries return pandas DataFrames for ML pipeline.

Author: Dr. Suksaeng Kukanok
Version: 1.0.2 (Fixed imports for 02_Brain/core/data/ location)
Date: 2025-12-06
"""

import sys
import os
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any, List

import pandas as pd
from influxdb_client import InfluxDBClient as _InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS, WriteOptions

# ===========================================================================
# PATH FIX: Add 02_Brain/ to sys.path so 'import config' works
# This file is at: 02_Brain/core/data/influxdb_client.py
# config.py is at:  02_Brain/config.py
# So we go up 2 levels: core/data/ → core/ → 02_Brain/
# ===========================================================================
_brain_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
if _brain_dir not in sys.path:
    sys.path.insert(0, _brain_dir)

from config import (
    INFLUXDB_URL, INFLUXDB_TOKEN, INFLUXDB_ORG, INFLUXDB_BUCKET,
    INFLUXDB_BATCH_SIZE, INFLUXDB_FLUSH_INTERVAL_MS, INFLUXDB_WRITE_TIMEOUT_MS,
    MEASUREMENT_TICKS, MEASUREMENT_OHLC, MEASUREMENT_INDICATORS,
    TICK_RAW_RETENTION_DAYS,
)

logger = logging.getLogger("FlashEA.InfluxDB")


class InfluxDBClient:
    """
    InfluxDB 2.x client for FlashEASuite time-series storage.
    
    Measurements:
        - ticks:      tag=symbol  fields=bid,ask,volume,spread
        - ohlc:       tag=symbol,timeframe  fields=open,high,low,close,volume
        - indicators: tag=symbol,timeframe  fields=rsi,atr,adx,bb_upper,bb_middle,bb_lower,...
    
    Usage:
        client = InfluxDBClient()
        client.connect()
        client.write_tick("XAUUSD", 2650.50, 2650.80, 150, timestamp_ms)
        df = client.query_latest("XAUUSD", "ticks", 100)
        client.close()
    """

    def __init__(
        self,
        url: str = INFLUXDB_URL,
        token: str = INFLUXDB_TOKEN,
        org: str = INFLUXDB_ORG,
        bucket: str = INFLUXDB_BUCKET,
        batch_size: int = INFLUXDB_BATCH_SIZE,
        flush_interval_ms: int = INFLUXDB_FLUSH_INTERVAL_MS,
    ):
        self._url = url
        self._token = token
        self._org = org
        self._bucket = bucket
        self._batch_size = batch_size
        self._flush_interval_ms = flush_interval_ms

        self._client: Optional[_InfluxDBClient] = None
        self._write_api = None
        self._query_api = None
        self._connected = False

        # Stats
        self._ticks_written = 0
        self._ohlc_written = 0
        self._indicators_written = 0
        self._write_errors = 0

    # =========================================================================
    # Connection Management
    # =========================================================================

    def connect(self, synchronous: bool = False) -> bool:
        """
        Connect to InfluxDB.
        
        Args:
            synchronous: If True, use synchronous writes (for testing).
                         If False, use batched writes (for production).
        Returns:
            True if connected successfully.
        """
        try:
            self._client = _InfluxDBClient(
                url=self._url,
                token=self._token,
                org=self._org,
                timeout=INFLUXDB_WRITE_TIMEOUT_MS,
            )

            if synchronous:
                self._write_api = self._client.write_api(write_options=SYNCHRONOUS)
            else:
                write_options = WriteOptions(
                    batch_size=self._batch_size,
                    flush_interval=self._flush_interval_ms,
                    jitter_interval=0,
                    retry_interval=5000,
                    max_retries=3,
                    max_retry_delay=30000,
                    exponential_base=2,
                )
                self._write_api = self._client.write_api(write_options=write_options)

            self._query_api = self._client.query_api()
            self._connected = True
            logger.info(f"Connected to InfluxDB: {self._url} org={self._org} bucket={self._bucket}")
            return True

        except Exception as e:
            logger.error(f"Failed to connect to InfluxDB: {e}")
            self._connected = False
            return False

    def close(self):
        """Close connection and flush remaining writes."""
        if self._write_api:
            try:
                self._write_api.close()
            except Exception as e:
                logger.warning(f"Error closing write API: {e}")

        if self._client:
            try:
                self._client.close()
            except Exception as e:
                logger.warning(f"Error closing client: {e}")

        self._connected = False
        logger.info(
            f"InfluxDB closed. Stats: ticks={self._ticks_written}, "
            f"ohlc={self._ohlc_written}, indicators={self._indicators_written}, "
            f"errors={self._write_errors}"
        )

    def health_check(self) -> bool:
        """
        Check InfluxDB server health.
        
        Returns:
            True if server is healthy and reachable.
        """
        if not self._client:
            return False
        try:
            health = self._client.health()
            is_healthy = health.status == "pass"
            if not is_healthy:
                logger.warning(f"InfluxDB health check: {health.status} - {health.message}")
            return is_healthy
        except Exception as e:
            logger.error(f"InfluxDB health check failed: {e}")
            return False

    @property
    def is_connected(self) -> bool:
        return self._connected

    @property
    def stats(self) -> Dict[str, int]:
        return {
            "ticks_written": self._ticks_written,
            "ohlc_written": self._ohlc_written,
            "indicators_written": self._indicators_written,
            "write_errors": self._write_errors,
        }

    # =========================================================================
    # Write Operations
    # =========================================================================

    def write_tick(
        self,
        symbol: str,
        bid: float,
        ask: float,
        volume: float,
        timestamp_ms: int,
    ) -> bool:
        """
        Write a single tick data point.
        
        Args:
            symbol:       e.g. "XAUUSD"
            bid:          Bid price
            ask:          Ask price
            volume:       Tick volume (flags from MT5)
            timestamp_ms: Unix timestamp in milliseconds
            
        Returns:
            True if write was accepted (batched, not necessarily flushed).
        """
        if not self._connected:
            return False
        try:
            point = (
                Point(MEASUREMENT_TICKS)
                .tag("symbol", symbol)
                .field("bid", float(bid))
                .field("ask", float(ask))
                .field("spread", float(ask - bid))
                .field("volume", float(volume))
                .time(timestamp_ms, WritePrecision.MS)
            )
            self._write_api.write(bucket=self._bucket, org=self._org, record=point)
            self._ticks_written += 1
            return True

        except Exception as e:
            self._write_errors += 1
            if self._write_errors % 100 == 1:
                logger.error(f"write_tick error ({self._write_errors} total): {e}")
            return False

    def write_ticks_batch(self, ticks: List[Dict[str, Any]]) -> int:
        """
        Write multiple ticks at once.
        
        Args:
            ticks: List of dicts with keys: symbol, bid, ask, volume, timestamp_ms
            
        Returns:
            Number of points successfully queued.
        """
        if not self._connected:
            return 0

        points = []
        for t in ticks:
            try:
                bid = float(t["bid"])
                ask = float(t["ask"])
                point = (
                    Point(MEASUREMENT_TICKS)
                    .tag("symbol", t["symbol"])
                    .field("bid", bid)
                    .field("ask", ask)
                    .field("spread", ask - bid)
                    .field("volume", float(t.get("volume", 0)))
                    .time(int(t["timestamp_ms"]), WritePrecision.MS)
                )
                points.append(point)
            except (KeyError, ValueError, TypeError) as e:
                self._write_errors += 1
                logger.debug(f"Skipping invalid tick: {e}")

        if points:
            try:
                self._write_api.write(bucket=self._bucket, org=self._org, record=points)
                self._ticks_written += len(points)
            except Exception as e:
                self._write_errors += len(points)
                logger.error(f"write_ticks_batch error: {e}")
                return 0

        return len(points)

    def write_ohlc(
        self,
        symbol: str,
        tf: str,
        o: float,
        h: float,
        l: float,
        c: float,
        vol: float,
        timestamp_ms: int,
    ) -> bool:
        """
        Write a single OHLC bar.
        
        Args:
            symbol:       e.g. "XAUUSD"
            tf:           Timeframe e.g. "M1", "M5", "M15", "H1", "H4", "D1"
            o, h, l, c:   Open, High, Low, Close prices
            vol:          Bar volume
            timestamp_ms: Bar open time in milliseconds
            
        Returns:
            True if write was accepted.
        """
        if not self._connected:
            return False
        try:
            point = (
                Point(MEASUREMENT_OHLC)
                .tag("symbol", symbol)
                .tag("timeframe", tf)
                .field("open", float(o))
                .field("high", float(h))
                .field("low", float(l))
                .field("close", float(c))
                .field("volume", float(vol))
                .time(timestamp_ms, WritePrecision.MS)
            )
            self._write_api.write(bucket=self._bucket, org=self._org, record=point)
            self._ohlc_written += 1
            return True

        except Exception as e:
            self._write_errors += 1
            logger.error(f"write_ohlc error: {e}")
            return False

    def write_indicators(
        self,
        symbol: str,
        tf: str,
        indicators_dict: Dict[str, float],
        timestamp_ms: int,
    ) -> bool:
        """
        Write indicator values for a symbol/timeframe.
        
        Args:
            symbol:          e.g. "XAUUSD"
            tf:              Timeframe e.g. "M15"
            indicators_dict: e.g. {"rsi": 45.2, "atr": 0.0015, "adx": 22.5}
            timestamp_ms:    Timestamp in milliseconds
            
        Returns:
            True if write was accepted.
        """
        if not self._connected or not indicators_dict:
            return False
        try:
            point = (
                Point(MEASUREMENT_INDICATORS)
                .tag("symbol", symbol)
                .tag("timeframe", tf)
            )
            for key, value in indicators_dict.items():
                if value is not None:
                    point = point.field(str(key), float(value))

            point = point.time(timestamp_ms, WritePrecision.MS)
            self._write_api.write(bucket=self._bucket, org=self._org, record=point)
            self._indicators_written += 1
            return True

        except Exception as e:
            self._write_errors += 1
            logger.error(f"write_indicators error: {e}")
            return False

    # =========================================================================
    # Query Operations
    # =========================================================================

    def query_range(
        self,
        symbol: str,
        start: str,
        end: str,
        measurement: str = MEASUREMENT_TICKS,
        timeframe: Optional[str] = None,
    ) -> pd.DataFrame:
        """
        Query data within a time range.
        
        Args:
            symbol:      e.g. "XAUUSD"
            start:       ISO format or relative e.g. "-7d", "2025-12-01T00:00:00Z"
            end:         ISO format or "now()"
            measurement: "ticks", "ohlc", or "indicators"
            timeframe:   Required for ohlc/indicators e.g. "M15"
            
        Returns:
            DataFrame with time index and measurement fields.
        """
        if not self._connected:
            return pd.DataFrame()

        tf_filter = ""
        if timeframe and measurement in (MEASUREMENT_OHLC, MEASUREMENT_INDICATORS):
            tf_filter = f'  |> filter(fn: (r) => r["timeframe"] == "{timeframe}")\n'

        flux = f'''
from(bucket: "{self._bucket}")
  |> range(start: {start}, stop: {end})
  |> filter(fn: (r) => r["_measurement"] == "{measurement}")
  |> filter(fn: (r) => r["symbol"] == "{symbol}")
{tf_filter}  |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> sort(columns: ["_time"])
'''
        try:
            df = self._query_api.query_data_frame(flux, org=self._org)
            if isinstance(df, list):
                df = pd.concat(df, ignore_index=True) if df else pd.DataFrame()
            if not df.empty:
                df = self._clean_dataframe(df)
            return df

        except Exception as e:
            logger.error(f"query_range error: {e}")
            return pd.DataFrame()

    def query_latest(
        self,
        symbol: str,
        measurement: str = MEASUREMENT_TICKS,
        n_points: int = 100,
        timeframe: Optional[str] = None,
    ) -> pd.DataFrame:
        """
        Query the N most recent data points.
        
        Args:
            symbol:      e.g. "XAUUSD"
            measurement: "ticks", "ohlc", or "indicators"
            n_points:    Number of points to return
            timeframe:   Required for ohlc/indicators
            
        Returns:
            DataFrame sorted by time ascending (oldest first).
        """
        if not self._connected:
            return pd.DataFrame()

        tf_filter = ""
        if timeframe and measurement in (MEASUREMENT_OHLC, MEASUREMENT_INDICATORS):
            tf_filter = f'  |> filter(fn: (r) => r["timeframe"] == "{timeframe}")\n'

        flux = f'''
from(bucket: "{self._bucket}")
  |> range(start: -180d)
  |> filter(fn: (r) => r["_measurement"] == "{measurement}")
  |> filter(fn: (r) => r["symbol"] == "{symbol}")
{tf_filter}  |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: {n_points})
  |> sort(columns: ["_time"])
'''
        try:
            df = self._query_api.query_data_frame(flux, org=self._org)
            if isinstance(df, list):
                df = pd.concat(df, ignore_index=True) if df else pd.DataFrame()
            if not df.empty:
                df = self._clean_dataframe(df)
            return df

        except Exception as e:
            logger.error(f"query_latest error: {e}")
            return pd.DataFrame()

    def query_tick_count(self, symbol: str, start: str = "-1d") -> int:
        """Get tick count for a symbol in a time range (for monitoring)."""
        if not self._connected:
            return 0

        flux = f'''
from(bucket: "{self._bucket}")
  |> range(start: {start})
  |> filter(fn: (r) => r["_measurement"] == "{MEASUREMENT_TICKS}")
  |> filter(fn: (r) => r["symbol"] == "{symbol}")
  |> filter(fn: (r) => r["_field"] == "bid")
  |> count()
'''
        try:
            tables = self._query_api.query(flux, org=self._org)
            for table in tables:
                for record in table.records:
                    return int(record.get_value())
            return 0
        except Exception:
            return 0

    # =========================================================================
    # Downsampling (Tick → OHLC M1)
    # =========================================================================

    def downsample_ticks_to_ohlc(
        self,
        symbol: str,
        source_start: str = "-8d",
        source_end: str = "-7d",
    ) -> int:
        """
        Downsample raw ticks into OHLC M1 bars.
        Call periodically to compress old tick data.
        
        Args:
            symbol:       Symbol to downsample
            source_start: Start of tick range (e.g. "-8d")
            source_end:   End of tick range (e.g. "-7d")
            
        Returns:
            Number of OHLC bars created.
        """
        if not self._connected:
            return 0

        try:
            df = self.query_range(symbol, source_start, source_end, MEASUREMENT_TICKS)
            if df.empty or "bid" not in df.columns:
                return 0

            df.index = pd.to_datetime(df.index)
            ohlc = df["bid"].resample("1min").agg(
                open="first", high="max", low="min", close="last"
            ).dropna()

            vol = pd.DataFrame()
            if "volume" in df.columns:
                vol = df["volume"].resample("1min").sum()

            bars_written = 0
            for ts, row in ohlc.iterrows():
                v = float(vol.loc[ts]) if not vol.empty and ts in vol.index else 0.0
                ts_ms = int(ts.timestamp() * 1000)
                if self.write_ohlc(symbol, "M1", row["open"], row["high"],
                                   row["low"], row["close"], v, ts_ms):
                    bars_written += 1

            logger.info(
                f"Downsampled {symbol}: {len(df)} ticks → {bars_written} M1 bars "
                f"({source_start} to {source_end})"
            )
            return bars_written

        except Exception as e:
            logger.error(f"downsample_ticks_to_ohlc error: {e}")
            return 0

    def delete_old_ticks(
        self,
        symbol: str,
        older_than_days: int = TICK_RAW_RETENTION_DAYS,
    ) -> bool:
        """
        Delete raw ticks older than N days (after downsampling).
        
        Args:
            symbol:          Symbol to clean
            older_than_days: Delete ticks older than this many days
            
        Returns:
            True if deletion succeeded.
        """
        if not self._client:
            return False
        try:
            delete_api = self._client.delete_api()
            start = "1970-01-01T00:00:00Z"
            stop_dt = datetime.now(timezone.utc).replace(
                hour=0, minute=0, second=0, microsecond=0
            )
            stop_dt = stop_dt - timedelta(days=older_than_days)
            stop = stop_dt.isoformat().replace("+00:00", "Z")

            predicate = (
                f'_measurement="{MEASUREMENT_TICKS}" AND symbol="{symbol}"'
            )
            delete_api.delete(
                start=start,
                stop=stop,
                predicate=predicate,
                bucket=self._bucket,
                org=self._org,
            )
            logger.info(f"Deleted {symbol} ticks older than {older_than_days} days")
            return True

        except Exception as e:
            logger.error(f"delete_old_ticks error: {e}")
            return False

    # =========================================================================
    # Internal Helpers
    # =========================================================================

    @staticmethod
    def _clean_dataframe(df: pd.DataFrame) -> pd.DataFrame:
        """Remove InfluxDB metadata columns, set time index."""
        drop_cols = [
            c for c in df.columns
            if c.startswith("_") and c not in ("_time",)
        ]
        for extra in ("result", "table"):
            if extra in df.columns:
                drop_cols.append(extra)
        df = df.drop(columns=drop_cols, errors="ignore")

        if "_time" in df.columns:
            df = df.set_index("_time")
            df.index.name = "time"
            df.index = pd.to_datetime(df.index)

        for tag in ("symbol", "timeframe"):
            if tag in df.columns:
                df = df.drop(columns=[tag], errors="ignore")

        return df
