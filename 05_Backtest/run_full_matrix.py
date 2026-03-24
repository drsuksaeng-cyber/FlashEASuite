#!/usr/bin/env python
"""
FlashEASuite V2 — Full Matrix Runner
29 symbols x 16 strategies x 9 TFs = 4,176 combinations

Phase 1: SCREEN (default params, no optimize) -> filter viable combos
Phase 2: OPTIMIZE (Optuna 100 trials) -> only on survivors
Phase 3: WALK-FORWARD -> validate

Usage:
    python run_full_matrix.py                    # full run
    python run_full_matrix.py --screen-only      # just screen, no optimize
    python run_full_matrix.py --skip-fetch       # use cached data only
"""
import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from data.mt5_fetcher import fetch_ohlcv
from strategies.base import discover_strategies
from engine.backtester import run_backtest
from optimize.optuna_runner import optimize
from optimize.walk_forward import run_walk_forward

OUTPUT_DIR = Path(__file__).parent.parent / "output"
OUTPUT_DIR.mkdir(exist_ok=True)

# 28 major forex pairs + XAUUSD
SYMBOLS = [
    "EURUSD.tp", "GBPUSD.tp", "USDJPY.tp", "USDCHF.tp", "USDCAD.tp", "AUDUSD.tp", "NZDUSD.tp",
    "EURGBP.tp", "EURJPY.tp", "EURCHF.tp", "EURAUD.tp", "EURCAD.tp", "EURNZD.tp",
    "GBPJPY.tp", "GBPCHF.tp", "GBPAUD.tp", "GBPCAD.tp", "GBPNZD.tp",
    "AUDJPY.tp", "AUDNZD.tp", "AUDCAD.tp", "AUDCHF.tp",
    "NZDJPY.tp", "NZDCAD.tp", "NZDCHF.tp",
    "CADJPY.tp", "CADCHF.tp", "CHFJPY.tp",
    "XAUUSD.tp",
]

TIMEFRAMES = ["M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1"]
# Note: MN1 excluded — yfinance/MT5 monthly data too sparse for meaningful backtest

# Screen filter thresholds
SCREEN_MIN_TRADES = 10
SCREEN_MIN_PF = 0.8


def fetch_all_data(symbols, timeframes, skip_fetch=False):
    """Fetch and cache data for all symbol/TF combos."""
    data_map = {}
    total = len(symbols) * len(timeframes)
    done = 0
    failed = 0

    for sym in symbols:
        for tf in timeframes:
            done += 1
            key = f"{sym}_{tf}"
            try:
                df = fetch_ohlcv(sym, tf, source="mt5" if not skip_fetch else "auto")
                if len(df) >= 100:
                    data_map[key] = df
                else:
                    failed += 1
            except Exception as e:
                failed += 1
                if done <= 5 or done % 50 == 0:
                    print(f"  [{done}/{total}] {sym} {tf}: FAIL ({e})")

            if done % 20 == 0:
                print(f"  Fetched {done}/{total} ({failed} failed)")

    print(f"\nData fetch complete: {len(data_map)}/{total} OK, {failed} failed")
    return data_map


def run_screen(data_map, strategies):
    """Phase 1: Quick screen with default params."""
    results = []
    total = len(data_map) * len(strategies)
    done = 0
    t0 = time.time()

    for data_key, df in sorted(data_map.items()):
        parts = data_key.rsplit("_", 1)
        sym = parts[0]
        tf = parts[1]

        for sk, strategy in sorted(strategies.items()):
            done += 1
            try:
                result = run_backtest(df, strategy, strategy.default_params(),
                                       max_positions=strategy.max_positions)
                summary = result.summary()
                summary["symbol"] = sym
                summary["tf"] = tf
                summary["strategy"] = strategy.name
                summary["strategy_key"] = sk
                results.append(summary)
            except Exception:
                pass

            if done % 500 == 0:
                elapsed = time.time() - t0
                rate = done / elapsed
                eta = (total - done) / rate if rate > 0 else 0
                print(f"  Screen: {done}/{total} ({elapsed:.0f}s elapsed, ETA {eta:.0f}s)")

    elapsed = time.time() - t0
    print(f"\nScreen complete: {len(results)} combos in {elapsed:.0f}s")
    return results


def filter_screen(results):
    """Filter screen results for viable combos."""
    viable = [r for r in results
              if r["trades"] >= SCREEN_MIN_TRADES and r["PF"] >= SCREEN_MIN_PF and r["profit"] > 0]
    print(f"Screen filter: {len(viable)}/{len(results)} pass (trades>={SCREEN_MIN_TRADES}, PF>={SCREEN_MIN_PF}, profit>0)")
    return viable


