"""
╔══════════════════════════════════════════════════════════════════════════════╗
║  FlashEASuite V2 — csv_reporter.py                                          ║
║  Phase 7 Chat P7-1: CSV Reports (Daily / Weekly / Monthly)                  ║
║  Save at: 02_Brain/reports/csv_reporter.py                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

ภาพรวม:
  - อ่านข้อมูลจาก 02_Brain/logs/decisions/{date}_{HH}.json (decision_logger.py)
  - อ่าน trade results จาก 02_Brain/logs/trades_{date}.json (execution_listener.py)
  - สร้าง CSV รายวัน / สัปดาห์ / เดือน ใน 02_Brain/reports/
  - วิเคราะห์ strategy attribution, drawdown, reasoning accuracy

Columns per trade:
  timestamp, symbol, strategy, mm_method, direction, lot,
  entry, exit, pnl, confidence, regime, reasoning_correct

L-PY-01: sys.path trick สำหรับ standalone run
L-PY-07: soft import — ทำงานได้แม้ไม่มี pandas
L-PY-08: performance warning pattern
"""

# ──────────────────────────────────────────────────────────────────────────────
# PATH SETUP (L-PY-01: standalone run support)
# ──────────────────────────────────────────────────────────────────────────────
import sys
import os
from pathlib import Path

_REPORTS_DIR = Path(__file__).parent            # 02_Brain/reports/
_BRAIN_DIR   = _REPORTS_DIR.parent              # 02_Brain/
_LOGS_DIR    = _BRAIN_DIR / "logs"
_DECISIONS_DIR = _LOGS_DIR / "decisions"

# เพิ่ม 02_Brain เข้า sys.path เพื่อ import core modules
if str(_BRAIN_DIR) not in sys.path:
    sys.path.insert(0, str(_BRAIN_DIR))

# ──────────────────────────────────────────────────────────────────────────────
# STANDARD IMPORTS
# ──────────────────────────────────────────────────────────────────────────────
import csv
import json
import logging
import time
import threading
from datetime import datetime, date, timedelta
from collections import defaultdict
from typing import List, Dict, Optional, Tuple, Any

# ──────────────────────────────────────────────────────────────────────────────
# SOFT IMPORTS (L-PY-07)
# ──────────────────────────────────────────────────────────────────────────────
try:
    import pandas as pd
    _PANDAS_AVAILABLE = True
except ImportError:
    _PANDAS_AVAILABLE = False

try:
    import matplotlib
    matplotlib.use("Agg")           # non-interactive backend
    import matplotlib.pyplot as plt
    _MATPLOTLIB_AVAILABLE = True
except ImportError:
    _MATPLOTLIB_AVAILABLE = False

# ──────────────────────────────────────────────────────────────────────────────
# LOGGER
# ──────────────────────────────────────────────────────────────────────────────
logger = logging.getLogger("csv_reporter")
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter(
        "%(asctime)s [%(levelname)s] csv_reporter: %(message)s",
        datefmt="%H:%M:%S"
    ))
    logger.addHandler(_handler)
    logger.setLevel(logging.INFO)

# ──────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ──────────────────────────────────────────────────────────────────────────────
TRADE_COLUMNS = [
    "timestamp", "symbol", "strategy", "mm_method", "direction",
    "lot", "entry", "exit", "pnl", "confidence", "regime", "reasoning_correct"
]

# ชื่อ strategy ทั้ง 16 ตัว
STRATEGY_NAMES = {
    "S01": "StatArb",       "S02": "MLEnsemble",    "S03": "SMC",
    "S04": "MarketProfile", "S05": "SupplyDemand",  "S06": "KAMA",
    "S07": "MeanReversion", "S08": "Intermarket",   "S09": "SessionBreakout",
    "S10": "Turtle",        "S11": "Ichimoku",      "S12": "PriceAction",
    "S13": "FibStoch",      "S14": "BBSqueeze",     "S15": "Grid",
    "S16": "Spike",
}

_PERF_WARN_MS = 500     # warn ถ้า load ช้า >500ms


# ══════════════════════════════════════════════════════════════════════════════
# TRADE RECORD — ข้อมูลเทรด 1 คำสั่ง
# ══════════════════════════════════════════════════════════════════════════════
class TradeRecord:
    """
    ข้อมูลเทรด 1 คำสั่ง — ตรงกับ TRADE_COLUMNS ทุกฟิลด์
    """
    __slots__ = TRADE_COLUMNS

    def __init__(self,
                 timestamp: str,
                 symbol: str,
                 strategy: str,
                 mm_method: str,
                 direction: str,
                 lot: float,
                 entry: float,
                 exit: float,
                 pnl: float,
                 confidence: float,
                 regime: str,
                 reasoning_correct: bool):
        self.timestamp        = timestamp
        self.symbol           = symbol
        self.strategy         = strategy
        self.mm_method        = mm_method
        self.direction        = direction
        self.lot              = lot
        self.entry            = entry
        self.exit             = exit
        self.pnl              = pnl
        self.confidence       = confidence
        self.regime           = regime
        self.reasoning_correct = reasoning_correct

    def to_dict(self) -> Dict:
        return {col: getattr(self, col) for col in TRADE_COLUMNS}

    def to_row(self) -> List:
        return [getattr(self, col) for col in TRADE_COLUMNS]


