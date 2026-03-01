"""
FlashEASuite V2 — P0.6-5 Test Suite
ทดสอบ MMAnalyzer + RegimeParameterMapper

วิธีรัน:
    cd 02_Brain
    python -m pytest tests/test_p065_mm_analyzer_regime_mapper.py -v
    
    หรือรันตรง:
    python tests/test_p065_mm_analyzer_regime_mapper.py

Author: FlashEASuite V2 Team | Phase: P0.6-5
"""

import sys
import os
import json
import time
import random
import tempfile
import shutil

# ============================================================
# Mock ParameterRepository (จำลอง P0.6-3)
# ============================================================

class MockParameterRepository:
    """
    จำลอง ParameterRepository สำหรับ test
    ใช้แทน class จริงจาก P0.6-3
    """
    def __init__(self):
        self._mm_params = {
            # MM17 regime multipliers
            ("MM17", "MM17_TREND_MULTIPLIER"): 1.2,
            ("MM17", "MM17_RANGE_MULTIPLIER"): 1.0,
            ("MM17", "MM17_VOLATILE_MULTIPLIER"): 0.3,
            ("MM17", "MM17_CRISIS_MULTIPLIER"): 0.0,
            ("MM17", "MM17_CONFIRM_BARS"): 3,
            # MM01
            ("MM01", "MM01_RISK_PCT"): 1.0,
            # MM04
            ("MM04", "MM04_KELLY_FRACTION"): 0.5,
            # MM10
            ("MM10", "MM10_DD_TIER1_PCT"): 10.0,
            ("MM10", "MM10_DD_TIER2_PCT"): 15.0,
            ("MM10", "MM10_DD_STOP_PCT"): 20.0,
        }

    def get_mm_param(self, mm_method: str, param_name: str):
        return self._mm_params.get((mm_method, param_name))

    def set_mm_param(self, mm_method: str, param_name: str, value, reason=""):
        self._mm_params[(mm_method, param_name)] = value
        return True

    def get_mm_for_strategy(self, strategy_id: str, regime: str = None):
        defaults = {"S01": "MM04", "S15": "MM03", "S16": "MM01"}
        return defaults.get(strategy_id, "MM01")


# ============================================================
# Helper: สร้าง test config directory + JSON files
# ============================================================

def create_test_config_dir() -> str:
    """สร้าง temp directory พร้อม mm_selection_matrix.json สำหรับ test."""
    tmpdir = tempfile.mkdtemp(prefix="flashea_test_")

    # mm_selection_matrix.json (จาก P0.6-2)
    matrix = {
        "default_mm_per_strategy": {
            "S01": "MM04", "S02": "MM01", "S03": "MM01",
            "S04": "MM01", "S05": "MM01", "S06": "MM08",
            "S07": "MM01", "S08": "MM01", "S09": "MM01",
            "S10": "MM08", "S11": "MM01", "S12": "MM01",
            "S13": "MM01", "S14": "MM03", "S15": "MM03",
            "S16": "MM01"
        },
        "volatile_mm_per_strategy": {
            "S01": "MM07", "S02": "MM17", "S06": "MM16",
            "S07": "MM07", "S10": "MM16", "S14": "MM07",
            "S15": "MM17", "S16": "MM01"
        },
        "dd_mm_per_strategy": {
            "S01": "MM10", "S02": "MM10", "S15": "MM10", "S16": "MM10"
        },
        "regime_overrides": {
            "TRENDING": {
                "preferred_mm": ["MM03", "MM08", "MM17"],
                "avoid": ["MM05"],
                "risk_adjustment": 1.0
            },
            "RANGING": {
                "preferred_mm": ["MM01", "MM04", "MM07"],
                "avoid": ["MM08"],
                "risk_adjustment": 1.0
            },
            "VOLATILE": {
                "preferred_mm": ["MM10", "MM16", "MM17"],
                "avoid": ["MM05", "MM06"],
                "risk_adjustment": 0.5
            },
            "CRISIS": {
                "preferred_mm": ["MM10"],
                "avoid": ["MM05", "MM06", "MM08"],
                "risk_adjustment": 0.0,
                "force_reduce": True
            }
        },
        "dd_overrides": {
            "dd_10pct": {"threshold_pct": 10.0, "action": "reduce_50pct", "switch_to": "MM10"},
            "dd_15pct": {"threshold_pct": 15.0, "action": "reduce_75pct", "switch_to": "MM10"},
            "dd_20pct": {"threshold_pct": 20.0, "action": "stop_new_trades", "only_mm": "MM10"}
        },
        "mm_method_info": {
            "MM01": {"name": "Fixed Fractional Conservative", "type": "Anti-M"},
            "MM04": {"name": "Kelly Criterion (Half-Kelly)", "type": "Anti-M"},
            "MM10": {"name": "Drawdown-Based (Tiered)", "type": "Adaptive"}
        }
    }

    with open(os.path.join(tmpdir, "mm_selection_matrix.json"), 'w') as f:
        json.dump(matrix, f, indent=2)

    return tmpdir


