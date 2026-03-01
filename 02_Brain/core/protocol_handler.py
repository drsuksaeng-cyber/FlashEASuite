#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 V6 — Protocol Handler
ZMQ + MessagePack communication layer for the Python Brain (Server).

Manages 3 ZMQ sockets:
  - PULL on port 7777: Receive from Feeder (TICK, OHLC, INDICATOR data)
  - PUB  on port 7778: Broadcast to Clients (CONFIG_PUSH, HEARTBEAT, etc.)
  - PULL on port 7779: Receive from Clients (CLIENT_HELLO, TRADE_REPORT, etc.)

Author: Dr. Suksaeng Kukanok
Version: 6.0.0
Date: 2026-02-13
"""

import zmq
import msgpack
import time
import logging
from typing import Optional, Any

try:
    from .message_types import (
        MsgType, PortConfig, now_ms, parse_message,
        ConfigPushMsg, ConfigPushV2, InitialConfigMsg, HeartbeatMsg,
        NewsAlertMsg, RegimeChangeMsg, CommandMsg, PolicyUpdateMsg, ErrorMsg,
        TickDataMsg, OHLCDataMsg, IndicatorDataMsg,
        ClientHelloMsg, TradeReportMsg, PositionUpdateMsg, PerformanceMetricsMsg,
    )
except ImportError:
    from message_types import (
        MsgType, PortConfig, now_ms, parse_message,
        ConfigPushMsg, ConfigPushV2, InitialConfigMsg, HeartbeatMsg,
        NewsAlertMsg, RegimeChangeMsg, CommandMsg, PolicyUpdateMsg, ErrorMsg,
        TickDataMsg, OHLCDataMsg, IndicatorDataMsg,
        ClientHelloMsg, TradeReportMsg, PositionUpdateMsg, PerformanceMetricsMsg,
    )

logger = logging.getLogger("FlashEA.Protocol")


class ProtocolHandler:
    """
    ZMQ + MessagePack protocol handler for the Brain (Server).

    Architecture:
        Feeder → [PUSH] ──→ [PULL port 7777] Server
        Server  [PUB  port 7778] ──→ [SUB] Clients
        Clients → [PUSH] ──→ [PULL port 7779] Server
    """

    def __init__(self,
                 feeder_pull_addr: str = "tcp://127.0.0.1:7777",
                 pub_addr: str = "tcp://*:7778",
                 client_pull_addr: str = "tcp://127.0.0.1:7779",
                 bind_feeder: bool = True,
                 bind_pub: bool = True,
                 bind_client: bool = True):
        """
        Initialize ZMQ context and sockets.

        Args:
            feeder_pull_addr: Address for PULL socket receiving from Feeder.
            pub_addr: Address for PUB socket broadcasting to Clients.
            client_pull_addr: Address for PULL socket receiving from Clients.
            bind_feeder: True = bind (server side), False = connect (client side).
            bind_pub: True = bind PUB socket.
            bind_client: True = bind PULL socket for client messages.
        """
        self._feeder_pull_addr = feeder_pull_addr
        self._pub_addr = pub_addr
        self._client_pull_addr = client_pull_addr
        self._bind_feeder = bind_feeder
        self._bind_pub = bind_pub
        self._bind_client = bind_client

        self._context: Optional[zmq.Context] = None
        self._feeder_pull: Optional[zmq.Socket] = None  # PULL from Feeder
        self._pub: Optional[zmq.Socket] = None           # PUB to Clients
        self._client_pull: Optional[zmq.Socket] = None   # PULL from Clients
        self._initialized = False

        # Stats
        self._sent_count = 0
        self._recv_count = 0

    # ==================================================================
    # Lifecycle
    # ==================================================================
    def initialize(self) -> bool:
        """Initialize ZMQ context and all sockets. Returns True on success."""
        try:
            self._context = zmq.Context()

            # --- Socket 1: PULL from Feeder (port 7777) ---
            self._feeder_pull = self._context.socket(zmq.PULL)
            self._feeder_pull.setsockopt(zmq.LINGER, 0)
            self._feeder_pull.setsockopt(zmq.RCVTIMEO, 100)  # 100ms timeout
            if self._bind_feeder:
                self._feeder_pull.bind(self._feeder_pull_addr)
                logger.info(f"PULL (Feeder) bound to {self._feeder_pull_addr}")
            else:
                self._feeder_pull.connect(self._feeder_pull_addr)
                logger.info(f"PULL (Feeder) connected to {self._feeder_pull_addr}")

            # --- Socket 2: PUB to Clients (port 7778) ---
            self._pub = self._context.socket(zmq.PUB)
            self._pub.setsockopt(zmq.LINGER, 0)
            self._pub.setsockopt(zmq.SNDHWM, 1000)
            if self._bind_pub:
                self._pub.bind(self._pub_addr)
                logger.info(f"PUB bound to {self._pub_addr}")
            else:
                self._pub.connect(self._pub_addr)
                logger.info(f"PUB connected to {self._pub_addr}")

            # --- Socket 3: PULL from Clients (port 7779) ---
            self._client_pull = self._context.socket(zmq.PULL)
            self._client_pull.setsockopt(zmq.LINGER, 0)
            self._client_pull.setsockopt(zmq.RCVTIMEO, 100)  # 100ms timeout
            if self._bind_client:
                self._client_pull.bind(self._client_pull_addr)
                logger.info(f"PULL (Client) bound to {self._client_pull_addr}")
            else:
                self._client_pull.connect(self._client_pull_addr)
                logger.info(f"PULL (Client) connected to {self._client_pull_addr}")

            self._initialized = True
            logger.info("✅ ProtocolHandler initialized (3 sockets ready)")
            return True

        except zmq.ZMQError as e:
            logger.error(f"❌ ZMQ initialization failed: {e}")
            self.shutdown()
            return False

    def shutdown(self) -> None:
        """Close all sockets and terminate context."""
        for name, sock in [("feeder_pull", self._feeder_pull),
                           ("pub", self._pub),
                           ("client_pull", self._client_pull)]:
            if sock is not None:
                try:
                    sock.close()
                    logger.info(f"Socket {name} closed")
                except Exception:
                    pass

        if self._context is not None:
            try:
                self._context.term()
            except Exception:
                pass

        self._feeder_pull = None
        self._pub = None
        self._client_pull = None
        self._context = None
        self._initialized = False
        logger.info("ProtocolHandler shutdown complete")

    @property
    def is_initialized(self) -> bool:
        return self._initialized

    # ==================================================================
    # Low-level Send / Receive
    # ==================================================================
    def _send_pub(self, data: list) -> bool:
        """Serialize and send data via PUB socket."""
        if self._pub is None:
            return False
        try:
            packed = msgpack.packb(data, use_bin_type=True)
            self._pub.send(packed, zmq.NOBLOCK)
            self._sent_count += 1
            return True
        except zmq.ZMQError as e:
            logger.warning(f"PUB send failed: {e}")
            return False

    def _recv_from(self, socket: zmq.Socket) -> Optional[list]:
        """Receive and deserialize data from a PULL socket."""
        if socket is None:
            return None
        try:
            raw = socket.recv(zmq.NOBLOCK)
            data = msgpack.unpackb(raw, raw=False)
            self._recv_count += 1
            return data
        except zmq.Again:
            return None  # No message available (timeout)
        except (msgpack.UnpackException, Exception) as e:
            logger.warning(f"Receive/unpack error: {e}")
            return None

    # ==================================================================
    # Receive Methods — from Feeder (port 7777)
    # ==================================================================
    def receive_from_feeder(self):
        """
        Poll Feeder PULL socket for incoming data.
        Returns typed message object or None.
        """
        arr = self._recv_from(self._feeder_pull)
        if arr is None:
            return None
        return parse_message(arr)

    # ==================================================================
    # Receive Methods — from Clients (port 7779)
    # ==================================================================
    def receive_from_client(self):
        """
        Poll Client PULL socket for incoming data.
        Returns typed message object or None.
        """
        arr = self._recv_from(self._client_pull)
        if arr is None:
            return None
        return parse_message(arr)

    # ==================================================================
    # Send Methods — Server → Clients (port 7778 PUB)
    # ==================================================================
    def send_config_push(self, msg: ConfigPushMsg) -> bool:
        """Send CONFIG_PUSH (type 10) V1 to all clients."""
        msg.timestamp_ms = now_ms()
        return self._send_pub(msg.to_array())

    def send_config_push_v2(self, config: ConfigPushV2) -> bool:
        """Send CONFIG_PUSH V2 (type 10) to all clients.

        V2 array has 8 elements — V1 clients parse index 0-5 normally,
        index 6-7 (version, optimization_cycle) are ignored by old clients.
        """
        config.timestamp_ms = now_ms()
        return self._send_pub(config.to_array())

    def send_config_push_v2_raw(self, config_push_dict: dict) -> bool:
        """Send CONFIG_PUSH V2 from raw dict (output of ConfigPushGenerator).

        Convenience method — converts dict → array and sends via PUB.

        Args:
            config_push_dict: Dict from ConfigPushGenerator.generate()
        """
        arr = [
            config_push_dict.get("type", 10),
            now_ms(),
            config_push_dict.get("regime", "UNKNOWN"),
            config_push_dict.get("symbol_configs", []),
            config_push_dict.get("reasoning", {}),
            config_push_dict.get("standalone_config", {}),
            config_push_dict.get("version", 2),
            config_push_dict.get("optimization_cycle", ""),
        ]
        return self._send_pub(arr)

    def send_initial_config(self, msg: InitialConfigMsg) -> bool:
        """Send INITIAL_CONFIG (type 12) to a specific client."""
        msg.timestamp_ms = now_ms()
        return self._send_pub(msg.to_array())

    def send_heartbeat(self, sequence: int = 0) -> bool:
        """Send HEARTBEAT (type 13) from server."""
        msg = HeartbeatMsg(
            timestamp_ms=now_ms(),
            source="SERVER",
            sequence=sequence,
            is_alive=True
        )
        return self._send_pub(msg.to_array())

    def send_news_alert(self, msg: NewsAlertMsg) -> bool:
        """Send NEWS_ALERT (type 30) to all clients."""
        msg.timestamp_ms = now_ms()
        return self._send_pub(msg.to_array())

    def send_regime_change(self, msg: RegimeChangeMsg) -> bool:
        """Send REGIME_CHANGE (type 31) to all clients."""
        msg.timestamp_ms = now_ms()
        return self._send_pub(msg.to_array())

    def send_command(self, msg: CommandMsg) -> bool:
        """Send COMMAND (type 40) to specific client or broadcast."""
        msg.timestamp_ms = now_ms()
        return self._send_pub(msg.to_array())

    def send_policy_update(self, msg: PolicyUpdateMsg) -> bool:
        """Send POLICY_UPDATE (type 50) to all clients."""
        msg.timestamp_ms = now_ms()
        return self._send_pub(msg.to_array())

    def send_error(self, source: str, error_code: int, error_message: str) -> bool:
        """Send ERROR (type 99)."""
        msg = ErrorMsg(
            timestamp_ms=now_ms(),
            source=source,
            error_code=error_code,
            error_message=error_message
        )
        return self._send_pub(msg.to_array())

    # ==================================================================
    # Utility
    # ==================================================================
    def get_stats(self) -> dict:
        """Return send/receive statistics."""
        return {
            "sent": self._sent_count,
            "received": self._recv_count,
            "initialized": self._initialized,
        }

    def __enter__(self):
        self.initialize()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.shutdown()


# ====================================================================
# Inline Tests — run: python protocol_handler.py
# ====================================================================
if __name__ == "__main__":
    print("[TEST] protocol_handler.py — V2 methods\n")

    # Use a mock _send_pub to test without real ZMQ
    handler = ProtocolHandler.__new__(ProtocolHandler)
    handler._pub = None
    handler._feeder_pull = None
    handler._client_pull = None
    handler._context = None
    handler._initialized = False
    handler._sent_count = 0
    handler._recv_count = 0

    # Capture what _send_pub receives
    _captured = []
    def mock_send_pub(data: list) -> bool:
        _captured.append(data)
        handler._sent_count += 1
        return True
    handler._send_pub = mock_send_pub

    # T1: send_config_push (V1 — existing, ไม่พัง)
    v1 = ConfigPushMsg(regime="TRENDING", symbol_configs=[{"symbol": "XAUUSD"}])
    result = handler.send_config_push(v1)
    assert result is True
    assert _captured[-1][0] == 10  # msg_type
    assert _captured[-1][2] == "TRENDING"  # regime
    assert len(_captured[-1]) == 6  # V1 = 6 elements
    print("✅ T1: send_config_push(V1) — 6 elements, type=10")

    # T2: send_config_push_v2 (V2 dataclass)
    v2 = ConfigPushV2(
        regime="RANGING",
        symbol_configs=[{"symbol": "XAUUSD", "strategies": [
            {"id": "S01", "enabled": True, "confidence": 0.75,
             "parameters": {"S01_LOOKBACK": 25},
             "mm_method": "MM04", "mm_parameters": {"MM04_KELLY": 0.4}}
        ]}],
        reasoning={"summary_th": "ปรับ LOOKBACK", "changes": []},
        standalone_config={"enabled_strategies": ["S01"], "default_mm": "MM01"},
        optimization_cycle="OPT_20260217_001",
    )
    result = handler.send_config_push_v2(v2)
    assert result is True
    arr = _captured[-1]
    assert arr[0] == 10 and arr[2] == "RANGING"
    assert len(arr) == 8  # V2 = 8 elements
    assert arr[6] == 2  # version
    assert arr[7] == "OPT_20260217_001"  # cycle
    print("✅ T2: send_config_push_v2(V2) — 8 elements, version=2, cycle=OPT_...")

    # T3: send_config_push_v2_raw (dict from ConfigPushGenerator)
    raw_dict = {
        "type": 10, "version": 2, "regime": "VOLATILE",
        "symbol_configs": [{"symbol": "GBPJPY"}],
        "reasoning": {"summary_th": "test raw"},
        "standalone_config": {"default_mm": "MM01"},
        "optimization_cycle": "OPT_RAW_001",
    }
    result = handler.send_config_push_v2_raw(raw_dict)
    assert result is True
    arr = _captured[-1]
    assert arr[0] == 10 and arr[2] == "VOLATILE"
    assert len(arr) == 8
    assert arr[6] == 2 and arr[7] == "OPT_RAW_001"
    print("✅ T3: send_config_push_v2_raw(dict) — converts dict → array OK")

    # T4: V1 backward compat — V1 client can read V2 array
    v2_arr = _captured[1]  # from T2
    v1_parsed = ConfigPushMsg.from_array(v2_arr)
    assert v1_parsed.regime == "RANGING"
    assert len(v1_parsed.symbol_configs) == 1
    print("✅ T4: V1 client reads V2 array (index 0-5) — backward compat")

    # T5: V2 parse_message auto-detect
    parsed = parse_message(_captured[1])
    assert isinstance(parsed, ConfigPushV2)
    assert parsed.is_v2 and parsed.optimization_cycle == "OPT_20260217_001"
    print("✅ T5: parse_message(V2 array) → ConfigPushV2 auto-detect")

    # T6: Stats tracking
    assert handler._sent_count == 3
    print(f"✅ T6: Stats — sent_count={handler._sent_count}")

    # T7: send_config_push_v2_raw with missing fields → defaults
    minimal = {"regime": "CRISIS"}
    handler.send_config_push_v2_raw(minimal)
    arr = _captured[-1]
    assert arr[0] == 10 and arr[2] == "CRISIS"
    assert arr[6] == 2  # default version
    assert arr[7] == ""  # default empty cycle
    print("✅ T7: Minimal dict → defaults applied (version=2, cycle='')")

    # T8: Original V1 methods still exist and work
    assert hasattr(handler, 'send_config_push')
    assert hasattr(handler, 'send_config_push_v2')
    assert hasattr(handler, 'send_config_push_v2_raw')
    assert hasattr(handler, 'send_heartbeat')
    assert hasattr(handler, 'send_regime_change')
    print("✅ T8: All methods exist (V1 + V2 + raw + heartbeat + regime)")

    print("\n" + "=" * 58)
    print("✅ ALL 8 TESTS PASSED — protocol_handler.py V2 patch OK")
    print("=" * 58)
