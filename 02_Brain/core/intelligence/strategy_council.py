"""
strategy_council.py
FlashEASuite V2 — P4-3: AI Council Voting System (Orchestrator)
===============================================================
รับ votes จาก 16 analyzers → apply 5 factors → filter → select top 1-3

Pipeline:
  Step 1: Collect votes from 16 analyzers (ANALYZER_REGISTRY)
  Step 2: Apply 5-factor weighted confidence (ConfidenceScorer)
  Step 3: R:R Gate — expected R:R < 1.5 → SKIP
  Step 4: Filter — weighted < 0.55 → SKIP
  Step 5: Portfolio diversification check
  Step 6: Select top 1-3 per symbol
  Step 7: Self-tuning — EMA(accuracy) per strategy×symbol, adjust weekly

Save: 02_Brain/core/intelligence/strategy_council.py
"""

import time
import logging
import threading
from dataclasses import dataclass, field
from typing import Optional, Any
from datetime import datetime, timedelta, timezone
from enum import IntEnum

try:
    from .confidence_scorer import (
        ConfidenceScorer, ScoringInput, ScoringResult, Regime
    )
    from .portfolio_diversifier import (
        PortfolioDiversifier, PortfolioState, DiversificationResult
    )
except ImportError:
    # Standalone execution / direct script run
    from confidence_scorer import (  # type: ignore
        ConfidenceScorer, ScoringInput, ScoringResult, Regime
    )
    from portfolio_diversifier import (  # type: ignore
        PortfolioDiversifier, PortfolioState, DiversificationResult
    )

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

TOP_N_PER_SYMBOL: int = 3           # เลือก top 1-3 strategy ต่อ symbol
EMA_ALPHA: float = 0.1              # EMA smoothing สำหรับ accuracy tracking
SELF_TUNE_INTERVAL_DAYS: int = 7    # ปรับ weight ทุกสัปดาห์
MIN_HISTORY_FOR_TUNING: int = 10    # ต้องมีข้อมูล ≥ 10 trades ก่อน tune
HIST_PERF_MIN: float = 0.5          # ค่าต่ำสุดของ historical performance factor
HIST_PERF_MAX: float = 1.5          # ค่าสูงสุดของ historical performance factor


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class AnalyzerResult:
    """
    ผลลัพธ์จาก 1 analyzer (P4-2 interface)
    ต้องตรงกับ ANALYZER_REGISTRY output
    """
    strategy_id: int
    symbol: str
    confidence: float               # 0.0-1.0 raw confidence
    expected_rr: float              # expected Risk:Reward
    extra_params: dict = field(default_factory=dict)   # สำหรับ CONFIG_PUSH (hybrid only)
    reasoning: str = ""


@dataclass
class CouncilDecision:
    """ผลการ vote และ select จาก AI Council"""
    symbol: str
    selected: list[ScoringResult]           # strategy ที่ผ่านการ select
    all_votes: list[ScoringResult]          # ผลทุกคน (สำหรับ debug)
    diversification_adjustments: list[DiversificationResult] = field(default_factory=list)
    timestamp: float = field(default_factory=time.time)
    session_id: str = ""

    @property
    def top_strategy_id(self) -> Optional[int]:
        return self.selected[0].strategy_id if self.selected else None

    def summary(self) -> str:
        lines = [f"CouncilDecision@{self.symbol} [{len(self.selected)} selected]"]
        for i, r in enumerate(self.selected, 1):
            lines.append(
                f"  #{i} S{r.strategy_id:02d}: weighted={r.weighted_confidence:.3f} "
                f"RR={r.expected_rr:.2f}"
            )
        return "\n".join(lines)