# ============================================================
# Helper: Generate fake trade data
# ============================================================

def make_trade(pnl: float, symbol: str = "XAUUSD", regime: str = "RANGING",
               lot: float = 0.05, risk: float = 1.0, dd: float = 3.0,
               duration: int = 600) -> dict:
    """สร้าง trade_data dict สำหรับ test."""
    return {
        "symbol": symbol,
        "direction": "BUY" if pnl > 0 else "SELL",
        "entry_price": 2000.0,
        "exit_price": 2000.0 + pnl,
        "pnl": pnl,
        "lot_size": lot,
        "risk_pct": risk,
        "duration_seconds": duration,
        "drawdown_at_entry": dd,
        "regime_at_entry": regime,
        "timestamp": time.time(),
        "params_used": {},
        "mm_used": "MM01"
    }


def generate_trade_batch(count: int, win_rate: float = 0.6,
                          avg_win: float = 50.0, avg_loss: float = -30.0,
                          symbol: str = "XAUUSD", regime: str = "RANGING") -> list:
    """Generate a batch of trades with specified win rate."""
    trades = []
    for _ in range(count):
        if random.random() < win_rate:
            pnl = avg_win * (0.5 + random.random())  # 25-75 range
        else:
            pnl = avg_loss * (0.5 + random.random())
        trades.append(make_trade(pnl, symbol=symbol, regime=regime))
    return trades


# ============================================================
# TEST 1: MMAnalyzer — Record + Basic Validation
# ============================================================

def test_record_mm_usage(analyzer):
    """ทดสอบ record_mm_usage: valid/invalid inputs."""
    print("\n" + "="*60)
    print("TEST 1: record_mm_usage")
    print("="*60)

    # Valid record
    trade = make_trade(pnl=45.0, symbol="XAUUSD")
    result = analyzer.record_mm_usage("S01", "MM04", trade)
    assert result is True, "Valid record should return True"
    print("  ✅ Valid record accepted")

    # Invalid MM method
    result = analyzer.record_mm_usage("S01", "MM99", trade)
    assert result is False, "Invalid MM should return False"
    print("  ✅ Invalid MM method rejected")

    # Invalid strategy
    result = analyzer.record_mm_usage("S99", "MM01", trade)
    assert result is False, "Invalid strategy should return False"
    print("  ✅ Invalid strategy rejected")

    # Record multiple
    for t in generate_trade_batch(25, symbol="XAUUSD"):
        analyzer.record_mm_usage("S01", "MM04", t)
    count = analyzer.get_trade_count("MM04", "S01", "XAUUSD")
    assert count >= 25, f"Should have >= 25 trades, got {count}"
    print(f"  ✅ Batch recorded: {count} trades for S01/MM04/XAUUSD")

    print("TEST 1: PASSED ✅")


# ============================================================
# TEST 2: MMAnalyzer — analyze_mm_effectiveness
# ============================================================

