"""
s01_stat_arb_analyzer.py — Hybrid Analyzer
FlashEASuite V2 | 02_Brain/strategies/

Statistical Arbitrage (Pairs Trading):
  Confidence: Z-Score extremity + correlation + cointegration quality
  Hybrid extras (sent via CONFIG_PUSH):
    - selected_pair  → best pair to trade with current symbol
    - beta           → hedge ratio for the pair
    - cointegration_pvalue → statistical validity

Confidence logic (spec):
  Z-Score more extreme → higher confidence
  regime=RANGING bonus applies

Author: FlashEASuite V2 Dev | P4-2
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING

logger = logging.getLogger(__name__)


class S01StatArbAnalyzer(BaseAnalyzer):
    """
    Hybrid analyzer: computes confidence + pair selection parameters.
    extra_params carries data for CONFIG_PUSH to MQL5.
    """

    # Pairs to evaluate against (can be extended)
    CANDIDATE_PAIRS: Dict[str, List[str]] = {
        "XAUUSDtp":  ["XAGUSDtp"],
        "EURUSDtp":  ["GBPUSDtp", "AUDUSDtp"],
        "GBPUSDtp":  ["EURUSDtp", "AUDUSDtp"],
        "USDJPYtp":  ["USDCHFtp"],
        "default":   ["EURUSDtp", "GBPUSDtp"],
    }

    def get_id(self)   -> str: return "S01"
    def get_name(self) -> str: return "Statistical Arbitrage (Pairs)"

    def get_preferred_regimes(self) -> List[str]:
        return [REGIME_RANGING]

    def analyze(
        self,
        symbol:     str,
        regime:     str,
        indicators: Dict[str, Any],
        history:    Optional[List[Dict[str, Any]]] = None,
    ) -> AnalysisResult:

        # ── Indicators ────────────────────────────────────────────────
        zscore         = float(self._safe_get(indicators, "zscore",          0.0))
        correlation    = float(self._safe_get(indicators, "correlation",     0.5))
        coint_pvalue   = float(self._safe_get(indicators, "coint_pvalue",    1.0))  # 0=perfect
        beta           = float(self._safe_get(indicators, "beta",            1.0))
        pair_prices    = dict(self._safe_get(indicators,  "pair_prices",     {}))

        # ── Cointegration validity ─────────────────────────────────────
        # p-value < 0.05 = cointegrated (conf boost)
        coint_score    = max(0.0, (0.10 - coint_pvalue) / 0.10) * 0.25 \
                         if coint_pvalue <= 0.10 else 0.0

        # ── Z-Score extremity (spec: higher abs Z → higher conf) ────────
        abs_z          = abs(zscore)
        if abs_z < 1.0:
            z_score    = 0.0
        elif abs_z < 2.0:
            z_score    = self._normalize(abs_z, 1.0, 2.0) * 0.30
        else:
            z_score    = 0.30 + self._normalize(abs_z, 2.0, 4.0) * 0.15

        # ── Correlation quality ───────────────────────────────────────
        corr_score     = max(0.0, (correlation - 0.5) / 0.5) * 0.20

        # ── Beta reasonableness (0.5–2.0 is practical) ───────────────
        beta_score     = max(0.0, 1.0 - abs(beta - 1.0) / 1.0) * 0.10

        raw            = coint_score + z_score + corr_score + beta_score
        confidence     = self._apply_regime(raw, regime)

        # ── Pair selection (best candidate for this symbol) ───────────
        selected_pair  = self._select_best_pair(symbol, pair_prices, correlation)

        # ── Extra params for CONFIG_PUSH ──────────────────────────────
        extra = {
            "stat_arb_pair":        selected_pair,
            "stat_arb_beta":        round(beta, 4),
            "stat_arb_zscore":      round(zscore, 4),
            "stat_arb_coint_pval":  round(coint_pvalue, 4),
            "stat_arb_correlation": round(correlation, 4),
        }

        reasoning = (
            f"StatArb |Z|={abs_z:.2f} corr={correlation:.3f} "
            f"coint_p={coint_pvalue:.3f} beta={beta:.3f} "
            f"pair={selected_pair} regime={regime} → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning,
                              extra_params=extra)

    # ------------------------------------------------------------------
    def _select_best_pair(
        self,
        symbol:      str,
        pair_prices: Dict[str, float],
        correlation: float,
    ) -> str:
        """Select the best correlated pair for the given symbol."""
        candidates = self.CANDIDATE_PAIRS.get(symbol,
                     self.CANDIDATE_PAIRS["default"])
        # If prices provided, pick first available; otherwise first candidate
        for p in candidates:
            if p in pair_prices:
                return p
        return candidates[0] if candidates else "EURUSDtp"

    # ------------------------------------------------------------------
    @staticmethod
    def compute_zscore_from_history(
        spread_series: List[float],
        window: int = 20,
    ) -> Tuple[float, float]:
        """
        Utility: compute rolling Z-Score of a spread series.
        Returns (current_zscore, rolling_std).
        Called by engine.py when building indicators dict.
        """
        if len(spread_series) < window:
            return 0.0, 0.0
        arr = np.array(spread_series[-window:], dtype=float)
        mean = arr.mean()
        std  = arr.std()
        if std < 1e-10:
            return 0.0, 0.0
        return float((spread_series[-1] - mean) / std), float(std)

    @staticmethod
    def compute_beta_ols(x: List[float], y: List[float]) -> float:
        """
        Utility: OLS beta (hedge ratio) between two price series.
        beta = Cov(x,y) / Var(x)
        """
        if len(x) < 10 or len(x) != len(y):
            return 1.0
        xa = np.array(x, dtype=float)
        ya = np.array(y, dtype=float)
        xa_c = xa - xa.mean()
        var_x = float(xa_c @ xa_c)
        if var_x < 1e-12:
            return 1.0
        return float(xa_c @ (ya - ya.mean()) / var_x)
