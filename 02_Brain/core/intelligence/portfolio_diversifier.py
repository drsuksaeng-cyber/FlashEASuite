"""
portfolio_diversifier.py
FlashEASuite V2 — P4-3: Portfolio Diversifier
=============================================
ตรวจสอบ portfolio concentration และ correlation ก่อน execute

Rules (V6 spec):
  1. Strategy concentration < 40%  → หนึ่ง strategy ไม่เกิน 40% ของ portfolio
  2. Symbol exposure < 15%          → exposure ต่อ symbol ไม่เกิน 15%
  3. Correlation > 0.7             → ลด weight 50%

Save: 02_Brain/core/intelligence/portfolio_diversifier.py
"""

import logging
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

MAX_STRATEGY_CONCENTRATION: float = 0.40   # สูงสุด 40% ต่อ strategy
MAX_SYMBOL_EXPOSURE: float = 0.15          # สูงสุด 15% ต่อ symbol
HIGH_CORRELATION_THRESHOLD: float = 0.70   # correlation > 0.7 → reduce 50%
CORRELATION_REDUCTION_FACTOR: float = 0.50  # ลด weight 50%


# ─────────────────────────────────────────────
# Built-in strategy correlation table
# คู่ที่มีกลยุทธ์คล้ายกันมาก → correlation สูง
# ─────────────────────────────────────────────
# Format: {(sid_a, sid_b): correlation_estimate}
STRATEGY_CORRELATION_ESTIMATES: dict[tuple[int, int], float] = {
    (1, 7):   0.75,   # StatArb ↔ MeanReversion (ทั้งคู่ mean-reverting)
    (1, 13):  0.72,   # StatArb ↔ FibStoch (reversal-based)
    (7, 13):  0.78,   # MeanReversion ↔ FibStoch
    (7, 14):  0.71,   # MeanReversion ↔ BBSqueeze (ranging)
    (4, 15):  0.73,   # MarketProfile ↔ Grid (ranging market tools)
    (3, 9):   0.72,   # SMC ↔ SessionBreakout (breakout family)
    (3, 10):  0.74,   # SMC ↔ Turtle (trend-following breakout)
    (9, 10):  0.80,   # SessionBreakout ↔ Turtle (both breakout)
    (6, 11):  0.76,   # KAMA ↔ Ichimoku (trend-following)
    (6, 10):  0.71,   # KAMA ↔ Turtle (trend-following)
}


def get_strategy_correlation(sid_a: int, sid_b: int) -> float:
    """ดึงค่า correlation ระหว่าง 2 strategy (symmetric)"""
    if sid_a == sid_b:
        return 1.0
    key = (min(sid_a, sid_b), max(sid_a, sid_b))
    return STRATEGY_CORRELATION_ESTIMATES.get(key, 0.0)


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class PortfolioState:
    """
    สถานะปัจจุบันของ portfolio ที่ active อยู่
    ใช้คำนวณ concentration และ exposure
    """
    total_positions: int = 0               # จำนวน position ทั้งหมดที่ active
    strategy_counts: dict[int, int] = field(default_factory=dict)   # {sid: count}
    symbol_counts: dict[str, int] = field(default_factory=dict)     # {symbol: count}
    active_strategy_ids: list[int] = field(default_factory=list)    # list of active sids

    def strategy_concentration(self, strategy_id: int) -> float:
        """% ของ portfolio ที่ใช้ strategy นี้"""
        if self.total_positions == 0:
            return 0.0
        return self.strategy_counts.get(strategy_id, 0) / self.total_positions

    def symbol_exposure(self, symbol: str) -> float:
        """% ของ portfolio ที่ expose กับ symbol นี้"""
        if self.total_positions == 0:
            return 0.0
        return self.symbol_counts.get(symbol, 0) / self.total_positions


@dataclass
class DiversificationResult:
    """ผลลัพธ์จาก diversification check"""
    strategy_id: int
    symbol: str
    original_weight: float
    adjusted_weight: float
    allowed: bool
    reason: str

    @property
    def weight_reduction_pct(self) -> float:
        if self.original_weight == 0:
            return 0.0
        return (1.0 - self.adjusted_weight / self.original_weight) * 100.0


# ─────────────────────────────────────────────
# PortfolioDiversifier
# ─────────────────────────────────────────────

