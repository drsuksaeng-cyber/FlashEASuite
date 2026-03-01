"""
s16_spike_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Spike / News Event Adaptation:
  - spike_score      → detected spike intensity (0–1, from existing spike_analyzer.py)
  - atr_spike_ratio  → ATR_current / ATR_normal: >2.0 = spike
  - volume_spike     → volume / MA_volume: >3.0 = spike
  - news_imminent    → high-impact news within 15 min
  - price_momentum   → rapid directional price change (pips/bar)
Regime: VOLATILE best
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_VOLATILE


class S16SpikeAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S16"
    def get_name(self) -> str: return "Spike / News Adaptation"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_VOLATILE]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        spike_score   = float(self._safe_get(indicators, "spike_score",       0.0))
        atr_spike_r   = float(self._safe_get(indicators, "atr_spike_ratio",   1.0))
        vol_spike     = float(self._safe_get(indicators, "volume_spike",       1.0))
        news_imminent = bool(self._safe_get(indicators,  "news_imminent",     False))
        price_mom     = abs(float(self._safe_get(indicators, "price_momentum", 0.0)))

        # Primary: existing spike detector score
        spike_s       = self._clamp(spike_score) * 0.35

        # ATR spike (>2.0 = active spike)
        atr_s         = min(0.25, (atr_spike_r - 1.0) / 3.0 * 0.25) if atr_spike_r > 1.0 else 0.0

        # Volume spike
        vol_s         = min(0.20, (vol_spike - 1.0) / 4.0 * 0.20) if vol_spike > 1.0 else 0.0

        # News imminent bonus
        news_s        = 0.10 if news_imminent else 0.0

        # Price momentum
        mom_s         = min(0.10, price_mom / 50.0 * 0.10)

        raw           = spike_s + atr_s + vol_s + news_s + mom_s
        confidence    = self._apply_regime(raw, regime)

        reasoning = (
            f"Spike spike={spike_score:.3f} ATR_ratio={atr_spike_r:.2f} "
            f"vol_spike={vol_spike:.2f} news={news_imminent} mom={price_mom:.1f} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