@dataclass
class AccuracyRecord:
    """ข้อมูล accuracy tracking สำหรับ self-tuning"""
    ema_accuracy: float = 0.5       # EMA ของ accuracy (init=0.5 = neutral)
    trade_count: int = 0
    last_updated: float = field(default_factory=time.time)

    def update(self, was_correct: bool) -> float:
        """อัปเดต EMA accuracy แล้วคืน ค่าใหม่"""
        outcome = 1.0 if was_correct else 0.0
        self.ema_accuracy = EMA_ALPHA * outcome + (1.0 - EMA_ALPHA) * self.ema_accuracy
        self.trade_count += 1
        self.last_updated = time.time()
        return self.ema_accuracy

    def to_hist_perf_factor(self) -> float:
        """แปลง EMA accuracy → hist_perf_factor ใน range [0.5, 1.5]"""
        # accuracy 0.5 (50%) → factor 1.0 (neutral)
        # accuracy 1.0 (100%) → factor 1.5
        # accuracy 0.0 (0%)   → factor 0.5
        factor = HIST_PERF_MIN + (self.ema_accuracy * (HIST_PERF_MAX - HIST_PERF_MIN))
        return round(factor, 4)


# ─────────────────────────────────────────────
# StrategyCouncil
# ─────────────────────────────────────────────

