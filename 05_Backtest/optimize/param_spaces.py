"""
Optuna search spaces per strategy — matches MQL5 input parameter ranges.
"""

PARAM_SPACES = {
    "S14_BBSqueeze": {
        "bb_period":     ("int", 15, 60),
        "bb_deviation":  ("float", 1.5, 3.0),
        "kc_period":     ("int", 10, 40),
        "kc_atr_mult":   ("float", 0.8, 2.0),
        "squeeze_min":   ("int", 3, 12),
        "breakout_mom":  ("float", 0.05, 0.5),
        "sl_atr_mult":   ("float", 1.5, 5.0),
        "tp_atr_mult":   ("float", 1.5, 6.0),
        "atr_period":    ("int", 10, 20),
        "lr_period":     ("int", 8, 20),
    },
    "S06_KAMA": {
        "kama_period":   ("int", 5, 30),
        "kama_fast":     ("int", 2, 5),
        "kama_slow":     ("int", 20, 40),
        "er_threshold":  ("float", 0.10, 0.95),
        "tp_atr_mult":   ("float", 1.5, 6.0),
        "sl_atr_mult":   ("float", 1.0, 4.0),
        "atr_period":    ("int", 10, 20),
    },
    "S10_Turtle": {
        "entry_period":  ("int", 5, 30),
        "exit_period":   ("int", 5, 50),
        "atr_period":    ("int", 14, 25),
        "breakout_buf":  ("float", 0.0, 0.50),
        "max_units":     ("int", 1, 5),
        "unit_spacing":  ("float", 0.25, 1.0),
        "risk_pct":      ("float", 0.1, 1.0),
    },
}


def suggest_params(trial, strategy_name: str) -> dict:
    """Use Optuna trial to suggest params for given strategy."""
    space = PARAM_SPACES[strategy_name]
    params = {}
    for key, (ptype, lo, hi) in space.items():
        if ptype == "int":
            params[key] = trial.suggest_int(key, lo, hi)
        elif ptype == "float":
            params[key] = trial.suggest_float(key, lo, hi)
    return params
