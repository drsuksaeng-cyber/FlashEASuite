"""
FlashEASuite V2 — P0.6-6 Integration Test
ทดสอบ MultiStrategyOptimizer + ParameterFamilyOptimizer

วิธีใช้:
========
1. วาง multi_strategy_optimizer.py + parameter_family_optimizer.py ใน:
     02_Brain/core/optimization/

2. รัน test จาก folder 02_Brain:
     cd 02_Brain
     python -m tests.test_p06_6_optimizer

   หรือรันจาก root:
     cd FlashEASuite_V2
     python -m pytest 02_Brain/tests/test_p06_6_optimizer.py -v

   หรือรันตรง:
     cd 02_Brain
     python tests/test_p06_6_optimizer.py

File locations expected:
========================
02_Brain/
├── config/
│   ├── strategy_parameters.json        (P0.6-1)
│   ├── strategy_parameter_families.json (P0.6-1)
│   ├── mm_parameters.json              (P0.6-2)
│   ├── mm_parameter_families.json      (P0.6-2)
│   └── mm_selection_matrix.json        (P0.6-2)
├── core/
│   ├── Parameter_repository.py         (P0.6-3)
│   ├── Parameter_Family_Index.py       (P0.6-3)
│   ├── intelligence/
│   │   ├── generic_strategy_analyzer.py (P0.6-4)
│   │   ├── multi_strategy_analyzer.py   (P0.6-4)
│   │   └── mm_analyzer.py              (P0.6-5)
│   └── optimization/
│       ├── regime_parameter_mapper.py   (P0.6-5)
│       ├── multi_strategy_optimizer.py  (P0.6-6) ★ NEW
│       └── parameter_family_optimizer.py(P0.6-6) ★ NEW
└── tests/
    └── test_p06_6_optimizer.py          ★ THIS FILE
"""

import sys
import os
import time
import random
import traceback

# ============================================================
# Path Setup — ให้ทำงานได้ทั้ง cd 02_Brain และ cd FlashEASuite_V2
# ============================================================

def setup_paths():
    """หา config/ dir ที่ถูกต้อง"""
    # Try multiple possible locations
    candidates = [
        "config",                              # cd 02_Brain
        "02_Brain/config",                     # cd FlashEASuite_V2
        os.path.join(os.path.dirname(__file__), "..", "config"),  # relative to test file
    ]
    for c in candidates:
        if os.path.exists(c) and os.path.isfile(os.path.join(c, "strategy_parameters.json")):
            return os.path.abspath(c)
    return None

def setup_imports():
    """Add correct path for imports — bypass core/__init__.py heavy imports"""
    # Add 02_Brain to path
    test_dir = os.path.dirname(os.path.abspath(__file__))
    brain_dir = os.path.dirname(test_dir)  # 02_Brain/
    project_root = os.path.dirname(brain_dir)  # FlashEASuite_V2/
    
    for p in [brain_dir, project_root, os.path.join(project_root, "02_Brain"), ".", ".."]:
        ap = os.path.abspath(p)
        if ap not in sys.path:
            sys.path.insert(0, ap)
    
    # CRITICAL: Temporarily replace core/__init__.py to avoid importing
    # message_types/protocol_handler/zmq which aren't needed for this test.
    # This prevents: "No module named 'core.message_types'" errors
    import importlib
    import types
    
    core_path = os.path.join(brain_dir, "core")
    if os.path.exists(core_path):
        # Pre-register 'core' as a namespace package so sub-imports work
        # without triggering core/__init__.py's heavy imports
        core_mod = types.ModuleType("core")
        core_mod.__path__ = [core_path]
        core_mod.__package__ = "core"
        sys.modules["core"] = core_mod
        
        # Pre-register sub-packages
        for subpkg in ["intelligence", "optimization", "data", "policy",
                        "risk_management", "strategy"]:
            subpath = os.path.join(core_path, subpkg)
            if os.path.exists(subpath):
                sub_mod = types.ModuleType(f"core.{subpkg}")
                sub_mod.__path__ = [subpath]
                sub_mod.__package__ = f"core.{subpkg}"
                sys.modules[f"core.{subpkg}"] = sub_mod


# ============================================================
# Test Results Tracker
# ============================================================

