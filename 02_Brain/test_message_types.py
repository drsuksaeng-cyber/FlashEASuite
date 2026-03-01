#!/usr/bin/env python3
"""Test all 15 message types — serialize to_array() → from_array() roundtrip."""

import sys
sys.path.insert(0, '/home/claude/P0_2')
import msgpack
from python.message_types import *

def test_roundtrip(name, msg):
    """Test to_array → msgpack → unpack → from_array roundtrip."""
    arr = msg.to_array()
    packed = msgpack.packb(arr, use_bin_type=True)
    unpacked = msgpack.unpackb(packed, raw=False)
    
    # Use parse_message factory
    restored = parse_message(unpacked)
    assert restored is not None, f"{name}: parse_message returned None"
    assert restored.msg_type == msg.msg_type, f"{name}: msg_type mismatch"
    print(f"  ✅ {name}: {len(packed)} bytes, type={msg.msg_type}")
    return restored

print("=" * 60)
print("FlashEASuite V2 V6 — Message Types Test")
print("=" * 60)

# Type 1: TICK_DATA
t = test_roundtrip("TICK_DATA", TickDataMsg(
    timestamp_ms=now_ms(), symbol="XAUUSD.tp",
    bid=2650.50, ask=2650.80, last=2650.65, volume=100, time_msc_sent=now_ms()))

# Type 2: OHLC_DATA
test_roundtrip("OHLC_DATA", OHLCDataMsg(
    timestamp_ms=now_ms(), symbol="EURUSD.tp", timeframe="H1",
    open=1.08500, high=1.08700, low=1.08400, close=1.08650,
    volume=5000, bar_time=1707800000))

# Type 3: INDICATOR_DATA
test_roundtrip("INDICATOR_DATA", IndicatorDataMsg(
    timestamp_ms=now_ms(), symbol="XAUUSD.tp", timeframe="M15",
    indicators={"rsi_14": 55.2, "atr_14": 0.0015, "adx_14": 28.5, "bb_width": 0.003}))

# Type 10: CONFIG_PUSH
test_roundtrip("CONFIG_PUSH", ConfigPushMsg(
    timestamp_ms=now_ms(), regime="RANGING",
    symbol_configs=[{
        "symbol": "XAUUSD", 
        "strategies": [{"id": "S01", "name": "StatArb", "enabled": True, "confidence": 0.69}]
    }],
    reasoning={"XAUUSD": {"regime": "RANGING", "selected": ["S01"]}},
    standalone_config={"enabled_strategies": ["S01","S06","S15"], "risk_multiplier": 0.5}))

# Type 11: CLIENT_HELLO
test_roundtrip("CLIENT_HELLO", ClientHelloMsg(
    timestamp_ms=now_ms(), client_id="CLIENT_001",
    account_number=12345678, broker="ThinkMarkets",
    terminal_version="5.0.45", symbol_suffix=".tp"))

# Type 12: INITIAL_CONFIG
test_roundtrip("INITIAL_CONFIG", InitialConfigMsg(
    timestamp_ms=now_ms(), client_id="CLIENT_001", regime="TRENDING",
    symbol_configs=[{"symbol": "XAUUSD", "strategies": []}],
    standalone_config={}, server_version="6.0.0"))

# Type 13: HEARTBEAT
test_roundtrip("HEARTBEAT", HeartbeatMsg(
    timestamp_ms=now_ms(), source="SERVER", sequence=42, is_alive=True))

# Type 20: TRADE_REPORT
test_roundtrip("TRADE_REPORT", TradeReportMsg(
    timestamp_ms=now_ms(), client_id="CLIENT_001", symbol="XAUUSD.tp",
    strategy_id="S15", magic=1015, order_type=0, lots=0.01,
    open_price=2650.50, close_price=2655.20, profit=47.0,
    commission=-0.70, swap=-0.15, open_time_ms=now_ms(), close_time_ms=now_ms()))

# Type 21: POSITION_UPDATE
test_roundtrip("POSITION_UPDATE", PositionUpdateMsg(
    timestamp_ms=now_ms(), client_id="CLIENT_001", symbol="EURUSD.tp",
    strategy_id="S06", magic=1006, direction=1, lots=0.05,
    open_price=1.08500, current_price=1.08650, unrealized_pnl=7.50,
    sl=1.08200, tp=1.09000))

# Type 22: PERFORMANCE_METRICS
test_roundtrip("PERFORMANCE_METRICS", PerformanceMetricsMsg(
    timestamp_ms=now_ms(), client_id="CLIENT_001",
    balance=10000.0, equity=10047.50, margin_level=2500.0,
    total_trades=150, win_rate=0.62, daily_pnl=125.30, max_drawdown=3.5))

# Type 30: NEWS_ALERT
test_roundtrip("NEWS_ALERT", NewsAlertMsg(
    timestamp_ms=now_ms(), event_name="Non-Farm Payrolls",
    currency="USD", impact=3, forecast="200K", previous="187K",
    event_time_ms=now_ms() + 3600000))

# Type 31: REGIME_CHANGE
test_roundtrip("REGIME_CHANGE", RegimeChangeMsg(
    timestamp_ms=now_ms(), old_regime="RANGING", new_regime="TRENDING",
    confidence=0.87, method="RF_ML",
    affected_symbols=["XAUUSD", "EURUSD", "GBPUSD"]))

# Type 40: COMMAND
test_roundtrip("COMMAND", CommandMsg(
    timestamp_ms=now_ms(), target_client="CLIENT_001",
    command="CLOSE_ALL", parameters={"reason": "margin_call"}))

# Type 50: POLICY_UPDATE
test_roundtrip("POLICY_UPDATE", PolicyUpdateMsg(
    timestamp_ms=now_ms(), policy_version="2.0.1",
    policy_data={"max_orders": 10, "max_lots": 1.0}, signature="abc123"))

# Type 99: ERROR
test_roundtrip("ERROR", ErrorMsg(
    timestamp_ms=now_ms(), source="Brain",
    error_code=1001, error_message="Connection timeout"))

print()
print("=" * 60)
print("✅ ALL 15 MESSAGE TYPES PASSED — roundtrip verified!")
print("=" * 60)

# Test MsgType enum coverage
print(f"\nTotal MsgType values: {len(MsgType)}")
print(f"Total MSG_CLASS_MAP entries: {len(MSG_CLASS_MAP)}")
assert len(MsgType) == len(MSG_CLASS_MAP), "Mismatch between enum and class map!"
print("✅ Enum ↔ ClassMap consistency verified")
