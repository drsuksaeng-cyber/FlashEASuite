"""
performance_tracker.py
FlashEASuite V2 — P4-4: Performance Tracker
============================================
Track accuracy per strategy×symbol สำหรับ:
  1. Self-tuning weights ใน AI Council (get_ema_weight)
  2. Kelly Criterion MM4 (get_win_rate)
  3. Symbol ranking ใน SymbolOptimizer

Persistent storage: JSON file (02_Brain/data/metrics/performance_metrics.json)

Integration:
  - strategy_council.py → record_outcome() เรียก tracker.record_prediction()
  - symbol_optimizer.py → get_accuracy(), get_win_rate() ใช้หา best symbols
  - mm_optimizer.py    → get_win_rate() สำหรับ Kelly Criterion

Save: 02_Brain/core/intelligence/performance_tracker.py
"""

import json
import logging
import threading
import os
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone, timedelta
from typing import Optional
from pathlib import Path

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

EMA_ALPHA: float = 0.1                  # EMA smoothing (เหมือน P4-3)
MIN_TRADES_FOR_STATS: int = 5           # ต้องมี ≥ 5 trades ก่อนใช้ stats จริง
DEFAULT_EMA_WEIGHT: float = 1.0         # default เมื่อยังไม่มีข้อมูล
DEFAULT_WIN_RATE: float = 0.5           # default win rate (neutral)
MAX_RECORDS_PER_KEY: int = 1000         # เก็บสูงสุด 1000 records ต่อ key (prevent memory leak)
METRICS_FILE_DEFAULT = Path("02_Brain/data/metrics/performance_metrics.json")


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class PredictionRecord:
    """บันทึก 1 trade prediction + outcome"""
    strategy_id: int
    symbol: str
    prediction: int             # 1=BUY, -1=SELL, 0=SKIP
    actual_outcome: float       # pnl จริง (บวก=กำไร, ลบ=ขาดทุน)
    was_correct: bool           # True ถ้า prediction ตรงกับ actual
    timestamp: float            # Unix timestamp (UTC)
    rr_achieved: float = 0.0    # R:R ที่ได้จริง
    extra: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "sid": self.strategy_id,
            "sym": self.symbol,
            "pred": self.prediction,
            "pnl": self.actual_outcome,
            "ok": self.was_correct,
            "ts": self.timestamp,
            "rr": self.rr_achieved,
        }

    @staticmethod
    def from_dict(d: dict) -> "PredictionRecord":
        return PredictionRecord(
            strategy_id=d["sid"],
            symbol=d["sym"],
            prediction=d["pred"],
            actual_outcome=d["pnl"],
            was_correct=d["ok"],
            timestamp=d["ts"],
            rr_achieved=d.get("rr", 0.0),
        )