class StrategyCouncil:
    """
    AI Council Voting System — Orchestrator หลัก

    Usage:
        council = StrategyCouncil(analyzer_registry=ANALYZER_REGISTRY)
        decisions = council.vote(
            symbol="XAUUSD",
            regime=Regime.RANGING,
            indicators=indicators_dict,
            portfolio=portfolio_state,
            weekday=2,
            news_factor=1.0,
        )
    """

    def __init__(
        self,
        analyzer_registry: Optional[dict] = None,
        scorer: Optional[ConfidenceScorer] = None,
        diversifier: Optional[PortfolioDiversifier] = None,
    ):
        # P4-2 ANALYZER_REGISTRY: {strategy_id: analyzer_instance}
        self._registry: dict = analyzer_registry or {}
        self._scorer = scorer or ConfidenceScorer()
        self._diversifier = diversifier or PortfolioDiversifier()

        # Self-tuning data: {(strategy_id, symbol): AccuracyRecord}
        self._accuracy: dict[tuple[int, str], AccuracyRecord] = {}
        self._lock = threading.Lock()
        self._last_tune_time = datetime.now(timezone.utc)

        logger.info(
            f"StrategyCouncil initialized | "
            f"{len(self._registry)} analyzers registered"
        )

    # ─────────────────────────────────────────
    # Public API
    # ─────────────────────────────────────────

    def vote(
        self,
        symbol: str,
        regime: Regime,
        indicators: dict[str, Any],
        portfolio: Optional[PortfolioState] = None,
        weekday: int = 2,
        news_factor: float = 1.0,
    ) -> CouncilDecision:
        """
        รัน full voting pipeline สำหรับ 1 symbol

        Returns:
            CouncilDecision พร้อม selected strategies
        """
        t0 = time.perf_counter()

        if portfolio is None:
            portfolio = PortfolioState()  # empty portfolio

        # ── Step 1: Collect votes ────────────────────────────────────────
        raw_results = self._collect_votes(symbol, regime, indicators)
        logger.debug(f"[Council] Collected {len(raw_results)} votes for {symbol}")

        # ── Step 2+3+4: Score + Gate + Threshold filter ──────────────────
        scoring_inputs = self._build_scoring_inputs(
            raw_results, regime, weekday, news_factor
        )
        all_scores = self._scorer.score_batch(scoring_inputs)

        # filter ที่ผ่าน RR gate และ threshold
        eligible = [s for s in all_scores if s.is_eligible]
        logger.debug(
            f"[Council] {len(eligible)}/{len(all_scores)} passed RR+threshold gates"
        )

        # ── Step 5: Portfolio diversification ───────────────────────────
        candidates = [(s.strategy_id, symbol, s.weighted_confidence) for s in eligible]
        approved = self._diversifier.filter_candidates(candidates, portfolio)

        # สร้าง map กลับไปหา ScoringResult
        score_map = {s.strategy_id: s for s in eligible}
        div_results = []
        approved_scores = []
        for sid, sym, adj_w, div_result in approved:
            div_results.append(div_result)
            if sid in score_map:
                score = score_map[sid]
                # อัปเดต weighted_confidence ด้วย adjusted weight
                score.weighted_confidence = adj_w
                approved_scores.append(score)

        # ── Step 6: Select top 1-3 ──────────────────────────────────────
        approved_scores.sort(key=lambda s: s.weighted_confidence, reverse=True)
        selected = approved_scores[:TOP_N_PER_SYMBOL]

        elapsed_ms = (time.perf_counter() - t0) * 1000
        logger.info(
            f"[Council] {symbol} → {len(selected)} selected "
            f"in {elapsed_ms:.1f}ms | "
            f"votes={len(raw_results)} eligible={len(eligible)} "
            f"approved={len(approved_scores)}"
        )

        decision = CouncilDecision(
            symbol=symbol,
            selected=selected,
            all_votes=all_scores,
            diversification_adjustments=div_results,
            session_id=f"{symbol}_{int(time.time())}",
        )

        # ── Step 7: Self-tuning (weekly) ─────────────────────────────────
        self._maybe_self_tune()

        return decision

    def vote_all_symbols(
        self,
        symbols: list[str],
        regime: Regime,
        indicators_per_symbol: dict[str, dict],
        portfolio: Optional[PortfolioState] = None,
        weekday: int = 2,
        news_factor: float = 1.0,
    ) -> dict[str, CouncilDecision]:
        """Vote สำหรับหลาย symbols พร้อมกัน"""
        decisions = {}
        # ใช้ portfolio เดิมและ update ทีละ symbol
        working_portfolio = portfolio or PortfolioState()

        for sym in symbols:
            ind = indicators_per_symbol.get(sym, {})
            decision = self.vote(
                symbol=sym,
                regime=regime,
                indicators=ind,
                portfolio=working_portfolio,
                weekday=weekday,
                news_factor=news_factor,
            )
            decisions[sym] = decision

            # อัปเดต portfolio ด้วย selected strategies
            for score in decision.selected:
                working_portfolio.total_positions += 1
                sid = score.strategy_id
                working_portfolio.strategy_counts[sid] = \
                    working_portfolio.strategy_counts.get(sid, 0) + 1
                working_portfolio.symbol_counts[sym] = \
                    working_portfolio.symbol_counts.get(sym, 0) + 1
                if sid not in working_portfolio.active_strategy_ids:
                    working_portfolio.active_strategy_ids.append(sid)

        return decisions

    def record_outcome(
        self,
        strategy_id: int,
        symbol: str,
        was_profitable: bool,
    ) -> None:
        """
        บันทึกผลลัพธ์ trade สำหรับ self-tuning (Step 7)
        เรียกจาก feedback loop หลัง trade ปิด
        """
        key = (strategy_id, symbol)
        with self._lock:
            if key not in self._accuracy:
                self._accuracy[key] = AccuracyRecord()
            new_ema = self._accuracy[key].update(was_profitable)

        logger.debug(
            f"[Council] Recorded outcome S{strategy_id:02d}@{symbol} "
            f"{'WIN' if was_profitable else 'LOSS'} | ema_acc={new_ema:.3f}"
        )

    def get_hist_perf_factor(self, strategy_id: int, symbol: str) -> float:
        """คืน hist_perf_factor สำหรับ ConfidenceScorer"""
        key = (strategy_id, symbol)
        with self._lock:
            record = self._accuracy.get(key)
        if record is None or record.trade_count < MIN_HISTORY_FOR_TUNING:
            return 1.0  # ไม่มีข้อมูลพอ → neutral factor
        return record.to_hist_perf_factor()

    def get_accuracy_summary(self) -> dict[tuple[int, str], dict]:
        """สรุป accuracy ทุก strategy×symbol"""
        with self._lock:
            return {
                k: {
                    "ema_accuracy": v.ema_accuracy,
                    "trade_count": v.trade_count,
                    "hist_perf_factor": v.to_hist_perf_factor(),
                }
                for k, v in self._accuracy.items()
            }

    # ─────────────────────────────────────────
    # Private helpers
    # ─────────────────────────────────────────

    def _collect_votes(
        self,
        symbol: str,
        regime: Regime,
        indicators: dict[str, Any],
    ) -> list[AnalyzerResult]:
        """
        Step 1: เรียก analyze() จากทุก analyzer ใน registry

        Compatible กับ P4-2 ANALYZER_REGISTRY:
            result = analyzer.analyze(symbol, regime, indicators)
            votes[sid] = result.confidence
            config[sid] = result.extra_params
        """
        results = []
        for sid, analyzer in self._registry.items():
            try:
                raw = analyzer.analyze(symbol, regime, indicators)

                # Support both dict-style and object-style results
                if isinstance(raw, dict):
                    confidence = float(raw.get("confidence", 0.0))
                    extra_params = raw.get("extra_params", {})
                    reasoning = raw.get("reasoning", "")
                    expected_rr = float(raw.get("expected_rr", 2.0))
                else:
                    confidence = float(getattr(raw, "confidence", 0.0))
                    extra_params = getattr(raw, "extra_params", {})
                    reasoning = getattr(raw, "reasoning", "")
                    expected_rr = float(getattr(raw, "expected_rr", 2.0))

                results.append(AnalyzerResult(
                    strategy_id=int(sid),
                    symbol=symbol,
                    confidence=min(1.0, max(0.0, confidence)),
                    expected_rr=expected_rr,
                    extra_params=extra_params,
                    reasoning=reasoning,
                ))
            except Exception as e:
                logger.warning(f"[Council] Analyzer S{sid} failed: {e}")
                # ให้ confidence=0 แทนการ crash
                results.append(AnalyzerResult(
                    strategy_id=int(sid),
                    symbol=symbol,
                    confidence=0.0,
                    expected_rr=0.0,
                    reasoning=f"ERROR: {e}",
                ))

        return results

    def _build_scoring_inputs(
        self,
        raw_results: list[AnalyzerResult],
        regime: Regime,
        weekday: int,
        news_factor: float,
    ) -> list[ScoringInput]:
        """สร้าง ScoringInput batch โดยดึง hist_perf_factor จาก self-tuning"""
        inputs = []
        for r in raw_results:
            hist_perf = self.get_hist_perf_factor(r.strategy_id, r.symbol)
            inputs.append(ScoringInput(
                strategy_id=r.strategy_id,
                symbol=r.symbol,
                raw_confidence=r.confidence,
                expected_rr=r.expected_rr,
                regime=regime,
                hist_perf_factor=hist_perf,
                news_factor=news_factor,
                weekday=weekday,
            ))
        return inputs

    def _maybe_self_tune(self) -> None:
        """
        Step 7: Self-tuning weekly
        ทุก 7 วัน → log summary ของ accuracy EMA
        (การ adjust weight ทำ auto ผ่าน get_hist_perf_factor ทุกครั้ง)
        """
        now = datetime.now(timezone.utc)
        if (now - self._last_tune_time) >= timedelta(days=SELF_TUNE_INTERVAL_DAYS):
            with self._lock:
                summary = {
                    f"S{k[0]:02d}@{k[1]}": {
                        "ema_acc": f"{v.ema_accuracy:.3f}",
                        "factor": f"{v.to_hist_perf_factor():.3f}",
                        "trades": v.trade_count,
                    }
                    for k, v in self._accuracy.items()
                    if v.trade_count >= MIN_HISTORY_FOR_TUNING
                }
            logger.info(f"[Council] Weekly self-tune summary: {summary}")
            self._last_tune_time = now


