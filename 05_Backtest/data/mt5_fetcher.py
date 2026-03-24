"""
Data Fetcher — Pull OHLCV data via yfinance (default) or MT5 API.
Caches to Parquet files in data/cache/
"""
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd

CACHE_DIR = Path(__file__).parent / "cache"
CACHE_DIR.mkdir(exist_ok=True)

# Symbol mapping: broker symbol → yfinance ticker
YF_SYMBOL_MAP = {
    "USDJPY":    "USDJPY=X",
    "USDJPY.tp": "USDJPY=X",
    "XAUUSD":    "GC=F",
    "XAUUSD.tp": "GC=F",
    "GBPUSD":    "GBPUSD=X",
    "GBPUSD.tp": "GBPUSD=X",
    "EURUSD":    "EURUSD=X",
    "EURUSD.tp": "EURUSD=X",
    "EURJPY":    "EURJPY=X",
    "EURJPY.tp": "EURJPY=X",
    "AUDUSD":    "AUDUSD=X",
    "AUDUSD.tp": "AUDUSD=X",
    "GBPJPY":    "GBPJPY=X",
    "GBPJPY.tp": "GBPJPY=X",
}

# yfinance interval mapping
YF_TF_MAP = {
    "M1":  "1m",
    "M5":  "5m",
    "M15": "15m",
    "M30": "30m",
    "H1":  "1h",
    "H4":  "4h",     # yfinance doesn't natively have H4; we resample from H1
    "D1":  "1d",
    "W1":  "1wk",
}

# MT5 timeframe mapping (for MT5 API fallback)
MT5_TF_MAP = {
    "M1": 1, "M5": 5, "M15": 15, "M30": 30,
    "H1": 16385, "H4": 16388, "D1": 16408, "W1": 32769,
}


def _cache_path(symbol: str, tf: str, start: datetime, end: datetime) -> Path:
    s = start.strftime("%Y%m%d")
    e = end.strftime("%Y%m%d")
    safe_sym = symbol.replace(".", "_").replace("=", "_")
    return CACHE_DIR / f"{safe_sym}_{tf}_{s}_{e}.parquet"


def _resample_to_h4(df: pd.DataFrame) -> pd.DataFrame:
    """Resample H1 data to H4."""
    df = df.set_index("time")
    resampled = df.resample("4h").agg({
        "open": "first",
        "high": "max",
        "low": "min",
        "close": "last",
        "tick_volume": "sum",
        "spread": "mean",
    }).dropna()
    resampled = resampled.reset_index()
    return resampled


def fetch_yfinance(
    symbol: str,
    tf: str = "H1",
    start: datetime | None = None,
    end: datetime | None = None,
) -> pd.DataFrame:
    """
    Fetch OHLCV from yfinance.

    Note: yfinance H1 data limited to ~2 years. D1 available for 20+ years.
    For H4: fetches H1 then resamples.
    """
    import yfinance as yf

    yf_ticker = YF_SYMBOL_MAP.get(symbol, symbol)
    need_resample = False

    if tf == "H4":
        yf_interval = "1h"
        need_resample = True
    else:
        yf_interval = YF_TF_MAP.get(tf, "1h")

    # yfinance max period for intraday
    if yf_interval in ("1m", "5m", "15m", "30m"):
        max_days = 60
    elif yf_interval in ("1h",):
        max_days = 730  # ~2 years
    else:
        max_days = 365 * 20

    if start is not None and end is not None:
        requested_days = (end - start).days
        if requested_days > max_days:
            print(f"[yfinance] WARNING: {tf} data limited to {max_days} days, requested {requested_days}")
            start = end - timedelta(days=max_days)

    ticker = yf.Ticker(yf_ticker)
    hist = ticker.history(
        start=start.strftime("%Y-%m-%d") if start else None,
        end=end.strftime("%Y-%m-%d") if end else None,
        interval=yf_interval,
    )

    if hist.empty:
        raise RuntimeError(f"No data from yfinance for {yf_ticker} ({symbol}) {tf}")

    df = pd.DataFrame({
        "time": hist.index,
        "open": hist["Open"].values,
        "high": hist["High"].values,
        "low": hist["Low"].values,
        "close": hist["Close"].values,
        "tick_volume": hist["Volume"].values if "Volume" in hist else 0,
        "spread": 0,
    })
    df["time"] = pd.to_datetime(df["time"]).dt.tz_localize(None)
    df = df.reset_index(drop=True)

    if need_resample:
        df = _resample_to_h4(df)

    return df


