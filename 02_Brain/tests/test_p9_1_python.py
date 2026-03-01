"""
test_p9_1_python.py
FlashEASuite V2 — P9-1: Python Integration Tests
==================================================
ทดสอบ decision_logger.py + retrain_feedback.py

วิธีรัน:
    cd 02_Brain
    python -m pytest tests/test_p9_1_python.py -v
    หรือ:
    python tests/test_p9_1_python.py

Save: 02_Brain/tests/test_p9_1_python.py
"""

import csv
import json
import random
import sys
import tempfile
from pathlib import Path
from datetime import datetime, timezone, timedelta

# ─── Setup sys.path ───────────────────────────────────────────────
# รองรับทั้ง pytest และ python direct
_BRAIN_DIR = Path(__file__).parent.parent  # 02_Brain/
if str(_BRAIN_DIR) not in sys.path:
    sys.path.insert(0, str(_BRAIN_DIR))

from explainable.decision_logger import DecisionLogger
from explainable.retrain_feedback import RetrainFeedback, RetrainTrigger


# ─── Fixtures / Helpers ───────────────────────────────────────────

def _make_reasoning_record(symbol="XAUUSD", sid=15, score=0.75, regime="TRENDING"):
    """Mock ReasoningChain.to_dict() output"""
    return {
        "symbol":      symbol,
        "cycle_id":    datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S"),
        "timestamp":   datetime.now(timezone.utc).isoformat(),
        "regime": {
            "type":       regime,
            "method":     "3-layer",
            "confidence": 0.82,
            "detail":     f"ADX=28.5 Rule→{regime}",
        },
        "votes": [
            {"strategy": f"S{i:02d}", "vote": random.choice([0, 1, -1]), "score": round(random.uniform(0.4, 0.9), 3)}
            for i in range(1, 5)
        ],
        "vote_summary": {"total": 16, "eligible": 7, "selected": 1},
        "selected": [{
            "rank":           1,
            "strategy":       f"S{sid:02d}",
            "name":           "Grid" if sid == 15 else "Spike",
            "score":          score,
            "allocation_pct": 100.0,
        }],
        "mm":   {"method": "MM03", "name": "ATR-Based", "reasoning": "Regime=TRENDING → MM03"},
        "risk": {"multiplier": 1.0, "reasoning": "DD=2.1% < threshold=10%"},
        "summary_th": f"[TEST] {symbol} S{sid:02d} score={score:.2f} regime={regime}",
        "summary_en": f"[TEST] {symbol} S{sid:02d} score={score:.2f} regime={regime}",
    }


# ─── DecisionLogger Tests ─────────────────────────────────────────

