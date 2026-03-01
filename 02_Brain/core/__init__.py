"""
FlashEASuite V2 V6 — Core Module
Protocol communication layer: 15 message types via ZMQ + MessagePack.
"""

from .message_types import (
    MsgType, PortConfig, MSG_DIRECTION, Direction,
    TickDataMsg, OHLCDataMsg, IndicatorDataMsg,
    ConfigPushMsg, ClientHelloMsg, InitialConfigMsg, HeartbeatMsg,
    TradeReportMsg, PositionUpdateMsg, PerformanceMetricsMsg,
    NewsAlertMsg, RegimeChangeMsg, CommandMsg, PolicyUpdateMsg, ErrorMsg,
    parse_message, now_ms, MSG_CLASS_MAP,
)
from .protocol_handler import ProtocolHandler