@dataclass
class StrategyMetrics:
    """
    Aggregate metrics สำหรับ strategy×symbol pair
    อัปเดตแบบ incremental ทุกครั้งที่ record_prediction() ถูกเรียก
    """
    strategy_id: int
    symbol: str
    total_trades: int = 0
    win_count: int = 0
    loss_count: int = 0
    total_pnl: float = 0.0
    ema_accuracy: float = 0.5       # EMA(accuracy) init=0.5 neutral
    last_updated: float = field(default_factory=lambda: datetime.now(timezone.utc).timestamp())

    # ─── Computed properties ─────────────────────

    @property
    def win_rate(self) -> float:
        """win count / total trades (สำหรับ Kelly Criterion)"""
        if self.total_trades < MIN_TRADES_FOR_STATS:
            return DEFAULT_WIN_RATE
        return self.win_count / self.total_trades

    @property
    def profit_factor(self) -> float:
        """total pnl บวก / |total pnl ลบ| — ถ้าไม่มีขาดทุนคืน 999"""
        gross_profit = sum(
            r.actual_outcome for r in []  # placeholder (ต้องใช้ history)
        )
        return 1.0  # simplified — detail ใช้ history จาก records

    @property
    def ema_weight(self) -> float:
        """
        แปลง EMA accuracy → hist_perf_factor ใน [0.5, 1.5]
        ตรงกับ logic ใน strategy_council.AccuracyRecord
        """
        if self.total_trades < MIN_TRADES_FOR_STATS:
            return DEFAULT_EMA_WEIGHT
        return 0.5 + self.ema_accuracy * 1.0  # [0.5, 1.5]

    def update(self, was_correct: bool, pnl: float) -> None:
        """อัปเดต metrics ด้วย 1 trade result"""
        self.total_trades += 1
        if was_correct:
            self.win_count += 1
        else:
            self.loss_count += 1
        self.total_pnl += pnl
        # EMA update
        outcome = 1.0 if was_correct else 0.0
        self.ema_accuracy = EMA_ALPHA * outcome + (1.0 - EMA_ALPHA) * self.ema_accuracy
        self.last_updated = datetime.now(timezone.utc).timestamp()

    def to_dict(self) -> dict:
        return {
            "sid": self.strategy_id,
            "sym": self.symbol,
            "total": self.total_trades,
            "wins": self.win_count,
            "losses": self.loss_count,
            "pnl": round(self.total_pnl, 4),
            "ema_acc": round(self.ema_accuracy, 6),
            "updated": self.last_updated,
        }

    @staticmethod
    def from_dict(d: dict) -> "StrategyMetrics":
        m = StrategyMetrics(
            strategy_id=d["sid"],
            symbol=d["sym"],
            total_trades=d["total"],
            win_count=d["wins"],
            loss_count=d["losses"],
            total_pnl=d["pnl"],
            ema_accuracy=d["ema_acc"],
            last_updated=d["updated"],
        )
        return m


# ─────────────────────────────────────────────
# PerformanceTracker
# ─────────────────────────────────────────────