class TestDecisionLogger:
    """Test suite for decision_logger.py"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self.log_dir    = Path(self._tmpdir) / "logs" / "decisions"
        self.report_dir = Path(self._tmpdir) / "logs" / "reports"
        self.logger = DecisionLogger(
            log_dir=self.log_dir,
            report_dir=self.report_dir,
            rotation_days=30,
        )

    # ── Test 1 ──────────────────────────────────────────────────────
    def test_01_directories_created(self):
        """log_dir และ report_dir ต้องถูกสร้างอัตโนมัติ"""
        assert self.log_dir.exists(), "log_dir ไม่ถูกสร้าง"
        assert self.report_dir.exists(), "report_dir ไม่ถูกสร้าง"
        print("✅ test_01_directories_created")

    # ── Test 2 ──────────────────────────────────────────────────────
    def test_02_log_and_flush(self):
        """log() + flush() ต้องสร้างไฟล์ JSON และ count ถูกต้อง"""
        rng = random.Random(42)
        for i in range(5):
            rec = _make_reasoning_record(
                symbol=rng.choice(["XAUUSD","EURUSD"]),
                sid=rng.choice([15, 16]),
                score=rng.uniform(0.6, 0.9),
            )
            assert self.logger.log(rec), f"log() failed at i={i}"

        self.logger.flush()

        files = list(self.log_dir.glob("*.json"))
        assert len(files) >= 1, "ไม่มีไฟล์ JSON หลัง flush"

        with open(files[0], encoding="utf-8") as f:
            data = json.load(f)

        assert "records" in data
        assert data["count"] >= 1
        assert "date" in data
        assert "updated_at" in data
        print(f"✅ test_02_log_and_flush — {data['count']} records in {files[0].name}")

    # ── Test 3 ──────────────────────────────────────────────────────
    def test_03_log_chain_shortcut(self):
        """log_chain() ต้องรับ object ที่มี to_dict()"""
        class FakeChain:
            def to_dict(self):
                return _make_reasoning_record()

        chain = FakeChain()
        assert self.logger.log_chain(chain), "log_chain() failed"
        self.logger.flush()
        print("✅ test_03_log_chain_shortcut")

    # ── Test 4 ──────────────────────────────────────────────────────
    def test_04_daily_csv_generated(self):
        """generate_daily_csv() ต้องสร้าง CSV พร้อม header ถูกต้อง"""
        rng = random.Random(99)
        for _ in range(10):
            self.logger.log(_make_reasoning_record(
                symbol=rng.choice(["XAUUSD","GBPUSD"]),
                sid=rng.choice([1,7,15]),
            ))
        self.logger.flush()

        csv_path = self.logger.generate_daily_csv()
        assert csv_path is not None, "generate_daily_csv() returned None"
        assert csv_path.exists(), f"CSV ไม่ถูกสร้าง: {csv_path}"

        with open(csv_path, encoding="utf-8") as f:
            rows = list(csv.reader(f))

        assert len(rows) > 1, "CSV ว่างเปล่า"
        header = rows[0]
        for col in ["timestamp", "symbol", "regime_type", "selected_strategies", "mm_method"]:
            assert col in header, f"Column '{col}' ไม่อยู่ใน header: {header}"
        print(f"✅ test_04_daily_csv_generated — {len(rows)-1} data rows, columns={header}")

    # ── Test 5 ──────────────────────────────────────────────────────
    def test_05_weekly_csv_aggregation(self):
        """generate_weekly_csv() ต้องรวมข้อมูลและ aggregate ถูกต้อง"""
        rng = random.Random(7)
        for _ in range(15):
            self.logger.log(_make_reasoning_record(
                symbol=rng.choice(["XAUUSD","EURUSD"]),
                sid=rng.choice([15, 16]),
            ))
        self.logger.flush()

        weekly = self.logger.generate_weekly_csv()
        assert weekly is not None
        assert weekly.exists()

        with open(weekly, encoding="utf-8") as f:
            rows = list(csv.reader(f))
        assert len(rows) > 1
        print(f"✅ test_05_weekly_csv — {len(rows)-1} rows in {weekly.name}")

    # ── Test 6 ──────────────────────────────────────────────────────
    def test_06_rotation_removes_old_files(self):
        """rotate() ต้องลบไฟล์ที่เก่ากว่า rotation_days"""
        old_date = (datetime.now(timezone.utc) - timedelta(days=35)).strftime("%Y%m%d")
        old_file = self.log_dir / f"{old_date}_06.json"
        old_file.parent.mkdir(parents=True, exist_ok=True)
        with open(old_file, "w", encoding="utf-8") as f:
            json.dump({"date": old_date, "records": [], "count": 0}, f)

        removed = self.logger.rotate()
        assert removed >= 1, "rotate() ไม่ลบไฟล์เก่า"
        assert not old_file.exists(), "ไฟล์เก่ายังอยู่หลัง rotate"
        print(f"✅ test_06_rotation — removed {removed} file(s)")

    # ── Test 7 ──────────────────────────────────────────────────────
    def test_07_get_stats(self):
        """get_stats() ต้องคืน dict พร้อม keys ที่ถูกต้อง"""
        for _ in range(3):
            self.logger.log(_make_reasoning_record())
        self.logger.flush()

        stats = self.logger.get_stats()
        assert "log_files" in stats
        assert "total_records" in stats
        assert "buffer_pending" in stats
        assert stats["total_records"] >= 3
        print(f"✅ test_07_get_stats — {stats}")

    # ── Test 8 ──────────────────────────────────────────────────────
    def test_08_encoding_utf8_safe(self):
        """log ที่มีภาษาไทยต้องอ่านกลับได้ถูกต้อง"""
        rec = _make_reasoning_record()
        rec["summary_th"] = "ทดสอบภาษาไทย — สัญญาณซื้อ XAUUSD แข็งแกร่ง"
        self.logger.log(rec)
        self.logger.flush()

        files = list(self.log_dir.glob("*.json"))
        with open(files[0], encoding="utf-8") as f:
            data = json.load(f)

        thai_found = any(
            "ทดสอบ" in r.get("summary_th", "")
            for r in data.get("records", [])
        )
        assert thai_found, "ภาษาไทยหาย — encoding error"
        print("✅ test_08_encoding_utf8_safe")


# ─── RetrainFeedback Tests ────────────────────────────────────────

class TestRetrainFeedback:
    """Test suite for retrain_feedback.py"""

    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._storage = Path(self._tmpdir) / "retrain.json"
        self._triggers = []

        def _on_trigger(t: RetrainTrigger):
            self._triggers.append(t)

        self.feedback = RetrainFeedback(
            storage_file=self._storage,
            on_retrain_trigger=_on_trigger,
        )

    # ── Test 1 ──────────────────────────────────────────────────────
    def test_01_good_strategy_weight_increases(self):
        """Strategy ที่ win rate สูง (70%) ต้อง weight >= 1.0"""
        rng = random.Random(42)
        for _ in range(20):
            pnl = rng.uniform(50, 200) if rng.random() < 0.70 else rng.uniform(-100, -30)
            self.feedback.record_outcome(15, "XAUUSD", 1, 0.78, pnl)

        w = self.feedback.get_weight(15, "XAUUSD")
        acc = self.feedback.get_accuracy(15, "XAUUSD")
        assert w >= 1.0, f"Good strategy weight ต้อง >= 1.0 แต่ได้ {w:.3f}"
        assert acc >= 0.55, f"Accuracy ต้อง >= 55% แต่ได้ {acc:.1%}"
        print(f"✅ test_01_good_strategy — weight={w:.3f} acc={acc:.1%}")

    # ── Test 2 ──────────────────────────────────────────────────────
    def test_02_bad_strategy_triggers_retrain(self):
        """Strategy ที่ win rate ต่ำ (30%) ต้อง trigger retrain และ weight ลด"""
        rng = random.Random(777)
        triggered = 0
        for _ in range(20):
            pnl = rng.uniform(30, 100) if rng.random() < 0.30 else rng.uniform(-150, -40)
            t = self.feedback.record_outcome(13, "XAUUSD", -1, 0.60, pnl)
            if t:
                triggered += 1

        w = self.feedback.get_weight(13, "XAUUSD")
        assert w < 1.0, f"Bad strategy weight ต้อง < 1.0 แต่ได้ {w:.3f}"
        assert triggered >= 1, "ต้อง trigger retrain อย่างน้อย 1 ครั้ง"
        assert len(self._triggers) >= 1, "on_retrain_trigger callback ไม่ถูกเรียก"
        print(f"✅ test_02_bad_strategy — weight={w:.3f} triggers={triggered}")

    # ── Test 3 ──────────────────────────────────────────────────────
    def test_03_weight_bounds_respected(self):
        """Weight ต้องไม่เกิน WEIGHT_MAX และไม่ต่ำกว่า WEIGHT_MIN"""
        rng = random.Random(1)
        # กด weight ให้ต่ำมาก (win rate 10%)
        for _ in range(50):
            pnl = rng.uniform(10, 50) if rng.random() < 0.10 else rng.uniform(-200, -50)
            self.feedback.record_outcome(2, "EURUSD", 1, 0.5, pnl)

        w_low = self.feedback.get_weight(2, "EURUSD")
        from explainable.retrain_feedback import WEIGHT_MIN, WEIGHT_MAX
        assert w_low >= WEIGHT_MIN, f"Weight ต่ำกว่า MIN: {w_low} < {WEIGHT_MIN}"

        # กด weight ให้สูง (win rate 95%)
        for _ in range(50):
            pnl = rng.uniform(100, 300) if rng.random() < 0.95 else rng.uniform(-10, -5)
            self.feedback.record_outcome(2, "GBPUSD", 1, 0.9, pnl)

        w_high = self.feedback.get_weight(2, "GBPUSD")
        assert w_high <= WEIGHT_MAX, f"Weight เกิน MAX: {w_high} > {WEIGHT_MAX}"
        print(f"✅ test_03_weight_bounds — low={w_low:.3f} high={w_high:.3f}")

    # ── Test 4 ──────────────────────────────────────────────────────
    def test_04_save_and_load_integrity(self):
        """save() + load() ต้องรักษา weight และ accuracy ครบถ้วน"""
        rng = random.Random(55)
        for _ in range(15):
            pnl = rng.uniform(50, 200) if rng.random() < 0.65 else rng.uniform(-100, -30)
            self.feedback.record_outcome(15, "XAUUSD", 1, 0.75, pnl)

        w_before = self.feedback.get_weight(15, "XAUUSD")
        acc_before = self.feedback.get_accuracy(15, "XAUUSD")

        ok = self.feedback.save()
        assert ok, "save() ล้มเหลว"

        # โหลดใหม่
        feedback2 = RetrainFeedback(storage_file=self._storage)
        w_after   = feedback2.get_weight(15, "XAUUSD")
        acc_after  = feedback2.get_accuracy(15, "XAUUSD")

        assert abs(w_after - w_before) < 0.001, \
            f"Weight เปลี่ยนหลัง load: {w_before:.4f} → {w_after:.4f}"
        assert abs(acc_after - acc_before) < 0.001, \
            f"Accuracy เปลี่ยนหลัง load: {acc_before:.4f} → {acc_after:.4f}"
        print(f"✅ test_04_save_load — weight={w_after:.4f} acc={acc_after:.4f}")

    # ── Test 5 ──────────────────────────────────────────────────────
    def test_05_get_all_weights(self):
        """get_all_weights() ต้องคืน dict ที่มีทุก pair ที่บันทึกไว้"""
        pairs = [(15,"XAUUSD"), (16,"XAUUSD"), (7,"EURUSD")]
        rng = random.Random(3)
        for (sid, sym) in pairs:
            for _ in range(5):
                pnl = rng.uniform(20, 100) if rng.random() > 0.4 else rng.uniform(-80, -20)
                self.feedback.record_outcome(sid, sym, 1, 0.7, pnl)

        all_w = self.feedback.get_all_weights()
        assert len(all_w) == len(pairs), \
            f"all_weights count ผิด: {len(all_w)} != {len(pairs)}"
        for (sid, sym) in pairs:
            assert (sid, sym) in all_w, f"ไม่พบ S{sid:02d}@{sym}"
        print(f"✅ test_05_get_all_weights — {len(all_w)} pairs")

    # ── Test 6 ──────────────────────────────────────────────────────
    def test_06_retrain_history(self):
        """get_retrain_history() ต้องคืน trigger list ถูกต้อง"""
        rng = random.Random(8)
        for _ in range(20):
            pnl = rng.uniform(10,50) if rng.random() < 0.20 else rng.uniform(-150,-30)
            self.feedback.record_outcome(3, "XAUUSD", 1, 0.5, pnl)

        history = self.feedback.get_retrain_history()
        assert isinstance(history, list)
        for t in history:
            assert hasattr(t, "strategy_id")
            assert hasattr(t, "symbol")
            assert hasattr(t, "trigger_reason")
        print(f"✅ test_06_retrain_history — {len(history)} trigger(s)")

    # ── Test 7 ──────────────────────────────────────────────────────
    def test_07_summary(self):
        """get_summary() ต้องคืน dict พร้อม weight, ema_acc, trades"""
        rng = random.Random(9)
        for _ in range(8):
            pnl = rng.uniform(50,200) if rng.random() < 0.6 else rng.uniform(-100,-20)
            self.feedback.record_outcome(15, "XAUUSD", 1, 0.7, pnl)

        summary = self.feedback.get_summary()
        assert len(summary) > 0
        for key, val in summary.items():
            assert "weight" in val
            assert "ema_acc" in val
            assert "trades" in val
        print(f"✅ test_07_summary — {len(summary)} entries")

    # ── Test 8 ──────────────────────────────────────────────────────
    def test_08_ema_convergence_direction(self):
        """
        EMA recovery logic: weight ต้อง UP เมื่อ acc > current_weight
        ป้องกัน MISTAKE 7 จาก P8-4 Lessons Learned
        """
        # Drop phase: 40% win rate → weight ลดลง
        rng = random.Random(11)
        for _ in range(20):
            pnl = rng.uniform(30,100) if rng.random() < 0.40 else rng.uniform(-120,-30)
            self.feedback.record_outcome(6, "XAUUSD", 1, 0.6, pnl)
        w_low = self.feedback.get_weight(6, "XAUUSD")

        # Recovery phase: 85% win rate → weight ต้องขึ้น
        for _ in range(20):
            pnl = rng.uniform(50,200) if rng.random() < 0.85 else rng.uniform(-30,-10)
            self.feedback.record_outcome(6, "XAUUSD", 1, 0.85, pnl)
        w_rec = self.feedback.get_weight(6, "XAUUSD")

        assert w_rec > w_low, \
            f"EMA recovery ผิด: w_rec={w_rec:.4f} ต้อง > w_low={w_low:.4f}"
        print(f"✅ test_08_ema_convergence — drop={w_low:.3f} → recover={w_rec:.3f}")


# ─── Main (direct run) ───────────────────────────────────────────

def _run_all():
    import traceback

    suites = [
        ("DecisionLogger", TestDecisionLogger),
        ("RetrainFeedback", TestRetrainFeedback),
    ]

    total_pass = 0
    total_fail = 0

    for suite_name, SuiteClass in suites:
        print(f"\n{'='*60}")
        print(f"  {suite_name}")
        print('='*60)
        suite = SuiteClass()
        methods = sorted(m for m in dir(suite) if m.startswith("test_"))
        for method in methods:
            suite.setup_method()
            try:
                getattr(suite, method)()
                total_pass += 1
            except Exception as e:
                print(f"❌ {method}: {e}")
                traceback.print_exc()
                total_fail += 1

    print(f"\n{'='*60}")
    print(f"  RESULT: {total_pass} PASS / {total_fail} FAIL")
    if total_fail == 0:
        print("  🏆 P9-1 Python Tests: ALL PASS")
    print('='*60)
    return total_fail == 0


if __name__ == "__main__":
    ok = _run_all()
    sys.exit(0 if ok else 1)
