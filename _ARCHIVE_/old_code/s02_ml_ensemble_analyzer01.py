"""
s02_ml_ensemble_analyzer.py — Hybrid Analyzer
FlashEASuite V2 | 02_Brain/strategies/

ML Ensemble (5 Models): RF + LSTM + XGBoost + KMeans + HMM
  Confidence: weighted ensemble vote quality
  Hybrid extras (sent via CONFIG_PUSH):
    - ml_signal       → +1 (buy), -1 (sell), 0 (neutral)
    - ml_confidence   → 0.0–1.0 ensemble confidence
    - model_agreement → how many models agree (0–5)

NOTE: Full ML models are implemented in P4-7 (ml_models/ folder).
      This analyzer acts as orchestrator bridge between models and AI Council.
      In standalone fallback mode, it uses rule-based approximation.

Author: FlashEASuite V2 Dev | P4-2
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING, REGIME_TRENDING

logger = logging.getLogger(__name__)

# Model weight allocation (must sum to 1.0)
_MODEL_WEIGHTS = {
    "random_forest": 0.25,
    "lstm":          0.25,
    "xgboost":       0.25,
    "kmeans":        0.10,
    "hmm":           0.15,
}


class S02MlEnsembleAnalyzer(BaseAnalyzer):
    """
    Hybrid analyzer: orchestrates ML ensemble vote.
    Full model logic added in P4-7.  Here we consume pre-computed
    model outputs from the 'indicators' dict (filled by the ML pipeline).
    """

    def get_id(self)   -> str: return "S02"
    def get_name(self) -> str: return "ML Ensemble (5 Models)"

    def get_preferred_regimes(self) -> List[str]:
        # ML adapts to all regimes → no specific preference
        return [REGIME_TRENDING, REGIME_RANGING]

    def analyze(
        self,
        symbol:     str,
        regime:     str,
        indicators: Dict[str, Any],
        history:    Optional[List[Dict[str, Any]]] = None,
    ) -> AnalysisResult:

        # ── Per-model signals and confidences (provided by P4-7 pipeline) ──
        rf_signal   = int(self._safe_get(indicators,   "rf_signal",     0))    # +1/0/-1
        rf_conf     = float(self._safe_get(indicators, "rf_confidence", 0.5))

        lstm_signal = int(self._safe_get(indicators,   "lstm_signal",   0))
        lstm_conf   = float(self._safe_get(indicators, "lstm_confidence", 0.5))

        xgb_signal  = int(self._safe_get(indicators,   "xgb_signal",    0))
        xgb_conf    = float(self._safe_get(indicators, "xgb_confidence", 0.5))

        km_signal   = int(self._safe_get(indicators,   "km_signal",     0))
        km_conf     = float(self._safe_get(indicators, "km_confidence", 0.5))

        hmm_signal  = int(self._safe_get(indicators,   "hmm_signal",    0))
        hmm_conf    = float(self._safe_get(indicators, "hmm_confidence", 0.5))

        # ── Ensemble vote ──────────────────────────────────────────────
        signals  = [rf_signal, lstm_signal, xgb_signal, km_signal, hmm_signal]
        weights  = list(_MODEL_WEIGHTS.values())
        confs    = [rf_conf, lstm_conf, xgb_conf, km_conf, hmm_conf]

        # Weighted signal
        w_signal = sum(s * w * c for s, w, c in zip(signals, weights, confs))

        # Model agreement (how many agree on direction)
        buys     = sum(1 for s in signals if s > 0)
        sells    = sum(1 for s in signals if s < 0)
        agreement = max(buys, sells)

        # Final signal direction
        if   w_signal >  0.10: final_signal = 1
        elif w_signal < -0.10: final_signal = -1
        else:                  final_signal = 0

        # Ensemble confidence = weighted avg of individual confidences × agreement factor
        avg_conf     = sum(w * c for w, c in zip(weights, confs))
        agree_factor = agreement / 5.0   # 1.0 when all 5 agree
        raw_conf     = avg_conf * (0.6 + 0.4 * agree_factor)

        # Overall confidence (no strong regime bias – ML is adaptive)
        confidence   = self._clamp(raw_conf)

        extra = {
            "ml_signal":         final_signal,
            "ml_confidence":     round(confidence, 4),
            "ml_model_agreement": agreement,
            "ml_w_signal":       round(w_signal, 4),
        }

        reasoning = (
            f"MLEnsemble w_signal={w_signal:.3f} agreement={agreement}/5 "
            f"avg_conf={avg_conf:.3f} regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning,
                              extra_params=extra)

    # ------------------------------------------------------------------
    def analyze_fallback(
        self,
        symbol:     str,
        regime:     str,
        indicators: Dict[str, Any],
    ) -> AnalysisResult:
        """
        Rule-based fallback when ML models not available / not trained yet.
        Uses RSI + MACD + ADX heuristics to approximate ML output.
        """
        rsi  = float(self._safe_get(indicators, "rsi",  50.0))
        macd = float(self._safe_get(indicators, "macd",  0.0))
        adx  = float(self._safe_get(indicators, "adx",  20.0))

        # Heuristic signal
        if rsi > 55 and macd > 0 and adx > 25:
            fb_signal, fb_conf = 1, 0.55
        elif rsi < 45 and macd < 0 and adx > 25:
            fb_signal, fb_conf = -1, 0.55
        else:
            fb_signal, fb_conf = 0, 0.40

        extra = {
            "ml_signal":      fb_signal,
            "ml_confidence":  fb_conf,
            "ml_model_agreement": 0,
            "ml_fallback":    True,
        }
        return AnalysisResult(
            confidence=fb_conf,
            reasoning=f"ML_fallback RSI={rsi:.1f} MACD={macd:.5f} ADX={adx:.1f} "
                      f"→ sig={fb_signal} conf={fb_conf:.3f}",
            extra_params=extra,
        )