# ══════════════════════════════════════════════════════════════════════════════
# DATA LOADER — โหลดข้อมูลจาก JSON logs
# ══════════════════════════════════════════════════════════════════════════════
class TradeDataLoader:
    """
    โหลด trade records จาก:
    1. 02_Brain/logs/trades_{date}.json   ← execution_listener เขียน
    2. 02_Brain/logs/decisions/{date}_{HH}.json ← decision_logger เขียน (fallback)
    """

    def __init__(self, logs_dir: Path = _LOGS_DIR):
        self.logs_dir      = logs_dir
        self.decisions_dir = logs_dir / "decisions"
        self.trades_dir    = logs_dir                   # trades_{date}.json อยู่ที่ root logs

    # ──────────────────────────────────────────────────────────────────────────
    def load_date(self, target_date: date) -> List[TradeRecord]:
        """โหลด trade records ของวันที่ระบุ"""
        t0 = time.perf_counter()
        records: List[TradeRecord] = []

        # 1. โหลดจาก trades log ก่อน (primary)
        records = self._load_trades_json(target_date)

        # 2. ถ้าไม่มี trade log → fallback อ่านจาก decision logs
        if not records:
            logger.info("ไม่พบ trades_%s.json — fallback จาก decision logs", target_date)
            records = self._load_from_decisions(target_date)

        elapsed_ms = (time.perf_counter() - t0) * 1000
        if elapsed_ms >= _PERF_WARN_MS:
            logger.warning("⚠️ PERF: load_date(%s) ใช้เวลา %.0fms", target_date, elapsed_ms)

        logger.info("โหลด %d records สำหรับวันที่ %s (%.0fms)", len(records), target_date, elapsed_ms)
        return records

    def load_date_range(self, start: date, end: date) -> List[TradeRecord]:
        """โหลด trade records ในช่วงวันที่ start..end (inclusive)"""
        all_records: List[TradeRecord] = []
        current = start
        while current <= end:
            all_records.extend(self.load_date(current))
            current += timedelta(days=1)
        return all_records

    # ──────────────────────────────────────────────────────────────────────────
    def _load_trades_json(self, target_date: date) -> List[TradeRecord]:
        """อ่านจาก logs/trades_{YYYYMMDD}.json"""
        path = self.trades_dir / f"trades_{target_date.strftime('%Y%m%d')}.json"
        if not path.exists():
            return []
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return [self._parse_trade_entry(e) for e in data if e]
        except Exception as ex:
            logger.warning("อ่าน %s ไม่ได้: %s", path.name, ex)
            return []

    def _load_from_decisions(self, target_date: date) -> List[TradeRecord]:
        """อ่านจาก logs/decisions/{YYYYMMDD}_{HH}.json — สร้าง trade records จาก decisions"""
        if not self.decisions_dir.exists():
            return []

        date_str = target_date.strftime("%Y%m%d")
        records: List[TradeRecord] = []

        # วน loop 24 ชั่วโมง
        for hour in range(24):
            path = self.decisions_dir / f"{date_str}_{hour:02d}.json"
            if not path.exists():
                continue
            try:
                with open(path, "r", encoding="utf-8") as f:
                    decisions = json.load(f)
                if isinstance(decisions, list):
                    for d in decisions:
                        recs = self._decision_to_trade_records(d)
                        records.extend(recs)
                elif isinstance(decisions, dict):
                    records.extend(self._decision_to_trade_records(decisions))
            except Exception as ex:
                logger.warning("อ่าน %s ไม่ได้: %s", path.name, ex)

        return records

    # ──────────────────────────────────────────────────────────────────────────
    def _parse_trade_entry(self, entry: Dict) -> Optional[TradeRecord]:
        """แปลง dict จาก trades_{date}.json → TradeRecord"""
        try:
            return TradeRecord(
                timestamp        = entry.get("timestamp", ""),
                symbol           = entry.get("symbol", "UNKNOWN"),
                strategy         = entry.get("strategy", "UNKNOWN"),
                mm_method        = entry.get("mm_method", "UNKNOWN"),
                direction        = entry.get("direction", "UNKNOWN"),
                lot              = float(entry.get("lot", 0.0)),
                entry            = float(entry.get("entry", 0.0)),
                exit             = float(entry.get("exit", 0.0)),
                pnl              = float(entry.get("pnl", 0.0)),
                confidence       = float(entry.get("confidence", 0.0)),
                regime           = entry.get("regime", "UNKNOWN"),
                reasoning_correct = bool(entry.get("reasoning_correct", False)),
            )
        except Exception as ex:
            logger.debug("parse_trade_entry ผิดพลาด: %s", ex)
            return None

    def _decision_to_trade_records(self, decision: Dict) -> List[TradeRecord]:
        """
        แปลง decision JSON (reasoning_builder format) → TradeRecord list
        ใช้ใน fallback mode — ไม่มีข้อมูล entry/exit/lot จริง
        """
        records = []
        regime  = decision.get("regime", {}).get("type", "UNKNOWN")
        ts      = decision.get("timestamp", datetime.now().isoformat())

        for sel in decision.get("selected", []):
            strat_id   = sel.get("strategy", "UNKNOWN")
            confidence = float(sel.get("score", 0.0))
            mm_info    = decision.get("mm", {})
            mm_method  = mm_info.get("method", "UNKNOWN") if isinstance(mm_info, dict) else str(mm_info)
            symbol     = decision.get("symbol", "UNKNOWN")

            # ถ้า decision ไม่มี pnl จริง → ใส่ 0.0 (placeholder)
            records.append(TradeRecord(
                timestamp        = ts,
                symbol           = symbol,
                strategy         = strat_id,
                mm_method        = mm_method,
                direction        = "UNKNOWN",
                lot              = 0.0,
                entry            = 0.0,
                exit             = 0.0,
                pnl              = float(decision.get("actual_pnl", 0.0)),
                confidence       = confidence,
                regime           = regime,
                reasoning_correct = bool(decision.get("reasoning_correct", False)),
            ))
        return records


