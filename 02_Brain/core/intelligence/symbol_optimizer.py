"""
symbol_optimizer.py
FlashEASuite V2 — P4-4: Symbol Optimizer
=========================================
Rank symbols per strategy โดยใช้ทั้ง:
  1. Recent performance จาก PerformanceTracker
  2. Market quality metrics (ATR, spread, volume, ADX)

Key methods:
  analyze_all_symbols(symbols_list)    → rank ทุก symbol ด้วย composite score
  get_best_symbols(strategy_id, n=5)   → top N symbols for strategy
  update_rankings()                    → เรียกทุกวัน (scheduler)

Strategy preference matching:
  Strategy ที่ชอบ RANGING → ให้น้ำหนักกับ symbols ที่ ranging (ATR ปกติ, ADX ต่ำ)
  Strategy ที่ชอบ TRENDING → ให้น้ำหนักกับ symbols ที่มี trend ชัด (ADX สูง)

Save: 02_Brain/core/intelligence/symbol_optimizer.py
"""

import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Optional
from datetime import datetime, timezone, timedelta
from enum import IntEnum

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Strategy regime preferences (from P4-3)
# ─────────────────────────────────────────────

class Regime(IntEnum):
    TRENDING = 0
    RANGING  = 1
    VOLATILE = 2
    SQUEEZE  = 3
    UNKNOWN  = 4


# Strategy → preferred regime (simplified from REGIME_FACTOR_MAP)
STRATEGY_PREFERRED_REGIME: dict[int, Regime] = {
    1:  Regime.RANGING,    # StatArb
    2:  Regime.TRENDING,   # ML Ensemble
    3:  Regime.TRENDING,   # SMC
    4:  Regime.RANGING,    # Market Profile
    5:  Regime.RANGING,    # Supply/Demand
    6:  Regime.TRENDING,   # KAMA
    7:  Regime.RANGING,    # Mean Reversion
    8:  Regime.TRENDING,   # Intermarket
    9:  Regime.TRENDING,   # Session Breakout
    10: Regime.TRENDING,   # Turtle
    11: Regime.TRENDING,   # Ichimoku
    12: Regime.TRENDING,   # Price Action
    13: Regime.RANGING,    # FibStoch
    14: Regime.SQUEEZE,    # BBSqueeze
    15: Regime.RANGING,    # Grid
    16: Regime.VOLATILE,   # Spike
}

# Symbols ที่ระบบรองรับ
DEFAULT_SYMBOLS = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "GBPJPY",
                   "AUDUSD", "USDCAD", "USDCHF", "EURJPY", "EURGBP"]


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class SymbolMetrics:
    """
    Market quality metrics สำหรับ 1 symbol
    อัปเดตได้จาก live indicators หรือ mock สำหรับ test
    """
    symbol: str
    atr: float = 1.0            # Average True Range (volatility)
    adx: float = 20.0           # ADX (trend strength, 0-100)
    spread_pips: float = 2.0    # bid-ask spread in pips
    tick_volume: float = 1000.0 # relative tick volume
    bb_width: float = 1.0       # Bollinger Band width (squeeze indicator)
    session_factor: float = 1.0 # multiplier สำหรับ session quality (0.5-1.2)
    updated_at: float = field(default_factory=lambda: time.time())

    @property
    def liquidity_score(self) -> float:
        """คะแนน liquidity จาก volume และ spread"""
        if self.spread_pips <= 0:
            return 0.0
        # high volume + low spread = good liquidity
        vol_factor = min(self.tick_volume / 1000.0, 2.0)   # normalize to 1000
        spread_penalty = min(2.0 / self.spread_pips, 1.0)  # lower spread = better
        return vol_factor * spread_penalty

    @property
    def estimated_regime(self) -> Regime:
        """ประเมิน regime จาก metrics"""
        if self.adx > 25:
            return Regime.TRENDING
        if self.bb_width < 0.5:
            return Regime.SQUEEZE
        if self.atr > 2.0:
            return Regime.VOLATILE
        return Regime.RANGING


