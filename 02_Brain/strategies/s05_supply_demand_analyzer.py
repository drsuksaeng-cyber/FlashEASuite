"""
s05_supply_demand_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Confidence based on Supply / Demand zones:
  - zone_count    → how many valid zones exist
  - zone_strength → average strength of zones (0–1)
  - price_at_zone → price currently at a S/D zone
  - fresh_zone    → zone is unmitigated (higher priority)
  - zone_rr       → expected R:R from nearest zone
Regime: RANGING best, TRENDING also viable
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING, REGIME_TRENDING


class S05SupplyDemandAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S05"
    def get_name(self) -> str: return "Supply & Demand Zones"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_RANGING, REGIME_TRENDING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        zone_count    = float(self._safe_get(indicators, "zone_count",    2.0))
        zone_strength = float(self._safe_get(indicators, "zone_strength", 0.5))
        price_at_zone = bool(self._safe_get(indicators,  "price_at_zone", False))
        fresh_zone    = bool(self._safe_get(indicators,  "fresh_zone",    False))
        zone_rr       = float(self._safe_get(indicators, "zone_rr",       1.5))

        zone_score    = self._normalize(zone_count, 1.0, 6.0) * 0.20
        strength_score = self._clamp(zone_strength) * 0.25
        at_zone_score  = 0.25 if price_at_zone else 0.0
        fresh_score    = 0.15 if fresh_zone else 0.0
        rr_score       = min(0.15, (zone_rr - 1.0) / 10.0)

        raw        = zone_score + strength_score + at_zone_score + fresh_score + rr_score
        confidence = self._apply_regime(raw, regime)

        reasoning = (
            f"S&D zones={zone_count:.0f} str={zone_strength:.2f} "
            f"at_zone={price_at_zone} fresh={fresh_zone} R:R={zone_rr:.1f} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
