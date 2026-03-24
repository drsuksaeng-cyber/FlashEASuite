"""
Backtester Engine — bar-by-bar position management with vectorized signals.
Matches MT5 Strategy Tester behavior for bar-level backtests.
"""
import numpy as np
import pandas as pd

from engine.metrics import BacktestResult
from strategies.base import BaseStrategy


def run_backtest(
    df: pd.DataFrame,
    strategy: BaseStrategy,
    params: dict,
    initial_equity: float = 10000.0,
    risk_pct: float = 1.0,
    max_positions: int = 1,
) -> BacktestResult:
    """
    Run backtest on OHLCV data with given strategy and parameters.

    Args:
        df: OHLCV DataFrame
        strategy: strategy instance
        params: strategy parameters
        initial_equity: starting equity
        risk_pct: risk % per trade for position sizing
        max_positions: max concurrent positions (1 for most, >1 for Turtle pyramid)

    Returns:
        BacktestResult with all trades
    """
    # 1. Compute signals (vectorized + stateful loop in strategy)
    signals = strategy.compute_signals(df, params)

    # 2. Walk bars — manage positions
    trades = []
    positions = []  # list of open position dicts
    equity = initial_equity

    close = df["close"].values.astype(float)
    high = df["high"].values.astype(float)
    low = df["low"].values.astype(float)
    sig_arr = signals["signal"].values
    sl_arr = signals["sl_dist"].values
    tp_arr = signals["tp_dist"].values

    for i in range(1, len(df)):
        bar_high = high[i]
        bar_low = low[i]
        bar_close = close[i]

        # Check SL/TP on open positions using current bar high/low
        closed = []
        for pos in positions:
            pnl = None
            exit_price = None
            exit_reason = None

            if pos["dir"] == 1:  # LONG
                if bar_low <= pos["sl"]:
                    exit_price = pos["sl"]
                    exit_reason = "SL"
                elif pos["tp"] > 0 and bar_high >= pos["tp"]:
                    exit_price = pos["tp"]
                    exit_reason = "TP"
            elif pos["dir"] == -1:  # SHORT
                if bar_high >= pos["sl"]:
                    exit_price = pos["sl"]
                    exit_reason = "SL"
                elif pos["tp"] > 0 and bar_low <= pos["tp"]:
                    exit_price = pos["tp"]
                    exit_reason = "TP"

            if exit_price is not None:
                if pos["dir"] == 1:
                    pnl = (exit_price - pos["entry"]) * pos["lot_units"]
                else:
                    pnl = (pos["entry"] - exit_price) * pos["lot_units"]

                trades.append({
                    "entry_bar": pos["entry_bar"],
                    "exit_bar": i,
                    "dir": pos["dir"],
                    "entry": pos["entry"],
                    "exit": exit_price,
                    "sl": pos["sl"],
                    "tp": pos["tp"],
                    "pnl": pnl,
                    "reason": exit_reason,
                })
                equity += pnl
                closed.append(pos)

        for c in closed:
            positions.remove(c)

        # New entry signal
        sig = int(sig_arr[i])
        if sig != 0 and len(positions) < max_positions:
            sl_d = sl_arr[i]
            tp_d = tp_arr[i]
            entry_price = bar_close

            if sl_d <= 0:
                continue

            # Position sizing: risk_pct of equity / SL distance
            risk_money = equity * risk_pct / 100.0
            lot_units = risk_money / sl_d if sl_d > 0 else 0

            if lot_units <= 0:
                continue

            if sig == 1:
                sl_price = entry_price - sl_d
                tp_price = entry_price + tp_d if tp_d > 0 else 0.0
            else:
                sl_price = entry_price + sl_d
                tp_price = entry_price - tp_d if tp_d > 0 else 0.0

            positions.append({
                "dir": sig,
                "entry": entry_price,
                "entry_bar": i,
                "sl": sl_price,
                "tp": tp_price,
                "lot_units": lot_units,
            })

    # Close remaining positions at last bar close
    for pos in positions:
        final_price = close[-1]
        if pos["dir"] == 1:
            pnl = (final_price - pos["entry"]) * pos["lot_units"]
        else:
            pnl = (pos["entry"] - final_price) * pos["lot_units"]
        trades.append({
            "entry_bar": pos["entry_bar"],
            "exit_bar": len(df) - 1,
            "dir": pos["dir"],
            "entry": pos["entry"],
            "exit": final_price,
            "sl": pos["sl"],
            "tp": pos["tp"],
            "pnl": pnl,
            "reason": "EOD",
        })

    result = BacktestResult(trades=trades, initial_equity=initial_equity)
    return result
