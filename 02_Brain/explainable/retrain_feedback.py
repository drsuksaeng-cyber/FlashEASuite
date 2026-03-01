"""
retrain_feedback.py
FlashEASuite V2 — P4-6: Retrain Feedback (Destination 4)
=========================================================
เปรียบเทียบ reasoning prediction vs actual outcome
-> คำนวณ accuracy per strategyxsymbol
-> trigger weight adjustment เมื่อ accuracy ตก

Flow:
  1. StrategyCouncil เลือก S15 สำหรับ XAUUSD (confidence=0.78)
  2. Trade เปิดและปิด -> ส่ง TRADE_REPORT กลับมา
  3. retrain_feedback.record_outcome(S15, XAUUSD, prediction, actual_pnl)
  4. ถ้า accuracy ตกต่ำกว่า threshold -> trigger_retrain(S15, XAUUSD)
  5. StrategyCouncil ใช้ adjusted weight รอบถัดไป

Integration:
  ← performance_tracker.py (P4-4): ใช้ data ร่วมกัน
  -> strategy_council.py (P4-3): อัปเดต hist_perf_factor

Save: 02_Brain/explainable/retrain_feedback.py
"""

import json
import logging
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional, Callable

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

EMA_ALPHA: float = 0.1              # EMA smoothing (เหมือน P4-3)
ACCURACY_DROP_THRESHOLD: float = 0.45   # ถ้า accuracy < 45% -> trigger retrain
ACCURACY_WINDOW_TRADES: int = 20     # ใช้ 20 trades ล่าสุดเท่านั้น
MIN_TRADES_FOR_RETRAIN: int = 10     # ต้องมี ≥ 10 trades ก่อน trigger
WEIGHT_ADJUST_STEP: float = 0.05    # ปรับ weight ทีละ 5%
WEIGHT_MIN: float = 0.50
WEIGHT_MAX: float = 1.50
STORAGE_FILE_DEFAULT = Path("02_Brain/data/retrain_feedback.json")


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class OutcomeRecord:
    """บันทึก 1 trade outcome เพื่อเปรียบเทียบกับ prediction"""
    strategy_id: int
    symbol: str
    predicted_direction: int    # 1=BUY, -1=SELL (prediction ของ council)
    predicted_confidence: float # weighted_confidence ที่ council ให้
    actual_pnl: float           # pnl จริงที่ได้
    was_correct: bool           # True ถ้า pnl > 0
    timestamp: float            # unix timestamp
    regime: str = "UNKNOWN"     # P9-1: regime ตอนที่ตัดสินใจ

    def to_dict(self) -> dict:
        return {
            "sid": self.strategy_id,
            "sym": self.symbol,
            "pred_dir": self.predicted_direction,
            "pred_conf": round(self.predicted_confidence, 4),
            "pnl": round(self.actual_pnl, 4),
            "ok": self.was_correct,
            "ts": self.timestamp,
            "reg": self.regime,
        }

    @staticmethod
    def from_dict(d: dict) -> "OutcomeRecord":
        return OutcomeRecord(
            strategy_id=d["sid"],
            symbol=d["sym"],
            predicted_direction=d.get("pred_dir", 1),
            predicted_confidence=d.get("pred_conf", 0.5),
            actual_pnl=d.get("pnl", 0.0),
            was_correct=d.get("ok", False),
            timestamp=d.get("ts", 0.0),
            regime=d.get("reg", "UNKNOWN"),
        )


