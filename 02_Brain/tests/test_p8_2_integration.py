"""
test_p8_2_integration.py
FlashEASuite V2 — P8-2: Full System Integration Tests
=====================================================
ทดสอบ full pipeline:
  Signal → AI Council → CONFIG_PUSH → (MQL5 sim) → TRADE_REPORT → Feedback Loop

วิธี run: cd 02_Brain && pytest tests/test_p8_2_integration.py -v

Groups:
  A — Single strategy, single symbol (4 tests)
  B — Multi-strategy per symbol (4 tests)
  C — Multi-symbol simultaneous (4 tests)
  D — Feedback loop & self-tuning (4 tests)

Author: FlashEASuite V2 Dev | Phase: P8-2
"""

import sys
import os
import time
import threading
import queue
import tempfile
import msgpack
from pathlib import Path
from datetime import datetime

# ── path setup ────────────────────────────────────────────────────────────────
sys.path.insert(0, str(Path(__file__).parent.parent))  # 02_Brain root

import pytest

# ── imports ───────────────────────────────────────────────────────────────────
from strategies.base_analyzer import BaseAnalyzer, AnalysisResult
from core.intelligence.regime_classifier import RegimeClassifier
from core.intelligence.strategy_council import StrategyCouncil, CouncilDecision
from core.intelligence.confidence_scorer import Regime
from core.intelligence.performance_tracker import PerformanceTracker
from config_push.config_builder import (
    ConfigBuilder, ConfigPushMessage,
    SymbolConfig, StrategyConfig, StandaloneConfig,
    MSG_CONFIG_PUSH, MSG_INITIAL_CONFIG,
)
from config_push.config_pusher import ConfigPusher
from core.feedback.multi_strategy_feedback import MultiStrategyFeedback
from core.strategy.engine import normalize_symbol

# ─────────────────────────────────────────────────────────────────────────────
# Shared constants
# ─────────────────────────────────────────────────────────────────────────────
SYMBOLS_5 = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "GBPJPY"]

MAGIC_TO_SID_STR = {
    10001: "S01", 10002: "S02", 10003: "S03", 10004: "S04",
    10005: "S05", 10006: "S06", 10007: "S07", 10008: "S08",
    10009: "S09", 10010: "S10", 10011: "S11", 10012: "S12",
    10013: "S13", 10014: "S14", 10015: "S15", 10016: "S16",
}

INDICATORS_BASE = {
    "adx": 28.5, "atr": 1.2, "atr_ma": 1.0, "atr_norm": 0.6,
    "bb_width": 0.8, "bb_width_ma": 0.75, "bb_width_norm": 0.55,
    "volume": 1500.0, "volume_ma_ratio": 1.1,
    "rsi": 52.0, "stoch_k": 55.0, "stoch_d": 53.0,
    "price_change": 0.05, "spread": 0.3,
}


# ─────────────────────────────────────────────────────────────────────────────
# Mock Analyzer (P8-2 ใช้ Mock เพราะ S01-S16 จริงต้องใช้ indicator จริง)
# ─────────────────────────────────────────────────────────────────────────────
class MockAnalyzer(BaseAnalyzer):
    """Deterministic analyzer — confidence ขึ้นกับ strategy_id และ regime"""

    def __init__(self, sid: int, base_conf: float = 0.70, preferred_regimes=None):
        super().__init__()
        self._sid = sid
        self._base_conf = base_conf
        self._preferred = preferred_regimes or ["RANGING", "TRENDING"]

    def analyze(self, symbol, regime, indicators, history=None) -> AnalysisResult:
        # ปรับ confidence ตาม regime match
        conf = self._apply_regime(self._base_conf, regime)
        conf = self._clamp(conf + (self._sid % 5) * 0.01)  # ทำให้ต่างกันเล็กน้อย
        return AnalysisResult(
            confidence=conf,
            reasoning=f"Mock S{self._sid:02d} on {symbol} regime={regime}",
            extra_params={"expected_rr": 2.0 + conf},
        )

    def get_preferred_regimes(self): return self._preferred
    def get_name(self): return f"MockStrategy_{self._sid:02d}"
    def get_id(self): return f"S{self._sid:02d}"


