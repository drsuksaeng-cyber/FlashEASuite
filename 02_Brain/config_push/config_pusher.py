"""
config_pusher.py
FlashEASuite V2 — P4-5: Config Pusher (ZMQ PUB)
================================================
ส่ง CONFIG_PUSH message ผ่าน ZMQ PUB port 7778

Methods:
    push_to_all(config_message)           → broadcast ให้ทุก client
    push_to_client(client_id, message)   → targeted (ใส่ client_id ใน topic)
    push_initial_config(client_id, ...)  → Type 12 INITIAL_CONFIG

ZMQ Pattern:
    Server: zmq.PUB bind tcp://*:7778
    Client: zmq.SUB connect tcp://127.0.0.1:7778
            subscribe to topic "" (all) หรือ topic "client_001"

Message Frame:
    [topic_bytes][separator b" "][packed_bytes]
    e.g. b"ALL " + msgpack_bytes
         b"client_001 " + msgpack_bytes

Save: 02_Brain/core/config_push/config_pusher.py
"""

import time
import logging
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Callable

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

ZMQ_PUB_PORT: int = 7778
TOPIC_ALL: str = "ALL"                  # broadcast topic
TOPIC_CLIENT_PREFIX: str = "CLIENT_"   # targeted topic prefix
SEND_TIMEOUT_MS: int = 100             # ZMQ send timeout
MAX_RETRY: int = 3                     # retry บน send failure
STATS_LOG_INTERVAL: int = 100          # log stats ทุก N messages


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class PushStats:
    """สถิติการส่ง messages"""
    total_sent: int = 0
    total_failed: int = 0
    total_bytes: int = 0
    broadcast_count: int = 0
    targeted_count: int = 0
    last_sent_at: float = 0.0

    @property
    def success_rate(self) -> float:
        total = self.total_sent + self.total_failed
        return self.total_sent / total if total > 0 else 1.0


@dataclass
class ClientInfo:
    """ข้อมูล client ที่ registered"""
    client_id: str
    connected_at: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)
    messages_received: int = 0


# ─────────────────────────────────────────────
# ConfigPusher
# ─────────────────────────────────────────────

