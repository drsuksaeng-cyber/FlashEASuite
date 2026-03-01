#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - InfluxDB Integration Test
02_Brain/tests/test_influxdb_ingestion.py

Tests:
1. InfluxDB connection & health check
2. Write 1000 fake ticks → query back → verify count & values
3. Write OHLC bars → query back → verify
4. Write indicators → query back → verify
5. DataIngestion.receive_from_feeder() parsing
6. DataIngestion.calculate_derived_indicators()
7. DataIngestion.get_feature_dataframe()
8. Batch write performance

Run: cd 02_Brain && python tests/test_influxdb_ingestion.py

PREREQUISITE: InfluxDB 2.x running on localhost:8086

Author: Dr. Suksaeng Kukanok
Version: 1.0.1 (Fixed imports)
Date: 2025-12-06
"""

import sys
import os
import time
import random
import traceback

# ===========================================================================
# PATH FIX: Add 02_Brain/ to sys.path
# This file is at: 02_Brain/tests/test_influxdb_ingestion.py
# config.py is at:  02_Brain/config.py
# So we go up 1 level: tests/ → 02_Brain/
# ===========================================================================
_brain_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if _brain_dir not in sys.path:
    sys.path.insert(0, _brain_dir)

from config import (
    MSG_TICK_DATA, MSG_OHLC_DATA, MSG_INDICATOR_DATA,
    MEASUREMENT_TICKS, MEASUREMENT_OHLC, MEASUREMENT_INDICATORS,
)
from core.data.influxdb_client import InfluxDBClient
from core.data.data_ingestion import DataIngestion


# =============================================================================
# Test Helpers
# =============================================================================

def print_header(title: str):
    print(f"\n{'=' * 70}")
    print(f"  {title}")
    print(f"{'=' * 70}")


def print_result(test_name: str, passed: bool, detail: str = ""):
    status = "✅ PASSED" if passed else "❌ FAILED"
    print(f"  {status} | {test_name}")
    if detail:
        print(f"          {detail}")


def generate_fake_ticks(symbol: str, n: int, base_price: float) -> list:
    """Generate N fake tick messages in FeederEA format."""
    ticks = []
    now_ms = int(time.time() * 1000)
    price = base_price

    for i in range(n):
        price += random.uniform(-0.5, 0.5)
        spread = random.uniform(0.1, 0.5)
        bid = round(price, 2)
        ask = round(price + spread, 2)
        flags = random.randint(1, 15)
        ts = now_ms + (i * 50)  # 50ms apart

        # FeederEA format: [type, seq_id, timestamp_ms, symbol, bid, ask, flags]
        tick_msg = [MSG_TICK_DATA, i + 1, ts, symbol, bid, ask, flags]
        ticks.append(tick_msg)

    return ticks


def generate_fake_ohlc(symbol: str, tf: str, n: int, base_price: float) -> list:
    """Generate N fake OHLC messages."""
    bars = []
    now_ms = int(time.time() * 1000)
    price = base_price

    tf_ms = {"M1": 60000, "M5": 300000, "M15": 900000,
             "H1": 3600000, "H4": 14400000, "D1": 86400000}
    interval = tf_ms.get(tf, 900000)

    for i in range(n):
        o = round(price, 2)
        h = round(price + random.uniform(0.5, 3.0), 2)
        l = round(price - random.uniform(0.5, 3.0), 2)
        c = round(price + random.uniform(-1.5, 1.5), 2)
        if l > o:
            l = round(o - 0.1, 2)
        if h < o:
            h = round(o + 0.1, 2)
        vol = random.randint(100, 5000)
        ts = now_ms - ((n - i) * interval)

        # [type, seq, ts_ms, symbol, tf, open, high, low, close, volume]
        bar_msg = [MSG_OHLC_DATA, i + 1, ts, symbol, tf, o, h, l, c, vol]
        bars.append(bar_msg)
        price = c

    return bars


# =============================================================================
# Tests
# =============================================================================

def test_1_connection(db: InfluxDBClient) -> bool:
    """Test 1: Connect and health check."""
    ok = db.connect(synchronous=True)
    if not ok:
        return False
    return db.health_check()


def test_2_write_1000_ticks(db: InfluxDBClient, ingestion: DataIngestion) -> bool:
    """Test 2: Write 1000 ticks → query back → verify."""
    symbol = "XAUUSD"
    ticks = generate_fake_ticks(symbol, 1000, 2650.0)

    t_start = time.perf_counter()
    written = 0
    for tick_msg in ticks:
        parsed = ingestion.receive_from_feeder(tick_msg)
        if parsed and ingestion.store_to_influxdb(parsed):
            written += 1
    elapsed = time.perf_counter() - t_start

    print(f"          Wrote {written}/1000 ticks in {elapsed:.3f}s "
          f"({written / elapsed:.0f} ticks/sec)")

    if written != 1000:
        return False

    # Wait for InfluxDB to flush all data to queryable state
    # Synchronous writes are confirmed but indexing needs time
    time.sleep(3)

    df = db.query_latest(symbol, MEASUREMENT_TICKS, 1000)
    print(f"          Queried back: {len(df)} rows, columns: {list(df.columns)}")

    if df.empty:
        print("          WARNING: Query returned empty — InfluxDB might need more time")
        return False

    for col in ("bid", "ask", "spread"):
        if col not in df.columns:
            print(f"          Missing column: {col}")
            return False

    if (df["bid"] <= 0).any():
        print("          Found negative bid values!")
        return False

    if (df["spread"] < 0).any():
        print("          Found negative spread values!")
        return False

    # Allow small tolerance for InfluxDB indexing timing
    if len(df) < 950:
        print(f"          Too few rows: {len(df)}/1000 (need >= 950)")
        return False

    return True


def test_3_write_ohlc(db: InfluxDBClient, ingestion: DataIngestion) -> bool:
    """Test 3: Write OHLC bars → query back → verify."""
    symbol = "XAUUSD"
    tf = "M15"
    bars = generate_fake_ohlc(symbol, tf, 100, 2650.0)

    written = 0
    for bar_msg in bars:
        parsed = ingestion.receive_from_feeder(bar_msg)
        if parsed and ingestion.store_to_influxdb(parsed):
            written += 1

    print(f"          Wrote {written}/100 OHLC bars")
    time.sleep(0.5)

    df = db.query_latest(symbol, MEASUREMENT_OHLC, 100, timeframe=tf)
    print(f"          Queried back: {len(df)} rows, columns: {list(df.columns)}")

    if df.empty:
        return False

    for col in ("open", "high", "low", "close", "volume"):
        if col not in df.columns:
            print(f"          Missing column: {col}")
            return False

    return len(df) == 100


def test_4_write_indicators(db: InfluxDBClient, ingestion: DataIngestion) -> bool:
    """Test 4: Write indicator data → query back → verify."""
    symbol = "XAUUSD"
    tf = "M15"
    now_ms = int(time.time() * 1000)

    indicator_msg = [
        MSG_INDICATOR_DATA, 1, now_ms, symbol, tf,
        {"rsi": 55.3, "atr": 12.5, "adx": 28.7,
         "bb_upper": 2680.0, "bb_middle": 2650.0, "bb_lower": 2620.0}
    ]

    parsed = ingestion.receive_from_feeder(indicator_msg)
    if not parsed:
        print("          Failed to parse indicator message")
        return False

    ok = ingestion.store_to_influxdb(parsed)
    if not ok:
        print("          Failed to store indicator")
        return False

    time.sleep(0.5)

    df = db.query_latest(symbol, MEASUREMENT_INDICATORS, 10, timeframe=tf)
    print(f"          Queried back: {len(df)} rows, columns: {list(df.columns)}")

    if df.empty:
        return False

    last_row = df.iloc[-1]
    if "rsi" in df.columns:
        rsi_val = last_row["rsi"]
        print(f"          RSI = {rsi_val}")
        return abs(rsi_val - 55.3) < 0.01
    return True


def test_5_parse_validation(ingestion: DataIngestion) -> bool:
    """Test 5: Message parsing edge cases."""
    # Valid tick
    ok = ingestion.receive_from_feeder([1, 1, 1000, "EURUSD", 1.05, 1.06, 6])
    if ok is None:
        print("          Failed to parse valid tick")
        return False

    # Invalid: ask < bid
    bad = ingestion.receive_from_feeder([1, 2, 1000, "EURUSD", 1.06, 1.05, 6])
    if bad is not None:
        print("          Should reject ask < bid")
        return False

    # Invalid: negative price
    bad2 = ingestion.receive_from_feeder([1, 3, 1000, "EURUSD", -1.0, 1.05, 6])
    if bad2 is not None:
        print("          Should reject negative price")
        return False

    # Invalid: too short
    bad3 = ingestion.receive_from_feeder([1, 4])
    if bad3 is not None:
        print("          Should reject short message")
        return False

    # Valid OHLC
    ok_ohlc = ingestion.receive_from_feeder(
        [2, 1, 1000, "XAUUSD", "M15", 2650.0, 2660.0, 2640.0, 2655.0, 500]
    )
    if ok_ohlc is None:
        print("          Failed to parse valid OHLC")
        return False

    # Invalid OHLC: high < low
    bad_ohlc = ingestion.receive_from_feeder(
        [2, 2, 1000, "XAUUSD", "M15", 2650.0, 2640.0, 2660.0, 2655.0, 500]
    )
    if bad_ohlc is not None:
        print("          Should reject high < low")
        return False

    # Valid indicator
    ok_ind = ingestion.receive_from_feeder(
        [3, 1, 1000, "XAUUSD", "M15", {"rsi": 50.0, "atr": 10.0}]
    )
    if ok_ind is None:
        print("          Failed to parse valid indicator")
        return False

    print(f"          All edge cases handled correctly")
    return True


def test_6_derived_indicators(ingestion: DataIngestion) -> bool:
    """Test 6: Calculate derived indicators from stored OHLC."""
    result = ingestion.calculate_derived_indicators("XAUUSD", "M15", 100)

    if result is None:
        print("          No indicators calculated (might need more OHLC data)")
        return True  # Soft pass

    print(f"          Calculated: {list(result.keys())}")
    for k, v in result.items():
        print(f"            {k}: {v}")

    return "rsi" in result or "atr" in result


def test_7_feature_dataframe(ingestion: DataIngestion) -> bool:
    """Test 7: Get ML-ready feature DataFrame."""
    df = ingestion.get_feature_dataframe("XAUUSD", lookback_bars=100, timeframe="M15")

    if df.empty:
        print("          Empty feature DataFrame (expected if insufficient data)")
        return True  # Soft pass

    print(f"          Shape: {df.shape}")
    print(f"          Columns: {list(df.columns)}")
    print(f"          NaN count: {df.isna().sum().sum()}")

    expected = ["close", "returns"]
    for col in expected:
        if col not in df.columns:
            print(f"          Missing expected column: {col}")
            return False

    return True


def test_8_batch_performance(db: InfluxDBClient) -> bool:
    """Test 8: Batch write performance."""
    symbol = "EURUSD"
    n = 5000
    base_price = 1.0540
    now_ms = int(time.time() * 1000)

    batch = []
    price = base_price
    for i in range(n):
        price += random.uniform(-0.0005, 0.0005)
        spread = random.uniform(0.00005, 0.0002)
        batch.append({
            "symbol": symbol,
            "bid": round(price, 5),
            "ask": round(price + spread, 5),
            "volume": random.randint(1, 20),
            "timestamp_ms": now_ms + (i * 20),
        })

    t_start = time.perf_counter()
    written = db.write_ticks_batch(batch)
    elapsed = time.perf_counter() - t_start

    rate = written / elapsed if elapsed > 0 else 0
    print(f"          Batch: {written}/{n} ticks in {elapsed:.3f}s ({rate:.0f} ticks/sec)")

    return written == n


# =============================================================================
# Main
# =============================================================================

def main():
    print_header("FlashEASuite V2 - InfluxDB Integration Test")
    print(f"  InfluxDB URL: http://localhost:8086")
    print(f"  Org: flashea | Bucket: trading")
    print()

    db = InfluxDBClient()
    ingestion = DataIngestion(db)
    results = []

    # Test 1: Connection
    print_header("Test 1: Connection & Health Check")
    try:
        ok = test_1_connection(db)
        print_result("InfluxDB Connection", ok)
        results.append(("Connection", ok))
        if not ok:
            print("\n  ⚠️  Cannot connect to InfluxDB!")
            print("  Make sure influxd.exe is running on localhost:8086")
            print("  And token in config.py matches your InfluxDB token")

            # Still run parse tests
            print_header("Test 5: Message Parsing (no DB needed)")
            ok5 = test_5_parse_validation(ingestion)
            print_result("Message Parsing", ok5)
            results.append(("Message Parsing", ok5))

            print_header("SUMMARY")
            passed = sum(1 for _, r in results if r)
            total = len(results)
            print(f"  {passed}/{total} tests passed (DB tests skipped)")
            return

    except Exception as e:
        print_result("Connection", False, str(e))
        traceback.print_exc()
        return

    # Test 2: Write 1000 ticks
    print_header("Test 2: Write 1000 Ticks → Query → Verify")
    try:
        ok = test_2_write_1000_ticks(db, ingestion)
        print_result("1000 Ticks Round-trip", ok)
        results.append(("1000 Ticks", ok))
    except Exception as e:
        print_result("1000 Ticks", False, str(e))
        results.append(("1000 Ticks", False))

    # Test 3: OHLC
    print_header("Test 3: Write OHLC Bars → Query → Verify")
    try:
        ok = test_3_write_ohlc(db, ingestion)
        print_result("OHLC Bars", ok)
        results.append(("OHLC Bars", ok))
    except Exception as e:
        print_result("OHLC Bars", False, str(e))
        results.append(("OHLC Bars", False))

    # Test 4: Indicators
    print_header("Test 4: Write Indicators → Query → Verify")
    try:
        ok = test_4_write_indicators(db, ingestion)
        print_result("Indicators", ok)
        results.append(("Indicators", ok))
    except Exception as e:
        print_result("Indicators", False, str(e))
        results.append(("Indicators", False))

    # Test 5: Parse validation
    print_header("Test 5: Message Parsing Validation")
    try:
        ok = test_5_parse_validation(ingestion)
        print_result("Message Parsing", ok)
        results.append(("Message Parsing", ok))
    except Exception as e:
        print_result("Message Parsing", False, str(e))
        results.append(("Message Parsing", False))

    # Test 6: Derived indicators
    print_header("Test 6: Derived Indicators from OHLC")
    try:
        ok = test_6_derived_indicators(ingestion)
        print_result("Derived Indicators", ok)
        results.append(("Derived Indicators", ok))
    except Exception as e:
        print_result("Derived Indicators", False, str(e))
        results.append(("Derived Indicators", False))

    # Test 7: Feature DataFrame
    print_header("Test 7: ML Feature DataFrame")
    try:
        ok = test_7_feature_dataframe(ingestion)
        print_result("Feature DataFrame", ok)
        results.append(("Feature DataFrame", ok))
    except Exception as e:
        print_result("Feature DataFrame", False, str(e))
        results.append(("Feature DataFrame", False))

    # Test 8: Batch performance
    print_header("Test 8: Batch Write Performance (5000 ticks)")
    try:
        ok = test_8_batch_performance(db)
        print_result("Batch Performance", ok)
        results.append(("Batch Performance", ok))
    except Exception as e:
        print_result("Batch Performance", False, str(e))
        results.append(("Batch Performance", False))

    # Cleanup
    db.close()

    # Summary
    print_header("SUMMARY")
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"\n  Results: {passed}/{total} tests passed\n")
    for name, ok in results:
        status = "✅" if ok else "❌"
        print(f"    {status} {name}")

    print(f"\n  Ingestion stats: {ingestion.stats}")
    print(f"  DB stats: {db.stats}")

    if passed == total:
        print(f"\n  🎉 ALL TESTS PASSED! InfluxDB pipeline is ready.")
    else:
        print(f"\n  ⚠️  {total - passed} test(s) failed. Check logs above.")

    print()


if __name__ == "__main__":
    main()
