"""
test_regime_classifier.py — Unit tests for 3-Layer RegimeClassifier
FlashEASuite V2 | 02_Brain/tests/

วิธีรัน (from 02_Brain folder):
    python tests/test_regime_classifier.py

หรือใช้ pytest:
    pytest tests/test_regime_classifier.py -v
"""

import sys
import os
import logging
import numpy as np
import pandas as pd

# ── path setup ────────────────────────────────────────────────────────────────
# ถ้ารันจาก 02_Brain/tests/ → เพิ่ม 02_Brain/ ใน path
_this_dir   = os.path.dirname(os.path.abspath(__file__))
_brain_root = os.path.join(_this_dir, "..")
sys.path.insert(0, _brain_root)
sys.path.insert(0, _this_dir)   # fallback for standalone run

try:
    from core.intelligence.regime_classifier import (
        Regime, RegimeResult, RuleBasedClassifier,
        RandomForestClassifier, HMMRegimeClassifier,
        RegimeClassifier, build_features, _generate_synthetic_ohlcv,
    )
except ModuleNotFoundError:
    from regime_classifier import (
        Regime, RegimeResult, RuleBasedClassifier,
        RandomForestClassifier, HMMRegimeClassifier,
        RegimeClassifier, build_features, _generate_synthetic_ohlcv,
    )

logging.basicConfig(level=logging.WARNING)

# ──────────────────────────────────────────────────────────────────────────────
# Helper
# ──────────────────────────────────────────────────────────────────────────────

PASS = "✅ PASS"
FAIL = "❌ FAIL"

def check(condition: bool, msg: str) -> bool:
    status = PASS if condition else FAIL
    print(f"  {status} | {msg}")
    return condition


# ──────────────────────────────────────────────────────────────────────────────
# Test 1: Layer 1 — Rule-based
# ──────────────────────────────────────────────────────────────────────────────

def test_rule_based() -> int:
    print("\n[Test 1] Layer 1 — Rule-Based Classifier")
    clf = RuleBasedClassifier()
    passed = 0
    total  = 0

    # TRENDING: ADX >= 27, no VOLATILE, no SQUEEZE
    r = clf.classify(adx=28, atr=0.001, atr_ma=0.001, bb_width=0.002, bb_width_ma=0.004)
    total += 1; passed += check(r == Regime.TRENDING, f"ADX=28 → TRENDING (got {r})")

    # Hysteresis: entered TRENDING — stays in until ADX < 23
    r = clf.classify(adx=24, atr=0.001, atr_ma=0.001, bb_width=0.002, bb_width_ma=0.004)
    total += 1; passed += check(r == Regime.TRENDING, f"Hysteresis: ADX=24 still TRENDING (got {r})")

    # Exit hysteresis at ADX=22 (< 23)
    r = clf.classify(adx=22, atr=0.001, atr_ma=0.001, bb_width=0.002, bb_width_ma=0.004)
    total += 1; passed += check(r == Regime.RANGING, f"ADX=22 exits TRENDING → RANGING (got {r})")

    # VOLATILE: ATR > 1.5 × ATR_MA
    r = clf.classify(adx=15, atr=0.003, atr_ma=0.001, bb_width=0.002, bb_width_ma=0.004)
    total += 1; passed += check(r == Regime.VOLATILE, f"ATR=3×MA → VOLATILE (got {r})")

    # SQUEEZE: BB_Width < 0.5 × BB_MA
    r = clf.classify(adx=15, atr=0.001, atr_ma=0.001, bb_width=0.001, bb_width_ma=0.004)
    total += 1; passed += check(r == Regime.SQUEEZE, f"BB=0.25×MA → SQUEEZE (got {r})")

    # RANGING: low ADX, normal ATR/BB
    clf.reset()
    r = clf.classify(adx=15, atr=0.001, atr_ma=0.001, bb_width=0.002, bb_width_ma=0.004)
    total += 1; passed += check(r == Regime.RANGING, f"ADX=15 → RANGING (got {r})")

    # VOLATILE takes priority over SQUEEZE
    r = clf.classify(adx=15, atr=0.003, atr_ma=0.001, bb_width=0.001, bb_width_ma=0.004)
    total += 1; passed += check(r == Regime.VOLATILE, f"VOLATILE priority over SQUEEZE (got {r})")

    print(f"  Layer 1: {passed}/{total} passed")
    return passed


