"""
confidence_scorer.py
FlashEASuite V2 — P4-3: AI Council Confidence Scorer
=====================================================
คำนวณ weighted confidence score จาก 5 factors:
  weighted = raw × hist_perf × regime_bonus × calendar × news

Regime Factor Scale (gradual):
  Perfect match → 1.5
  Good          → 1.2
  Neutral       → 1.0
  Poor          → 0.5
  Terrible      → 0.3

Save: 02_Brain/core/intelligence/confidence_scorer.py
"""

import math
import logging
from dataclasses import dataclass, field
from typing import Optional
from enum import IntEnum

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Enums & Constants
# ─────────────────────────────────────────────

class Regime(IntEnum):
    TRENDING  = 0
    RANGING   = 1
    VOLATILE  = 2
    SQUEEZE   = 3
    UNKNOWN   = 4


# Regime compatibility matrix[strategy_id][market_regime] → factor
# ค่าตาม V6 spec: Perfect=1.5, Good=1.2, Neutral=1.0, Poor=0.5, Terrible=0.3
REGIME_FACTOR_MAP: dict[int, dict[Regime, float]] = {
    # S01 StatArb       → ดีสุดใน RANGING
    1:  {Regime.RANGING: 1.5, Regime.SQUEEZE: 1.2, Regime.TRENDING: 0.5, Regime.VOLATILE: 0.3, Regime.UNKNOWN: 1.0},
    # S02 ML Ensemble   → ทำงานได้ทุก regime
    2:  {Regime.TRENDING: 1.2, Regime.RANGING: 1.2, Regime.VOLATILE: 1.2, Regime.SQUEEZE: 1.0, Regime.UNKNOWN: 1.0},
    # S03 SMC           → ดีสุดใน TRENDING/VOLATILE
    3:  {Regime.TRENDING: 1.5, Regime.VOLATILE: 1.2, Regime.RANGING: 0.5, Regime.SQUEEZE: 0.3, Regime.UNKNOWN: 1.0},
    # S04 Market Profile→ ดีใน RANGING
    4:  {Regime.RANGING: 1.5, Regime.TRENDING: 1.0, Regime.VOLATILE: 0.5, Regime.SQUEEZE: 1.2, Regime.UNKNOWN: 1.0},
    # S05 Supply/Demand → ดีใน RANGING/TRENDING
    5:  {Regime.RANGING: 1.5, Regime.TRENDING: 1.2, Regime.VOLATILE: 0.5, Regime.SQUEEZE: 1.0, Regime.UNKNOWN: 1.0},
    # S06 KAMA          → ดีสุดใน TRENDING
    6:  {Regime.TRENDING: 1.5, Regime.RANGING: 0.3, Regime.VOLATILE: 1.0, Regime.SQUEEZE: 0.5, Regime.UNKNOWN: 1.0},
    # S07 Mean Reversion→ ดีใน RANGING/SQUEEZE
    7:  {Regime.RANGING: 1.5, Regime.SQUEEZE: 1.2, Regime.TRENDING: 0.3, Regime.VOLATILE: 0.5, Regime.UNKNOWN: 1.0},
    # S08 Intermarket   → ดีใน TRENDING
    8:  {Regime.TRENDING: 1.5, Regime.VOLATILE: 1.2, Regime.RANGING: 0.5, Regime.SQUEEZE: 0.3, Regime.UNKNOWN: 1.0},
    # S09 Session Breakout → ดีใน TRENDING/VOLATILE
    9:  {Regime.TRENDING: 1.5, Regime.VOLATILE: 1.2, Regime.RANGING: 0.5, Regime.SQUEEZE: 0.3, Regime.UNKNOWN: 1.0},
    # S10 Turtle        → ดีใน TRENDING
    10: {Regime.TRENDING: 1.5, Regime.VOLATILE: 1.0, Regime.RANGING: 0.3, Regime.SQUEEZE: 0.3, Regime.UNKNOWN: 1.0},
    # S11 Ichimoku      → ดีใน TRENDING
    11: {Regime.TRENDING: 1.5, Regime.RANGING: 0.5, Regime.VOLATILE: 1.0, Regime.SQUEEZE: 0.3, Regime.UNKNOWN: 1.0},
    # S12 Price Action  → ดีใน TRENDING/RANGING
    12: {Regime.TRENDING: 1.2, Regime.RANGING: 1.2, Regime.VOLATILE: 1.0, Regime.SQUEEZE: 1.0, Regime.UNKNOWN: 1.0},
    # S13 FibStoch      → ดีใน RANGING
    13: {Regime.RANGING: 1.5, Regime.SQUEEZE: 1.2, Regime.TRENDING: 0.5, Regime.VOLATILE: 0.3, Regime.UNKNOWN: 1.0},
    # S14 BBSqueeze     → ดีสุดใน SQUEEZE
    14: {Regime.SQUEEZE: 1.5, Regime.RANGING: 1.2, Regime.TRENDING: 0.5, Regime.VOLATILE: 0.3, Regime.UNKNOWN: 1.0},
    # S15 Grid          → ดีสุดใน RANGING
    15: {Regime.RANGING: 1.5, Regime.SQUEEZE: 1.2, Regime.TRENDING: 0.3, Regime.VOLATILE: 0.5, Regime.UNKNOWN: 1.0},
    # S16 Spike         → ดีสุดใน VOLATILE
    16: {Regime.VOLATILE: 1.5, Regime.TRENDING: 1.0, Regime.RANGING: 0.3, Regime.SQUEEZE: 0.3, Regime.UNKNOWN: 1.0},
}

