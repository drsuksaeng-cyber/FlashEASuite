"""
Backtester Engine — bar-by-bar position management with vectorized signals.
Matches MT5 Strategy Tester behavior for bar-level backtests.
Now includes spread cost on entry and exit.
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
    spread_mode: str = "data",
) -> BacktestResult:
    """
    Run backtest on OHLCV data with given strategy and parameters.

    Args:
        df: OHLCV DataFrame (must have 'spread' column for spread_mode="data")
        strategy: strategy instance
        params: strategy parameters
        initial_equity: starting equity
        risk_pct: risk % per trade for position sizing
        max_positions: max concurrent positions
        spread_mode: "data" = use df['spread'] column (points)
                     "none" = no spread cost (old behavior)

    Returns:
        BacktestResult with all trades
    """
    signals = strategy.compute_signals(df, params)

    trades = []
    positions = []
    equity = initial_equity

    close = df["close"].values.astype(float)
    high = df["high"].values.astype(float)
    low = df["low"].values.astype(float)
    sig_arr = signals["signal"].values
    sl_arr = signals["sl_dist"].values
    tp_arr = signals["tp_dist"].values

    # Spread handling
    has_spread = "spread" in df.columns and spread_mode == "data"
    if has_spread:
        spread_pts = df["spread"].values.astype(float)
        # Estimate point value: use median price to convert spread points to price units
        # For forex: spread in points (e.g. 15 = 1.5 pips for 5-digit)
        # For XAUUSD: spread in points (e.g. 30 = 0.30 USD)
        median_price = np.median(close[close > 0])
        if median_price > 500:
            # Gold/metals: 1 point = 0.01
            point_size = 0.01
        elif median_price > 50:
            # JPY pairs: 1 point = 0.001
            point_size = 0.001
        else:
            # Standard forex: 1 point = 0.00001
            point_size = 0.00001
        spread_price = spread_pts * point_size
    else:
        spread_price = np.zeros(len(df))

    for i in range(1, len(df)):
        bar_high = high[i]
        bar_low = low[i]
        half_spread = spread_price[i] / 2.0  # half spread on each side

        # Check SL/TP on open positions
        closed = []
        for pos in positions:
            exit_price = None
            exit_reason = None

            if pos["dir"] == 1:  # LONG
                # Exit at bid (= price - half_spread)
                effective_low = bar_low - half_spread
                effective_high = bar_high - half_spread
                if effective_low <= pos["sl"]:
                    exit_price = pos["sl"]
                    exit_reason = "SL"
                elif pos["tp"] > 0 and effective_high >= pos["tp"]:
                    exit_price = pos["tp"]
                    exit_reason = "TP"
            elif pos["dir"] == -1:  # SHORT
                # Exit at ask (= price + half_spread)
                effective_high = bar_high + half_spread
                effective_low = bar_low + half_spread
                if effective_high >= pos["sl"]:
                    exit_price = pos["sl"]
                    exit_reason = "SL"
                elif pos["tp"] > 0 and effective_low <= pos["tp"]:
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
                    "spread_cost": pos.get("spread_cost", 0),
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

            if sl_d <= 0:
                continue

            # Entry price includes spread cost
            # BUY at ask (close + half_spread), SELL at bid (close - half_spread)
            hs = half_spread
            if sig == 1:
                entry_price = close[i] + hs  # buy at ask
                sl_price = entry_price - sl_d
                tp_price = entry_price + tp_d if tp_d > 0 else 0.0
            else:
                entry_price = close[i] - hs  # sell at bid
                sl_price = entry_price + sl_d
                tp_price = entry_price - tp_d if tp_d > 0 else 0.0

            # Spread cost per unit (full round-trip)
            spread_cost_per_unit = spread_price[i]

            # Position sizing: risk_pct of equity / SL distance
            risk_money = equity * risk_pct / 100.0
            lot_units = risk_money / sl_d if sl_d > 0 else 0

            if lot_units <= 0:
                continue

            positions.append({
                "dir": sig,
                "entry": entry_price,
                "entry_bar": i,
                "sl": sl_price,
                "tp": tp_price,
                "lot_units": lot_units,
                "spread_cost": spread_cost_per_unit * lot_units,
            })

    # Close remaining positions at last bar close
    for pos in positions:
        final_price = close[-1]
        hs = spread_price[-1] / 2.0 if len(spread_price) > 0 else 0
        if pos["dir"] == 1:
            exit_p = final_price - hs  # close long at bid
            pnl = (exit_p - pos["entry"]) * pos["lot_units"]
        else:
            exit_p = final_price + hs  # close short at ask
            pnl = (pos["entry"] - exit_p) * pos["lot_units"]
        trades.append({
            "entry_bar": pos["entry_bar"],
            "exit_bar": len(df) - 1,
            "dir": pos["dir"],
            "entry": pos["entry"],
            "exit": exit_p,
            "sl": pos["sl"],
            "tp": pos["tp"],
            "pnl": pnl,
            "reason": "EOD",
            "spread_cost": pos.get("spread_cost", 0),
        })

    result = BacktestResult(trades=trades, initial_equity=initial_equity)
    return result
