"""
s06_kama_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Confidence based on KAMA Efficiency Ratio:
  - efficiency_ratio (ER)  → higher ER = more directional = better for KAMA
  - kama_slope             → speed of KAMA movement (normalised)
  - price_vs_kama          → price relative position vs KAMA
  - adx                    → trend strength confirmation
Regime: TRENDING best
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_TRENDING


class S06KamaAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S06"
    def get_name(self) -> str: return "KAMA Trend Following"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_TRENDING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        er          = float(self._safe_get(indicators, "efficiency_ratio", 0.3))
        kama_slope  = float(self._safe_get(indicators, "kama_slope",       0.0))
        price_vs_kama = float(self._safe_get(indicators, "price_vs_kama", 0.0))  # pips
        adx         = float(self._safe_get(indicators, "adx",              20.0))

        # ER is the primary driver (spec: ER higher → confidence higher)
        er_score     = self._clamp(er) * 0.45

        # Slope confirms direction momentum
        slope_score  = min(0.20, abs(kama_slope) / 0.01 * 0.20)

        # Price beyond KAMA = already in move (0.15)
        pvk_score    = min(0.15, abs(price_vs_kama) / 50.0 * 0.15)

        # ADX bonus 0–0.20
        adx_score    = self._normalize(adx, 15.0, 50.0) * 0.20

        raw          = er_score + slope_score + pvk_score + adx_score
        confidence   = self._apply_regime(raw, regime)

        reasoning = (
            f"KAMA ER={er:.3f} slope={kama_slope:.5f} pvk={price_vs_kama:.1f} "
            f"ADX={adx:.1f} regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