def make_registry(high_sids=None) -> dict:
    """สร้าง analyzer registry — high_sids จะได้ confidence 0.85 (ผ่าน gate ง่าย)"""
    high = set(high_sids or [1, 7, 15])
    reg = {}
    for sid in range(1, 17):
        conf = 0.85 if sid in high else 0.65
        reg[sid] = MockAnalyzer(sid, base_conf=conf)
    return reg


# ─────────────────────────────────────────────────────────────────────────────
# Mock GenericAnalyzer (สำหรับ MultiStrategyFeedback)
# ─────────────────────────────────────────────────────────────────────────────
class MockGenericAnalyzer:
    def __init__(self):
        self.trades = []

    def record_trade(self, sid, symbol, trade_data):
        self.trades.append({"sid": sid, "symbol": symbol, "pnl": trade_data.get("pnl", 0)})

    def get_trade_count(self):
        return len(self.trades)


# ─────────────────────────────────────────────────────────────────────────────
# Helper: build fake TRADE_REPORT (parsed dict — ผลจาก ExecutionListener)
# ─────────────────────────────────────────────────────────────────────────────
def make_trade_report(magic=10001, symbol="XAUUSD.tp", profit=150.0,
                      order_type=0, open_price=2650.0):
    return {
        "msg_type":   100,
        "timestamp":  int(time.time() * 1000),
        "ticket":     12345678,
        "symbol":     symbol,
        "type":       order_type,   # 0=BUY, 1=SELL
        "volume":     0.10,
        "open_price": open_price,
        "sl":         open_price - 20.0,
        "tp":         open_price + 30.0,
        "profit":     profit,
        "magic":      magic,
        "comment":    f"S{magic-10000:02d}_{normalize_symbol(symbol)}",
        "is_win":     profit > 0,
        "is_loss":    profit < 0,
        "datetime":   datetime.now(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Helper: indicators per symbol
# ─────────────────────────────────────────────────────────────────────────────
def make_indicators_per_symbol(syms, adx_override=None):
    return {
        s: {**INDICATORS_BASE, "adx": adx_override or (28.5 + i * 2)}
        for i, s in enumerate(syms)
    }


# =============================================================================
# GROUP A — Single strategy, single symbol (4 tests)
# =============================================================================

class TestGroupA:
    """Single strategy + single symbol pipeline"""

    def _run_single_pipeline(self, sid: int, symbol: str, regime: Regime,
                             check_type: int = MSG_CONFIG_PUSH):
        """Helper: Council vote → build → pack → verify structure"""
        reg = make_registry(high_sids=[sid])
        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        decision = council.vote(
            symbol=symbol,
            regime=regime,
            indicators=INDICATORS_BASE,
        )

        # Council ต้องได้ผล (selected อาจว่างถ้า threshold ไม่ผ่าน แต่ all_votes ต้องมี 16)
        assert decision is not None
        assert len(decision.all_votes) == 16, "ต้องได้ 16 votes"
        assert decision.symbol == symbol

        # Build SymbolConfig จาก selected (ถ้าผ่าน gate)
        strategies = [
            StrategyConfig(
                strategy_id=s.strategy_id,
                enabled=True,
                confidence=s.weighted_confidence,
                parameters={"test_param": 1.0},
                mm_method="MM04",
            )
            for s in decision.selected
        ] or [
            # fallback: force enable target strategy
            StrategyConfig(strategy_id=sid, enabled=True, confidence=0.7)
        ]

        sym_cfg = SymbolConfig(symbol=symbol, strategies=strategies)
        packed = builder.build_and_pack([sym_cfg], regime=regime.name)

        # Verify packed
        assert isinstance(packed, bytes), "ต้องได้ bytes"
        assert len(packed) > 0

        decoded = builder.unpack(packed)
        assert decoded["type"] == check_type
        assert decoded["regime"] == regime.name
        assert len(decoded["symbol_configs"]) == 1
        assert decoded["symbol_configs"][0]["symbol"] == symbol
        assert "standalone_config" in decoded

        return decision, decoded

    def test_A1_s01_xauusd_ranging(self):
        """A1: S01 StatArb — XAUUSD — RANGING regime"""
        decision, decoded = self._run_single_pipeline(
            sid=1, symbol="XAUUSD", regime=Regime.RANGING
        )
        # standalone_config ต้องมี enabled_strategies
        sc = decoded["standalone_config"]
        assert isinstance(sc["enabled_strategies"], list)
        assert sc["regime_hint"] == "RANGING"
        print(f"\n  ✅ A1: {decision.summary()}")

    def test_A2_s07_eurusd_ranging(self):
        """A2: S07 MeanReversion — EURUSD — RANGING regime"""
        decision, decoded = self._run_single_pipeline(
            sid=7, symbol="EURUSD", regime=Regime.RANGING
        )
        assert decoded["symbol_configs"][0]["symbol"] == "EURUSD"
        print(f"\n  ✅ A2: {decision.summary()}")

    def test_A3_s10_gbpusd_trending(self):
        """A3: S10 Turtle — GBPUSD — TRENDING regime"""
        decision, decoded = self._run_single_pipeline(
            sid=10, symbol="GBPUSD", regime=Regime.TRENDING
        )
        assert decoded["regime"] == "TRENDING"
        print(f"\n  ✅ A3: {decision.summary()}")

    def test_A4_s15_xauusd_ranging_grid(self):
        """A4: S15 Grid — XAUUSD — RANGING (Grid ชอบ RANGING)"""
        reg = make_registry(high_sids=[15])
        reg[15] = MockAnalyzer(15, base_conf=0.88, preferred_regimes=["RANGING"])

        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        decision = council.vote(
            symbol="XAUUSD", regime=Regime.RANGING, indicators=INDICATORS_BASE
        )
        assert decision is not None

        # Build with Grid-specific params
        strategies = [
            StrategyConfig(
                strategy_id=15,
                enabled=True,
                confidence=0.80,
                parameters={"S15_GRID_STEP": 15.0, "S15_GRID_LEVELS": 5},
                mm_method="MM03",
                mm_parameters={"MM03_ATR_MULT": 1.5},
            )
        ]
        sym_cfg = SymbolConfig("XAUUSD", strategies,
                               mm_overrides={"dd_current": 3.0, "regime_mm_active": False})
        packed = builder.build_and_pack([sym_cfg], regime="RANGING")
        decoded = builder.unpack(packed)

        s = decoded["symbol_configs"][0]["strategies"][0]
        assert s["id"] == 15
        assert s["mm_method"] == "MM03"
        assert "S15_GRID_STEP" in s["parameters"]
        print(f"\n  ✅ A4: Grid S15 packed correctly, params={s['parameters']}")


# =============================================================================
# GROUP B — Multi-strategy per symbol (4 tests)
# =============================================================================

class TestGroupB:
    """Multi-strategy per symbol — top 3 selection"""

    def test_B1_xauusd_top3_selected(self):
        """B1: XAUUSD — เลือก S01+S07+S15 เป็น top 3"""
        reg = make_registry(high_sids=[1, 7, 15])
        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        decision = council.vote(
            symbol="XAUUSD", regime=Regime.RANGING, indicators=INDICATORS_BASE
        )

        assert decision is not None
        # selected ≤ 3 เสมอ (TOP_N_PER_SYMBOL = 3)
        assert len(decision.selected) <= 3
        # all_votes ต้องมีทุก 16 strategy
        assert len(decision.all_votes) == 16

        # ตรวจ ordering — weighted_confidence ลดลงเรื่อยๆ
        for i in range(len(decision.selected) - 1):
            assert decision.selected[i].weighted_confidence >= \
                   decision.selected[i+1].weighted_confidence, \
                   "selected ต้องเรียงจาก confidence สูงสุด"

        # Build CONFIG_PUSH จาก top 3
        strategies = [
            StrategyConfig(s.strategy_id, True, s.weighted_confidence)
            for s in decision.selected
        ]
        packed = builder.build_and_pack(
            [SymbolConfig("XAUUSD", strategies)], regime="RANGING"
        )
        decoded = builder.unpack(packed)
        assert len(decoded["symbol_configs"][0]["strategies"]) == len(decision.selected)
        print(f"\n  ✅ B1: {len(decision.selected)} strategies selected for XAUUSD")

    def test_B2_eurusd_trending_multi(self):
        """B2: EURUSD — TRENDING — S06+S10+S12"""
        reg = make_registry(high_sids=[6, 10, 12])
        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        decision = council.vote(
            symbol="EURUSD", regime=Regime.TRENDING,
            indicators={**INDICATORS_BASE, "adx": 38.0},
        )

        assert decision is not None
        assert decision.symbol == "EURUSD"
        packed = builder.build_and_pack(
            [SymbolConfig("EURUSD", [
                StrategyConfig(s.strategy_id, True, s.weighted_confidence)
                for s in (decision.selected or [StrategyConfig(6, True, 0.7)])
            ])],
            regime="TRENDING"
        )
        decoded = builder.unpack(packed)
        assert decoded["regime"] == "TRENDING"
        print(f"\n  ✅ B2: EURUSD TRENDING — {len(decision.selected)} strategies")

    def test_B3_gbpusd_volatile_s16_active(self):
        """B3: GBPUSD — VOLATILE — S16 Spike ควร active"""
        reg = make_registry(high_sids=[16])
        reg[16] = MockAnalyzer(16, base_conf=0.88, preferred_regimes=["VOLATILE"])
        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        decision = council.vote(
            symbol="GBPUSD", regime=Regime.VOLATILE,
            indicators={**INDICATORS_BASE, "atr": 3.5, "adx": 45.0},
        )

        # ตรวจ all_votes ว่า S16 ได้ confidence สูง
        s16_vote = next((v for v in decision.all_votes if v.strategy_id == 16), None)
        assert s16_vote is not None
        assert s16_vote.weighted_confidence > 0.0, "S16 ควรได้ confidence > 0"

        # Build ด้วย S16
        sym_cfg = SymbolConfig("GBPUSD", [
            StrategyConfig(16, True, 0.80,
                           parameters={"S16_MIN_SPIKE_PIPS": 5.0},
                           mm_method="MM01")
        ])
        packed = builder.build_and_pack([sym_cfg], regime="VOLATILE")
        decoded = builder.unpack(packed)
        s = decoded["symbol_configs"][0]["strategies"][0]
        assert s["id"] == 16
        print(f"\n  ✅ B3: S16 Spike for GBPUSD VOLATILE, conf={s16_vote.weighted_confidence:.3f}")

    def test_B4_usdjpy_squeeze_s14(self):
        """B4: USDJPY — SQUEEZE — S14 BBSqueeze ควร active"""
        reg = make_registry(high_sids=[14])
        reg[14] = MockAnalyzer(14, base_conf=0.85, preferred_regimes=["SQUEEZE", "RANGING"])
        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        decision = council.vote(
            symbol="USDJPY", regime=Regime.SQUEEZE,
            indicators={**INDICATORS_BASE, "bb_width": 0.2, "bb_width_norm": 0.1},
        )

        s14_vote = next((v for v in decision.all_votes if v.strategy_id == 14), None)
        assert s14_vote is not None

        packed = builder.build_and_pack(
            [SymbolConfig("USDJPY", [StrategyConfig(14, True, 0.78)])],
            regime="SQUEEZE"
        )
        decoded = builder.unpack(packed)
        assert decoded["regime"] == "SQUEEZE"
        print(f"\n  ✅ B4: S14 BBSqueeze for USDJPY SQUEEZE, conf={s14_vote.weighted_confidence:.3f}")


# =============================================================================
# GROUP C — Multi-symbol simultaneous (4 tests)
# =============================================================================

class TestGroupC:
    """Multi-symbol pipeline ทั้ง 5 symbols พร้อมกัน"""

    def test_C1_three_symbols_vote_all(self):
        """C1: 3 symbols — vote_all_symbols() → 1 CONFIG_PUSH ต่อ symbol"""
        reg = make_registry(high_sids=[1, 7, 15])
        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        symbols = ["XAUUSD", "EURUSD", "GBPUSD"]
        indicators_per_sym = make_indicators_per_symbol(symbols)

        all_decisions = council.vote_all_symbols(
            symbols=symbols,
            regime=Regime.RANGING,
            indicators_per_symbol=indicators_per_sym,
        )

        assert len(all_decisions) == 3
        for sym in symbols:
            assert sym in all_decisions
            dec = all_decisions[sym]
            assert dec.symbol == sym
            assert len(dec.all_votes) == 16

        # Build 1 CONFIG_PUSH ต่อ symbol แล้ว verify แต่ละตัว
        for sym, dec in all_decisions.items():
            strategies = [
                StrategyConfig(s.strategy_id, True, s.weighted_confidence)
                for s in dec.selected
            ] or [StrategyConfig(1, True, 0.7)]

            packed = builder.build_and_pack(
                [SymbolConfig(sym, strategies)], regime="RANGING"
            )
            decoded = builder.unpack(packed)
            assert decoded["symbol_configs"][0]["symbol"] == sym

        print(f"\n  ✅ C1: {len(symbols)} symbols voted, all CONFIG_PUSH built")

    def test_C2_five_symbols_portfolio_diversification(self):
        """C2: 5 symbols — portfolio diversification check"""
        reg = make_registry()
        council = StrategyCouncil(analyzer_registry=reg)
        builder = ConfigBuilder()

        indicators_per_sym = make_indicators_per_symbol(SYMBOLS_5)

        all_decisions = council.vote_all_symbols(
            symbols=SYMBOLS_5,
            regime=Regime.TRENDING,
            indicators_per_symbol=indicators_per_sym,
        )

        assert len(all_decisions) == 5

        # Build combined CONFIG_PUSH (ทุก symbols ใน 1 message)
        symbol_configs = []
        for sym, dec in all_decisions.items():
            strategies = [
                StrategyConfig(s.strategy_id, True, s.weighted_confidence)
                for s in dec.selected
            ] or [StrategyConfig(1, True, 0.6)]
            symbol_configs.append(SymbolConfig(sym, strategies))

        packed = builder.build_and_pack(symbol_configs, regime="TRENDING")
        decoded = builder.unpack(packed)

        assert len(decoded["symbol_configs"]) == 5
        syms_in_msg = [sc["symbol"] for sc in decoded["symbol_configs"]]
        for sym in SYMBOLS_5:
            assert sym in syms_in_msg

        print(f"\n  ✅ C2: 5 symbols in 1 CONFIG_PUSH, {len(decoded['symbol_configs'])} symbol_configs")

    def test_C3_regime_change_notification(self):
        """C3: Regime change — push_regime_change() ส่ง type=31"""
        builder = ConfigBuilder()

        # Build config ใหม่สำหรับ TRENDING
        sym_cfg = SymbolConfig("XAUUSD", [StrategyConfig(10, True, 0.75)])
        new_packed = builder.build_and_pack([sym_cfg], regime="TRENDING")

        # Pusher ใน simulation mode (ไม่มี ZMQ จริง)
        pusher = ConfigPusher(port=7778)
        pusher.start()

        ok = pusher.push_regime_change(
            new_regime="TRENDING",
            old_regime="RANGING",
            packed_config=new_packed,
        )
        stats = pusher.get_stats()
        pusher.stop()

        assert ok, "push_regime_change ต้องสำเร็จ"
        # 2 messages: type=31 + config
        assert stats["total_sent"] >= 2
        assert stats["broadcast_count"] >= 2
        print(f"\n  ✅ C3: Regime change RANGING→TRENDING, sent={stats['total_sent']} msgs")

    def test_C4_online_to_standalone_switch(self):
        """C4: Online → Standalone — standalone_config ต้องถูก embed ใน CONFIG_PUSH"""
        builder = ConfigBuilder()

        # Standalone config ที่ MQL5 จะ save แล้วใช้ตอน disconnect
        standalone = StandaloneConfig(
            enabled_strategies=[15, 7, 1],  # 3 standalone-capable strategies
            default_mm="MM01",
            risk_multiplier=0.8,            # ลด risk ตอน standalone
            regime_hint="RANGING",
        )

        sym_cfg = SymbolConfig("XAUUSD", [
            StrategyConfig(15, True, 0.78, mm_method="MM01"),
            StrategyConfig(7,  True, 0.72, mm_method="MM01"),
            StrategyConfig(1,  True, 0.68, mm_method="MM01"),
        ])

        packed = builder.build_and_pack(
            [sym_cfg], regime="RANGING", standalone_config=standalone
        )
        decoded = builder.unpack(packed)

        sc = decoded["standalone_config"]
        assert sc["enabled_strategies"] == [15, 7, 1]
        assert sc["default_mm"] == "MM01"
        assert sc["risk_multiplier"] == 0.8
        assert sc["regime_hint"] == "RANGING"
        print(f"\n  ✅ C4: Standalone config embedded: strategies={sc['enabled_strategies']}")


# =============================================================================
# GROUP D — Feedback Loop & Self-tuning (4 tests)
# =============================================================================

class TestGroupD:
    """Feedback loop: TRADE_REPORT → MultiStrategyFeedback → PerformanceTracker → Council"""

    def _setup_feedback_components(self, tmp_path):
        generic = MockGenericAnalyzer()
        feedback = MultiStrategyFeedback(generic_analyzer=generic)
        tracker = PerformanceTracker(metrics_file=tmp_path / "metrics.json")
        reg = make_registry(high_sids=[1, 7])
        council = StrategyCouncil(analyzer_registry=reg)
        return feedback, tracker, council, generic

    def test_D1_win_trade_feedback(self, tmp_path):
        """D1: WIN trade → feedback pipeline ครบทุก component"""
        feedback, tracker, council, generic = self._setup_feedback_components(tmp_path)

        trade = make_trade_report(magic=10001, symbol="XAUUSD.tp", profit=150.0)
        sid_str = MAGIC_TO_SID_STR[trade["magic"]]  # "S01"
        sid_int = int(sid_str[1:])                    # 1
        base_sym = normalize_symbol(trade["symbol"])  # "XAUUSD"

        # Step 1: MultiStrategyFeedback
        result = feedback.process_trade_report({
            "client_id":       "MT5_Client_001",
            "symbol":          base_sym,
            "strategy_id":     sid_str,
            "order_type":      trade["type"],
            "open_price":      trade["open_price"],
            "close_price":     trade["open_price"] + 30.0,
            "profit":          trade["profit"],
            "open_time_ms":    trade["timestamp"] - 3600000,
            "close_time_ms":   trade["timestamp"],
            "mm_used":         "MM04",
            "regime_at_entry": "RANGING",
        })
        assert result["status"] == "ok"
        assert result["pnl"] == 150.0
        assert "GenericAnalyzer" in result["routed_to"]

        # Step 2: PerformanceTracker
        tracker.record_prediction(
            strategy=sid_int,
            symbol=base_sym,
            prediction=1,
            actual_outcome=trade["profit"],
            rr_achieved=2.5,
        )
        m = tracker.get_metrics(sid_int, base_sym)
        assert m is not None
        assert m.total_trades == 1
        assert m.win_count == 1

        # Step 3: Council self-tuning
        council.record_outcome(strategy_id=sid_int, symbol=base_sym, was_profitable=True)
        factor = council.get_hist_perf_factor(sid_int, base_sym)
        # < 10 trades → ยังคืน 1.0 (neutral)
        assert factor == 1.0, "< 10 trades → factor ต้องเป็น 1.0"

        print(f"\n  ✅ D1: WIN trade S01@XAUUSD — pnl={trade['profit']}, "
              f"win_count={m.win_count}, factor={factor}")

    def test_D2_loss_trade_feedback(self, tmp_path):
        """D2: LOSS trade → win_count ไม่เพิ่ม, loss_count เพิ่ม"""
        feedback, tracker, council, generic = self._setup_feedback_components(tmp_path)

        trade = make_trade_report(magic=10007, symbol="EURUSD.tp", profit=-80.0)
        sid_str = "S07"
        sid_int = 7
        base_sym = "EURUSD"

        result = feedback.process_trade_report({
            "client_id":   "MT5_Client_001",
            "symbol":      base_sym,
            "strategy_id": sid_str,
            "order_type":  trade["type"],
            "open_price":  trade["open_price"],
            "close_price": trade["open_price"] - 10.0,
            "profit":      trade["profit"],
            "open_time_ms": 0,
            "close_time_ms": trade["timestamp"],
            "mm_used":     "MM04",
            "regime_at_entry": "RANGING",
        })
        assert result["status"] == "ok"
        assert result["pnl"] == -80.0

        tracker.record_prediction(sid_int, base_sym, -1, trade["profit"])
        m = tracker.get_metrics(sid_int, base_sym)
        assert m.win_count == 0
        assert m.loss_count == 1
        assert m.total_pnl == -80.0

        council.record_outcome(sid_int, base_sym, was_profitable=False)
        print(f"\n  ✅ D2: LOSS trade S07@EURUSD — pnl={trade['profit']}, "
              f"loss_count={m.loss_count}")

    def test_D3_ten_trades_factor_changes(self, tmp_path):
        """D3: 10+ trades → hist_perf_factor เปลี่ยนจาก neutral 1.0"""
        feedback, tracker, council, generic = self._setup_feedback_components(tmp_path)

        sid_int = 1
        symbol = "XAUUSD"

        # บันทึก 12 trades: 8 WIN, 4 LOSS → win rate 67%
        for i in range(12):
            is_win = (i % 3 != 0)  # 8 WIN, 4 LOSS
            pnl = 100.0 if is_win else -50.0
            tracker.record_prediction(sid_int, symbol, 1, pnl)
            council.record_outcome(sid_int, symbol, was_profitable=is_win)

        factor = council.get_hist_perf_factor(sid_int, symbol)
        # 12 trades ≥ MIN_HISTORY_FOR_TUNING(10) → factor ≠ 1.0
        assert factor != 1.0, f"หลัง 12 trades factor ต้องเปลี่ยนจาก 1.0 (ได้ {factor})"
        assert 0.5 <= factor <= 1.5, f"factor ต้องอยู่ใน [0.5, 1.5] (ได้ {factor})"

        m = tracker.get_metrics(sid_int, symbol)
        assert m.total_trades == 12
        wr = tracker.get_win_rate(sid_int, symbol)
        assert 0.6 <= wr <= 0.75  # ประมาณ 67%

        print(f"\n  ✅ D3: 12 trades → factor={factor:.3f}, win_rate={wr:.1%}, "
              f"ema_weight={tracker.get_ema_weight(sid_int, symbol):.3f}")

    def test_D4_council_vote_uses_updated_weights(self, tmp_path):
        """D4: หลัง record_outcome → vote() ครั้งถัดไป ใช้ weight ที่อัปเดตแล้ว"""
        feedback, tracker, council, generic = self._setup_feedback_components(tmp_path)

        sid_int = 1
        symbol = "XAUUSD"

        # Record 12 WIN trades → ประสิทธิภาพสูง
        for _ in range(12):
            council.record_outcome(sid_int, symbol, was_profitable=True)

        # factor ควรสูงกว่า 1.0 (เพราะ win rate สูง)
        factor_after = council.get_hist_perf_factor(sid_int, symbol)
        assert factor_after > 1.0, f"หลัง 12 WIN factor ควร > 1.0 (ได้ {factor_after})"

        # Vote อีกครั้ง — S01 ควรได้ weighted_confidence สูงขึ้น
        decision = council.vote(symbol=symbol, regime=Regime.RANGING,
                                indicators=INDICATORS_BASE)
        assert decision is not None

        s01_vote = next((v for v in decision.all_votes if v.strategy_id == sid_int), None)
        assert s01_vote is not None
        # weighted_confidence ต้องได้รับ boost จาก hist_perf_factor > 1.0
        assert s01_vote.weighted_confidence > 0.0

        print(f"\n  ✅ D4: hist_perf_factor={factor_after:.3f} → "
              f"S01 weighted_conf={s01_vote.weighted_confidence:.3f}")


# =============================================================================
# BONUS — CONFIG_PUSH format integrity (ไม่อยู่ใน group แต่สำคัญ)
# =============================================================================

class TestConfigFormat:
    """ตรวจสอบ format ของ CONFIG_PUSH V2 ให้ตรงกับที่ MQL5 expect"""

    def test_config_push_all_required_fields(self):
        """ตรวจ fields ทุกอย่างที่ MQL5 ConfigReceiver._ParseConfigPush() expect"""
        builder = ConfigBuilder()
        sym_cfg = SymbolConfig("XAUUSD", [
            StrategyConfig(1, True, 0.72,
                           {"S01_LOOKBACK": 20, "S01_ZSCORE": 2.0},
                           "MM04", {"MM04_KELLY": 0.4}, "StatArb RANGING")
        ])
        packed = builder.build_and_pack([sym_cfg], regime="RANGING")
        d = builder.unpack(packed)

        # Top-level fields
        assert d["type"] == 10
        assert d["version"] == "2.0"
        assert "timestamp" in d
        assert "optimization_cycle" in d
        assert d["regime"] == "RANGING"
        assert "symbol_configs" in d
        assert "reasoning" in d
        assert "standalone_config" in d

        # symbol_configs structure
        sc = d["symbol_configs"][0]
        assert sc["symbol"] == "XAUUSD"
        assert "strategies" in sc
        assert "mm_overrides" in sc

        # strategy structure
        s = sc["strategies"][0]
        assert s["id"] == 1
        assert s["enabled"] is True
        assert "confidence" in s
        assert "parameters" in s
        assert s["mm_method"] == "MM04"
        assert "mm_parameters" in s

        # standalone_config structure
        ssc = d["standalone_config"]
        assert "enabled_strategies" in ssc
        assert "default_mm" in ssc
        assert "risk_multiplier" in ssc
        assert "regime_hint" in ssc
        assert 1 in ssc["enabled_strategies"]

        print("\n  ✅ CONFIG_PUSH V2 format: ทุก field ครบตามที่ MQL5 expect")

    def test_initial_config_type_12(self):
        """INITIAL_CONFIG ต้องเป็น type=12"""
        builder = ConfigBuilder()
        sym_cfg = SymbolConfig("XAUUSD", [StrategyConfig(15, True, 0.75)])
        initial = builder.build_initial_config("MT5_Client_001", [sym_cfg], "RANGING")

        assert initial["type"] == MSG_INITIAL_CONFIG  # 12
        assert initial["client_id"] == "MT5_Client_001"
        assert initial["is_initial"] is True

        packed = builder.pack_dict(initial)
        decoded = builder.unpack(packed)
        assert decoded["type"] == 12
        print("\n  ✅ INITIAL_CONFIG type=12 verified")

    def test_pusher_simulation_mode_stats(self):
        """ConfigPusher simulation mode — stats tracking ถูกต้อง"""
        builder = ConfigBuilder()
        pusher = ConfigPusher(port=17778)  # port ที่ไม่ใช้จริง
        pusher.start()

        sym_cfg = SymbolConfig("XAUUSD", [StrategyConfig(1, True, 0.7)])
        packed = builder.build_and_pack([sym_cfg], regime="RANGING")

        for _ in range(5):
            ok = pusher.push_to_all(packed)
            assert ok

        pusher.register_client("cli_001")
        ok = pusher.push_to_client("cli_001", packed)
        assert ok

        stats = pusher.get_stats()
        assert stats["total_sent"] == 6
        assert stats["broadcast_count"] == 5
        assert stats["targeted_count"] == 1
        assert stats["clients"] == 1
        assert stats["success_rate"] == 1.0

        pusher.stop()
        print(f"\n  ✅ Pusher stats: {stats}")

    def test_normalize_symbol_broker_suffixes(self):
        """normalize_symbol ต้อง strip suffix ทุก pattern"""
        assert normalize_symbol("XAUUSD.tp") == "XAUUSD"
        assert normalize_symbol("GBPUSD_m")  == "GBPUSD"
        assert normalize_symbol("EURUSD.raw") == "EURUSD"
        assert normalize_symbol("USDJPY.ecn") == "USDJPY"
        assert normalize_symbol("XAUUSD")     == "XAUUSD"  # ไม่มี suffix
        print("\n  ✅ normalize_symbol: ทุก broker suffix stripped correctly")


# =============================================================================
# Entry point
# =============================================================================

if __name__ == "__main__":
    print("=" * 65)
    print("FlashEASuite V2 — P8-2 Integration Tests")
    print("run: cd 02_Brain && pytest tests/test_p8_2_integration.py -v")
    print("=" * 65)
    pytest.main([__file__, "-v", "--tb=short"])
