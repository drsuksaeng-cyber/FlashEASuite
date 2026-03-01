"""
FlashEASuite V2 — P0.6-7: CONFIG_PUSH V2 Generator
สร้าง CONFIG_PUSH V2 message จาก optimization results
Pack strategy params (S01-S16) + MM params + MM selection + reasoning

Format V2 backward compatible:
    - type: 10 (same as V1)
    - เพิ่ม: optimization_cycle, per-strategy parameters, mm_parameters
    - เพิ่ม: reasoning dict (Thai text)
    - เพิ่ม: standalone_config fallback

Dependencies:
    - ParameterRepository (P0.6-3)
    - MultiStrategyOptimizer output (P0.6-6)

Author: FlashEASuite V2 Team | Phase: P0.6-7
"""

import time
import logging
import msgpack
from datetime import datetime, timezone
from typing import Optional

logger = logging.getLogger("FlashEA.ConfigPush")

# Standalone-capable strategies (can run without server)
STANDALONE_STRATEGIES = ["S01", "S06", "S07", "S10", "S14", "S15", "S16"]
STANDALONE_DEFAULT_MM = "MM01"
STANDALONE_RISK_MULT = 0.5

# All strategies S01-S16
ALL_STRATEGY_IDS = [f"S{i:02d}" for i in range(1, 17)]

# CONFIG_PUSH V2 version identifier
CONFIG_PUSH_VERSION = 2