# ══════════════════════════════════════════════════════════════════════════════
# ANALYTICS HELPERS
# ══════════════════════════════════════════════════════════════════════════════
class ReportAnalytics:
    """
    คำนวณ metrics ต่าง ๆ จาก list of TradeRecord
    — ทำงานได้ทั้งแบบมีและไม่มี pandas
    """

    @staticmethod
    def total_pnl(records: List[TradeRecord]) -> float:
        return sum(r.pnl for r in records)

    @staticmethod
    def win_rate(records: List[TradeRecord]) -> float:
        if not records:
            return 0.0
        wins = sum(1 for r in records if r.pnl > 0)
        return wins / len(records)

    @staticmethod
    def profit_factor(records: List[TradeRecord]) -> float:
        gross_profit = sum(r.pnl for r in records if r.pnl > 0)
        gross_loss   = abs(sum(r.pnl for r in records if r.pnl < 0))
        return gross_profit / gross_loss if gross_loss > 0 else float("inf")

    @staticmethod
    def max_drawdown(records: List[TradeRecord]) -> Tuple[float, float]:
        """Return (max_drawdown_abs, max_drawdown_pct_of_peak)"""
        if not records:
            return 0.0, 0.0
        equity  = 0.0
        peak    = 0.0
        max_dd  = 0.0
        max_dd_pct = 0.0
        for r in records:
            equity += r.pnl
            if equity > peak:
                peak = equity
            dd = peak - equity
            if dd > max_dd:
                max_dd = dd
                max_dd_pct = (dd / peak * 100) if peak > 0 else 0.0
        return max_dd, max_dd_pct

    @staticmethod
    def strategy_attribution(records: List[TradeRecord]) -> Dict[str, Dict]:
        """
        วิเคราะห์ contribution ของแต่ละ strategy
        Return: {strategy_id: {trades, pnl, win_rate, pct_of_total}}
        """
        by_strat: Dict[str, List[TradeRecord]] = defaultdict(list)
        for r in records:
            by_strat[r.strategy].append(r)

        total_pnl = ReportAnalytics.total_pnl(records) or 1e-9
        result: Dict[str, Dict] = {}

        for strat_id, recs in sorted(by_strat.items()):
            pnl = ReportAnalytics.total_pnl(recs)
            result[strat_id] = {
                "name"       : STRATEGY_NAMES.get(strat_id, strat_id),
                "trades"     : len(recs),
                "pnl"        : round(pnl, 4),
                "win_rate"   : round(ReportAnalytics.win_rate(recs), 4),
                "pct_of_total": round(pnl / total_pnl * 100, 2),
            }
        return result

    @staticmethod
    def mm_effectiveness(records: List[TradeRecord]) -> Dict[str, Dict]:
        """วิเคราะห์ effectiveness ของแต่ละ MM method"""
        by_mm: Dict[str, List[TradeRecord]] = defaultdict(list)
        for r in records:
            by_mm[r.mm_method].append(r)

        result = {}
        for mm, recs in sorted(by_mm.items()):
            result[mm] = {
                "trades"        : len(recs),
                "pnl"           : round(ReportAnalytics.total_pnl(recs), 4),
                "win_rate"      : round(ReportAnalytics.win_rate(recs), 4),
                "profit_factor" : round(ReportAnalytics.profit_factor(recs), 4),
            }
        return result

    @staticmethod
    def regime_distribution(records: List[TradeRecord]) -> Dict[str, Dict]:
        """กระจาย trade ตาม market regime"""
        by_regime: Dict[str, List[TradeRecord]] = defaultdict(list)
        for r in records:
            by_regime[r.regime].append(r)

        total = len(records) or 1
        result = {}
        for regime, recs in sorted(by_regime.items()):
            result[regime] = {
                "trades"  : len(recs),
                "pct"     : round(len(recs) / total * 100, 2),
                "pnl"     : round(ReportAnalytics.total_pnl(recs), 4),
                "win_rate": round(ReportAnalytics.win_rate(recs), 4),
            }
        return result

    @staticmethod
    def reasoning_accuracy(records: List[TradeRecord]) -> Dict[str, float]:
        """
        คำนวณ reasoning quality:
        - overall_accuracy: % ที่ reasoning_correct = True
        - by_strategy: accuracy แยกตาม strategy
        """
        if not records:
            return {"overall": 0.0, "by_strategy": {}}

        overall = sum(1 for r in records if r.reasoning_correct) / len(records)

        by_strat: Dict[str, List[bool]] = defaultdict(list)
        for r in records:
            by_strat[r.strategy].append(r.reasoning_correct)

        by_strategy = {
            sid: round(sum(flags) / len(flags), 4)
            for sid, flags in by_strat.items()
        }

        return {
            "overall"    : round(overall, 4),
            "by_strategy": by_strategy,
        }

    @staticmethod
    def strategy_ranking(records: List[TradeRecord]) -> List[Dict]:
        """จัดอันดับ strategy โดย pnl (สูง → ต่ำ)"""
        attribution = ReportAnalytics.strategy_attribution(records)
        ranked = sorted(attribution.items(), key=lambda x: x[1]["pnl"], reverse=True)
        return [{"rank": i + 1, "strategy": sid, **metrics}
                for i, (sid, metrics) in enumerate(ranked)]

    @staticmethod
    def ai_council_accuracy(records: List[TradeRecord]) -> float:
        """
        AI Council accuracy = สัดส่วนที่ strategy ที่ selected ให้ pnl > 0
        (approximation — confidence > 0.5 → คาดว่า win)
        """
        if not records:
            return 0.0
        correct = sum(1 for r in records
                      if (r.confidence > 0.5 and r.pnl > 0) or
                         (r.confidence <= 0.5 and r.pnl <= 0))
        return round(correct / len(records), 4)