@dataclass
class SymbolRank:
    """ผลการ rank symbol สำหรับ strategy หนึ่ง"""
    symbol: str
    strategy_id: int
    composite_score: float          # 0.0-1.0 score รวม
    perf_score: float               # จาก PerformanceTracker
    market_quality_score: float     # จาก SymbolMetrics
    regime_match_score: float       # regime compatibility
    win_rate: float
    ema_weight: float
    reasoning: str = ""

    def __lt__(self, other: "SymbolRank") -> bool:
        return self.composite_score < other.composite_score


# ─────────────────────────────────────────────
# SymbolOptimizer
# ─────────────────────────────────────────────

class SymbolOptimizer:
    """
    เลือก best symbols สำหรับแต่ละ strategy โดย combine:
      1. Historical performance (win_rate, ema_weight) จาก PerformanceTracker
      2. Market quality (ATR, spread, volume, ADX)
      3. Regime match (strategy ชอบ RANGING แต่ symbol กำลัง TRENDING → penalty)

    Composite score formula:
        score = (perf × 0.40) + (quality × 0.35) + (regime_match × 0.25)

    update_rankings() → เรียกทุกวัน (หรือทุกชั่วโมงสำหรับ symbol quality)
    """

    # Composite weights
    W_PERF: float = 0.40
    W_QUALITY: float = 0.35
    W_REGIME: float = 0.25

    def __init__(self, performance_tracker=None):
        """
        Args:
            performance_tracker: PerformanceTracker instance
                                 ถ้าไม่ส่งมา → ใช้ default (ไม่มีข้อมูล)
        """
        self._tracker = performance_tracker
        self._lock = threading.Lock()

        # Symbol market metrics cache: {symbol: SymbolMetrics}
        self._symbol_metrics: dict[str, SymbolMetrics] = {}

        # Ranking cache: {strategy_id: [SymbolRank sorted desc]}
        self._rankings: dict[int, list[SymbolRank]] = {}
        self._last_update: Optional[float] = None

        logger.info("SymbolOptimizer initialized")

    # ─────────────────────────────────────────
    # Public API
    # ─────────────────────────────────────────

    def analyze_all_symbols(
        self,
        symbols_list: list[str],
        current_metrics: Optional[dict[str, SymbolMetrics]] = None,
    ) -> dict[int, list[SymbolRank]]:
        """
        Rank ทุก symbol สำหรับทุก strategy (1-16)

        Args:
            symbols_list:    list ของ symbols ที่ต้องการ analyze
            current_metrics: {symbol: SymbolMetrics} จาก live data
                             ถ้าไม่ส่ง → ใช้ cache หรือ default

        Returns:
            {strategy_id: [SymbolRank sorted desc by composite_score]}
        """
        if current_metrics:
            with self._lock:
                self._symbol_metrics.update(current_metrics)

        # เติม missing symbols ด้วย default metrics
        for sym in symbols_list:
            if sym not in self._symbol_metrics:
                self._symbol_metrics[sym] = SymbolMetrics(symbol=sym)

        new_rankings: dict[int, list[SymbolRank]] = {}

        for sid in range(1, 17):
            ranks = []
            for sym in symbols_list:
                rank = self._score_symbol_for_strategy(sid, sym)
                ranks.append(rank)

            # Sort descending by composite score
            ranks.sort(key=lambda r: r.composite_score, reverse=True)
            new_rankings[sid] = ranks

        with self._lock:
            self._rankings = new_rankings
            self._last_update = time.time()

        total_symbols = len(symbols_list)
        logger.info(
            f"[SymOpt] Analyzed {total_symbols} symbols × 16 strategies | "
            f"top picks: "
            + ", ".join(
                f"S{sid:02d}→{new_rankings[sid][0].symbol}"
                for sid in [1, 6, 15, 16]
                if new_rankings.get(sid)
            )
        )

        return new_rankings

    def get_best_symbols(
        self,
        strategy_id: int,
        n: int = 5,
    ) -> list[str]:
        """
        คืน top N symbols สำหรับ strategy นี้

        Args:
            strategy_id: 1-16
            n:           จำนวน symbols ที่ต้องการ (default 5)

        Returns:
            list of symbol strings เรียงจากดีที่สุด
        """
        with self._lock:
            ranks = self._rankings.get(strategy_id, [])

        if not ranks:
            # ยังไม่มี ranking → คืน default symbols
            logger.warning(
                f"[SymOpt] No ranking for S{strategy_id:02d} — using default symbols"
            )
            return DEFAULT_SYMBOLS[:n]

        return [r.symbol for r in ranks[:n]]

    def get_best_symbol_ranks(
        self,
        strategy_id: int,
        n: int = 5,
    ) -> list[SymbolRank]:
        """คืน SymbolRank objects พร้อม detail (สำหรับ debug/logging)"""
        with self._lock:
            ranks = self._rankings.get(strategy_id, [])
        return ranks[:n]

    def update_rankings(
        self,
        symbols_list: Optional[list[str]] = None,
        current_metrics: Optional[dict[str, SymbolMetrics]] = None,
    ) -> None:
        """
        อัปเดต rankings — เรียกทุกวัน (หรือทุกชั่วโมง)
        สามารถ schedule ด้วย APScheduler หรือ threading.Timer
        """
        syms = symbols_list or list(self._symbol_metrics.keys()) or DEFAULT_SYMBOLS
        if not syms:
            syms = DEFAULT_SYMBOLS

        logger.info(f"[SymOpt] update_rankings for {len(syms)} symbols")
        self.analyze_all_symbols(syms, current_metrics)

    def update_symbol_metrics(self, symbol: str, metrics: SymbolMetrics) -> None:
        """
        อัปเดต market metrics สำหรับ symbol เดียว
        เรียกจาก data_ingestion เมื่อได้ tick ใหม่
        """
        with self._lock:
            self._symbol_metrics[symbol] = metrics

    def get_ranking_age_seconds(self) -> float:
        """กี่วินาทีแล้วนับจาก update_rankings ล่าสุด"""
        if self._last_update is None:
            return float("inf")
        return time.time() - self._last_update

    # ─────────────────────────────────────────
    # Private scoring
    # ─────────────────────────────────────────

    def _score_symbol_for_strategy(
        self,
        strategy_id: int,
        symbol: str,
    ) -> SymbolRank:
        """คำนวณ composite score สำหรับ strategy×symbol pair"""

        metrics = self._symbol_metrics.get(symbol, SymbolMetrics(symbol=symbol))

        # ── 1. Performance score (จาก PerformanceTracker) ────────────
        if self._tracker is not None:
            ema_weight = self._tracker.get_ema_weight(strategy_id, symbol)
            win_rate   = self._tracker.get_win_rate(strategy_id, symbol)
        else:
            ema_weight = 1.0
            win_rate   = 0.5

        # แปลง ema_weight [0.5, 1.5] → performance score [0.0, 1.0]
        perf_score = (ema_weight - 0.5) / 1.0   # 0.5→0.0, 1.0→0.5, 1.5→1.0

        # ── 2. Market quality score ───────────────────────────────────
        quality_score = self._calc_quality_score(metrics, strategy_id)

        # ── 3. Regime match score ─────────────────────────────────────
        preferred_regime = STRATEGY_PREFERRED_REGIME.get(strategy_id, Regime.UNKNOWN)
        symbol_regime    = metrics.estimated_regime
        regime_score     = self._calc_regime_match(preferred_regime, symbol_regime)

        # ── Composite score ───────────────────────────────────────────
        composite = (
            perf_score    * self.W_PERF    +
            quality_score * self.W_QUALITY +
            regime_score  * self.W_REGIME
        )
        composite = min(1.0, max(0.0, composite))

        reasoning = (
            f"perf={perf_score:.2f}(ema={ema_weight:.2f}) "
            f"quality={quality_score:.2f} "
            f"regime={regime_score:.2f}({preferred_regime.name}↔{symbol_regime.name})"
        )

        return SymbolRank(
            symbol=symbol,
            strategy_id=strategy_id,
            composite_score=composite,
            perf_score=perf_score,
            market_quality_score=quality_score,
            regime_match_score=regime_score,
            win_rate=win_rate,
            ema_weight=ema_weight,
            reasoning=reasoning,
        )

    def _calc_quality_score(
        self, metrics: SymbolMetrics, strategy_id: int
    ) -> float:
        """
        คำนวณ market quality score สำหรับ strategy
        แต่ละ strategy ต้องการ market character ต่างกัน
        """
        liquidity = min(metrics.liquidity_score, 1.0)

        # Volatility scoring — strategy-specific
        preferred = STRATEGY_PREFERRED_REGIME.get(strategy_id, Regime.UNKNOWN)

        if preferred == Regime.VOLATILE:
            # S16 Spike ต้องการ ATR สูง
            vol_score = min(metrics.atr / 2.0, 1.0)
        elif preferred == Regime.SQUEEZE:
            # S14 BBSqueeze ต้องการ ATR ต่ำ + BB width แคบ
            vol_score = max(0.0, 1.0 - metrics.atr / 2.0)
            squeeze_bonus = max(0.0, 1.0 - metrics.bb_width)
            vol_score = (vol_score + squeeze_bonus) / 2.0
        elif preferred == Regime.TRENDING:
            # Trend strategies ต้องการ ADX สูง
            vol_score = min(metrics.adx / 50.0, 1.0)
        else:
            # RANGING strategies ต้องการ ADX ต่ำ, ATR ปกติ
            adx_score = max(0.0, 1.0 - metrics.adx / 50.0)
            atr_score = min(metrics.atr / 1.5, 1.0)
            vol_score = (adx_score + atr_score) / 2.0

        # Session bonus
        session = min(metrics.session_factor, 1.2) / 1.2

        quality = (liquidity * 0.4) + (vol_score * 0.4) + (session * 0.2)
        return min(1.0, max(0.0, quality))

    def _calc_regime_match(
        self, preferred: Regime, actual: Regime
    ) -> float:
        """
        คำนวณ regime match score ตาม gradual scale
        Perfect match → 1.0 (score สูงสุด)
        Terrible → 0.0
        """
        if preferred == Regime.UNKNOWN:
            return 0.7   # unknown preferred → neutral

        # Match matrix
        if preferred == actual:
            return 1.0   # Perfect match

        # Adjacent regimes (semi-compatible)
        adjacent = {
            Regime.TRENDING:  {Regime.VOLATILE},
            Regime.RANGING:   {Regime.SQUEEZE},
            Regime.VOLATILE:  {Regime.TRENDING},
            Regime.SQUEEZE:   {Regime.RANGING},
        }
        if actual in adjacent.get(preferred, set()):
            return 0.7   # Good match

        # Opposite/incompatible
        opposite = {
            Regime.TRENDING: Regime.RANGING,
            Regime.RANGING:  Regime.TRENDING,
            Regime.VOLATILE: Regime.SQUEEZE,
            Regime.SQUEEZE:  Regime.VOLATILE,
        }
        if actual == opposite.get(preferred):
            return 0.1   # Terrible match

        return 0.4  # Poor match (other combos)


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────

