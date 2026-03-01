"""
s12_price_action_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Price Action (candlestick patterns + structure):
  - engulfing_quality  → 0–1 quality of engulfing candle
  - pin_bar_ratio      → wick/body ratio (higher = stronger rejection)
  - inside_bar         → is current bar inside bar?
  - pattern_context    → 1=trend continuation, 2=reversal, 0=none
  - key_level_distance → distance from S/R level (pips, 0=at level)
Regime: all regimes viable (price action universal)
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_TRENDING, REGIME_RANGING


class S12PriceActionAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S12"
    def get_name(self) -> str: return "Price Action Patterns"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_TRENDING, REGIME_RANGING]   # universal

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        engulfing_q  = float(self._safe_get(indicators, "engulfing_quality",   0.0))
        pin_ratio    = float(self._safe_get(indicators, "pin_bar_ratio",        0.0))
        inside_bar   = bool(self._safe_get(indicators,  "inside_bar",          False))
        context      = int(self._safe_get(indicators,   "pattern_context",      0))    # 0/1/2
        key_dist     = abs(float(self._safe_get(indicators, "key_level_distance", 50.0)))

        # Best candle pattern
        pattern_score = max(
            self._clamp(engulfing_q) * 0.35,
            min(0.35, pin_ratio / 10.0 * 0.35),
            0.15 if inside_bar else 0.0,
        )

        # Pattern context
        context_score = 0.25 if context in (1, 2) else 0.0

        # Proximity to key level (S/R, supply/demand)
        level_score   = max(0.0, 1.0 - key_dist / 50.0) * 0.25

        # Regime alignment
        regime_adj    = 0.15 if regime in (REGIME_TRENDING, REGIME_RANGING) else 0.05

        raw           = pattern_score + context_score + level_score + regime_adj
        confidence    = self._clamp(raw)   # no regime multiplier – it's universal

        reasoning = (
            f"PA engulf={engulfing_q:.2f} pin={pin_ratio:.1f} inside={inside_bar} "
            f"ctx={context} dist={key_dist:.1f}pips "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