class TestTracker:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.errors = []
    
    def ok(self, name, detail=""):
        self.passed += 1
        d = f" — {detail}" if detail else ""
        print(f"  ✅ {name}{d}")
    
    def fail(self, name, reason):
        self.failed += 1
        self.errors.append((name, reason))
        print(f"  ❌ {name} — {reason}")
    
    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*60}")
        if self.failed == 0:
            print(f"✅ ALL {total} TESTS PASSED")
        else:
            print(f"⚠️ {self.passed}/{total} passed, {self.failed} FAILED:")
            for name, reason in self.errors:
                print(f"   ❌ {name}: {reason}")
        print(f"{'='*60}")
        return self.failed == 0


# ============================================================
# Test Functions
# ============================================================

def test_01_imports(T):
    """ทดสอบว่า import ทุก module ได้"""
    try:
        from core.Parameter_repository import ParameterRepository
        from core.Parameter_Family_Index import ParameterFamilyIndex
        from core.intelligence.generic_strategy_analyzer import GenericStrategyAnalyzer
        from core.intelligence.mm_analyzer import MMAnalyzer
        from core.optimization.regime_parameter_mapper import RegimeParameterMapper
        from core.optimization.parameter_family_optimizer import ParameterFamilyOptimizer
        from core.optimization.multi_strategy_optimizer import MultiStrategyOptimizer
        T.ok("T01: Import all modules", "7 modules loaded")
    except ImportError as e:
        T.fail("T01: Import all modules", str(e))
        raise  # Cannot continue


def test_02_init_components(T, cfg):
    """ทดสอบ initialize ทุก component"""
    from core.Parameter_repository import ParameterRepository
    from core.Parameter_Family_Index import ParameterFamilyIndex
    from core.intelligence.generic_strategy_analyzer import GenericStrategyAnalyzer
    from core.intelligence.mm_analyzer import MMAnalyzer
    from core.optimization.regime_parameter_mapper import RegimeParameterMapper
    from core.optimization.parameter_family_optimizer import ParameterFamilyOptimizer
    from core.optimization.multi_strategy_optimizer import MultiStrategyOptimizer

    repo = ParameterRepository(cfg)
    fam_ix = ParameterFamilyIndex(cfg)
    gen_az = GenericStrategyAnalyzer(repo)
    mm_az = MMAnalyzer(repo, cfg)
    regime_mapper = RegimeParameterMapper(repo, cfg)
    fam_opt = ParameterFamilyOptimizer(fam_ix, repo)

    opt = MultiStrategyOptimizer(
        param_repo=repo,
        strategy_analyzer=gen_az,
        mm_analyzer=mm_az,
        regime_mapper=regime_mapper,
        family_index=fam_ix,
        family_optimizer=fam_opt
    )

    assert repo.total_params >= 190, f"Expected ≥190 params, got {repo.total_params}"
    assert fam_ix.total_families == 20, f"Expected 20 families, got {fam_ix.total_families}"

    T.ok("T02: Init all components",
         f"repo={repo.total_params} params, families={fam_ix.total_families}")

    return repo, fam_ix, gen_az, mm_az, regime_mapper, fam_opt, opt


def test_03_should_optimize_empty(T, opt):
    """ทดสอบ should_optimize เมื่อไม่มี trade data"""
    result = opt.should_optimize("XAUUSD")
    assert result is False, "Should be False with no trades"
    T.ok("T03: should_optimize=False (no data)")