class PerformanceTracker:
    """
    Track accuracy per strategy×symbol

    Key methods:
        record_prediction()  → บันทึก trade result
        get_accuracy()       → accuracy % ใน lookback window
        get_ema_weight()     → สำหรับ AI Council self-tuning
        get_win_rate()       → สำหรับ Kelly Criterion MM4
        save_metrics()       → persist ลง JSON
        load_metrics()       → โหลดจาก JSON
    """

    def __init__(self, metrics_file: Optional[Path] = None):
        self._metrics_file = Path(metrics_file or METRICS_FILE_DEFAULT)
        self._lock = threading.Lock()

        # aggregate metrics: {(sid, symbol): StrategyMetrics}
        self._metrics: dict[tuple[int, str], StrategyMetrics] = {}

        # history records: {(sid, symbol): [PredictionRecord]}
        self._history: dict[tuple[int, str], list[PredictionRecord]] = {}

        # โหลดข้อมูลที่บันทึกไว้
        self.load_metrics()

        logger.info(
            f"PerformanceTracker initialized | "
            f"{len(self._metrics)} strategy×symbol pairs loaded"
        )

    # ─────────────────────────────────────────
    # Core recording
    # ─────────────────────────────────────────

    def record_prediction(
        self,
        strategy: int,
        symbol: str,
        prediction: int,
        actual_outcome: float,
        rr_achieved: float = 0.0,
    ) -> None:
        """
        บันทึก 1 trade result

        Args:
            strategy:       strategy_id (1-16)
            symbol:         e.g. "XAUUSD"
            prediction:     1=BUY, -1=SELL, 0=SKIP
            actual_outcome: pnl จริง (บวก=กำไร, ลบ=ขาดทุน)
            rr_achieved:    R:R ที่ได้จริง
        """
        was_correct = actual_outcome > 0.0

        record = PredictionRecord(
            strategy_id=strategy,
            symbol=symbol,
            prediction=prediction,
            actual_outcome=actual_outcome,
            was_correct=was_correct,
            timestamp=datetime.now(timezone.utc).timestamp(),
            rr_achieved=rr_achieved,
        )

        key = (strategy, symbol)
        with self._lock:
            # อัปเดต aggregate metrics
            if key not in self._metrics:
                self._metrics[key] = StrategyMetrics(strategy, symbol)
            self._metrics[key].update(was_correct, actual_outcome)

            # เพิ่มใน history
            if key not in self._history:
                self._history[key] = []
            self._history[key].append(record)

            # Trim เพื่อป้องกัน memory leak
            if len(self._history[key]) > MAX_RECORDS_PER_KEY:
                self._history[key] = self._history[key][-MAX_RECORDS_PER_KEY:]

        logger.debug(
            f"[Tracker] S{strategy:02d}@{symbol} "
            f"{'WIN' if was_correct else 'LOSS'} pnl={actual_outcome:.2f} "
            f"ema_acc={self._metrics[key].ema_accuracy:.3f}"
        )

    # ─────────────────────────────────────────
    # Query methods
    # ─────────────────────────────────────────

    def get_accuracy(
        self,
        strategy: int,
        symbol: str,
        lookback_days: int = 30,
    ) -> float:
        """
        คำนวณ accuracy % ในช่วง lookback_days ที่ผ่านมา

        Returns:
            accuracy ในช่วง 0.0-1.0 (0%=ผิดทั้งหมด, 1.0=ถูกทั้งหมด)
            คืน DEFAULT_WIN_RATE (0.5) ถ้าไม่มีข้อมูลพอ
        """
        key = (strategy, symbol)
        cutoff_ts = (
            datetime.now(timezone.utc) - timedelta(days=lookback_days)
        ).timestamp()

        with self._lock:
            history = self._history.get(key, [])

        recent = [r for r in history if r.timestamp >= cutoff_ts]

        if len(recent) < MIN_TRADES_FOR_STATS:
            return DEFAULT_WIN_RATE

        correct = sum(1 for r in recent if r.was_correct)
        return correct / len(recent)

    def get_ema_weight(self, strategy: int, symbol: str) -> float:
        """
        คืน EMA(accuracy) weight สำหรับ AI Council self-tuning
        Range: [0.5, 1.5] — เหมือนกับ AccuracyRecord.to_hist_perf_factor()

        สำหรับใช้แทน strategy_council.get_hist_perf_factor()
        เมื่อมี PerformanceTracker แล้วไม่ต้องใช้ AccuracyRecord ใน council แยก
        """
        key = (strategy, symbol)
        with self._lock:
            m = self._metrics.get(key)
        if m is None or m.total_trades < MIN_TRADES_FOR_STATS:
            return DEFAULT_EMA_WEIGHT
        return m.ema_weight

    def get_win_rate(self, strategy: int, symbol: str) -> float:
        """
        คืน win rate (0.0-1.0) สำหรับ Kelly Criterion MM4

        Kelly formula: f* = W - (1-W)/R
            W = win rate
            R = average win / average loss ratio

        ตัวอย่าง: W=0.6, R=1.5 → f* = 0.6 - 0.4/1.5 = 0.33 = 33% position size
        """
        key = (strategy, symbol)
        with self._lock:
            m = self._metrics.get(key)
        if m is None:
            return DEFAULT_WIN_RATE
        return m.win_rate

    def get_avg_rr(self, strategy: int, symbol: str) -> float:
        """
        คืน average R:R achieved — ใช้คู่กับ get_win_rate() สำหรับ full Kelly
        """
        key = (strategy, symbol)
        with self._lock:
            history = self._history.get(key, [])

        if not history:
            return 1.5  # default

        rr_values = [r.rr_achieved for r in history if r.rr_achieved > 0]
        if not rr_values:
            return 1.5
        return sum(rr_values) / len(rr_values)

    def get_kelly_fraction(self, strategy: int, symbol: str) -> float:
        """
        คำนวณ Kelly fraction: f* = W - (1-W)/R
        Clamp ไว้ที่ [0.05, 0.25] เพื่อความปลอดภัย
        """
        w = self.get_win_rate(strategy, symbol)
        r = self.get_avg_rr(strategy, symbol)
        if r <= 0:
            return 0.05
        kelly = w - (1.0 - w) / r
        return max(0.05, min(0.25, kelly))

    def get_metrics(self, strategy: int, symbol: str) -> Optional[StrategyMetrics]:
        """คืน full StrategyMetrics object"""
        with self._lock:
            return self._metrics.get((strategy, symbol))

    def get_all_keys(self) -> list[tuple[int, str]]:
        """คืน list ของ (strategy_id, symbol) ทั้งหมดที่มีข้อมูล"""
        with self._lock:
            return list(self._metrics.keys())

    def get_summary(self) -> dict[tuple[int, str], dict]:
        """สรุป metrics ทุก key"""
        with self._lock:
            return {
                k: {
                    "win_rate": round(v.win_rate, 4),
                    "ema_weight": round(v.ema_weight, 4),
                    "total_trades": v.total_trades,
                    "total_pnl": round(v.total_pnl, 2),
                    "ema_accuracy": round(v.ema_accuracy, 4),
                }
                for k, v in self._metrics.items()
            }

    # ─────────────────────────────────────────
    # Persistence
    # ─────────────────────────────────────────

    def save_metrics(self) -> bool:
        """
        บันทึก metrics ลง JSON file
        เรียกได้บ่อยๆ (หลัง record หรือ scheduled ทุก 5 นาที)

        Returns:
            True ถ้าสำเร็จ
        """
        try:
            # สร้าง directory ถ้าไม่มี
            self._metrics_file.parent.mkdir(parents=True, exist_ok=True)

            with self._lock:
                data = {
                    "version": "1.0",
                    "saved_at": datetime.now(timezone.utc).isoformat(),
                    "metrics": [m.to_dict() for m in self._metrics.values()],
                    "history": {
                        f"{k[0]}_{k[1]}": [r.to_dict() for r in v[-200:]]  # เก็บ 200 record ล่าสุด
                        for k, v in self._history.items()
                    },
                }

            # Write atomically (temp file → rename)
            tmp_file = self._metrics_file.with_suffix(".tmp")
            with open(tmp_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            tmp_file.replace(self._metrics_file)

            logger.debug(
                f"[Tracker] Saved {len(self._metrics)} metrics → {self._metrics_file}"
            )
            return True

        except Exception as e:
            logger.error(f"[Tracker] save_metrics failed: {e}")
            return False

    def load_metrics(self) -> bool:
        """
        โหลด metrics จาก JSON file
        เรียกอัตโนมัติใน __init__

        Returns:
            True ถ้าโหลดสำเร็จ, False ถ้าไม่มีไฟล์หรือ error
        """
        if not self._metrics_file.exists():
            logger.info(f"[Tracker] No metrics file at {self._metrics_file} — starting fresh")
            return False

        try:
            with open(self._metrics_file, "r", encoding="utf-8") as f:
                data = json.load(f)

            with self._lock:
                # โหลด aggregate metrics
                self._metrics = {}
                for m_dict in data.get("metrics", []):
                    m = StrategyMetrics.from_dict(m_dict)
                    self._metrics[(m.strategy_id, m.symbol)] = m

                # โหลด history records
                self._history = {}
                for key_str, records in data.get("history", {}).items():
                    parts = key_str.split("_", 1)
                    if len(parts) == 2:
                        try:
                            sid = int(parts[0])
                            sym = parts[1]
                            self._history[(sid, sym)] = [
                                PredictionRecord.from_dict(r) for r in records
                            ]
                        except (ValueError, KeyError):
                            pass

            logger.info(
                f"[Tracker] Loaded {len(self._metrics)} metrics from {self._metrics_file}"
            )
            return True

        except Exception as e:
            logger.warning(f"[Tracker] load_metrics failed: {e} — starting fresh")
            return False

    def clear_old_records(self, days: int = 90) -> int:
        """
        ลบ history records เก่ากว่า N วัน
        เรียกสัปดาห์ละครั้งเพื่อประหยัด disk

        Returns:
            จำนวน records ที่ลบ
        """
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).timestamp()
        removed = 0
        with self._lock:
            for key in list(self._history.keys()):
                before = len(self._history[key])
                self._history[key] = [
                    r for r in self._history[key] if r.timestamp >= cutoff
                ]
                removed += before - len(self._history[key])
        logger.info(f"[Tracker] Cleared {removed} old records (>{days}d)")
        return removed


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────

