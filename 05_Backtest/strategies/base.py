"""
Base Strategy Interface for Python backtester.
Auto-discovery: any subclass of BaseStrategy is automatically registered.

To add a new strategy:
  1. Create strategies/sXX_name.py
  2. Define class that inherits BaseStrategy
  3. Set name, max_positions, param_space
  4. Implement compute_signals() and default_params()
  5. Done! No other files need editing.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass
import importlib
import pkgutil
from pathlib import Path

import pandas as pd


# Global registry — auto-populated by subclass __init_subclass__
_REGISTRY: dict[str, type] = {}


@dataclass
class Signal:
    direction: int  # 1=BUY, -1=SELL, 0=NONE
    sl_dist: float  # SL distance from entry (always positive)
    tp_dist: float  # TP distance from entry (0 = no fixed TP)
    confidence: float


class BaseStrategy(ABC):
    name: str = "BaseStrategy"
    max_positions: int = 1           # Override for pyramid/grid strategies
    param_space: dict = {}           # Optuna search space {key: (type, lo, hi)}

    def __init_subclass__(cls, **kwargs):
        """Auto-register every concrete subclass."""
        super().__init_subclass__(**kwargs)
        if cls.name != "BaseStrategy":
            # Short key: "S06", "S14", etc. (first 3 chars of name)
            short = cls.name.split("_")[0] if "_" in cls.name else cls.name
            _REGISTRY[short] = cls

    @abstractmethod
    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        """
        Compute signals for entire dataset.

        Returns DataFrame with columns: signal, sl_dist, tp_dist, confidence
        """
        pass

    @abstractmethod
    def default_params(self) -> dict:
        """Return default parameter values."""
        pass


def discover_strategies() -> dict[str, BaseStrategy]:
    """
    Import all strategy modules in strategies/ folder,
    triggering __init_subclass__ auto-registration.
    Returns dict of {short_key: instance}.
    """
    pkg_dir = Path(__file__).parent
    for _, module_name, _ in pkgutil.iter_modules([str(pkg_dir)]):
        if module_name.startswith("s") and module_name != "base":
            try:
                importlib.import_module(f"strategies.{module_name}")
            except Exception as e:
                print(f"[WARN] Failed to load strategies.{module_name}: {e}")

    return {key: cls() for key, cls in _REGISTRY.items()}


def get_param_spaces() -> dict[str, dict]:
    """Get all param spaces from registered strategies."""
    spaces = {}
    for key, cls in _REGISTRY.items():
        inst = cls()
        if inst.param_space:
            spaces[inst.name] = inst.param_space
    return spaces
