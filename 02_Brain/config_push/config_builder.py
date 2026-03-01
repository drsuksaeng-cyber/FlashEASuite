"""
config_builder.py
FlashEASuite V2 — P4-5: Config Push Builder
============================================
สร้าง CONFIG_PUSH message (Type 10) สมบูรณ์พร้อม MessagePack encoding

Config structure (V2 format จาก P0.6-6):
{
  "type": 10,
  "timestamp": "...",
  "optimization_cycle": "weekly_2026-02-22",
  "regime": "RANGING",
  "symbol_configs": [
    {
      "symbol": "XAUUSD",
      "strategies": [
        {
          "id": 15,
          "enabled": true,
          "confidence": 0.78,
          "parameters": {"S15_GRID_STEP": 15.0, ...},
          "mm_method": "MM03",
          "mm_parameters": {"MM03_ATR_MULT": 1.5, ...}
        }
      ],
      "mm_overrides": {"dd_current": 5.2, "regime_mm_active": false}
    }
  ],
  "reasoning": {
    "summary_th": "...",
    "summary_en": "...",
    "changes": [...]
  },
  "standalone_config": {
    "enabled_strategies": [15, 6, 1],
    "default_mm": "MM01",
    "risk_multiplier": 1.0,
    "regime_hint": "RANGING"
  }
}

Save: 02_Brain/core/config_push/config_builder.py
"""

import logging
import msgpack
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Any

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Message Type Constants
# ─────────────────────────────────────────────

MSG_CONFIG_PUSH    = 10
MSG_INITIAL_CONFIG = 12

PROTOCOL_VERSION   = "2.0"


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class StrategyConfig:
    """Configuration สำหรับ 1 strategy ใน symbol"""
    strategy_id: int
    enabled: bool
    confidence: float
    parameters: dict[str, Any] = field(default_factory=dict)     # dynamic params
    mm_method: str = "MM01"
    mm_parameters: dict[str, Any] = field(default_factory=dict)  # MM params
    reasoning: str = ""

    def to_dict(self) -> dict:
        return {
            "id": self.strategy_id,
            "enabled": self.enabled,
            "confidence": round(self.confidence, 4),
            "parameters": self.parameters,
            "mm_method": self.mm_method,
            "mm_parameters": self.mm_parameters,
            "reasoning": self.reasoning,
        }


@dataclass
class SymbolConfig:
    """Configuration สำหรับ 1 symbol"""
    symbol: str
    strategies: list[StrategyConfig] = field(default_factory=list)
    mm_overrides: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "symbol": self.symbol,
            "strategies": [s.to_dict() for s in self.strategies],
            "mm_overrides": self.mm_overrides,
        }


@dataclass
class StandaloneConfig:
    """
    Config สำหรับ client ที่ทำงาน standalone (ไม่มี server)
    Client จะ save ไว้ใช้เมื่อ server disconnect
    """
    enabled_strategies: list[int] = field(default_factory=list)
    default_mm: str = "MM01"
    risk_multiplier: float = 1.0
    regime_hint: str = "UNKNOWN"
    updated_at: str = ""

    def to_dict(self) -> dict:
        return {
            "enabled_strategies": self.enabled_strategies,
            "default_mm": self.default_mm,
            "risk_multiplier": round(self.risk_multiplier, 4),
            "regime_hint": self.regime_hint,
            "updated_at": self.updated_at or datetime.now(timezone.utc).isoformat(),
        }


@dataclass
class ConfigPushMessage:
    """Full CONFIG_PUSH message (Type 10)"""
    type: int = MSG_CONFIG_PUSH
    version: str = PROTOCOL_VERSION
    timestamp: str = ""
    optimization_cycle: str = ""
    regime: str = "UNKNOWN"
    symbol_configs: list[SymbolConfig] = field(default_factory=list)
    reasoning: dict = field(default_factory=dict)
    standalone_config: Optional[StandaloneConfig] = None

    def to_dict(self) -> dict:
        return {
            "type": self.type,
            "version": self.version,
            "timestamp": self.timestamp or datetime.now(timezone.utc).isoformat(),
            "optimization_cycle": self.optimization_cycle,
            "regime": self.regime,
            "symbol_configs": [sc.to_dict() for sc in self.symbol_configs],
            "reasoning": self.reasoning,
            "standalone_config": self.standalone_config.to_dict() if self.standalone_config else {},
        }