# ══════════════════════════════════════════════════════════════════════════════
# CSV REPORTER — MAIN CLASS
# ══════════════════════════════════════════════════════════════════════════════
class CSVReporter:
    """
    สร้าง CSV reports 3 ระดับ:
    - Daily  : FlashEA_Daily_YYYYMMDD.csv
    - Weekly : FlashEA_Weekly_YYYY_WXX.csv
    - Monthly: FlashEA_Monthly_YYYYMM.csv

    ทุก report มีทั้ง:
    1. trade_detail.csv   — rows ตาม TRADE_COLUMNS
    2. summary.csv        — aggregated metrics

    Usage:
        reporter = CSVReporter()
        reporter.generate_daily_report(date(2026, 2, 23))
        reporter.generate_weekly_report(2026, 8)        # week 8 ของปี 2026
        reporter.generate_monthly_report(2026, 2)
    """

    def __init__(self,
                 output_dir: Path = _REPORTS_DIR,
                 logs_dir:   Path = _LOGS_DIR):
        self.output_dir = output_dir
        self.loader     = TradeDataLoader(logs_dir)
        self.analytics  = ReportAnalytics()
        self._lock      = threading.Lock()

        # สร้าง output dir ถ้าไม่มี
        self.output_dir.mkdir(parents=True, exist_ok=True)
        logger.info("CSVReporter initialized → output: %s", self.output_dir)

    # ──────────────────────────────────────────────────────────────────────────
    # PUBLIC: record_trade (เรียกจาก execution_listener.py)
    # ──────────────────────────────────────────────────────────────────────────
    def record_trade(self, trade_dict: Dict) -> None:
        """
        บันทึก trade result ลง trades_{date}.json
        เรียกจาก execution_listener.py หลังได้รับ trade result จาก ZMQ 7779

        trade_dict ต้องมี fields ตาม TRADE_COLUMNS
        """
        ts_str = trade_dict.get("timestamp", datetime.now().isoformat())
        try:
            ts = datetime.fromisoformat(ts_str)
        except Exception:
            ts = datetime.now()

        trade_date  = ts.date()
        trades_path = _LOGS_DIR / f"trades_{trade_date.strftime('%Y%m%d')}.json"

        with self._lock:
            # โหลด existing
            existing: List[Dict] = []
            if trades_path.exists():
                try:
                    with open(trades_path, "r", encoding="utf-8") as f:
                        existing = json.load(f)
                except Exception:
                    existing = []

            existing.append(trade_dict)

            trades_path.parent.mkdir(parents=True, exist_ok=True)
            with open(trades_path, "w", encoding="utf-8") as f:
                json.dump(existing, f, ensure_ascii=False, indent=2)

    # ──────────────────────────────────────────────────────────────────────────
    # DAILY REPORT
    # ──────────────────────────────────────────────────────────────────────────
    def generate_daily_report(self, target_date: Optional[date] = None) -> Dict[str, Path]:
        """
        สร้าง daily report สำหรับวันที่ระบุ (default = วันนี้)

        Output files:
        - FlashEA_Daily_{YYYYMMDD}_trades.csv   — trade detail
        - FlashEA_Daily_{YYYYMMDD}_summary.csv  — aggregated metrics

        Return: {"trades": Path, "summary": Path}
        """
        if target_date is None:
            target_date = date.today()

        logger.info("กำลังสร้าง Daily Report สำหรับ %s …", target_date)
        records = self.loader.load_date(target_date)

        date_str = target_date.strftime("%Y%m%d")
        trades_path  = self.output_dir / f"FlashEA_Daily_{date_str}_trades.csv"
        summary_path = self.output_dir / f"FlashEA_Daily_{date_str}_summary.csv"

        # 1. Trade detail CSV
        self._write_trade_csv(records, trades_path)

        # 2. Summary CSV
        summary = self._build_daily_summary(records, target_date)
        self._write_summary_csv(summary, summary_path)

        if _MATPLOTLIB_AVAILABLE:
            self._plot_daily_pnl(records, target_date)

        logger.info("✅ Daily Report: %s (%d trades)", date_str, len(records))
        return {"trades": trades_path, "summary": summary_path}

    # ──────────────────────────────────────────────────────────────────────────
    # WEEKLY REPORT
    # ──────────────────────────────────────────────────────────────────────────
    def generate_weekly_report(self,
                                year: Optional[int] = None,
                                week: Optional[int] = None) -> Dict[str, Path]:
        """
        สร้าง weekly report

        Parameters:
            year: ปี ค.ศ. (default = ปีนี้)
            week: ISO week number 1-53 (default = สัปดาห์นี้)

        Output files:
        - FlashEA_Weekly_{YYYY}_W{WW}_trades.csv
        - FlashEA_Weekly_{YYYY}_W{WW}_summary.csv
        - FlashEA_Weekly_{YYYY}_W{WW}_strategy_rank.csv
        """
        today = date.today()
        if year is None:
            year = today.isocalendar()[0]
        if week is None:
            week = today.isocalendar()[1]

        # คำนวณ Monday–Sunday ของ week นั้น
        mon = date.fromisocalendar(year, week, 1)
        sun = date.fromisocalendar(year, week, 7)

        logger.info("กำลังสร้าง Weekly Report Y%d W%02d (%s→%s) …", year, week, mon, sun)
        records = self.loader.load_date_range(mon, sun)

        label        = f"{year}_W{week:02d}"
        trades_path  = self.output_dir / f"FlashEA_Weekly_{label}_trades.csv"
        summary_path = self.output_dir / f"FlashEA_Weekly_{label}_summary.csv"
        rank_path    = self.output_dir / f"FlashEA_Weekly_{label}_strategy_rank.csv"

        self._write_trade_csv(records, trades_path)

        summary = self._build_weekly_summary(records, year, week, mon, sun)
        self._write_summary_csv(summary, summary_path)

        # Strategy ranking
        ranking = self.analytics.strategy_ranking(records)
        self._write_ranking_csv(ranking, rank_path)

        logger.info("✅ Weekly Report: %s (%d trades)", label, len(records))
        return {"trades": trades_path, "summary": summary_path, "ranking": rank_path}

    # ──────────────────────────────────────────────────────────────────────────
    # MONTHLY REPORT
    # ──────────────────────────────────────────────────────────────────────────
    def generate_monthly_report(self,
                                 year:  Optional[int] = None,
                                 month: Optional[int] = None) -> Dict[str, Path]:
        """
        สร้าง monthly report

        Output files:
        - FlashEA_Monthly_{YYYYMM}_trades.csv
        - FlashEA_Monthly_{YYYYMM}_summary.csv
        - FlashEA_Monthly_{YYYYMM}_strategy_attr.csv  ← 16-strategy attribution
        - FlashEA_Monthly_{YYYYMM}_mm_effectiveness.csv
        - FlashEA_Monthly_{YYYYMM}_regime_dist.csv
        """
        today = date.today()
        if year  is None: year  = today.year
        if month is None: month = today.month

        # วันแรก–วันสุดท้ายของเดือน
        first_day = date(year, month, 1)
        if month == 12:
            last_day = date(year + 1, 1, 1) - timedelta(days=1)
        else:
            last_day = date(year, month + 1, 1) - timedelta(days=1)

        label = f"{year}{month:02d}"
        logger.info("กำลังสร้าง Monthly Report %s (%s→%s) …", label, first_day, last_day)
        records = self.loader.load_date_range(first_day, last_day)

        trades_path      = self.output_dir / f"FlashEA_Monthly_{label}_trades.csv"
        summary_path     = self.output_dir / f"FlashEA_Monthly_{label}_summary.csv"
        attr_path        = self.output_dir / f"FlashEA_Monthly_{label}_strategy_attr.csv"
        mm_path          = self.output_dir / f"FlashEA_Monthly_{label}_mm_effectiveness.csv"
        regime_path      = self.output_dir / f"FlashEA_Monthly_{label}_regime_dist.csv"

        self._write_trade_csv(records, trades_path)

        summary = self._build_monthly_summary(records, year, month, first_day, last_day)
        self._write_summary_csv(summary, summary_path)

        # 16-strategy attribution
        attr = self.analytics.strategy_attribution(records)
        self._write_attribution_csv(attr, attr_path)

        # MM effectiveness
        mm_eff = self.analytics.mm_effectiveness(records)
        self._write_mm_csv(mm_eff, mm_path)

        # Regime distribution
        regime_dist = self.analytics.regime_distribution(records)
        self._write_regime_csv(regime_dist, regime_path)

        if _MATPLOTLIB_AVAILABLE:
            self._plot_equity_curve(records, label)

        logger.info("✅ Monthly Report: %s (%d trades)", label, len(records))
        return {
            "trades"    : trades_path,
            "summary"   : summary_path,
            "attribution": attr_path,
            "mm"        : mm_path,
            "regime"    : regime_path,
        }

    # ──────────────────────────────────────────────────────────────────────────
    # BUILD SUMMARY DICTS
    # ──────────────────────────────────────────────────────────────────────────
    def _build_daily_summary(self, records: List[TradeRecord],
                              target_date: date) -> List[Dict]:
        if not records:
            return [{"metric": "no_data", "value": str(target_date)}]

        a = self.analytics
        dd_abs, dd_pct  = a.max_drawdown(records)
        reasoning_acc   = a.reasoning_accuracy(records)
        regime_dist     = a.regime_distribution(records)
        dominant_regime = max(regime_dist, key=lambda r: regime_dist[r]["trades"]) \
                          if regime_dist else "UNKNOWN"

        return [
            {"metric": "date",               "value": str(target_date)},
            {"metric": "total_trades",        "value": len(records)},
            {"metric": "total_pnl",           "value": round(a.total_pnl(records), 4)},
            {"metric": "win_rate",            "value": round(a.win_rate(records), 4)},
            {"metric": "profit_factor",       "value": round(a.profit_factor(records), 4)},
            {"metric": "max_drawdown_abs",    "value": round(dd_abs, 4)},
            {"metric": "max_drawdown_pct",    "value": round(dd_pct, 2)},
            {"metric": "dominant_regime",     "value": dominant_regime},
            {"metric": "reasoning_accuracy",  "value": reasoning_acc["overall"]},
            {"metric": "ai_council_accuracy", "value": a.ai_council_accuracy(records)},
        ]

    def _build_weekly_summary(self, records: List[TradeRecord],
                               year: int, week: int,
                               start: date, end: date) -> List[Dict]:
        if not records:
            return [{"metric": "no_data", "value": f"{year}_W{week:02d}"}]

        a = self.analytics
        dd_abs, dd_pct = a.max_drawdown(records)
        reasoning_acc  = a.reasoning_accuracy(records)
        ranking        = a.strategy_ranking(records)
        best_strat     = ranking[0]["strategy"] if ranking else "N/A"
        best_pnl       = ranking[0]["pnl"] if ranking else 0.0
        mm_eff         = a.mm_effectiveness(records)
        best_mm        = max(mm_eff, key=lambda m: mm_eff[m]["pnl"]) if mm_eff else "N/A"

        return [
            {"metric": "year",                "value": year},
            {"metric": "week",                "value": week},
            {"metric": "period_start",        "value": str(start)},
            {"metric": "period_end",          "value": str(end)},
            {"metric": "total_trades",        "value": len(records)},
            {"metric": "total_pnl",           "value": round(a.total_pnl(records), 4)},
            {"metric": "win_rate",            "value": round(a.win_rate(records), 4)},
            {"metric": "profit_factor",       "value": round(a.profit_factor(records), 4)},
            {"metric": "max_drawdown_abs",    "value": round(dd_abs, 4)},
            {"metric": "max_drawdown_pct",    "value": round(dd_pct, 2)},
            {"metric": "best_strategy",       "value": best_strat},
            {"metric": "best_strategy_pnl",   "value": round(best_pnl, 4)},
            {"metric": "best_mm_method",      "value": best_mm},
            {"metric": "reasoning_accuracy",  "value": reasoning_acc["overall"]},
            {"metric": "ai_council_accuracy", "value": a.ai_council_accuracy(records)},
        ]

    def _build_monthly_summary(self, records: List[TradeRecord],
                                year: int, month: int,
                                start: date, end: date) -> List[Dict]:
        if not records:
            return [{"metric": "no_data", "value": f"{year}{month:02d}"}]

        a = self.analytics
        dd_abs, dd_pct = a.max_drawdown(records)
        reasoning_acc  = a.reasoning_accuracy(records)
        regime_dist    = a.regime_distribution(records)
        ranking        = a.strategy_ranking(records)

        # หาจำนวน trading days จริง (วันที่มี trade)
        trade_days = len(set(r.timestamp[:10] for r in records if len(r.timestamp) >= 10))

        # คำนวณ ROI approximate (สมมติ base equity = 10000)
        total_pnl = a.total_pnl(records)

        # จำนวน trade ต่อวัน
        avg_trades_per_day = len(records) / max(trade_days, 1)

        return [
            {"metric": "year",                "value": year},
            {"metric": "month",               "value": month},
            {"metric": "period_start",        "value": str(start)},
            {"metric": "period_end",          "value": str(end)},
            {"metric": "trading_days",        "value": trade_days},
            {"metric": "total_trades",        "value": len(records)},
            {"metric": "avg_trades_per_day",  "value": round(avg_trades_per_day, 1)},
            {"metric": "total_pnl",           "value": round(total_pnl, 4)},
            {"metric": "win_rate",            "value": round(a.win_rate(records), 4)},
            {"metric": "profit_factor",       "value": round(a.profit_factor(records), 4)},
            {"metric": "max_drawdown_abs",    "value": round(dd_abs, 4)},
            {"metric": "max_drawdown_pct",    "value": round(dd_pct, 2)},
            {"metric": "reasoning_accuracy",  "value": reasoning_acc["overall"]},
            {"metric": "ai_council_accuracy", "value": a.ai_council_accuracy(records)},
            {"metric": "dominant_regime",     "value": max(regime_dist,
                key=lambda r: regime_dist[r]["trades"], default="UNKNOWN")},
        ]

    # ──────────────────────────────────────────────────────────────────────────
    # CSV WRITERS
    # ──────────────────────────────────────────────────────────────────────────
    def _write_trade_csv(self, records: List[TradeRecord], path: Path) -> None:
        """เขียน trade detail CSV"""
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(TRADE_COLUMNS)
            for r in records:
                writer.writerow(r.to_row())
        logger.debug("เขียน %s (%d rows)", path.name, len(records))

    def _write_summary_csv(self, summary: List[Dict], path: Path) -> None:
        """เขียน summary CSV (metric, value format)"""
        if not summary:
            return
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["metric", "value"])
            writer.writeheader()
            writer.writerows(summary)
        logger.debug("เขียน %s (%d rows)", path.name, len(summary))

    def _write_ranking_csv(self, ranking: List[Dict], path: Path) -> None:
        """เขียน strategy ranking CSV"""
        if not ranking:
            return
        fieldnames = list(ranking[0].keys()) if ranking else ["rank", "strategy"]
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(ranking)
        logger.debug("เขียน %s (%d rows)", path.name, len(ranking))

    def _write_attribution_csv(self, attribution: Dict[str, Dict], path: Path) -> None:
        """เขียน 16-strategy attribution CSV"""
        rows = [{"strategy": sid, **metrics} for sid, metrics in attribution.items()]
        if not rows:
            rows = [{"strategy": "no_data"}]
        fieldnames = list(rows[0].keys())
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
        logger.debug("เขียน %s (%d strategies)", path.name, len(rows))

    def _write_mm_csv(self, mm_eff: Dict[str, Dict], path: Path) -> None:
        """เขียน MM effectiveness CSV"""
        rows = [{"mm_method": mm, **metrics} for mm, metrics in mm_eff.items()]
        if not rows:
            rows = [{"mm_method": "no_data"}]
        fieldnames = list(rows[0].keys())
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def _write_regime_csv(self, regime_dist: Dict[str, Dict], path: Path) -> None:
        """เขียน regime distribution CSV"""
        rows = [{"regime": r, **metrics} for r, metrics in regime_dist.items()]
        if not rows:
            rows = [{"regime": "no_data"}]
        fieldnames = list(rows[0].keys())
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    # ──────────────────────────────────────────────────────────────────────────
    # CHARTS (optional — ถ้ามี matplotlib)
    # ──────────────────────────────────────────────────────────────────────────
    def _plot_daily_pnl(self, records: List[TradeRecord], target_date: date) -> None:
        if not records:
            return
        try:
            pnls       = [r.pnl for r in records]
            cum_pnl    = []
            running    = 0.0
            for p in pnls:
                running += p
                cum_pnl.append(running)

            fig, axes = plt.subplots(1, 2, figsize=(14, 5))
            fig.suptitle(f"Daily P&L — {target_date}", fontsize=13)

            # Cumulative PnL
            axes[0].plot(cum_pnl, color="steelblue", linewidth=1.5)
            axes[0].axhline(0, color="gray", linewidth=0.8, linestyle="--")
            axes[0].fill_between(range(len(cum_pnl)), cum_pnl, 0,
                                  where=[p >= 0 for p in cum_pnl],
                                  alpha=0.3, color="green", label="Profit")
            axes[0].fill_between(range(len(cum_pnl)), cum_pnl, 0,
                                  where=[p < 0 for p in cum_pnl],
                                  alpha=0.3, color="red", label="Loss")
            axes[0].set_title("Cumulative P&L")
            axes[0].set_xlabel("Trade #")
            axes[0].set_ylabel("P&L")
            axes[0].legend()

            # Strategy PnL bar chart
            by_strat  = defaultdict(float)
            for r in records:
                by_strat[r.strategy] += r.pnl
            strats = sorted(by_strat.keys())
            pnl_vals = [by_strat[s] for s in strats]
            colors = ["green" if v >= 0 else "red" for v in pnl_vals]
            axes[1].bar(strats, pnl_vals, color=colors, edgecolor="white")
            axes[1].axhline(0, color="gray", linewidth=0.8, linestyle="--")
            axes[1].set_title("P&L by Strategy")
            axes[1].set_xlabel("Strategy")
            axes[1].set_ylabel("P&L")
            axes[1].tick_params(axis="x", rotation=45)

            plt.tight_layout()
            chart_path = self.output_dir / f"chart_daily_{target_date.strftime('%Y%m%d')}.png"
            plt.savefig(chart_path, dpi=120, bbox_inches="tight")
            plt.close(fig)
            logger.debug("บันทึก chart → %s", chart_path.name)
        except Exception as ex:
            logger.warning("plot_daily_pnl ผิดพลาด: %s", ex)

    def _plot_equity_curve(self, records: List[TradeRecord], label: str) -> None:
        if not records:
            return
        try:
            pnls    = [r.pnl for r in records]
            cum_pnl = []
            running = 0.0
            for p in pnls:
                running += p
                cum_pnl.append(running)

            # คำนวณ drawdown
            peak     = 0.0
            drawdown = []
            for eq in cum_pnl:
                if eq > peak:
                    peak = eq
                drawdown.append(peak - eq)

            fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 8), sharex=True)
            fig.suptitle(f"Equity Curve — {label}", fontsize=13)

            ax1.plot(cum_pnl, color="steelblue", linewidth=1.5, label="Equity")
            ax1.fill_between(range(len(cum_pnl)), cum_pnl, 0,
                              where=[p >= 0 for p in cum_pnl],
                              alpha=0.15, color="steelblue")
            ax1.set_ylabel("Cumulative P&L")
            ax1.legend()
            ax1.grid(True, alpha=0.3)

            ax2.fill_between(range(len(drawdown)), drawdown, color="red", alpha=0.4)
            ax2.set_ylabel("Drawdown")
            ax2.set_xlabel("Trade #")
            ax2.grid(True, alpha=0.3)

            plt.tight_layout()
            chart_path = self.output_dir / f"chart_equity_{label}.png"
            plt.savefig(chart_path, dpi=120, bbox_inches="tight")
            plt.close(fig)
            logger.debug("บันทึก equity curve → %s", chart_path.name)
        except Exception as ex:
            logger.warning("plot_equity_curve ผิดพลาด: %s", ex)


