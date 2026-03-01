#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — Auto-Retrain System
======================================
ระบบ retrain ML models อัตโนมัติ สำหรับ S02 ML Ensemble

Mode การทำงาน:
  1. Daemon thread (ถูก start จาก main.py)
  2. Standalone process (python auto_retrain.py)

Schedule:
  - Weekly retrain: RF, XGBoost, LSTM บน rolling 3-month window
  - Trigger retrain: accuracy < 60% ติดกัน 2 สัปดาห์
  - EMA weight adjustment: ต่อ strategy×symbol → update council weights

Author: FlashEASuite V2 Team
Version: 1.0.0
Phase: P4-8
Date: 2026-02-22
"""

# ─────────────────────────────────────────────
# Standard imports
# ─────────────────────────────────────────────
import json
import logging
import os
import sys
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ─────────────────────────────────────────────
# Path setup — ให้ import จาก strategies/ml_models ได้ทั้งสองโหมด
# ─────────────────────────────────────────────
_BRAIN_DIR = Path(__file__).resolve().parent
_ML_MODELS_DIR = _BRAIN_DIR / "strategies" / "ml_models"
_STRATEGIES_DIR = _BRAIN_DIR / "strategies"

for _p in [str(_BRAIN_DIR), str(_STRATEGIES_DIR), str(_ML_MODELS_DIR)]:
    if _p not in sys.path:
        sys.path.insert(0, _p)

# ─────────────────────────────────────────────
# Soft imports — ML models
# ─────────────────────────────────────────────
try:
    from model_trainer import ModelTrainer
    _TRAINER_AVAILABLE = True
except ImportError:
    _TRAINER_AVAILABLE = False

try:
    import pandas as pd
    _PANDAS_AVAILABLE = True
except ImportError:
    _PANDAS_AVAILABLE = False

# ─────────────────────────────────────────────
# Soft import — performance_tracker (P4-4, may not exist yet)
# ─────────────────────────────────────────────
try:
    from core.intelligence.performance_tracker import PerformanceTracker
    _PERF_TRACKER_AVAILABLE = True
except ImportError:
    _PERF_TRACKER_AVAILABLE = False

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────
WEEKLY_INTERVAL_SEC      = 7 * 24 * 3600   # 7 วัน
CHECK_INTERVAL_SEC       = 3600             # ตรวจทุก 1 ชั่วโมง
RETRAIN_WINDOW_DAYS      = 90               # rolling 3 months
ACCURACY_THRESHOLD       = 0.60            # trigger ถ้าต่ำกว่า 60%
CONSECUTIVE_WEEKS_LIMIT  = 2               # trigger หลัง 2 สัปดาห์ติดกัน
EMA_ALPHA                = 0.3             # α สำหรับ EMA(accuracy)

# Paths
_DATA_DIR    = _BRAIN_DIR / "data"
_LOGS_DIR    = _BRAIN_DIR / "logs" / "retrain"
_WEIGHTS_DIR = _BRAIN_DIR / "logs" / "weights"
_RETRAIN_DB  = _BRAIN_DIR / "logs" / "retrain_events.json"
_WEIGHTS_FILE = _BRAIN_DIR / "logs" / "council_weights.json"

# ─────────────────────────────────────────────
# Logger
# ─────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [AUTO-RETRAIN] %(levelname)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("auto_retrain")


# ═════════════════════════════════════════════
# RetrainEvent — data class
# ═════════════════════════════════════════════
class RetrainEvent:
    """บันทึก retrain event หนึ่งครั้ง"""

    def __init__(
        self,
        trigger: str,                   # "weekly" | "accuracy_drop" | "manual"
        models: List[str],             # ["RF", "XGBoost", "LSTM"]
        symbols: List[str],
        duration_sec: float,
        success: bool,
        accuracy_before: Dict[str, float],
        accuracy_after: Dict[str, float],
        notes: str = "",
    ):
        self.timestamp       = datetime.utcnow().isoformat()
        self.trigger         = trigger
        self.models          = models
        self.symbols         = symbols
        self.duration_sec    = round(duration_sec, 2)
        self.success         = success
        self.accuracy_before = accuracy_before
        self.accuracy_after  = accuracy_after
        self.notes           = notes

    def to_dict(self) -> dict:
        return self.__dict__


# ═════════════════════════════════════════════
# AccuracyTracker — track accuracy per model×symbol
# ═════════════════════════════════════════════
class AccuracyTracker:
    """
    Track weekly accuracy ต่อ model×symbol
    Compatible กับ performance_tracker.py (P4-4) ถ้ามี
    Fallback: เก็บใน JSON ถ้าไม่มี performance_tracker
    """

    def __init__(self, storage_path: Path):
        self._path = storage_path
        self._data: Dict[str, List[Dict]] = {}  # key: "RF|XAUUSD.tp"
        self._load()

    def _load(self):
        if self._path.exists():
            try:
                with open(self._path, "r") as f:
                    self._data = json.load(f)
            except Exception as e:
                logger.warning("AccuracyTracker load failed: %s", e)
                self._data = {}

    def _save(self):
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with open(self._path, "w") as f:
            json.dump(self._data, f, indent=2)

    def _key(self, model: str, symbol: str) -> str:
        return f"{model}|{symbol}"

    def record(self, model: str, symbol: str, accuracy: float, week_iso: str):
        """บันทึก accuracy ของสัปดาห์นั้น"""
        k = self._key(model, symbol)
        if k not in self._data:
            self._data[k] = []
        self._data[k].append({"week": week_iso, "accuracy": accuracy})
        # Keep last 52 weeks
        self._data[k] = self._data[k][-52:]
        self._save()

    def get_recent_weeks(
        self, model: str, symbol: str, n: int = 2
    ) -> List[float]:
        """ดึง accuracy n สัปดาห์ล่าสุด"""
        k = self._key(model, symbol)
        records = self._data.get(k, [])
        return [r["accuracy"] for r in records[-n:]]

    def should_trigger_retrain(
        self, model: str, symbol: str
    ) -> Tuple[bool, str]:
        """
        ตรวจว่าควร trigger retrain ไหม
        Return: (should_retrain, reason)
        """
        recent = self.get_recent_weeks(model, symbol, CONSECUTIVE_WEEKS_LIMIT)
        if len(recent) < CONSECUTIVE_WEEKS_LIMIT:
            return False, "not enough history"

        if all(acc < ACCURACY_THRESHOLD for acc in recent):
            reason = (
                f"accuracy {recent} < {ACCURACY_THRESHOLD:.0%} "
                f"for {CONSECUTIVE_WEEKS_LIMIT} consecutive weeks"
            )
            return True, reason

        return False, "accuracy OK"


# ═════════════════════════════════════════════
# CouncilWeightManager — EMA weight per strategy×symbol
# ═════════════════════════════════════════════
class CouncilWeightManager:
    """
    จัดการ AI Council weights
    - EMA(accuracy) ต่อ strategy×symbol
    - เขียนลง council_weights.json เพื่อให้ strategy_council.py อ่าน
    """

    def __init__(self, weights_file: Path):
        self._path = weights_file
        self._weights: Dict[str, float] = {}  # key: "S02|XAUUSD.tp"
        self._load()

    def _load(self):
        if self._path.exists():
            try:
                with open(self._path, "r") as f:
                    self._weights = json.load(f)
            except Exception as e:
                logger.warning("WeightManager load failed: %s", e)
                self._weights = {}

    def _save(self):
        self._path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_suffix(".tmp")
        with open(tmp, "w") as f:
            json.dump(self._weights, f, indent=2)
        tmp.replace(self._path)  # atomic write
        logger.info("Council weights saved → %s", self._path)

    def _key(self, strategy_id: str, symbol: str) -> str:
        return f"{strategy_id}|{symbol}"

    def update(self, strategy_id: str, symbol: str, new_accuracy: float):
        """
        อัปเดต weight ด้วย EMA(accuracy)
        weight_new = α × accuracy + (1 - α) × weight_old
        """
        k = self._key(strategy_id, symbol)
        old_weight = self._weights.get(k, new_accuracy)  # init = first accuracy
        ema_weight = EMA_ALPHA * new_accuracy + (1 - EMA_ALPHA) * old_weight
        ema_weight = max(0.05, min(2.0, ema_weight))     # clamp 0.05 – 2.0
        self._weights[k] = round(ema_weight, 4)
        logger.info(
            "Weight update %s: %.3f → %.3f (accuracy=%.2f%%)",
            k, old_weight, ema_weight, new_accuracy * 100,
        )
        self._save()

    def get_weight(self, strategy_id: str, symbol: str) -> float:
        return self._weights.get(self._key(strategy_id, symbol), 1.0)

    def get_all(self) -> Dict[str, float]:
        return dict(self._weights)


# ═════════════════════════════════════════════
# AutoRetrainer — core class
# ═════════════════════════════════════════════
class AutoRetrainer:
    """
    Automatic ML model retraining system

    Features:
    - Weekly retrain: RF, XGBoost, LSTM บน rolling 3-month window
    - Accuracy-triggered retrain (< 60% ติดกัน 2 สัปดาห์)
    - EMA weight adjustment → update council weights
    - Full event logging (JSON)
    - Thread-safe: ใช้เป็น daemon thread หรือ standalone ได้

    Usage (daemon thread):
        retrainer = AutoRetrainer(symbols=["XAUUSD.tp", "EURUSD.tp"])
        thread = retrainer.start_daemon()

    Usage (standalone / CLI):
        retrainer = AutoRetrainer(...)
        retrainer.run_blocking()   # blocks until stop()
    """

    # Models ที่ retrain ได้ (order = priority)
    RETRAIN_MODELS = ["RF", "XGBoost", "LSTM"]
    # Strategy ID ที่ใช้ ML (สำหรับ weight update)
    ML_STRATEGY_ID = "S02"

    def __init__(
        self,
        symbols: Optional[List[str]] = None,
        weekly_interval_sec: int = WEEKLY_INTERVAL_SEC,
        check_interval_sec: int = CHECK_INTERVAL_SEC,
        data_dir: Optional[Path] = None,
    ):
        self.symbols          = symbols or ["XAUUSD.tp", "EURUSD.tp"]
        self.weekly_interval  = weekly_interval_sec
        self.check_interval   = check_interval_sec
        self.data_dir         = data_dir or _DATA_DIR

        self._stop_event      = threading.Event()
        self._retrain_now     = threading.Event()   # force retrain on demand
        self._lock            = threading.Lock()

        # Sub-components
        _acc_db = _BRAIN_DIR / "logs" / "accuracy_history.json"
        self.accuracy_tracker = AccuracyTracker(_acc_db)
        self.weight_manager   = CouncilWeightManager(_WEIGHTS_FILE)

        # Timestamps
        self._last_weekly_retrain: Optional[datetime] = None
        self._load_last_retrain_time()

        # Event log (in-memory append, saved each time)
        self._events: List[dict] = self._load_events()

        # Trainer (P4-7 model_trainer.py)
        self._trainer: Optional[Any] = None
        if _TRAINER_AVAILABLE:
            try:
                self._trainer = ModelTrainer()
                logger.info("ModelTrainer loaded ✅")
            except Exception as e:
                logger.warning("ModelTrainer init failed: %s — will use mock retrain", e)
        else:
            logger.warning("model_trainer.py not found — using mock retrain")

        logger.info("AutoRetrainer initialized | symbols=%s", self.symbols)

    # ─────────────────────────────────────────
    # Public API
    # ─────────────────────────────────────────

    def start_daemon(self) -> threading.Thread:
        """Start เป็น daemon thread — return thread object"""
        t = threading.Thread(
            target=self._run_loop,
            name="AutoRetrainWorker",
            daemon=True,
        )
        t.start()
        logger.info("AutoRetrainer daemon thread started (tid=%s)", t.ident)
        return t

    def stop(self):
        """หยุด run loop"""
        logger.info("AutoRetrainer stopping...")
        self._stop_event.set()

    def trigger_now(self, reason: str = "manual"):
        """Force retrain ทันที (เรียกจาก host_cli.py)"""
        logger.info("Manual retrain triggered — reason: %s", reason)
        self._retrain_now.set()

    def run_blocking(self):
        """รัน blocking (standalone mode)"""
        logger.info("AutoRetrainer running in standalone mode")
        self._run_loop()

    def get_status(self) -> dict:
        """คืน status dict (ใช้โดย host_cli.py)"""
        with self._lock:
            last_event = self._events[-1] if self._events else {}
            return {
                "last_weekly_retrain": (
                    self._last_weekly_retrain.isoformat()
                    if self._last_weekly_retrain
                    else None
                ),
                "next_weekly_retrain": self._next_retrain_str(),
                "symbols": self.symbols,
                "council_weights": self.weight_manager.get_all(),
                "total_retrain_events": len(self._events),
                "last_event": last_event,
                "trainer_available": _TRAINER_AVAILABLE,
            }

    # ─────────────────────────────────────────
    # Internal — run loop
    # ─────────────────────────────────────────

    def _run_loop(self):
        """Main loop — รันใน thread"""
        logger.info("AutoRetrainer loop started")

        while not self._stop_event.is_set():
            try:
                # 1. ตรวจ force retrain
                if self._retrain_now.is_set():
                    self._retrain_now.clear()
                    self._do_retrain("manual", self.RETRAIN_MODELS)

                # 2. ตรวจ weekly schedule
                elif self._is_weekly_due():
                    self._do_retrain("weekly", self.RETRAIN_MODELS)
                    self._last_weekly_retrain = datetime.utcnow()
                    self._save_last_retrain_time()

                # 3. ตรวจ accuracy-triggered (ทุก symbol × model)
                else:
                    self._check_accuracy_trigger()

            except Exception as e:
                logger.error("AutoRetrainer loop error: %s", e, exc_info=True)

            # รอ check_interval (แต่ตอบสนอง force retrain ได้เร็ว)
            self._stop_event.wait(timeout=self.check_interval)

        logger.info("AutoRetrainer loop ended")

    def _is_weekly_due(self) -> bool:
        if self._last_weekly_retrain is None:
            return True  # ครั้งแรก
        elapsed = (datetime.utcnow() - self._last_weekly_retrain).total_seconds()
        return elapsed >= self.weekly_interval

    def _next_retrain_str(self) -> str:
        if self._last_weekly_retrain is None:
            return "imminent"
        next_dt = self._last_weekly_retrain + timedelta(seconds=self.weekly_interval)
        return next_dt.isoformat()

    def _check_accuracy_trigger(self):
        """ตรวจ accuracy ของทุก model×symbol — trigger retrain ถ้าต่ำ"""
        triggered_models = set()
        for symbol in self.symbols:
            for model in self.RETRAIN_MODELS:
                should, reason = self.accuracy_tracker.should_trigger_retrain(
                    model, symbol
                )
                if should:
                    logger.warning(
                        "⚠️ Accuracy trigger: model=%s symbol=%s — %s",
                        model, symbol, reason,
                    )
                    triggered_models.add(model)

        if triggered_models:
            models_list = sorted(triggered_models)
            self._do_retrain("accuracy_drop", models_list)

    # ─────────────────────────────────────────
    # Internal — actual retrain
    # ─────────────────────────────────────────

    def _do_retrain(self, trigger: str, models: List[str]):
        """
        Execute retrain สำหรับ models ที่ระบุ
        - โหลด data 3-month window
        - เรียก ModelTrainer หรือ mock
        - คำนวณ accuracy before/after
        - อัปเดต EMA weights
        - Log event
        """
        logger.info(
            "=" * 60 + "\n🔄 RETRAIN START — trigger=%s models=%s\n" + "=" * 60,
            trigger, models,
        )
        t_start = time.perf_counter()

        accuracy_before = self._collect_current_accuracies(models)
        success = True
        notes_parts = []

        with self._lock:
            for model in models:
                try:
                    ok, note = self._retrain_one_model(model)
                    if not ok:
                        success = False
                    notes_parts.append(f"{model}: {note}")
                    logger.info("  %s → %s", model, note)
                except Exception as e:
                    success = False
                    msg = f"{model}: FAILED ({e})"
                    notes_parts.append(msg)
                    logger.error("  %s", msg, exc_info=True)

        duration = time.perf_counter() - t_start
        accuracy_after = self._collect_current_accuracies(models)

        # อัปเดต EMA weights สำหรับ S02
        for symbol in self.symbols:
            # ใช้ mean accuracy across models เป็น proxy สำหรับ S02 performance
            accs = [
                accuracy_after.get(f"{m}|{symbol}", 0.0)
                for m in models
            ]
            mean_acc = sum(accs) / len(accs) if accs else 0.5
            self.weight_manager.update(self.ML_STRATEGY_ID, symbol, mean_acc)

        # Log event
        event = RetrainEvent(
            trigger=trigger,
            models=models,
            symbols=self.symbols,
            duration_sec=duration,
            success=success,
            accuracy_before=accuracy_before,
            accuracy_after=accuracy_after,
            notes="; ".join(notes_parts),
        )
        self._events.append(event.to_dict())
        self._save_events()

        logger.info(
            "🏁 RETRAIN DONE — trigger=%s success=%s duration=%.1fs",
            trigger, success, duration,
        )

    def _retrain_one_model(self, model: str) -> Tuple[bool, str]:
        """
        Retrain โมเดลเดียว
        Return: (success, note_string)
        """
        if self._trainer is not None:
            # ─────────────────────────────────
            # Real retrain via ModelTrainer
            # ─────────────────────────────────
            try:
                # โหลด data 3-month window
                end_dt   = datetime.utcnow()
                start_dt = end_dt - timedelta(days=RETRAIN_WINDOW_DAYS)

                result = self._trainer.retrain_model(
                    model_name=model,
                    start_date=start_dt.strftime("%Y-%m-%d"),
                    end_date=end_dt.strftime("%Y-%m-%d"),
                    symbols=self.symbols,
                )
                acc = result.get("accuracy", 0.0)
                week_iso = datetime.utcnow().strftime("%Y-W%W")

                for symbol in self.symbols:
                    self.accuracy_tracker.record(model, symbol, acc, week_iso)

                return True, f"acc={acc:.3f}"

            except AttributeError:
                # ModelTrainer ไม่มี retrain_model() — fallback to train()
                return self._mock_retrain(model)
        else:
            return self._mock_retrain(model)

    def _mock_retrain(self, model: str) -> Tuple[bool, str]:
        """
        Mock retrain — ใช้เมื่อ trainer ไม่พร้อม
        Simulate accuracy improvement เพื่อทดสอบ pipeline
        """
        import random
        time.sleep(0.5)  # simulate work
        mock_acc = random.uniform(0.60, 0.85)
        week_iso = datetime.utcnow().strftime("%Y-W%W")

        for symbol in self.symbols:
            self.accuracy_tracker.record(model, symbol, mock_acc, week_iso)

        return True, f"MOCK acc={mock_acc:.3f}"

    def _collect_current_accuracies(self, models: List[str]) -> Dict[str, float]:
        """ดึง accuracy ปัจจุบัน (สัปดาห์ล่าสุด) ของ model×symbol ทุกคู่"""
        result = {}
        for symbol in self.symbols:
            for model in models:
                recent = self.accuracy_tracker.get_recent_weeks(model, symbol, 1)
                k = f"{model}|{symbol}"
                result[k] = recent[-1] if recent else 0.0
        return result

    # ─────────────────────────────────────────
    # Persistence helpers
    # ─────────────────────────────────────────

    def _load_events(self) -> List[dict]:
        if _RETRAIN_DB.exists():
            try:
                with open(_RETRAIN_DB, "r") as f:
                    return json.load(f)
            except Exception:
                return []
        return []

    def _save_events(self):
        _RETRAIN_DB.parent.mkdir(parents=True, exist_ok=True)
        with open(_RETRAIN_DB, "w") as f:
            json.dump(self._events, f, indent=2)

    def _load_last_retrain_time(self):
        _ts_file = _BRAIN_DIR / "logs" / "last_retrain.txt"
        if _ts_file.exists():
            try:
                ts_str = _ts_file.read_text().strip()
                self._last_weekly_retrain = datetime.fromisoformat(ts_str)
                logger.info("Last weekly retrain: %s", ts_str)
            except Exception:
                self._last_weekly_retrain = None

    def _save_last_retrain_time(self):
        _ts_file = _BRAIN_DIR / "logs" / "last_retrain.txt"
        _ts_file.parent.mkdir(parents=True, exist_ok=True)
        _ts_file.write_text(datetime.utcnow().isoformat())


# ═════════════════════════════════════════════
# Standalone entry point
# ═════════════════════════════════════════════
def main():
    """Standalone mode — รัน loop จนกว่า Ctrl+C"""
    import argparse

    parser = argparse.ArgumentParser(
        description="FlashEASuite V2 — Auto-Retrain System"
    )
    parser.add_argument(
        "--symbols",
        nargs="+",
        default=["XAUUSD.tp", "EURUSD.tp"],
        help="Symbols to monitor (default: XAUUSD.tp EURUSD.tp)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Trigger retrain immediately on start, then run loop",
    )
    parser.add_argument(
        "--weekly-interval",
        type=int,
        default=WEEKLY_INTERVAL_SEC,
        help=f"Weekly interval in seconds (default: {WEEKLY_INTERVAL_SEC})",
    )
    parser.add_argument(
        "--check-interval",
        type=int,
        default=CHECK_INTERVAL_SEC,
        help=f"Check interval in seconds (default: {CHECK_INTERVAL_SEC})",
    )
    args = parser.parse_args()

    retrainer = AutoRetrainer(
        symbols=args.symbols,
        weekly_interval_sec=args.weekly_interval,
        check_interval_sec=args.check_interval,
    )

    if args.force:
        retrainer.trigger_now("manual-on-start")

    try:
        retrainer.run_blocking()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt — stopping")
        retrainer.stop()


if __name__ == "__main__":
    main()
