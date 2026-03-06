#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
setfile_generator.py — MT5 Strategy Tester .set File Generator
FlashEASuite V2 | 02_Brain/core/optimization/

Generates narrow .set files from Brain pre-optimizer results.
Best params ± 2 steps → tight optimization range for MT5.

CRITICAL encoding requirements (from project MEMORY.md):
    - UTF-16 LE with BOM
    - Header line 1: "; saved automatically on YYYY.MM.DD"
    - Header line 2: "; this file contains last used input parameters..."
    - Header line 3: ";"
    - Double pipe separator: "||"
    - String params declared LAST → numeric Y flags preserved

Author: FlashEASuite V2 Dev
"""

from __future__ import annotations

import logging
import math
from datetime import date
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ..strategy.adaptive_params import PARAM_BOUNDS, STRATEGY_DEFAULTS

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# PARAM MAP — Brain internal name → Opt EA .set file variable name
# ─────────────────────────────────────────────────────────────────────────────
#
# Layout per strategy:
#   "optimised" : {brain_key: (set_file_param_name, default_value, is_float)}
#   "fixed"     : [(set_file_param_name, value)]   — appear as N (no Y flag)
#   "ea_level"  : [(set_file_param_name, value, optimise)]  — EA-level inputs
#   "string"    : [(set_file_param_name, value)]    — must be LAST (no Y flag)
#
# For "ea_level": optimise=True → generates tight range with Y; False → N.

STRATEGY_CONFIG: Dict[str, dict] = {

    "S06": {
        # Only entry params optimised (Period, ER_Thresh) — TP/SL fixed at Brain best.
        # 5 × 5 = 25 passes  (vs 625 if TP/SL were also optimised)
        "optimised": {
            "S06_KAMA_PERIOD": ("KAMA_Period",    25,   False),  # int
            "S06_ER_THRESH":   ("KAMA_ER_Thresh", 0.5,  True),   # float
        },
        # TP/SL fixed at best_params value (no range, N flag)
        "fixed_from_params": [
            ("KAMA_TP_ATR", "S06_TP_ATR", 3.0, True),
            ("KAMA_SL_ATR", "S06_SL_ATR", 1.5, True),
        ],
        "fixed": [
            ("KAMA_Fast",       2),
            ("KAMA_Slow",       30),
            ("KAMA_ATR_Period", 14),
        ],
        "ea_level": [
            ("Inp_RiskPct",       1.0,  False),
            ("Inp_MinConfidence", 0.3,  False),
            ("Inp_MaxPositions",  1,    False),
            ("Inp_Slippage",      10,   False),
            ("Inp_UseOnTester",   "true",  False),
            ("Inp_UseKAMAExit",   "true",  False),
        ],
        "string": [],
        "ea_name": "Opt_S06_KAMA",
    },

    "S10": {
        "optimised": {
            "S10_ENTRY_PERIOD": ("Turtle_EntryPeriod", 20,  False),
            "S10_EXIT_PERIOD":  ("Turtle_ExitPeriod",  10,  False),
            "S10_BREAKOUT_BUF": ("Turtle_BreakoutBuf", 0.1, True),
        },
        "fixed": [
            ("Turtle_ATR_Period",  20),
            ("Turtle_MaxUnits",    4),
            ("Turtle_UnitSpacing", 0.5),
            ("Turtle_RiskPct",     1.0),
        ],
        "ea_level": [
            ("Inp_RiskPct",       1.0, False),
            ("Inp_MinConfidence", 0.4, False),
            ("Inp_MaxPositions",  4,   False),
            ("Inp_Slippage",      10,  False),
            ("Inp_UseOnTester",   "true", False),
        ],
        "string": [],
        "ea_name": "Opt_S10_Turtle",
    },

    "S01": {
        "optimised": {
            # EA-level optimised params come first (before string params)
            "S01_PERIOD":  ("StatArb_Period",  20,  False),
            "S01_ENTRY_Z": ("StatArb_EntryZ",  2.0, True),
            "S01_STOP_Z":  ("StatArb_StopZ",   3.0, True),
        },
        "fixed": [],
        "ea_level": [
            # Tuple format: (set_name, current, do_optimise[, lo, step, hi])
            # These appear FIRST in the .set (before strategy params)
            ("Inp_RiskPct",       1.0,    True,  0.25, 0.25, 1.0),
            ("Inp_MinConfidence", 0.4,    True,  0.3,  0.1,  0.6),
            ("Inp_MaxPositions",  1,      False),
            ("Inp_Slippage",      10,     False),
            ("Inp_UseOnTester",   "true", False),
        ],
        "string": [
            # String params MUST be last — they break Y-flag chain if not
            ("StatArb_Pair1", "EURUSD.tp"),
            ("StatArb_Pair2", "GBPUSD.tp"),
        ],
        "ea_name": "Opt_S01_StatArb",
        "ea_level_first": True,  # EA-level before strategy params
    },

    "S14": {
        # Only entry params optimised (BB, KC, Squeeze) — SL/TP fixed at Brain best.
        # 5 × 5 × 4 = 100 passes  (vs 2500 if SL/TP were also optimised)
        "optimised": {
            "S14_BB_PERIOD":   ("BS_BB_Period",    20,  False),
            "S14_KC_ATR_MULT": ("BS_KC_ATR_Mult",  1.5, True),
            "S14_SQUEEZE_MIN": ("BS_Squeeze_Min",  6,   False),
        },
        # SL/TP: fixed at Brain best_params value (no Y flag, no range)
        "fixed_from_params": [
            ("BS_SL_ATR_Mult", "S14_SL_ATR",  2.0, True),
            ("BS_TP_ATR_Mult", "S14_TP_ATR",  3.0, True),
        ],
        "fixed": [
            ("BS_BB_Deviation",  2.0),
            ("BS_KC_Period",     20),
            ("BS_Breakout_Mom",  0.1),   # 0.1 = slope/ATR threshold (0.5 caused 0 trades)
            ("BS_ATR_Period",    14),
            ("BS_LR_Period",     14),
        ],
        "ea_level": [
            ("Inp_RiskPct",       1.0, False),
            ("Inp_MinConfidence", 0.0, False),  # standalone: no Brain confidence, gated by BS_Breakout_Mom only
            ("Inp_MaxPositions",  1,   False),
            ("Inp_Slippage",      10,  False),
            ("Inp_UseOnTester",   "true", False),
        ],
        "string": [],
        "ea_name": "Opt_S14_BBSqueeze",
    },

    "S15": {
        # Optimise: MaxPositions × MinConfidence × TP_ATR = 5×5×4 = 100 passes
        # RiskPct and SL_ATR fixed — Grid profits from many small wins, not TP/SL tuning
        "optimised": {
            "S15_MAX_ORDERS":    ("Inp_MaxPositions",  5,   False),
            "S15_CONF_THRESHOLD":("Inp_MinConfidence", 0.3, True),
        },
        "fixed": [],
        "ea_level": [
            # (set_name, current, do_optimise[, lo, step, hi])
            ("Inp_RiskPct",      0.5,    False),                   # fixed — not optimised
            ("Inp_TP_ATR_Mult",  2.0,    True,  1.5,  0.5,  3.0), # 4 values
            ("Inp_SL_ATR_Mult",  1.5,    False),                   # fixed
            ("Inp_Slippage",     10,     False),
            ("Inp_UseOnTester",  "true", False),
            ("Inp_TrailEnabled", "false", False),
        ],
        "string": [],
        "ea_name": "Opt_S15_Grid",
        "ea_level_first": True,
    },
}

# Maps strategy_id to the EA-level optimised params (key=brain_param or ea_param)
# S15 has max_orders → Inp_MaxPositions and conf_threshold → Inp_MinConfidence
# Those are handled via STRATEGY_CONFIG optimised dict


class SetFileGenerator:
    """
    Generates MT5 Strategy Tester .set files from Brain pre-optimizer results.

    Usage:
        gen = SetFileGenerator()
        content = gen.generate("S06", best_params, "EURUSD", "H1")
        path    = gen.write("S06", content, profiles_path, "EURUSD", "H1")
    """

    def generate(
        self,
        strategy_id: str,
        best_params: dict,
        symbol: str = "EURUSD",
        tf_label: str = "H1",
    ) -> str:
        """
        Generate .set file content as a string.

        Parameters
        ----------
        strategy_id : e.g. "S06"
        best_params : dict of Brain internal param names → best values
        symbol      : e.g. "EURUSD" (used for string param defaults)
        tf_label    : e.g. "H1" (informational)

        Returns
        -------
        Full .set file content as string (no BOM).
        """
        if strategy_id not in STRATEGY_CONFIG:
            raise ValueError(f"SetFileGenerator: unknown strategy {strategy_id}")

        config = STRATEGY_CONFIG[strategy_id]
        ea_name = config["ea_name"]
        ea_level_first = config.get("ea_level_first", False)

        lines: List[str] = []
        lines.append(self._generate_header(ea_name))

        # ── Build parameter lines ─────────────────────────────────────────

        if ea_level_first:
            # EA-level params first (S01, S15)
            lines += self._build_ea_level_lines(config, best_params)
            lines += self._build_optimised_lines(strategy_id, config, best_params)
        else:
            # Strategy params first (S06, S10, S14)
            lines += self._build_optimised_lines(strategy_id, config, best_params)
            lines += self._build_fixed_from_params_lines(config, best_params)
            lines += self._build_fixed_lines(config)
            lines += self._build_ea_level_lines(config, best_params)

        # Fixed params (only for non-ea_level_first strategies; already added above for others)
        if ea_level_first:
            lines += self._build_fixed_lines(config)

        # String params LAST (critical for Y-flag preservation)
        lines += self._build_string_lines(config, symbol)

        return "\n".join(lines) + "\n"

    def write(
        self,
        strategy_id: str,
        content: str,
        profiles_path: str,
        symbol: str = "EURUSD",
        tf_label: str = "H1",
    ) -> str:
        """
        Write .set file to MT5 Profiles/Tester directory as UTF-16 LE with BOM.

        Returns path of written file.
        """
        filename = f"Opt_{strategy_id}_{symbol}_{tf_label}_brain.set"
        out_path = Path(profiles_path) / filename
        out_path.parent.mkdir(parents=True, exist_ok=True)

        # Python's 'utf-16' codec automatically writes BOM + LE on little-endian systems
        out_path.write_text(content, encoding="utf-16")

        logger.info("[SetFileGen] Written: %s", out_path)
        return str(out_path)

    # ──────────────────────────────────────────────────────────────────────
    # LINE BUILDERS
    # ──────────────────────────────────────────────────────────────────────

    def _generate_header(self, ea_name: str) -> str:
        today = date.today().strftime("%Y.%m.%d")
        return (
            f"; saved automatically on {today}\n"
            f"; this file contains last used input parameters for testing/optimizing {ea_name} expert advisor\n"
            f";"
        )

    def _build_optimised_lines(
        self,
        strategy_id: str,
        config: dict,
        best_params: dict,
    ) -> List[str]:
        """Build lines for optimised params with Y flag and tight range."""
        lines = []
        for brain_key, (set_name, default_val, is_float) in config["optimised"].items():
            bounds = PARAM_BOUNDS.get(brain_key)
            current = best_params.get(brain_key, default_val)

            if bounds is not None:
                lo, hi, step = bounds
                start = max(lo, current - 2 * step)
                stop  = min(hi, current + 2 * step)
                lines.append(
                    self._fmt_param(set_name, current, start, step, stop, optimise=True)
                )
            else:
                lines.append(
                    self._fmt_param(set_name, current, current, 0, current, optimise=False)
                )
        return lines

    def _build_fixed_from_params_lines(self, config: dict, best_params: dict) -> List[str]:
        """
        Build N-flagged lines for params that should be fixed at best_params value.

        Config entry tuple: (set_name, brain_key, default_val, is_float)
        Value comes from best_params[brain_key] if present, else default_val.
        """
        lines = []
        for entry in config.get("fixed_from_params", []):
            set_name, brain_key, default_val, _is_float = entry
            val = best_params.get(brain_key, default_val)
            lines.append(
                self._fmt_param(set_name, val, val, 0, val, optimise=False)
            )
        return lines

    def _build_fixed_lines(self, config: dict) -> List[str]:
        """Build lines for fixed (non-optimised) strategy params with N flag."""
        lines = []
        for set_name, default_val in config.get("fixed", []):
            lines.append(
                self._fmt_param(set_name, default_val, default_val, 0, default_val, optimise=False)
            )
        return lines

    def _build_ea_level_lines(self, config: dict, best_params: dict) -> List[str]:
        """
        Build lines for EA-level inputs.

        Entry tuple format:
            (set_name, current, do_optimise)               — fixed range
            (set_name, current, do_optimise, lo, step, hi) — explicit range (Y params)
        """
        lines = []
        for entry in config.get("ea_level", []):
            set_name    = entry[0]
            default_val = entry[1]
            do_optimise = entry[2]

            if do_optimise and len(entry) == 6:
                _, _, _, lo, step, hi = entry
                lines.append(
                    self._fmt_param(set_name, default_val, lo, step, hi, optimise=True)
                )
            else:
                lines.append(
                    self._fmt_param(set_name, default_val, default_val, 0, default_val,
                                    optimise=False)
                )
        return lines

    # Correlated pair map for S01 StatArb: Pair1 (chart symbol) -> Pair2 (hedge pair)
    _STATARB_PAIR2: Dict[str, str] = {
        "EURUSD": "GBPUSD.tp",
        "GBPUSD": "EURUSD.tp",
        "USDJPY": "EURJPY.tp",
        "EURJPY": "GBPJPY.tp",
        "GBPJPY": "EURJPY.tp",
        "AUDUSD": "NZDUSD.tp",
        "NZDUSD": "AUDUSD.tp",
        "AUDJPY": "NZDJPY.tp",
        "XAUUSD": "EURUSD.tp",
    }

    def _build_string_lines(self, config: dict, symbol: str) -> List[str]:
        """Build lines for string params (no Y flag, must be last)."""
        lines = []
        for set_name, default_val in config.get("string", []):
            if set_name == "StatArb_Pair1":
                default_val = f"{symbol}.tp"
            elif set_name == "StatArb_Pair2":
                # Use the correlated pair, not the same symbol as Pair1
                default_val = self._STATARB_PAIR2.get(symbol.upper(), default_val)
            lines.append(f"{set_name}={default_val}")
        return lines

    # ──────────────────────────────────────────────────────────────────────
    # FORMAT HELPERS
    # ──────────────────────────────────────────────────────────────────────

    @staticmethod
    def _fmt_param(
        name: str,
        current: Any,
        start: Any,
        step: Any,
        stop: Any,
        optimise: bool,
    ) -> str:
        """
        Format a single .set file parameter line.

        Format: Name=current||start||step||stop||Y_or_N

        Booleans and strings are formatted without the range part.
        """
        flag = "Y" if optimise else "N"

        # Boolean inputs (MT5 uses true/false lowercase)
        if isinstance(current, str) and current.lower() in ("true", "false"):
            return f"{name}={current}||false||0||true||N"

        # Determine float decimal places from the step value.
        # Use string-based counting to avoid log10 issues with values like 0.25.
        def _decimal_places(v: float) -> int:
            if v == 0:
                return 0
            s = f"{v:.10f}".rstrip("0")
            if "." in s:
                return len(s.split(".")[1])
            return 0

        step_decimals = _decimal_places(float(step)) if step != 0 else 0

        def fmt(v: Any) -> str:
            if isinstance(v, bool):
                return str(v).lower()
            if isinstance(v, int):
                return str(v)
            if isinstance(v, float):
                if step_decimals == 0:
                    # Fixed param: show as int if whole, else use generic float
                    if v == int(v):
                        return str(int(v))
                    return f"{v:g}"  # strips trailing zeros
                return f"{v:.{step_decimals}f}"
            return str(v)

        return f"{name}={fmt(current)}||{fmt(start)}||{fmt(step)}||{fmt(stop)}||{flag}"
