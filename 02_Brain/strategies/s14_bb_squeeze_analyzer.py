"""
s14_bb_squeeze_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Bollinger Band Squeeze (volatility compression → expansion):
  - bb_width_ratio   → BB width / MA(BB width): <0.5 = squeeze
  - bb_squeeze       → bool: currently in squeeze
  - momentum_hist    → histogram of momentum oscillator (direction)
  - atr_ratio        → ATR / MA(ATR): <0.7 = low vol (squeeze condition)
  - bars_in_squeeze  → how long price has been squeezed (longer = more energy)
Regime: SQUEEZE best, VOLATILE for breakout phase
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_SQUEEZE, REGIME_VOLATILE


class S14BbSqueezeAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S14"
    def get_name(self) -> str: return "Bollinger Band Squeeze"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_SQUEEZE, REGIME_VOLATILE]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        bb_ratio       = float(self._safe_get(indicators, "bb_width_ratio",  1.0))
        in_squeeze     = bool(self._safe_get(indicators,  "bb_squeeze",      False))
        mom_hist       = abs(float(self._safe_get(indicators, "momentum_hist", 0.0)))
        atr_ratio      = float(self._safe_get(indicators, "atr_ratio",        1.0))
        bars_squeeze   = float(self._safe_get(indicators, "bars_in_squeeze",  0.0))

        # Squeeze tightness (lower bb_ratio = tighter = more energy)
        squeeze_score  = max(0.0, 1.0 - bb_ratio / 0.5) * 0.30 if bb_ratio < 1.0 else 0.0
        squeeze_bonus  = 0.10 if in_squeeze else 0.0

        # Momentum building
        mom_score      = min(0.25, mom_hist * 10.0)

        # ATR compression
        atr_score      = max(0.0, 1.0 - atr_ratio) * 0.20 if atr_ratio < 1.0 else 0.0

        # Duration of squeeze (energy buildup)
        dur_score      = min(0.15, bars_squeeze / 20.0 * 0.15)

        raw            = squeeze_score + squeeze_bonus + mom_score + atr_score + dur_score
        confidence     = self._apply_regime(raw, regime)

        reasoning = (
            f"BBSqueeze bb_ratio={bb_ratio:.2f} in_squeeze={in_squeeze} "
            f"mom={mom_hist:.4f} atr_ratio={atr_ratio:.2f} bars={bars_squeeze:.0f} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
