"""
s03_smc_analyzer.py — Smart Money Concept (SMC) Analyzer
FlashEASuite V2 | 02_Brain/strategies/

Confidence factors:
  - BOS (Break of Structure) detected        → +0.35
  - CHoCH (Change of Character) detected     → +0.25
  - Order Block (OB) present near price      → +0.20
  - Fair Value Gap (FVG) present             → +0.15
  - ADX (trend strength)                     → up to +0.15 bonus
Regime: TRENDING best, RANGING poor
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_TRENDING, REGIME_RANGING


class S03SmcAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S03"
    def get_name(self) -> str: return "Smart Money Concept (SMC)"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_TRENDING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        bos_detected   = bool(self._safe_get(indicators, "bos_detected",   False))
        choch_detected = bool(self._safe_get(indicators, "choch_detected", False))
        ob_near_price  = bool(self._safe_get(indicators, "ob_near_price",  False))
        fvg_present    = bool(self._safe_get(indicators, "fvg_present",    False))
        adx            = float(self._safe_get(indicators, "adx",            20.0))

        raw = 0.0
        parts = []

        if bos_detected:
            raw += 0.35
            parts.append("BOS+0.35")
        if choch_detected:
            raw += 0.25
            parts.append("CHoCH+0.25")
        if ob_near_price:
            raw += 0.20
            parts.append("OB+0.20")
        if fvg_present:
            raw += 0.15
            parts.append("FVG+0.15")

        # ADX bonus (0–15 pts)
        adx_bonus = min(0.15, (adx - 20.0) / 200.0) if adx > 20 else 0.0
        raw += adx_bonus

        raw = self._clamp(raw)
        confidence = self._apply_regime(raw, regime)

        reasoning = (
            f"SMC raw={raw:.2f} [{', '.join(parts) or 'no_signals'}] "
            f"ADX={adx:.1f} regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