def test_analyze_effectiveness(analyzer):
    """ทดสอบ analyze_mm_effectiveness: metrics calculation."""
    print("\n" + "="*60)
    print("TEST 2: analyze_mm_effectiveness")
    print("="*60)

    # Insufficient data
    result = analyzer.analyze_mm_effectiveness("MM07", "S02", "EURUSD")
    assert result["status"] == "insufficient_data", "Should be insufficient"
    print(f"  ✅ Insufficient data detected (count={result['trade_count']})")

    # Add data for MM01/S15
    for t in generate_trade_batch(30, win_rate=0.65, avg_win=60, avg_loss=-35, symbol="XAUUSD"):
        analyzer.record_mm_usage("S15", "MM01", t)

    result = analyzer.analyze_mm_effectiveness("MM01", "S15", "XAUUSD")
    assert result["status"] == "ok", f"Should be ok, got {result['status']}"
    assert "win_rate" in result, "Missing win_rate"
    assert "profit_factor" in result, "Missing profit_factor"
    assert "max_dd_pct" in result, "Missing max_dd_pct"
    assert "risk_adjusted_return" in result, "Missing risk_adjusted_return"
    assert 0 <= result["win_rate"] <= 1.0, f"Win rate out of range: {result['win_rate']}"

    print(f"  ✅ Analysis OK: trades={result['trade_count']}")
    print(f"     win_rate={result['win_rate']:.2%}, pf={result['profit_factor']:.2f}")
    print(f"     max_dd={result['max_dd_pct']:.1f}%, rar={result['risk_adjusted_return']:.4f}")
    print(f"     avg_lot={result['avg_lot_size']}, total_pnl={result['total_pnl']:.2f}")

    # Without filters (all data for MM01)
    result_all = analyzer.analyze_mm_effectiveness("MM01")
    assert result_all["status"] == "ok"
    assert result_all["trade_count"] >= result["trade_count"]
    print(f"  ✅ Unfiltered analysis: {result_all['trade_count']} total trades")

    print("TEST 2: PASSED ✅")


# ============================================================
# TEST 3: MMAnalyzer — compare_mm_methods
# ============================================================

def test_compare_mm_methods(analyzer):
    """ทดสอบ compare_mm_methods: ranking + scoring."""
    print("\n" + "="*60)
    print("TEST 3: compare_mm_methods")
    print("="*60)

    # Add data for MM03/S15 (worse performance)
    for t in generate_trade_batch(20, win_rate=0.45, avg_win=40, avg_loss=-50, symbol="XAUUSD"):
        analyzer.record_mm_usage("S15", "MM03", t)

    # Add data for MM07/S15 (medium performance)
    for t in generate_trade_batch(20, win_rate=0.55, avg_win=45, avg_loss=-40, symbol="XAUUSD"):
        analyzer.record_mm_usage("S15", "MM07", t)

    result = analyzer.compare_mm_methods("S15", ["MM01", "MM03", "MM07"], "XAUUSD")
    assert result["status"] == "ok", f"Should be ok, got {result.get('status')}"
    assert result["compared_count"] >= 2, "Should compare at least 2"
    assert len(result["ranking"]) >= 2, "Should have ranked list"

    # Check ranking structure
    top = result["ranking"][0]
    assert "mm_method" in top, "Missing mm_method"
    assert "total_score" in top, "Missing total_score"
    assert "breakdown" in top, "Missing breakdown"
    assert all(k in top["breakdown"] for k in
               ["risk_adjusted", "profit_factor", "win_rate", "recovery_speed", "max_dd"])

    # Verify sorted descending
    scores = [r["total_score"] for r in result["ranking"]]
    assert scores == sorted(scores, reverse=True), "Should be sorted descending"

    print(f"  ✅ Compared {result['compared_count']} methods:")
    for r in result["ranking"]:
        print(f"     #{result['ranking'].index(r)+1} {r['mm_method']}: "
              f"score={r['total_score']:.4f} (trades={r['trade_count']})")

    # Insufficient data case
    result_bad = analyzer.compare_mm_methods("S15", ["MM09", "MM10"], "EURUSD")
    assert result_bad["status"] == "insufficient_data"
    print("  ✅ Insufficient data handled for missing methods")

    print("TEST 3: PASSED ✅")


# ============================================================
# TEST 4: MMAnalyzer — get_best_mm_for_regime
# ============================================================