@dataclass
class StrategyWeightState:
    """Weight state สำหรับ 1 strategyxsymbol pair"""
    strategy_id: int
    symbol: str
    current_weight: float = 1.0     # hist_perf_factor ปัจจุบัน (-> council)
    ema_accuracy: float = 0.5       # EMA accuracy
    trade_count: int = 0
    retrain_count: int = 0
    last_retrain_at: Optional[float] = None
    last_adjusted_at: Optional[float] = None

    def update_ema(self, was_correct: bool) -> None:
        outcome = 1.0 if was_correct else 0.0
        self.ema_accuracy = EMA_ALPHA * outcome + (1.0 - EMA_ALPHA) * self.ema_accuracy
        self.trade_count += 1

    def adjust_weight(self, direction: str) -> float:
        """เพิ่มหรือลด weight ทีละ step"""
        if direction == "up":
            self.current_weight = min(WEIGHT_MAX, self.current_weight + WEIGHT_ADJUST_STEP)
        else:
            self.current_weight = max(WEIGHT_MIN, self.current_weight - WEIGHT_ADJUST_STEP)
        self.last_adjusted_at = datetime.now(timezone.utc).timestamp()
        return self.current_weight

    def to_dict(self) -> dict:
        return {
            "sid": self.strategy_id,
            "sym": self.symbol,
            "weight": round(self.current_weight, 4),
            "ema_acc": round(self.ema_accuracy, 6),
            "trades": self.trade_count,
            "retrains": self.retrain_count,
            "last_retrain": self.last_retrain_at,
            "last_adjusted": self.last_adjusted_at,
        }

    @staticmethod
    def from_dict(d: dict) -> "StrategyWeightState":
        s = StrategyWeightState(
            strategy_id=d["sid"],
            symbol=d["sym"],
            current_weight=d.get("weight", 1.0),
            ema_accuracy=d.get("ema_acc", 0.5),
            trade_count=d.get("trades", 0),
            retrain_count=d.get("retrains", 0),
            last_retrain_at=d.get("last_retrain"),
            last_adjusted_at=d.get("last_adjusted"),
        )
        return s


@dataclass
class RetrainTrigger:
    """เหตุที่ trigger retrain"""
    strategy_id: int
    symbol: str
    trigger_reason: str          # "accuracy_drop", "manual", "regime_change"
    current_accuracy: float
    current_weight: float
    new_weight: float
    trade_count: int
    timestamp: str


# ─────────────────────────────────────────────
# RetrainFeedback
# ─────────────────────────────────────────────