class ConfigPushGenerator:
    """
    สร้าง CONFIG_PUSH V2 message จาก optimization results.

    Output format:
    {
        "type": 10,
        "version": 2,
        "timestamp": "2026-02-17T00:00:00Z",
        "optimization_cycle": "OPT_20260217_000000",
        "regime": "TRENDING",
        "symbol_configs": [
            {
                "symbol": "XAUUSD",
                "strategies": [
                    {
                        "id": "S01", "enabled": true, "confidence": 0.69,
                        "parameters": {"S01_LOOKBACK_PERIOD": 25, ...},
                        "mm_method": "MM04",
                        "mm_parameters": {"MM04_KELLY_FRACTION": 0.4, ...}
                    }, ...
                ],
                "mm_overrides": {"dd_current": 5.2, "regime_mm_active": false}
            }
        ],
        "reasoning": {"summary_th": "...", "changes": [...]},
        "standalone_config": {
            "enabled_strategies": ["S01","S06",...],
            "default_mm": "MM01",
            "risk_multiplier": 0.5
        }
    }
    """

    def __init__(self, param_repo=None):
        self._repo = param_repo
        self._cycle_count = 0
        logger.info("[ConfigPushGen] Initialized")

    def generate(self, optimized: dict, param_repo=None,
                 symbol: str = "XAUUSD",
                 enabled_strategies: list = None,
                 dd_pct: float = 0.0) -> dict:
        """
        สร้าง CONFIG_PUSH V2 dict จาก optimizer output.

        Args:
            optimized: Output from MultiStrategyOptimizer.optimize_all()
                       {strategy_changes, mm_changes, mm_selection,
                        reasoning, confidence, applied, regime, ...}
            param_repo: ParameterRepository (fallback to self._repo)
            symbol: Target symbol
            enabled_strategies: List of enabled strategy IDs (None = all)
            dd_pct: Current drawdown %

        Returns:
            dict: CONFIG_PUSH V2 payload ready for MessagePack
        """
        repo = param_repo or self._repo
        if repo is None:
            logger.error("[ConfigPushGen] No ParameterRepository!")
            return {"error": "no_param_repo"}

        self._cycle_count += 1
        now = datetime.now(timezone.utc)
        cycle_id = f"OPT_{now.strftime('%Y%m%d_%H%M%S')}_{self._cycle_count:04d}"

        regime = optimized.get("regime", "UNKNOWN")
        mm_selection = optimized.get("mm_selection", {})
        reasoning = optimized.get("reasoning", {})
        confidence = optimized.get("confidence", 0.0)

        if enabled_strategies is None:
            enabled_strategies = ALL_STRATEGY_IDS

        # Build per-strategy config
        strategies_config = self._build_strategies_config(
            repo, symbol, enabled_strategies, mm_selection, confidence
        )

        # Build symbol config
        symbol_config = {
            "symbol": symbol,
            "strategies": strategies_config,
            "mm_overrides": {
                "dd_current": round(dd_pct, 2),
                "regime_mm_active": regime in ("VOLATILE", "CRISIS"),
            },
        }

        # Build standalone config
        standalone = self._build_standalone_config(
            repo, enabled_strategies, regime
        )

        # Build final CONFIG_PUSH V2
        config_push = {
            "type": 10,
            "version": CONFIG_PUSH_VERSION,
            "timestamp": now.isoformat(),
            "optimization_cycle": cycle_id,
            "regime": regime,
            "symbol_configs": [symbol_config],
            "reasoning": {
                "summary_th": reasoning.get("summary_th", "ไม่มีข้อมูล"),
                "changes": reasoning.get("changes", []),
                "total_changes": reasoning.get("total_changes", 0),
                "confidence": confidence,
                "applied": optimized.get("applied", False),
            },
            "standalone_config": standalone,
        }

        logger.info(f"[ConfigPushGen] Generated {cycle_id}: "
                    f"{len(strategies_config)} strategies, regime={regime}, "
                    f"conf={confidence:.2f}")

        return config_push

    def generate_multi_symbol(self, optimizer_results: dict,
                              param_repo=None,
                              symbols: list = None,
                              enabled_strategies: list = None,
                              dd_pct: float = 0.0) -> dict:
        """
        สร้าง CONFIG_PUSH V2 สำหรับหลาย symbols.

        Args:
            optimizer_results: {symbol: optimize_all_result, ...}
            symbols: list of symbols (None = use keys from results)
        """
        repo = param_repo or self._repo
        if repo is None:
            return {"error": "no_param_repo"}

        self._cycle_count += 1
        now = datetime.now(timezone.utc)
        cycle_id = f"OPT_{now.strftime('%Y%m%d_%H%M%S')}_{self._cycle_count:04d}"

        if symbols is None:
            symbols = list(optimizer_results.keys())
        if enabled_strategies is None:
            enabled_strategies = ALL_STRATEGY_IDS

        symbol_configs = []
        combined_reasoning_parts = []
        overall_confidence = 0.0
        total_applied = False

        for sym in symbols:
            opt_result = optimizer_results.get(sym, {})
            regime = opt_result.get("regime", "UNKNOWN")
            mm_selection = opt_result.get("mm_selection", {})
            confidence = opt_result.get("confidence", 0.0)
            overall_confidence = max(overall_confidence, confidence)
            if opt_result.get("applied"):
                total_applied = True

            strategies_config = self._build_strategies_config(
                repo, sym, enabled_strategies, mm_selection, confidence
            )
            symbol_configs.append({
                "symbol": sym,
                "strategies": strategies_config,
                "mm_overrides": {
                    "dd_current": round(dd_pct, 2),
                    "regime_mm_active": regime in ("VOLATILE", "CRISIS"),
                },
            })
            r = opt_result.get("reasoning", {})
            if r.get("summary_th"):
                combined_reasoning_parts.append(r["summary_th"])

        # Use first symbol's regime as primary
        primary_regime = "UNKNOWN"
        if symbols and symbols[0] in optimizer_results:
            primary_regime = optimizer_results[symbols[0]].get("regime", "UNKNOWN")

        standalone = self._build_standalone_config(
            repo, enabled_strategies, primary_regime
        )

        return {
            "type": 10,
            "version": CONFIG_PUSH_VERSION,
            "timestamp": now.isoformat(),
            "optimization_cycle": cycle_id,
            "regime": primary_regime,
            "symbol_configs": symbol_configs,
            "reasoning": {
                "summary_th": " | ".join(combined_reasoning_parts) if combined_reasoning_parts
                              else "ไม่มีข้อมูล",
                "changes": [],
                "total_changes": sum(r.get("reasoning", {}).get("total_changes", 0)
                                     for r in optimizer_results.values()),
                "confidence": overall_confidence,
                "applied": total_applied,
            },
            "standalone_config": standalone,
        }

    def pack_to_messagepack(self, config_push: dict) -> bytes:
        """
        Serialize CONFIG_PUSH V2 dict → MessagePack bytes.
        Compatible with existing MQL5 unpacker.

        Pack order (array): [type, timestamp_ms, regime,
                             symbol_configs, reasoning, standalone_config,
                             version, optimization_cycle]
        Index 0-5 matches V1 ConfigPushMsg.from_array() for backward compat.
        Index 6-7 are V2 extensions (old clients ignore extra fields).
        """
        timestamp_ms = int(time.time() * 1000)

        # Array format for backward compatibility with ConfigPushMsg
        arr = [
            config_push.get("type", 10),           # [0] msg_type
            timestamp_ms,                            # [1] timestamp_ms
            config_push.get("regime", "UNKNOWN"),    # [2] regime
            config_push.get("symbol_configs", []),   # [3] symbol_configs
            config_push.get("reasoning", {}),        # [4] reasoning
            config_push.get("standalone_config", {}),# [5] standalone_config
            # V2 extensions (backward compat — old clients ignore these)
            config_push.get("version", 2),           # [6] version
            config_push.get("optimization_cycle", ""),# [7] cycle_id
        ]

        try:
            packed = msgpack.packb(arr, use_bin_type=True)
            logger.debug(f"[ConfigPushGen] Packed {len(packed)} bytes")
            return packed
        except Exception as e:
            logger.error(f"[ConfigPushGen] MessagePack error: {e}")
            return b""

    @staticmethod
    def unpack_from_messagepack(data: bytes) -> dict:
        """Deserialize MessagePack → CONFIG_PUSH V2 dict."""
        try:
            arr = msgpack.unpackb(data, raw=False)
            result = {
                "type": arr[0],
                "timestamp_ms": arr[1],
                "regime": arr[2],
                "symbol_configs": arr[3] if len(arr) > 3 else [],
                "reasoning": arr[4] if len(arr) > 4 else {},
                "standalone_config": arr[5] if len(arr) > 5 else {},
                "version": arr[6] if len(arr) > 6 else 1,
                "optimization_cycle": arr[7] if len(arr) > 7 else "",
            }
            return result
        except Exception as e:
            logger.error(f"[ConfigPushGen] Unpack error: {e}")
            return {}

    # ================================================================
    # Internal Builders
    # ================================================================

    def _build_strategies_config(self, repo, symbol: str,
                                  enabled: list, mm_selection: dict,
                                  confidence: float) -> list:
        """Build per-strategy config list for one symbol."""
        configs = []
        for sid in enabled:
            # Strategy parameters
            sparams = repo.get_all_strategy_params(sid)
            if not sparams:
                continue  # Strategy has no params defined → skip

            # MM method (from optimizer selection or repo default)
            mm = mm_selection.get(sid) or repo.get_mm_for_strategy(sid)
            mm_params = repo.get_all_mm_params(mm)

            configs.append({
                "id": sid,
                "enabled": True,
                "confidence": round(confidence, 4),
                "parameters": sparams,
                "mm_method": mm,
                "mm_parameters": mm_params,
            })

        return configs

    def _build_standalone_config(self, repo, enabled: list,
                                  regime: str) -> dict:
        """Build standalone fallback config for offline clients."""
        # Only standalone-capable strategies
        standalone_enabled = [s for s in STANDALONE_STRATEGIES if s in enabled]

        return {
            "enabled_strategies": standalone_enabled,
            "default_mm": STANDALONE_DEFAULT_MM,
            "risk_multiplier": STANDALONE_RISK_MULT,
            "regime_hint": regime,
        }