# ══════════════════════════════════════════════════════════════════════════════
# REPORT SCHEDULER — สร้าง report ตามเวลา (เรียกจาก main.py)
# ══════════════════════════════════════════════════════════════════════════════
class ReportScheduler:
    """
    สร้าง reports อัตโนมัติตามเวลา:
    - Daily   : 00:05 ของทุกวัน (สร้าง report ของเมื่อวาน)
    - Weekly  : วันจันทร์ 00:10 (สร้าง report ของสัปดาห์ที่ผ่านมา)
    - Monthly : วันที่ 1 00:15 (สร้าง report ของเดือนที่ผ่านมา)

    Usage:
        scheduler = ReportScheduler(reporter)
        scheduler.start()   # รันใน background thread
    """

    def __init__(self, reporter: CSVReporter, check_interval_sec: int = 60):
        self.reporter         = reporter
        self.check_interval   = check_interval_sec
        self._thread: Optional[threading.Thread] = None
        self._stop_event      = threading.Event()
        self._last_daily_date: Optional[date] = None
        self._last_weekly_key: Optional[str]  = None
        self._last_monthly_key: Optional[str] = None

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, daemon=True,
                                         name="report_scheduler")
        self._thread.start()
        logger.info("ReportScheduler เริ่มทำงานแล้ว (interval=%ds)", self.check_interval)

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("ReportScheduler หยุดแล้ว")

    def _run(self) -> None:
        while not self._stop_event.is_set():
            try:
                self._check_and_generate()
            except Exception as ex:
                logger.error("ReportScheduler error: %s", ex)
            self._stop_event.wait(timeout=self.check_interval)

    def _check_and_generate(self) -> None:
        now   = datetime.now()
        today = now.date()

        # Daily: สร้างเมื่อวานหลัง 00:05
        if now.hour == 0 and now.minute >= 5:
            yesterday = today - timedelta(days=1)
            if self._last_daily_date != yesterday:
                self.reporter.generate_daily_report(yesterday)
                self._last_daily_date = yesterday

        # Weekly: วันจันทร์ 00:10
        if now.weekday() == 0 and now.hour == 0 and now.minute >= 10:
            last_mon = today - timedelta(days=7)
            y, w, _ = last_mon.isocalendar()
            key = f"{y}_W{w:02d}"
            if self._last_weekly_key != key:
                self.reporter.generate_weekly_report(y, w)
                self._last_weekly_key = key

        # Monthly: วันที่ 1 00:15
        if today.day == 1 and now.hour == 0 and now.minute >= 15:
            # เดือนที่ผ่านมา
            if today.month == 1:
                prev_year, prev_month = today.year - 1, 12
            else:
                prev_year, prev_month = today.year, today.month - 1
            key = f"{prev_year}{prev_month:02d}"
            if self._last_monthly_key != key:
                self.reporter.generate_monthly_report(prev_year, prev_month)
                self._last_monthly_key = key