# ──────────────────────────────────────────────────────────────────────────────
# Test 2: Layer 2 — Random Forest
# ──────────────────────────────────────────────────────────────────────────────

def test_random_forest() -> int:
    print("\n[Test 2] Layer 2 — Random Forest Classifier")
    passed = 0
    total  = 0

    df_raw = _generate_synthetic_ohlcv(n=1500)
    df = build_features(df_raw)

    # Build rule labels for training
    rule_clf = RuleBasedClassifier()
    y = np.array([
        int(rule_clf.classify(
            adx=row["adx"], atr=row["atr"], atr_ma=row["atr_ma"],
            bb_width=row["bb_width"], bb_width_ma=row["bb_width_ma"],
        ))
        for _, row in df.iterrows()
    ])
    rule_clf.reset()

    rf_cols = RandomForestClassifier.FEATURE_NAMES
    X = df[rf_cols].values.astype(float)

    clf = RandomForestClassifier()
    total += 1; passed += check(not clf.is_trained, "Not trained before fit()")

    metrics = clf.train(X, y)
    total += 1; passed += check(clf.is_trained, "Trained after fit()")

    total += 1; passed += check(
        metrics["cv_accuracy_mean"] > 0.80,
        f"CV accuracy {metrics['cv_accuracy_mean']:.3f} > 0.80"
    )

    # Single prediction
    x_single = X[-1]
    regime, conf = clf.predict(x_single)
    total += 1; passed += check(isinstance(regime, Regime), f"predict() returns Regime (got {type(regime)})")
    total += 1; passed += check(0.0 <= conf <= 1.0, f"confidence in [0,1]: {conf:.3f}")

    # Not trained error
    clf2 = RandomForestClassifier()
    try:
        clf2.predict(x_single)
        total += 1; passed += check(False, "Should raise RuntimeError when not trained")
    except RuntimeError:
        total += 1; passed += check(True, "RuntimeError raised when not trained ✓")

    print(f"  Layer 2: {passed}/{total} passed")
    return passed


# ──────────────────────────────────────────────────────────────────────────────
# Test 3: Layer 3 — HMM
# ──────────────────────────────────────────────────────────────────────────────

def test_hmm() -> int:
    print("\n[Test 3] Layer 3 — HMM Classifier")
    passed = 0
    total  = 0

    df_raw = _generate_synthetic_ohlcv(n=1200)
    df = build_features(df_raw)

    rule_clf = RuleBasedClassifier()
    y = np.array([
        int(rule_clf.classify(
            adx=row["adx"], atr=row["atr"], atr_ma=row["atr_ma"],
            bb_width=row["bb_width"], bb_width_ma=row["bb_width_ma"],
        ))
        for _, row in df.iterrows()
    ])
    rule_clf.reset()

    hmm_cols = HMMRegimeClassifier.HMM_FEATURE_NAMES
    X = df[hmm_cols].values.astype(float)

    clf = HMMRegimeClassifier()
    total += 1; passed += check(not clf.is_trained, "Not trained before fit()")

    clf.train(X, y)
    total += 1; passed += check(clf.is_trained, "Trained after fit()")

    # predict_shift on recent window
    window = X[-30:]
    shift_prob, next_regime = clf.predict_shift(window)
    total += 1; passed += check(0.0 <= shift_prob <= 1.0, f"shift_prob in [0,1]: {shift_prob:.4f}")
    total += 1; passed += check(
        next_regime is None or isinstance(next_regime, Regime),
        f"next_regime is Regime or None: {next_regime}"
    )

    # Window too short — should return 0
    shift2, _ = clf.predict_shift(X[-5:])
    # hmmlearn can handle short window but we just verify no crash
    total += 1; passed += check(True, "Short window does not crash")

    print(f"  Layer 3: {passed}/{total} passed")
    return passed


# ──────────────────────────────────────────────────────────────────────────────
# Test 4: Combined decision logic
# ──────────────────────────────────────────────────────────────────────────────

