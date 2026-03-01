#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — P7-3: Retrain Reporter
==========================================
รายงานการ retrain ML models: performance curves, feature importance,
council weight evolution, และ retrain event log

Reads from: 02_Brain/reports/data/
  - retrain_events_*.jsonl   : log ทุกครั้งที่ retrain (when, why, metrics)
  - model_metrics_*.jsonl    : accuracy, f1, auc ต่อ model ต่อ timestamp
  - feature_importance_*.jsonl: feature importance snapshot ต่อ timestamp
  - council_weights_*.jsonl  : council weight evolution ต่อ timestamp

Outputs to: 02_Brain/reports/output/
  - model_performance_<date>.csv
  - feature_importance_<date>.csv
  - council_weights_<date>.csv
  - retrain_events_<date>.csv

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
from typing import Dict, List, Optional, Any

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("RetrainReporter")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ML_MODELS = ["random_forest", "xgboost", "lstm", "kmeans", "hmm"]

STRATEGY_NAMES: Dict[str, str] = {
    "S01": "StatArb",       "S02": "ML_Ensemble",    "S03": "SMC",
    "S04": "MarketProfile", "S05": "SupplyDemand",   "S06": "KAMA",
    "S07": "MeanReversion", "S08": "Intermarket",    "S09": "SessionBreakout",
    "S10": "Turtle",        "S11": "Ichimoku",       "S12": "PriceAction",
    "S13": "FibStoch",      "S14": "BBSqueeze",      "S15": "Grid",
    "S16": "Spike",
}

# Retrain trigger reasons
RETRAIN_REASONS = [
    "accuracy_drop",   # accuracy ต่ำกว่า threshold
    "scheduled",       # retrain ตามกำหนด (weekly/monthly)
    "regime_shift",    # market regime เปลี่ยนอย่างรุนแรง
    "data_drift",      # feature distribution เปลี่ยน
    "manual",          # manual trigger โดย user
]


# ===========================================================================
# 1. Data Loaders
# ===========================================================================

