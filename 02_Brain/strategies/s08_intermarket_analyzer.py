"""
s08_intermarket_analyzer.py — Hybrid Analyzer
FlashEASuite V2 | 02_Brain/strategies/

Intermarket Analysis (DXY / Gold / Bonds correlation):
  Confidence: correlation strength + directional alignment
  Hybrid extras (sent via CONFIG_PUSH):
    - correlation          → DXY correlation value (−1 to +1)
    - dxy_direction        → +1 (rising DXY), -1 (falling), 0 (neutral)
    - leading_symbol       → which intermarket is leading
    - divergence_detected  → price diverging from correlated market

Regime: TRENDING best (intermarket works best in trending conditions)

Author: FlashEASuite V2 Dev | P4-2
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_TRENDING

logger = logging.getLogger(__name__)

# Known inverse/direct correlation pairs with DXY
_DXY_CORRELATION_DIRECTION = {
    "XAUUSDtp":  -1,   # Gold inverse DXY
    "EURUSDtp":  -1,   # EUR inverse DXY
    "GBPUSDtp":  -1,
    "AUDUSDtp":  -1,
    "NZDUSDtp":  -1,
    "USDJPYtp":  +1,   # USD pairs direct DXY
    "USDCHFtp":  +1,
    "USDCADtp":  +1,
}


class S08IntermarketAnalyzer(BaseAnalyzer):
    """
    Hybrid analyzer: DXY correlation + bond/commodity signals.
    extra_params carries DXY direction for CONFIG_PUSH to MQL5.
    """

    def get_id(self)   -> str: return "S08"
    def get_name(self) -> str: return "Intermarket / DXY Correlation"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_TRENDING]

    def analyze(
        self,
        symbol:     str,
        regime:     str,
        indicators: Dict[str, Any],
        history:    Optional[List[Dict[str, Any]]] = None,
    ) -> AnalysisResult:

        # ── Indicators ────────────────────────────────────────────────
        dxy_corr        = float(self._safe_get(indicators, "dxy_correlation",    0.0))
        dxy_momentum    = float(self._safe_get(indicators, "dxy_momentum",       0.0))  # rate of change
        dxy_vs_ma       = float(self._safe_get(indicators, "dxy_vs_ma",          0.0))  # DXY - MA(DXY)
        gold_corr       = float(self._safe_get(indicators, "gold_correlation",   0.0))  # XAU vs symbol
        bond_yield_chg  = float(self._safe_get(indicators, "bond_yield_change",  0.0))  # 10Y yield delta
        divergence_flag = bool(self._safe_get(indicators,  "divergence_detected", False))

        # ── DXY direction ─────────────────────────────────────────────
        if   dxy_momentum >  0.05: dxy_direction = 1
        elif dxy_momentum < -0.05: dxy_direction = -1
        else:                      dxy_direction = 0

        # ── Correlation quality ───────────────────────────────────────
        # Strong abs correlation (>0.7) = better signal alignment
        abs_corr      = abs(dxy_corr)
        corr_score    = self._normalize(abs_corr, 0.3, 0.9) * 0.30

        # ── DXY directional clarity ───────────────────────────────────
        dxy_strength  = self._normalize(abs(dxy_vs_ma), 0.0, 2.0) * 0.25

        # ── DXY momentum ─────────────────────────────────────────────
        mom_score     = min(0.20, abs(dxy_momentum) * 10.0)

        # ── Bond yield alignment (higher yields → DXY up often) ──────
        bond_score    = min(0.15, abs(bond_yield_chg) / 0.20 * 0.15)

        # ── Divergence bonus (rare but strong signal) ─────────────────
        div_score     = 0.10 if divergence_flag else 0.0

        raw           = corr_score + dxy_strength + mom_score + bond_score + div_score
        confidence    = self._apply_regime(raw, regime)

        # ── Determine leading symbol ─────────────────────────────────
        leading = "DXY" if abs(dxy_corr) > abs(gold_corr) else "XAUUSD"

        extra = {
            "correlation":         round(dxy_corr, 4),
            "dxy_direction":       dxy_direction,
            "dxy_leading":         leading,
            "divergence_detected": divergence_flag,
            "bond_yield_delta":    round(bond_yield_chg, 4),
        }

        reasoning = (
            f"Intermarket DXY_corr={dxy_corr:.3f} dxy_dir={dxy_direction} "
            f"dxy_mom={dxy_momentum:.4f} bond_chg={bond_yield_chg:.4f} "
            f"divergence={divergence_flag} leading={leading} "
            f"regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning,
                              extra_params=extra)

    # ------------------------------------------------------------------
    @classmethod
    def get_expected_dxy_direction(cls, symbol: str) -> int:
        """
        Return expected DXY impact direction for a given symbol.
        e.g. XAUUSD: DXY rising → bearish for Gold → direction = -1
        Called by engine.py to filter alignment.
        """
        return _DXY_CORRELATION_DIRECTION.get(symbol, 0)