# Calendar factor: วัน/ช่วงเวลาที่ดี/ไม่ดีสำหรับ forex
# key: (weekday 0=Mon..4=Fri), value: multiplier
CALENDAR_WEEKDAY_FACTOR = {0: 0.9, 1: 1.0, 2: 1.0, 3: 1.0, 4: 0.8}  # Mon weak, Fri weak


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class ScoringInput:
    """Input data สำหรับ confidence scoring"""
    strategy_id: int                        # 1-16
    symbol: str                             # e.g. "XAUUSD"
    raw_confidence: float                   # 0.0-1.0 จาก analyzer
    expected_rr: float                      # expected Risk:Reward ratio
    regime: Regime                          # current market regime
    hist_perf_factor: float = 1.0           # EMA(accuracy) weight 0.5-1.5, default=1.0
    news_factor: float = 1.0               # news impact 0.5-1.2, default=1.0
    weekday: int = 2                        # 0=Mon..4=Fri, default=Wed


@dataclass
class ScoringResult:
    """ผลลัพธ์จาก confidence scorer"""
    strategy_id: int
    symbol: str
    raw_confidence: float
    weighted_confidence: float
    regime_factor: float
    hist_perf_factor: float
    calendar_factor: float
    news_factor: float
    expected_rr: float
    passed_rr_gate: bool                    # RR >= 1.5
    passed_threshold: bool                  # weighted >= 0.55
    reasoning: str = ""

    @property
    def is_eligible(self) -> bool:
        """ผ่านทั้ง RR gate และ threshold"""
        return self.passed_rr_gate and self.passed_threshold


# ─────────────────────────────────────────────
# ConfidenceScorer
# ─────────────────────────────────────────────

class ConfidenceScorer:
    """
    คำนวณ 5-factor weighted confidence

    Formula:
        weighted = raw × hist_perf × regime_bonus × calendar × news

    Steps:
        1. ดึง regime_factor จาก REGIME_FACTOR_MAP
        2. ดึง calendar_factor จาก weekday
        3. คำนวณ weighted = raw × hist_perf × regime × calendar × news
        4. Clamp ให้อยู่ใน [0.0, 1.0] ก่อน gate check
        5. R:R gate: expected_rr >= 1.5
        6. Threshold gate: weighted >= 0.55
    """

    RR_GATE_MIN: float = 1.5
    CONFIDENCE_THRESHOLD: float = 0.55

    def score(self, inp: ScoringInput) -> ScoringResult:
        """คำนวณ weighted confidence จาก ScoringInput"""

        # 1. Regime factor (gradual scale)
        regime_map = REGIME_FACTOR_MAP.get(inp.strategy_id, {})
        regime_factor = regime_map.get(inp.regime, 1.0)

        # 2. Calendar factor
        calendar_factor = CALENDAR_WEEKDAY_FACTOR.get(inp.weekday, 1.0)

        # 3. Weighted confidence (5 factors)
        weighted = (
            inp.raw_confidence
            * inp.hist_perf_factor
            * regime_factor
            * calendar_factor
            * inp.news_factor
        )

        # 4. Clamp to [0.0, 1.0]
        weighted = min(1.0, max(0.0, weighted))

        # 5. Gate checks
        passed_rr   = inp.expected_rr >= self.RR_GATE_MIN
        passed_thr  = weighted >= self.CONFIDENCE_THRESHOLD

        # 6. Build reasoning string
        regime_name = inp.regime.name if isinstance(inp.regime, Regime) else str(inp.regime)
        reasoning = (
            f"S{inp.strategy_id:02d}@{inp.symbol}: "
            f"raw={inp.raw_confidence:.3f} "
            f"× hist={inp.hist_perf_factor:.2f} "
            f"× regime({regime_name})={regime_factor:.2f} "
            f"× cal={calendar_factor:.2f} "
            f"× news={inp.news_factor:.2f} "
            f"= weighted={weighted:.3f} | "
            f"RR={inp.expected_rr:.2f}{'✓' if passed_rr else '✗'} "
            f"THR={'✓' if passed_thr else '✗'}"
        )

        logger.debug(reasoning)

        return ScoringResult(
            strategy_id=inp.strategy_id,
            symbol=inp.symbol,
            raw_confidence=inp.raw_confidence,
            weighted_confidence=weighted,
            regime_factor=regime_factor,
            hist_perf_factor=inp.hist_perf_factor,
            calendar_factor=calendar_factor,
            news_factor=inp.news_factor,
            expected_rr=inp.expected_rr,
            passed_rr_gate=passed_rr,
            passed_threshold=passed_thr,
            reasoning=reasoning,
        )

    def score_batch(self, inputs: list[ScoringInput]) -> list[ScoringResult]:
        """Score หลาย strategy พร้อมกัน"""
        return [self.score(inp) for inp in inputs]


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────
if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG)
    scorer = ConfidenceScorer()

    # ตัวอย่าง: S15 Grid ใน RANGING regime ควรได้ score สูง
    test_cases = [
        ScoringInput(15, "XAUUSD", raw_confidence=0.65, expected_rr=1.8,
                     regime=Regime.RANGING, hist_perf_factor=1.1, weekday=2),
        ScoringInput(16, "XAUUSD", raw_confidence=0.70, expected_rr=1.2,  # RR < 1.5 → SKIP
                     regime=Regime.VOLATILE, hist_perf_factor=0.9, weekday=4),
        ScoringInput(6,  "EURUSD", raw_confidence=0.80, expected_rr=2.0,
                     regime=Regime.TRENDING, hist_perf_factor=1.2, weekday=1),
    ]

    for tc in test_cases:
        result = scorer.score(tc)
        status = "✅ ELIGIBLE" if result.is_eligible else "❌ SKIP"
        print(f"{status} | {result.reasoning}")
