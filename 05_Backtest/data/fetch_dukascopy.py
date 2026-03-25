#!/usr/bin/env python
"""
Fetch historical forex data from Dukascopy (free, 20+ years).
Downloads M1 tick data, resamples to M1/M5/M15, caches as Parquet.
"""
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

CACHE_DIR = Path(__file__).parent / "cache"
CACHE_DIR.mkdir(exist_ok=True)

# Dukascopy symbol names (no suffix)
DUKA_SYMBOLS = {
    "EURUSD": "EURUSD", "GBPUSD": "GBPUSD", "USDJPY": "USDJPY",
    "USDCHF": "USDCHF", "USDCAD": "USDCAD", "AUDUSD": "AUDUSD",
    "NZDUSD": "NZDUSD", "EURGBP": "EURGBP", "EURJPY": "EURJPY",
    "EURCHF": "EURCHF", "EURAUD": "EURAUD", "EURCAD": "EURCAD",
    "EURNZD": "EURNZD", "GBPJPY": "GBPJPY", "GBPCHF": "GBPCHF",
    "GBPAUD": "GBPAUD", "GBPCAD": "GBPCAD", "GBPNZD": "GBPNZD",
    "AUDJPY": "AUDJPY", "AUDNZD": "AUDNZD", "AUDCAD": "AUDCAD",
    "AUDCHF": "AUDCHF", "NZDJPY": "NZDJPY", "NZDCAD": "NZDCAD",
    "NZDCHF": "NZDCHF", "CADJPY": "CADJPY", "CADCHF": "CADCHF",
    "CHFJPY": "CHFJPY", "XAUUSD": "XAUUSD",
}


def _download_duka_m1(symbol: str, start: datetime, end: datetime) -> pd.DataFrame:
    """Download M1 data from Dukascopy using duka library."""
    try:
        from duka.app import app
        from duka.core.utils import TimeFrame
    except ImportError:
        raise ImportError("duka not installed. Run: pip install duka")

    # duka writes to current directory, so we use a temp dir
    import tempfile
    tmpdir = tempfile.mkdtemp()
    old_cwd = os.getcwd()

    try:
        os.chdir(tmpdir)
        app(symbol, start, end, 1, TimeFrame.M1, tmpdir)  # 1 thread

        # Find the output CSV
        csvs = list(Path(tmpdir).glob("*.csv"))
        if not csvs:
            return pd.DataFrame()

        df = pd.read_csv(csvs[0])
        # duka CSV columns: time, open, close, high, low, volume
        if "time" in df.columns:
            df["time"] = pd.to_datetime(df["time"])
        elif "Gmt time" in df.columns:
            df["time"] = pd.to_datetime(df["Gmt time"], format="%d.%m.%Y %H:%M:%S.%f")

        # Normalize columns
        col_map = {}
        for c in df.columns:
            cl = c.lower().strip()
            if "open" in cl: col_map[c] = "open"
            elif "high" in cl: col_map[c] = "high"
            elif "low" in cl: col_map[c] = "low"
            elif "close" in cl: col_map[c] = "close"
            elif "vol" in cl: col_map[c] = "tick_volume"
        df = df.rename(columns=col_map)

        if "time" not in df.columns:
            df["time"] = pd.to_datetime(df.iloc[:, 0])

        needed = ["time", "open", "high", "low", "close", "tick_volume"]
        for c in needed:
            if c not in df.columns:
                df[c] = 0
        df["spread"] = 0
        df = df[["time", "open", "high", "low", "close", "tick_volume", "spread"]]
        return df.reset_index(drop=True)

    finally:
        os.chdir(old_cwd)
        import shutil
        shutil.rmtree(tmpdir, ignore_errors=True)


def _download_direct(symbol: str, year: int, month: int) -> pd.DataFrame:
    """Download one month of M1 data directly from Dukascopy servers."""
    import struct
    import lzma
    from urllib.request import urlopen, Request
    from urllib.error import URLError

    # Dukascopy URL: /SYMBOL/YEAR/MONTH(0-indexed)/DAY/BID_candles_min_1.bi5
    # This function downloads day 1 only. Use _download_month for full month.
    url = (f"https://datafeed.dukascopy.com/datafeed/{symbol}/"
           f"{year}/{month-1:02d}/01/BID_candles_min_1.bi5")

    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        resp = urlopen(req, timeout=30)
        data = resp.read()
    except (URLError, Exception):
        return pd.DataFrame()

    if len(data) == 0:
        return pd.DataFrame()

    # Decompress LZMA
    try:
        decompressed = lzma.decompress(data)
    except Exception:
        return pd.DataFrame()

    # Parse binary: each row = 20 bytes (uint32 time_offset, uint32 open, uint32 high,
    #                                      uint32 low, uint32 close, float32 volume)
    row_size = 20
    n_rows = len(decompressed) // row_size
    if n_rows == 0:
        return pd.DataFrame()

    rows = []
    base_time = datetime(year, month, 1)

    for i in range(n_rows):
        offset = i * row_size
        chunk = decompressed[offset:offset + row_size]
        if len(chunk) < row_size:
            break
        time_ms, o, h, l, c = struct.unpack(">IIIII", chunk[:20])
        dt = base_time + timedelta(milliseconds=time_ms)
        rows.append([dt, o, h, l, c, 0])

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows, columns=["time", "open", "high", "low", "close", "tick_volume"])

    # Convert pipettes to price
    # Dukascopy stores all prices as integers:
    #   Standard forex (EURUSD etc): pipettes = 1/100000
    #   JPY pairs (USDJPY etc): 1/1000
    #   Gold (XAUUSD): 1/1000
    sample = df["open"].median()
    if symbol in ("XAUUSD",):
        scale = 1000.0
    elif "JPY" in symbol:
        scale = 1000.0
    else:
        scale = 100000.0

    for col in ["open", "high", "low", "close"]:
        df[col] = df[col] / scale

    df["spread"] = 0
    df["tick_volume"] = df["tick_volume"].astype(int)

    return df


