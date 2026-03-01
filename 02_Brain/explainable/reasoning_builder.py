"""
reasoning_builder.py
FlashEASuite V2 — P4-6: Explainable Reasoning Engine
=====================================================
สร้าง reasoning chain สมบูรณ์สำหรับทุก decision
ส่งไป 4 destinations:
  1. CONFIG_PUSH → reasoning field (ส่งให้ Client)
  2. decision_logger.py → JSON audit trail
  3. CSV report → daily/weekly performance
  4. retrain_feedback.py → auto-retrain trigger

Output structure:
{
  "symbol": "XAUUSD",
  "cycle_id": "20260222_0615",
  "regime": {"type", "method", "confidence", "detail"},
  "votes": [16 × {"strategy", "raw", "hist", "regime_bonus", "cal", "news", "final", "rr", "reasoning"}],
  "selected": [{"rank", "strategy", "score", "allocation"}],
  "mm": {"method", "reasoning"},
  "risk": {"multiplier", "reasoning"},
  "summary_th": "...",
  "summary_en": "..."
}

Save: 02_Brain/explainable/reasoning_builder.py
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Any

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Strategy name lookup
# ─────────────────────────────────────────────

STRATEGY_NAMES: dict[int, str] = {
    1:  "StatArb",        2:  "ML Ensemble",    3:  "SMC",
    4:  "MarketProfile",  5:  "Supply/Demand",  6:  "KAMA",
    7:  "MeanReversion",  8:  "Intermarket",    9:  "SessionBreak",
    10: "Turtle",         11: "Ichimoku",        12: "PriceAction",
    13: "FibStoch",       14: "BBSqueeze",       15: "Grid",
    16: "Spike",
}

MM_NAMES: dict[str, str] = {
    "MM01": "Fixed Fractional Conservative",
    "MM02": "Fixed Fractional Aggressive",
    "MM03": "ATR-Based Dynamic",
    "MM04": "Kelly Criterion (Half-Kelly)",
    "MM05": "Martingale Controlled",
    "MM06": "Anti-Martingale (Snowball)",
    "MM07": "Percent Volatility",
    "MM08": "Pyramid / Scale-In",
    "MM09": "Equity Curve Recovery",
    "MM10": "Drawdown-Based (Tiered)",
    "MM11": "Session-Based Risk",
    "MM12": "Equity Curve Filter",
    "MM13": "Correlation Adjusted",
    "MM14": "Tiered Risk (by Balance)",
    "MM15": "Adaptive Win-Streak",
    "MM16": "Volatility Percentile",
    "MM17": "Regime-Based Scaling",
    "MM18": "Portfolio Risk Cap",
    "MM19": "Dynamic Multi-Method",
}


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class VoteReason:
    """Reasoning สำหรับ 1 strategy vote"""
    strategy_id: int
    raw_confidence: float
    hist_perf_factor: float
    regime_bonus: float
    calendar_factor: float
    news_factor: float
    final_score: float
    expected_rr: float
    passed_rr_gate: bool
    passed_threshold: bool
    reasoning: str = ""

    def to_dict(self) -> dict:
        return {
            "strategy": f"S{self.strategy_id:02d}",
            "name": STRATEGY_NAMES.get(self.strategy_id, "Unknown"),
            "raw": round(self.raw_confidence, 4),
            "hist": round(self.hist_perf_factor, 4),
            "regime_bonus": round(self.regime_bonus, 4),
            "cal": round(self.calendar_factor, 4),
            "news": round(self.news_factor, 4),
            "final": round(self.final_score, 4),
            "rr": round(self.expected_rr, 2),
            "passed_rr": self.passed_rr_gate,
            "passed_thr": self.passed_threshold,
            "eligible": self.passed_rr_gate and self.passed_threshold,
            "reasoning": self.reasoning,
        }


@dataclass
class SelectionReason:
    """Reasoning สำหรับ strategy ที่ถูกเลือก"""
    rank: int
    strategy_id: int
    score: float
    allocation: float        # % allocation (0-100)
    diversification_note: str = ""

    def to_dict(self) -> dict:
        return {
            "rank": self.rank,
            "strategy": f"S{self.strategy_id:02d}",
            "name": STRATEGY_NAMES.get(self.strategy_id, "Unknown"),
            "score": round(self.score, 4),
            "allocation_pct": round(self.allocation, 1),
            "diversification_note": self.diversification_note,
        }


@dataclass
class ReasoningChain:
    """Full reasoning chain สำหรับ 1 symbol per cycle"""
    symbol: str
    cycle_id: str
    timestamp: str

    # Regime
    regime_type: str = "UNKNOWN"
    regime_method: str = "rule_based"
    regime_confidence: float = 0.0
    regime_detail: str = ""

    # Votes (16 strategies)
    votes: list[VoteReason] = field(default_factory=list)

    # Selected strategies
    selected: list[SelectionReason] = field(default_factory=list)

    # MM decision
    mm_method: str = "MM01"
    mm_reasoning: str = ""

    # Risk
    risk_multiplier: float = 1.0
    risk_reasoning: str = ""

    # Summary
    summary_th: str = ""
    summary_en: str = ""

    def to_dict(self) -> dict:
        eligible_count = sum(1 for v in self.votes if v.passed_rr_gate and v.passed_threshold)
        return {
            "symbol": self.symbol,
            "cycle_id": self.cycle_id,
            "timestamp": self.timestamp,
            "regime": {
                "type": self.regime_type,
                "method": self.regime_method,
                "confidence": round(self.regime_confidence, 4),
                "detail": self.regime_detail,
            },
            "votes": [v.to_dict() for v in self.votes],
            "vote_summary": {
                "total": len(self.votes),
                "eligible": eligible_count,
                "selected": len(self.selected),
            },
            "selected": [s.to_dict() for s in self.selected],
            "mm": {
                "method": self.mm_method,
                "name": MM_NAMES.get(self.mm_method, self.mm_method),
                "reasoning": self.mm_reasoning,
            },
            "risk": {
                "multiplier": round(self.risk_multiplier, 4),
                "reasoning": self.risk_reasoning,
            },
            "summary_th": self.summary_th,
            "summary_en": self.summary_en,
        }

    def to_config_push_reasoning(self) -> dict:
        """Compact version สำหรับใส่ใน CONFIG_PUSH (ไม่ต้องส่ง votes ทั้งหมด)"""
        return {
            "cycle_id": self.cycle_id,
            "regime": self.regime_type,
            "regime_confidence": round(self.regime_confidence, 3),
            "selected_strategies": [
                f"S{s.strategy_id:02d}({s.score:.2f})"
                for s in self.selected
            ],
            "mm": self.mm_method,
            "risk_mult": round(self.risk_multiplier, 3),
            "summary_th": self.summary_th,
            "summary_en": self.summary_en,
        }


# ─────────────────────────────────────────────
# ReasoningBuilder
# ─────────────────────────────────────────────

class ReasoningBuilder:
    """
    สร้าง ReasoningChain สมบูรณ์จาก inputs ของ P4-3, P4-5

    Usage:
        builder = ReasoningBuilder()
        chain = builder.build(
            symbol="XAUUSD",
            regime_info={...},
            scoring_results=[...],    # จาก P4-3 StrategyCouncil
            mm_decision=mm_dec,       # จาก P4-5 MMOptimizer
            account_state=account,
        )
        # chain.to_dict()                      → full JSON
        # chain.to_config_push_reasoning()     → compact สำหรับ CONFIG_PUSH
    """

    def build(
        self,
        symbol: str,
        regime_info: dict,
        scoring_results: list,        # list of ScoringResult-like objects/dicts
        mm_decision: Any = None,      # MMDecision from P4-5
        account_state: Any = None,    # AccountState from P4-5
        all_votes: Optional[list] = None,   # all 16 votes (รวม rejected)
        cycle_id: Optional[str] = None,
    ) -> ReasoningChain:
        """
        Build full reasoning chain

        Args:
            symbol:          trading symbol
            regime_info:     {"type": "RANGING", "method": "3-layer", "confidence": 0.85, "detail": "..."}
            scoring_results: selected ScoringResult objects (passed all gates)
            mm_decision:     MMDecision object หรือ dict
            account_state:   AccountState object หรือ dict
            all_votes:       all 16 votes (รวม rejected) — optional
            cycle_id:        e.g. "20260222_0615"
        """
        now = datetime.now(timezone.utc)
        cycle = cycle_id or now.strftime("%Y%m%d_%H%M")
        ts = now.isoformat()

        chain = ReasoningChain(
            symbol=symbol,
            cycle_id=cycle,
            timestamp=ts,
        )

        # ── Regime ──────────────────────────────────────────────────
        if isinstance(regime_info, dict):
            chain.regime_type = regime_info.get("type", "UNKNOWN")
            chain.regime_method = regime_info.get("method", "rule_based")
            chain.regime_confidence = regime_info.get("confidence", 0.0)
            chain.regime_detail = regime_info.get("detail", "")
        else:
            chain.regime_type = str(regime_info)

        # ── Votes (build from all_votes + scoring_results) ──────────
        if all_votes:
            chain.votes = self._build_votes_from_list(all_votes)
        elif scoring_results:
            chain.votes = self._build_votes_from_selected(scoring_results)

        # ── Selected strategies ──────────────────────────────────────
        total_score = sum(
            self._get_score(r) for r in scoring_results
        ) or 1.0

        for rank, result in enumerate(scoring_results, 1):
            score = self._get_score(result)
            sid   = self._get_strategy_id(result)
            alloc = (score / total_score) * 100.0

            chain.selected.append(SelectionReason(
                rank=rank,
                strategy_id=sid,
                score=score,
                allocation=alloc,
            ))

        # ── MM decision ──────────────────────────────────────────────
        if mm_decision:
            if isinstance(mm_decision, dict):
                chain.mm_method    = mm_decision.get("mm_method", "MM01")
                chain.mm_reasoning = mm_decision.get("reasoning", "")
            else:
                chain.mm_method    = getattr(mm_decision, "mm_method", "MM01")
                chain.mm_reasoning = getattr(mm_decision, "reasoning", "")

        # ── Risk multiplier ──────────────────────────────────────────
        if account_state:
            dd = (
                account_state.get("drawdown_pct", 0.0)
                if isinstance(account_state, dict)
                else getattr(account_state, "drawdown_pct", 0.0)
            )
            mult = (
                mm_decision.get("risk_multiplier", 1.0)
                if isinstance(mm_decision, dict)
                else getattr(mm_decision, "risk_multiplier", 1.0)
            ) if mm_decision else 1.0

            chain.risk_multiplier = mult
            chain.risk_reasoning  = self._build_risk_reasoning(dd, mult)

        # ── Summaries ────────────────────────────────────────────────
        chain.summary_th = self._build_summary_th(chain)
        chain.summary_en = self._build_summary_en(chain)

        logger.info(
            f"[Reasoning] {symbol}@{cycle}: regime={chain.regime_type} "
            f"votes={len(chain.votes)} selected={len(chain.selected)} "
            f"mm={chain.mm_method} risk×{chain.risk_multiplier:.2f}"
        )
        return chain

    # ─────────────────────────────────────────
    # Vote builders
    # ─────────────────────────────────────────

    def _build_votes_from_list(self, all_votes: list) -> list[VoteReason]:
        """สร้าง VoteReason จาก list ของ ScoringResult objects"""
        result = []
        for v in all_votes:
            if isinstance(v, dict):
                vr = VoteReason(
                    strategy_id=v.get("strategy_id", 0),
                    raw_confidence=v.get("raw_confidence", 0.0),
                    hist_perf_factor=v.get("hist_perf_factor", 1.0),
                    regime_bonus=v.get("regime_bonus", 1.0),
                    calendar_factor=v.get("calendar_factor", 1.0),
                    news_factor=v.get("news_factor", 1.0),
                    final_score=v.get("weighted_confidence", 0.0),
                    expected_rr=v.get("expected_rr", 0.0),
                    passed_rr_gate=v.get("passed_rr_gate", False),
                    passed_threshold=v.get("passed_threshold", False),
                    reasoning=v.get("reasoning", ""),
                )
            else:
                # ScoringResult object จาก P4-3
                vr = VoteReason(
                    strategy_id=getattr(v, "strategy_id", 0),
                    raw_confidence=getattr(v, "raw_confidence", 0.0),
                    hist_perf_factor=getattr(v, "hist_perf_factor", 1.0),
                    regime_bonus=getattr(v, "regime_factor", 1.0),
                    calendar_factor=getattr(v, "calendar_factor", 1.0),
                    news_factor=getattr(v, "news_factor", 1.0),
                    final_score=getattr(v, "weighted_confidence", 0.0),
                    expected_rr=getattr(v, "expected_rr", 0.0),
                    passed_rr_gate=getattr(v, "passed_rr_gate", False),
                    passed_threshold=getattr(v, "passed_threshold", False),
                    reasoning=getattr(v, "reasoning", ""),
                )
            result.append(vr)
        return result

    def _build_votes_from_selected(self, selected: list) -> list[VoteReason]:
        """สร้าง VoteReason จาก selected results เท่านั้น (ไม่มี full votes)"""
        result = []
        selected_ids = set()
        for r in selected:
            sid = self._get_strategy_id(r)
            selected_ids.add(sid)
            score = self._get_score(r)
            vr = VoteReason(
                strategy_id=sid,
                raw_confidence=getattr(r, "raw_confidence", score),
                hist_perf_factor=getattr(r, "hist_perf_factor", 1.0),
                regime_bonus=getattr(r, "regime_factor", 1.0),
                calendar_factor=getattr(r, "calendar_factor", 1.0),
                news_factor=getattr(r, "news_factor", 1.0),
                final_score=score,
                expected_rr=getattr(r, "expected_rr", 1.5),
                passed_rr_gate=True,
                passed_threshold=True,
                reasoning=getattr(r, "reasoning", f"S{sid:02d} selected"),
            )
            result.append(vr)

        # เติม strategies ที่ไม่ได้ selected (rejected)
        for sid in range(1, 17):
            if sid not in selected_ids:
                result.append(VoteReason(
                    strategy_id=sid,
                    raw_confidence=0.0,
                    hist_perf_factor=1.0,
                    regime_bonus=1.0,
                    calendar_factor=1.0,
                    news_factor=1.0,
                    final_score=0.0,
                    expected_rr=0.0,
                    passed_rr_gate=False,
                    passed_threshold=False,
                    reasoning="Not selected this cycle",
                ))

        # Sort by strategy_id
        result.sort(key=lambda v: v.strategy_id)
        return result

    # ─────────────────────────────────────────
    # Summary builders
    # ─────────────────────────────────────────

    def _build_summary_th(self, chain: ReasoningChain) -> str:
        selected_names = ", ".join(
            f"S{s.strategy_id:02d}({s.score:.2f})"
            for s in chain.selected
        ) or "ไม่มี"

        dd_note = ""
        if chain.risk_multiplier < 1.0:
            dd_note = f" | ⚠️ ลด risk เหลือ {chain.risk_multiplier:.0%}"

        return (
            f"[{chain.cycle_id}] {chain.symbol} | "
            f"Regime: {chain.regime_type} (conf={chain.regime_confidence:.0%}) | "
            f"เลือก: {selected_names} | "
            f"MM: {chain.mm_method} ({MM_NAMES.get(chain.mm_method, '')}) | "
            f"Eligible: {sum(1 for v in chain.votes if v.passed_rr_gate and v.passed_threshold)}/16"
            f"{dd_note}"
        )

    def _build_summary_en(self, chain: ReasoningChain) -> str:
        selected_names = ", ".join(
            f"S{s.strategy_id:02d}({s.score:.2f})"
            for s in chain.selected
        ) or "none"

        eligible = sum(1 for v in chain.votes if v.passed_rr_gate and v.passed_threshold)
        return (
            f"[{chain.cycle_id}] {chain.symbol} | "
            f"Regime={chain.regime_type}({chain.regime_confidence:.0%} conf) | "
            f"Selected={selected_names} | MM={chain.mm_method} | "
            f"Eligible={eligible}/16 | Risk×{chain.risk_multiplier:.2f}"
        )

    def _build_risk_reasoning(self, dd_pct: float, multiplier: float) -> str:
        if multiplier == 0.0:
            return f"🚨 DD={dd_pct:.1f}% ≥ 20% — EMERGENCY: หยุดเปิด trade ใหม่"
        if multiplier <= 0.25:
            return f"⚠️ DD={dd_pct:.1f}% ≥ 15% — ลด risk เหลือ 25%"
        if multiplier <= 0.50:
            return f"⚠️ DD={dd_pct:.1f}% ≥ 10% — ลด risk เหลือ 50%"
        if multiplier < 1.0:
            return f"📊 Regime adjustment — risk ×{multiplier:.2f}"
        return f"✅ DD={dd_pct:.1f}% ปกติ — risk ×1.00"

    # ─────────────────────────────────────────
    # Helpers
    # ─────────────────────────────────────────

    def _get_strategy_id(self, result: Any) -> int:
        if isinstance(result, dict):
            return result.get("strategy_id", 0)
        return getattr(result, "strategy_id", 0)

    def _get_score(self, result: Any) -> float:
        if isinstance(result, dict):
            return result.get("weighted_confidence", result.get("score", 0.0))
        return getattr(result, "weighted_confidence",
               getattr(result, "score", 0.0))


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────

if __name__ == "__main__":
    import json
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )

    print("=" * 60)
    print("FlashEASuite V2 — Reasoning Builder Test")
    print("=" * 60)

    builder = ReasoningBuilder()

    # Mock scoring results (simulate P4-3 output)
    class MockScore:
        def __init__(self, sid, score, rr, reasoning=""):
            self.strategy_id = sid
            self.weighted_confidence = score
            self.raw_confidence = score * 0.9
            self.hist_perf_factor = 1.1
            self.regime_factor = 1.2
            self.calendar_factor = 1.0
            self.news_factor = 1.0
            self.expected_rr = rr
            self.passed_rr_gate = rr >= 1.5
            self.passed_threshold = score >= 0.55
            self.reasoning = reasoning or f"S{sid:02d} analysis result"

    # Mock MM decision
    class MockMM:
        mm_method = "MM03"
        risk_multiplier = 1.0
        reasoning = "✅ S15 default MM03 compatible กับ regime=RANGING"

    # Mock account state
    class MockAccount:
        drawdown_pct = 5.2

    # All 16 votes (including rejected)
    all_votes = [
        MockScore(15, 0.78, 2.5, "Grid: RANGING regime perfect match"),
        MockScore(1,  0.72, 1.8, "StatArb: co-integration signal"),
        MockScore(7,  0.61, 1.6, "MeanRev: overbought detected"),
        MockScore(6,  0.48, 1.2, "KAMA: trend weak"),        # fail threshold
        MockScore(16, 0.30, 0.8, "Spike: no volatility"),    # fail RR gate
    ] + [
        MockScore(sid, 0.0, 0.0, "Not analyzed this cycle")
        for sid in range(2, 16)
        if sid not in [1, 6, 7, 15, 16]
    ]

    selected = [v for v in all_votes if v.passed_rr_gate and v.passed_threshold]

    # ── Test 1: Build reasoning chain ─────────────────────────────────
    print("\n── Test 1: Build reasoning chain ──")
    chain = builder.build(
        symbol="XAUUSD",
        regime_info={
            "type": "RANGING",
            "method": "3-layer(Rule+RF+HMM)",
            "confidence": 0.83,
            "detail": "ADX=18 BB_width=0.8 HMM=RANGING(0.71)",
        },
        scoring_results=selected,
        mm_decision=MockMM(),
        account_state=MockAccount(),
        all_votes=all_votes,
        cycle_id="20260222_0615",
    )

    print(f"  Cycle: {chain.cycle_id}")
    print(f"  Regime: {chain.regime_type} ({chain.regime_confidence:.0%} conf)")
    print(f"  Votes: {len(chain.votes)}")
    print(f"  Selected: {len(chain.selected)}")
    print(f"  MM: {chain.mm_method}")
    print(f"  Risk: ×{chain.risk_multiplier}")

    # ── Test 2: to_dict (full) ─────────────────────────────────────────
    print("\n── Test 2: to_dict (full JSON) ──")
    full = chain.to_dict()
    assert full["regime"]["type"] == "RANGING"
    assert full["regime"]["confidence"] == 0.83
    assert len(full["votes"]) > 0
    assert len(full["selected"]) == len(selected)
    assert full["mm"]["method"] == "MM03"
    print(f"  regime.type: {full['regime']['type']}")
    print(f"  votes count: {len(full['votes'])}")
    print(f"  selected: {[s['strategy'] for s in full['selected']]}")
    print(f"  mm.method: {full['mm']['method']}")
    print(f"  summary_en: {full['summary_en'][:80]}...")

    # ── Test 3: to_config_push_reasoning (compact) ────────────────────
    print("\n── Test 3: CONFIG_PUSH compact reasoning ──")
    compact = chain.to_config_push_reasoning()
    assert "regime" in compact
    assert "selected_strategies" in compact
    print(f"  Keys: {list(compact.keys())}")
    print(f"  selected_strategies: {compact['selected_strategies']}")
    compact_json = json.dumps(compact, ensure_ascii=False)
    print(f"  Compact size: {len(compact_json.encode())} bytes")

    # ── Test 4: Summary strings ────────────────────────────────────────
    print("\n── Test 4: Summary strings ──")
    print(f"  TH: {chain.summary_th[:90]}...")
    print(f"  EN: {chain.summary_en[:90]}...")
    assert "RANGING" in chain.summary_th
    assert "MM03" in chain.summary_th

    # ── Test 5: DD override scenario ──────────────────────────────────
    print("\n── Test 5: DD Override scenario (DD=16%) ──")
    class DDAccount:
        drawdown_pct = 16.0
    class DDMm:
        mm_method = "MM10"
        risk_multiplier = 0.25
        reasoning = "⚠️ DD=16% ≥ 15% → MM10, risk 25%"

    chain_dd = builder.build(
        symbol="XAUUSD",
        regime_info={"type": "VOLATILE", "method": "rule_based", "confidence": 0.70, "detail": ""},
        scoring_results=selected[:1],
        mm_decision=DDMm(),
        account_state=DDAccount(),
        cycle_id="20260222_0700",
    )
    assert chain_dd.risk_multiplier == 0.25
    assert chain_dd.mm_method == "MM10"
    assert "15%" in chain_dd.risk_reasoning
    print(f"  MM: {chain_dd.mm_method} | risk×{chain_dd.risk_multiplier}")
    print(f"  Risk reasoning: {chain_dd.risk_reasoning}")
    print("  DD override: ✅")

    print("\n✅ All tests passed!")
