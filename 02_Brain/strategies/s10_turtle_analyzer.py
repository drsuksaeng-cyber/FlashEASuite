"""
s10_turtle_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Turtle Breakout (20-week high/low system):
  - price_vs_20wk_high  → how close price is to 20-week high (pips)
  - price_vs_20wk_low   → how close price is to 20-week low (pips)
  - adx                 → trend strength
  - momentum_ratio      → recent speed of price movement
  - consecutive_breaks  → number of recent new highs/lows (streak)
Regime: TRENDING best
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_TRENDING


class S10TurtleAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S10"
    def get_name(self) -> str: return "Turtle Breakout (20-week)"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_TRENDING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        dist_high  = abs(float(self._safe_get(indicators, "price_vs_20wk_high", 100.0)))  # pips
        dist_low   = abs(float(self._safe_get(indicators, "price_vs_20wk_low",  100.0)))
        adx        = float(self._safe_get(indicators, "adx",              20.0))
        mom_ratio  = float(self._safe_get(indicators, "momentum_ratio",    1.0))
        consec     = float(self._safe_get(indicators, "consecutive_breaks", 0.0))

        # Closer to breakout level = higher confidence
        dist_score  = max(0.0, 1.0 - min(dist_high, dist_low) / 100.0) * 0.30

        # ADX (trend must exist)
        adx_score   = self._normalize(adx, 20.0, 50.0) * 0.30

        # Momentum
        mom_score   = self._normalize(mom_ratio, 0.5, 2.5) * 0.25

        # Streak bonus
        streak_score = min(0.15, consec * 0.05)

        raw          = dist_score + adx_score + mom_score + streak_score
        confidence   = self._apply_regime(raw, regime)

        reasoning = (
            f"Turtle dist_break={min(dist_high, dist_low):.1f}pips "
            f"ADX={adx:.1f} mom={mom_ratio:.2f} streak={consec:.0f} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