# ================================================================
# INLINE TESTS
# ================================================================
if __name__ == "__main__":

    # Mock ParameterRepository
    class MockRepo:
        def __init__(self):
            self._sparams = {
                "S01_LOOKBACK_PERIOD": {"strategy": "S01", "default": 20},
                "S01_ENTRY_ZSCORE": {"strategy": "S01", "default": 2.0},
                "S15_ELASTIC_FACTOR": {"strategy": "S15", "default": 1.5},
            }
            self._mparams = {
                "MM04_KELLY_FRACTION": {"mm_method": "MM04", "default": 0.25},
                "MM01_RISK_PCT": {"mm_method": "MM01", "default": 1.0},
            }

        def get_all_strategy_params(self, sid):
            return {n: d["default"] for n, d in self._sparams.items()
                    if d.get("strategy") == sid}

        def get_all_mm_params(self, mm):
            return {n: d["default"] for n, d in self._mparams.items()
                    if d.get("mm_method") == mm}

        def get_mm_for_strategy(self, sid, **kw):
            return {"S01": "MM04", "S15": "MM03"}.get(sid, "MM01")

    repo = MockRepo()
    gen = ConfigPushGenerator(param_repo=repo)

    # T1: Basic generation
    opt = {
        "strategy_changes": {"S01_LOOKBACK_PERIOD": {"value": 25}},
        "mm_changes": {},
        "mm_selection": {"S01": "MM04"},
        "reasoning": {"summary_th": "ปรับ LOOKBACK 20→25 (TRENDING)", "changes": [], "total_changes": 1},
        "confidence": 0.75,
        "applied": True,
        "regime": "TRENDING",
    }
    cp = gen.generate(opt, symbol="XAUUSD")
    assert cp["type"] == 10 and cp["version"] == 2
    assert cp["regime"] == "TRENDING"
    assert len(cp["symbol_configs"]) == 1
    assert cp["symbol_configs"][0]["symbol"] == "XAUUSD"
    print(f"✅ T1: Generated — cycle={cp['optimization_cycle']}, "
          f"{len(cp['symbol_configs'][0]['strategies'])} strategies")

    # T2: Standalone config
    sc = cp["standalone_config"]
    assert "S01" in sc["enabled_strategies"]
    assert sc["default_mm"] == "MM01"
    assert sc["risk_multiplier"] == 0.5
    print(f"✅ T2: Standalone — {len(sc['enabled_strategies'])} strategies, "
          f"mm={sc['default_mm']}")

    # T3: Reasoning preserved
    assert "ปรับ LOOKBACK" in cp["reasoning"]["summary_th"]
    print(f"✅ T3: Reasoning — '{cp['reasoning']['summary_th'][:50]}...'")

    # T4: MessagePack round-trip
    packed = gen.pack_to_messagepack(cp)
    assert len(packed) > 0
    unpacked = ConfigPushGenerator.unpack_from_messagepack(packed)
    assert unpacked["type"] == 10
    assert unpacked["regime"] == "TRENDING"
    assert unpacked["version"] == 2
    assert len(unpacked["symbol_configs"]) == 1
    print(f"✅ T4: MessagePack round-trip — {len(packed)} bytes")

    # T5: Backward compatibility (V1 client reads index 0-5 only)
    arr = msgpack.unpackb(packed, raw=False)
    assert arr[0] == 10 and isinstance(arr[2], str)  # type + regime
    assert isinstance(arr[3], list)  # symbol_configs
    print("✅ T5: Backward compatible (V1 indexes 0-5 preserved)")

    # T6: Multi-symbol generation
    opt2 = dict(opt)
    opt2["regime"] = "RANGING"
    results = {"XAUUSD": opt, "EURUSD": opt2}
    multi = gen.generate_multi_symbol(results, symbols=["XAUUSD", "EURUSD"])
    assert len(multi["symbol_configs"]) == 2
    assert multi["symbol_configs"][1]["symbol"] == "EURUSD"
    print(f"✅ T6: Multi-symbol — {len(multi['symbol_configs'])} symbols")

    # T7: Empty optimization (no changes)
    empty_opt = {"strategy_changes": {}, "mm_changes": {}, "mm_selection": {},
                 "reasoning": {}, "confidence": 0.0, "applied": False, "regime": "UNKNOWN"}
    cp_empty = gen.generate(empty_opt, symbol="GBPUSD")
    assert cp_empty["type"] == 10 and cp_empty["reasoning"]["confidence"] == 0.0
    print("✅ T7: Empty optimization handled")

    # T8: MM overrides with DD
    cp_dd = gen.generate(opt, symbol="XAUUSD", dd_pct=16.5)
    ovr = cp_dd["symbol_configs"][0]["mm_overrides"]
    assert ovr["dd_current"] == 16.5
    print(f"✅ T8: MM overrides — DD={ovr['dd_current']}%, "
          f"regime_active={ovr['regime_mm_active']}")

    print("\n" + "=" * 50)
    print("✅ ALL ConfigPushGenerator TESTS PASSED")
    print("=" * 50)
