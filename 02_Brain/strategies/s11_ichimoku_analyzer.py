"""
s11_ichimoku_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Ichimoku Kinko Hyo:
  - price_vs_cloud   → above/below/inside cloud  (+1 / -1 / 0)
  - cloud_thickness  → thicker = stronger support/resistance
  - tenkan_kijun_pos → Tenkan above Kijun = bullish, below = bearish
  - chikou_clear     → Chikou span clear of cloud & candles
  - future_cloud     → cloud colour ahead (bullish/bearish twist)
Regime: TRENDING best
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_TRENDING


class S11IchimokuAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S11"
    def get_name(self) -> str: return "Ichimoku Kinko Hyo"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_TRENDING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        price_vs_cloud   = int(self._safe_get(indicators, "price_vs_cloud",   0))   # +1/0/-1
        cloud_thickness  = float(self._safe_get(indicators, "cloud_thickness", 10.0))  # pips
        tk_cross         = bool(self._safe_get(indicators,  "tenkan_kijun_aligned", False))
        chikou_clear     = bool(self._safe_get(indicators,  "chikou_clear",    False))
        future_cloud_bull = bool(self._safe_get(indicators, "future_cloud_bullish", False))

        # Price position vs cloud (most important)
        cloud_score      = 0.30 if abs(price_vs_cloud) == 1 else 0.0

        # Thick cloud = stronger S/R
        thick_score      = self._normalize(cloud_thickness, 5.0, 50.0) * 0.20

        # TK cross alignment
        tk_score         = 0.20 if tk_cross else 0.0

        # Chikou clear confirmation
        chikou_score     = 0.20 if chikou_clear else 0.0

        # Future cloud colour
        future_score     = 0.10 if future_cloud_bull else 0.0

        raw              = cloud_score + thick_score + tk_score + chikou_score + future_score
        confidence       = self._apply_regime(raw, regime)

        reasoning = (
            f"Ichimoku price_vs_cloud={price_vs_cloud} thickness={cloud_thickness:.1f} "
            f"TK_aligned={tk_cross} chikou={chikou_clear} future_bull={future_cloud_bull} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
