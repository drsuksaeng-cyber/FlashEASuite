"""
s07_mean_reversion_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Confidence based on mean-reversion conditions:
  - zscore         → |Z-Score| higher = more extreme deviation = better setup
  - bb_position    → 0=lower band, 1=upper band (extreme = better)
  - rsi            → extreme readings (<30 or >70)
  - price_vs_ma    → distance from MA (normalised)
  - atr_normal     → normal ATR (not spike volatile)
Regime: RANGING best
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING


class S07MeanReversionAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S07"
    def get_name(self) -> str: return "Mean Reversion"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_RANGING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        zscore      = abs(float(self._safe_get(indicators, "zscore",      0.0)))
        bb_pos      = float(self._safe_get(indicators, "bb_position",     0.5))   # 0–1
        rsi         = float(self._safe_get(indicators, "rsi",             50.0))
        price_vs_ma = abs(float(self._safe_get(indicators, "price_vs_ma", 0.0)))  # pips
        atr_ratio   = float(self._safe_get(indicators, "atr_ratio",       1.0))   # ATR/MA(ATR)

        # Z-Score: 0–3+ range → confidence (higher = better, cap at Z=3)
        z_score_conf = self._normalize(zscore, 0.5, 3.0) * 0.30

        # BB extremity: how far from 0.5 centre
        bb_score     = abs(bb_pos - 0.5) * 2.0 * 0.20   # 0–0.20

        # RSI extremity
        rsi_extreme  = max(0.0, 30.0 - rsi, rsi - 70.0) / 30.0
        rsi_score    = min(0.20, rsi_extreme * 0.20)

        # Price vs MA (pips)
        pvma_score   = min(0.15, price_vs_ma / 100.0 * 0.15)

        # ATR near normal (ratio ~1.0) = stable ranging = better
        atr_score    = max(0.0, 1.0 - abs(atr_ratio - 1.0)) * 0.15

        raw          = z_score_conf + bb_score + rsi_score + pvma_score + atr_score
        confidence   = self._apply_regime(raw, regime)

        reasoning = (
            f"MeanRev |Z|={zscore:.2f} BB_pos={bb_pos:.2f} RSI={rsi:.1f} "
            f"pvma={price_vs_ma:.1f} ATR_ratio={atr_ratio:.2f} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
