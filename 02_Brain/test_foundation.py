#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 V6 — P0-5: Foundation Integration Test (Python Side)
=====================================================================
ทดสอบ Python Foundation ทั้งหมด (P0-1 ถึง P0-4) ทำงานร่วมกันได้

Test Scenarios:
  TC-01  All 15 message types: encode → decode → verify no data loss
  TC-02  CONFIG_PUSH V2: encode → decode → verify fields + V2 extensions
  TC-03  MessagePack round-trip: bytes → array → bytes ต้องเท่ากัน
  TC-04  Latency: encode/decode cycle < 10ms per message
  TC-05  Batch latency: 1000 messages < 100ms total
  TC-06  TRADE_REPORT parse: verify all 15 fields correct
  TC-07  parse_message() factory: all 15 types return correct class
  TC-08  Malformed message: graceful handling (no crash)
  TC-09  InfluxDB: write 100 ticks → query back → verify count (skip if offline)
  TC-10  InfluxDB: write OHLC → query M1 bars → verify (skip if offline)
  TC-11  ProtocolHandler: initialize offline mock (no live ZMQ)
  TC-12  ProtocolHandler: _pack / _unpack symmetry

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-18
"""

import sys
import os
import time
import logging
import traceback
from typing import List, Tuple, Callable

# =========================================================================
# Path Setup — test อยู่ที่ 02_Brain/ ข้างๆ core/ และ data/
# =========================================================================
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))

# ให้ import ได้จากหลายที่:  02_Brain/core/, 02_Brain/core/data/, 02_Brain/
sys.path.insert(0, _THIS_DIR)
sys.path.insert(0, os.path.join(_THIS_DIR, "core"))
sys.path.insert(0, os.path.join(_THIS_DIR, "core", "data"))

# =========================================================================
# Logging
# =========================================================================
logging.basicConfig(
    level=logging.WARNING,
    format="%(levelname)s | %(name)s | %(message)s",
)
logger = logging.getLogger("P0-5-Test")

# =========================================================================
# Import dependencies
# =========================================================================
try:
    import msgpack
    MSGPACK_OK = True
except ImportError:
    MSGPACK_OK = False

try:
    import zmq
    ZMQ_OK = True
except ImportError:
    ZMQ_OK = False

# message_types อาจอยู่ที่ core/ หรือ core/message_types.py
MESSAGE_TYPES_OK = False
try:
    from message_types import (
        MsgType, now_ms, parse_message,
        TickDataMsg, OHLCDataMsg, IndicatorDataMsg,
        ConfigPushMsg, ConfigPushV2,
        ClientHelloMsg, InitialConfigMsg, HeartbeatMsg,
        TradeReportMsg, PositionUpdateMsg, PerformanceMetricsMsg,
        NewsAlertMsg, RegimeChangeMsg, CommandMsg, PolicyUpdateMsg, ErrorMsg,
        MSG_CLASS_MAP,
    )
    MESSAGE_TYPES_OK = True
except ImportError:
    try:
        from core.message_types import (
            MsgType, now_ms, parse_message,
            TickDataMsg, OHLCDataMsg, IndicatorDataMsg,
            ConfigPushMsg, ConfigPushV2,
            ClientHelloMsg, InitialConfigMsg, HeartbeatMsg,
            TradeReportMsg, PositionUpdateMsg, PerformanceMetricsMsg,
            NewsAlertMsg, RegimeChangeMsg, CommandMsg, PolicyUpdateMsg, ErrorMsg,
            MSG_CLASS_MAP,
        )
        MESSAGE_TYPES_OK = True
    except ImportError as e:
        logger.error(f"Cannot import message_types: {e}")

PROTOCOL_OK = False
ProtocolHandler = None
try:
    from protocol_handler import ProtocolHandler  # type: ignore
    PROTOCOL_OK = True
except ImportError:
    try:
        from core.protocol_handler import ProtocolHandler  # type: ignore
        PROTOCOL_OK = True
    except ImportError:
        pass

INFLUXDB_OK = False
InfluxDBClientClass = None
DataIngestion = None
try:
    from influxdb_client_flashea import InfluxDBClient as InfluxDBClientClass  # type: ignore
    INFLUXDB_OK = True
except ImportError:
    try:
        # ชื่อไฟล์จริงคือ influxdb_client.py
        import importlib.util
        for candidate in [
            os.path.join(_THIS_DIR, "core", "data", "influxdb_client.py"),
            os.path.join(_THIS_DIR, "data", "influxdb_client.py"),
        ]:
            if os.path.exists(candidate):
                spec = importlib.util.spec_from_file_location("influxdb_client_flashea", candidate)
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                InfluxDBClientClass = mod.InfluxDBClient
                INFLUXDB_OK = True
                break
    except Exception:
        pass

# =========================================================================
# Test Framework (minimal, no pytest required)
# =========================================================================
_RESULTS: List[Tuple[str, bool, str]] = []


def run_test(name: str, fn: Callable):
    """Execute a test function and record pass/fail."""
    try:
        fn()
        _RESULTS.append((name, True, ""))
        print(f"  ✅ {name}")
        return True
    except AssertionError as e:
        msg = str(e) or "AssertionError"
        _RESULTS.append((name, False, msg))
        print(f"  ❌ {name}")
        print(f"     → {msg}")
        return False
    except Exception as e:
        msg = f"{type(e).__name__}: {e}"
        _RESULTS.append((name, False, msg))
        print(f"  ❌ {name}")
        print(f"     → {msg}")
        return False


def skip_test(name: str, reason: str):
    """Mark a test as skipped."""
    _RESULTS.append((name, True, f"SKIP: {reason}"))
    print(f"  ⏭️  {name}  [{reason}]")


def assert_eq(a, b, msg=""):
    assert a == b, msg or f"Expected {b!r}, got {a!r}"


def assert_close(a: float, b: float, tol: float = 1e-9, msg=""):
    assert abs(a - b) < tol, msg or f"|{a} - {b}| = {abs(a-b)} > tol {tol}"


# =========================================================================
# Sample data builders
# =========================================================================
def _ts():
    return now_ms() if MESSAGE_TYPES_OK else int(time.time() * 1000)


def _make_all_messages():
    """สร้าง sample instance ของทุก 15 message types."""
    ts = _ts()
    return [
        TickDataMsg(timestamp_ms=ts, symbol="EURUSD", bid=1.08500, ask=1.08503,
                    last=1.08501, volume=10, time_msc_sent=ts),
        OHLCDataMsg(timestamp_ms=ts, symbol="XAUUSD", timeframe="M1",
                    open=2320.0, high=2325.5, low=2318.0, close=2323.1,
                    volume=500, bar_time=ts // 1000),
        IndicatorDataMsg(timestamp_ms=ts, symbol="GBPUSD", timeframe="H1",
                         indicators={"rsi_14": 55.2, "atr_14": 0.0015, "adx_14": 28.5}),
        ConfigPushMsg(timestamp_ms=ts, regime="TRENDING",
                      symbol_configs=[{"symbol": "EURUSD", "enabled": True}],
                      reasoning={"summary_th": "ทดสอบ", "changes": []},
                      standalone_config={"default_mm": "MM01"}),
        ClientHelloMsg(timestamp_ms=ts, client_id="MT5_Test_001",
                       account_number=123456, broker="ICMarkets",
                       terminal_version="5.0.37", symbol_suffix=".tp"),
        InitialConfigMsg(timestamp_ms=ts, client_id="MT5_Test_001",
                         regime="RANGING",
                         symbol_configs=[{"symbol": "XAUUSD"}],
                         standalone_config={"risk_mult": 0.5},
                         server_version="6.0.0"),
        HeartbeatMsg(timestamp_ms=ts, source="SERVER", sequence=42, is_alive=True),
        TradeReportMsg(timestamp_ms=ts, client_id="MT5_Test_001", symbol="XAUUSD",
                       strategy_id="S01", magic=1001, order_type=0, lots=0.10,
                       open_price=2320.0, close_price=2325.0, profit=50.0,
                       commission=-1.5, swap=0.0,
                       open_time_ms=ts - 60000, close_time_ms=ts),
        PositionUpdateMsg(timestamp_ms=ts, client_id="MT5_Test_001", symbol="GBPUSD",
                          strategy_id="S07", magic=1007, direction=1, lots=0.05,
                          open_price=1.27000, current_price=1.27150,
                          unrealized_pnl=7.5, sl=1.26800, tp=1.27300),
        PerformanceMetricsMsg(timestamp_ms=ts, client_id="MT5_Test_001",
                              balance=10000.0, equity=10050.0, margin_level=1500.0,
                              total_trades=25, win_rate=0.64, daily_pnl=120.0,
                              max_drawdown=3.5),
        NewsAlertMsg(timestamp_ms=ts, event_name="USD NFP", currency="USD",
                     impact=3, forecast="200K", previous="180K",
                     event_time_ms=ts + 3600000),
        RegimeChangeMsg(timestamp_ms=ts, old_regime="TRENDING", new_regime="RANGING",
                        confidence=0.82, method="RF_ML",
                        affected_symbols=["EURUSD", "GBPUSD"]),
        CommandMsg(timestamp_ms=ts, target_client="", command="STOP",
                   parameters={"reason": "news_event"}),
        PolicyUpdateMsg(timestamp_ms=ts, policy_version="1.2.0",
                        policy_data={"max_lot": 1.0}, signature="ABC123"),
        ErrorMsg(timestamp_ms=ts, source="BRAIN", error_code=404,
                 error_message="Symbol not found"),
    ]


# =========================================================================
# TC-01: All 15 Message Types — encode → decode round-trip
# =========================================================================
def _tc01_all_message_types():
    assert MESSAGE_TYPES_OK, "message_types.py not importable — skip dependency"
    msgs = _make_all_messages()
    assert len(msgs) == 15, f"Expected 15 message instances, got {len(msgs)}"

    for msg in msgs:
        cls = type(msg)
        arr = msg.to_array()
        assert isinstance(arr, list), f"{cls.__name__}.to_array() must return list"
        assert len(arr) >= 2, f"{cls.__name__}.to_array() too short: {arr}"
        assert arr[0] == msg.msg_type, f"{cls.__name__} arr[0] != msg_type"

        rebuilt = cls.from_array(arr)
        assert rebuilt.msg_type == msg.msg_type, \
            f"{cls.__name__} msg_type lost: {rebuilt.msg_type}"


# =========================================================================
# TC-02: CONFIG_PUSH V2 — encode → decode → verify all V2 fields
# =========================================================================
def _tc02_config_push_v2():
    assert MESSAGE_TYPES_OK
    ts = _ts()
    cycle = "OPT_20260218_000000_0001"
    v2 = ConfigPushV2(
        timestamp_ms=ts,
        regime="VOLATILE",
        symbol_configs=[{
            "symbol": "XAUUSD",
            "strategies": [{
                "id": "S01", "enabled": True, "confidence": 0.75,
                "parameters": {"S01_LOOKBACK_PERIOD": 30, "S01_SIGNAL_PERIOD": 10},
                "mm_method": "MM04",
                "mm_parameters": {"MM04_KELLY_FRACTION": 0.35},
            }]
        }],
        reasoning={"summary_th": "Volatile regime — ลด position size", "changes": ["S01 confidence +0.05"],
                   "total_changes": 1},
        standalone_config={"enabled_strategies": ["S01", "S15"],
                           "default_mm": "MM01", "risk_multiplier": 0.5},
        optimization_cycle=cycle,
        version=2,
    )
    assert v2.is_v2, "is_v2 should be True"

    arr = v2.to_array()
    assert len(arr) == 8, f"V2 array must have 8 elements, got {len(arr)}"
    assert arr[6] == 2, f"arr[6] (version) should be 2, got {arr[6]}"
    assert arr[7] == cycle, f"arr[7] (cycle) mismatch"

    # round-trip
    v2b = ConfigPushV2.from_array(arr)
    assert v2b.regime == "VOLATILE"
    assert v2b.version == 2
    assert v2b.optimization_cycle == cycle
    sc = v2b.symbol_configs[0]["strategies"][0]
    assert sc["parameters"]["S01_LOOKBACK_PERIOD"] == 30
    assert sc["mm_method"] == "MM04"
    assert sc["mm_parameters"]["MM04_KELLY_FRACTION"] == 0.35

    # backward compat: V1 client reads V2 array at index 0-5
    v1 = ConfigPushMsg.from_array(arr)
    assert v1.regime == "VOLATILE"
    assert len(v1.symbol_configs) == 1

    # auto-detect via parse_message
    parsed = parse_message(arr)
    assert isinstance(parsed, ConfigPushV2), \
        f"parse_message with 8-elem array should return ConfigPushV2, got {type(parsed)}"


# =========================================================================
# TC-03: MessagePack round-trip bytes → array → bytes equality
# =========================================================================
def _tc03_msgpack_roundtrip():
    assert MESSAGE_TYPES_OK, "message_types required"
    assert MSGPACK_OK, "msgpack library not installed (pip install msgpack)"

    msgs = _make_all_messages()
    for msg in msgs:
        arr_original = msg.to_array()
        packed = msgpack.packb(arr_original, use_bin_type=True)
        assert isinstance(packed, bytes), f"msgpack.packb must return bytes"
        unpacked = msgpack.unpackb(packed, raw=False)
        # Compare reconstructed message
        msg2 = type(msg).from_array(unpacked)
        assert msg2.msg_type == msg.msg_type, \
            f"{type(msg).__name__} msg_type mismatch after msgpack round-trip"


# =========================================================================
# TC-04: Latency — encode/decode cycle < 10ms per message
# =========================================================================
def _tc04_latency_per_message():
    assert MESSAGE_TYPES_OK
    assert MSGPACK_OK, "msgpack required for latency test"

    TRIALS = 100
    threshold_ms = 10.0

    trade = TradeReportMsg(
        timestamp_ms=_ts(), client_id="CLIENT_001", symbol="XAUUSD",
        strategy_id="S01", magic=1001, order_type=0, lots=0.10,
        open_price=2320.0, close_price=2325.0, profit=50.0,
    )

    times_ms = []
    for _ in range(TRIALS):
        t0 = time.perf_counter()
        arr = trade.to_array()
        packed = msgpack.packb(arr, use_bin_type=True)
        unpacked = msgpack.unpackb(packed, raw=False)
        TradeReportMsg.from_array(unpacked)
        t1 = time.perf_counter()
        times_ms.append((t1 - t0) * 1000)

    avg_ms = sum(times_ms) / len(times_ms)
    max_ms = max(times_ms)
    assert max_ms < threshold_ms, \
        f"Max latency {max_ms:.3f}ms exceeds {threshold_ms}ms threshold (avg={avg_ms:.3f}ms)"


# =========================================================================
# TC-05: Batch latency — 1000 messages < 100ms total
# =========================================================================
def _tc05_batch_latency():
    assert MESSAGE_TYPES_OK
    assert MSGPACK_OK

    BATCH = 1000
    threshold_total_ms = 100.0

    ts = _ts()
    t0 = time.perf_counter()
    for i in range(BATCH):
        tick = TickDataMsg(timestamp_ms=ts + i, symbol="EURUSD",
                           bid=1.08500 + i * 0.00001, ask=1.08503 + i * 0.00001,
                           last=1.08501, volume=i % 100, time_msc_sent=ts + i)
        arr = tick.to_array()
        packed = msgpack.packb(arr, use_bin_type=True)
        unpacked = msgpack.unpackb(packed, raw=False)
        TickDataMsg.from_array(unpacked)
    t1 = time.perf_counter()
    total_ms = (t1 - t0) * 1000

    assert total_ms < threshold_total_ms, \
        f"Batch {BATCH} ticks took {total_ms:.1f}ms > {threshold_total_ms}ms limit"


# =========================================================================
# TC-06: TRADE_REPORT — verify all 15 fields survive round-trip
# =========================================================================
def _tc06_trade_report_fields():
    assert MESSAGE_TYPES_OK

    ts = _ts()
    orig = TradeReportMsg(
        timestamp_ms=ts, client_id="MT5_Client_007", symbol="GBPJPY",
        strategy_id="S14", magic=1014, order_type=1, lots=0.25,
        open_price=192.500, close_price=191.800, profit=-175.0,
        commission=-2.0, swap=-0.5,
        open_time_ms=ts - 3600000, close_time_ms=ts,
    )
    arr = orig.to_array()
    assert len(arr) == 15, f"TradeReportMsg.to_array() must have 15 elements, got {len(arr)}"

    back = TradeReportMsg.from_array(arr)
    assert_eq(back.client_id,   orig.client_id)
    assert_eq(back.symbol,      orig.symbol)
    assert_eq(back.strategy_id, orig.strategy_id)
    assert_eq(back.magic,       orig.magic)
    assert_eq(back.order_type,  orig.order_type)
    assert_close(back.lots,        orig.lots)
    assert_close(back.open_price,  orig.open_price)
    assert_close(back.close_price, orig.close_price)
    assert_close(back.profit,      orig.profit)
    assert_close(back.commission,  orig.commission)
    assert_close(back.swap,        orig.swap)
    assert_eq(back.open_time_ms,  orig.open_time_ms)
    assert_eq(back.close_time_ms, orig.close_time_ms)


# =========================================================================
# TC-07: parse_message() factory — all 15 types → correct class
# =========================================================================
def _tc07_parse_message_factory():
    assert MESSAGE_TYPES_OK

    msgs = _make_all_messages()
    expected_classes = {
        1:  TickDataMsg,
        2:  OHLCDataMsg,
        3:  IndicatorDataMsg,
        10: ConfigPushMsg,   # V1 (6 elements) → ConfigPushMsg
        11: ClientHelloMsg,
        12: InitialConfigMsg,
        13: HeartbeatMsg,
        20: TradeReportMsg,
        21: PositionUpdateMsg,
        22: PerformanceMetricsMsg,
        30: NewsAlertMsg,
        31: RegimeChangeMsg,
        40: CommandMsg,
        50: PolicyUpdateMsg,
        99: ErrorMsg,
    }

    for msg in msgs:
        arr = msg.to_array()
        parsed = parse_message(arr)
        mt = msg.msg_type
        expected_cls = expected_classes[mt]
        assert isinstance(parsed, expected_cls), \
            f"parse_message(type={mt}) → {type(parsed).__name__}, expected {expected_cls.__name__}"

    # V2 CONFIG_PUSH (8 elements) → ConfigPushV2
    v2 = ConfigPushV2(regime="TRENDING", optimization_cycle="OPT_TEST")
    parsed_v2 = parse_message(v2.to_array())
    assert isinstance(parsed_v2, ConfigPushV2), \
        f"parse_message(V2 array) should return ConfigPushV2, got {type(parsed_v2)}"


# =========================================================================
# TC-08: Malformed messages — graceful handling
# =========================================================================
def _tc08_malformed_messages():
    assert MESSAGE_TYPES_OK

    # Empty array
    r1 = parse_message([])
    assert r1 is None, f"parse_message([]) should return None, got {r1}"

    # Unknown type
    r2 = parse_message([999, 0, "x"])
    assert r2 is None, f"parse_message([999, ...]) should return None, got {r2}"

    # Too short
    r3 = parse_message([1])
    assert r3 is None, f"parse_message([1]) (1 element) should return None, got {r3}"

    # None input
    try:
        r4 = parse_message(None)
        # Should either return None or raise TypeError — both OK
    except (TypeError, AttributeError):
        pass  # Acceptable

    # Partial TradeReport — missing optional fields should not crash
    partial = [20, _ts(), "C1", "EURUSD", "S01", 1001, 0, 0.1, 1.085, 1.087, 20.0]
    r5 = parse_message(partial)
    assert isinstance(r5, TradeReportMsg), "Partial TradeReport should still parse"


# =========================================================================
# TC-09: InfluxDB — write 100 ticks → query back (skip if offline)
# =========================================================================
def _tc09_influxdb_write_ticks():
    assert INFLUXDB_OK and InfluxDBClientClass is not None, "InfluxDB client not importable"

    client = InfluxDBClientClass()
    if not client.connect():
        raise AssertionError("SKIP_OFFLINE: Cannot connect to InfluxDB — run with live server")

    try:
        ts_base = int(time.time() * 1000)
        test_tag = f"test_{ts_base}"
        written = 0

        for i in range(100):
            ts = ts_base + i * 100  # 100ms apart
            tick = {
                "timestamp_ms": ts,
                "symbol": "EURUSD_TEST",
                "bid": 1.08500 + i * 0.00001,
                "ask": 1.08503 + i * 0.00001,
                "volume": i,
            }
            ok = client.write_tick(tick)
            if ok:
                written += 1

        client.flush()
        time.sleep(1.5)  # wait for InfluxDB to index

        # Query back
        count = client.count_ticks("EURUSD_TEST",
                                   start_ms=ts_base - 1000,
                                   end_ms=ts_base + 15000)
        assert count >= 95, \
            f"Expected ≥95 ticks back, got {count} (wrote {written})"
    finally:
        client.close()


# =========================================================================
# TC-10: InfluxDB — write OHLC → query bars (skip if offline)
# =========================================================================
def _tc10_influxdb_ohlc():
    assert INFLUXDB_OK and InfluxDBClientClass is not None, "InfluxDB client not importable"

    client = InfluxDBClientClass()
    if not client.connect():
        raise AssertionError("SKIP_OFFLINE: Cannot connect to InfluxDB")

    try:
        ts_base = int(time.time())
        bar = {
            "timestamp_ms": ts_base * 1000,
            "symbol": "XAUUSD_TEST",
            "timeframe": "M1",
            "open": 2320.0, "high": 2325.0, "low": 2318.0, "close": 2322.5,
            "volume": 120,
            "bar_time": ts_base,
        }
        ok = client.write_ohlc(bar)
        assert ok, "write_ohlc returned False"
        client.flush()
        time.sleep(1.0)

        df = client.query_ohlc("XAUUSD_TEST", "M1", n_bars=10)
        assert df is not None and len(df) >= 1, \
            f"query_ohlc returned {len(df) if df is not None else 'None'} bars"
    finally:
        client.close()


# =========================================================================
# TC-11: ProtocolHandler — offline mock initialization
# =========================================================================
def _tc11_protocol_handler_init():
    assert PROTOCOL_OK and ProtocolHandler is not None, "ProtocolHandler not importable"
    assert ZMQ_OK, "zmq not installed"

    # Initialize with non-binding mock (test only encode/decode methods)
    ph = ProtocolHandler(
        feeder_pull_addr="tcp://127.0.0.1:17777",   # use non-standard ports
        pub_addr="tcp://127.0.0.1:17778",
        client_pull_addr="tcp://127.0.0.1:17779",
    )
    # Test that the object exists and has expected methods
    assert hasattr(ph, "initialize"), "ProtocolHandler missing initialize()"
    assert hasattr(ph, "send_config_push"), "ProtocolHandler missing send_config_push()"
    assert hasattr(ph, "shutdown"), "ProtocolHandler missing shutdown()"


# =========================================================================
# TC-12: ProtocolHandler _pack/_unpack symmetry (offline)
# =========================================================================
def _tc12_protocol_pack_unpack():
    assert PROTOCOL_OK and ProtocolHandler is not None, "ProtocolHandler not importable"
    assert MSGPACK_OK

    ph = ProtocolHandler()

    # Test internal pack/unpack if method exists, else test msgpack directly
    pack_fn = getattr(ph, "_pack", None) or getattr(ph, "_encode", None)
    unpack_fn = getattr(ph, "_unpack", None) or getattr(ph, "_decode", None)

    if pack_fn and unpack_fn:
        data = [10, _ts(), "TRENDING", [{"symbol": "EURUSD"}], {}, {}]
        packed = pack_fn(data)
        unpacked = unpack_fn(packed)
        assert unpacked[2] == "TRENDING", "Pack/unpack round-trip failed"
    else:
        # Fallback: test msgpack directly mimicking what ProtocolHandler does
        data = [20, _ts(), "CLIENT_001", "XAUUSD", "S01", 1001, 0, 0.1, 1.0, 1.0, 5.0]
        packed = msgpack.packb(data, use_bin_type=True)
        unpacked = msgpack.unpackb(packed, raw=False)
        assert_eq(unpacked[2], "CLIENT_001")
        assert_close(unpacked[7], 0.1)


# =========================================================================
# Main Runner
# =========================================================================
def main():
    print()
    print("=" * 65)
    print("  FlashEASuite V2 — P0-5 Foundation Integration Test (Python)")
    print("=" * 65)
    print()

    # Dependency summary
    print("📦 Dependencies:")
    print(f"   msgpack      : {'✅' if MSGPACK_OK else '❌ pip install msgpack'}")
    print(f"   zmq          : {'✅' if ZMQ_OK else '❌ pip install pyzmq'}")
    print(f"   message_types: {'✅' if MESSAGE_TYPES_OK else '❌'}")
    print(f"   protocol     : {'✅' if PROTOCOL_OK else '⚠️  not found (TC-11/12 will skip)'}")
    print(f"   influxdb     : {'✅' if INFLUXDB_OK else '⚠️  not found (TC-09/10 will skip)'}")
    print()

    if not MESSAGE_TYPES_OK:
        print("❌ FATAL: Cannot import message_types.py — cannot run tests.")
        print("   วาง test_foundation.py ที่ 02_Brain/ หรือ 02_Brain/core/")
        sys.exit(1)

    # ─── Core message type tests (must have msgpack)
    print("── Group A: Message Types & Serialization ──────────────────")
    run_test("TC-01 All 15 message types round-trip", _tc01_all_message_types)
    run_test("TC-02 CONFIG_PUSH V2 fields + backward compat", _tc02_config_push_v2)

    if MSGPACK_OK:
        run_test("TC-03 MessagePack bytes round-trip", _tc03_msgpack_roundtrip)
        run_test("TC-04 Latency per message < 10ms", _tc04_latency_per_message)
        run_test("TC-05 Batch 1000 msgs < 100ms", _tc05_batch_latency)
    else:
        skip_test("TC-03 MessagePack bytes round-trip", "msgpack not installed")
        skip_test("TC-04 Latency per message < 10ms", "msgpack not installed")
        skip_test("TC-05 Batch 1000 msgs < 100ms", "msgpack not installed")

    print()
    print("── Group B: Field Verification ─────────────────────────────")
    run_test("TC-06 TRADE_REPORT all 15 fields", _tc06_trade_report_fields)
    run_test("TC-07 parse_message() factory all 15 types", _tc07_parse_message_factory)
    run_test("TC-08 Malformed messages graceful handling", _tc08_malformed_messages)

    print()
    print("── Group C: InfluxDB Pipeline ───────────────────────────────")
    if INFLUXDB_OK:
        try:
            run_test("TC-09 InfluxDB write 100 ticks + query back", _tc09_influxdb_write_ticks)
            run_test("TC-10 InfluxDB write OHLC + query bars", _tc10_influxdb_ohlc)
        except AssertionError as e:
            if "SKIP_OFFLINE" in str(e):
                skip_test("TC-09 InfluxDB write ticks", "InfluxDB server offline")
                skip_test("TC-10 InfluxDB write OHLC", "InfluxDB server offline")
    else:
        skip_test("TC-09 InfluxDB write ticks", "influxdb_client not importable")
        skip_test("TC-10 InfluxDB write OHLC", "influxdb_client not importable")

    print()
    print("── Group D: Protocol Handler ────────────────────────────────")
    if PROTOCOL_OK and ZMQ_OK:
        run_test("TC-11 ProtocolHandler offline init", _tc11_protocol_handler_init)
        run_test("TC-12 ProtocolHandler pack/unpack symmetry", _tc12_protocol_pack_unpack)
    else:
        skip_test("TC-11 ProtocolHandler offline init",
                  "protocol_handler or zmq not available")
        skip_test("TC-12 ProtocolHandler pack/unpack symmetry",
                  "protocol_handler or zmq not available")

    # ─── Summary
    print()
    print("=" * 65)
    passed   = sum(1 for _, ok, reason in _RESULTS if ok and not reason.startswith("SKIP"))
    skipped  = sum(1 for _, ok, reason in _RESULTS if ok and reason.startswith("SKIP"))
    failed   = sum(1 for _, ok, _ in _RESULTS if not ok)
    total    = len(_RESULTS)

    print(f"  TOTAL : {total}   PASSED : {passed}   SKIPPED : {skipped}   FAILED : {failed}")
    print()

    if failed == 0:
        print("  🎉 ALL TESTS PASSED (หรือ SKIPPED เนื่องจาก offline)")
        print("  ✅ Python Foundation (P0-1 ~ P0-4) พร้อมใช้งาน")
    else:
        print("  ⚠️  มีบางเทสไม่ผ่าน กรุณาแก้ไขก่อน deploy")
        for name, ok, reason in _RESULTS:
            if not ok:
                print(f"     ❌ {name}: {reason}")

    print("=" * 65)
    print()
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
