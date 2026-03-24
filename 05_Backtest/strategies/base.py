"""
Base Strategy Interface for Python backtester.
Each strategy implements compute_signals() returning a DataFrame of signals.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass

import pandas as pd


@dataclass
class Signal:
    direction: int  # 1=BUY, -1=SELL, 0=NONE
    sl_dist: float  # SL distance from entry (always positive)
    tp_dist: float  # TP distance from entry (0 = no fixed TP)
    confidence: float


class BaseStrategy(ABC):
    name: str = "BaseStrategy"

    @abstractmethod
    def compute_signals(self, df: pd.DataFrame, params: dict) -> pd.DataFrame:
        """
        Compute signals for entire dataset (vectorized where possible).

        Args:
            df: OHLCV DataFrame with columns: time, open, high, low, close, tick_volume, spread
            params: strategy-specific parameters dict

        Returns:
            DataFrame with same index as df, columns:
                signal    : int (1=BUY, -1=SELL, 0=NONE)
                sl_dist   : float (SL distance, always positive)
                tp_dist   : float (TP distance, 0=no fixed TP)
                confidence: float (0.0-1.0)
        """
        pass

    @abstractmethod
    def default_params(self) -> dict:
        """Return default parameter values."""
        pass
