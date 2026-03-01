"""
mm_optimizer.py
FlashEASuite V2 — P4-5: MM Optimizer
=====================================
เลือก MM method ที่ดีที่สุดสำหรับแต่ละ strategy ตาม:
  1. Default MM per strategy (จาก mm_selection_matrix.json)
  2. Regime override (VOLATILE → volatile_mm, RANGING → preferred_mm)
  3. DD override (สูงสุด — บังคับทุกกรณี):
       DD > 10% → MM10 + reduce 50%
       DD > 15% → MM10 + reduce 75%
       DD > 20% → MM10 + stop new trades

Save: 02_Brain/core/intelligence/mm_optimizer.py
"""

import logging
from dataclasses import dataclass, field
from typing import Optional
from enum import IntEnum

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Enums & Constants
# ─────────────────────────────────────────────

class Regime(IntEnum):
    TRENDING = 0
    RANGING  = 1
    VOLATILE = 2
    SQUEEZE  = 3
    UNKNOWN  = 4


# DD thresholds (ตรงกับ mm_selection_matrix.json)
DD_TIER1_PCT: float = 10.0   # reduce 50% → MM10
DD_TIER2_PCT: float = 15.0   # reduce 75% → MM10
DD_TIER3_PCT: float = 20.0   # stop new trades → MM10


# ─────────────────────────────────────────────
# MM Selection Matrix (embedded จาก JSON)
# ─────────────────────────────────────────────

# Default MM per strategy (no DD, no regime override)
DEFAULT_MM: dict[int, str] = {
    1:  "MM04",   # StatArb → Kelly (ชนะสูง + history พอ)
    2:  "MM01",   # ML Ensemble → Fixed Conservative
    3:  "MM01",   # SMC
    4:  "MM01",   # Market Profile
    5:  "MM01",   # Supply/Demand
    6:  "MM08",   # KAMA → Pyramid (trend following)
    7:  "MM01",   # Mean Reversion → Fixed (trade สั้น)
    8:  "MM01",   # Intermarket
    9:  "MM01",   # Session Breakout
    10: "MM08",   # Turtle → Pyramid (trend following ยาว)
    11: "MM01",   # Ichimoku
    12: "MM01",   # Price Action
    13: "MM01",   # FibStoch
    14: "MM03",   # BBSqueeze → ATR-Based (vol-driven)
    15: "MM03",   # Grid → ATR-Based (SL ปรับตาม ATR)
    16: "MM01",   # Spike → Fixed (quick in-out)
}

# Volatile MM per strategy (regime=VOLATILE override)
VOLATILE_MM: dict[int, str] = {
    1:  "MM07",   # StatArb → Percent Volatility
    2:  "MM17",   3:  "MM17",   4:  "MM17",   5:  "MM17",
    6:  "MM16",   # KAMA → Volatility Percentile
    7:  "MM07",   8:  "MM17",   9:  "MM17",
    10: "MM16",   # Turtle → Volatility Percentile
    11: "MM17",   12: "MM17",
    13: "MM07",   14: "MM07",   # FibStoch, BBSqueeze → Vol Target
    15: "MM17",   # Grid → Regime-Based
    16: "MM01",   # Spike → ยังคง Fixed
}

# Regime preferred_mm (จาก regime_overrides)
REGIME_PREFERRED: dict[Regime, list[str]] = {
    Regime.TRENDING:  ["MM03", "MM08", "MM17"],
    Regime.RANGING:   ["MM01", "MM04", "MM07"],
    Regime.VOLATILE:  ["MM10", "MM16", "MM17"],
    Regime.SQUEEZE:   ["MM01", "MM03", "MM07"],
    Regime.UNKNOWN:   ["MM01"],
}

REGIME_AVOID: dict[Regime, list[str]] = {
    Regime.TRENDING:  ["MM05"],
    Regime.RANGING:   ["MM08"],
    Regime.VOLATILE:  ["MM05", "MM06"],
    Regime.SQUEEZE:   ["MM05", "MM06"],
    Regime.UNKNOWN:   [],
}

REGIME_RISK_ADJ: dict[Regime, float] = {
    Regime.TRENDING:  1.0,
    Regime.RANGING:   1.0,
    Regime.VOLATILE:  0.5,   # ลด risk 50% ใน volatile
    Regime.SQUEEZE:   0.8,
    Regime.UNKNOWN:   1.0,
}


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class AccountState:
    """สถานะ account สำหรับ DD calculation"""
    balance: float = 10000.0
    equity: float = 10000.0
    peak_equity: float = 10000.0    # high watermark
    open_positions: int = 0

    @property
    def drawdown_pct(self) -> float:
        """current drawdown % จาก peak"""
        if self.peak_equity <= 0:
            return 0.0
        return max(0.0, (self.peak_equity - self.equity) / self.peak_equity * 100.0)

    def update_peak(self) -> None:
        """อัปเดต peak_equity ถ้า equity สูงกว่า"""
        if self.equity > self.peak_equity:
            self.peak_equity = self.equity


