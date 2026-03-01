#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — P7-2: Decision Analytics
============================================
วิเคราะห์คุณภาพการตัดสินใจของ AI Council, Regime Classifier, และ Reasoning Chain

Reads from:
  - Trade log CSV   (ผลิตโดย csv_reporter.py)    : 02_Brain/reports/data/trades_*.csv
  - Decision log    (ผลิตโดย decision_logger.py)  : 02_Brain/reports/data/decisions_*.jsonl
  - Regime log      (ผลิตโดย regime_classifier.py): 02_Brain/reports/data/regimes_*.jsonl

Outputs to: 02_Brain/reports/output/
  - council_accuracy_<date>.csv
  - regime_accuracy_<date>.csv
  - reasoning_quality_<date>.csv
  - false_pos_neg_<date>.csv

Author: Claude AI for Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-23
"""

import os
import csv
import json
import logging
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("DecisionAnalytics")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
STRATEGY_NAMES: Dict[str, str] = {
    "S01": "StatArb",       "S02": "ML_Ensemble",    "S03": "SMC",
    "S04": "MarketProfile", "S05": "SupplyDemand",   "S06": "KAMA",
    "S07": "MeanReversion", "S08": "Intermarket",    "S09": "SessionBreakout",
    "S10": "Turtle",        "S11": "Ichimoku",       "S12": "PriceAction",
    "S13": "FibStoch",      "S14": "BBSqueeze",      "S15": "Grid",
    "S16": "Spike",
}

REGIME_METHODS = ["rule", "rf", "hmm", "ensemble"]

# Confidence thresholds สำหรับ bucket analysis
CONF_BUCKETS: List[Tuple[float, float]] = [
    (0.0, 0.50), (0.50, 0.60), (0.60, 0.70), (0.70, 0.80), (0.80, 1.01),
]
CONF_LABELS: List[str] = ["lt050", "050_060", "060_070", "070_080", "gte080"]


# ===========================================================================
# 1. Data Loaders
# ===========================================================================

def load_trade_log(csv_path: str) -> List[Dict]:
    """
    โหลด trade log CSV ที่ผลิตโดย csv_reporter.py

    Expected columns:
      timestamp, symbol, strategy, mm_method, direction,
      lot, entry, exit, pnl, confidence, regime, reasoning_correct
    """
    trades: List[Dict] = []
    if not os.path.exists(csv_path):
        logger.warning(f"Trade log not found: {csv_path}")
        return trades

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                trades.append({
                    "timestamp":         row["timestamp"],
                    "symbol":            row["symbol"].upper(),
                    "strategy":          row["strategy"].upper(),
                    "mm_method":         row["mm_method"],
                    "direction":         row["direction"].upper(),
                    "lot":               float(row["lot"]),
                    "entry":             float(row["entry"]),
                    "exit":              float(row["exit"]),
                    "pnl":               float(row["pnl"]),
                    "confidence":        float(row["confidence"]),
                    "regime":            row["regime"].lower(),
                    "reasoning_correct": row["reasoning_correct"].strip().lower() == "true",
                })
            except (KeyError, ValueError) as e:
                logger.debug(f"Skip malformed row: {e} — {row}")

    logger.info(f"Loaded {len(trades)} trades from {csv_path}")
    return trades


def load_decision_log(jsonl_path: str) -> List[Dict]:
    """
    โหลด decision log JSONL ที่ผลิตโดย decision_logger.py

    Expected fields per line:
      timestamp, symbol, strategy, predicted_direction, actual_direction,
      confidence, council_vote, regime, reasoning_text, outcome_correct
    """
    decisions: List[Dict] = []
    if not os.path.exists(jsonl_path):
        logger.warning(f"Decision log not found: {jsonl_path}")
        return decisions

    with open(jsonl_path, encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                decisions.append(json.loads(line))
            except json.JSONDecodeError as e:
                logger.debug(f"Skip malformed JSON at line {line_num}: {e}")

    logger.info(f"Loaded {len(decisions)} decisions from {jsonl_path}")
    return decisions


def load_regime_log(jsonl_path: str) -> List[Dict]:
    """
    โหลด regime prediction log JSONL

    Expected fields per line:
      timestamp, symbol, rule_regime, rf_regime, hmm_regime,
      ensemble_regime, actual_regime
    """
    records: List[Dict] = []
    if not os.path.exists(jsonl_path):
        logger.warning(f"Regime log not found: {jsonl_path}")
        return records

    with open(jsonl_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    logger.info(f"Loaded {len(records)} regime records from {jsonl_path}")
    return records


# ===========================================================================
# 2. AI Council Accuracy per Strategy × Symbol
# ===========================================================================

class CouncilAccuracyAnalyzer:
    """
    วิเคราะห์ความแม่นยำของ AI Council แยกตาม strategy × symbol

    Metric หลัก: ในบรรดา trades ที่ Council แนะนำ → กี่ % ที่ pnl > 0
    Metric เพิ่ม: high-confidence trades (confidence >= 0.70) win rate
    """

    HIGH_CONF_THRESHOLD = 0.70

    def analyze(self, trades: List[Dict]) -> List[Dict]:
        """
        Returns:
          strategy, strategy_name, symbol,
          total_trades, winning_trades, win_rate_pct,
          avg_pnl, total_pnl, avg_confidence,
          high_conf_trades, high_conf_wins, high_conf_win_rate_pct
        """
        # (strategy, symbol) → stats dict
        buckets: Dict[Tuple[str, str], Dict] = defaultdict(lambda: {
            "total": 0, "wins": 0, "pnl_sum": 0.0, "conf_sum": 0.0,
            "hc_total": 0, "hc_wins": 0,
        })

        for t in trades:
            key = (t["strategy"], t["symbol"])
            b = buckets[key]
            b["total"]    += 1
            b["pnl_sum"]  += t["pnl"]
            b["conf_sum"] += t["confidence"]
            if t["pnl"] > 0:
                b["wins"] += 1
            if t["confidence"] >= self.HIGH_CONF_THRESHOLD:
                b["hc_total"] += 1
                if t["pnl"] > 0:
                    b["hc_wins"] += 1

        rows = []
        for (strategy, symbol), b in sorted(buckets.items()):
            n = b["total"]
            if n == 0:
                continue
            hc = b["hc_total"]
            rows.append({
                "strategy":              strategy,
                "strategy_name":         STRATEGY_NAMES.get(strategy[:3], strategy),
                "symbol":                symbol,
                "total_trades":          n,
                "winning_trades":        b["wins"],
                "win_rate_pct":          round(b["wins"] / n * 100, 2),
                "avg_pnl":               round(b["pnl_sum"] / n, 4),
                "total_pnl":             round(b["pnl_sum"], 4),
                "avg_confidence":        round(b["conf_sum"] / n, 4),
                "high_conf_trades":      hc,
                "high_conf_wins":        b["hc_wins"],
                "high_conf_win_rate_pct": round(b["hc_wins"] / hc * 100 if hc > 0 else 0.0, 2),
            })
        return rows


# ===========================================================================
# 3. Regime Prediction Accuracy (Rule vs RF vs HMM vs Ensemble)
# ===========================================================================

class RegimeAccuracyAnalyzer:
    """
    เปรียบเทียบความแม่นยำของ Rule-based, Random Forest, HMM, และ Ensemble
    ในการทำนาย market regime
    """

    def analyze(self, regime_records: List[Dict]) -> List[Dict]:
        """
        Returns one row per method:
          method, total_predictions, correct_predictions, accuracy_pct,
          regime_<X>_total, regime_<X>_correct, regime_<X>_acc_pct
          (สำหรับทุก regime ที่พบใน data)
        """
        # per method: total, correct, and per-regime breakdown
        stats: Dict[str, Dict] = {
            m: {"total": 0, "correct": 0, "by_regime": defaultdict(lambda: {"t": 0, "c": 0})}
            for m in REGIME_METHODS
        }

        all_regimes: set = set()
        for rec in regime_records:
            actual = rec.get("actual_regime", "")
            if actual:
                all_regimes.add(actual)
            for method in REGIME_METHODS:
                predicted = rec.get(f"{method}_regime", "")
                if not predicted or not actual:
                    continue
                s = stats[method]
                s["total"] += 1
                s["by_regime"][actual]["t"] += 1
                if predicted == actual:
                    s["correct"] += 1
                    s["by_regime"][actual]["c"] += 1

        all_regimes_sorted = sorted(all_regimes)
        rows = []
        for method in REGIME_METHODS:
            s = stats[method]
            total = s["total"]
            if total == 0:
                continue
            row: Dict = {
                "method":               method,
                "total_predictions":    total,
                "correct_predictions":  s["correct"],
                "accuracy_pct":         round(s["correct"] / total * 100, 2),
            }
            for regime in all_regimes_sorted:
                rt = s["by_regime"][regime]["t"]
                rc = s["by_regime"][regime]["c"]
                row[f"regime_{regime}_total"]   = rt
                row[f"regime_{regime}_correct"] = rc
                row[f"regime_{regime}_acc_pct"] = round(rc / rt * 100 if rt > 0 else 0.0, 2)
            rows.append(row)
        return rows


# ===========================================================================
# 4. Reasoning Chain Quality
# ===========================================================================

class ReasoningQualityAnalyzer:
    """
    วิเคราะห์ว่า Reasoning ของ AI Council สอดคล้องกับผลลัพธ์จริงมากแค่ไหน
    โดยใช้ field 'reasoning_correct' จาก trade log

    Metrics:
      - reasoning_accuracy_pct : สัดส่วน trades ที่ reasoning_correct = True
      - correct_win_rate_pct   : win rate เมื่อ reasoning ถูก
      - incorrect_win_rate_pct : win rate เมื่อ reasoning ผิด
      - reasoning_value_add_pct: ส่วนต่าง → ถ้า > 0 แปลว่า reasoning มีคุณค่า
    """

    def analyze(self, trades: List[Dict]) -> List[Dict]:
        """
        Returns one row per strategy:
          strategy, strategy_name, total_trades,
          reasoning_correct_count, reasoning_accuracy_pct,
          correct_and_profitable, correct_but_lost,
          incorrect_and_profitable, incorrect_and_lost,
          correct_win_rate_pct, incorrect_win_rate_pct,
          reasoning_value_add_pct
        """
        buckets: Dict[str, Dict] = defaultdict(lambda: {
            "total": 0,
            "rc": 0,        # reasoning correct count
            "rc_win": 0,    # reasoning correct + profit
            "rc_lose": 0,   # reasoning correct + loss
            "rw_win": 0,    # reasoning wrong + profit
            "rw_lose": 0,   # reasoning wrong + loss
        })

        for t in trades:
            b = buckets[t["strategy"]]
            b["total"] += 1
            rc  = t["reasoning_correct"]
            win = t["pnl"] > 0
            if rc:
                b["rc"] += 1
                if win:
                    b["rc_win"] += 1
                else:
                    b["rc_lose"] += 1
            else:
                if win:
                    b["rw_win"] += 1
                else:
                    b["rw_lose"] += 1

        rows = []
        for strategy, b in sorted(buckets.items()):
            n   = b["total"]
            if n == 0:
                continue
            rc  = b["rc"]
            rw  = n - rc
            rc_wr = b["rc_win"]  / rc * 100 if rc > 0 else 0.0
            rw_wr = b["rw_win"]  / rw * 100 if rw > 0 else 0.0
            rows.append({
                "strategy":                strategy,
                "strategy_name":           STRATEGY_NAMES.get(strategy[:3], strategy),
                "total_trades":            n,
                "reasoning_correct_count": rc,
                "reasoning_accuracy_pct":  round(rc / n * 100, 2),
                "correct_and_profitable":  b["rc_win"],
                "correct_but_lost":        b["rc_lose"],
                "incorrect_and_profitable": b["rw_win"],
                "incorrect_and_lost":      b["rw_lose"],
                "correct_win_rate_pct":    round(rc_wr, 2),
                "incorrect_win_rate_pct":  round(rw_wr, 2),
                "reasoning_value_add_pct": round(rc_wr - rw_wr, 2),
            })
        return rows


# ===========================================================================
# 5. False Positive / False Negative Rates per Strategy
# ===========================================================================

class FalseRateAnalyzer:
    """
    คำนวณ False Positive (FP) rates ต่อ strategy
    แยกตาม regime และ confidence bucket

    นิยาม (based on executed trades only):
      TP: Council แนะนำ → pnl > 0
      FP: Council แนะนำ → pnl <= 0
      Precision       = TP / (TP + FP)
      False Discovery = FP / (TP + FP)

    หมายเหตุ: FN (missed opportunities) ไม่สามารถคำนวณได้จาก trade log
    เพราะไม่มีข้อมูล trades ที่ Council ปฏิเสธ
    """

    def analyze(self, trades: List[Dict]) -> List[Dict]:
        """
        Returns one row per strategy:
          strategy, strategy_name, total_trades, tp, fp,
          precision_pct, false_discovery_rate_pct,
          avg_tp_pnl, avg_fp_pnl,
          fp_rate_<regime>_pct (per regime found in data),
          fdr_conf_<bucket>_pct (per confidence bucket)
        """
        buckets: Dict[str, Dict] = defaultdict(lambda: {
            "tp": 0, "fp": 0,
            "by_regime": defaultdict(lambda: {"tp": 0, "fp": 0}),
            "by_conf": [{"tp": 0, "fp": 0} for _ in CONF_BUCKETS],
            "tp_pnl_sum": 0.0,
            "fp_pnl_sum": 0.0,
        })

        for t in trades:
            b   = buckets[t["strategy"]]
            win = t["pnl"] > 0
            regime = t["regime"]
            if win:
                b["tp"] += 1
                b["by_regime"][regime]["tp"] += 1
                b["tp_pnl_sum"] += t["pnl"]
            else:
                b["fp"] += 1
                b["by_regime"][regime]["fp"] += 1
                b["fp_pnl_sum"] += t["pnl"]
            # confidence bucket
            conf = t["confidence"]
            for idx, (lo, hi) in enumerate(CONF_BUCKETS):
                if lo <= conf < hi:
                    if win:
                        b["by_conf"][idx]["tp"] += 1
                    else:
                        b["by_conf"][idx]["fp"] += 1
                    break

        rows = []
        for strategy, b in sorted(buckets.items()):
            tp = b["tp"]
            fp = b["fp"]
            total = tp + fp
            if total == 0:
                continue

            row: Dict = {
                "strategy":                 strategy,
                "strategy_name":            STRATEGY_NAMES.get(strategy[:3], strategy),
                "total_trades":             total,
                "tp":                       tp,
                "fp":                       fp,
                "precision_pct":            round(tp / total * 100, 2),
                "false_discovery_rate_pct": round(fp / total * 100, 2),
                "avg_tp_pnl":               round(b["tp_pnl_sum"] / tp if tp > 0 else 0.0, 4),
                "avg_fp_pnl":               round(b["fp_pnl_sum"] / fp if fp > 0 else 0.0, 4),
            }
            # per-regime FP rate
            for regime, rv in sorted(b["by_regime"].items()):
                rt = rv["tp"] + rv["fp"]
                row[f"fp_rate_{regime}_pct"] = round(rv["fp"] / rt * 100 if rt > 0 else 0.0, 2)
                row[f"trades_{regime}"]      = rt
            # per-confidence FDR
            for idx, label in enumerate(CONF_LABELS):
                cv = b["by_conf"][idx]
                ct = cv["tp"] + cv["fp"]
                row[f"fdr_conf_{label}_pct"] = round(cv["fp"] / ct * 100 if ct > 0 else 0.0, 2)

            rows.append(row)
        return rows


# ===========================================================================
# 6. CSV Writer
# ===========================================================================

def write_csv(rows: List[Dict], output_path: str) -> None:
    """เขียน list of dict เป็น CSV file — สร้าง directory อัตโนมัติ"""
    if not rows:
        logger.warning(f"No data to write → {output_path}")
        return
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    logger.info(f"Saved {len(rows)} rows → {output_path}")


# ===========================================================================
# 7. Main Runner
# ===========================================================================

class DecisionAnalytics:
    """
    Entry point สำหรับรัน Decision Analytics ทั้งหมด

    Usage:
        da = DecisionAnalytics(
            data_dir="FlashEASuite_V2/02_Brain/reports/data",
            output_dir="FlashEASuite_V2/02_Brain/reports/output"
        )
        outputs = da.run(date_str="2026-02-23")
    """

    def __init__(self, data_dir: str = "data", output_dir: str = "output"):
        self.data_dir  = data_dir
        self.output_dir = output_dir

    def _find_files(self, prefix: str, date_str: Optional[str]) -> List[str]:
        """ค้นหาไฟล์ใน data_dir ที่ขึ้นต้นด้วย prefix (และ filter ด้วย date_str ถ้ากำหนด)"""
        if not os.path.isdir(self.data_dir):
            return []
        result = []
        for fname in sorted(os.listdir(self.data_dir)):
            if fname.startswith(prefix):
                if date_str is None or date_str in fname:
                    result.append(os.path.join(self.data_dir, fname))
        return result

    def run(
        self,
        date_str:       Optional[str] = None,
        trade_csv:      Optional[str] = None,
        decision_jsonl: Optional[str] = None,
        regime_jsonl:   Optional[str] = None,
    ) -> Dict[str, str]:
        """
        รัน analytics ทั้ง 4 reports

        Args:
            date_str:       filter ไฟล์ตาม date เช่น "2026-02-23"
            trade_csv:      path ตรงของ trade log CSV (override auto-discovery)
            decision_jsonl: path ตรงของ decision log JSONL
            regime_jsonl:   path ตรงของ regime log JSONL

        Returns:
            dict {report_name: output_path}
        """
        tag = date_str or datetime.now().strftime("%Y-%m-%d")
        outputs: Dict[str, str] = {}

        # Load data
        trades:    List[Dict] = []
        decisions: List[Dict] = []
        regimes:   List[Dict] = []

        if trade_csv:
            trades = load_trade_log(trade_csv)
        else:
            for p in self._find_files("trades_", date_str):
                trades.extend(load_trade_log(p))

        if decision_jsonl:
            decisions = load_decision_log(decision_jsonl)
        else:
            for p in self._find_files("decisions_", date_str):
                decisions.extend(load_decision_log(p))

        if regime_jsonl:
            regimes = load_regime_log(regime_jsonl)
        else:
            for p in self._find_files("regimes_", date_str):
                regimes.extend(load_regime_log(p))

        if not trades and not decisions and not regimes:
            logger.warning("No data found. Provide data_dir with files or explicit paths.")
            return outputs

        # Report 1: Council Accuracy (strategy × symbol)
        if trades:
            rows = CouncilAccuracyAnalyzer().analyze(trades)
            path = os.path.join(self.output_dir, f"council_accuracy_{tag}.csv")
            write_csv(rows, path)
            outputs["council_accuracy"] = path

        # Report 2: Regime Prediction Accuracy
        if regimes:
            rows = RegimeAccuracyAnalyzer().analyze(regimes)
            path = os.path.join(self.output_dir, f"regime_accuracy_{tag}.csv")
            write_csv(rows, path)
            outputs["regime_accuracy"] = path

        # Report 3: Reasoning Chain Quality
        if trades:
            rows = ReasoningQualityAnalyzer().analyze(trades)
            path = os.path.join(self.output_dir, f"reasoning_quality_{tag}.csv")
            write_csv(rows, path)
            outputs["reasoning_quality"] = path

        # Report 4: False Positive / Negative Rates
        if trades:
            rows = FalseRateAnalyzer().analyze(trades)
            path = os.path.join(self.output_dir, f"false_pos_neg_{tag}.csv")
            write_csv(rows, path)
            outputs["false_pos_neg"] = path

        logger.info(f"DecisionAnalytics complete — {len(outputs)} reports generated.")
        return outputs


# ===========================================================================
# 8. CLI
# ===========================================================================

def main() -> None:
    """
    CLI usage:
        python decision_analytics.py [date_str]
        python decision_analytics.py 2026-02-23
        python decision_analytics.py          # uses today's date
    """
    import sys
    date_arg   = sys.argv[1] if len(sys.argv) > 1 else None
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir   = os.path.join(script_dir, "data")
    output_dir = os.path.join(script_dir, "output")

    da = DecisionAnalytics(data_dir=data_dir, output_dir=output_dir)
    outputs = da.run(date_str=date_arg)

    print("\n=== Decision Analytics Output ===")
    for name, path in outputs.items():
        print(f"  {name:<22} → {path}")
    print(f"  Total: {len(outputs)} reports")


if __name__ == "__main__":
    main()
