"""
Risk Management Module
FlashEASuite V2.1 - Option A

This module provides comprehensive risk management components:
- Position Sizing: 1% risk rule with ATR adjustment
- Daily Loss Limit: 4% daily limit with auto-stop
- Future additions: Volatility adjustment, exposure management, etc.

Author: Dr. Suksaeng Kukanok
Version: 2.10
Date: December 23, 2025
"""

from .position_sizing import PositionSizingManager
from .daily_loss_limit import DailyLossLimit

__version__ = '2.10'
__author__ = 'Dr. Suksaeng Kukanok'

__all__ = [
    'PositionSizingManager',
    'DailyLossLimit',
]

# Module info
print(f"✅ Risk Management Module v{__version__} loaded")