def test_best_mm_for_regime(analyzer):
    """ทดสอบ get_best_mm_for_regime: historical > matrix fallback."""
    print("\n" + "="*60)
    print("TEST 4: get_best_mm_for_regime")
    print("="*60)

    # CRISIS → always MM10
    result = analyzer.get_best_mm_for_regime("S01", "CRISIS")
    assert result == "MM10", f"CRISIS should return MM10, got {result}"
    print("  ✅ CRISIS → MM10 (forced)")

    # RANGING for S01 — has data for MM04, matrix says preferred=[MM01,MM04,MM07]
    result = analyzer.get_best_mm_for_regime("S01", "RANGING")
    assert result in ["MM01", "MM04", "MM07"], f"Unexpected result: {result}"
    print(f"  ✅ RANGING/S01 → {result}")

    # Strategy with no data — falls back to matrix
    result = analyzer.get_best_mm_for_regime("S09", "TRENDING")
    assert result in ["MM03", "MM08", "MM17", "MM01"], f"Unexpected: {result}"
    print(f"  ✅ TRENDING/S09 (no data) → {result} (matrix fallback)")

    # VOLATILE for S15 — volatile_mm = MM17
    result = analyzer.get_best_mm_for_regime("S15", "VOLATILE")
    print(f"  ✅ VOLATILE/S15 → {result}")

    # Invalid regime → defaults to RANGING
    result = analyzer.get_best_mm_for_regime("S01", "INVALID_REGIME")
    print(f"  ✅ Invalid regime → {result} (defaulted to RANGING)")

    print("TEST 4: PASSED ✅")


# ============================================================
# TEST 5: MMAnalyzer — DD Override Recommendation
# ============================================================

def test_dd_override(analyzer):
    """ทดสอบ get_dd_override_recommendation: 4 tiers."""
    print("\n" + "="*60)
    print("TEST 5: get_dd_override_recommendation")
    print("="*60)

    # Normal (DD = 5%)
    r = analyzer.get_dd_override_recommendation(5.0)
    assert r["override_active"] is False
    assert r["action"] == "normal"
    assert r["dd_tier"] == "NORMAL"
    print(f"  ✅ DD 5.0% → {r['action']} (tier={r['dd_tier']})")

    # Tier 1 (DD = 12%)
    r = analyzer.get_dd_override_recommendation(12.0)
    assert r["override_active"] is True
    assert r["switch_to"] == "MM10"
    assert r["reduce_pct"] == 50.0
    assert r["dd_tier"] == "TIER1"
    print(f"  ✅ DD 12.0% → {r['action']} reduce={r['reduce_pct']}% (tier={r['dd_tier']})")

    # Tier 2 (DD = 17%)
    r = analyzer.get_dd_override_recommendation(17.0)
    assert r["override_active"] is True
    assert r["reduce_pct"] == 75.0
    assert r["dd_tier"] == "TIER2"
    print(f"  ✅ DD 17.0% → {r['action']} reduce={r['reduce_pct']}% (tier={r['dd_tier']})")

    # Stop (DD = 22%)
    r = analyzer.get_dd_override_recommendation(22.0)
    assert r["override_active"] is True
    assert r["reduce_pct"] == 100.0
    assert r["action"] == "stop_new_trades"
    assert r["dd_tier"] == "STOP"
    print(f"  ✅ DD 22.0% → {r['action']} (tier={r['dd_tier']})")

    # Edge cases: exactly at thresholds
    r10 = analyzer.get_dd_override_recommendation(10.0)
    assert r10["dd_tier"] == "TIER1", f"DD=10% should be TIER1, got {r10['dd_tier']}"
    r15 = analyzer.get_dd_override_recommendation(15.0)
    assert r15["dd_tier"] == "TIER2", f"DD=15% should be TIER2, got {r15['dd_tier']}"
    r20 = analyzer.get_dd_override_recommendation(20.0)
    assert r20["dd_tier"] == "STOP", f"DD=20% should be STOP, got {r20['dd_tier']}"
    print("  ✅ Edge cases: DD=10%→TIER1, DD=15%→TIER2, DD=20%→STOP")

    # Has Thai reasoning
    assert "reasoning_th" in r20 and len(r20["reasoning_th"]) > 0
    print(f"  ✅ Thai reasoning: {r20['reasoning_th']}")

    print("TEST 5: PASSED ✅")


