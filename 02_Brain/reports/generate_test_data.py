#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — Test Data Generator (P7-2 + P7-3)
=====================================================
สร้าง sample data files ใน data/ subfolder เพื่อทดสอบ:
  - decision_analytics.py  (P7-2)
  - retrain_reporter.py    (P7-3)

วิธีใช้:
    python generate_test_data.py

ผลลัพธ์ (สร้างใน ./data/):
    trades_2026-02-23.csv
    regimes_2026-02-23.jsonl
    decisions_2026-02-23.jsonl
    retrain_events_2026-02-23.jsonl
    model_metrics_2026-02-23.jsonl
    feature_importance_2026-02-23.jsonl
    council_weights_2026-02-23.jsonl

Author: Claude AI for Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-23
"""

import os
import csv
import json
import random
from datetime import datetime, timedelta

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
random.seed(42)
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
DATE_STR = "2026-02-23"

SYMBOLS    = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCHF"]
STRATEGIES = ["S01", "S07", "S10", "S13", "S14", "S15", "S16"]
MM_METHODS = ["MM01", "MM02", "MM03", "MM05", "MM07"]
REGIMES    = ["trending", "ranging", "volatile"]
ML_MODELS  = ["random_forest", "xgboost", "lstm", "kmeans", "hmm"]
FEATURES   = ["rsi", "atr", "ema_diff", "volume", "spread",
               "bb_width", "macd_hist", "stoch_k", "adx", "obv"]


def rand_time(date_str: str, idx: int) -> str:
    """สุ่ม timestamp ภายในวันที่กำหนด"""
    base = datetime.strptime(date_str, "%Y-%m-%d").replace(hour=0, minute=0)
    offset = timedelta(minutes=idx * 17 + random.randint(0, 10))
    return (base + offset).strftime("%Y-%m-%d %H:%M")


# ===========================================================================
# 1. trades_<date>.csv  (สำหรับ decision_analytics.py)
# ===========================================================================
def generate_trades(n: int = 80) -> str:
    path = os.path.join(DATA_DIR, f"trades_{DATE_STR}.csv")
    fieldnames = [
        "timestamp", "symbol", "strategy", "mm_method",
        "direction", "lot", "entry", "exit", "pnl",
        "confidence", "regime", "reasoning_correct",
    ]
    rows = []
    for i in range(n):
        sym      = random.choice(SYMBOLS)
        strategy = random.choice(STRATEGIES)
        regime   = random.choice(REGIMES)
        conf     = round(random.uniform(0.45, 0.95), 3)
        direction = random.choice(["BUY", "SELL"])
        lot      = round(random.choice([0.01, 0.05, 0.1, 0.2]), 2)
        entry    = round(random.uniform(1.05, 1.30) if "JPY" not in sym else 148.0 + random.uniform(-2, 2), 4)
        # PnL: สัมพันธ์กับ confidence บ้าง
        win_prob = conf * 0.8 + 0.1          # high conf → win more
        win      = random.random() < win_prob
        pnl      = round(random.uniform(5, 50) if win else -random.uniform(5, 40), 2)
        exit_px  = round(entry + (pnl * 0.0001 * (1 if direction == "BUY" else -1)), 4)
        # reasoning_correct: สัมพันธ์กับ win บ้าง
        reasoning_correct = (win and random.random() < 0.85) or (not win and random.random() < 0.20)

        rows.append({
            "timestamp":         rand_time(DATE_STR, i),
            "symbol":            sym,
            "strategy":          strategy,
            "mm_method":         random.choice(MM_METHODS),
            "direction":         direction,
            "lot":               lot,
            "entry":             entry,
            "exit":              exit_px,
            "pnl":               pnl,
            "confidence":        conf,
            "regime":            regime,
            "reasoning_correct": str(reasoning_correct),
        })

    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"  ✅ {path}  ({n} trades)")
    return path


# ===========================================================================
# 2. regimes_<date>.jsonl  (สำหรับ decision_analytics.py — Regime Accuracy)
# ===========================================================================
def generate_regimes(n: int = 100) -> str:
    path = os.path.join(DATA_DIR, f"regimes_{DATE_STR}.jsonl")
    records = []
    for i in range(n):
        actual  = random.choice(REGIMES)
        # Rule: แม่นประมาณ 65%
        rule    = actual if random.random() < 0.65 else random.choice(REGIMES)
        # RF:   แม่นประมาณ 72%
        rf      = actual if random.random() < 0.72 else random.choice(REGIMES)
        # HMM:  แม่นประมาณ 68%
        hmm     = actual if random.random() < 0.68 else random.choice(REGIMES)
        # Ensemble: majority vote
        votes   = [rule, rf, hmm]
        ensemble = max(set(votes), key=votes.count)
        records.append({
            "timestamp":        rand_time(DATE_STR, i),
            "symbol":           random.choice(SYMBOLS),
            "rule_regime":      rule,
            "rf_regime":        rf,
            "hmm_regime":       hmm,
            "ensemble_regime":  ensemble,
            "actual_regime":    actual,
        })

    with open(path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    print(f"  ✅ {path}  ({n} regime predictions)")
    return path


# ===========================================================================
# 3. decisions_<date>.jsonl  (optional — สำหรับ decision_analytics.py)
# ===========================================================================
def generate_decisions(n: int = 50) -> str:
    path = os.path.join(DATA_DIR, f"decisions_{DATE_STR}.jsonl")
    records = []
    for i in range(n):
        strategy   = random.choice(STRATEGIES)
        conf       = round(random.uniform(0.50, 0.95), 3)
        pred_dir   = random.choice(["BUY", "SELL"])
        outcome_ok = random.random() < conf * 0.8
        actual_dir = pred_dir if outcome_ok else ("SELL" if pred_dir == "BUY" else "BUY")
        records.append({
            "timestamp":           rand_time(DATE_STR, i),
            "symbol":              random.choice(SYMBOLS),
            "strategy":            strategy,
            "predicted_direction": pred_dir,
            "actual_direction":    actual_dir,
            "confidence":          conf,
            "council_vote":        conf,
            "regime":              random.choice(REGIMES),
            "reasoning_text":      f"Signal based on {random.choice(FEATURES)} and {random.choice(FEATURES)} crossover.",
            "outcome_correct":     outcome_ok,
        })

    with open(path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    print(f"  ✅ {path}  ({n} decision records)")
    return path


# ===========================================================================
# 4. retrain_events_<date>.jsonl  (สำหรับ retrain_reporter.py)
# ===========================================================================
def generate_retrain_events() -> str:
    path = os.path.join(DATA_DIR, f"retrain_events_{DATE_STR}.jsonl")
    reasons = ["scheduled", "accuracy_drop", "regime_shift", "data_drift", "manual"]
    events = []
    base_time = datetime.strptime(DATE_STR, "%Y-%m-%d").replace(hour=6)
    for i, model in enumerate(ML_MODELS):
        prev_acc = round(random.uniform(0.70, 0.85), 4)
        # scheduled retrain biasกำไร, accuracy_drop ลด
        reason   = random.choice(reasons)
        delta    = random.uniform(0.01, 0.05) if reason != "accuracy_drop" else -random.uniform(0.01, 0.04)
        new_acc  = round(min(max(prev_acc + delta, 0.55), 0.95), 4)
        ts       = (base_time + timedelta(hours=i * 3)).strftime("%Y-%m-%d %H:%M")
        events.append({
            "timestamp":             ts,
            "model_name":            model,
            "trigger_reason":        reason,
            "previous_accuracy":     prev_acc,
            "new_accuracy":          new_acc,
            "training_samples":      random.randint(3000, 8000),
            "validation_samples":    random.randint(500, 1500),
            "training_duration_sec": round(random.uniform(20.0, 120.0), 1),
            "hyperparams_changed":   random.random() < 0.3,
            "notes":                 f"{reason} trigger — model retrained on latest {random.randint(7, 30)}-day window",
        })

    with open(path, "w", encoding="utf-8") as f:
        for e in events:
            f.write(json.dumps(e) + "\n")

    print(f"  ✅ {path}  ({len(events)} retrain events)")
    return path


# ===========================================================================
# 5. model_metrics_<date>.jsonl  (สำหรับ retrain_reporter.py)
# ===========================================================================
def generate_model_metrics(days: int = 14) -> str:
    path = os.path.join(DATA_DIR, f"model_metrics_{DATE_STR}.jsonl")
    records = []
    base_date = datetime.strptime(DATE_STR, "%Y-%m-%d") - timedelta(days=days - 1)

    for model in ML_MODELS:
        # เริ่มจาก accuracy สุ่ม แล้ว random walk ทุกวัน
        acc = round(random.uniform(0.68, 0.82), 4)
        for day_idx in range(days):
            ts  = (base_date + timedelta(days=day_idx)).strftime("%Y-%m-%d")
            acc = round(min(max(acc + random.uniform(-0.015, 0.015), 0.55), 0.95), 4)
            f1  = round(acc + random.uniform(-0.03, 0.03), 4)
            auc = round(acc + random.uniform(0.02, 0.08), 4)
            records.append({
                "timestamp":        ts,
                "model_name":       model,
                "accuracy":         acc,
                "precision":        round(f1 + random.uniform(-0.02, 0.02), 4),
                "recall":           round(f1 + random.uniform(-0.02, 0.02), 4),
                "f1_score":         f1,
                "auc_roc":          min(auc, 0.99),
                "val_accuracy":     round(acc - random.uniform(0.01, 0.05), 4),
                "eval_window_days": 7,
            })

    with open(path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    total = len(records)
    print(f"  ✅ {path}  ({total} metric snapshots — {days} days × {len(ML_MODELS)} models)")
    return path


# ===========================================================================
# 6. feature_importance_<date>.jsonl  (สำหรับ retrain_reporter.py)
# ===========================================================================
def generate_feature_importance(snapshots: int = 7) -> str:
    path = os.path.join(DATA_DIR, f"feature_importance_{DATE_STR}.jsonl")
    records = []
    base_date = datetime.strptime(DATE_STR, "%Y-%m-%d") - timedelta(days=snapshots - 1)

    for model in ["random_forest", "xgboost"]:   # feature importance available สำหรับ tree models
        # กำหนด base importance สำหรับ features แต่ละตัว
        base_imp = {feat: round(random.uniform(0.03, 0.25), 4) for feat in FEATURES}
        # Normalize ให้รวม = 1
        total = sum(base_imp.values())
        base_imp = {k: round(v / total, 6) for k, v in base_imp.items()}

        for snap_idx in range(snapshots):
            ts = (base_date + timedelta(days=snap_idx)).strftime("%Y-%m-%d")
            # random walk ทีละ snapshot
            features = {}
            for feat in FEATURES:
                delta = random.uniform(-0.02, 0.02)
                base_imp[feat] = round(max(base_imp[feat] + delta, 0.005), 6)
                features[feat] = base_imp[feat]
            # Re-normalize
            total = sum(features.values())
            features = {k: round(v / total, 6) for k, v in features.items()}
            records.append({
                "timestamp":  ts,
                "model_name": model,
                "features":   features,
            })

    with open(path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    print(f"  ✅ {path}  ({len(records)} importance snapshots)")
    return path


# ===========================================================================
# 7. council_weights_<date>.jsonl  (สำหรับ retrain_reporter.py)
# ===========================================================================
def generate_council_weights(events: int = 10) -> str:
    path = os.path.join(DATA_DIR, f"council_weights_{DATE_STR}.jsonl")
    records = []
    triggers = ["scheduled", "regime_shift", "accuracy_drop", "manual"]
    base_date = datetime.strptime(DATE_STR, "%Y-%m-%d") - timedelta(days=events - 1)

    # Initial weights
    weights = {s: round(random.uniform(0.05, 0.15), 4) for s in STRATEGIES}
    # Normalize
    total = sum(weights.values())
    weights = {k: round(v / total, 6) for k, v in weights.items()}

    for ev_idx in range(events):
        ts      = (base_date + timedelta(days=ev_idx)).strftime("%Y-%m-%d")
        regime  = random.choice(REGIMES)
        trigger = random.choice(triggers)
        # Adjust weights เล็กน้อย
        for s in STRATEGIES:
            weights[s] = round(max(weights[s] + random.uniform(-0.02, 0.02), 0.01), 6)
        # Re-normalize
        total = sum(weights.values())
        weights = {k: round(v / total, 6) for k, v in weights.items()}
        records.append({
            "timestamp": ts,
            "trigger":   trigger,
            "regime":    regime,
            "weights":   dict(weights),
        })

    with open(path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    print(f"  ✅ {path}  ({len(records)} weight snapshots — {len(STRATEGIES)} strategies each)")
    return path


# ===========================================================================
# Main
# ===========================================================================
def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    print(f"📁 Creating test data in: {DATA_DIR}\n")

    print("--- P7-2: Decision Analytics data ---")
    generate_trades(n=80)
    generate_regimes(n=100)
    generate_decisions(n=50)

    print("\n--- P7-3: Retrain Reporter data ---")
    generate_retrain_events()
    generate_model_metrics(days=14)
    generate_feature_importance(snapshots=7)
    generate_council_weights(events=10)

    print("\n✅ All test data generated.")
    print(f"\n📌 Now run:")
    print(f"   python decision_analytics.py {DATE_STR}")
    print(f"   python retrain_reporter.py   {DATE_STR}")
    print(f"\n📂 Reports will be saved to: {os.path.join(os.path.dirname(DATA_DIR), 'output')}")


if __name__ == "__main__":
    main()
