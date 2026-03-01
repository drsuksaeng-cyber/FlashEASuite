#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 V6 — Message Type Definitions
15 message types for communication between Feeder, Brain (Server), and Trader (Clients).

Author: Dr. Suksaeng Kukanok
Version: 6.0.0
Date: 2026-02-13

Protocol Overview:
  Feeder → Server:  PUSH/PULL (Port 7777)  — Types 1-3
  Server → Clients: PUB/SUB  (Port 7778)  — Types 10,12,13,30,31,40,50
  Clients → Server: PUSH/PULL (Port 7779)  — Types 11,13,20,21,22
  Any → Any:                                — Type 99
"""

from dataclasses import dataclass, field
from enum import IntEnum
from typing import List, Dict, Any, Optional
import time


# ====================================================================
# Message Type Enumeration
# ====================================================================
class MsgType(IntEnum):
    """15 message types for FlashEASuite V2 V6 protocol."""
    # --- Feeder → Server (Port 7777 PUSH/PULL) ---
    TICK_DATA           = 1   # Raw tick data (bid, ask, volume)
    OHLC_DATA           = 2   # OHLC bars (M1, M5, M15, H1, H4, D1)
    INDICATOR_DATA      = 3   # Pre-calculated indicators from Feeder

    # --- Server → Clients (Port 7778 PUB/SUB) ---
    CONFIG_PUSH         = 10  # Strategy/MM configuration + reasoning
    INITIAL_CONFIG      = 12  # First-time config + standalone fallback
    HEARTBEAT           = 13  # Keep-alive (every 10s, timeout 30s)
    NEWS_ALERT          = 30  # Economic calendar alert
    REGIME_CHANGE       = 31  # Market regime shift notification
    COMMAND             = 40  # Manual command (stop, start, etc.)
    POLICY_UPDATE       = 50  # Security policy update

    # --- Clients → Server (Port 7779 PUSH/PULL) ---
    CLIENT_HELLO        = 11  # Client registration
    TRADE_REPORT        = 20  # Trade execution report
    POSITION_UPDATE     = 21  # Position status
    PERFORMANCE_METRICS = 22  # Performance stats

    # --- Any → Any ---
    ERROR               = 99  # Error message


# ====================================================================
# Direction Constants (for documentation / validation)
# ====================================================================
class Direction:
    """Message direction constants."""
    FEEDER_TO_SERVER  = "Feeder→Server"
    SERVER_TO_CLIENT  = "Server→Client"
    CLIENT_TO_SERVER  = "Client→Server"
    BIDIRECTIONAL     = "Any→Any"


# Direction mapping for each message type
MSG_DIRECTION = {
    MsgType.TICK_DATA:           Direction.FEEDER_TO_SERVER,
    MsgType.OHLC_DATA:           Direction.FEEDER_TO_SERVER,
    MsgType.INDICATOR_DATA:      Direction.FEEDER_TO_SERVER,
    MsgType.CONFIG_PUSH:         Direction.SERVER_TO_CLIENT,
    MsgType.CLIENT_HELLO:        Direction.CLIENT_TO_SERVER,
    MsgType.INITIAL_CONFIG:      Direction.SERVER_TO_CLIENT,
    MsgType.HEARTBEAT:           Direction.BIDIRECTIONAL,
    MsgType.TRADE_REPORT:        Direction.CLIENT_TO_SERVER,
    MsgType.POSITION_UPDATE:     Direction.CLIENT_TO_SERVER,
    MsgType.PERFORMANCE_METRICS: Direction.CLIENT_TO_SERVER,
    MsgType.NEWS_ALERT:          Direction.SERVER_TO_CLIENT,
    MsgType.REGIME_CHANGE:       Direction.SERVER_TO_CLIENT,
    MsgType.COMMAND:             Direction.SERVER_TO_CLIENT,
    MsgType.POLICY_UPDATE:       Direction.SERVER_TO_CLIENT,
    MsgType.ERROR:               Direction.BIDIRECTIONAL,
}


# ====================================================================
# Port Configuration
# ====================================================================
class PortConfig:
    """ZMQ port assignments."""
    FEEDER_PORT  = 7777  # Feeder → Server (PUSH/PULL)
    PUB_PORT     = 7778  # Server → Clients (PUB/SUB)
    CLIENT_PORT  = 7779  # Clients → Server (PUSH/PULL)


# ====================================================================
# Message Dataclasses — Feeder → Server
# ====================================================================
@dataclass
class TickDataMsg:
    """Type 1: Raw tick data from Feeder."""
    msg_type: int = MsgType.TICK_DATA
    timestamp_ms: int = 0
    symbol: str = ""
    bid: float = 0.0
    ask: float = 0.0
    last: float = 0.0
    volume: int = 0
    time_msc_sent: int = 0  # When feeder sent this tick

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.symbol,
                self.bid, self.ask, self.last, self.volume, self.time_msc_sent]

    @classmethod
    def from_array(cls, arr: list) -> 'TickDataMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], symbol=arr[2],
            bid=arr[3], ask=arr[4], last=arr[5],
            volume=int(arr[6]), time_msc_sent=int(arr[7])
        )


@dataclass
class OHLCDataMsg:
    """Type 2: OHLC bar data from Feeder."""
    msg_type: int = MsgType.OHLC_DATA
    timestamp_ms: int = 0
    symbol: str = ""
    timeframe: str = ""     # "M1","M5","M15","H1","H4","D1"
    open: float = 0.0
    high: float = 0.0
    low: float = 0.0
    close: float = 0.0
    volume: int = 0
    bar_time: int = 0       # Bar open time (epoch seconds)

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.symbol, self.timeframe,
                self.open, self.high, self.low, self.close, self.volume, self.bar_time]

    @classmethod
    def from_array(cls, arr: list) -> 'OHLCDataMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], symbol=arr[2], timeframe=arr[3],
            open=arr[4], high=arr[5], low=arr[6], close=arr[7],
            volume=int(arr[8]), bar_time=int(arr[9])
        )


@dataclass
class IndicatorDataMsg:
    """Type 3: Pre-calculated indicator data from Feeder."""
    msg_type: int = MsgType.INDICATOR_DATA
    timestamp_ms: int = 0
    symbol: str = ""
    timeframe: str = ""
    indicators: Dict[str, float] = field(default_factory=dict)
    # indicators example: {"rsi_14": 55.2, "atr_14": 0.0015, "adx_14": 28.5, ...}

    def to_array(self) -> list:
        # Flatten indicators dict into key-value pairs list
        ind_pairs = []
        for k, v in self.indicators.items():
            ind_pairs.append(k)
            ind_pairs.append(v)
        return [self.msg_type, self.timestamp_ms, self.symbol, self.timeframe,
                len(self.indicators), *ind_pairs]

    @classmethod
    def from_array(cls, arr: list) -> 'IndicatorDataMsg':
        n_indicators = int(arr[4])
        indicators = {}
        idx = 5
        for _ in range(n_indicators):
            if idx + 1 < len(arr):
                indicators[arr[idx]] = float(arr[idx + 1])
                idx += 2
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], symbol=arr[2],
            timeframe=arr[3], indicators=indicators
        )


# ====================================================================
# Message Dataclasses — Server → Clients
# ====================================================================
@dataclass
class ConfigPushMsg:
    """Type 10: Strategy/MM configuration + reasoning chain."""
    msg_type: int = MsgType.CONFIG_PUSH
    timestamp_ms: int = 0
    regime: str = ""                                # "TRENDING","RANGING","VOLATILE","SQUEEZE"
    symbol_configs: List[Dict[str, Any]] = field(default_factory=list)
    reasoning: Dict[str, Any] = field(default_factory=dict)
    standalone_config: Dict[str, Any] = field(default_factory=dict)

    def to_array(self) -> list:
        """Serialize to MessagePack-friendly array.
        Complex nested structures are kept as dicts — msgpack handles them natively.
        """
        return [self.msg_type, self.timestamp_ms, self.regime,
                self.symbol_configs, self.reasoning, self.standalone_config]

    @classmethod
    def from_array(cls, arr: list) -> 'ConfigPushMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], regime=arr[2],
            symbol_configs=arr[3] if len(arr) > 3 else [],
            reasoning=arr[4] if len(arr) > 4 else {},
            standalone_config=arr[5] if len(arr) > 5 else {}
        )


@dataclass
class ConfigPushV2:
    """Type 10 V2: Expanded CONFIG_PUSH with dynamic parameters.

    Backward compatible with V1 ConfigPushMsg:
      - Index 0-5 identical to V1 → old clients parse normally
      - Index 6-7 are V2 extensions → old clients ignore extra fields

    V2 additions:
      - version (int): Protocol version (2)
      - optimization_cycle (str): Unique cycle ID e.g. "OPT_20260217_000000_0001"

    symbol_configs V2 format per strategy:
      {"id": "S01", "enabled": true, "confidence": 0.69,
       "parameters": {"S01_LOOKBACK_PERIOD": 25, ...},
       "mm_method": "MM04",
       "mm_parameters": {"MM04_KELLY_FRACTION": 0.4, ...}}
    """
    msg_type: int = MsgType.CONFIG_PUSH
    timestamp_ms: int = 0
    regime: str = ""
    symbol_configs: List[Dict[str, Any]] = field(default_factory=list)
    reasoning: Dict[str, Any] = field(default_factory=dict)
    standalone_config: Dict[str, Any] = field(default_factory=dict)
    # --- V2 extensions ---
    version: int = 2
    optimization_cycle: str = ""

    def to_array(self) -> list:
        """Serialize to MessagePack-friendly array.
        Index 0-5 identical to V1 for backward compatibility.
        Index 6-7 are V2 extensions (old clients ignore).
        """
        return [self.msg_type, self.timestamp_ms, self.regime,
                self.symbol_configs, self.reasoning, self.standalone_config,
                self.version, self.optimization_cycle]

    @classmethod
    def from_array(cls, arr: list) -> 'ConfigPushV2':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], regime=arr[2],
            symbol_configs=arr[3] if len(arr) > 3 else [],
            reasoning=arr[4] if len(arr) > 4 else {},
            standalone_config=arr[5] if len(arr) > 5 else {},
            version=arr[6] if len(arr) > 6 else 1,
            optimization_cycle=arr[7] if len(arr) > 7 else "",
        )

    @classmethod
    def from_v1(cls, v1_msg: ConfigPushMsg) -> 'ConfigPushV2':
        """Convert V1 ConfigPushMsg → V2."""
        return cls(
            msg_type=v1_msg.msg_type, timestamp_ms=v1_msg.timestamp_ms,
            regime=v1_msg.regime, symbol_configs=v1_msg.symbol_configs,
            reasoning=v1_msg.reasoning, standalone_config=v1_msg.standalone_config,
            version=1, optimization_cycle="",
        )

    @property
    def is_v2(self) -> bool:
        return self.version >= 2


@dataclass
class ClientHelloMsg:
    """Type 11: Client registration."""
    msg_type: int = MsgType.CLIENT_HELLO
    timestamp_ms: int = 0
    client_id: str = ""
    account_number: int = 0
    broker: str = ""
    terminal_version: str = ""
    symbol_suffix: str = ""     # e.g. ".tp"

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.client_id,
                self.account_number, self.broker, self.terminal_version,
                self.symbol_suffix]

    @classmethod
    def from_array(cls, arr: list) -> 'ClientHelloMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], client_id=arr[2],
            account_number=int(arr[3]), broker=arr[4],
            terminal_version=arr[5] if len(arr) > 5 else "",
            symbol_suffix=arr[6] if len(arr) > 6 else ""
        )


@dataclass
class InitialConfigMsg:
    """Type 12: First-time config sent to newly registered client."""
    msg_type: int = MsgType.INITIAL_CONFIG
    timestamp_ms: int = 0
    client_id: str = ""
    regime: str = ""
    symbol_configs: List[Dict[str, Any]] = field(default_factory=list)
    standalone_config: Dict[str, Any] = field(default_factory=dict)
    server_version: str = ""

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.client_id, self.regime,
                self.symbol_configs, self.standalone_config, self.server_version]

    @classmethod
    def from_array(cls, arr: list) -> 'InitialConfigMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], client_id=arr[2],
            regime=arr[3], symbol_configs=arr[4] if len(arr) > 4 else [],
            standalone_config=arr[5] if len(arr) > 5 else {},
            server_version=arr[6] if len(arr) > 6 else ""
        )


@dataclass
class HeartbeatMsg:
    """Type 13: Keep-alive (bidirectional, every 10s, timeout 30s)."""
    msg_type: int = MsgType.HEARTBEAT
    timestamp_ms: int = 0
    source: str = ""            # "SERVER", "CLIENT_xxx"
    sequence: int = 0
    is_alive: bool = True

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.source,
                self.sequence, 1 if self.is_alive else 0]

    @classmethod
    def from_array(cls, arr: list) -> 'HeartbeatMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], source=arr[2],
            sequence=int(arr[3]), is_alive=bool(arr[4])
        )


# ====================================================================
# Message Dataclasses — Clients → Server
# ====================================================================
@dataclass
class TradeReportMsg:
    """Type 20: Trade execution report from client."""
    msg_type: int = MsgType.TRADE_REPORT
    timestamp_ms: int = 0
    client_id: str = ""
    symbol: str = ""
    strategy_id: str = ""       # "S01", "S15", etc.
    magic: int = 0
    order_type: int = 0         # 0=BUY, 1=SELL
    lots: float = 0.0
    open_price: float = 0.0
    close_price: float = 0.0
    profit: float = 0.0
    commission: float = 0.0
    swap: float = 0.0
    open_time_ms: int = 0
    close_time_ms: int = 0

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.client_id, self.symbol,
                self.strategy_id, self.magic, self.order_type, self.lots,
                self.open_price, self.close_price, self.profit,
                self.commission, self.swap, self.open_time_ms, self.close_time_ms]

    @classmethod
    def from_array(cls, arr: list) -> 'TradeReportMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], client_id=arr[2], symbol=arr[3],
            strategy_id=arr[4], magic=int(arr[5]), order_type=int(arr[6]),
            lots=float(arr[7]), open_price=float(arr[8]), close_price=float(arr[9]),
            profit=float(arr[10]), commission=float(arr[11]) if len(arr) > 11 else 0.0,
            swap=float(arr[12]) if len(arr) > 12 else 0.0,
            open_time_ms=int(arr[13]) if len(arr) > 13 else 0,
            close_time_ms=int(arr[14]) if len(arr) > 14 else 0
        )


@dataclass
class PositionUpdateMsg:
    """Type 21: Current position status from client."""
    msg_type: int = MsgType.POSITION_UPDATE
    timestamp_ms: int = 0
    client_id: str = ""
    symbol: str = ""
    strategy_id: str = ""
    magic: int = 0
    direction: int = 0          # 0=FLAT, 1=LONG, 2=SHORT
    lots: float = 0.0
    open_price: float = 0.0
    current_price: float = 0.0
    unrealized_pnl: float = 0.0
    sl: float = 0.0
    tp: float = 0.0

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.client_id, self.symbol,
                self.strategy_id, self.magic, self.direction, self.lots,
                self.open_price, self.current_price, self.unrealized_pnl,
                self.sl, self.tp]

    @classmethod
    def from_array(cls, arr: list) -> 'PositionUpdateMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], client_id=arr[2], symbol=arr[3],
            strategy_id=arr[4], magic=int(arr[5]), direction=int(arr[6]),
            lots=float(arr[7]), open_price=float(arr[8]),
            current_price=float(arr[9]), unrealized_pnl=float(arr[10]),
            sl=float(arr[11]) if len(arr) > 11 else 0.0,
            tp=float(arr[12]) if len(arr) > 12 else 0.0
        )


@dataclass
class PerformanceMetricsMsg:
    """Type 22: Performance stats from client."""
    msg_type: int = MsgType.PERFORMANCE_METRICS
    timestamp_ms: int = 0
    client_id: str = ""
    balance: float = 0.0
    equity: float = 0.0
    margin_level: float = 0.0
    total_trades: int = 0
    win_rate: float = 0.0
    daily_pnl: float = 0.0
    max_drawdown: float = 0.0

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.client_id,
                self.balance, self.equity, self.margin_level,
                self.total_trades, self.win_rate, self.daily_pnl, self.max_drawdown]

    @classmethod
    def from_array(cls, arr: list) -> 'PerformanceMetricsMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], client_id=arr[2],
            balance=float(arr[3]), equity=float(arr[4]),
            margin_level=float(arr[5]), total_trades=int(arr[6]),
            win_rate=float(arr[7]), daily_pnl=float(arr[8]),
            max_drawdown=float(arr[9]) if len(arr) > 9 else 0.0
        )


# ====================================================================
# Message Dataclasses — Server Notifications
# ====================================================================
@dataclass
class NewsAlertMsg:
    """Type 30: Economic calendar alert."""
    msg_type: int = MsgType.NEWS_ALERT
    timestamp_ms: int = 0
    event_name: str = ""
    currency: str = ""          # "USD", "EUR", etc.
    impact: int = 0             # 1=Low, 2=Medium, 3=High
    forecast: str = ""
    previous: str = ""
    event_time_ms: int = 0      # When the event occurs

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.event_name,
                self.currency, self.impact, self.forecast, self.previous,
                self.event_time_ms]

    @classmethod
    def from_array(cls, arr: list) -> 'NewsAlertMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], event_name=arr[2],
            currency=arr[3], impact=int(arr[4]),
            forecast=arr[5] if len(arr) > 5 else "",
            previous=arr[6] if len(arr) > 6 else "",
            event_time_ms=int(arr[7]) if len(arr) > 7 else 0
        )


@dataclass
class RegimeChangeMsg:
    """Type 31: Market regime shift notification."""
    msg_type: int = MsgType.REGIME_CHANGE
    timestamp_ms: int = 0
    old_regime: str = ""
    new_regime: str = ""
    confidence: float = 0.0
    method: str = ""            # "RULE", "RF_ML", "HMM"
    affected_symbols: List[str] = field(default_factory=list)

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.old_regime,
                self.new_regime, self.confidence, self.method,
                self.affected_symbols]

    @classmethod
    def from_array(cls, arr: list) -> 'RegimeChangeMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], old_regime=arr[2],
            new_regime=arr[3], confidence=float(arr[4]),
            method=arr[5] if len(arr) > 5 else "",
            affected_symbols=arr[6] if len(arr) > 6 else []
        )


@dataclass
class CommandMsg:
    """Type 40: Manual command from server to client."""
    msg_type: int = MsgType.COMMAND
    timestamp_ms: int = 0
    target_client: str = ""     # "" = broadcast to all
    command: str = ""           # "STOP", "START", "CLOSE_ALL", "SWITCH_STANDALONE"
    parameters: Dict[str, Any] = field(default_factory=dict)

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.target_client,
                self.command, self.parameters]

    @classmethod
    def from_array(cls, arr: list) -> 'CommandMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], target_client=arr[2],
            command=arr[3], parameters=arr[4] if len(arr) > 4 else {}
        )


@dataclass
class PolicyUpdateMsg:
    """Type 50: Security policy update."""
    msg_type: int = MsgType.POLICY_UPDATE
    timestamp_ms: int = 0
    policy_version: str = ""
    policy_data: Dict[str, Any] = field(default_factory=dict)
    signature: str = ""         # RSA signature for verification

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.policy_version,
                self.policy_data, self.signature]

    @classmethod
    def from_array(cls, arr: list) -> 'PolicyUpdateMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], policy_version=arr[2],
            policy_data=arr[3] if len(arr) > 3 else {},
            signature=arr[4] if len(arr) > 4 else ""
        )


@dataclass
class ErrorMsg:
    """Type 99: Error message."""
    msg_type: int = MsgType.ERROR
    timestamp_ms: int = 0
    source: str = ""
    error_code: int = 0
    error_message: str = ""

    def to_array(self) -> list:
        return [self.msg_type, self.timestamp_ms, self.source,
                self.error_code, self.error_message]

    @classmethod
    def from_array(cls, arr: list) -> 'ErrorMsg':
        return cls(
            msg_type=arr[0], timestamp_ms=arr[1], source=arr[2],
            error_code=int(arr[3]), error_message=arr[4]
        )


# ====================================================================
# Factory: Array → Typed Message
# ====================================================================
# Map MsgType → dataclass
MSG_CLASS_MAP = {
    MsgType.TICK_DATA:           TickDataMsg,
    MsgType.OHLC_DATA:           OHLCDataMsg,
    MsgType.INDICATOR_DATA:      IndicatorDataMsg,
    MsgType.CONFIG_PUSH:         ConfigPushMsg,
    MsgType.CLIENT_HELLO:        ClientHelloMsg,
    MsgType.INITIAL_CONFIG:      InitialConfigMsg,
    MsgType.HEARTBEAT:           HeartbeatMsg,
    MsgType.TRADE_REPORT:        TradeReportMsg,
    MsgType.POSITION_UPDATE:     PositionUpdateMsg,
    MsgType.PERFORMANCE_METRICS: PerformanceMetricsMsg,
    MsgType.NEWS_ALERT:          NewsAlertMsg,
    MsgType.REGIME_CHANGE:       RegimeChangeMsg,
    MsgType.COMMAND:             CommandMsg,
    MsgType.POLICY_UPDATE:       PolicyUpdateMsg,
    MsgType.ERROR:               ErrorMsg,
}


def parse_message(arr: list):
    """Parse MessagePack array into typed message object.

    Args:
        arr: Deserialized MessagePack array where arr[0] is the message type.

    Returns:
        Typed message dataclass instance, or None if unknown type.

    Note:
        CONFIG_PUSH (type 10) auto-detects V2 when arr has >= 8 elements.
        V1 arrays (6 elements) → ConfigPushMsg
        V2 arrays (8 elements) → ConfigPushV2
    """
    if not arr or len(arr) < 2:
        return None

    msg_type_id = int(arr[0])
    try:
        msg_type = MsgType(msg_type_id)
    except ValueError:
        return None

    # Auto-detect CONFIG_PUSH V2: array length >= 8 means V2 format
    if msg_type == MsgType.CONFIG_PUSH and len(arr) >= 8:
        return ConfigPushV2.from_array(arr)

    msg_class = MSG_CLASS_MAP.get(msg_type)
    if msg_class is None:
        return None

    return msg_class.from_array(arr)


def now_ms() -> int:
    """Current time in milliseconds since epoch."""
    return int(time.time() * 1000)


# ====================================================================
# Inline Tests — run: python message_types.py
# ====================================================================
if __name__ == "__main__":
    print("[TEST] message_types.py — V1 + V2 CONFIG_PUSH\n")

    # --- V1 (existing) ---
    v1 = ConfigPushMsg(regime="TRENDING", symbol_configs=[{"symbol": "XAUUSD"}])
    arr1 = v1.to_array()
    assert len(arr1) == 6
    v1b = ConfigPushMsg.from_array(arr1)
    assert v1b.regime == "TRENDING" and len(v1b.symbol_configs) == 1
    print("✅ T1: V1 ConfigPushMsg — create + round-trip")

    parsed1 = parse_message(arr1)
    assert isinstance(parsed1, ConfigPushMsg) and not isinstance(parsed1, ConfigPushV2)
    print("✅ T2: parse_message(V1 array 6 ช่อง) → ConfigPushMsg")

    # --- V2 (new) ---
    v2 = ConfigPushV2(
        regime="RANGING",
        symbol_configs=[{"symbol": "XAUUSD", "strategies": [
            {"id": "S01", "enabled": True, "confidence": 0.69,
             "parameters": {"S01_LOOKBACK": 25}, "mm_method": "MM04",
             "mm_parameters": {"MM04_KELLY": 0.4}}
        ]}],
        reasoning={"summary_th": "ปรับ test", "changes": [], "total_changes": 1},
        standalone_config={"enabled_strategies": ["S01", "S15"],
                           "default_mm": "MM01", "risk_multiplier": 0.5},
        optimization_cycle="OPT_20260217_000000_0001",
    )
    assert v2.is_v2 and v2.version == 2
    print("✅ T3: V2 ConfigPushV2 — create OK")

    arr2 = v2.to_array()
    assert len(arr2) == 8 and arr2[6] == 2 and arr2[7] == "OPT_20260217_000000_0001"
    print("✅ T4: V2 to_array() — 8 elements [6]=version [7]=cycle")

    v2b = ConfigPushV2.from_array(arr2)
    assert v2b.regime == "RANGING" and v2b.version == 2
    assert v2b.optimization_cycle == "OPT_20260217_000000_0001"
    assert v2b.symbol_configs[0]["strategies"][0]["parameters"]["S01_LOOKBACK"] == 25
    print("✅ T5: V2 from_array() — all fields preserved")

    parsed2 = parse_message(arr2)
    assert isinstance(parsed2, ConfigPushV2) and parsed2.is_v2
    print("✅ T6: parse_message(V2 array 8 ช่อง) → ConfigPushV2 auto-detect")

    # --- Backward compat: V1 client อ่าน V2 array ---
    v1_from_v2 = ConfigPushMsg.from_array(arr2)
    assert v1_from_v2.regime == "RANGING" and len(v1_from_v2.symbol_configs) == 1
    print("✅ T7: V1 client reads V2 array (index 0-5) — backward compat")

    # --- from_v1 converter ---
    v2c = ConfigPushV2.from_v1(v1)
    assert v2c.version == 1 and not v2c.is_v2 and v2c.regime == "TRENDING"
    print("✅ T8: ConfigPushV2.from_v1() — convert OK")

    # --- Other types ไม่กระทบ ---
    hello = ClientHelloMsg(client_id="TEST_001", broker="icmarkets")
    assert isinstance(parse_message(hello.to_array()), ClientHelloMsg)
    print("✅ T9: ClientHelloMsg unaffected")

    trade = TradeReportMsg(strategy_id="S01", symbol="XAUUSD", profit=10.0)
    assert isinstance(parse_message(trade.to_array()), TradeReportMsg)
    print("✅ T10: TradeReportMsg unaffected")

    assert MsgType.CONFIG_PUSH == 10 and MsgType.TRADE_REPORT == 20
    print("✅ T11: MsgType enum unchanged")

    assert now_ms() > 0
    print("✅ T12: now_ms() OK")

    print("\n" + "=" * 55)
    print("✅ ALL 12 TESTS PASSED — message_types.py V2 patch OK")
    print("=" * 55)