# ══════════════════════════════════════════════════════════════════════════════
# MODULE-LEVEL SINGLETON
# ══════════════════════════════════════════════════════════════════════════════
_reporter_instance: Optional[CSVReporter] = None


def get_reporter() -> CSVReporter:
    """Return singleton CSVReporter — เรียกจาก execution_listener.py"""
    global _reporter_instance
    if _reporter_instance is None:
        _reporter_instance = CSVReporter()
    return _reporter_instance


# ══════════════════════════════════════════════════════════════════════════════
# STANDALONE TEST (python csv_reporter.py)
# ══════════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    import random

    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S"
    )

    print("=" * 60)
    print("FlashEASuite V2 — csv_reporter.py STANDALONE TEST")
    print("=" * 60)

    # ──────────────────────────────────────────────────────────────
    # สร้าง mock trade data และเขียนลง trades_{date}.json
    # ──────────────────────────────────────────────────────────────
    reporter = CSVReporter(
        output_dir=_REPORTS_DIR,
        logs_dir=_LOGS_DIR,
    )

    STRATEGIES = list(STRATEGY_NAMES.keys())
    MM_METHODS = ["MM01", "MM02", "MM03", "MM05", "MM10"]
    REGIMES    = ["TRENDING_UP", "TRENDING_DOWN", "RANGING", "VOLATILE"]
    SYMBOLS    = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"]

    # สร้าง mock trades สำหรับ 7 วันย้อนหลัง
    test_dates = [date.today() - timedelta(days=i) for i in range(7)]

    for test_date in test_dates:
        n_trades = random.randint(20, 60)
        mock_trades = []
        for _ in range(n_trades):
            strat  = random.choice(STRATEGIES)
            pnl    = round(random.gauss(1.5, 8.0), 4)
            conf   = round(random.uniform(0.3, 0.95), 4)
            entry  = round(random.uniform(1.0, 200.0), 5)
            exit_  = round(entry + random.gauss(0, 0.002), 5)

            mock_trades.append({
                "timestamp"        : f"{test_date}T{random.randint(0,23):02d}:{random.randint(0,59):02d}:00",
                "symbol"           : random.choice(SYMBOLS),
                "strategy"         : strat,
                "mm_method"        : random.choice(MM_METHODS),
                "direction"        : random.choice(["BUY", "SELL"]),
                "lot"              : round(random.uniform(0.01, 0.5), 2),
                "entry"            : entry,
                "exit"             : exit_,
                "pnl"              : pnl,
                "confidence"       : conf,
                "regime"           : random.choice(REGIMES),
                "reasoning_correct": pnl > 0 and conf > 0.6,
            })

        # เขียน mock trades
        trades_path = _LOGS_DIR / f"trades_{test_date.strftime('%Y%m%d')}.json"
        _LOGS_DIR.mkdir(parents=True, exist_ok=True)
        with open(trades_path, "w", encoding="utf-8") as f:
            json.dump(mock_trades, f, ensure_ascii=False, indent=2)
        print(f"  📝 สร้าง mock trades: {trades_path.name} ({len(mock_trades)} trades)")

    print()

    # ──────────────────────────────────────────────────────────────
    # TEST 1: Daily Report
    # ──────────────────────────────────────────────────────────────
    print("TEST 1: Daily Report …")
    t0 = time.perf_counter()
    daily_paths = reporter.generate_daily_report(date.today())
    elapsed = (time.perf_counter() - t0) * 1000
    for k, p in daily_paths.items():
        exists = "✅" if p.exists() else "❌"
        print(f"  {exists} [{k}] {p.name}")
    print(f"  ⏱  {elapsed:.0f}ms")
    print()

    # ──────────────────────────────────────────────────────────────
    # TEST 2: Weekly Report
    # ──────────────────────────────────────────────────────────────
    print("TEST 2: Weekly Report …")
    t0 = time.perf_counter()
    y, w, _ = date.today().isocalendar()
    weekly_paths = reporter.generate_weekly_report(y, w)
    elapsed = (time.perf_counter() - t0) * 1000
    for k, p in weekly_paths.items():
        exists = "✅" if p.exists() else "❌"
        print(f"  {exists} [{k}] {p.name}")
    print(f"  ⏱  {elapsed:.0f}ms")
    print()

    # ──────────────────────────────────────────────────────────────
    # TEST 3: Monthly Report
    # ──────────────────────────────────────────────────────────────
    print("TEST 3: Monthly Report …")
    t0 = time.perf_counter()
    monthly_paths = reporter.generate_monthly_report(
        date.today().year, date.today().month
    )
    elapsed = (time.perf_counter() - t0) * 1000
    for k, p in monthly_paths.items():
        exists = "✅" if p.exists() else "❌"
        print(f"  {exists} [{k}] {p.name}")
    print(f"  ⏱  {elapsed:.0f}ms")
    print()

    # ──────────────────────────────────────────────────────────────
    # TEST 4: record_trade()
    # ──────────────────────────────────────────────────────────────
    print("TEST 4: record_trade() …")
    reporter.record_trade({
        "timestamp": datetime.now().isoformat(),
        "symbol": "EURUSD",
        "strategy": "S07",
        "mm_method": "MM03",
        "direction": "BUY",
        "lot": 0.1,
        "entry": 1.08500,
        "exit": 1.08650,
        "pnl": 15.0,
        "confidence": 0.78,
        "regime": "TRENDING_UP",
        "reasoning_correct": True,
    })
    today_trades = _LOGS_DIR / f"trades_{date.today().strftime('%Y%m%d')}.json"
    print(f"  ✅ trades file updated: {today_trades.name}")
    print()

    print("=" * 60)
    print("✅ STANDALONE TEST PASS")
    print(f"   Output dir: {_REPORTS_DIR}")
    print("=" * 60)