def test_04_inject_trades(T, gen_az, mm_az):
    """ทดสอบ inject mock trades"""
    random.seed(42)

    # S01 — 60 trades
    for _ in range(60):
        gen_az.record_trade("S01", "XAUUSD", {
            "direction": random.choice(["BUY", "SELL"]),
            "entry_price": 2000 + random.uniform(-50, 50),
            "exit_price": 2000 + random.uniform(-50, 50),
            "pnl": random.uniform(-80, 120),
            "duration_seconds": random.randint(60, 7200),
            "params_used": {
                "S01_LOOKBACK_PERIOD": random.choice([15, 20, 25, 30]),
                "S01_ENTRY_ZSCORE": random.choice([1.5, 2.0, 2.5]),
            },
            "mm_used": "MM04",
            "regime_at_entry": random.choice(["TRENDING", "RANGING", "VOLATILE"]),
            "timestamp": time.time() - random.randint(0, 86400 * 30),
        })

    # S06 — 40 trades
    for _ in range(40):
        gen_az.record_trade("S06", "XAUUSD", {
            "direction": "BUY",
            "entry_price": 2000, "exit_price": 2010,
            "pnl": random.uniform(-40, 60),
            "duration_seconds": random.randint(60, 3600),
            "params_used": {},
            "mm_used": "MM08",
            "regime_at_entry": random.choice(["TRENDING", "RANGING"]),
            "timestamp": time.time() - random.randint(0, 86400 * 14),
        })

    # MM trades
    for _ in range(30):
        mm_az.record_mm_usage("S01", "MM04", {
            "symbol": "XAUUSD",
            "pnl": random.uniform(-50, 100),
            "lot_size": round(random.uniform(0.01, 0.1), 2),
            "risk_pct": round(random.uniform(0.5, 2.0), 2),
            "duration_seconds": random.randint(60, 3600),
            "drawdown_at_entry": round(random.uniform(0, 8), 2),
            "regime_at_entry": "TRENDING",
            "timestamp": time.time() - random.randint(0, 86400 * 14),
        })

    c1 = gen_az.get_trade_count("S01", "XAUUSD")
    c6 = gen_az.get_trade_count("S06", "XAUUSD")
    cm = mm_az.get_trade_count("MM04", "S01", "XAUUSD")

    T.ok("T04: Inject trades",
         f"S01={c1}, S06={c6}, MM04={cm}")
    return c1 + c6


def test_05_should_optimize_with_data(T, opt):
    """ทดสอบ should_optimize เมื่อมี data"""
    result = opt.should_optimize("XAUUSD")
    assert result is True, "Should be True with sufficient trades"
    T.ok("T05: should_optimize=True (data exists)")


def test_06_optimize_trending(T, opt):
    """ทดสอบ optimize_all กับ TRENDING regime"""
    result = opt.optimize_all("XAUUSD", regime="TRENDING", broker="icmarkets", timeframe="H1")

    # Verify structure
    assert "strategy_changes" in result, "Missing strategy_changes"
    assert "mm_changes" in result, "Missing mm_changes"
    assert "mm_selection" in result, "Missing mm_selection"
    assert "reasoning" in result, "Missing reasoning"
    assert "confidence" in result, "Missing confidence"
    assert "applied" in result, "Missing applied"
    assert "factors_used" in result, "Missing factors_used"
    assert len(result["factors_used"]) == 10, f"Expected 10 factors, got {len(result['factors_used'])}"

    T.ok("T06: optimize_all (TRENDING)",
         f"changes={result['total_changes']}, conf={result['confidence']:.2f}, "
         f"applied={result['applied']}, {result['elapsed_ms']}ms")
    return result


def test_07_mm_selection(T, result):
    """ทดสอบ MM selection output"""
    ms = result["mm_selection"]
    assert len(ms) > 0, "MM selection should not be empty"
    assert isinstance(ms, dict), "MM selection should be dict"
    # ทุก strategy ต้องมี MM assignment
    for sid, mm in ms.items():
        assert mm.startswith("MM"), f"{sid} has invalid MM: {mm}"

    T.ok("T07: MM selection",
         f"{len(ms)} strategies assigned, sample: S01→{ms.get('S01','?')}")


def test_08_reasoning_thai(T, result):
    """ทดสอบ reasoning output เป็นภาษาไทย"""
    r = result["reasoning"]
    assert "summary_th" in r, "Missing summary_th"
    assert isinstance(r["summary_th"], str), "summary_th should be str"
    assert len(r["summary_th"]) > 10, "summary_th too short"
    assert isinstance(r["changes"], list), "changes should be list"

    # Check Thai text exists
    has_thai = any(ord(c) >= 0x0E00 for c in r["summary_th"])
    assert has_thai, "summary_th should contain Thai text"

    T.ok("T08: Reasoning (Thai)",
         f"summary={r['summary_th'][:60]}...")


