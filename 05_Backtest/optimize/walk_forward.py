"""
Anchored Walk-Forward Validation.
Train window expands; test window slides forward.
"""
from datetime import datetime
from dataclasses import dataclass

import pandas as pd
from tabulate import tabulate

from engine.backtester import run_backtest
from engine.metrics import BacktestResult
from strategies.base import BaseStrategy


@dataclass
class WFWindow:
    train_start: datetime
    train_end: datetime
    test_start: datetime
    test_end: datetime


def generate_windows(
    data_start: datetime,
    data_end: datetime,
    min_train_years: float = 3.0,
    test_months: int = 6,
    n_windows: int = 5,
) -> list[WFWindow]:
    """Generate anchored walk-forward windows."""
    windows = []
    total_days = (data_end - data_start).days
    train_days = int(min_train_years * 365)
    test_days = test_months * 30

    for i in range(n_windows):
        t_end_days = train_days + i * test_days
        if t_end_days + test_days > total_days:
            break

        train_end = data_start + pd.Timedelta(days=t_end_days)
        test_start = train_end
        test_end = test_start + pd.Timedelta(days=test_days)

        windows.append(WFWindow(
            train_start=data_start,
            train_end=train_end,
            test_start=test_start,
            test_end=min(test_end, data_end),
        ))

    return windows


def run_walk_forward(
    df: pd.DataFrame,
    strategy: BaseStrategy,
    best_params: dict,
    windows: list[WFWindow] | None = None,
    initial_equity: float = 10000.0,
    risk_pct: float = 1.0,
    max_positions: int = 1,
) -> list[dict]:
    """
    Run walk-forward validation with fixed params across windows.

    Returns list of dicts with IS and OOS metrics per window.
    """
    if windows is None:
        dstart = df["time"].iloc[0].to_pydatetime()
        dend = df["time"].iloc[-1].to_pydatetime()
        windows = generate_windows(dstart, dend)

    results = []
    for w in windows:
        # Split data
        train_mask = (df["time"] >= w.train_start) & (df["time"] < w.train_end)
        test_mask = (df["time"] >= w.test_start) & (df["time"] < w.test_end)
        df_train = df[train_mask].reset_index(drop=True)
        df_test = df[test_mask].reset_index(drop=True)

        if len(df_train) < 100 or len(df_test) < 20:
            continue

        # Run on train (IS)
        is_result = run_backtest(df_train, strategy, best_params,
                                  initial_equity, risk_pct, max_positions)
        # Run on test (OOS)
        oos_result = run_backtest(df_test, strategy, best_params,
                                   initial_equity, risk_pct, max_positions)

        results.append({
            "window": f"{w.train_start:%Y-%m} → {w.test_end:%Y-%m}",
            "train_bars": len(df_train),
            "test_bars": len(df_test),
            "IS_trades": is_result.total_trades,
            "IS_PF": round(is_result.profit_factor, 2),
            "IS_DD%": round(is_result.max_drawdown_pct, 2),
            "OOS_trades": oos_result.total_trades,
            "OOS_PF": round(oos_result.profit_factor, 2),
            "OOS_DD%": round(oos_result.max_drawdown_pct, 2),
            "OOS_profit": round(oos_result.net_profit, 2),
        })

    return results


def print_wf_results(results: list[dict], strategy_name: str = ""):
    """Pretty-print walk-forward results table."""
    if not results:
        print("No walk-forward results.")
        return

    print(f"\n{'=' * 70}")
    print(f"  Walk-Forward Validation: {strategy_name}")
    print(f"{'=' * 70}")
    print(tabulate(results, headers="keys", tablefmt="simple_grid", floatfmt=".2f"))

    # Summary
    oos_pfs = [r["OOS_PF"] for r in results if r["OOS_trades"] > 0]
    if oos_pfs:
        avg_pf = sum(oos_pfs) / len(oos_pfs)
        pass_count = sum(1 for pf in oos_pfs if pf >= 1.0)
        total = len(oos_pfs)
        status = "PASS" if pass_count >= total * 0.6 and avg_pf >= 1.2 else "FAIL"
        print(f"\n  OOS Avg PF: {avg_pf:.2f} | Pass: {pass_count}/{total} | {status}")
    print()