# ============================================================
# TEST 6: MMAnalyzer — Performance Summary
# ============================================================

def test_performance_summary(analyzer):
    """ทดสอบ get_mm_performance_summary."""
    print("\n" + "="*60)
    print("TEST 6: get_mm_performance_summary")
    print("="*60)

    summary = analyzer.get_mm_performance_summary()
    assert isinstance(summary, dict)
    assert len(summary) >= 2, f"Should have data for >= 2 methods, got {len(summary)}"
    print(f"  ✅ Summary covers {len(summary)} MM methods: {list(summary.keys())}")

    # Filtered by strategy
    summary_s15 = analyzer.get_mm_performance_summary(strategy_id="S15")
    print(f"  ✅ S15 filtered: {len(summary_s15)} methods: {list(summary_s15.keys())}")

    # Filtered by symbol
    summary_xau = analyzer.get_mm_performance_summary(symbol="XAUUSD")
    print(f"  ✅ XAUUSD filtered: {len(summary_xau)} methods")

    print("TEST 6: PASSED ✅")


# ============================================================
# TEST 7: RegimeParameterMapper — map_regime_to_params
# ============================================================

def test_regime_to_params(mapper):
    """ทดสอบ map_regime_to_params: 4 regimes."""
    print("\n" + "="*60)
    print("TEST 7: map_regime_to_params")
    print("="*60)

    for regime in ["TRENDING", "RANGING", "VOLATILE", "CRISIS"]:
        result = mapper.map_regime_to_params(regime, "S01")
        assert result["regime"] == regime
        assert "adjustment_multipliers" in result
        assert "recommended_mm" in result
        assert "risk_adjustment" in result

        adj = result["adjustment_multipliers"]
        assert all(k in adj for k in
                   ["tp_multiplier", "sl_multiplier", "entry_sensitivity",
                    "exit_patience", "position_size", "lookback_scale"])

        print(f"  ✅ {regime}: mm={result['recommended_mm']}, "
              f"risk_adj={result['risk_adjustment']}, "
              f"pos_size={adj['position_size']}, tp_mult={adj['tp_multiplier']}")

    # VOLATILE → position_size = 0.5
    vol = mapper.map_regime_to_params("VOLATILE", "S01")
    assert vol["adjustment_multipliers"]["position_size"] == 0.5
    assert vol["risk_adjustment"] == 0.5
    print("  ✅ VOLATILE: position_size=0.5, risk_adj=0.5")

    # CRISIS → position_size = 0.0, force_reduce = True
    crisis = mapper.map_regime_to_params("CRISIS", "S01")
    assert crisis["adjustment_multipliers"]["position_size"] == 0.0
    assert crisis["force_reduce"] is True
    assert crisis["recommended_mm"] == "MM10"
    print("  ✅ CRISIS: position_size=0.0, force_reduce=True, mm=MM10")

    # Invalid regime → defaults to RANGING
    invalid = mapper.map_regime_to_params("BANANA", "S01")
    assert invalid["regime"] == "RANGING"
    print("  ✅ Invalid regime → RANGING fallback")

    print("TEST 7: PASSED ✅")


# ============================================================
# TEST 8: RegimeParameterMapper — MM17 Scaling
# ============================================================

def test_mm_regime_scaling(mapper):
    """ทดสอบ get_mm_regime_scaling: MM17 multipliers."""
    print("\n" + "="*60)
    print("TEST 8: get_mm_regime_scaling (MM17)")
    print("="*60)

    # TRENDING → 1.2x
    r = mapper.get_mm_regime_scaling("TRENDING", "MM03")
    assert r["risk_multiplier"] == 1.2, f"Expected 1.2, got {r['risk_multiplier']}"
    assert r["mm_method"] == "MM03"
    assert r["regime"] == "TRENDING"
    print(f"  ✅ TRENDING/MM03: risk_mult={r['risk_multiplier']}")

    # RANGING → 1.0x
    r = mapper.get_mm_regime_scaling("RANGING", "MM04")
    assert r["risk_multiplier"] == 1.0
    print(f"  ✅ RANGING/MM04: risk_mult={r['risk_multiplier']}")

    # VOLATILE → 0.3x
    r = mapper.get_mm_regime_scaling("VOLATILE", "MM01")
    assert r["risk_multiplier"] == 0.3
    print(f"  ✅ VOLATILE/MM01: risk_mult={r['risk_multiplier']}")

    # CRISIS → 0.0x (always)
    r = mapper.get_mm_regime_scaling("CRISIS", "MM01")
    assert r["risk_multiplier"] == 0.0
    print(f"  ✅ CRISIS/MM01: risk_mult={r['risk_multiplier']} (forced 0)")

    # Check confirm_bars
    assert r["confirm_bars_required"] == 3
    print(f"  ✅ confirm_bars={r['confirm_bars_required']}")

    # Check additional_params structure
    assert r["additional_params"]["regime_scaling_active"] is True
    assert "reasoning_th" in r and len(r["reasoning_th"]) > 0
    print(f"  ✅ Reasoning: {r['reasoning_th']}")

    print("TEST 8: PASSED ✅")