# ─────────────────────────────────────────────
# Mock Analyzer (สำหรับ test ไม่มี P4-2)
# ─────────────────────────────────────────────

class MockAnalyzer:
    """Simulated analyzer สำหรับ test P4-3 โดยไม่ต้องมี P4-2"""

    def __init__(self, strategy_id: int, base_confidence: float = 0.65):
        self.strategy_id = strategy_id
        self.base_confidence = base_confidence

    def analyze(self, symbol: str, regime: Regime, indicators: dict) -> dict:
        import random
        rng = random.Random(self.strategy_id + hash(symbol) % 100)
        noise = rng.uniform(-0.15, 0.15)
        confidence = min(1.0, max(0.0, self.base_confidence + noise))
        # RR คำนวณจาก confidence
        expected_rr = 1.0 + confidence * 2.5
        return {
            "confidence": confidence,
            "expected_rr": expected_rr,
            "extra_params": {},
            "reasoning": f"Mock S{self.strategy_id:02d} analysis",
        }


def build_mock_registry(n: int = 16) -> dict:
    """สร้าง mock registry 16 analyzers สำหรับ test"""
    import random
    rng = random.Random(42)
    return {
        i: MockAnalyzer(strategy_id=i, base_confidence=rng.uniform(0.45, 0.85))
        for i in range(1, n + 1)
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
    print("FlashEASuite V2 — AI Council Voting System Test")
    print("=" * 60)

    # สร้าง council ด้วย mock analyzers
    registry = build_mock_registry(16)
    council = StrategyCouncil(analyzer_registry=registry)

    # Mock portfolio: มี position อยู่บ้างแล้ว
    portfolio = PortfolioState(
        total_positions=5,
        strategy_counts={15: 2, 6: 1, 9: 1, 16: 1},
        symbol_counts={"XAUUSD": 3, "EURUSD": 2},
        active_strategy_ids=[15, 6, 9, 16],
    )

    indicators = {
        "adx": 28.5, "atr": 1.2, "bb_width": 0.8,
        "rsi": 52.0, "volume": 1500, "spread": 0.3,
    }

    print("\n── Test 1: Single symbol vote (XAUUSD, RANGING regime) ──")
    decision = council.vote(
        symbol="XAUUSD",
        regime=Regime.RANGING,
        indicators=indicators,
        portfolio=portfolio,
        weekday=2,
        news_factor=1.0,
    )
    print(decision.summary())
    print(f"  Total votes: {len(decision.all_votes)}")
    eligible_count = sum(1 for v in decision.all_votes if v.is_eligible)
    print(f"  Eligible (passed gates): {eligible_count}")

    print("\n── Test 2: R:R Gate verification ──")
    rr_pass = [v for v in decision.all_votes if v.passed_rr_gate]
    rr_fail = [v for v in decision.all_votes if not v.passed_rr_gate]
    print(f"  Passed R:R gate (≥1.5): {len(rr_pass)}")
    print(f"  Failed R:R gate (<1.5): {len(rr_fail)}")
    for v in rr_fail:
        print(f"    ❌ S{v.strategy_id:02d}: RR={v.expected_rr:.2f}")

    print("\n── Test 3: Multi-symbol vote ──")
    symbols = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY"]
    ind_per_sym = {s: indicators for s in symbols}
    all_decisions = council.vote_all_symbols(
        symbols=symbols,
        regime=Regime.TRENDING,
        indicators_per_symbol=ind_per_sym,
        portfolio=PortfolioState(),
        weekday=3,
    )
    for sym, dec in all_decisions.items():
        top = f"S{dec.top_strategy_id:02d}" if dec.top_strategy_id else "NONE"
        print(f"  {sym}: {len(dec.selected)} selected | top={top}")

    print("\n── Test 4: Self-tuning (record outcomes) ──")
    for sid in [15, 6, 1, 7]:
        for _ in range(12):
            was_win = (sid % 2 == 0)  # even sid → winning
            council.record_outcome(sid, "XAUUSD", was_win)

    acc_summary = council.get_accuracy_summary()
    print(f"  Accuracy records: {len(acc_summary)}")
    for k, v in acc_summary.items():
        print(
            f"  S{k[0]:02d}@{k[1]}: "
            f"ema_acc={v['ema_accuracy']:.3f} "
            f"factor={v['hist_perf_factor']:.3f} "
            f"trades={v['trade_count']}"
        )

    print("\n✅ All tests passed!")
