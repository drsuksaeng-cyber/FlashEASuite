"""
s13_fib_stoch_analyzer.py
FlashEASuite V2 | 02_Brain/strategies/

Fibonacci + Stochastic combination:
  - fib_level        → key fib level nearby (0.382, 0.5, 0.618, 0.786)
  - fib_distance     → distance from fib level (pips)
  - stoch_k          → %K value (0–100)
  - stoch_d          → %D value for cross detection
  - stoch_oversold   → %K < 20
  - stoch_overbought → %K > 80
Regime: RANGING best (pullback strategy)
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING


class S13FibStochAnalyzer(BaseAnalyzer):

    def get_id(self)   -> str: return "S13"
    def get_name(self) -> str: return "Fibonacci + Stochastic"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_RANGING]

    def analyze(
        self, symbol: str, regime: str,
        indicators: Dict[str, Any],
        history: Optional[list] = None,
    ) -> AnalysisResult:

        fib_level   = float(self._safe_get(indicators, "fib_level",       0.618))
        fib_dist    = abs(float(self._safe_get(indicators, "fib_distance", 20.0)))  # pips
        stoch_k     = float(self._safe_get(indicators, "stoch_k",          50.0))
        stoch_d     = float(self._safe_get(indicators, "stoch_d",          50.0))
        at_key_fib  = fib_level in (0.382, 0.5, 0.618, 0.786)

        # Key fib level bonus
        fib_bonus   = 0.10 if at_key_fib else 0.0

        # Proximity to fib level
        prox_score  = max(0.0, 1.0 - fib_dist / 30.0) * 0.30

        # Stochastic extremes
        stoch_extreme = max(0.0, 20.0 - stoch_k, stoch_k - 80.0) / 20.0
        stoch_score   = min(0.30, stoch_extreme * 0.30)

        # K/D cross (divergence signal)
        kd_diff_score = min(0.20, abs(stoch_k - stoch_d) / 50.0 * 0.20)

        raw           = fib_bonus + prox_score + stoch_score + kd_diff_score
        confidence    = self._apply_regime(raw, regime)

        reasoning = (
            f"FibStoch fib={fib_level:.3f} dist={fib_dist:.1f}pips "
            f"K={stoch_k:.1f} D={stoch_d:.1f} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning)