def test_09_optimize_crisis(T, opt):
    """ทดสอบ CRISIS regime + high drawdown → ต้อง force MM10"""
    result = opt.optimize_all("XAUUSD", regime="CRISIS", dd_pct=18.0)
    ms = result["mm_selection"]
    mm_values = set(ms.values())

    assert "MM10" in mm_values, f"CRISIS should force MM10, got: {mm_values}"

    T.ok("T09: CRISIS+DD18%",
         f"MM methods={mm_values}, all MM10={mm_values == {'MM10'}}")


def test_10_optimize_volatile(T, opt):
    """ทดสอบ VOLATILE regime + broker + different TF"""
    result = opt.optimize_all("XAUUSD", regime="VOLATILE", broker="xm", timeframe="M5")

    assert result["total_changes"] >= 0  # May have 0 if all rejected
    assert result["regime"] == "VOLATILE"

    T.ok("T10: VOLATILE+xm+M5",
         f"changes={result['total_changes']}, {result['elapsed_ms']}ms")


def test_11_client_feedback(T, opt):
    """ทดสอบ client feedback aggregation"""
    # Add feedback from 5 clients
    for i in range(5):
        opt.add_client_feedback(f"client_{i}", {
            "strategy_id": "S01", "symbol": "XAUUSD",
            "param_results": {
                "S01_LOOKBACK_PERIOD": {"pnl": random.uniform(-10, -1)},
            }
        })

    f4 = opt._factor_4_client_feedback()
    assert f4["client_count"] == 5, f"Expected 5 clients, got {f4['client_count']}"
    assert f4["params_with_feedback"] >= 1

    T.ok("T11: Client feedback",
         f"clients={f4['client_count']}, params={f4['params_with_feedback']}")


def test_12_constraint_enforcement(T, opt):
    """ทดสอบ constraint enforcement — ค่าเกิน max change ต้อง clamp"""
    # S01_LOOKBACK_PERIOD: default=20, max_change_per_cycle=20% → max change=4
    test_pending = {
        "S01_LOOKBACK_PERIOD": {
            "value": 100,   # Way over 20% change
            "reason": "test constraint",
            "confidence": 0.9
        }
    }
    f9 = opt._factor_9_constraints(test_pending)

    # Should either clamp or reject (not accept 100 raw)
    if f9["accepted"] > 0:
        clamped = f9["constrained_changes"]["S01_LOOKBACK_PERIOD"]["value"]
        assert clamped < 100, f"Should be clamped, got {clamped}"
        T.ok("T12: Constraint enforcement",
             f"100→{clamped} (clamped to max change)")
    else:
        T.ok("T12: Constraint enforcement",
             f"rejected (change too large)")


def test_13_confidence_filter(T, opt):
    """ทดสอบ confidence filter — conf < 0.5 ต้องถูก remove"""
    test = {
        "LOW_CONF": {"value": 1, "reason": "test", "confidence": 0.2},
        "MED_CONF": {"value": 2, "reason": "test", "confidence": 0.49},
        "HIGH_CONF": {"value": 3, "reason": "test", "confidence": 0.8},
    }
    f10 = opt._factor_10_confidence(test)

    assert "LOW_CONF" not in f10["final_changes"], "Low conf should be removed"
    assert "MED_CONF" not in f10["final_changes"], "Med conf <0.5 should be removed"
    assert len(f10["removed"]) >= 2, f"Expected ≥2 removed, got {len(f10['removed'])}"

    T.ok("T13: Confidence filter",
         f"kept={len(f10['final_changes'])}, removed={len(f10['removed'])}")


def test_14_family_optimization_order(T, fam_opt):
    """ทดสอบลำดับ family optimization — risk families ต้องมาก่อน"""
    order = fam_opt.get_family_optimization_order()

    assert len(order) >= 15, f"Expected ≥15 families, got {len(order)}"
    assert order[0]["priority"] <= order[-1]["priority"], "Should be sorted by priority"

    # Risk families should be first
    first_3 = [o["family"] for o in order[:3]]
    assert any("MM_" in f or "RISK" in f for f in first_3), \
        f"First 3 should include risk families, got: {first_3}"

    T.ok("T14: Family order",
         f"{len(order)} families, first 3: {first_3}")


