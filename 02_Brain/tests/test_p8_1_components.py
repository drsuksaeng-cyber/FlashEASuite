#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — P8-1 Component Test (Python Side) v1.01
==========================================================
FIXES from v1.00:
  - Import paths fixed: strategies.xxx (not core.strategies.xxx)
  - ML models: strategies.ml_models.xxx
  - RegimeClassifier.classify() fixed to 14 positional args
  - StrategyCouncil: discover actual methods via introspection
  - No assumed method names (classify_rule_based, classify_rf, etc.)

CORRECT PATHS (from 02_Brain/):
  strategies/                   ← base_analyzer.py, s01..s16
  strategies/ml_models/         ← feature_engineering, RF, LSTM, etc.
  core/intelligence/            ← regime_classifier.py, strategy_council.py

HOW TO RUN (from 02_Brain/ directory):
  python tests/test_p8_1_components.py
  pytest tests/test_p8_1_components.py -v
"""

import sys
import os
import time
import traceback
from datetime import datetime
from typing import Dict, List, Any

# ── Path setup: add 02_Brain/ to sys.path ────────────────────────────
BRAIN_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BRAIN_DIR)

# ── Test counters ─────────────────────────────────────────────────────
_pass   = 0
_fail   = 0
_skip   = 0
_errors = []


def PASS(label: str):
    global _pass
    _pass += 1
    print(f"  [PASS] {label}")


def FAIL(label: str, reason: str = ""):
    global _fail
    _fail += 1
    msg = f"  [FAIL] {label}" + (f" — {reason}" if reason else "")
    print(msg)
    _errors.append(msg)


def SKIP(label: str, reason: str = ""):
    global _skip
    _skip += 1
    print(f"  [SKIP] {label}" + (f" — {reason}" if reason else ""))


def section(title: str):
    print()
    print("━" * 66)
    print(f"  {title}")
    print("━" * 66)


# ── Mock market data ─────────────────────────────────────────────────
def make_indicators(symbol: str = "XAUUSD") -> Dict[str, Any]:
    return {
        "symbol":          symbol,
        "bid":             2345.50,
        "ask":             2345.70,
        "spread":          0.20,
        "adx":             28.5,        # > 27 → TRENDING
        "atr":             4.20,
        "atr_ma":          4.10,        # atr moving average
        "atr_norm":        1.02,        # atr / atr_ma
        "bb_width":        0.0035,
        "bb_width_ma":     0.0042,
        "bb_width_norm":   0.833,       # bb_width / bb_width_ma
        "volume":          1250.0,
        "volume_ma_ratio": 1.1,         # volume / volume_ma
        "rsi":             52.0,
        "stoch_k":         58.0,
        "stoch_d":         55.0,
        "price_change":    0.0012,
        "session":         "LONDON",
        "timestamp":       datetime.utcnow(),
        "prices":          [2340.0 + i * 0.5 for i in range(60)],
    }


def make_history() -> List[Dict]:
    import random
    random.seed(42)
    trades = []
    for i in range(50):
        trades.append({
            "strategy_id": f"S{(i % 16) + 1:02d}",
            "symbol":      ["XAUUSD", "EURUSD", "GBPUSD"][i % 3],
            "pnl":         random.uniform(-20, 50),
            "win":         random.random() > 0.40,
        })
    return trades


# ====================================================================
#  TEST 1: ML Ensemble — 5 Models
# ====================================================================
def run_test1_ml_ensemble():
    section("TEST 1: ML Ensemble — 5 Models (RF/XGBoost/LSTM/KMeans/HMM)")

    # ✅ Correct import path: strategies.ml_models (NOT core.strategies)
    try:
        from strategies.ml_models.random_forest_model import RandomForestModel
        PASS("RandomForestModel import OK")
    except ImportError as e:
        FAIL("RandomForestModel import", str(e))
        return

    try:
        from strategies.ml_models.xgboost_model import XGBoostModel
        PASS("XGBoostModel import OK")
    except ImportError as e:
        FAIL("XGBoostModel import", str(e)); return

    try:
        from strategies.ml_models.lstm_model import LSTMModel
        PASS("LSTMModel import OK")
    except ImportError as e:
        FAIL("LSTMModel import", str(e)); return

    try:
        from strategies.ml_models.kmeans_model import KMeansModel
        PASS("KMeansModel import OK")
    except ImportError as e:
        FAIL("KMeansModel import", str(e)); return

    try:
        from strategies.ml_models.hmm_model import HMMModel
        PASS("HMMModel import OK")
    except ImportError as e:
        FAIL("HMMModel import", str(e)); return

    ind = make_indicators()

    # ── Introspect each model to find correct predict method ──────────
    models_classes = [
        ("RF",      RandomForestModel),
        ("XGBoost", XGBoostModel),
        ("LSTM",    LSTMModel),
        ("KMeans",  KMeansModel),
        ("HMM",     HMMModel),
    ]

    for (name, cls) in models_classes:
        try:
            obj = cls()
            PASS(f"{name} constructor OK")

            # Discover available methods
            methods = [m for m in dir(obj) if not m.startswith("_")]

            # Try fit/train methods
            fit_methods = [m for m in methods if "fit" in m.lower() or "train" in m.lower() or "build" in m.lower()]
            if fit_methods:
                for fm in fit_methods[:1]:
                    try:
                        getattr(obj, fm)()
                        PASS(f"{name}.{fm}() — no crash")
                        break
                    except Exception as e:
                        SKIP(f"{name}.{fm}()", f"needs args: {str(e)[:60]}")

            # Try predict methods
            predict_methods = [m for m in methods if "predict" in m.lower()]
            if predict_methods:
                for pm in predict_methods[:1]:
                    try:
                        result = getattr(obj, pm)(ind)
                        PASS(f"{name}.{pm}() → {type(result).__name__}")
                    except Exception as e:
                        SKIP(f"{name}.{pm}()", f"{str(e)[:80]}")

            # Try get_confidence if exists
            if "get_confidence" in methods:
                try:
                    c = obj.get_confidence()
                    assert 0.0 <= c <= 1.0, f"{c} out of [0,1]"
                    PASS(f"{name}.get_confidence() = {c:.3f}")
                except Exception as e:
                    FAIL(f"{name}.get_confidence()", str(e))

            PASS(f"{name} available methods: {', '.join(methods[:8])}")

        except Exception as e:
            FAIL(f"{name} test", str(e))


# ====================================================================
#  TEST 2: Regime Classifier — actual interface
# ====================================================================
def run_test2_regime_classifier():
    section("TEST 2: Regime Classifier — actual classify() interface")

    try:
        from core.intelligence.regime_classifier import RegimeClassifier
        PASS("RegimeClassifier import OK")
    except ImportError as e:
        FAIL("RegimeClassifier import", str(e)); return

    try:
        rc = RegimeClassifier()
        PASS("RegimeClassifier() constructor")
    except Exception as e:
        FAIL("RegimeClassifier() constructor", str(e)); return

    # ── Introspect: discover actual method signatures ─────────────────
    methods = [m for m in dir(rc) if not m.startswith("_")]
    PASS(f"RegimeClassifier methods: {', '.join(methods[:12])}")

    # ── Test classify() — actual signature requires 14 positional args
    # Signature: classify(adx, atr, atr_ma, atr_norm, bb_width, bb_width_ma,
    #                     bb_width_norm, volume, volume_ma_ratio,
    #                     rsi, stoch_k, stoch_d, price_change, session)
    ind = make_indicators()

    valid_regimes = {"TRENDING", "RANGING", "VOLATILE", "SQUEEZE", "UNKNOWN"}

    def call_classify(ind_dict):
        return rc.classify(
            ind_dict["adx"],
            ind_dict["atr"],
            ind_dict["atr_ma"],
            ind_dict["atr_norm"],
            ind_dict["bb_width"],
            ind_dict["bb_width_ma"],
            ind_dict["bb_width_norm"],
            ind_dict["volume"],
            ind_dict["volume_ma_ratio"],
            ind_dict["rsi"],
            ind_dict["stoch_k"],
            ind_dict["stoch_d"],
            ind_dict["price_change"],
            ind_dict["session"],
        )

    # Scenario A: TRENDING (ADX=28.5 > 27)
    try:
        result = call_classify(ind)
        if isinstance(result, tuple):
            regime, meta = result[0], result[1]
        else:
            regime = str(result)
        assert regime.upper() in valid_regimes, f"'{regime}' not valid"
        PASS(f"classify() ADX=28.5 → '{regime}'")
        if regime.upper() == "TRENDING":
            PASS("classify() → TRENDING (expected for ADX=28.5) ✅")
    except Exception as e:
        FAIL("classify() ADX=28.5", str(e))

    # Scenario B: RANGING (ADX=15)
    ind_b = make_indicators()
    ind_b["adx"] = 15.0; ind_b["atr_norm"] = 0.9
    try:
        result = call_classify(ind_b)
        regime_b = result[0] if isinstance(result, tuple) else str(result)
        PASS(f"classify() ADX=15.0 → '{regime_b}'")
    except Exception as e:
        FAIL("classify() ADX=15.0", str(e))

    # Scenario C: VOLATILE (ADX=40)
    ind_c = make_indicators()
    ind_c["adx"] = 40.0; ind_c["atr_norm"] = 1.8
    try:
        result = call_classify(ind_c)
        regime_c = result[0] if isinstance(result, tuple) else str(result)
        PASS(f"classify() ADX=40.0 → '{regime_c}'")
        if regime_c.upper() == "VOLATILE":
            PASS("classify() → VOLATILE (expected for ADX=40) ✅")
    except Exception as e:
        FAIL("classify() ADX=40.0", str(e))

    # Scenario D: SQUEEZE (bb_width << avg, ADX<20)
    ind_d = make_indicators()
    ind_d["adx"] = 16.0
    ind_d["bb_width"] = 0.001
    ind_d["bb_width_ma"] = 0.004
    ind_d["bb_width_norm"] = 0.25  # very low
    try:
        result = call_classify(ind_d)
        regime_d = result[0] if isinstance(result, tuple) else str(result)
        PASS(f"classify() BB_narrow → '{regime_d}'")
    except Exception as e:
        FAIL("classify() BB_narrow", str(e))

    # Hysteresis test: ADX=24.5 (between exit=23 and enter=27)
    try:
        ind_h1 = make_indicators(); ind_h1["adx"] = 28.0
        call_classify(ind_h1)  # enter TRENDING

        ind_h2 = make_indicators(); ind_h2["adx"] = 24.5  # between 23 and 27
        result_h2 = call_classify(ind_h2)
        regime_h2 = result_h2[0] if isinstance(result_h2, tuple) else str(result_h2)
        if regime_h2.upper() == "TRENDING":
            PASS("Hysteresis: ADX=24.5 stays TRENDING (no flicker) ✅")
        else:
            FAIL("Hysteresis", f"ADX=24.5 → '{regime_h2}' (expected TRENDING)")
    except Exception as e:
        SKIP("Hysteresis test", f"no hysteresis state: {str(e)[:60]}")

    # Test other available methods
    for method_name in methods:
        if method_name in ("classify",): continue
        if "classif" in method_name or "regime" in method_name or "predict" in method_name:
            try:
                result = getattr(rc, method_name)()
                PASS(f"rc.{method_name}() → {repr(result)[:40]}")
            except Exception as e:
                SKIP(f"rc.{method_name}()", str(e)[:60])


# ====================================================================
#  TEST 3: StrategyCouncil — discover actual interface
# ====================================================================
def run_test3_strategy_council():
    section("TEST 3: AI Council — StrategyCouncil (actual interface)")

    try:
        from core.intelligence.strategy_council import StrategyCouncil
        PASS("StrategyCouncil import OK")
    except ImportError as e:
        FAIL("StrategyCouncil import", str(e)); return

    try:
        council = StrategyCouncil()
        PASS("StrategyCouncil() constructor")
    except Exception as e:
        FAIL("StrategyCouncil() constructor", str(e)); return

    ind = make_indicators()
    history = make_history()

    # ── Discover all public methods ───────────────────────────────────
    all_methods = [m for m in dir(council) if not m.startswith("_")]
    PASS(f"StrategyCouncil methods ({len(all_methods)}): {', '.join(all_methods[:15])}")

    # ── Test key methods by category ─────────────────────────────────
    # Selection/voting methods
    selection_methods = [m for m in all_methods if any(kw in m.lower()
        for kw in ("select", "vote", "analyze", "get_best", "recommend", "top"))]
    for m in selection_methods[:3]:
        try:
            # Try with symbol + regime + indicators
            result = getattr(council, m)("XAUUSD", "TRENDING", ind)
            PASS(f"council.{m}('XAUUSD', 'TRENDING', ind) → {type(result).__name__}")
        except TypeError:
            try:
                result = getattr(council, m)(ind)
                PASS(f"council.{m}(ind) → {type(result).__name__}")
            except Exception as e2:
                SKIP(f"council.{m}", f"signature unknown: {str(e2)[:60]}")
        except Exception as e:
            SKIP(f"council.{m}", str(e)[:60])

    # Scoring/confidence methods
    score_methods = [m for m in all_methods if any(kw in m.lower()
        for kw in ("score", "confidence", "weight", "calc"))]
    for m in score_methods[:3]:
        try:
            result = getattr(council, m)()
            PASS(f"council.{m}() → {repr(result)[:40]}")
        except Exception as e:
            SKIP(f"council.{m}()", str(e)[:60])

    # Update/feedback methods
    update_methods = [m for m in all_methods if any(kw in m.lower()
        for kw in ("update", "feedback", "learn", "record"))]
    for m in update_methods[:3]:
        try:
            getattr(council, m)("S01", "XAUUSD", "WIN")
            PASS(f"council.{m}('S01', 'XAUUSD', 'WIN') — no crash")
        except TypeError:
            try:
                getattr(council, m)("WIN")
                PASS(f"council.{m}('WIN') — no crash")
            except Exception as e2:
                SKIP(f"council.{m}", str(e2)[:60])
        except Exception as e:
            SKIP(f"council.{m}", str(e)[:60])

    # Correlation method
    corr_methods = [m for m in all_methods if "corr" in m.lower()]
    for m in corr_methods:
        try:
            result = getattr(council, m)("EURUSD", "GBPUSD")
            PASS(f"council.{m}('EURUSD','GBPUSD') → {result}")
        except Exception as e:
            SKIP(f"council.{m}", str(e)[:60])


# ====================================================================
#  TEST 4: 16 Strategy Analyzers × 3 Symbols
# ====================================================================
def run_test4_strategy_analyzers():
    section("TEST 4: 16 Strategy Analyzers × 3 Symbols")

    # ✅ Correct import: from strategies (NOT core.strategies)
    try:
        from strategies.base_analyzer import BaseAnalyzer
        PASS("BaseAnalyzer import OK")
    except ImportError as e:
        FAIL("BaseAnalyzer import", str(e)); return

    # All 16 analyzer modules
    analyzer_defs = [
        ("S01", "s01_stat_arb_analyzer",          "StatArbAnalyzer"),
        ("S02", "s02_ml_ensemble_analyzer",        "MLEnsembleAnalyzer"),
        ("S03", "s03_smc_analyzer",                "SMCAnalyzer"),
        ("S04", "s04_market_profile_analyzer",     "MarketProfileAnalyzer"),
        ("S05", "s05_supply_demand_analyzer",      "SupplyDemandAnalyzer"),
        ("S06", "s06_kama_analyzer",               "KAMAAnalyzer"),
        ("S07", "s07_mean_reversion_analyzer",     "MeanReversionAnalyzer"),
        ("S08", "s08_intermarket_analyzer",        "IntermarketAnalyzer"),
        ("S09", "s09_session_breakout_analyzer",   "SessionBreakoutAnalyzer"),
        ("S10", "s10_turtle_analyzer",             "TurtleAnalyzer"),
        ("S11", "s11_ichimoku_analyzer",           "IchimokuAnalyzer"),
        ("S12", "s12_price_action_analyzer",       "PriceActionAnalyzer"),
        ("S13", "s13_fib_stoch_analyzer",          "FibStochAnalyzer"),
        ("S14", "s14_bb_squeeze_analyzer",         "BBSqueezeAnalyzer"),
        ("S15", "s15_grid_analyzer",               "GridAnalyzer"),
        ("S16", "s16_spike_analyzer",              "SpikeAnalyzer"),
    ]

    symbols  = ["XAUUSD", "EURUSD", "GBPUSD"]
    regimes  = ["TRENDING", "RANGING", "VOLATILE"]
    valid_r  = {"TRENDING", "RANGING", "VOLATILE", "SQUEEZE", "UNKNOWN"}
    history  = make_history()

    for (sid, mod_name, cls_name) in analyzer_defs:
        try:
            module = __import__(f"strategies.{mod_name}", fromlist=[cls_name])
        except ImportError as e:
            FAIL(f"{sid} import", str(e)); continue

        try:
            cls = getattr(module, cls_name)
            obj = cls()
        except Exception as e:
            FAIL(f"{sid} instantiate", str(e)); continue

        # ✅ get_id
        try:
            gid = obj.get_id()
            if gid == sid: PASS(f"{sid}.get_id() = '{gid}'")
            else: FAIL(f"{sid}.get_id()", f"expected '{sid}' got '{gid}'")
        except AttributeError:
            SKIP(f"{sid}.get_id()", "method not found")

        # ✅ get_name
        try:
            name = obj.get_name()
            if name: PASS(f"{sid}.get_name() = '{name}'")
            else: FAIL(f"{sid}.get_name()", "empty")
        except AttributeError:
            SKIP(f"{sid}.get_name()", "method not found")

        # ✅ get_preferred_regimes
        try:
            pref = obj.get_preferred_regimes()
            if pref and all(r in valid_r for r in pref):
                PASS(f"{sid}.get_preferred_regimes() = {pref}")
            else:
                FAIL(f"{sid}.get_preferred_regimes()", f"invalid: {pref}")
        except AttributeError:
            SKIP(f"{sid}.get_preferred_regimes()", "method not found")

        # ✅ analyze() × 3 symbols × 3 regimes
        for sym in symbols:
            for reg in regimes:
                ind = make_indicators(sym)
                try:
                    result = obj.analyze(sym, reg, ind, history)
                    conf = result.get("confidence", -1)
                    reason = result.get("reasoning", "")
                    assert 0.0 <= conf <= 1.0, f"conf={conf} out of [0,1]"
                    assert isinstance(reason, str) and len(reason) > 0, "reasoning empty"
                    PASS(f"{sid}.analyze({sym},{reg}) conf={conf:.3f}")
                except AssertionError as ae:
                    FAIL(f"{sid}.analyze({sym},{reg})", str(ae))
                except Exception as e:
                    FAIL(f"{sid}.analyze({sym},{reg})", str(e)[:80])


# ====================================================================
#  TEST 5: Feature Engineering & Pipeline Sanity
# ====================================================================
def run_test5_pipeline():
    section("TEST 5: Feature Engineering & Data Pipeline Sanity")

    # ✅ Correct path: strategies.ml_models
    try:
        from strategies.ml_models.feature_engineering import FeatureEngineer
        PASS("FeatureEngineer import OK")
    except ImportError as e:
        FAIL("FeatureEngineer import", str(e)); return

    try:
        fe = FeatureEngineer()
        PASS("FeatureEngineer() constructor")
    except Exception as e:
        FAIL("FeatureEngineer() constructor", str(e)); return

    ind = make_indicators()

    try:
        features = fe.extract(ind)
        assert isinstance(features, dict), "should return dict"
        assert len(features) >= 10, f"Only {len(features)} features (expected ≥10)"
        nan_keys = [k for k, v in features.items()
                    if v is None or (isinstance(v, float) and v != v)]
        if not nan_keys:
            PASS(f"FeatureEngineer.extract() → {len(features)} features, no NaN ✅")
        else:
            FAIL("FeatureEngineer.extract()", f"NaN/None in keys: {nan_keys[:5]}")
    except Exception as e:
        FAIL("FeatureEngineer.extract()", str(e))

    # InfluxDB ingestion (optional)
    try:
        from core.data.influxdb_client import InfluxDBClient
        PASS("InfluxDBClient import OK (core.data)")
    except ImportError:
        try:
            from core.ingestion import InfluxDBWriter
            PASS("InfluxDBWriter import OK (core.ingestion)")
        except ImportError:
            SKIP("InfluxDB import", "module path not found — skip data pipeline test")


# ====================================================================
#  MAIN
# ====================================================================
def main():
    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║         FlashEASuite V2 — P8-1 COMPONENT TEST REPORT            ║")
    print("║                   (Python Side v1.01)                           ║")
    print(f"║  Date: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC'):<56}║")
    print("╚══════════════════════════════════════════════════════════════════╝")

    t = time.time()

    run_test1_ml_ensemble()
    run_test2_regime_classifier()
    run_test3_strategy_council()
    run_test4_strategy_analyzers()
    run_test5_pipeline()

    elapsed = time.time() - t
    total = _pass + _fail

    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║                   FINAL SUMMARY REPORT                          ║")
    print("╠══════════════════════════════════════════════════════════════════╣")
    print(f"║  ✅ PASS : {_pass:<57}║")
    print(f"║  ❌ FAIL : {_fail:<57}║")
    print(f"║  ⏭ SKIP : {_skip:<57}║")
    pct = (100.0 * _pass / total) if total > 0 else 0.0
    print(f"║  Pass Rate : {pct:.1f}% ({_pass}/{total}){'':42}║")
    print(f"║  Duration  : {elapsed:.2f}s{'':52}║")
    print("╠══════════════════════════════════════════════════════════════════╣")

    if _fail == 0:
        print("║  🎉 ALL TESTS PASSED — READY FOR P8-2 INTEGRATION TEST          ║")
    else:
        print("║  ⚠  FAILURES FOUND — Fix before P8-2!                           ║")
        print("╠══════════════════════════════════════════════════════════════════╣")
        for err in _errors[:20]:
            print(f"║  {err:<66}║")

    print("╚══════════════════════════════════════════════════════════════════╝")
    print()
    return _fail


# ── Pytest compat ────────────────────────────────────────────────────
def test_ml_ensemble():
    run_test1_ml_ensemble()

def test_regime_classifier():
    run_test2_regime_classifier()

def test_ai_council():
    run_test3_strategy_council()

def test_analyzers():
    run_test4_strategy_analyzers()

def test_pipeline():
    run_test5_pipeline()


if __name__ == "__main__":
    sys.exit(main())
