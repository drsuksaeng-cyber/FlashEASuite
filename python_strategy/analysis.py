#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Market Analysis Module
Handles tick analysis and signal generation
"""

from typing import Dict, Any, Optional
from collections import deque


class MarketAnalyzer:
    """
    Market analysis module for generating trading signals.
    
    Analyzes:
    - Tick flow patterns
    - Currency strength
    - Market conditions
    """
    
    def __init__(self, has_modules: bool = False):
        """
        Initialize Market Analyzer.
        
        Args:
            has_modules: Whether tick_analyzer and currency_meter are available
        """
        self.has_modules = has_modules
        
        # Initialize modules if available
        if has_modules:
            try:
                from modules.tick_analyzer import TickFlowAnalyzer
                from modules.currency_meter import CurrencyStrengthMeter
                
                # Try with window_size parameter first
                try:
                    self.tick_analyzer = TickFlowAnalyzer(window_size=100)
                except TypeError:
                    # If doesn't support window_size, create without it
                    self.tick_analyzer = TickFlowAnalyzer()
                
                try:
                    self.csm = CurrencyStrengthMeter()
                except Exception as e:
                    print(f"⚠️ CSM initialization warning: {e}")
                    self.csm = None
                    
            except ImportError as e:
                print(f"⚠️ Failed to import modules: {e}")
                self.tick_analyzer = None
                self.csm = None
        else:
            self.tick_analyzer = None
            self.csm = None
    
    def analyze_market(
        self,
        tick_data: Dict[str, Any],
        tick_buffer: deque,
        is_in_cooldown: bool
    ) -> Optional[str]:
        """
        Analyze market and generate signal.
        
        Args:
            tick_data: Current tick data dictionary
            tick_buffer: Historical tick buffer
            is_in_cooldown: Whether system is in cooldown
            
        Returns:
            'BUY', 'SELL', or None
        """
        # Check cooldown first
        if is_in_cooldown:
            return None
        
        # Basic analysis
        symbol = tick_data.get('symbol', '')
        bid = tick_data.get('bid', 0.0)
        ask = tick_data.get('ask', 0.0)
        
        # Use modules if available
        if self.has_modules and len(tick_buffer) > 10:
            # Use TickAnalyzer
            if self.tick_analyzer:
                self.tick_analyzer.add_tick(bid)
            
            # Use CSM (simplified - actual implementation is more complex)
            # This is just a placeholder
            pass
        
        # Return None for now (no signal)
        # In production, implement your strategy logic here
        return None
    
    def get_tick_analyzer(self):
        """Get tick analyzer instance."""
        return self.tick_analyzer
    
    def get_csm(self):
        """Get Currency Strength Meter instance."""
        return self.csm