def load_jsonl(path: str, label: str = "records") -> List[Dict]:
    """Generic JSONL loader"""
    records: List[Dict] = []
    if not os.path.exists(path):
        logger.warning(f"{label} file not found: {path}")
        return records
    with open(path, encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as e:
                logger.debug(f"Skip malformed JSON at line {line_num}: {e}")
    logger.info(f"Loaded {len(records)} {label} from {path}")
    return records


def load_retrain_events(path: str) -> List[Dict]:
    """
    โหลด retrain event log

    Expected fields per line:
      timestamp, model_name, trigger_reason, previous_accuracy,
      new_accuracy, training_samples, validation_samples,
      training_duration_sec, hyperparams_changed (bool),
      notes
    """
    return load_jsonl(path, "retrain events")


def load_model_metrics(path: str) -> List[Dict]:
    """
    โหลด model performance metrics over time

    Expected fields per line:
      timestamp, model_name, accuracy, precision, recall,
      f1_score, auc_roc, val_accuracy, eval_window_days
    """
    return load_jsonl(path, "model metrics")


def load_feature_importance(path: str) -> List[Dict]:
    """
    โหลด feature importance snapshots

    Expected fields per line:
      timestamp, model_name, features (dict: {feature_name: importance_score})
    """
    return load_jsonl(path, "feature importance snapshots")


def load_council_weights(path: str) -> List[Dict]:
    """
    โหลด council weight evolution

    Expected fields per line:
      timestamp, weights (dict: {strategy_id: weight}),
      trigger (why weights changed), regime
    """
    return load_jsonl(path, "council weights")


# ===========================================================================
# 2. Model Performance Curve Analyzer
# ===========================================================================

class ModelPerformanceAnalyzer:
    """
    สร้าง accuracy curve ของแต่ละ ML model over time

    Output: หนึ่ง row ต่อ (timestamp × model) — เรียงตาม timestamp
    เพื่อให้ผู้ใช้ plot accuracy curve ได้ใน Excel/Tableau
    """

    def analyze(self, metrics_records: List[Dict]) -> List[Dict]:
        """
        Returns list of rows sorted by timestamp:
          timestamp, model_name, accuracy, precision, recall,
          f1_score, auc_roc, val_accuracy, eval_window_days,
          accuracy_delta (เทียบกับ row ก่อนหน้าของ model เดียวกัน),
          f1_delta
        """
        # Group by model → sorted by timestamp
        by_model: Dict[str, List[Dict]] = defaultdict(list)
        for rec in metrics_records:
            model = rec.get("model_name", "unknown")
            by_model[model].append(rec)

        rows = []
        for model in ML_MODELS:
            model_records = sorted(by_model.get(model, []), key=lambda r: r.get("timestamp", ""))
            prev_acc = None
            prev_f1  = None
            for rec in model_records:
                acc = rec.get("accuracy", 0.0)
                f1  = rec.get("f1_score", 0.0)
                row = {
                    "timestamp":        rec.get("timestamp", ""),
                    "model_name":       model,
                    "accuracy":         round(float(acc), 4),
                    "precision":        round(float(rec.get("precision", 0.0)), 4),
                    "recall":           round(float(rec.get("recall", 0.0)), 4),
                    "f1_score":         round(float(f1), 4),
                    "auc_roc":          round(float(rec.get("auc_roc", 0.0)), 4),
                    "val_accuracy":     round(float(rec.get("val_accuracy", 0.0)), 4),
                    "eval_window_days": rec.get("eval_window_days", 0),
                    "accuracy_delta":   round(float(acc) - prev_acc, 4) if prev_acc is not None else 0.0,
                    "f1_delta":         round(float(f1)  - prev_f1,  4) if prev_f1  is not None else 0.0,
                }
                rows.append(row)
                prev_acc = float(acc)
                prev_f1  = float(f1)

        # Also include any models not in ML_MODELS constant
        for model, model_records in by_model.items():
            if model in ML_MODELS:
                continue
            for rec in sorted(model_records, key=lambda r: r.get("timestamp", "")):
                rows.append({
                    "timestamp":        rec.get("timestamp", ""),
                    "model_name":       model,
                    "accuracy":         round(float(rec.get("accuracy", 0.0)), 4),
                    "precision":        round(float(rec.get("precision", 0.0)), 4),
                    "recall":           round(float(rec.get("recall", 0.0)), 4),
                    "f1_score":         round(float(rec.get("f1_score", 0.0)), 4),
                    "auc_roc":          round(float(rec.get("auc_roc", 0.0)), 4),
                    "val_accuracy":     round(float(rec.get("val_accuracy", 0.0)), 4),
                    "eval_window_days": rec.get("eval_window_days", 0),
                    "accuracy_delta":   0.0,
                    "f1_delta":         0.0,
                })

        # Sort all rows by timestamp then model
        rows.sort(key=lambda r: (r["timestamp"], r["model_name"]))
        return rows


# ===========================================================================
# 3. Feature Importance Change Tracker
# ===========================================================================

class FeatureImportanceTracker:
    """
    ติดตามการเปลี่ยนแปลงของ feature importance ตามเวลา

    สำหรับแต่ละ feature:
      - importance score ณ แต่ละ snapshot
      - rank ณ แต่ละ snapshot
      - delta จาก snapshot ก่อนหน้า
      - trend: "rising" / "falling" / "stable"
    """

    TREND_THRESHOLD = 0.01  # เปลี่ยน > 1% ถือว่า trend ชัด

    def analyze(self, snapshots: List[Dict]) -> List[Dict]:
        """
        Returns one row per (timestamp × model_name × feature):
          timestamp, model_name, feature_name, importance, rank,
          importance_delta, rank_delta, trend
        """
        # Group by model_name → sorted by timestamp
        by_model: Dict[str, List[Dict]] = defaultdict(list)
        for snap in snapshots:
            model = snap.get("model_name", "unknown")
            by_model[model].append(snap)

        rows = []
        for model, model_snaps in sorted(by_model.items()):
            sorted_snaps = sorted(model_snaps, key=lambda s: s.get("timestamp", ""))
            prev_importances: Dict[str, float] = {}
            prev_ranks: Dict[str, int]         = {}

            for snap in sorted_snaps:
                ts       = snap.get("timestamp", "")
                features: Dict[str, float] = snap.get("features", {})
                if not features:
                    continue

                # Compute ranks (1 = most important)
                sorted_features = sorted(features.items(), key=lambda x: x[1], reverse=True)
                ranks = {feat: rank + 1 for rank, (feat, _) in enumerate(sorted_features)}

                for feat, imp in sorted_features:
                    imp_f = float(imp)
                    prev_imp  = prev_importances.get(feat)
                    prev_rank = prev_ranks.get(feat)

                    imp_delta  = round(imp_f - prev_imp,  4) if prev_imp  is not None else 0.0
                    rank_delta = (ranks[feat] - prev_rank)    if prev_rank is not None else 0

                    if prev_imp is not None:
                        if imp_delta > self.TREND_THRESHOLD:
                            trend = "rising"
                        elif imp_delta < -self.TREND_THRESHOLD:
                            trend = "falling"
                        else:
                            trend = "stable"
                    else:
                        trend = "new"

                    rows.append({
                        "timestamp":        ts,
                        "model_name":       model,
                        "feature_name":     feat,
                        "importance":       round(imp_f, 6),
                        "rank":             ranks[feat],
                        "importance_delta": imp_delta,
                        "rank_delta":       rank_delta,
                        "trend":            trend,
                    })

                prev_importances = {f: float(v) for f, v in features.items()}
                prev_ranks       = ranks

        rows.sort(key=lambda r: (r["timestamp"], r["model_name"], r["rank"]))
        return rows


# ===========================================================================
# 4. Council Weight History
# ===========================================================================

class CouncilWeightHistory:
    """
    ติดตาม evolution ของ AI Council weights (weight ของแต่ละ strategy)

    Output: หนึ่ง row ต่อ (timestamp × strategy) — เรียงตาม timestamp
    เพื่อให้เห็นว่า strategy ไหนถูกเพิ่ม/ลด weight ตามเวลา
    """

    def analyze(self, weight_records: List[Dict]) -> List[Dict]:
        """
        Returns one row per (timestamp × strategy_id):
          timestamp, trigger, regime, strategy_id, strategy_name,
          weight, weight_delta, weight_pct (normalized to 100%)
        """
        rows = []
        # Sort by timestamp
        sorted_records = sorted(weight_records, key=lambda r: r.get("timestamp", ""))

        prev_weights: Dict[str, float] = {}

        for rec in sorted_records:
            ts      = rec.get("timestamp", "")
            trigger = rec.get("trigger", "")
            regime  = rec.get("regime", "")
            weights: Dict[str, Any] = rec.get("weights", {})
            if not weights:
                continue

            total_weight = sum(float(v) for v in weights.values())
            total_weight = total_weight if total_weight > 0 else 1.0

            for strategy_id, weight_val in sorted(weights.items()):
                w = float(weight_val)
                prev_w = prev_weights.get(strategy_id)
                delta  = round(w - prev_w, 6) if prev_w is not None else 0.0

                rows.append({
                    "timestamp":     ts,
                    "trigger":       trigger,
                    "regime":        regime,
                    "strategy_id":   strategy_id,
                    "strategy_name": STRATEGY_NAMES.get(strategy_id[:3], strategy_id),
                    "weight":        round(w, 6),
                    "weight_delta":  delta,
                    "weight_pct":    round(w / total_weight * 100, 2),
                })

            prev_weights = {s: float(v) for s, v in weights.items()}

        rows.sort(key=lambda r: (r["timestamp"], r["strategy_id"]))
        return rows


# ===========================================================================
# 5. Retrain Event Log Reporter
# ===========================================================================

class RetrainEventReporter:
    """
    สรุป retrain events: when, why, what changed, impact

    Output: หนึ่ง row ต่อ retrain event เรียงตาม timestamp
    """

    def analyze(self, events: List[Dict]) -> List[Dict]:
        """
        Returns list of rows (sorted by timestamp):
          timestamp, model_name, trigger_reason,
          previous_accuracy, new_accuracy, accuracy_improvement,
          training_samples, validation_samples,
          training_duration_sec, hyperparams_changed,
          notes, impact_category

        impact_category:
          "positive"  : new_accuracy > previous_accuracy + 0.01
          "neutral"   : ±0.01
          "negative"  : new_accuracy < previous_accuracy - 0.01
          "unknown"   : ไม่มีข้อมูล previous accuracy
        """
        rows = []
        for ev in sorted(events, key=lambda e: e.get("timestamp", "")):
            prev_acc = ev.get("previous_accuracy")
            new_acc  = ev.get("new_accuracy")

            if prev_acc is not None and new_acc is not None:
                improvement = round(float(new_acc) - float(prev_acc), 4)
                if improvement > 0.01:
                    impact = "positive"
                elif improvement < -0.01:
                    impact = "negative"
                else:
                    impact = "neutral"
            else:
                improvement = None
                impact      = "unknown"

            rows.append({
                "timestamp":              ev.get("timestamp", ""),
                "model_name":             ev.get("model_name", ""),
                "trigger_reason":         ev.get("trigger_reason", ""),
                "previous_accuracy":      round(float(prev_acc), 4) if prev_acc is not None else "",
                "new_accuracy":           round(float(new_acc),  4) if new_acc  is not None else "",
                "accuracy_improvement":   improvement if improvement is not None else "",
                "training_samples":       ev.get("training_samples", ""),
                "validation_samples":     ev.get("validation_samples", ""),
                "training_duration_sec":  ev.get("training_duration_sec", ""),
                "hyperparams_changed":    ev.get("hyperparams_changed", False),
                "notes":                  ev.get("notes", ""),
                "impact_category":        impact,
            })
        return rows


# ===========================================================================
# 6. CSV Writer
# ===========================================================================

def write_csv(rows: List[Dict], output_path: str) -> None:
    """เขียน list of dict เป็น CSV file"""
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

class RetrainReporter:
    """
    Entry point สำหรับรัน Retrain Reports ทั้งหมด

    Usage:
        reporter = RetrainReporter(
            data_dir="FlashEASuite_V2/02_Brain/reports/data",
            output_dir="FlashEASuite_V2/02_Brain/reports/output"
        )
        outputs = reporter.run(date_str="2026-02-23")
    """

    def __init__(self, data_dir: str = "data", output_dir: str = "output"):
        self.data_dir   = data_dir
        self.output_dir = output_dir

    def _find_files(self, prefix: str, date_str: Optional[str]) -> List[str]:
        """ค้นหาไฟล์ที่ตรงกับ prefix และ date_str"""
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
        date_str:              Optional[str] = None,
        retrain_events_path:   Optional[str] = None,
        model_metrics_path:    Optional[str] = None,
        feature_importance_path: Optional[str] = None,
        council_weights_path:  Optional[str] = None,
    ) -> Dict[str, str]:
        """
        รัน reports ทั้ง 4 ประเภท

        Args:
            date_str:                filter ไฟล์ตาม date เช่น "2026-02-23"
            retrain_events_path:     path ตรงของ retrain events JSONL
            model_metrics_path:      path ตรงของ model metrics JSONL
            feature_importance_path: path ตรงของ feature importance JSONL
            council_weights_path:    path ตรงของ council weights JSONL

        Returns:
            dict {report_name: output_path}
        """
        tag = date_str or datetime.now().strftime("%Y-%m-%d")
        outputs: Dict[str, str] = {}

        # --- Load retrain events ---
        retrain_events: List[Dict] = []
        if retrain_events_path:
            retrain_events = load_retrain_events(retrain_events_path)
        else:
            for p in self._find_files("retrain_events_", date_str):
                retrain_events.extend(load_retrain_events(p))

        # --- Load model metrics ---
        model_metrics: List[Dict] = []
        if model_metrics_path:
            model_metrics = load_model_metrics(model_metrics_path)
        else:
            for p in self._find_files("model_metrics_", date_str):
                model_metrics.extend(load_model_metrics(p))

        # --- Load feature importance ---
        feat_snapshots: List[Dict] = []
        if feature_importance_path:
            feat_snapshots = load_feature_importance(feature_importance_path)
        else:
            for p in self._find_files("feature_importance_", date_str):
                feat_snapshots.extend(load_feature_importance(p))

        # --- Load council weights ---
        weight_records: List[Dict] = []
        if council_weights_path:
            weight_records = load_council_weights(council_weights_path)
        else:
            for p in self._find_files("council_weights_", date_str):
                weight_records.extend(load_council_weights(p))

        if not any([retrain_events, model_metrics, feat_snapshots, weight_records]):
            logger.warning("No data found. Check data_dir or supply explicit paths.")
            return outputs

        # Report 1: ML Model Performance Over Time
        if model_metrics:
            rows = ModelPerformanceAnalyzer().analyze(model_metrics)
            path = os.path.join(self.output_dir, f"model_performance_{tag}.csv")
            write_csv(rows, path)
            outputs["model_performance"] = path

        # Report 2: Feature Importance Changes
        if feat_snapshots:
            rows = FeatureImportanceTracker().analyze(feat_snapshots)
            path = os.path.join(self.output_dir, f"feature_importance_{tag}.csv")
            write_csv(rows, path)
            outputs["feature_importance"] = path

        # Report 3: Council Weight Adjustment History
        if weight_records:
            rows = CouncilWeightHistory().analyze(weight_records)
            path = os.path.join(self.output_dir, f"council_weights_{tag}.csv")
            write_csv(rows, path)
            outputs["council_weights"] = path

        # Report 4: Retrain Event Log
        if retrain_events:
            rows = RetrainEventReporter().analyze(retrain_events)
            path = os.path.join(self.output_dir, f"retrain_events_{tag}.csv")
            write_csv(rows, path)
            outputs["retrain_events"] = path

        logger.info(f"RetrainReporter complete — {len(outputs)} reports generated.")
        return outputs


# ===========================================================================
# 8. CLI
# ===========================================================================

def main() -> None:
    """
    CLI usage:
        python retrain_reporter.py [date_str]
        python retrain_reporter.py 2026-02-23
        python retrain_reporter.py          # uses today's date
    """
    import sys
    date_arg   = sys.argv[1] if len(sys.argv) > 1 else None
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir   = os.path.join(script_dir, "data")
    output_dir = os.path.join(script_dir, "output")

    reporter = RetrainReporter(data_dir=data_dir, output_dir=output_dir)
    outputs  = reporter.run(date_str=date_arg)

    print("\n=== Retrain Reporter Output ===")
    for name, path in outputs.items():
        print(f"  {name:<22} → {path}")
    print(f"  Total: {len(outputs)} reports")


if __name__ == "__main__":
    main()