# ─────────────────────────────────────────────
# ConfigBuilder
# ─────────────────────────────────────────────

class ConfigBuilder:
    """
    สร้าง CONFIG_PUSH message พร้อม MessagePack encoding

    Key method:
        build_config_push(symbol_configs, regime, reasoning, standalone_config)
            → ConfigPushMessage

        pack(message) → bytes (MessagePack encoded)
        build_and_pack(...) → bytes (shortcut)
    """

    def build_config_push(
        self,
        symbol_configs: list[SymbolConfig],
        regime: str = "UNKNOWN",
        reasoning: Optional[dict] = None,
        standalone_config: Optional[StandaloneConfig] = None,
        optimization_cycle: Optional[str] = None,
    ) -> ConfigPushMessage:
        """
        สร้าง CONFIG_PUSH message สมบูรณ์

        Args:
            symbol_configs:      list ของ SymbolConfig (1 ต่อ symbol)
            regime:              current market regime string
            reasoning:           dict พร้อม summary_th, summary_en, changes
            standalone_config:   config สำหรับ client ใช้ตอน standalone
            optimization_cycle:  label เช่น "weekly_2026-02-22"

        Returns:
            ConfigPushMessage
        """
        now = datetime.now(timezone.utc)
        cycle = optimization_cycle or f"cycle_{now.strftime('%Y%m%d_%H%M')}"

        # Default reasoning ถ้าไม่ส่งมา
        if reasoning is None:
            active_strategies = set()
            for sc in symbol_configs:
                for s in sc.strategies:
                    if s.enabled:
                        active_strategies.add(s.strategy_id)
            reasoning = {
                "summary_th": (
                    f"AI Council เลือก {len(active_strategies)} strategies "
                    f"สำหรับ {len(symbol_configs)} symbols | Regime: {regime}"
                ),
                "summary_en": (
                    f"AI Council selected {len(active_strategies)} strategies "
                    f"for {len(symbol_configs)} symbols | Regime: {regime}"
                ),
                "changes": [],
            }

        # สร้าง standalone config อัตโนมัติถ้าไม่ได้ส่งมา
        if standalone_config is None:
            enabled = []
            for sc in symbol_configs:
                for s in sc.strategies:
                    if s.enabled and s.strategy_id not in enabled:
                        enabled.append(s.strategy_id)
            standalone_config = StandaloneConfig(
                enabled_strategies=enabled,
                default_mm="MM01",
                risk_multiplier=1.0,
                regime_hint=regime,
            )

        msg = ConfigPushMessage(
            type=MSG_CONFIG_PUSH,
            version=PROTOCOL_VERSION,
            timestamp=now.isoformat(),
            optimization_cycle=cycle,
            regime=regime,
            symbol_configs=symbol_configs,
            reasoning=reasoning,
            standalone_config=standalone_config,
        )

        total_strategies = sum(
            sum(1 for s in sc.strategies if s.enabled)
            for sc in symbol_configs
        )
        logger.info(
            f"[Builder] CONFIG_PUSH built: {len(symbol_configs)} symbols, "
            f"{total_strategies} active strategy assignments | regime={regime}"
        )
        return msg

    def build_initial_config(
        self,
        client_id: str,
        symbol_configs: list[SymbolConfig],
        regime: str = "UNKNOWN",
        standalone_config: Optional[StandaloneConfig] = None,
    ) -> dict:
        """
        สร้าง INITIAL_CONFIG message (Type 12)
        ส่งให้ client ใหม่เมื่อ connect เป็นครั้งแรก

        Returns:
            dict (ไม่ใช่ ConfigPushMessage เพราะ type ต่างกัน)
        """
        base = self.build_config_push(
            symbol_configs=symbol_configs,
            regime=regime,
            standalone_config=standalone_config,
            optimization_cycle="initial",
        )
        d = base.to_dict()
        d["type"] = MSG_INITIAL_CONFIG
        d["client_id"] = client_id
        d["is_initial"] = True

        logger.info(f"[Builder] INITIAL_CONFIG built for client={client_id}")
        return d

    def pack(self, message: ConfigPushMessage) -> bytes:
        """
        Serialize ConfigPushMessage → MessagePack bytes
        สำหรับส่งผ่าน ZMQ
        """
        data = message.to_dict()
        packed = msgpack.packb(data, use_bin_type=True)
        logger.debug(
            f"[Builder] Packed {len(packed)} bytes "
            f"(symbols={len(message.symbol_configs)})"
        )
        return packed

    def pack_dict(self, data: dict) -> bytes:
        """Pack dict โดยตรง (สำหรับ INITIAL_CONFIG)"""
        return msgpack.packb(data, use_bin_type=True)

    def unpack(self, data: bytes) -> dict:
        """Unpack MessagePack bytes → dict (สำหรับ test/debug)"""
        return msgpack.unpackb(data, raw=False)

    def build_and_pack(
        self,
        symbol_configs: list[SymbolConfig],
        regime: str = "UNKNOWN",
        reasoning: Optional[dict] = None,
        standalone_config: Optional[StandaloneConfig] = None,
        optimization_cycle: Optional[str] = None,
    ) -> bytes:
        """Shortcut: build + pack ในขั้นตอนเดียว → bytes"""
        msg = self.build_config_push(
            symbol_configs=symbol_configs,
            regime=regime,
            reasoning=reasoning,
            standalone_config=standalone_config,
            optimization_cycle=optimization_cycle,
        )
        return self.pack(msg)