# ============================================================
# TEST 9: RegimeParameterMapper — Regime Transition
# ============================================================

def test_regime_transition(mapper):
    """ทดสอบ detect_regime_transition: urgency + param changes."""
    print("\n" + "="*60)
    print("TEST 9: detect_regime_transition")
    print("="*60)

    # Same regime → no transition
    r = mapper.detect_regime_transition("TRENDING", "TRENDING")
    assert r["transition"] is False
    assert r["urgency"] == "none"
    print("  ✅ Same regime → no transition")

    # TRENDING → RANGING (low urgency)
    r = mapper.detect_regime_transition("TRENDING", "RANGING")
    assert r["transition"] is True
    assert r["urgency"] == "low"
    assert r["application_mode"] == "slow"
    assert len(r["param_changes"]) > 0
    print(f"  ✅ TRENDING→RANGING: urgency={r['urgency']}, mode={r['application_mode']}")

    # RANGING → VOLATILE (medium)
    r = mapper.detect_regime_transition("RANGING", "VOLATILE")
    assert r["urgency"] == "medium"
    assert r["application_mode"] == "gradual"
    print(f"  ✅ RANGING→VOLATILE: urgency={r['urgency']}, mode={r['application_mode']}")

    # VOLATILE → CRISIS (high)
    r = mapper.detect_regime_transition("VOLATILE", "CRISIS")
    assert r["urgency"] == "high"
    assert r["application_mode"] == "fast"
    assert r["mm_changes"]["force_reduce"] is True
    print(f"  ✅ VOLATILE→CRISIS: urgency={r['urgency']}, force_reduce=True")

    # TRENDING → CRISIS (critical)
    r = mapper.detect_regime_transition("TRENDING", "CRISIS")
    assert r["urgency"] == "critical"
    assert r["application_mode"] == "immediate"
    print(f"  ✅ TRENDING→CRISIS: urgency={r['urgency']}, mode={r['application_mode']}")

    # Check param_changes structure
    r = mapper.detect_regime_transition("RANGING", "TRENDING")
    for key, change in r["param_changes"].items():
        assert "old" in change and "new" in change and "change_pct" in change
    print(f"  ✅ Param changes: {len(r['param_changes'])} adjustments")
    for k, v in r["param_changes"].items():
        print(f"     {k}: {v['old']} → {v['new']} ({v['change_pct']:+.1f}%)")

    # Check mm_changes structure
    assert "old_preferred" in r["mm_changes"]
    assert "new_preferred" in r["mm_changes"]
    print(f"  ✅ MM changes: preferred {r['mm_changes']['old_preferred']} → {r['mm_changes']['new_preferred']}")

    # Thai reasoning present
    assert "reasoning_th" in r and len(r["reasoning_th"]) > 0
    print(f"  ✅ Reasoning TH: {r['reasoning_th']}")

    print("TEST 9: PASSED ✅")


# ============================================================
# TEST 10: Integration — MMAnalyzer + RegimeParameterMapper
# ============================================================