def _download_day(symbol: str, year: int, month: int, day: int) -> pd.DataFrame:
    """Download one day of M1 data from Dukascopy."""
    import struct, lzma
    from urllib.request import urlopen, Request
    from urllib.error import URLError

    url = (f"https://datafeed.dukascopy.com/datafeed/{symbol}/"
           f"{year}/{month-1:02d}/{day:02d}/BID_candles_min_1.bi5")

    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        resp = urlopen(req, timeout=15)
        data = resp.read()
    except Exception:
        return pd.DataFrame()

    if len(data) == 0:
        return pd.DataFrame()

    try:
        decompressed = lzma.decompress(data)
    except Exception:
        return pd.DataFrame()

    row_size = 20
    n_rows = len(decompressed) // row_size
    if n_rows == 0:
        return pd.DataFrame()

    rows = []
    base_time = datetime(year, month, day)

    for i in range(n_rows):
        offset = i * row_size
        chunk = decompressed[offset:offset + row_size]
        if len(chunk) < row_size:
            break
        time_ms, o, h, l, c = struct.unpack(">IIIII", chunk[:20])
        dt = base_time + timedelta(milliseconds=time_ms)
        rows.append([dt, o, h, l, c, 0])

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows, columns=["time", "open", "high", "low", "close", "tick_volume"])

    if symbol in ("XAUUSD",):
        scale = 1000.0
    elif "JPY" in symbol:
        scale = 1000.0
    else:
        scale = 100000.0

    for col in ["open", "high", "low", "close"]:
        df[col] = df[col] / scale

    df["spread"] = 0
    df["tick_volume"] = df["tick_volume"].astype(int)
    return df


def fetch_dukascopy_m1(symbol: str, start_year: int = 2016, end_year: int = 2026) -> pd.DataFrame:
    """
    Fetch M1 data from Dukascopy day by day.
    Returns DataFrame with columns: time, open, high, low, close, tick_volume, spread
    """
    import calendar

    all_dfs = []

    for year in range(start_year, end_year + 1):
        year_bars = 0
        for month in range(1, 13):
            if year == end_year and month > 3:
                break
            days_in_month = calendar.monthrange(year, month)[1]
            for day in range(1, days_in_month + 1):
                try:
                    df = _download_day(symbol, year, month, day)
                    if len(df) > 0:
                        all_dfs.append(df)
                        year_bars += len(df)
                except Exception:
                    pass
        if year_bars > 0:
            print(f"    {symbol} {year}: {year_bars:,} bars")

    if not all_dfs:
        return pd.DataFrame()

    result = pd.concat(all_dfs, ignore_index=True)
    result = result.sort_values("time").reset_index(drop=True)
    result = result.drop_duplicates(subset=["time"]).reset_index(drop=True)
    return result


def resample_ohlcv(df_m1: pd.DataFrame, tf: str) -> pd.DataFrame:
    """Resample M1 to M5, M15, M30, H1, H4, D1."""
    tf_map = {"M5": "5min", "M15": "15min", "M30": "30min",
              "H1": "1h", "H4": "4h", "D1": "1D"}
    freq = tf_map.get(tf)
    if freq is None:
        raise ValueError(f"Unknown TF: {tf}")

    df = df_m1.set_index("time")
    resampled = df.resample(freq).agg({
        "open": "first", "high": "max", "low": "min", "close": "last",
        "tick_volume": "sum", "spread": "mean",
    }).dropna()
    return resampled.reset_index()


def fetch_and_cache_all(
    symbols: list[str] | None = None,
    start_year: int = 2016,
    end_year: int = 2026,
    timeframes: list[str] | None = None,
    suffix: str = ".tp",
):
    """Fetch M1 from Dukascopy, resample, and cache as Parquet."""
    if symbols is None:
        symbols = list(DUKA_SYMBOLS.keys())
    if timeframes is None:
        timeframes = ["M1", "M5", "M15", "M30", "H1", "H4", "D1"]

    total = len(symbols)
    for i, sym in enumerate(symbols):
        print(f"\n[{i+1}/{total}] {sym}")
        duka_sym = DUKA_SYMBOLS.get(sym, sym)

        # Check if M1 already cached
        m1_cache = CACHE_DIR / f"{sym}{suffix}_M1_{start_year}0101_{end_year}0101.parquet"
        if m1_cache.exists():
            print(f"  M1 cached, loading...")
            df_m1 = pd.read_parquet(m1_cache)
        else:
            print(f"  Downloading M1 from Dukascopy ({start_year}-{end_year})...")
            df_m1 = fetch_dukascopy_m1(duka_sym, start_year, end_year)
            if len(df_m1) == 0:
                print(f"  FAILED: no data")
                continue
            df_m1.to_parquet(m1_cache, index=False)
            print(f"  M1: {len(df_m1):,} bars cached")

        # Resample to all TFs
        for tf in timeframes:
            cache_name = f"{sym}{suffix}_{tf}_{start_year}0101_{end_year}0101.parquet"
            cache_path = CACHE_DIR / cache_name
            if cache_path.exists():
                continue
            if tf == "M1":
                continue  # already saved

            try:
                df_tf = resample_ohlcv(df_m1, tf)
                df_tf.to_parquet(cache_path, index=False)
                print(f"  {tf}: {len(df_tf):,} bars")
            except Exception as e:
                print(f"  {tf}: FAIL ({e})")

    print("\nDone!")


if __name__ == "__main__":
    fetch_and_cache_all()
