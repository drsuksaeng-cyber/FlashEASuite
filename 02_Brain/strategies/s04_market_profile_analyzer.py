"""
s04_market_profile_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Confidence based on Market Profile / Volume Profile quality:
  - tpo_count      → more TPOs = stronger profile
  - value_area_pct → 68–72% ideal
  - poc_strength   → % of volume at POC
  - price_vs_poc   → distance from POC (mean-revert signal)
Regime: RANGING best
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING


class S04MarketProfileAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S04"
    def get_name(self) -> str: return "Market Profile / Volume Profile"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_RANGING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        tpo_count      = float(self._safe_get(indicators, "tpo_count",      5.0))
        value_area_pct = float(self._safe_get(indicators, "value_area_pct", 68.0))
        poc_strength   = float(self._safe_get(indicators, "poc_strength",   0.3))
        price_vs_poc   = float(self._safe_get(indicators, "price_vs_poc",   0.0))  # pips

        # Normalise TPO count (3–15 range)
        tpo_score  = self._normalize(tpo_count, 3.0, 15.0) * 0.25

        # Value area ideally 68–72 %
        va_dist    = abs(value_area_pct - 70.0)
        va_score   = max(0.0, 1.0 - va_dist / 10.0) * 0.25

        # POC strength (0–1)
        poc_score  = self._clamp(poc_strength) * 0.25

        # Price close to POC → higher confidence for mean reversion
        dist_score = max(0.0, 1.0 - abs(price_vs_poc) / 50.0) * 0.25

        raw        = tpo_score + va_score + poc_score + dist_score
        confidence = self._apply_regime(raw, regime)

        reasoning = (
            f"MarketProfile tpo={tpo_count:.0f} VA={value_area_pct:.1f}% "
            f"poc_str={poc_strength:.2f} dist={price_vs_poc:.1f}pips "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