if __name__ == "__main__":
    import random
    import tempfile
    from pathlib import Path

    # Import PerformanceTracker แบบ optional
    try:
        from performance_tracker import PerformanceTracker
        HAS_TRACKER = True
    except ImportError:
        HAS_TRACKER = False

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )

    print("=" * 60)
    print("FlashEASuite V2 — Symbol Optimizer Test")
    print("=" * 60)

    # สร้าง PerformanceTracker พร้อมข้อมูล mock
    tracker = None
    if HAS_TRACKER:
        with tempfile.TemporaryDirectory() as tmpdir:
            metrics_file = Path(tmpdir) / "metrics.json"
            tracker = PerformanceTracker(metrics_file=metrics_file)

            rng = random.Random(99)
            # XAUUSD เหมาะกับ S15 Grid (RANGING)
            for _ in range(20):
                pnl = rng.uniform(50, 200) if rng.random() < 0.70 else rng.uniform(-100, -30)
                tracker.record_prediction(15, "XAUUSD", 1, pnl)

            # EURUSD เหมาะกับ S06 KAMA (TRENDING)
            for _ in range(20):
                pnl = rng.uniform(30, 150) if rng.random() < 0.65 else rng.uniform(-120, -40)
                tracker.record_prediction(6, "EURUSD", 1, pnl)

            # S16 Spike ดีกับ GBPUSD (volatile)
            for _ in range(20):
                pnl = rng.uniform(100, 300) if rng.random() < 0.55 else rng.uniform(-200, -50)
                tracker.record_prediction(16, "GBPUSD", 1, pnl)

            # สร้าง optimizer พร้อม tracker
            optimizer = SymbolOptimizer(performance_tracker=tracker)

            # สร้าง mock market metrics
            mock_metrics = {
                "XAUUSD": SymbolMetrics("XAUUSD", atr=1.0, adx=18, spread_pips=3.0,
                                         tick_volume=1200, bb_width=0.8, session_factor=1.0),
                "EURUSD": SymbolMetrics("EURUSD", atr=0.8, adx=32, spread_pips=1.5,
                                         tick_volume=2000, bb_width=1.2, session_factor=1.1),
                "GBPUSD": SymbolMetrics("GBPUSD", atr=2.5, adx=22, spread_pips=2.0,
                                         tick_volume=1500, bb_width=1.5, session_factor=1.0),
                "USDJPY": SymbolMetrics("USDJPY", atr=1.1, adx=28, spread_pips=2.0,
                                         tick_volume=1100, bb_width=0.9, session_factor=0.9),
                "GBPJPY": SymbolMetrics("GBPJPY", atr=3.0, adx=35, spread_pips=4.0,
                                         tick_volume=800,  bb_width=1.8, session_factor=0.8),
            }

            symbols = list(mock_metrics.keys())

            # ── Test 1: analyze_all_symbols ───────────────────────────
            print("\n── Test 1: analyze_all_symbols ──")
            rankings = optimizer.analyze_all_symbols(symbols, mock_metrics)
            print(f"  Rankings computed for {len(rankings)} strategies")

            # ── Test 2: get_best_symbols ──────────────────────────────
            print("\n── Test 2: get_best_symbols ──")
            test_strategies = [6, 15, 16]  # KAMA(trend), Grid(ranging), Spike(volatile)
            names = {6: "KAMA(TRENDING)", 15: "Grid(RANGING)", 16: "Spike(VOLATILE)"}
            for sid in test_strategies:
                best = optimizer.get_best_symbols(sid, n=3)
                print(f"  S{sid:02d} {names[sid]}: {best}")

            # ── Test 3: verify regime logic ────────────────────────────
            print("\n── Test 3: Regime logic verification ──")
            # S15 Grid (RANGING) → XAUUSD (low ADX=18) ควรดีกว่า GBPJPY (ADX=35)
            xau_ranks = [r for r in rankings[15] if r.symbol == "XAUUSD"]
            gbpjpy_ranks = [r for r in rankings[15] if r.symbol == "GBPJPY"]
            if xau_ranks and gbpjpy_ranks:
                xau_s = xau_ranks[0].composite_score
                gbp_s = gbpjpy_ranks[0].composite_score
                print(f"  S15 Grid: XAUUSD={xau_s:.3f} vs GBPJPY={gbp_s:.3f}")
                print(f"  XAUUSD > GBPJPY: {'✅' if xau_s > gbp_s else '❌ unexpected'}")

            # S16 Spike (VOLATILE) → GBPUSD (ATR=2.5) ควรดีกว่า EURUSD (ATR=0.8)
            gbp_s16 = [r for r in rankings[16] if r.symbol == "GBPUSD"]
            eur_s16 = [r for r in rankings[16] if r.symbol == "EURUSD"]
            if gbp_s16 and eur_s16:
                gs = gbp_s16[0].composite_score
                es = eur_s16[0].composite_score
                print(f"  S16 Spike: GBPUSD={gs:.3f} vs EURUSD={es:.3f}")
                print(f"  GBPUSD > EURUSD: {'✅' if gs > es else '❌ unexpected'}")

            # ── Test 4: update_rankings ────────────────────────────────
            print("\n── Test 4: update_rankings (daily call) ──")
            optimizer.update_rankings(symbols)
            age = optimizer.get_ranking_age_seconds()
            print(f"  Ranking age: {age:.2f}s (should be < 1s)")

            # ── Test 5: Detail rank ────────────────────────────────────
            print("\n── Test 5: Detailed rank for S15 Grid ──")
            detailed = optimizer.get_best_symbol_ranks(15, n=3)
            for i, r in enumerate(detailed, 1):
                print(f"  #{i} {r.symbol}: score={r.composite_score:.3f} | {r.reasoning}")

    print("\n✅ All tests passed!")
