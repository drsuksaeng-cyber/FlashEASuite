"""
Optuna Optimizer — TPE sampler with pruning.
"""
import optuna
import pandas as pd
from tabulate import tabulate

from engine.backtester import run_backtest
from strategies.base import BaseStrategy


def optimize(
    df: pd.DataFrame,
    strategy: BaseStrategy,
    n_trials: int = 200,
    initial_equity: float = 10000.0,
    risk_pct: float = 1.0,
    max_positions: int = 1,
    study_name: str | None = None,
    storage: str | None = None,
    verbose: bool = True,
) -> tuple[dict, optuna.Study]:
    """
    Run Optuna optimization.

    Returns:
        (best_params, study)
    """
    def _suggest(trial, space):
        params = {}
        for key, (ptype, lo, hi) in space.items():
            if ptype == "int":
                params[key] = trial.suggest_int(key, lo, hi)
            elif ptype == "float":
                params[key] = trial.suggest_float(key, lo, hi)
        return params

    def objective(trial):
        params = _suggest(trial, strategy.param_space)
        result = run_backtest(df, strategy, params, initial_equity, risk_pct, max_positions)
        score = result.score()

        # Report intermediate metrics for pruning
        trial.set_user_attr("PF", result.profit_factor)
        trial.set_user_attr("DD%", result.max_drawdown_pct)
        trial.set_user_attr("trades", result.total_trades)
        trial.set_user_attr("WR%", result.win_rate * 100)
        trial.set_user_attr("profit", result.net_profit)

        return score

    sampler = optuna.samplers.TPESampler(seed=42)
    pruner = optuna.pruners.MedianPruner(n_startup_trials=20)

    if study_name is None:
        study_name = f"opt_{strategy.name}"

    study = optuna.create_study(
        study_name=study_name,
        direction="maximize",
        sampler=sampler,
        pruner=pruner,
        storage=storage,
        load_if_exists=True,
    )

    log_level = optuna.logging.WARNING if not verbose else optuna.logging.INFO
    optuna.logging.set_verbosity(log_level)

    study.optimize(objective, n_trials=n_trials, show_progress_bar=verbose)

    best = study.best_trial
    best_params = best.params

    if verbose:
        print(f"\n{'=' * 60}")
        print(f"  Optimization Complete: {strategy_name}")
        print(f"{'=' * 60}")
        print(f"  Best Score : {best.value:.4f}")
        print(f"  PF         : {best.user_attrs.get('PF', 0):.2f}")
        print(f"  DD%        : {best.user_attrs.get('DD%', 0):.2f}")
        print(f"  Trades     : {best.user_attrs.get('trades', 0)}")
        print(f"  WR%        : {best.user_attrs.get('WR%', 0):.1f}")
        print(f"  Profit     : ${best.user_attrs.get('profit', 0):.2f}")
        print(f"\n  Best Parameters:")
        for k, v in best_params.items():
            print(f"    {k:20s} = {v}")
        print()

        # Top 10 trials
        trials = sorted(study.trials, key=lambda t: t.value if t.value else 0, reverse=True)[:10]
        rows = []
        for t in trials:
            rows.append({
                "#": t.number,
                "Score": round(t.value, 4) if t.value else 0,
                "PF": round(t.user_attrs.get("PF", 0), 2),
                "DD%": round(t.user_attrs.get("DD%", 0), 2),
                "Trades": t.user_attrs.get("trades", 0),
                "WR%": round(t.user_attrs.get("WR%", 0), 1),
            })
        print("  Top 10 Trials:")
        print(tabulate(rows, headers="keys", tablefmt="grid"))

    return best_params, study