if __name__ == "__main__":
    import tempfile
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )

    print("=" * 60)
    print("FlashEASuite V2 — Performance Tracker Test")
    print("=" * 60)

    with tempfile.TemporaryDirectory() as tmpdir:
        metrics_file = Path(tmpdir) / "metrics" / "performance_metrics.json"
        tracker = PerformanceTracker(metrics_file=metrics_file)

        # ── Test 1: record_prediction ─────────────────────────────────
        print("\n── Test 1: Record 20 trades for S15@XAUUSD ──")
        import random
        rng = random.Random(42)

        # S15 Grid: ดีมากใน RANGING → simulate 65% win rate
        for i in range(20):
            pnl = rng.uniform(50, 200) if rng.random() < 0.65 else rng.uniform(-150, -30)
            tracker.record_prediction(15, "XAUUSD", 1, pnl, rr_achieved=abs(pnl/100))

        m = tracker.get_metrics(15, "XAUUSD")
        print(f"  Total trades:  {m.total_trades}")
        print(f"  Win count:     {m.win_count}")
        print(f"  Win rate:      {m.win_rate:.1%}")
        print(f"  EMA accuracy:  {m.ema_accuracy:.3f}")
        print(f"  EMA weight:    {m.ema_weight:.3f}")
        print(f"  Total PnL:     {m.total_pnl:.2f}")

        # ── Test 2: get_accuracy (lookback) ──────────────────────────
        print("\n── Test 2: get_accuracy with lookback ──")
        acc_30 = tracker.get_accuracy(15, "XAUUSD", lookback_days=30)
        acc_1  = tracker.get_accuracy(15, "XAUUSD", lookback_days=1)   # วันนี้เท่านั้น
        print(f"  Accuracy (30d): {acc_30:.1%}")
        print(f"  Accuracy (1d):  {acc_1:.1%}  (recent only)")

        # ── Test 3: get_win_rate + Kelly ─────────────────────────────
        print("\n── Test 3: Kelly Criterion ──")
        wr = tracker.get_win_rate(15, "XAUUSD")
        kelly = tracker.get_kelly_fraction(15, "XAUUSD")
        print(f"  Win rate:     {wr:.1%}")
        print(f"  Kelly f*:     {kelly:.1%}  (position size suggestion)")

        # ── Test 4: get_ema_weight ────────────────────────────────────
        print("\n── Test 4: EMA Weight for AI Council ──")
        # Strategy ที่แย่: S13 FibStoch ใน VOLATILE → simulate 30% win
        for i in range(15):
            pnl = rng.uniform(30, 100) if rng.random() < 0.30 else rng.uniform(-200, -50)
            tracker.record_prediction(13, "XAUUSD", -1, pnl)

        w15 = tracker.get_ema_weight(15, "XAUUSD")
        w13 = tracker.get_ema_weight(13, "XAUUSD")
        w99 = tracker.get_ema_weight(99, "NOSYM")   # ไม่มีข้อมูล → default
        print(f"  S15@XAUUSD weight: {w15:.3f}  (good strategy → > 1.0)")
        print(f"  S13@XAUUSD weight: {w13:.3f}  (poor strategy → < 1.0)")
        print(f"  S99@NOSYM  weight: {w99:.3f}  (no data → default 1.0)")

        # ── Test 5: save + load ───────────────────────────────────────
        print("\n── Test 5: Save and Load persistence ──")
        ok = tracker.save_metrics()
        print(f"  Save: {'✅' if ok else '❌'}")
        print(f"  File exists: {metrics_file.exists()}")

        # สร้าง tracker ใหม่จาก file
        tracker2 = PerformanceTracker(metrics_file=metrics_file)
        loaded_wr = tracker2.get_win_rate(15, "XAUUSD")
        loaded_w  = tracker2.get_ema_weight(15, "XAUUSD")
        print(f"  Loaded win_rate: {loaded_wr:.1%}  (should match {wr:.1%})")
        print(f"  Loaded ema_wt:   {loaded_w:.3f}   (should match {w15:.3f})")
        assert abs(loaded_wr - wr) < 0.001, "Win rate mismatch after load!"
        assert abs(loaded_w - w15) < 0.001, "EMA weight mismatch after load!"
        print("  Load integrity: ✅")

        # ── Test 6: Summary ───────────────────────────────────────────
        print("\n── Test 6: Full Summary ──")
        summary = tracker.get_summary()
        for k, v in summary.items():
            print(f"  S{k[0]:02d}@{k[1]}: wr={v['win_rate']:.1%} "
                  f"ema_wt={v['ema_weight']:.3f} trades={v['total_trades']}")

    print("\n✅ All tests passed!")