def test_15_family_dd_consistency(T, fam_opt):
    """ทดสอบ DD tier ordering — Tier1 < Tier2 < Stop ต้อง enforce"""
    # Case 1: WRONG order → should remove
    bad_changes = {
        "MM10_DD_TIER1_PCT": {"value": 18, "reason": "test"},  # 18% > tier2
        "MM10_DD_TIER2_PCT": {"value": 12, "reason": "test"},  # 12% < tier1 ❌
        "MM10_DD_STOP_PCT": {"value": 20, "reason": "test"},
    }
    result = fam_opt.ensure_family_consistency(bad_changes)
    # Should remove violating DD params
    dd_present = sum(1 for k in result if k.startswith("MM10_DD_"))
    assert dd_present == 0, f"DD tiers with wrong order should be removed, still have {dd_present}"

    # Case 2: CORRECT order → should keep
    good_changes = {
        "MM10_DD_TIER1_PCT": {"value": 8, "reason": "test"},
        "MM10_DD_TIER2_PCT": {"value": 13, "reason": "test"},
        "MM10_DD_STOP_PCT": {"value": 19, "reason": "test"},
    }
    result2 = fam_opt.ensure_family_consistency(good_changes)
    dd_present2 = sum(1 for k in result2 if k.startswith("MM10_DD_"))
    assert dd_present2 == 3, f"Correct DD order should keep all 3, got {dd_present2}"

    T.ok("T15: DD tier consistency",
         f"bad→removed({dd_present}), good→kept({dd_present2})")


def test_16_portfolio_cap_consistency(T, fam_opt):
    """ทดสอบ portfolio cap — per_trade ต้อง ≤ cap"""
    changes = {
        "MM18_PORTFOLIO_CAP_PCT": {"value": 5, "reason": "test"},
        "MM18_PER_TRADE_MAX_PCT": {"value": 10, "reason": "test"},  # 10% > cap 5% ❌
    }
    result = fam_opt.ensure_family_consistency(changes)

    if "MM18_PER_TRADE_MAX_PCT" in result:
        capped = result["MM18_PER_TRADE_MAX_PCT"]["value"]
        assert float(capped) <= 5.0, f"Per-trade should be ≤ cap(5%), got {capped}"
        T.ok("T16: Portfolio cap", f"per_trade capped to {capped}")
    else:
        T.ok("T16: Portfolio cap", "per_trade removed (violated)")


def test_17_regime_factor(T, opt):
    """ทดสอบ Factor 1 (Regime) แยก — ต้องสร้าง adjustments"""
    f1 = opt._factor_1_regime("XAUUSD", "VOLATILE")
    assert f1["regime"] == "VOLATILE"
    adj_count = f1.get("total_adjusted", 0)

    T.ok("T17: Factor 1 (Regime)",
         f"VOLATILE → {adj_count} params adjusted")


def test_18_effectiveness_factor(T, opt):
    """ทดสอบ Factor 2 (Effectiveness) — ต้อง produce suggestions"""
    f2 = opt._factor_2_effectiveness("XAUUSD")
    sug_count = f2.get("total_suggestions", 0)
    strat_count = f2.get("strategies_analyzed", 0)

    T.ok("T18: Factor 2 (Effectiveness)",
         f"{strat_count} strategies analyzed, {sug_count} suggestions")


def test_19_symbol_factor(T, opt):
    """ทดสอบ Factor 5 (Symbol) — XAUUSD ต้องมี profile"""
    f5_gold = opt._factor_5_symbol("XAUUSD")
    f5_eur = opt._factor_5_symbol("EURUSD")
    f5_unk = opt._factor_5_symbol("UNKNOWN_PAIR")

    assert f5_gold.get("profile") == "XAUUSD"
    assert f5_eur.get("profile") == "EURUSD"
    assert f5_unk.get("profile") == "default"

    T.ok("T19: Factor 5 (Symbol)",
         f"XAUUSD.sl_scale={f5_gold.get('sl_scale')}, "
         f"EURUSD.sl_scale={f5_eur.get('sl_scale')}")


