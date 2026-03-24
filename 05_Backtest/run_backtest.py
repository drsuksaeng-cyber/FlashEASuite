#!/usr/bin/env python
"""
FlashEASuite V2 — Python Backtester CLI
Usage:
    python run_backtest.py --strategy S14 --symbol XAUUSD.tp --tf H1
    python run_backtest.py --strategy S06 --symbol USDJPY.tp --tf H4 --optimize 200
    python run_backtest.py --strategy S10 --symbol USDJPY.tp --tf H4 --optimize 300 --wf
    python run_backtest.py --strategy all --symbol XAUUSD.tp,USDJPY.tp,GBPUSD.tp --tf H1,H4 --optimize 200 --wf
"""
import argparse
import sys
from datetime import datetime
from pathlib import Path

# Add parent to path so imports work
sys.path.insert(0, str(Path(__file__).parent.parent))

from tabulate import tabulate

from data.mt5_fetcher import fetch_ohlcv
from strategies.s06_kama import S06KAMA
from strategies.s10_turtle import S10Turtle
from strategies.s14_bbsqueeze import S14BBSqueeze
from engine.backtester import run_backtest
from optimize.optuna_runner import optimize
from optimize.walk_forward import run_walk_forward, print_wf_results

STRATEGIES = {
    "S06": S06KAMA(),
    "S10": S10Turtle(),
    "S14": S14BBSqueeze(),
}


def main():
    parser = argparse.ArgumentParser(description="FlashEASuite V2 Python Backtester")
    parser.add_argument("--strategy", "-s", default="S14", help="S06/S10/S14/all")
    parser.add_argument("--symbol", default="XAUUSD.tp", help="Symbol(s) comma-separated")
    parser.add_argument("--tf", default="H1", help="Timeframe(s) comma-separated")
    parser.add_argument("--start", default=None, help="Start date YYYY-MM-DD (default: 5y ago)")
    parser.add_argument("--end", default=None, help="End date YYYY-MM-DD (default: now)")
    parser.add_argument("--optimize", "-o", type=int, default=0, help="Optuna trials (0=skip)")
    parser.add_argument("--wf", action="store_true", help="Run walk-forward validation")
    parser.add_argument("--equity", type=float, default=10000.0, help="Initial equity")
    parser.add_argument("--risk", type=float, default=1.0, help="Risk %% per trade")
    parser.add_argument("--csv", default=None, help="Load CSV instead of MT5")
    args = parser.parse_args()

    start = datetime.strptime(args.start, "%Y-%m-%d") if args.start else None
    end = datetime.strptime(args.end, "%Y-%m-%d") if args.end else None

    symbols = [s.strip() for s in args.symbol.split(",")]
    timeframes = [t.strip() for t in args.tf.split(",")]
    strat_keys = list(STRATEGIES.keys()) if args.strategy.lower() == "all" else [args.strategy.upper()]

    all_results = []

    for sym in symbols:
        for tf in timeframes:
            # Load data
            print(f"\n{'#' * 60}")
            print(f"  {sym} {tf}")
            print(f"{'#' * 60}")

            if args.csv:
                from data.mt5_fetcher import load_csv
                df = load_csv(args.csv)
            else:
                df = fetch_ohlcv(sym, tf, start, end)

            print(f"  Data: {len(df)} bars | {df['time'].iloc[0]} → {df['time'].iloc[-1]}")

            for sk in strat_keys:
                strategy = STRATEGIES[sk]
                max_pos = 3 if sk == "S10" else 1

                print(f"\n  --- {strategy.name} ---")

                if args.optimize > 0:
                    # Optuna optimization
                    best_params, study = optimize(
                        df, strategy,
                        n_trials=args.optimize,
                        initial_equity=args.equity,
                        risk_pct=args.risk,
                        max_positions=max_pos,
                    )
                else:
                    best_params = strategy.default_params()

                # Run with best params
                result = run_backtest(df, strategy, best_params,
                                      args.equity, args.risk, max_pos)
                summary = result.summary()
                summary["symbol"] = sym
                summary["tf"] = tf
                summary["strategy"] = strategy.name
                all_results.append(summary)

                print(f"  Result: {summary}")

                # Walk-forward
                if args.wf:
                    wf_results = run_walk_forward(
                        df, strategy, best_params,
                        initial_equity=args.equity,
                        risk_pct=args.risk,
                        max_positions=max_pos,
                    )
                    print_wf_results(wf_results, f"{strategy.name} {sym} {tf}")

    # Final summary table
    if len(all_results) > 1:
        print(f"\n{'=' * 70}")
        print("  FULL RESULTS MATRIX")
        print(f"{'=' * 70}")
        print(tabulate(all_results, headers="keys", tablefmt="simple_grid", floatfmt=".2f"))


if __name__ == "__main__":
    main()