@dataclass
class MMDecision:
    """ผลการเลือก MM method"""
    strategy_id: int
    mm_method: str              # e.g. "MM10"
    risk_multiplier: float      # 1.0=normal, 0.5=half, 0.25=quarter
    dd_override_active: bool    # True ถ้า DD trigger ทำงาน
    stop_new_trades: bool       # True ถ้า DD > 20%
    regime_used: Regime
    dd_pct: float
    reasoning: str

    @property
    def mm_number(self) -> int:
        """คืน MM number เป็น int (MM10 → 10)"""
        try:
            return int(self.mm_method.replace("MM", ""))
        except ValueError:
            return 1


# ─────────────────────────────────────────────
# MMOptimizer
# ─────────────────────────────────────────────

class MMOptimizer:
    """
    เลือก MM method ที่ดีที่สุดสำหรับ strategy + account state

    Priority (สูงสุดไปต่ำสุด):
        1. DD override (DD>10/15/20%) → บังคับ MM10
        2. VOLATILE regime → volatile_mm
        3. Regime preferred_mm ที่ compatible กับ default
        4. Default MM per strategy

    Usage:
        optimizer = MMOptimizer()
        decision = optimizer.select_mm(strategy_id=15, regime=Regime.RANGING,
                                       account_state=account)
        # decision.mm_method → "MM03"
        # decision.risk_multiplier → 1.0
    """

    def select_mm(
        self,
        strategy_id: int,
        regime: Regime,
        account_state: AccountState,
    ) -> MMDecision:
        """
        เลือก MM method สำหรับ strategy × regime × account state

        Args:
            strategy_id:    1-16
            regime:         current market regime
            account_state:  account equity, peak, drawdown

        Returns:
            MMDecision พร้อม mm_method, risk_multiplier, reasoning
        """
        dd_pct = account_state.drawdown_pct

        # ── Priority 1: DD Override ──────────────────────────────────
        if dd_pct >= DD_TIER3_PCT:
            return MMDecision(
                strategy_id=strategy_id,
                mm_method="MM10",
                risk_multiplier=0.0,
                dd_override_active=True,
                stop_new_trades=True,
                regime_used=regime,
                dd_pct=dd_pct,
                reasoning=(
                    f"🚨 DD={dd_pct:.1f}% ≥ {DD_TIER3_PCT}% → EMERGENCY: "
                    f"หยุดเปิด trade ใหม่ ใช้ MM10 จัดการ position ที่เปิดอยู่เท่านั้น"
                ),
            )

        if dd_pct >= DD_TIER2_PCT:
            return MMDecision(
                strategy_id=strategy_id,
                mm_method="MM10",
                risk_multiplier=0.25,   # เหลือ 25%
                dd_override_active=True,
                stop_new_trades=False,
                regime_used=regime,
                dd_pct=dd_pct,
                reasoning=(
                    f"⚠️ DD={dd_pct:.1f}% ≥ {DD_TIER2_PCT}% → "
                    f"บังคับ MM10, ลด risk เหลือ 25% (reduce_75pct)"
                ),
            )

        if dd_pct >= DD_TIER1_PCT:
            return MMDecision(
                strategy_id=strategy_id,
                mm_method="MM10",
                risk_multiplier=0.50,   # เหลือ 50%
                dd_override_active=True,
                stop_new_trades=False,
                regime_used=regime,
                dd_pct=dd_pct,
                reasoning=(
                    f"⚠️ DD={dd_pct:.1f}% ≥ {DD_TIER1_PCT}% → "
                    f"บังคับ MM10, ลด risk เหลือ 50% (reduce_50pct)"
                ),
            )

        # ── Priority 2: VOLATILE regime → volatile_mm ────────────────
        if regime == Regime.VOLATILE:
            mm = VOLATILE_MM.get(strategy_id, "MM17")
            regime_risk = REGIME_RISK_ADJ[Regime.VOLATILE]
            return MMDecision(
                strategy_id=strategy_id,
                mm_method=mm,
                risk_multiplier=regime_risk,
                dd_override_active=False,
                stop_new_trades=False,
                regime_used=regime,
                dd_pct=dd_pct,
                reasoning=(
                    f"📊 Regime=VOLATILE → S{strategy_id:02d} ใช้ {mm} "
                    f"(risk_adj={regime_risk:.0%})"
                ),
            )

        # ── Priority 3: Check if default MM clashes with regime ───────
        default_mm = DEFAULT_MM.get(strategy_id, "MM01")
        avoid_list = REGIME_AVOID.get(regime, [])
        preferred_list = REGIME_PREFERRED.get(regime, ["MM01"])
        regime_risk = REGIME_RISK_ADJ.get(regime, 1.0)

        if default_mm in avoid_list:
            # Default MM ถูก avoid ใน regime นี้ → เลือก preferred แทน
            best_preferred = preferred_list[0] if preferred_list else "MM01"
            reason = (
                f"📊 Regime={regime.name}: default {default_mm} ถูก avoid "
                f"→ เปลี่ยนเป็น {best_preferred} (preferred)"
            )
            mm = best_preferred
        else:
            # Default MM ยังใช้ได้ใน regime นี้
            mm = default_mm
            reason = (
                f"✅ S{strategy_id:02d} default {mm} "
                f"compatible กับ regime={regime.name} "
                f"(risk_adj={regime_risk:.0%})"
            )

        return MMDecision(
            strategy_id=strategy_id,
            mm_method=mm,
            risk_multiplier=regime_risk,
            dd_override_active=False,
            stop_new_trades=False,
            regime_used=regime,
            dd_pct=dd_pct,
            reasoning=reason,
        )

    def select_all(
        self,
        strategy_ids: list[int],
        regime: Regime,
        account_state: AccountState,
    ) -> dict[int, MMDecision]:
        """เลือก MM สำหรับหลาย strategies พร้อมกัน"""
        return {
            sid: self.select_mm(sid, regime, account_state)
            for sid in strategy_ids
        }

    def get_dd_status(self, account_state: AccountState) -> dict:
        """สรุปสถานะ DD สำหรับ CONFIG_PUSH reasoning"""
        dd = account_state.drawdown_pct
        if dd >= DD_TIER3_PCT:
            level = "EMERGENCY"
        elif dd >= DD_TIER2_PCT:
            level = "CRITICAL"
        elif dd >= DD_TIER1_PCT:
            level = "WARNING"
        else:
            level = "NORMAL"
        return {
            "dd_pct": round(dd, 2),
            "level": level,
            "override_active": dd >= DD_TIER1_PCT,
        }


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )

    print("=" * 60)
    print("FlashEASuite V2 — MM Optimizer Test")
    print("=" * 60)

    optimizer = MMOptimizer()

    # ── Test 1: Normal (no DD) ────────────────────────────────────────
    print("\n── Test 1: Normal regime selections ──")
    account_normal = AccountState(balance=10000, equity=9900, peak_equity=10000)
    print(f"  DD = {account_normal.drawdown_pct:.1f}%")

    test_cases = [
        (1,  Regime.RANGING,  "S01 StatArb RANGING"),
        (6,  Regime.TRENDING, "S06 KAMA TRENDING"),
        (15, Regime.RANGING,  "S15 Grid RANGING"),
        (16, Regime.VOLATILE, "S16 Spike VOLATILE"),
        (6,  Regime.RANGING,  "S06 KAMA RANGING (avoid MM08?)"),
    ]
    for sid, regime, label in test_cases:
        d = optimizer.select_mm(sid, regime, account_normal)
        print(f"  {label}: → {d.mm_method} (×{d.risk_multiplier:.2f}) | {d.reasoning}")

    # ── Test 2: DD Override ───────────────────────────────────────────
    print("\n── Test 2: DD Override tiers ──")
    dd_cases = [
        AccountState(10000, 9100, 10000),   # DD=9% → normal
        AccountState(10000, 8900, 10000),   # DD=11% → tier1
        AccountState(10000, 8400, 10000),   # DD=16% → tier2
        AccountState(10000, 7900, 10000),   # DD=21% → tier3
    ]
    for acct in dd_cases:
        d = optimizer.select_mm(15, Regime.RANGING, acct)
        flag = "🚨" if d.stop_new_trades else ("⚠️" if d.dd_override_active else "✅")
        print(
            f"  {flag} DD={acct.drawdown_pct:.1f}%: "
            f"{d.mm_method} ×{d.risk_multiplier:.2f} | stop={d.stop_new_trades}"
        )

    # ── Test 3: Verify avoid logic ────────────────────────────────────
    print("\n── Test 3: Avoid list check ──")
    # S06 KAMA default=MM08 (Pyramid) → RANGING avoids MM08 → should switch
    d = optimizer.select_mm(6, Regime.RANGING, account_normal)
    assert d.mm_method != "MM08", f"S06 should NOT use MM08 in RANGING! Got {d.mm_method}"
    print(f"  S06 RANGING: {d.mm_method} (✅ NOT MM08 — correctly avoided)")

    # S16 Spike always MM01 even in VOLATILE (quick in-out design)
    d16 = optimizer.select_mm(16, Regime.VOLATILE, account_normal)
    assert d16.mm_method == "MM01", f"S16 VOLATILE should be MM01! Got {d16.mm_method}"
    print(f"  S16 VOLATILE: {d16.mm_method} (✅ correctly stays MM01)")

    # ── Test 4: select_all ────────────────────────────────────────────
    print("\n── Test 4: select_all (16 strategies) ──")
    all_decisions = optimizer.select_all(list(range(1, 17)), Regime.RANGING, account_normal)
    mm_counts: dict[str, int] = {}
    for sid, d in all_decisions.items():
        mm_counts[d.mm_method] = mm_counts.get(d.mm_method, 0) + 1
    print(f"  MM distribution: {mm_counts}")

    print("\n✅ All tests passed!")
