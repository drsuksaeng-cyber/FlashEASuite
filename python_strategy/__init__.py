#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Strategy Package
WITH FEEDBACK LOOP 🔄

Modular strategy engine with:
- Market analysis
- Feedback processing
- Policy generation
- Risk management
"""

from .engine import StrategyEngineThreaded, create_strategy_engine_threaded

__all__ = [
    'StrategyEngineThreaded',
    'create_strategy_engine_threaded'
]

__version__ = '2.0.0'
__author__ = 'FlashEASuite Team'