class ConfigPusher:
    """
    ส่ง CONFIG_PUSH และ INITIAL_CONFIG ผ่าน ZMQ PUB

    Architecture:
        ConfigPusher → ZMQ PUB (port 7778)
            ↓ broadcast topic "ALL"
        Trader Client 1 (zmq.SUB subscribe "ALL")
        Trader Client 2 (zmq.SUB subscribe "ALL")
        ...
        Trader Client N (zmq.SUB subscribe "ALL" + "CLIENT_clientN")

    Usage:
        pusher = ConfigPusher()
        pusher.start()
        pusher.push_to_all(packed_bytes)
        pusher.stop()

    หรือใช้ context manager:
        with ConfigPusher() as pusher:
            pusher.push_to_all(packed_bytes)
    """

    def __init__(
        self,
        port: int = ZMQ_PUB_PORT,
        bind_address: str = "tcp://*",
    ):
        self._port = port
        self._bind_addr = f"{bind_address}:{port}"
        self._socket = None
        self._context = None
        self._lock = threading.Lock()
        self._running = False
        self._stats = PushStats()
        self._clients: dict[str, ClientInfo] = {}
        self._zmq_available = False

        # ตรวจสอบว่า zmq ติดตั้งแล้ว
        try:
            import zmq  # noqa: F401
            self._zmq_available = True
        except ImportError:
            logger.warning(
                "[Pusher] pyzmq ไม่พร้อม — ทำงานใน simulation mode "
                "(ติดตั้งด้วย: pip install pyzmq)"
            )

    # ─────────────────────────────────────────
    # Lifecycle
    # ─────────────────────────────────────────

    def start(self) -> bool:
        """
        เริ่ม ZMQ PUB socket

        Returns:
            True ถ้าสำเร็จ, False ถ้า zmq ไม่พร้อม
        """
        if not self._zmq_available:
            logger.warning("[Pusher] Running in simulation mode (no ZMQ)")
            self._running = True
            return False

        try:
            import zmq
            self._context = zmq.Context()
            self._socket = self._context.socket(zmq.PUB)
            self._socket.setsockopt(zmq.SNDTIMEO, SEND_TIMEOUT_MS)
            self._socket.bind(self._bind_addr)
            self._running = True
            logger.info(f"[Pusher] ZMQ PUB bound to {self._bind_addr}")
            # Warm-up: ให้ subscribers มีเวลา connect ก่อนส่ง message แรก
            time.sleep(0.1)
            return True
        except Exception as e:
            logger.error(f"[Pusher] Failed to start ZMQ: {e}")
            return False

    def stop(self) -> None:
        """ปิด ZMQ socket"""
        self._running = False
        if self._socket:
            try:
                self._socket.close()
            except Exception:
                pass
            self._socket = None
        if self._context:
            try:
                self._context.term()
            except Exception:
                pass
            self._context = None
        logger.info(
            f"[Pusher] Stopped | stats: sent={self._stats.total_sent} "
            f"failed={self._stats.total_failed} "
            f"bytes={self._stats.total_bytes:,}"
        )

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *args):
        self.stop()

    # ─────────────────────────────────────────
    # Send methods
    # ─────────────────────────────────────────

    def push_to_all(self, packed_message: bytes) -> bool:
        """
        Broadcast CONFIG_PUSH ให้ทุก client ที่ subscribe topic "ALL"

        Args:
            packed_message: MessagePack bytes จาก ConfigBuilder.pack()

        Returns:
            True ถ้าส่งสำเร็จ
        """
        topic = TOPIC_ALL.encode("utf-8")
        success = self._send(topic, packed_message)

        if success:
            self._stats.broadcast_count += 1

        logger.debug(
            f"[Pusher] push_to_all: {len(packed_message)} bytes "
            f"{'✅' if success else '❌'}"
        )
        return success

    def push_to_client(
        self,
        client_id: str,
        packed_message: bytes,
    ) -> bool:
        """
        ส่ง CONFIG_PUSH ถึง client เฉพาะ (targeted)
        Client ต้อง subscribe topic "CLIENT_{client_id}"

        Args:
            client_id:      client identifier
            packed_message: MessagePack bytes

        Returns:
            True ถ้าส่งสำเร็จ
        """
        topic = f"{TOPIC_CLIENT_PREFIX}{client_id}".encode("utf-8")
        success = self._send(topic, packed_message)

        if success:
            self._stats.targeted_count += 1
            if client_id in self._clients:
                self._clients[client_id].messages_received += 1

        logger.debug(
            f"[Pusher] push_to_client({client_id}): "
            f"{len(packed_message)} bytes {'✅' if success else '❌'}"
        )
        return success

    def push_initial_config(
        self,
        client_id: str,
        initial_config_dict: dict,
        builder=None,
    ) -> bool:
        """
        ส่ง INITIAL_CONFIG (Type 12) ให้ client ใหม่

        Args:
            client_id:           client identifier
            initial_config_dict: dict จาก ConfigBuilder.build_initial_config()
            builder:             ConfigBuilder instance (สำหรับ pack)

        Returns:
            True ถ้าส่งสำเร็จ
        """
        # Pack the initial config
        if builder is not None:
            packed = builder.pack_dict(initial_config_dict)
        else:
            try:
                import msgpack
                packed = msgpack.packb(initial_config_dict, use_bin_type=True)
            except ImportError:
                import json
                packed = json.dumps(initial_config_dict).encode("utf-8")

        # Register client
        with self._lock:
            if client_id not in self._clients:
                self._clients[client_id] = ClientInfo(client_id=client_id)
            self._clients[client_id].last_seen = time.time()

        success = self.push_to_client(client_id, packed)

        logger.info(
            f"[Pusher] push_initial_config → {client_id}: "
            f"{len(packed)} bytes {'✅' if success else '❌'}"
        )
        return success

    def push_regime_change(
        self,
        new_regime: str,
        old_regime: str,
        packed_config: Optional[bytes] = None,
    ) -> bool:
        """
        Broadcast regime change notification (Type 31)
        ถ้ามี packed_config → ส่งพร้อม config ใหม่
        """
        import msgpack as mp

        msg = {
            "type": 31,  # REGIME_CHANGE
            "new_regime": new_regime,
            "old_regime": old_regime,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        try:
            packed = mp.packb(msg, use_bin_type=True)
        except Exception:
            import json
            packed = json.dumps(msg).encode("utf-8")

        logger.info(
            f"[Pusher] Regime change: {old_regime} → {new_regime}"
        )
        success = self.push_to_all(packed)

        # ถ้ามี new config → broadcast ตามมาทันที
        if packed_config and success:
            success = self.push_to_all(packed_config)

        return success

    # ─────────────────────────────────────────
    # Client management
    # ─────────────────────────────────────────

    def register_client(self, client_id: str) -> None:
        """บันทึก client ที่ connect ใหม่"""
        with self._lock:
            if client_id not in self._clients:
                self._clients[client_id] = ClientInfo(client_id=client_id)
                logger.info(f"[Pusher] New client registered: {client_id}")
            else:
                self._clients[client_id].last_seen = time.time()

    def get_client_count(self) -> int:
        """จำนวน client ที่ registered"""
        return len(self._clients)

    def get_stats(self) -> dict:
        """สถิติการส่ง"""
        return {
            "total_sent": self._stats.total_sent,
            "total_failed": self._stats.total_failed,
            "total_bytes": self._stats.total_bytes,
            "broadcast_count": self._stats.broadcast_count,
            "targeted_count": self._stats.targeted_count,
            "success_rate": round(self._stats.success_rate, 4),
            "clients": self.get_client_count(),
            "zmq_available": self._zmq_available,
            "running": self._running,
        }

    # ─────────────────────────────────────────
    # Internal
    # ─────────────────────────────────────────

    def _send(self, topic: bytes, data: bytes) -> bool:
        """
        ส่ง frame [topic][space][data] ผ่าน ZMQ PUB

        ถ้า ZMQ ไม่พร้อม → simulation mode (log only)
        """
        frame = topic + b" " + data

        if not self._zmq_available or self._socket is None:
            # Simulation mode — ไม่มี ZMQ จริง
            with self._lock:
                self._stats.total_sent += 1
                self._stats.total_bytes += len(frame)
                self._stats.last_sent_at = time.time()
            return True

        for attempt in range(MAX_RETRY):
            try:
                with self._lock:
                    self._socket.send(frame, flags=0)
                with self._lock:
                    self._stats.total_sent += 1
                    self._stats.total_bytes += len(frame)
                    self._stats.last_sent_at = time.time()

                # Log stats ทุก N messages
                if self._stats.total_sent % STATS_LOG_INTERVAL == 0:
                    logger.info(
                        f"[Pusher] Stats: sent={self._stats.total_sent} "
                        f"bytes={self._stats.total_bytes:,} "
                        f"rate={self._stats.success_rate:.1%}"
                    )
                return True
            except Exception as e:
                if attempt < MAX_RETRY - 1:
                    logger.warning(
                        f"[Pusher] Send attempt {attempt+1}/{MAX_RETRY} failed: {e}"
                    )
                    time.sleep(0.01)
                else:
                    logger.error(f"[Pusher] Send failed after {MAX_RETRY} attempts: {e}")
                    with self._lock:
                        self._stats.total_failed += 1
                    return False

        return False


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    import os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )

    print("=" * 60)
    print("FlashEASuite V2 — Config Pusher Test")
    print("=" * 60)

    # Import ConfigBuilder (sibling module)
    try:
        from config_builder import (
            ConfigBuilder, SymbolConfig, StrategyConfig, StandaloneConfig
        )
        HAS_BUILDER = True
    except ImportError:
        HAS_BUILDER = False
        print("  (config_builder ไม่พร้อม — test limited)")

    # ── Test 1: Pusher ใน simulation mode ─────────────────────────────
    print("\n── Test 1: Simulation mode (no ZMQ) ──")
    pusher = ConfigPusher(port=7778)
    pusher.start()

    print(f"  ZMQ available: {pusher._zmq_available}")
    print(f"  Running: {pusher._running}")

    # ── Test 2: push_to_all ───────────────────────────────────────────
    print("\n── Test 2: push_to_all ──")
    try:
        import msgpack
        mock_data = msgpack.packb(
            {"type": 10, "regime": "RANGING", "test": True},
            use_bin_type=True,
        )
    except ImportError:
        mock_data = b'{"type":10,"regime":"RANGING"}'

    for i in range(5):
        ok = pusher.push_to_all(mock_data)
        assert ok, f"push_to_all failed iteration {i}"

    stats = pusher.get_stats()
    assert stats["total_sent"] == 5
    assert stats["broadcast_count"] == 5
    print(f"  Sent: {stats['total_sent']} | bytes: {stats['total_bytes']}")
    print("  push_to_all: ✅")

    # ── Test 3: push_to_client ────────────────────────────────────────
    print("\n── Test 3: push_to_client (targeted) ──")
    pusher.register_client("client_001")
    pusher.register_client("client_002")

    ok1 = pusher.push_to_client("client_001", mock_data)
    ok2 = pusher.push_to_client("client_002", mock_data)
    assert ok1 and ok2

    stats = pusher.get_stats()
    assert stats["targeted_count"] == 2
    assert stats["clients"] == 2
    print(f"  Targeted: {stats['targeted_count']} | clients: {stats['clients']}")
    print("  push_to_client: ✅")

    # ── Test 4: push_initial_config ───────────────────────────────────
    print("\n── Test 4: push_initial_config (Type 12) ──")
    if HAS_BUILDER:
        builder = ConfigBuilder()
        sym_cfg = SymbolConfig(
            "XAUUSD",
            [StrategyConfig(15, True, 0.75, {}, "MM03", {})],
        )
        initial = builder.build_initial_config("client_003", [sym_cfg], "RANGING")
        ok = pusher.push_initial_config("client_003", initial, builder)
        assert ok
        assert pusher.get_client_count() == 3
        print(f"  Initial config sent: ✅ | clients={pusher.get_client_count()}")
    else:
        initial_dict = {"type": 12, "client_id": "client_003", "is_initial": True}
        ok = pusher.push_initial_config("client_003", initial_dict)
        print(f"  Initial config (mock): {'✅' if ok else '❌'}")

    # ── Test 5: push_regime_change ────────────────────────────────────
    print("\n── Test 5: push_regime_change ──")
    ok = pusher.push_regime_change("TRENDING", "RANGING")
    assert ok
    print(f"  Regime change broadcast: ✅")

    # ── Test 6: Final stats ───────────────────────────────────────────
    print("\n── Test 6: Final stats ──")
    final = pusher.get_stats()
    for k, v in final.items():
        print(f"  {k}: {v}")

    pusher.stop()
    print("\n✅ All tests passed!")
