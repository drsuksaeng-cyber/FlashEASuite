#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_preopt.py — Brain Pre-Optimizer CLI Entry Point
FlashEASuite V2 | 02_Brain/

Runs a fast Python parameter search on yfinance OHLCV data before
launching MT5 Strategy Tester, generating narrow .set files so MT5
validates only the best neighborhoods (~20-50 passes vs 400-1200).

Usage:
    python run_preopt.py                              # all strategies, default symbols
    python run_preopt.py --strategies S06 S10         # specific strategies
    python run_preopt.py --symbols EURUSD XAUUSD      # specific symbols
    python run_preopt.py --trials 500                 # more trials per combo
    python run_preopt.py --interval 4h                # different timeframe
    python run_preopt.py --period 1y                  # shorter history
    python run_preopt.py --profiles C:\\path\\to\\Tester  # custom profiles path

Examples:
    # Quick smoke test (fast)
    python run_preopt.py --strategies S06 --symbols EURUSD --trials 50

    # Full run with H4 data
    python run_preopt.py --interval 4h --trials 300

    # Generate files for specific pair
    python run_preopt.py --strategies S10 --symbols XAUUSD --trials 200

Author: FlashEASuite V2 Dev
"""

from __future__ import annotations

import argparse
import logging
import math
import sys
import time
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Add 02_Brain to sys.path so relative imports work when running directly
# ─────────────────────────────────────────────────────────────────────────────
_BRAIN_DIR = Path(__file__).resolve().parent
if str(_BRAIN_DIR) not in sys.path:
    sys.path.insert(0, str(_BRAIN_DIR))

from core.optimization.pre_optimizer import (
    BrainPreOptimizer,
    SUPPORTED_STRATEGIES,
    YFINANCE_MAP,
    INTERVAL_TF_MAP,
)

# ─────────────────────────────────────────────────────────────────────────────
# Logging setup
# ─────────────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Brain Pre-Optimizer — Fast parameter search before MT5 Strategy Tester",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--strategies",
        nargs="+",
        default=["S01", "S06", "S10", "S14", "S15"],
        metavar="S",
        help=f"Strategies to optimize. Choices: {SUPPORTED_STRATEGIES}",
    )
    parser.add_argument(
        "--symbols",
        nargs="+",
        default=["EURUSD", "XAUUSD", "GBPUSD"],
        metavar="SYM",
        help=f"Symbols to test. Choices: {list(YFINANCE_MAP.keys())}",
    )
    parser.add_argument(
        "--trials",
        type=int,
        default=300,
        metavar="N",
        help="Number of random trials per (strategy, symbol) pair (default: 300)",
    )
    parser.add_argument(
        "--interval",
        default="1h",
        choices=list(INTERVAL_TF_MAP.keys()),
        help="OHLCV bar interval (default: 1h)",
    )
    parser.add_argument(
        "--period",
        default="2y",
        help="Historical data period for yfinance (default: 2y)",
    )
    parser.add_argument(
        "--profiles",
        default=None,
        metavar="PATH",
        help="MT5 Profiles\\Tester directory path. Auto-detected if not specified.",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        metavar="PATH",
        help="Directory for preopt_results.json (default: 02_Brain/core/optimization/)",
    )
    parser.add_argument(
        "--no-setfiles",
        action="store_true",
        help="Skip .set file generation (JSON results only)",
    )
    parser.add_argument(
        "--export-only",
        action="store_true",
        help="Skip optimization — reload preopt_results.json and regenerate .set files only",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)",
    )
    return parser


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY TABLE
# ─────────────────────────────────────────────────────────────────────────────

def print_summary(results: dict) -> None:
    """Print a formatted summary table of pre-optimization results."""
    print()
    print("=" * 90)
    print(f"{'Strategy':<10} {'Symbol':<10} {'Score':>8} {'Trials':>7} "
          f"{'Top Params':<40} {'Regime Distribution'}")
    print("-" * 90)

    for strategy_id, sym_dict in results.items():
        for symbol, r in sym_dict.items():
            if "error" in r:
                print(f"{strategy_id:<10} {symbol:<10}  {'ERROR':<8}  —  {r['error'][:50]}")
                continue

            best      = r.get("overall_best", {})
            score     = best.get("score", 0.0)
            params    = best.get("params", {})
            regime_d  = r.get("regime_distribution", {})
            history   = r.get("score_history", [])
            n_nonzero = sum(1 for s in history if s > 0)

            # Format top params (show only optimised ones, abbreviated)
            param_str = _format_params_short(params, strategy_id)

            # Format regime distribution
            regime_str = " ".join(
                f"{k[:3]}={v:.0%}" for k, v in sorted(regime_d.items(), key=lambda x: -x[1])
            )

            print(f"{strategy_id:<10} {symbol:<10} {score:>8.3f} {n_nonzero:>7} "
                  f"{param_str:<40} {regime_str}")

    print("=" * 90)
    print()


def _format_params_short(params: dict, strategy_id: str) -> str:
    """Format key parameters into a short string for display."""
    from core.optimization.pre_optimizer import STRATEGY_OPT_PARAMS

    opt_keys = STRATEGY_OPT_PARAMS.get(strategy_id, [])
    parts = []
    for key in opt_keys:
        val = params.get(key)
        if val is None:
            continue
        # Abbreviate key name
        short_key = key.split("_", 2)[-1] if "_" in key else key
        if isinstance(val, float):
            parts.append(f"{short_key}={val:.2f}")
        else:
            parts.append(f"{short_key}={val}")
    return " ".join(parts)


def print_per_regime_detail(results: dict) -> None:
    """Print per-regime best parameters for each (strategy, symbol)."""
    print()
    print("Per-Regime Best Parameters:")
    print("-" * 70)

    for strategy_id, sym_dict in results.items():
        for symbol, r in sym_dict.items():
            if "error" in r:
                continue
            per_regime = r.get("per_regime_best", {})
            if not per_regime:
                continue

            print(f"\n  {strategy_id} / {symbol}:")
            for regime, info in per_regime.items():
                score  = info.get("score", 0.0)
                params = info.get("params", {})
                param_str = _format_params_short(params, strategy_id)
                print(f"    {regime:<12} score={score:.3f}  {param_str}")


def print_setfile_paths(paths: list) -> None:
    """Print generated .set file paths."""
    if not paths:
        return
    print()
    print("Generated .set files:")
    for p in paths:
        print(f"  -> {p}")
    print()


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = build_parser()
    args   = parser.parse_args()

    # Validate strategies
    invalid = [s for s in args.strategies if s not in SUPPORTED_STRATEGIES]
    if invalid:
        logger.error("Unsupported strategies: %s. Valid: %s", invalid, SUPPORTED_STRATEGIES)
        return 1

    # Validate symbols
    valid_symbols = list(YFINANCE_MAP.keys())
    invalid_sym = [s for s in args.symbols if s.upper() not in valid_symbols]
    if invalid_sym:
        logger.error("Unknown symbols: %s. Valid: %s", invalid_sym, valid_symbols)
        return 1

    print()
    print("=" * 70)
    print("  Brain Pre-Optimizer - FlashEASuite V2")
    print("=" * 70)

    optimizer = BrainPreOptimizer(seed=args.seed)

    # ── Export-only mode: reload saved JSON and regenerate .set files ─────
    if args.export_only:
        json_dir  = args.output_dir or str(Path(__file__).parent / "core" / "optimization")
        json_path = Path(json_dir) / "preopt_results.json"
        if not json_path.exists():
            logger.error("--export-only: preopt_results.json not found at %s", json_path)
            return 1
        import json
        with open(json_path, encoding="utf-8") as f:
            results = json.load(f)
        logger.info("Loaded existing results from %s", json_path)
        print(f"  Mode       : EXPORT ONLY (reloading {json_path})")
        print("=" * 70)
        print()
        generated_paths = optimizer.export_results(
            results=results,
            output_dir=args.output_dir,
            profiles_path=args.profiles,
        )
        print_setfile_paths(generated_paths)
        return 0

    print(f"  Strategies : {args.strategies}")
    print(f"  Symbols    : {args.symbols}")
    print(f"  Trials     : {args.trials} per combo")
    print(f"  Interval   : {args.interval}")
    print(f"  Period     : {args.period}")
    print(f"  Seed       : {args.seed}")
    print("=" * 70)
    print()

    total_combos = len(args.strategies) * len(args.symbols)
    logger.info("Starting pre-optimization: %d combos x %d trials = %d evaluations",
                total_combos, args.trials, total_combos * args.trials)

    t_start = time.time()

    results = optimizer.run_all(
        strategies=args.strategies,
        symbols=args.symbols,
        n_trials=args.trials,
        period=args.period,
        interval=args.interval,
    )

    elapsed = time.time() - t_start
    logger.info("Pre-optimization complete in %.1f seconds", elapsed)

    # Print summary table
    print_summary(results)
    print_per_regime_detail(results)

    # Export results
    generated_paths: list = []
    if not args.no_setfiles:
        try:
            generated_paths = optimizer.export_results(
                results=results,
                output_dir=args.output_dir,
                profiles_path=args.profiles,
            )
            print_setfile_paths(generated_paths)
        except Exception as exc:
            logger.error("Export failed: %s", exc)
    else:
        # Still save JSON
        try:
            optimizer.export_results(
                results=results,
                output_dir=args.output_dir,
                profiles_path=None,
            )
        except Exception as exc:
            logger.error("JSON export failed: %s", exc)

    # Final pass-count estimate
    if generated_paths:
        print("Pass count estimates (narrow range vs original):")
        _print_pass_estimates(results, args)

    return 0


def _print_pass_estimates(results: dict, args) -> None:
    """Estimate MT5 optimization pass counts for generated .set files."""
    from core.optimization.pre_optimizer import STRATEGY_OPT_PARAMS
    from core.strategy.adaptive_params import PARAM_BOUNDS

    print()
    for strategy_id in args.strategies:
        opt_params = STRATEGY_OPT_PARAMS.get(strategy_id, [])
        passes = 1
        param_counts = []
        for key in opt_params:
            bounds = PARAM_BOUNDS.get(key)
            if bounds is None:
                continue
            _, _, step = bounds
            # Tight range: ±2 steps = 5 values per param
            n_values = 5
            passes *= n_values
            param_counts.append(f"{key.split('_', 2)[-1]}(5)")

        print(f"  {strategy_id}: {' x '.join(param_counts)} = {passes} passes  "
              f"(vs original: higher)")


if __name__ == "__main__":
    sys.exit(main())