class RetrainFeedback:
    """
    Destination 4: Auto-Retrain Feedback

    Record trade outcomes -> compare with predictions -> adjust council weights

    Key methods:
        record_outcome(strategy, symbol, direction, confidence, actual_pnl)
            -> update EMA accuracy
            -> ถ้า accuracy ตก -> adjust_weight() + trigger_retrain()

        get_weight(strategy, symbol)
            -> คืน hist_perf_factor ให้ StrategyCouncil ใช้

        save() / load()
            -> persistent storage
    """

    def __init__(
        self,
        storage_file: Optional[Path] = None,
        on_retrain_trigger: Optional[Callable[[RetrainTrigger], None]] = None,
    ):
        """
        Args:
            storage_file:        Path ของ JSON storage
            on_retrain_trigger:  Callback ที่เรียกเมื่อ trigger retrain
                                 ใช้เพื่อ notify StrategyCouncil หรือ log
        """
        self._storage_file = Path(storage_file or STORAGE_FILE_DEFAULT)
        self._on_retrain = on_retrain_trigger
        self._lock = threading.Lock()

        # weight states: {(sid, symbol): StrategyWeightState}
        self._weights: dict[tuple[int, str], StrategyWeightState] = {}

        # outcome history: {(sid, symbol): [OutcomeRecord]}
        self._history: dict[tuple[int, str], list[OutcomeRecord]] = {}

        # P9-1: per-regime history: {(sid, regime): [OutcomeRecord]}
        self._regime_history: dict[tuple[int, str], list[OutcomeRecord]] = {}

        # retrain triggers log
        self._triggers: list[RetrainTrigger] = []

        self.load()

        logger.info(
            f"[Feedback] RetrainFeedback initialized | "
            f"{len(self._weights)} strategyxsymbol pairs"
        )

    # ─────────────────────────────────────────
    # Core: record outcome
    # ─────────────────────────────────────────

    def record_outcome(
        self,
        strategy_id: int,
        symbol: str,
        predicted_direction: int,
        predicted_confidence: float,
        actual_pnl: float,
        regime: str = "UNKNOWN",        # P9-1: optional regime tracking
    ) -> Optional[RetrainTrigger]:
        """
        บันทึก trade outcome และตรวจสอบว่าควร retrain หรือไม่

        Args:
            strategy_id:          1-16
            symbol:               e.g. "XAUUSD"
            predicted_direction:  1=BUY, -1=SELL (จาก council)
            predicted_confidence: weighted_confidence (จาก council)
            actual_pnl:           pnl จริง (บวก=กำไร, ลบ=ขาดทุน)
            regime:               P9-1: regime ตอนที่ตัดสินใจ (optional)

        Returns:
            RetrainTrigger ถ้า trigger retrain, None ถ้าไม่
        """
        was_correct = actual_pnl > 0.0
        now = datetime.now(timezone.utc).timestamp()

        record = OutcomeRecord(
            strategy_id=strategy_id,
            symbol=symbol,
            predicted_direction=predicted_direction,
            predicted_confidence=predicted_confidence,
            actual_pnl=actual_pnl,
            was_correct=was_correct,
            timestamp=now,
            regime=regime,
        )

        key = (strategy_id, symbol)

        with self._lock:
            # เพิ่มใน history (by symbol)
            if key not in self._history:
                self._history[key] = []
            self._history[key].append(record)

            # Trim history
            if len(self._history[key]) > ACCURACY_WINDOW_TRADES * 5:
                self._history[key] = self._history[key][-ACCURACY_WINDOW_TRADES * 5:]

            # P9-1: เพิ่มใน regime history (by regime)
            reg_key = (strategy_id, regime)
            if reg_key not in self._regime_history:
                self._regime_history[reg_key] = []
            self._regime_history[reg_key].append(record)
            if len(self._regime_history[reg_key]) > 500:
                self._regime_history[reg_key] = self._regime_history[reg_key][-500:]

            # อัปเดต weight state
            if key not in self._weights:
                self._weights[key] = StrategyWeightState(strategy_id, symbol)
            state = self._weights[key]
            state.update_ema(was_correct)

        logger.debug(
            f"[Feedback] S{strategy_id:02d}@{symbol}[{regime}] "
            f"{'WIN' if was_correct else 'LOSS'} pnl={actual_pnl:.2f} "
            f"ema_acc={state.ema_accuracy:.3f} weight={state.current_weight:.3f}"
        )

        # ตรวจสอบว่าควร retrain หรือไม่
        trigger = self._check_retrain(strategy_id, symbol, state)
        return trigger

    # ─────────────────────────────────────────
    # Query
    # ─────────────────────────────────────────

    def get_weight(self, strategy_id: int, symbol: str) -> float:
        """
        คืน current hist_perf_factor สำหรับ StrategyCouncil ใช้
        Range: [0.5, 1.5]

        ถ้าไม่มีข้อมูล = คืน 1.0 (neutral)
        """
        key = (strategy_id, symbol)
        with self._lock:
            state = self._weights.get(key)
        if state is None or state.trade_count < MIN_TRADES_FOR_RETRAIN:
            return 1.0
        return state.current_weight

    def get_accuracy(self, strategy_id: int, symbol: str, window: int = ACCURACY_WINDOW_TRADES) -> float:
        """
        คำนวณ accuracy ใน N trades ล่าสุด

        Returns:
            accuracy 0.0-1.0 หรือ 0.5 (neutral) ถ้าไม่มีข้อมูล
        """
        key = (strategy_id, symbol)
        with self._lock:
            history = self._history.get(key, [])

        recent = history[-window:] if len(history) >= window else history
        if not recent:
            return 0.5

        correct = sum(1 for r in recent if r.was_correct)
        return correct / len(recent)

    def get_all_weights(self) -> dict[tuple[int, str], float]:
        """คืน weights ทุก strategyxsymbol (สำหรับ bulk update ใน council)"""
        with self._lock:
            return {
                k: s.current_weight
                for k, s in self._weights.items()
                if s.trade_count >= MIN_TRADES_FOR_RETRAIN
            }

    def get_retrain_history(self, last_n: int = 10) -> list[RetrainTrigger]:
        """คืน retrain trigger history ล่าสุด"""
        with self._lock:
            return self._triggers[-last_n:]

    def get_summary(self) -> dict:
        """สรุปสถานะทั้งหมด"""
        with self._lock:
            return {
                f"S{k[0]:02d}@{k[1]}": {
                    "weight": round(v.current_weight, 3),
                    "ema_acc": round(v.ema_accuracy, 3),
                    "trades": v.trade_count,
                    "retrains": v.retrain_count,
                }
                for k, v in self._weights.items()
            }

    # ─────────────────────────────────────────
    # P9-1: Regime-level accuracy + weight suggestions
    # ─────────────────────────────────────────

    def calculate_accuracy(
        self,
        strategy_id: int,
        regime: str,
        lookback_days: int = 30,
    ) -> float:
        """
        P9-1: คำนวณ accuracy per strategy x regime ใน lookback window

        Args:
            strategy_id:   1-16
            regime:        RANGING/TRENDING/VOLATILE/SQUEEZE
            lookback_days: ดูข้อมูลย้อนหลัง N วัน

        Returns:
            accuracy 0.0-1.0 (0.5 ถ้ายังไม่มีข้อมูล)
        """
        from datetime import timedelta
        cutoff = (datetime.now(timezone.utc) - timedelta(days=lookback_days)).timestamp()
        reg_key = (strategy_id, regime)

        with self._lock:
            records = [
                r for r in self._regime_history.get(reg_key, [])
                if r.timestamp >= cutoff
            ]

        if len(records) < 2:
            return 0.5

        correct = sum(1 for r in records if r.was_correct)
        return round(correct / len(records), 4)

    def suggest_weight_update(self) -> dict:
        """
        P9-1: คืน suggested weights สำหรับทุก strategyxregime pair

        Returns:
            {
              "S01_RANGING": {
                "strategy_id": 1, "regime": "RANGING",
                "total_trades": 45, "current_ema": 0.72,
                "suggested_weight": 1.22, "needs_reweight": False
              }, ...
            }
        """
        result: dict = {}
        REGIME_DROP_THRESHOLD = 0.10    # ถ้า EMA ลดจาก peak เกิน 10% -> needs_reweight

        with self._lock:
            # กลุ่มตาม (strategy_id, regime)
            for reg_key, records in self._regime_history.items():
                sid, regime = reg_key
                if len(records) < MIN_TRADES_FOR_RETRAIN:
                    continue

                # คำนวณ EMA ตั้งแต่แรกจนปัจจุบัน
                ema = 0.5
                peak_ema = 0.5
                for r in records:
                    outcome = 1.0 if r.was_correct else 0.0
                    ema = EMA_ALPHA * outcome + (1.0 - EMA_ALPHA) * ema
                    if ema > peak_ema:
                        peak_ema = ema

                drop = peak_ema - ema
                suggested_weight = min(WEIGHT_MAX, max(WEIGHT_MIN, 0.5 + ema * 1.0))

                key_str = f"S{sid:02d}_{regime}"
                result[key_str] = {
                    "strategy_id":      sid,
                    "regime":           regime,
                    "total_trades":     len(records),
                    "current_ema":      round(ema, 4),
                    "peak_ema":         round(peak_ema, 4),
                    "suggested_weight": round(suggested_weight, 4),
                    "needs_reweight":   drop >= REGIME_DROP_THRESHOLD,
                }

        return result

    def get_accuracy_report(self) -> dict:
        """
        P9-1: Report รวม accuracy ทุก strategy x regime

        Returns:
            {
              "generated_at": "...",
              "total_pairs": N,
              "strategies": {
                1: {"RANGING": {"accuracy": 0.71, "trades": 45, "weight": 1.21}, ...},
                ...
              },
              "reweight_needed": ["S01_VOLATILE", ...]
            }
        """
        suggestions = self.suggest_weight_update()
        report: dict = {
            "generated_at":    datetime.now(timezone.utc).isoformat(),
            "total_pairs":     len(suggestions),
            "strategies":      {},
            "reweight_needed": [],
        }

        for key_str, info in suggestions.items():
            sid   = info["strategy_id"]
            regime = info["regime"]
            if sid not in report["strategies"]:
                report["strategies"][sid] = {}
            report["strategies"][sid][regime] = {
                "accuracy": info["current_ema"],
                "trades":   info["total_trades"],
                "weight":   info["suggested_weight"],
            }
            if info["needs_reweight"]:
                report["reweight_needed"].append(key_str)

        return report

    # ─────────────────────────────────────────
    # Retrain logic
    # ─────────────────────────────────────────

    def _check_retrain(
        self,
        strategy_id: int,
        symbol: str,
        state: StrategyWeightState,
    ) -> Optional[RetrainTrigger]:
        """
        ตรวจสอบว่าควร trigger retrain หรือปรับ weight หรือไม่
        """
        if state.trade_count < MIN_TRADES_FOR_RETRAIN:
            return None   # ยังมีข้อมูลน้อยเกินไป

        acc = self.get_accuracy(strategy_id, symbol)
        old_weight = state.current_weight

        trigger = None

        if acc < ACCURACY_DROP_THRESHOLD:
            # Accuracy ตกต่ำมาก -> ลด weight + trigger retrain
            with self._lock:
                new_weight = state.adjust_weight("down")
                state.retrain_count += 1
                state.last_retrain_at = datetime.now(timezone.utc).timestamp()

            trigger = RetrainTrigger(
                strategy_id=strategy_id,
                symbol=symbol,
                trigger_reason="accuracy_drop",
                current_accuracy=acc,
                current_weight=old_weight,
                new_weight=new_weight,
                trade_count=state.trade_count,
                timestamp=datetime.now(timezone.utc).isoformat(),
            )
            with self._lock:
                self._triggers.append(trigger)

            logger.warning(
                f"[Feedback] 🔁 RETRAIN TRIGGERED: S{strategy_id:02d}@{symbol} "
                f"acc={acc:.1%} < {ACCURACY_DROP_THRESHOLD:.1%} | "
                f"weight: {old_weight:.3f} -> {new_weight:.3f}"
            )

            if self._on_retrain:
                try:
                    self._on_retrain(trigger)
                except Exception as e:
                    logger.error(f"[Feedback] retrain callback error: {e}")

        elif acc > 0.65 and state.current_weight < WEIGHT_MAX:
            # Accuracy ดีขึ้นมาก -> เพิ่ม weight (ค่อยๆ)
            with self._lock:
                state.adjust_weight("up")

            logger.debug(
                f"[Feedback] 📈 Weight UP: S{strategy_id:02d}@{symbol} "
                f"acc={acc:.1%} weight={old_weight:.3f}->{state.current_weight:.3f}"
            )

        return trigger

    # ─────────────────────────────────────────
    # Persistence
    # ─────────────────────────────────────────

    def save(self) -> bool:
        """บันทึก state ลง JSON file"""
        try:
            self._storage_file.parent.mkdir(parents=True, exist_ok=True)

            with self._lock:
                data = {
                    "version": "1.0",
                    "saved_at": datetime.now(timezone.utc).isoformat(),
                    "weights": [s.to_dict() for s in self._weights.values()],
                    "history": {
                        f"{k[0]}_{k[1]}": [r.to_dict() for r in v[-100:]]
                        for k, v in self._history.items()
                    },
                    "regime_history": {
                        f"{k[0]}_{k[1]}": [r.to_dict() for r in v[-200:]]
                        for k, v in self._regime_history.items()
                    },
                    "triggers": [
                        {
                            "sid": t.strategy_id,
                            "sym": t.symbol,
                            "reason": t.trigger_reason,
                            "acc": t.current_accuracy,
                            "weight_old": t.current_weight,
                            "weight_new": t.new_weight,
                            "ts": t.timestamp,
                        }
                        for t in self._triggers[-50:]
                    ],
                }

            tmp = self._storage_file.with_suffix(".tmp")
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            tmp.replace(self._storage_file)

            logger.debug(f"[Feedback] Saved -> {self._storage_file}")
            return True
        except Exception as e:
            logger.error(f"[Feedback] save failed: {e}")
            return False

    def load(self) -> bool:
        """โหลด state จาก JSON file"""
        if not self._storage_file.exists():
            return False
        try:
            with open(self._storage_file, "r", encoding="utf-8") as f:
                data = json.load(f)

            with self._lock:
                self._weights = {}
                for w in data.get("weights", []):
                    s = StrategyWeightState.from_dict(w)
                    self._weights[(s.strategy_id, s.symbol)] = s

                self._history = {}
                for key_str, records in data.get("history", {}).items():
                    parts = key_str.split("_", 1)
                    if len(parts) == 2:
                        try:
                            sid = int(parts[0])
                            sym = parts[1]
                            self._history[(sid, sym)] = [
                                OutcomeRecord.from_dict(r) for r in records
                            ]
                        except Exception:
                            pass

                # P9-1: โหลด regime_history
                self._regime_history = {}
                for key_str, records in data.get("regime_history", {}).items():
                    parts = key_str.split("_", 1)
                    if len(parts) == 2:
                        try:
                            sid = int(parts[0])
                            reg = parts[1]
                            self._regime_history[(sid, reg)] = [
                                OutcomeRecord.from_dict(r) for r in records
                            ]
                        except Exception:
                            pass

            logger.info(f"[Feedback] Loaded {len(self._weights)} weight states")
            return True
        except Exception as e:
            logger.warning(f"[Feedback] load failed: {e}")
            return False