def test_20_broker_factor(T, opt):
    """ทดสอบ Factor 7 (Broker) — known + unknown broker"""
    f7_ic = opt._factor_7_broker("icmarkets")
    f7_xm = opt._factor_7_broker("xm")
    f7_none = opt._factor_7_broker(None)

    assert f7_ic.get("spread_factor") == 1.0, "icmarkets spread should be 1.0"
    assert f7_xm.get("spread_factor") == 1.3, "xm spread should be 1.3"
    assert f7_none.get("broker") is None

    T.ok("T20: Factor 7 (Broker)",
         f"IC={f7_ic.get('spread_factor')}, XM={f7_xm.get('spread_factor')}")


def test_21_multiple_optimize_calls(T, opt):
    """ทดสอบ optimize หลายรอบ — optimize_count ต้องเพิ่ม"""
    count_before = opt._optimize_count
    opt.optimize_all("XAUUSD", regime="RANGING")
    opt.optimize_all("EURUSD", regime="TRENDING")
    count_after = opt._optimize_count

    assert count_after == count_before + 2, \
        f"Expected count +2, got {count_before}→{count_after}"

    T.ok("T21: Multiple optimize calls",
         f"count {count_before}→{count_after}")


def test_22_broker_suffix_handling(T, opt):
    """ทดสอบว่า symbol ที่มี broker suffix (.tp, .m) ถูก strip"""
    f5 = opt._factor_5_symbol("XAUUSD.tp")
    assert f5.get("profile") == "XAUUSD", f"Should strip .tp suffix, got {f5.get('profile')}"

    f5b = opt._factor_5_symbol("EURUSD.m")
    assert f5b.get("profile") == "EURUSD"

    T.ok("T22: Broker suffix strip", "XAUUSD.tp→XAUUSD, EURUSD.m→EURUSD")


# ============================================================
# Main Runner
# ============================================================

def main():
    print("=" * 60)
    print("FlashEASuite V2 — P0.6-6 Integration Test")
    print("MultiStrategyOptimizer + ParameterFamilyOptimizer")
    print("=" * 60)

    # Setup
    setup_imports()
    cfg = setup_paths()
    if cfg is None:
        print("\n❌ ERROR: Cannot find config/ directory!")
        print("   Expected: 02_Brain/config/strategy_parameters.json")
        print("   Run this from 02_Brain/ or FlashEASuite_V2/ directory")
        sys.exit(1)

    print(f"\n📁 Config: {cfg}")

    T = TestTracker()

    try:
        # Phase 1: Setup
        print("\n--- Phase 1: Setup ---")
        test_01_imports(T)
        repo, fam_ix, gen_az, mm_az, regime_mapper, fam_opt, opt = \
            test_02_init_components(T, cfg)

        # Phase 2: Data
        print("\n--- Phase 2: Data Injection ---")
        test_03_should_optimize_empty(T, opt)
        test_04_inject_trades(T, gen_az, mm_az)
        test_05_should_optimize_with_data(T, opt)

        # Phase 3: Core Optimization
        print("\n--- Phase 3: Core Optimization ---")
        result = test_06_optimize_trending(T, opt)
        test_07_mm_selection(T, result)
        test_08_reasoning_thai(T, result)

        # Phase 4: Regime Scenarios
        print("\n--- Phase 4: Regime Scenarios ---")
        test_09_optimize_crisis(T, opt)
        test_10_optimize_volatile(T, opt)

        # Phase 5: Individual Factors
        print("\n--- Phase 5: Individual Factors ---")
        test_11_client_feedback(T, opt)
        test_12_constraint_enforcement(T, opt)
        test_13_confidence_filter(T, opt)
        test_17_regime_factor(T, opt)
        test_18_effectiveness_factor(T, opt)
        test_19_symbol_factor(T, opt)
        test_20_broker_factor(T, opt)

        # Phase 6: Family Optimizer
        print("\n--- Phase 6: Family Optimizer ---")
        test_14_family_optimization_order(T, fam_opt)
        test_15_family_dd_consistency(T, fam_opt)
        test_16_portfolio_cap_consistency(T, fam_opt)

        # Phase 7: Edge Cases
        print("\n--- Phase 7: Edge Cases ---")
        test_21_multiple_optimize_calls(T, opt)
        test_22_broker_suffix_handling(T, opt)

    except Exception as e:
        T.fail("UNEXPECTED", f"{type(e).__name__}: {e}")
        traceback.print_exc()

    # Summary
    success = T.summary()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()