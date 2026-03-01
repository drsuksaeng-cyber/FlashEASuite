"""
s15_grid_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Grid Trading:
  - atr_ratio      → ATR / MA(ATR): ~1.0 = normal vol (ideal for grid)
  - range_pips     → recent price range (enough room for grid levels)
  - price_vs_range → position within range (middle = best)
  - trend_strength → ADX: lower = more ranging = better
  - spread_ratio   → spread / ATR: lower is better (grid needs tight spread)
Regime: RANGING best (spec: ATR normal = RANGING)
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING


class S15GridAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S15"
    def get_name(self) -> str: return "Grid Trading"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_RANGING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        atr_ratio     = float(self._safe_get(indicators, "atr_ratio",      1.0))
        range_pips    = float(self._safe_get(indicators, "range_pips",     30.0))
        pos_in_range  = float(self._safe_get(indicators, "price_vs_range", 0.5))  # 0–1
        adx           = float(self._safe_get(indicators, "adx",            20.0))
        spread_ratio  = float(self._safe_get(indicators, "spread_ratio",   0.05))

        # ATR near normal (spec: ATR normal → higher confidence)
        # perfect at ratio=1.0, degrades ±0.5 away
        atr_score     = max(0.0, 1.0 - abs(atr_ratio - 1.0) / 0.5) * 0.30

        # Range must be wide enough for grid (50+ pips ideal)
        range_score   = self._normalize(range_pips, 20.0, 80.0) * 0.25

        # Price near middle of range → more room in both directions
        mid_score     = max(0.0, 1.0 - abs(pos_in_range - 0.5) * 4.0) * 0.20

        # Low ADX = ranging (good for grid)
        adx_score     = max(0.0, 1.0 - adx / 40.0) * 0.15

        # Tight spread
        spread_score  = max(0.0, 1.0 - spread_ratio / 0.10) * 0.10

        raw           = atr_score + range_score + mid_score + adx_score + spread_score
        confidence    = self._apply_regime(raw, regime)

        reasoning = (
            f"Grid ATR_ratio={atr_ratio:.2f} range={range_pips:.1f}pips "
            f"pos={pos_in_range:.2f} ADX={adx:.1f} spread_r={spread_ratio:.3f} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