# ─────────────────────────────────────────────
# Standalone test
# ─────────────────────────────────────────────

if __name__ == "__main__":
    import tempfile
    import random
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )

    print("=" * 60)
    print("FlashEASuite V2 — Retrain Feedback Test")
    print("=" * 60)

    retrain_events: list[RetrainTrigger] = []

    def on_retrain(trigger: RetrainTrigger):
        retrain_events.append(trigger)
        print(
            f"  🔔 CALLBACK: S{trigger.strategy_id:02d}@{trigger.symbol} "
            f"acc={trigger.current_accuracy:.1%} "
            f"weight {trigger.current_weight:.3f}->{trigger.new_weight:.3f}"
        )

    with tempfile.TemporaryDirectory() as tmpdir:
        storage = Path(tmpdir) / "retrain.json"
        feedback = RetrainFeedback(storage_file=storage, on_retrain_trigger=on_retrain)

        rng = random.Random(777)

        # ── Test 1: Good strategy (S15 Grid) — 70% win ────────────────
        print("\n── Test 1: Good strategy S15@XAUUSD (70% win rate) ──")
        for _ in range(20):
            pnl = rng.uniform(50, 200) if rng.random() < 0.70 else rng.uniform(-100, -30)
            feedback.record_outcome(15, "XAUUSD", 1, 0.78, pnl)

        w15 = feedback.get_weight(15, "XAUUSD")
        acc15 = feedback.get_accuracy(15, "XAUUSD")
        print(f"  Weight: {w15:.3f} (should be ≥ 1.0)")
        print(f"  Accuracy: {acc15:.1%} (should be ~70%)")
        assert w15 >= 1.0, f"Good strategy weight should be ≥ 1.0, got {w15}"

        # ── Test 2: Bad strategy (S13 FibStoch) — 30% win ────────────
        print("\n── Test 2: Bad strategy S13@XAUUSD (30% win) -> trigger retrain ──")
        triggered = 0
        for i in range(20):
            pnl = rng.uniform(30, 100) if rng.random() < 0.30 else rng.uniform(-150, -40)
            t = feedback.record_outcome(13, "XAUUSD", -1, 0.60, pnl)
            if t:
                triggered += 1

        w13 = feedback.get_weight(13, "XAUUSD")
        acc13 = feedback.get_accuracy(13, "XAUUSD")
        print(f"  Weight: {w13:.3f} (should be < 1.0)")
        print(f"  Accuracy: {acc13:.1%} (should be ~30%)")
        print(f"  Retrain triggered: {triggered} times")
        assert w13 < 1.0, f"Bad strategy weight should be < 1.0, got {w13}"
        assert triggered >= 1

        # ── Test 3: get_all_weights ────────────────────────────────────
        print("\n── Test 3: get_all_weights ──")
        all_w = feedback.get_all_weights()
        for (sid, sym), w in all_w.items():
            print(f"  S{sid:02d}@{sym}: {w:.3f}")

        # ── Test 4: save + load ────────────────────────────────────────
        print("\n── Test 4: Save and Load ──")
        ok = feedback.save()
        assert ok
        print(f"  Save: ✅")

        feedback2 = RetrainFeedback(storage_file=storage)
        w15_loaded = feedback2.get_weight(15, "XAUUSD")
        w13_loaded = feedback2.get_weight(13, "XAUUSD")
        print(f"  Loaded S15 weight: {w15_loaded:.3f} (should match {w15:.3f})")
        print(f"  Loaded S13 weight: {w13_loaded:.3f} (should match {w13:.3f})")
        assert abs(w15_loaded - w15) < 0.001
        assert abs(w13_loaded - w13) < 0.001
        print("  Load integrity: ✅")

        # ── Test 5: retrain history ────────────────────────────────────
        print("\n── Test 5: Retrain trigger history ──")
        history = feedback.get_retrain_history()
        print(f"  Total triggers: {len(history)}")
        for t in history:
            print(
                f"  [{t.timestamp[:16]}] S{t.strategy_id:02d}@{t.symbol} "
                f"acc={t.current_accuracy:.1%} reason={t.trigger_reason}"
            )

        # ── Test 6: Summary ────────────────────────────────────────────
        print("\n── Test 6: Summary ──")
        summary = feedback.get_summary()
        for k, v in summary.items():
            print(f"  {k}: weight={v['weight']} acc={v['ema_acc']} trades={v['trades']}")

    print("\n✅ All tests passed!")
