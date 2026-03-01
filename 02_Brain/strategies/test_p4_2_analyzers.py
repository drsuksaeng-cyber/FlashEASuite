"""
test_p4_2_analyzers.py — P4-2 Validation Test
FlashEASuite V2

Test: all 16 analyzers return valid confidence (0.0–1.0) for XAUUSD
Run:  python test_p4_2_analyzers.py
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from strategies import ANALYZER_REGISTRY, AnalysisResult

# ──────────────────────────────────────────────────────────────────────
# Mock indicators covering all 16 analyzers
# ──────────────────────────────────────────────────────────────────────
MOCK_INDICATORS_XAUUSD = {
    # S01 StatArb
    "zscore":           2.3,
    "correlation":      0.85,
    "coint_pvalue":     0.04,
    "beta":             1.1,
    "pair_prices":      {"XAGUSDtp": 24.5},

    # S02 ML
    "rf_signal":        1,    "rf_confidence":   0.72,
    "lstm_signal":      1,    "lstm_confidence": 0.65,
    "xgb_signal":       1,    "xgb_confidence":  0.70,
    "km_signal":        0,    "km_confidence":   0.55,
    "hmm_signal":       1,    "hmm_confidence":  0.68,

    # S03 SMC
    "bos_detected":     True,
    "choch_detected":   False,
    "ob_near_price":    True,
    "fvg_present":      True,
    "adx":              32.0,

    # S04 Market Profile
    "tpo_count":        8,
    "value_area_pct":   70.0,
    "poc_strength":     0.45,
    "price_vs_poc":     12.0,

    # S05 Supply Demand
    "zone_count":       3,
    "zone_strength":    0.7,
    "price_at_zone":    True,
    "fresh_zone":       True,
    "zone_rr":          2.2,

    # S06 KAMA
    "efficiency_ratio": 0.65,
    "kama_slope":       0.0012,
    "price_vs_kama":    25.0,

    # S07 Mean Reversion (uses zscore above)
    "bb_position":      0.92,
    "rsi":              75.0,
    "price_vs_ma":      35.0,
    "atr_ratio":        1.1,

    # S08 Intermarket
    "dxy_correlation":  -0.78,
    "dxy_momentum":     -0.08,
    "dxy_vs_ma":        -0.4,
    "gold_correlation": -0.82,
    "bond_yield_change": 0.05,
    "divergence_detected": True,

    # S09 Session
    "session_active":   True,
    "session_range":    35.0,
    "atr":              15.0,
    "volume_ratio":     1.8,
    "time_to_open":     10.0,

    # S10 Turtle
    "price_vs_20wk_high": 8.0,
    "price_vs_20wk_low":  420.0,
    "momentum_ratio":     1.6,
    "consecutive_breaks": 3,

    # S11 Ichimoku
    "price_vs_cloud":         1,
    "cloud_thickness":        20.0,
    "tenkan_kijun_aligned":   True,
    "chikou_clear":           True,
    "future_cloud_bullish":   True,

    # S12 Price Action
    "engulfing_quality":  0.8,
    "pin_bar_ratio":      3.5,
    "inside_bar":         False,
    "pattern_context":    1,
    "key_level_distance": 5.0,

    # S13 Fib Stoch
    "fib_level":      0.618,
    "fib_distance":   3.0,
    "stoch_k":        18.0,
    "stoch_d":        22.0,

    # S14 BB Squeeze
    "bb_width_ratio":   0.35,
    "bb_squeeze":       True,
    "momentum_hist":    0.012,
    "bars_in_squeeze":  8,

    # S15 Grid
    "range_pips":     45.0,
    "price_vs_range": 0.52,
    "spread_ratio":   0.03,

    # S16 Spike
    "spike_score":      0.7,
    "atr_spike_ratio":  2.5,
    "volume_spike":     4.2,
    "news_imminent":    True,
    "price_momentum":   30.0,
}

REGIMES_TO_TEST = ["RANGING", "TRENDING", "VOLATILE", "SQUEEZE"]


def run_tests() -> bool:
    symbol  = "XAUUSDtp"
    passed  = 0
    failed  = 0
    errors  = []

    print("=" * 70)
    print("  P4-2 — 16 Strategy Analyzers Validation Test")
    print(f"  Symbol: {symbol} | Regimes tested: {REGIMES_TO_TEST}")
    print("=" * 70)

    for sid, analyzer in sorted(ANALYZER_REGISTRY.items()):
        for regime in REGIMES_TO_TEST:
            try:
                result = analyzer.analyze(
                    symbol=symbol,
                    regime=regime,
                    indicators=MOCK_INDICATORS_XAUUSD,
                    history=None,
                )

                # Validate return type
                assert isinstance(result, AnalysisResult), \
                    f"Expected AnalysisResult, got {type(result)}"

                # Validate confidence range
                assert 0.0 <= result.confidence <= 1.0, \
                    f"confidence={result.confidence} out of [0,1]"

                # Validate reasoning is non-empty string
                assert isinstance(result.reasoning, str) and len(result.reasoning) > 0, \
                    "reasoning must be non-empty string"

                # Hybrid analyzers must have extra_params
                if sid in ("S01", "S02", "S08"):
                    assert isinstance(result.extra_params, dict) and len(result.extra_params) > 0, \
                        f"{sid} hybrid must have extra_params"

                passed += 1
                if regime == "RANGING":  # print one sample per analyzer
                    marker = "★" if sid in ("S01", "S02", "S08") else " "
                    print(f"  {marker}{sid} [{analyzer.get_name()[:30]:30s}] "
                          f"regime={regime:8s} conf={result.confidence:.4f}  ✓")

            except Exception as exc:
                failed += 1
                errors.append(f"  {sid} regime={regime}: {exc}")
                print(f"  ✗ {sid} regime={regime}: {exc}")

    print("-" * 70)
    print(f"  Results: {passed} passed / {failed} failed "
          f"({passed}/{passed+failed} = {100*passed/(passed+failed):.1f}%)")

    if errors:
        print("\n  FAILURES:")
        for e in errors:
            print(e)

    # Extra: check preferred regimes
    print("\n  Preferred Regimes Summary:")
    for sid, analyzer in sorted(ANALYZER_REGISTRY.items()):
        prefs = analyzer.get_preferred_regimes()
        hybrid = "★ HYBRID" if sid in ("S01", "S02", "S08") else "       "
        print(f"  {sid} {hybrid} preferred={prefs}")

    print("=" * 70)
    return failed == 0


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