def fetch_mt5(
    symbol: str,
    tf: str = "H1",
    start: datetime | None = None,
    end: datetime | None = None,
) -> pd.DataFrame:
    """Fetch from MT5 Python API (requires MT5 terminal running)."""
    import MetaTrader5 as mt5

    if not mt5.initialize():
        raise RuntimeError(f"MT5 initialize failed: {mt5.last_error()}")

    mt5_tf = MT5_TF_MAP.get(tf)
    if mt5_tf is None:
        mt5.shutdown()
        raise ValueError(f"Unknown timeframe: {tf}")

    rates = mt5.copy_rates_range(symbol, mt5_tf, start, end)
    mt5.shutdown()

    if rates is None or len(rates) == 0:
        raise RuntimeError(f"No data from MT5 for {symbol} {tf}")

    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")
    df = df[["time", "open", "high", "low", "close", "tick_volume", "spread"]]
    return df.reset_index(drop=True)


def fetch_ohlcv(
    symbol: str,
    tf: str = "H1",
    start: datetime | None = None,
    end: datetime | None = None,
    use_cache: bool = True,
    source: str = "auto",
) -> pd.DataFrame:
    """
    Fetch OHLCV data. Tries cache → yfinance → MT5.

    Args:
        symbol: e.g. "USDJPY.tp", "XAUUSD.tp", "USDJPY"
        tf: "M1","M5","M15","M30","H1","H4","D1","W1"
        start: start date (default: 5 years ago)
        end: end date (default: now)
        use_cache: load from parquet cache if available
        source: "auto" (try yfinance first), "yfinance", "mt5"
    """
    if end is None:
        end = datetime.now()
    if start is None:
        start = end - timedelta(days=5 * 365)

    # Check cache
    cache_file = _cache_path(symbol, tf, start, end)
    if use_cache and cache_file.exists():
        df = pd.read_parquet(cache_file)
        print(f"[Cache] Loaded {len(df)} bars from {cache_file.name}")
        return df

    # Fetch
    df = None
    if source in ("auto", "yfinance"):
        try:
            df = fetch_yfinance(symbol, tf, start, end)
            print(f"[yfinance] Fetched {len(df)} bars for {symbol} {tf}")
        except Exception as e:
            print(f"[yfinance] Failed: {e}")
            if source == "yfinance":
                raise

    if df is None and source in ("auto", "mt5"):
        df = fetch_mt5(symbol, tf, start, end)
        print(f"[MT5] Fetched {len(df)} bars for {symbol} {tf}")

    if df is None:
        raise RuntimeError(f"Could not fetch data for {symbol} {tf}")

    # Cache
    df.to_parquet(cache_file, index=False)
    print(f"  → Cached to {cache_file.name}")

    return df


def load_csv(path: str) -> pd.DataFrame:
    """Load OHLCV from CSV."""
    df = pd.read_csv(path)
    if "time" in df.columns:
        df["time"] = pd.to_datetime(df["time"])
    elif "datetime" in df.columns:
        df["time"] = pd.to_datetime(df["datetime"])
        df = df.drop(columns=["datetime"])
    return df


def list_cached() -> list[str]:
    """List all cached parquet files."""
    return [f.name for f in CACHE_DIR.glob("*.parquet")]