def run_optimize_phase(data_map, strategies, viable_combos, n_trials=100):
    """Phase 2: Optimize viable combos."""
    results = []
    total = len(viable_combos)
    t0 = time.time()

    for i, combo in enumerate(viable_combos):
        sym = combo["symbol"]
        tf = combo["tf"]
        sk = combo["strategy_key"]
        strategy = strategies[sk]
        data_key = f"{sym}_{tf}"
        df = data_map.get(data_key)

        if df is None:
            continue

        print(f"\n  [{i+1}/{total}] Optimize: {strategy.name} {sym} {tf}")

        try:
            best_params, study = optimize(
                df, strategy, n_trials=n_trials,
                max_positions=strategy.max_positions, verbose=False,
            )

            result = run_backtest(df, strategy, best_params,
                                   max_positions=strategy.max_positions)
            summary = result.summary()
            summary["symbol"] = sym
            summary["tf"] = tf
            summary["strategy"] = strategy.name
            summary["strategy_key"] = sk
            summary["best_params"] = best_params
            summary["optimized"] = True

            # Walk-forward
            wf_results = run_walk_forward(df, strategy, best_params,
                                           max_positions=strategy.max_positions)
            oos_pfs = [r["OOS_PF"] for r in wf_results if r["OOS_trades"] > 0]
            wf_pass_count = sum(1 for pf in oos_pfs if pf >= 1.0) if oos_pfs else 0
            wf_total = len(oos_pfs)
            wf_avg_pf = sum(oos_pfs) / len(oos_pfs) if oos_pfs else 0
            summary["wf_status"] = "PASS" if wf_pass_count >= wf_total * 0.6 and wf_avg_pf >= 1.2 else "FAIL"
            summary["wf_avg_pf"] = round(wf_avg_pf, 2)
            summary["wf_pass"] = f"{wf_pass_count}/{wf_total}"

            results.append(summary)

            status = summary["wf_status"]
            print(f"    PF={summary['PF']:.2f} DD={summary['DD%']:.1f}% WF={status} ({summary['wf_pass']})")

        except Exception as e:
            print(f"    ERROR: {e}")

    elapsed = time.time() - t0
    print(f"\nOptimize complete: {len(results)} combos in {elapsed:.0f}s")
    return results


def save_results(screen_results, opt_results, timestamp):
    """Save all results to JSON."""
    screen_path = OUTPUT_DIR / f"full_screen_{timestamp}.json"
    screen_path.write_text(json.dumps(screen_results, indent=2, default=str))

    if opt_results:
        opt_path = OUTPUT_DIR / f"full_optimize_{timestamp}.json"
        opt_path.write_text(json.dumps(opt_results, indent=2, default=str))

    # Update best_params_all.json for report generator
    if opt_results:
        best_map = {}
        for r in opt_results:
            key = f"{r['strategy']}|{r['symbol']}|{r['tf']}"
            best_map[key] = {
                "strategy": r["strategy"],
                "symbol": r["symbol"],
                "tf": r["tf"],
                "score": r["Score"],
                "pf": r["PF"],
                "dd": r["DD%"],
                "trades": r["trades"],
                "wr": r["WR%"],
                "profit": r["profit"],
                "profit_per_year": round(r["profit"] / 5.0, 2),
                "annual_return_pct": round(r["profit"] / 5.0 / 100, 1),
                "wf_status": r.get("wf_status", "N/A"),
                "wf_avg_pf": r.get("wf_avg_pf", 0),
                "wf_pass": r.get("wf_pass", "0/0"),
                "params": r.get("best_params", {}),
            }
        bp_path = OUTPUT_DIR / "best_params_all.json"
        bp_path.write_text(json.dumps(best_map, indent=2, default=str))

    print(f"Results saved to {OUTPUT_DIR}")


def main():
    parser = argparse.ArgumentParser(description="FlashEASuite Full Matrix Runner")
    parser.add_argument("--screen-only", action="store_true", help="Only run screen, skip optimize")
    parser.add_argument("--skip-fetch", action="store_true", help="Use cached data only")
    parser.add_argument("--trials", type=int, default=100, help="Optuna trials per combo")
    parser.add_argument("--symbols", default=None, help="Override symbols (comma-separated)")
    parser.add_argument("--tf", default=None, help="Override timeframes (comma-separated)")
    args = parser.parse_args()

    symbols = args.symbols.split(",") if args.symbols else SYMBOLS
    timeframes = args.tf.split(",") if args.tf else TIMEFRAMES
    strategies = discover_strategies()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")

    total_combos = len(symbols) * len(timeframes) * len(strategies)
    print(f"FlashEASuite V2 — Full Matrix")
    print(f"  Symbols:    {len(symbols)}")
    print(f"  Timeframes: {len(timeframes)} ({','.join(timeframes)})")
    print(f"  Strategies: {len(strategies)}")
    print(f"  Total:      {total_combos} combinations")
    print(f"  Timestamp:  {timestamp}")
    print()

    # Phase 0: Fetch data
    print("=" * 60)
    print("  PHASE 0: Fetching Data")
    print("=" * 60)
    data_map = fetch_all_data(symbols, timeframes, args.skip_fetch)

    # Phase 1: Screen
    print("\n" + "=" * 60)
    print("  PHASE 1: Screening (default params)")
    print("=" * 60)
    screen_results = run_screen(data_map, strategies)
    viable = filter_screen(screen_results)

    # Save screen results
    save_results(screen_results, None, timestamp)

    if args.screen_only:
        print("\n-- Screen only mode. Done. --")
        # Print top 30
        viable.sort(key=lambda x: x["Score"], reverse=True)
        print("\nTop 30 by Score:")
        for i, r in enumerate(viable[:30]):
            print(f"  {i+1:2d}. {r['strategy']:22s} {r['symbol']:14s} {r['tf']:3s} | "
                  f"PF={r['PF']:6.2f} DD={r['DD%']:5.1f}% trades={r['trades']:5d} Score={r['Score']:.2f}")
        return

    # Phase 2: Optimize + WF
    print("\n" + "=" * 60)
    print(f"  PHASE 2: Optimize ({len(viable)} viable combos, {args.trials} trials each)")
    print("=" * 60)
    opt_results = run_optimize_phase(data_map, strategies, viable, args.trials)

    # Save
    save_results(screen_results, opt_results, timestamp)

    # Generate HTML report
    try:
        from generate_report import generate_html
        generate_html()
    except Exception as e:
        print(f"Report generation failed: {e}")

    # Summary
    wf_pass = [r for r in opt_results if r.get("wf_status") == "PASS"]
    print(f"\n{'=' * 60}")
    print(f"  COMPLETE")
    print(f"  Screen:   {len(screen_results)} tested, {len(viable)} viable")
    print(f"  Optimize: {len(opt_results)} optimized, {len(wf_pass)} WF PASS")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