# ─────────────────────────────────────────────
# Helper: build SymbolConfig จาก council + mm optimizer
# ─────────────────────────────────────────────

def build_symbol_config_from_decisions(
    symbol: str,
    scoring_results: list,      # list[ScoringResult] จาก P4-3
    mm_decisions: dict,         # {strategy_id: MMDecision} จาก P4-5
    strategy_params: Optional[dict] = None,  # {sid: {param: value}} จาก ParameterRepository
) -> SymbolConfig:
    """
    Helper: สร้าง SymbolConfig จาก AI Council decisions + MM decisions

    Args:
        symbol:           e.g. "XAUUSD"
        scoring_results:  list ของ ScoringResult ที่ selected (P4-3)
        mm_decisions:     {strategy_id: MMDecision} (P4-5)
        strategy_params:  {strategy_id: {param_name: value}} (optional)
    """
    strategies = []
    dd_status = None

    for score in scoring_results:
        sid = score.strategy_id
        mm_dec = mm_decisions.get(sid)

        if dd_status is None and mm_dec:
            dd_status = {
                "dd_current": mm_dec.dd_pct,
                "regime_mm_active": mm_dec.dd_override_active,
            }

        strat_cfg = StrategyConfig(
            strategy_id=sid,
            enabled=True,
            confidence=score.weighted_confidence,
            parameters=strategy_params.get(sid, {}) if strategy_params else {},
            mm_method=mm_dec.mm_method if mm_dec else "MM01",
            mm_parameters={},  # จะ fill ใน P4-5 ที่สมบูรณ์กว่า
            reasoning=score.reasoning[:100] if score.reasoning else "",  # truncate
        )
        strategies.append(strat_cfg)

    return SymbolConfig(
        symbol=symbol,
        strategies=strategies,
        mm_overrides=dd_status or {"dd_current": 0.0, "regime_mm_active": False},
    )


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )

    print("=" * 60)
    print("FlashEASuite V2 — Config Builder Test")
    print("=" * 60)

    builder = ConfigBuilder()

    # Mock symbol configs
    xauusd = SymbolConfig(
        symbol="XAUUSD",
        strategies=[
            StrategyConfig(15, True, 0.78,
                           {"S15_GRID_STEP": 15.0, "S15_GRID_LEVELS": 5},
                           "MM03", {"MM03_ATR_MULT": 1.5}, "Grid in RANGING"),
            StrategyConfig(1,  True, 0.72,
                           {"S01_LOOKBACK": 30, "S01_ZSCORE_ENTRY": 2.0},
                           "MM04", {"MM04_KELLY_FRACTION": 0.4}, "StatArb signal"),
        ],
        mm_overrides={"dd_current": 5.2, "regime_mm_active": False},
    )
    eurusd = SymbolConfig(
        symbol="EURUSD",
        strategies=[
            StrategyConfig(6,  True, 0.65,
                           {"S06_KAMA_FAST": 2, "S06_KAMA_SLOW": 30},
                           "MM08", {}, "KAMA TRENDING"),
        ],
        mm_overrides={"dd_current": 5.2, "regime_mm_active": False},
    )

    # ── Test 1: build_config_push ─────────────────────────────────────
    print("\n── Test 1: build_config_push ──")
    msg = builder.build_config_push(
        symbol_configs=[xauusd, eurusd],
        regime="RANGING",
        reasoning={
            "summary_th": "AI Council เลือก 3 strategies สำหรับ 2 symbols | Regime: RANGING",
            "summary_en": "AI Council selected 3 strategies for 2 symbols | Regime: RANGING",
            "changes": [
                {"strategy": "S15", "param": "GRID_STEP", "old": 20.0, "new": 15.0},
            ],
        },
    )
    assert msg.type == MSG_CONFIG_PUSH
    assert msg.regime == "RANGING"
    assert len(msg.symbol_configs) == 2
    assert msg.standalone_config is not None
    print(f"  type={msg.type} regime={msg.regime} symbols={len(msg.symbol_configs)}")
    print(f"  standalone_config enabled={msg.standalone_config.enabled_strategies}")
    print(f"  reasoning: {msg.reasoning['summary_en']}")

    # ── Test 2: MessagePack encoding ──────────────────────────────────
    print("\n── Test 2: MessagePack encode/decode ──")
    packed = builder.pack(msg)
    assert isinstance(packed, bytes)
    print(f"  Packed size: {len(packed)} bytes")

    unpacked = builder.unpack(packed)
    assert unpacked["type"] == MSG_CONFIG_PUSH
    assert unpacked["regime"] == "RANGING"
    assert len(unpacked["symbol_configs"]) == 2
    assert unpacked["symbol_configs"][0]["symbol"] == "XAUUSD"
    assert len(unpacked["symbol_configs"][0]["strategies"]) == 2
    print(f"  Decoded type={unpacked['type']} regime={unpacked['regime']}")
    print(f"  XAUUSD strategies={len(unpacked['symbol_configs'][0]['strategies'])}")
    print("  MessagePack integrity: ✅")

    # ── Test 3: INITIAL_CONFIG ────────────────────────────────────────
    print("\n── Test 3: INITIAL_CONFIG (Type 12) ──")
    initial = builder.build_initial_config(
        client_id="client_001",
        symbol_configs=[xauusd],
        regime="RANGING",
    )
    assert initial["type"] == MSG_INITIAL_CONFIG
    assert initial["client_id"] == "client_001"
    assert initial["is_initial"] is True

    initial_packed = builder.pack_dict(initial)
    initial_unpacked = builder.unpack(initial_packed)
    print(f"  type={initial['type']} client_id={initial['client_id']}")
    print(f"  Packed size: {len(initial_packed)} bytes")
    print(f"  Decoded type={initial_unpacked['type']} ✅")

    # ── Test 4: build_and_pack shortcut ───────────────────────────────
    print("\n── Test 4: build_and_pack ──")
    raw = builder.build_and_pack([xauusd, eurusd], regime="TRENDING")
    result = builder.unpack(raw)
    assert result["regime"] == "TRENDING"
    print(f"  Packed {len(raw)} bytes | regime={result['regime']} ✅")

    # ── Test 5: Verify standalone_config content ──────────────────────
    print("\n── Test 5: Standalone config verification ──")
    sc = msg.standalone_config
    print(f"  enabled_strategies: {sc.enabled_strategies}")
    print(f"  default_mm: {sc.default_mm}")
    print(f"  regime_hint: {sc.regime_hint}")
    assert 15 in sc.enabled_strategies
    assert 1  in sc.enabled_strategies
    assert 6  in sc.enabled_strategies
    print("  Content correct: ✅")

    print("\n✅ All tests passed!")