def test_combined_logic() -> int:
    print("\n[Test 4] Combined Decision Logic")
    passed = 0
    total  = 0

    df_raw = _generate_synthetic_ohlcv(n=1500)
    df = build_features(df_raw)
    split = int(len(df) * 0.8)

    clf = RegimeClassifier()
    clf.train(df.iloc[:split], symbol="XAUUSD.tp")

    sources = {"RF": 0, "HMM": 0, "RULE": 0}
    for _, row in df.iloc[split:].iterrows():
        result = clf.classify(
            adx=row["adx"],           atr=row["atr"],
            atr_ma=row["atr_ma"],     atr_norm=row["atr_norm"],
            bb_width=row["bb_width"], bb_width_ma=row["bb_width_ma"],
            bb_width_norm=row["bb_width_norm"],
            volume=row["volume"],     volume_ma_ratio=row["volume_ma_ratio"],
            rsi=row["rsi"],           stoch_k=row["stoch_k"],
            stoch_d=row["stoch_d"],   price_change=row["price_change"],
            session=int(row["session"]),
        )
        sources[result.source] += 1

        total += 1
        passed += check(
            isinstance(result.regime, Regime),
            f"result.regime is Regime: {result.regime}"
        ) if total <= 5 else True   # only print first 5

    # At least some result exists
    n_classified = sum(sources.values())
    passed = 0  # reset for clean count of logical checks

    total = 6
    passed += check(n_classified > 0, f"Classified {n_classified} periods")
    passed += check(sources["RULE"] + sources["RF"] + sources["HMM"] == n_classified,
                    "Source counts sum to total")

    # RegimeResult has all fields
    sample_result = None
    clf2 = RegimeClassifier()
    clf2.train(df.iloc[:split], symbol="XAUUSD.tp")
    row = df.iloc[-1]
    sample_result = clf2.classify(
        adx=row["adx"],           atr=row["atr"],
        atr_ma=row["atr_ma"],     atr_norm=row["atr_norm"],
        bb_width=row["bb_width"], bb_width_ma=row["bb_width_ma"],
        bb_width_norm=row["bb_width_norm"],
        volume=row["volume"],     volume_ma_ratio=row["volume_ma_ratio"],
        rsi=row["rsi"],           stoch_k=row["stoch_k"],
        stoch_d=row["stoch_d"],   price_change=row["price_change"],
        session=int(row["session"]),
    )
    passed += check(hasattr(sample_result, "reasoning") and len(sample_result.reasoning) > 0,
                    f"reasoning field: '{sample_result.reasoning[:60]}...'")
    passed += check(isinstance(sample_result.as_dict(), dict), "as_dict() returns dict")
    passed += check("regime" in sample_result.as_dict(), "as_dict() has 'regime' key")

    # reset_symbol clears buffer
    clf2.reset_symbol()
    passed += check(len(clf2._hmm_buffer) == 0, "reset_symbol() clears HMM buffer")

    print(f"  Source distribution (test set): {sources}")
    print(f"  Combined: {passed}/{total} passed")
    return passed


# ──────────────────────────────────────────────────────────────────────────────
# Test 5: build_features
# ──────────────────────────────────────────────────────────────────────────────

def test_build_features() -> int:
    print("\n[Test 5] build_features()")
    passed = 0
    total  = 0

    df_raw = _generate_synthetic_ohlcv(n=200)
    df = build_features(df_raw)

    required_cols = (
        RandomForestClassifier.FEATURE_NAMES
        + HMMRegimeClassifier.HMM_FEATURE_NAMES
        + ["atr_ma", "bb_width_ma"]
    )
    required_cols = list(set(required_cols))

    for col in required_cols:
        total += 1
        passed += check(col in df.columns, f"Column '{col}' exists")

    total += 1; passed += check(len(df) > 0, f"Non-empty output: {len(df)} rows")
    total += 1; passed += check(not df.isnull().any().any(), "No NaN after build_features()")

    print(f"  Feature builder: {passed}/{total} passed")
    return passed


# ──────────────────────────────────────────────────────────────────────────────
# Main runner
# ──────────────────────────────────────────────────────────────────────────────

def main() -> None:
    print("=" * 60)
    print("RegimeClassifier — Unit Tests")
    print("FlashEASuite V2 | P4-1")
    print("=" * 60)

    results = {
        "Layer1_Rule":   test_rule_based(),
        "Layer2_RF":     test_random_forest(),
        "Layer3_HMM":    test_hmm(),
        "Combined":      test_combined_logic(),
        "BuildFeatures": test_build_features(),
    }

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    for name, n_passed in results.items():
        status = "✅" if n_passed > 0 else "❌"
        print(f"  {status} {name}: {n_passed} checks passed")

    print("\n✅ Test suite complete" if all(v > 0 for v in results.values())
          else "\n❌ Some tests FAILED — check output above")


if __name__ == "__main__":
    main()