class PortfolioDiversifier:
    """
    ตรวจสอบ 3 เงื่อนไข:
    1. Strategy concentration < 40%
    2. Symbol exposure < 15%
    3. Correlation > 0.7 → reduce weight 50%

    ถ้า violation ข้อ 1 หรือ 2 → block (allowed=False)
    ถ้า correlation สูง → reduce weight (allowed=True แต่ adjusted_weight ต่ำลง)
    """

    def check(
        self,
        strategy_id: int,
        symbol: str,
        weight: float,
        portfolio: PortfolioState,
    ) -> DiversificationResult:
        """ตรวจสอบ strategy 1 ตัวว่า eligible ไหม"""

        adjusted = weight
        reasons = []

        # ── Rule 1: Strategy concentration ──────────────────────────────
        concentration = portfolio.strategy_concentration(strategy_id)
        if concentration >= MAX_STRATEGY_CONCENTRATION:
            return DiversificationResult(
                strategy_id=strategy_id,
                symbol=symbol,
                original_weight=weight,
                adjusted_weight=0.0,
                allowed=False,
                reason=(
                    f"Strategy S{strategy_id:02d} concentration "
                    f"{concentration:.0%} ≥ {MAX_STRATEGY_CONCENTRATION:.0%} limit"
                )
            )

        # ── Rule 2: Symbol exposure ──────────────────────────────────────
        exposure = portfolio.symbol_exposure(symbol)
        if exposure >= MAX_SYMBOL_EXPOSURE:
            return DiversificationResult(
                strategy_id=strategy_id,
                symbol=symbol,
                original_weight=weight,
                adjusted_weight=0.0,
                allowed=False,
                reason=(
                    f"Symbol {symbol} exposure "
                    f"{exposure:.0%} ≥ {MAX_SYMBOL_EXPOSURE:.0%} limit"
                )
            )

        # ── Rule 3: Correlation reduction ───────────────────────────────
        high_corr_partners = []
        for active_sid in portfolio.active_strategy_ids:
            if active_sid == strategy_id:
                continue
            corr = get_strategy_correlation(strategy_id, active_sid)
            if corr > HIGH_CORRELATION_THRESHOLD:
                high_corr_partners.append((active_sid, corr))
                adjusted *= CORRELATION_REDUCTION_FACTOR

        if high_corr_partners:
            partner_str = ", ".join(
                f"S{s:02d}(corr={c:.2f})" for s, c in high_corr_partners
            )
            reasons.append(
                f"Correlation reduction ×{CORRELATION_REDUCTION_FACTOR} with {partner_str}"
            )
            # Floor: ไม่ให้ adjusted ต่ำกว่า 0.1 (ยังให้ผ่าน แต่ weight ต่ำ)
            adjusted = max(0.1, adjusted)

        reason_str = "; ".join(reasons) if reasons else "OK"

        return DiversificationResult(
            strategy_id=strategy_id,
            symbol=symbol,
            original_weight=weight,
            adjusted_weight=adjusted,
            allowed=True,
            reason=reason_str,
        )

    def filter_candidates(
        self,
        candidates: list[tuple[int, str, float]],   # [(sid, symbol, weight)]
        portfolio: PortfolioState,
    ) -> list[tuple[int, str, float, DiversificationResult]]:
        """
        Filter candidates ทั้งหมด
        Returns: [(sid, symbol, adjusted_weight, result), ...]
        เฉพาะรายการที่ allowed=True
        """
        results = []
        # Process ทีละตัว — แต่ละ candidate ที่ผ่านจะ affect portfolio state ของถัดไป
        working_portfolio = PortfolioState(
            total_positions=portfolio.total_positions,
            strategy_counts=dict(portfolio.strategy_counts),
            symbol_counts=dict(portfolio.symbol_counts),
            active_strategy_ids=list(portfolio.active_strategy_ids),
        )

        for sid, sym, w in candidates:
            result = self.check(sid, sym, w, working_portfolio)
            if result.allowed:
                results.append((sid, sym, result.adjusted_weight, result))
                # Update working portfolio state
                working_portfolio.total_positions += 1
                working_portfolio.strategy_counts[sid] = working_portfolio.strategy_counts.get(sid, 0) + 1
                working_portfolio.symbol_counts[sym] = working_portfolio.symbol_counts.get(sym, 0) + 1
                if sid not in working_portfolio.active_strategy_ids:
                    working_portfolio.active_strategy_ids.append(sid)
                logger.debug(
                    f"  ✅ S{sid:02d}@{sym} weight={result.adjusted_weight:.3f} | {result.reason}"
                )
            else:
                logger.debug(
                    f"  ❌ S{sid:02d}@{sym} BLOCKED | {result.reason}"
                )

        return results


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────
if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG)

    diversifier = PortfolioDiversifier()

    # สร้าง mock portfolio: มี 10 positions อยู่แล้ว, S15@XAUUSD 4 ตัว (40%)
    portfolio = PortfolioState(
        total_positions=10,
        strategy_counts={15: 4, 6: 2, 9: 2, 16: 2},
        symbol_counts={"XAUUSD": 7, "EURUSD": 2, "GBPUSD": 1},
        active_strategy_ids=[15, 6, 9, 16],
    )

    candidates = [
        (15, "XAUUSD", 0.80),   # S15 concentration 40% → BLOCK
        (7,  "XAUUSD", 0.70),   # Symbol exposure สูง แต่ < 15% (7/11 > 15%?) → check
        (1,  "EURUSD", 0.75),   # S01 ↔ S07 correlation 0.75 → reduce
        (6,  "GBPUSD", 0.65),   # ปกติ
    ]

    print("\n─── Portfolio Diversifier Test ───")
    results = diversifier.filter_candidates(candidates, portfolio)
    print(f"\nPassd: {len(results)}/{len(candidates)}")
    for sid, sym, w, r in results:
        reduction = r.weight_reduction_pct
        tag = f"(-{reduction:.0f}%)" if reduction > 0 else ""
        print(f"  S{sid:02d}@{sym}: weight={w:.3f} {tag} | {r.reason}")
