"""
s09_session_breakout_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Session Breakout (London/NY/Asia):
  - session_active      → is a high-probability session active?
  - session_range       → Asian range (pips) – wider = more energy
  - atr                 → volatility context
  - volume_ratio        → current vs average volume
  - time_to_open        → minutes to session open (closer = better setup)
Regime: VOLATILE best (breakout needs expansion), TRENDING also viable
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_VOLATILE, REGIME_TRENDING


class S09SessionBreakoutAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S09"
    def get_name(self) -> str: return "Session Breakout"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_VOLATILE, REGIME_TRENDING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        session_active  = bool(self._safe_get(indicators,  "session_active",  False))
        session_range   = float(self._safe_get(indicators, "session_range",   20.0))  # pips
        atr             = float(self._safe_get(indicators, "atr",             10.0))
        volume_ratio    = float(self._safe_get(indicators, "volume_ratio",    1.0))
        time_to_open    = float(self._safe_get(indicators, "time_to_open",    60.0))  # minutes

        # Session must be active or near open
        session_score   = 0.30 if session_active else max(0.0, 0.15 * (1 - time_to_open / 60.0))

        # Session range vs ATR
        range_atr_ratio = session_range / max(atr, 0.1)
        range_score     = self._normalize(range_atr_ratio, 0.5, 3.0) * 0.30

        # Volume surge
        vol_score       = min(0.25, (volume_ratio - 1.0) * 0.15) if volume_ratio > 1.0 else 0.0

        # ATR normalised (need adequate volatility)
        atr_score       = self._normalize(atr, 5.0, 30.0) * 0.15

        raw             = session_score + range_score + vol_score + atr_score
        confidence      = self._apply_regime(raw, regime)

        reasoning = (
            f"Session active={session_active} range={session_range:.1f}pips "
            f"ATR={atr:.1f} vol_ratio={volume_ratio:.2f} "
            f"t2open={time_to_open:.0f}min regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
