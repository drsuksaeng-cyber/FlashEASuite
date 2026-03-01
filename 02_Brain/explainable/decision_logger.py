"""
decision_logger.py
FlashEASuite V2 — P4-6: Decision Logger (Destination 2)
========================================================
บันทึก reasoning chain ลง JSON audit trail

File naming: 02_Brain/logs/decisions/{YYYYMMDD}_{HH}.json
Rotation: เก็บ 30 วัน → ลบไฟล์เก่าอัตโนมัติ

เพิ่มเติม: รองรับ Destination 3 (CSV export)
  - generate_daily_csv(date) → 02_Brain/logs/reports/{date}_decisions.csv

Save: 02_Brain/explainable/decision_logger.py
"""

import csv
import json
import logging
import os
import threading
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

DEFAULT_LOG_DIR    = Path("02_Brain/logs/decisions")
DEFAULT_REPORT_DIR = Path("02_Brain/logs/reports")
ROTATION_DAYS      = 30          # เก็บ log 30 วัน
MAX_RECORDS_PER_FILE = 10000     # safety cap per hourly file


# ─────────────────────────────────────────────
# DecisionLogger
# ─────────────────────────────────────────────

class DecisionLogger:
    """
    Destination 2: JSON audit trail
    Destination 3: CSV performance report

    JSON structure per file:
    {
      "date": "2026-02-22",
      "hour": "06",
      "records": [
        {full ReasoningChain.to_dict()}, ...
      ]
    }

    File per hour → max 24 files/day → easy to grep/analyze
    """

    def __init__(
        self,
        log_dir: Optional[Path] = None,
        report_dir: Optional[Path] = None,
        rotation_days: int = ROTATION_DAYS,
    ):
        self._log_dir    = Path(log_dir    or DEFAULT_LOG_DIR)
        self._report_dir = Path(report_dir or DEFAULT_REPORT_DIR)
        self._rotation_days = rotation_days
        self._lock = threading.Lock()

        # In-memory buffer (flush to disk periodically)
        self._buffer: list[dict] = []
        self._buffer_limit = 50   # flush ทุก 50 records

        # สร้าง directories
        self._log_dir.mkdir(parents=True, exist_ok=True)
        self._report_dir.mkdir(parents=True, exist_ok=True)

        logger.info(
            f"[Logger] DecisionLogger initialized | "
            f"log_dir={self._log_dir} | rotation={rotation_days}d"
        )

    # ─────────────────────────────────────────
    # Core logging
    # ─────────────────────────────────────────

    def log(self, reasoning_dict: dict) -> bool:
        """
        บันทึก 1 reasoning chain

        Args:
            reasoning_dict: ReasoningChain.to_dict() output

        Returns:
            True ถ้าสำเร็จ
        """
        with self._lock:
            self._buffer.append(reasoning_dict)
            should_flush = len(self._buffer) >= self._buffer_limit

        if should_flush:
            return self.flush()
        return True

    def log_chain(self, chain) -> bool:
        """
        Log จาก ReasoningChain object โดยตรง
        (shortcut — ไม่ต้องเรียก .to_dict() เอง)
        """
        try:
            d = chain.to_dict() if hasattr(chain, "to_dict") else dict(chain)
            return self.log(d)
        except Exception as e:
            logger.error(f"[Logger] log_chain failed: {e}")
            return False

    def flush(self) -> bool:
        """
        Flush buffer ลง disk
        เรียกอัตโนมัติเมื่อ buffer เต็ม หรือเรียกเองทุก N นาที
        """
        with self._lock:
            if not self._buffer:
                return True
            records = self._buffer.copy()
            self._buffer.clear()

        try:
            file_path = self._get_log_file_path()
            self._append_to_file(file_path, records)
            logger.debug(
                f"[Logger] Flushed {len(records)} records → {file_path.name}"
            )
            return True
        except Exception as e:
            logger.error(f"[Logger] Flush failed: {e}")
            # คืน records กลับ buffer
            with self._lock:
                self._buffer = records + self._buffer
            return False

    # ─────────────────────────────────────────
    # File management
    # ─────────────────────────────────────────

    def _get_log_file_path(self) -> Path:
        """คืน path ของ hourly log file ปัจจุบัน"""
        now = datetime.now(timezone.utc)
        filename = f"{now.strftime('%Y%m%d')}_{now.strftime('%H')}.json"
        return self._log_dir / filename

    def _append_to_file(self, file_path: Path, records: list[dict]) -> None:
        """
        Append records ลง JSON file แบบ safe (read → merge → write)
        """
        # โหลดข้อมูลเดิม (ถ้ามี)
        existing = {"date": "", "hour": "", "records": []}
        if file_path.exists():
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    existing = json.load(f)
            except Exception:
                pass   # ถ้าอ่านไม่ได้ → เริ่มใหม่

        now = datetime.now(timezone.utc)
        existing["date"] = now.strftime("%Y-%m-%d")
        existing["hour"] = now.strftime("%H")
        existing["updated_at"] = now.isoformat()

        # Append records (ป้องกัน cap)
        current_records = existing.get("records", [])
        new_total = current_records + records
        if len(new_total) > MAX_RECORDS_PER_FILE:
            new_total = new_total[-MAX_RECORDS_PER_FILE:]
        existing["records"] = new_total
        existing["count"] = len(new_total)

        # Atomic write
        tmp = file_path.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(existing, f, ensure_ascii=False, indent=2)
        tmp.replace(file_path)

    def rotate(self) -> int:
        """
        ลบ log files เก่ากว่า rotation_days
        เรียกวันละครั้ง (หรือ startup)

        Returns:
            จำนวนไฟล์ที่ลบ
        """
        cutoff = datetime.now(timezone.utc) - timedelta(days=self._rotation_days)
        cutoff_str = cutoff.strftime("%Y%m%d")
        removed = 0

        for f in self._log_dir.glob("*.json"):
            try:
                # filename format: YYYYMMDD_HH.json
                date_part = f.stem.split("_")[0]
                if date_part < cutoff_str:
                    f.unlink()
                    removed += 1
                    logger.debug(f"[Logger] Rotated: {f.name}")
            except Exception:
                pass

        if removed:
            logger.info(f"[Logger] Rotated {removed} old log files (>{self._rotation_days}d)")
        return removed

    def list_log_files(self, last_n_days: int = 7) -> list[Path]:
        """คืน list ของ log files ใน N วันล่าสุด"""
        cutoff = datetime.now(timezone.utc) - timedelta(days=last_n_days)
        cutoff_str = cutoff.strftime("%Y%m%d")
        files = sorted(
            f for f in self._log_dir.glob("*.json")
            if f.stem.split("_")[0] >= cutoff_str
        )
        return files

    # ─────────────────────────────────────────
    # Destination 3: CSV report
    # ─────────────────────────────────────────

    def generate_daily_csv(
        self,
        date: Optional[str] = None,
    ) -> Optional[Path]:
        """
        สร้าง CSV report จาก JSON logs ของวันนั้น
        Destination 3: Performance Report

        Args:
            date: "YYYY-MM-DD" หรือ None (= วันนี้)

        Returns:
            Path ของ CSV file หรือ None ถ้าไม่มีข้อมูล
        """
        # flush buffer ก่อน
        self.flush()

        target_date = date or datetime.now(timezone.utc).strftime("%Y%m%d")
        target_date_fmt = target_date.replace("-", "")

        # รวม records จากทุก hourly files ของวันนั้น
        all_records: list[dict] = []
        for f in self._log_dir.glob(f"{target_date_fmt}_*.json"):
            try:
                with open(f, "r", encoding="utf-8") as fp:
                    data = json.load(fp)
                all_records.extend(data.get("records", []))
            except Exception as e:
                logger.warning(f"[Logger] Cannot read {f.name}: {e}")

        if not all_records:
            logger.info(f"[Logger] No records for {target_date_fmt}")
            return None

        # สร้าง CSV
        csv_path = self._report_dir / f"{target_date_fmt}_decisions.csv"
        fieldnames = [
            "timestamp", "cycle_id", "symbol",
            "regime_type", "regime_confidence",
            "selected_count", "selected_strategies",
            "mm_method", "risk_multiplier",
            "eligible_votes", "total_votes",
            "summary_en",
        ]

        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
            writer.writeheader()

            for rec in all_records:
                selected = rec.get("selected", [])
                vote_sum = rec.get("vote_summary", {})

                row = {
                    "timestamp":           rec.get("timestamp", ""),
                    "cycle_id":            rec.get("cycle_id", ""),
                    "symbol":              rec.get("symbol", ""),
                    "regime_type":         rec.get("regime", {}).get("type", ""),
                    "regime_confidence":   rec.get("regime", {}).get("confidence", 0),
                    "selected_count":      len(selected),
                    "selected_strategies": "|".join(
                        s.get("strategy", "") for s in selected
                    ),
                    "mm_method":           rec.get("mm", {}).get("method", ""),
                    "risk_multiplier":     rec.get("risk", {}).get("multiplier", 1.0),
                    "eligible_votes":      vote_sum.get("eligible", 0),
                    "total_votes":         vote_sum.get("total", 0),
                    "summary_en":          rec.get("summary_en", "")[:120],
                }
                writer.writerow(row)

        logger.info(
            f"[Logger] CSV generated: {csv_path.name} "
            f"({len(all_records)} records)"
        )
        return csv_path

    def generate_weekly_csv(self) -> Optional[Path]:
        """สร้าง weekly summary CSV (7 วันล่าสุด)"""
        self.flush()

        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(days=7)
        cutoff_str = cutoff.strftime("%Y%m%d")

        all_records: list[dict] = []
        for f in self._log_dir.glob("*.json"):
            if f.stem.split("_")[0] >= cutoff_str:
                try:
                    with open(f, "r", encoding="utf-8") as fp:
                        data = json.load(fp)
                    all_records.extend(data.get("records", []))
                except Exception:
                    pass

        if not all_records:
            return None

        csv_path = self._report_dir / f"weekly_{now.strftime('%Y%m%d')}.csv"

        # Aggregate per symbol per strategy
        agg: dict[tuple, dict] = {}
        for rec in all_records:
            sym = rec.get("symbol", "")
            for sel in rec.get("selected", []):
                strat = sel.get("strategy", "")
                key = (sym, strat)
                if key not in agg:
                    agg[key] = {"count": 0, "total_score": 0.0, "mm_counts": {}}
                agg[key]["count"] += 1
                agg[key]["total_score"] += sel.get("score", 0.0)
                mm = rec.get("mm", {}).get("method", "")
                agg[key]["mm_counts"][mm] = agg[key]["mm_counts"].get(mm, 0) + 1

        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=["symbol", "strategy", "selected_count", "avg_score", "top_mm"],
                extrasaction="ignore",
            )
            writer.writeheader()
            for (sym, strat), data in sorted(agg.items()):
                top_mm = max(data["mm_counts"], key=data["mm_counts"].get, default="")
                writer.writerow({
                    "symbol": sym,
                    "strategy": strat,
                    "selected_count": data["count"],
                    "avg_score": round(data["total_score"] / data["count"], 4),
                    "top_mm": top_mm,
                })

        logger.info(f"[Logger] Weekly CSV: {csv_path.name} ({len(agg)} rows)")
        return csv_path

    # ─────────────────────────────────────────
    # P9-1 additions
    # ─────────────────────────────────────────

    def log_decision(self, decision: dict) -> bool:
        """
        P9-1: บันทึก 1 AI Council decision (wrapper สำหรับ P9 API)

        Args:
            decision: dict ที่มีฟิลด์ใดๆ รวมถึง:
                timestamp, symbol, regime, strategy_scores,
                final_decision, confidence, reasoning

        Returns:
            True ถ้าสำเร็จ
        """
        # Normalize timestamp ถ้ายังไม่มี
        entry = dict(decision)
        if "timestamp" not in entry or not entry.get("timestamp"):
            entry["timestamp"] = datetime.now(timezone.utc).isoformat()
        elif isinstance(entry.get("timestamp"), (int, float)):
            entry["timestamp"] = datetime.fromtimestamp(
                entry["timestamp"], tz=timezone.utc
            ).isoformat()
        return self.log(entry)

    def get_daily_summary(
        self,
        date: Optional[str] = None,
    ) -> dict:
        """
        P9-1: สรุปผล decisions ของวันที่ระบุ

        Args:
            date: "YYYY-MM-DD" หรือ None (= วันนี้)

        Returns:
            {
              "date": "2026-02-25",
              "total_decisions": 142,
              "by_symbol": {"XAUUSD": 38, ...},
              "by_regime": {"RANGING": 65, ...},
              "top_strategy_ids": {1: 55, 7: 40, ...},
              "avg_confidence": 0.701,
              "files_read": ["20260225_09.json", ...]
            }
        """
        self.flush()

        target_date_fmt = (date or datetime.now(timezone.utc).strftime("%Y-%m-%d")).replace("-", "")
        files = sorted(self._log_dir.glob(f"{target_date_fmt}_*.json"))

        all_records: list[dict] = []
        for f in files:
            try:
                with open(f, "r", encoding="utf-8") as fp:
                    data = json.load(fp)
                all_records.extend(data.get("records", []))
            except Exception:
                pass

        by_symbol: dict[str, int] = {}
        by_regime: dict[str, int] = {}
        top_strat: dict[int, int] = {}
        conf_sum = 0.0
        conf_cnt = 0

        for e in all_records:
            sym = e.get("symbol", "UNKNOWN")
            by_symbol[sym] = by_symbol.get(sym, 0) + 1

            # รองรับทั้ง "regime" string และ "regime": {"type": ...}
            reg_raw = e.get("regime", "UNKNOWN")
            reg = reg_raw.get("type", "UNKNOWN") if isinstance(reg_raw, dict) else reg_raw
            by_regime[reg] = by_regime.get(reg, 0) + 1

            # รองรับทั้ง final_decision dict และ selected list
            fd = e.get("final_decision")
            if fd and isinstance(fd, dict):
                sid = fd.get("strategy_id")
                if sid is not None:
                    top_strat[sid] = top_strat.get(sid, 0) + 1
            else:
                for sel in (e.get("selected") or []):
                    sid = sel.get("strategy_id") or sel.get("strategy")
                    if sid is not None:
                        try:
                            top_strat[int(str(sid).lstrip("S"))] = top_strat.get(int(str(sid).lstrip("S")), 0) + 1
                        except (ValueError, AttributeError):
                            pass
                    break   # เฉพาะ rank=1

            conf = e.get("confidence")
            if isinstance(conf, (int, float)):
                conf_sum += float(conf)
                conf_cnt += 1

        return {
            "date":             target_date_fmt[:4] + "-" + target_date_fmt[4:6] + "-" + target_date_fmt[6:],
            "total_decisions":  len(all_records),
            "by_symbol":        dict(sorted(by_symbol.items(), key=lambda x: -x[1])),
            "by_regime":        by_regime,
            "top_strategy_ids": dict(sorted(top_strat.items(), key=lambda x: -x[1])),
            "avg_confidence":   round(conf_sum / conf_cnt, 4) if conf_cnt else 0.0,
            "files_read":       [f.name for f in files],
        }

    def get_stats(self) -> dict:
        """สถิติ logger"""
        files = list(self._log_dir.glob("*.json"))
        total_records = 0
        for f in files:
            try:
                with open(f, "r", encoding="utf-8") as fp:
                    total_records += json.load(fp).get("count", 0)
            except Exception:
                pass
        return {
            "log_files": len(files),
            "total_records": total_records,
            "buffer_pending": len(self._buffer),
            "log_dir": str(self._log_dir),
        }


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
    print("FlashEASuite V2 — Decision Logger Test")
    print("=" * 60)

    with tempfile.TemporaryDirectory() as tmpdir:
        log_dir    = Path(tmpdir) / "logs" / "decisions"
        report_dir = Path(tmpdir) / "logs" / "reports"

        dec_logger = DecisionLogger(log_dir=log_dir, report_dir=report_dir, rotation_days=30)

        # Mock reasoning records
        def make_record(symbol, sid, score, regime="RANGING"):
            return {
                "symbol": symbol,
                "cycle_id": datetime.now(timezone.utc).strftime("%Y%m%d_%H%M"),
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "regime": {"type": regime, "method": "3-layer", "confidence": 0.80, "detail": ""},
                "votes": [],
                "vote_summary": {"total": 16, "eligible": 7, "selected": 1},
                "selected": [{"rank": 1, "strategy": f"S{sid:02d}", "name": "Grid",
                              "score": score, "allocation_pct": 100.0}],
                "mm": {"method": "MM03", "name": "ATR-Based", "reasoning": "default"},
                "risk": {"multiplier": 1.0, "reasoning": "DD normal"},
                "summary_th": f"[TEST] {symbol} S{sid:02d} score={score:.2f}",
                "summary_en": f"[TEST] {symbol} S{sid:02d} score={score:.2f}",
            }

        # ── Test 1: log records ───────────────────────────────────────
        print("\n── Test 1: Log 20 records ──")
        import random
        rng = random.Random(42)
        for i in range(20):
            sym = rng.choice(["XAUUSD", "EURUSD", "GBPUSD"])
            sid = rng.choice([1, 6, 15, 16])
            rec = make_record(sym, sid, rng.uniform(0.6, 0.9))
            ok = dec_logger.log(rec)
            assert ok

        # Force flush
        dec_logger.flush()

        files = list(log_dir.glob("*.json"))
        print(f"  Log files created: {len(files)}")
        assert len(files) >= 1

        # ── Test 2: Verify file content ───────────────────────────────
        print("\n── Test 2: Verify JSON file ──")
        with open(files[0], "r", encoding="utf-8") as f:
            data = json.load(f)
        print(f"  File: {files[0].name}")
        print(f"  Records: {data['count']}")
        print(f"  First record symbol: {data['records'][0]['symbol']}")
        assert data["count"] >= 1
        assert "records" in data
        print("  Content valid: ✅")

        # ── Test 3: CSV daily report ──────────────────────────────────
        print("\n── Test 3: Daily CSV (Destination 3) ──")
        csv_path = dec_logger.generate_daily_csv()
        if csv_path and csv_path.exists():
            with open(csv_path, "r", encoding="utf-8") as f:
                rows = list(csv.reader(f))
            print(f"  CSV: {csv_path.name}")
            print(f"  Rows (incl header): {len(rows)}")
            print(f"  Columns: {rows[0]}")
            assert len(rows) > 1
            print("  Daily CSV: ✅")
        else:
            print("  Daily CSV: ❌ (not generated)")

        # ── Test 4: Weekly CSV ────────────────────────────────────────
        print("\n── Test 4: Weekly CSV ──")
        weekly = dec_logger.generate_weekly_csv()
        if weekly and weekly.exists():
            with open(weekly, "r", encoding="utf-8") as f:
                wrows = list(csv.reader(f))
            print(f"  Weekly CSV: {weekly.name} | {len(wrows)} rows")
            print("  Weekly CSV: ✅")
        else:
            print("  Weekly CSV: ❌")

        # ── Test 5: Rotation ──────────────────────────────────────────
        print("\n── Test 5: Rotation (simulate old files) ──")
        # สร้างไฟล์เก่า
        old_date = (datetime.now(timezone.utc) - timedelta(days=35)).strftime("%Y%m%d")
        old_file = log_dir / f"{old_date}_12.json"
        with open(old_file, "w") as f:
            json.dump({"date": old_date, "records": [], "count": 0}, f)

        removed = dec_logger.rotate()
        print(f"  Removed: {removed} files")
        assert removed >= 1
        assert not old_file.exists()
        print("  Rotation: ✅")

        # ── Test 6: Stats ─────────────────────────────────────────────
        print("\n── Test 6: Stats ──")
        stats = dec_logger.get_stats()
        for k, v in stats.items():
            print(f"  {k}: {v}")

    print("\n✅ All tests passed!")