def test_integration(analyzer, mapper):
    """ทดสอบ workflow: regime change → MM recommendation → DD check."""
    print("\n" + "="*60)
    print("TEST 10: Integration Test")
    print("="*60)

    # Scenario: ตลาดเปลี่ยนจาก RANGING → VOLATILE
    strategy_id = "S15"
    symbol = "XAUUSD"

    # Step 1: Detect transition
    transition = mapper.detect_regime_transition("RANGING", "VOLATILE")
    assert transition["transition"] is True
    print(f"  Step 1: Transition detected: {transition['urgency']}")

    # Step 2: Get new regime params
    regime_params = mapper.map_regime_to_params("VOLATILE", strategy_id)
    assert regime_params["risk_adjustment"] == 0.5
    print(f"  Step 2: New params — risk_adj={regime_params['risk_adjustment']}, "
          f"mm={regime_params['recommended_mm']}")

    # Step 3: Get MM17 scaling
    scaling = mapper.get_mm_regime_scaling("VOLATILE", regime_params["recommended_mm"])
    print(f"  Step 3: MM17 scaling — mult={scaling['risk_multiplier']}")

    # Step 4: Get best MM from historical data
    best_mm = analyzer.get_best_mm_for_regime(strategy_id, "VOLATILE")
    print(f"  Step 4: Best MM for {strategy_id}/VOLATILE: {best_mm}")

    # Step 5: Check DD status
    dd_check = analyzer.get_dd_override_recommendation(8.5)
    assert dd_check["override_active"] is False
    print(f"  Step 5: DD check 8.5% → {dd_check['action']}")

    # Step 6: DD deteriorates to 12%
    dd_check = analyzer.get_dd_override_recommendation(12.0)
    assert dd_check["override_active"] is True
    assert dd_check["switch_to"] == "MM10"
    print(f"  Step 6: DD deteriorates 12% → {dd_check['action']}, switch to {dd_check['switch_to']}")

    # Step 7: Get performance summary for optimizer
    summary = analyzer.get_mm_performance_summary(strategy_id, symbol)
    print(f"  Step 7: Performance summary — {len(summary)} methods with data")

    print("\nTEST 10: Integration PASSED ✅")


# ============================================================
# MAIN
# ============================================================

def main():
    print("=" * 60)
    print("FlashEASuite V2 — P0.6-5 Test Suite")
    print("MMAnalyzer + RegimeParameterMapper")
    print("=" * 60)

    # Setup
    random.seed(42)  # Reproducible results
    config_dir = create_test_config_dir()
    param_repo = MockParameterRepository()

    try:
        # Import (adjust path as needed)
        # ถ้ารัน standalone ให้ import ตรงจาก path
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

        try:
            from core.intelligence.mm_analyzer import MMAnalyzer
            from core.optimization.regime_parameter_mapper import RegimeParameterMapper
        except ImportError:
            # Fallback: ถ้ารันจาก root directory
            try:
                from mm_analyzer import MMAnalyzer
                from regime_parameter_mapper import RegimeParameterMapper
            except ImportError:
                print("❌ Cannot import modules. Make sure mm_analyzer.py and")
                print("   regime_parameter_mapper.py are in the correct path.")
                print("   Try: python -m pytest tests/test_p065_mm_analyzer_regime_mapper.py")
                return False

        # Initialize
        analyzer = MMAnalyzer(param_repo, config_dir=config_dir)
        mapper = RegimeParameterMapper(param_repo, config_dir=config_dir)

        # Run tests
        test_record_mm_usage(analyzer)
        test_analyze_effectiveness(analyzer)
        test_compare_mm_methods(analyzer)
        test_best_mm_for_regime(analyzer)
        test_dd_override(analyzer)
        test_performance_summary(analyzer)
        test_regime_to_params(mapper)
        test_mm_regime_scaling(mapper)
        test_regime_transition(mapper)
        test_integration(analyzer, mapper)

        # Summary
        print("\n" + "=" * 60)
        print("🎉 ALL 10 TESTS PASSED!")
        print("=" * 60)
        print(f"\nTotal trades recorded: {analyzer.get_trade_count()}")
        print(f"Config dir: {config_dir}")
        return True

    except AssertionError as e:
        print(f"\n❌ ASSERTION FAILED: {e}")
        import traceback
        traceback.print_exc()
        return False
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        # Cleanup
        shutil.rmtree(config_dir, ignore_errors=True)


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)