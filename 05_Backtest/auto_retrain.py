#!/usr/bin/env python
"""
FlashEASuite V2 -- Auto Retrain Scheduler
Runs periodically to:
1. Fetch latest data from MT5
2. Re-optimize all strategies
3. Compare old vs new params
4. Update deploy .set files if improved
5. Optionally push to Brain CONFIG_PUSH

Usage:
    # One-shot retrain
    python auto_retrain.py

    # Run every 7 days (loop mode)
    python auto_retrain.py --loop --interval 7

    # Windows Task Scheduler (recommended):
    schtasks /create /tn "FlashEA_Retrain" /tr "python auto_retrain.py" /sc weekly /d SUN /st 06:00
"""
import argparse
import json
import time
import codecs
from datetime import datetime
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent))

from data.mt5_fetcher import fetch_ohlcv
from strategies.base import discover_strategies
from engine.backtester import run_backtest
from optimize.optuna_runner import optimize
from optimize.walk_forward import run_walk_forward

# Auto-discover all strategies
STRATEGIES = discover_strategies()

SYMBOLS = ["USDJPY.tp", "XAUUSD.tp", "GBPUSD.tp"]
TIMEFRAMES = ["H1", "H4"]
N_TRIALS = 200
RESULTS_DIR = Path(__file__).parent.parent / "output"
RESULTS_DIR.mkdir(exist_ok=True)
PRESETS_DIR = Path("C:/Users/drsuk/AppData/Roaming/MetaQuotes/Terminal/B2C22A9C2EA0D03B7096C9AF7E852052/MQL5/Presets")
HISTORY_FILE = RESULTS_DIR / "retrain_history.json"


def load_history() -> dict:
    if HISTORY_FILE.exists():
        return json.loads(HISTORY_FILE.read_text())
    return {}


def save_history(history: dict):
    HISTORY_FILE.write_text(json.dumps(history, indent=2, default=str))


def run_retrain(n_trials: int = N_TRIALS, verbose: bool = True):
    """Run full retrain cycle."""
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M")
    history = load_history()
    results = []

    for sym in SYMBOLS:
        for tf in TIMEFRAMES:
            # Fetch latest data (use cache if recent)
            try:
                df = fetch_ohlcv(sym, tf, source="auto", use_cache=True)
            except Exception as e:
                print(f"[SKIP] {sym} {tf}: {e}")
                continue

            if len(df) < 500:
                print(f"[SKIP] {sym} {tf}: only {len(df)} bars")
                continue

            for sk, strategy in STRATEGIES.items():
                max_pos = strategy.max_positions
                key = f"{sk}_{sym}_{tf}"

                print(f"\n{'='*50}")
                print(f"  Optimizing: {key}")
                print(f"{'='*50}")

                # Optimize
                try:
                    best_params, study = optimize(
                        df, strategy,
                        n_trials=n_trials,
                        max_positions=max_pos,
                        verbose=verbose,
                    )
                except Exception as e:
                    print(f"[ERROR] {key}: {e}")
                    continue

                # Full backtest with best params
                result = run_backtest(df, strategy, best_params, max_positions=max_pos)
                summary = result.summary()

                # Walk-forward
                wf_results = run_walk_forward(
                    df, strategy, best_params, max_positions=max_pos
                )
                oos_pfs = [r["OOS_PF"] for r in wf_results if r["OOS_trades"] > 0]
                wf_pass_count = sum(1 for pf in oos_pfs if pf >= 1.0) if oos_pfs else 0
                wf_total = len(oos_pfs)
                wf_avg_pf = sum(oos_pfs) / len(oos_pfs) if oos_pfs else 0.0
                wf_status = "PASS" if wf_pass_count >= wf_total * 0.6 and wf_avg_pf >= 1.2 else "FAIL"

                # Compare with previous
                prev = history.get(key, {})
                prev_score = prev.get("score", 0)
                new_score = summary["Score"]
                improved = new_score > prev_score

                entry = {
                    "timestamp": timestamp,
                    "params": best_params,
                    "score": new_score,
                    "pf": summary["PF"],
                    "dd": summary["DD%"],
                    "trades": summary["trades"],
                    "wr": summary["WR%"],
                    "wf_status": wf_status,
                    "wf_avg_pf": round(wf_avg_pf, 2),
                    "wf_pass": f"{wf_pass_count}/{wf_total}",
                    "improved": improved,
                }

                results.append({**entry, "key": key})

                status = "IMPROVED" if improved else "same"
                print(f"  Score: {new_score:.2f} (prev: {prev_score:.2f}) [{status}]")
                print(f"  WF: {wf_status} ({wf_pass_count}/{wf_total}, avg PF={wf_avg_pf:.2f})")

                # Update history if improved AND WF passed
                if improved and wf_status == "PASS":
                    history[key] = entry
                    print(f"  -> UPDATED best params for {key}")

    save_history(history)

    # Save run results
    run_file = RESULTS_DIR / f"retrain_{timestamp}.json"
    run_file.write_text(json.dumps(results, indent=2, default=str))
    print(f"\nResults saved: {run_file}")

    # Summary
    print(f"\n{'='*60}")
    print(f"  RETRAIN SUMMARY - {timestamp}")
    print(f"{'='*60}")
    improved_count = sum(1 for r in results if r.get("improved") and r.get("wf_status") == "PASS")
    total = len(results)
    print(f"  Total combos: {total}")
    print(f"  Improved + WF PASS: {improved_count}")
    print(f"  History saved: {HISTORY_FILE}")

    return results


def main():
    parser = argparse.ArgumentParser(description="FlashEASuite Auto Retrain")
    parser.add_argument("--trials", type=int, default=200, help="Optuna trials per combo")
    parser.add_argument("--loop", action="store_true", help="Run in loop mode")
    parser.add_argument("--interval", type=int, default=7, help="Days between retrains (loop mode)")
    parser.add_argument("--quiet", action="store_true", help="Less verbose output")
    args = parser.parse_args()

    if args.loop:
        print(f"Auto-retrain loop: every {args.interval} days")
        while True:
            run_retrain(args.trials, verbose=not args.quiet)
            next_run = args.interval * 86400
            print(f"\nNext retrain in {args.interval} days. Sleeping...")
            time.sleep(next_run)
    else:
        run_retrain(args.trials, verbose=not args.quiet)


if __name__ == "__main__":
    main()
