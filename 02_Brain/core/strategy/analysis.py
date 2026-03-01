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
                self.tick_analyzer.on_tick(bid, ask)
            
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


# ============================================================================
# NEW: Function required by engine.py for Spike Strategy integration
# ============================================================================

def analyze_market_condition(
    tick_data: Dict[str, Any],
    price_history: Optional[list] = None,
    **kwargs
) -> Dict[str, Any]:
    """
    Analyze market condition from tick data.
    
    This function is used by the Strategy Engine for simple market analysis.
    For Grid strategy, more complex analysis is done in the Grid module itself.
    For Spike strategy, this provides basic trend/volatility info.
    
    Args:
        tick_data: Dict containing symbol, bid, ask, timestamp
        price_history: Optional list of recent prices
        **kwargs: Additional parameters (ignored)
        
    Returns:
        Dict with market analysis:
        {
            'symbol': str,
            'price': float,
            'bid': float,
            'ask': float,
            'spread': float,
            'spread_pct': float,
            'trend': str,  # 'BUY', 'SELL', 'NEUTRAL'
            'volatility': float,
            'confidence': float,
            'timestamp': int
        }
    """
    # Extract tick data
    symbol = tick_data.get('symbol', 'UNKNOWN')
    bid = tick_data.get('bid', 0.0)
    ask = tick_data.get('ask', 0.0)
    timestamp = tick_data.get('timestamp', 0)
    
    # Calculate spread
    spread = ask - bid
    spread_pct = (spread / bid * 100) if bid > 0 else 0.0
    
    # Calculate mid price
    mid_price = (bid + ask) / 2
    
    # Default values
    trend = 'NEUTRAL'
    volatility = 0.0
    confidence = 0.5  # Default medium confidence
    
    # Analyze trend if we have price history
    if price_history and len(price_history) >= 10:
        recent_prices = price_history[-10:]
        
        # Calculate simple moving average
        sma = sum(recent_prices) / len(recent_prices)
        
        # Determine trend based on current price vs SMA
        if mid_price > sma * 1.001:  # 0.1% above SMA
            trend = 'BUY'
            # Calculate confidence based on distance from SMA
            distance = (mid_price - sma) / sma
            confidence = min(0.8, 0.5 + distance * 100)
            
        elif mid_price < sma * 0.999:  # 0.1% below SMA
            trend = 'SELL'
            # Calculate confidence based on distance from SMA
            distance = (sma - mid_price) / sma
            confidence = min(0.8, 0.5 + distance * 100)
        
        # Calculate volatility (standard deviation of recent prices)
        if len(recent_prices) >= 2:
            mean = sum(recent_prices) / len(recent_prices)
            variance = sum((x - mean) ** 2 for x in recent_prices) / len(recent_prices)
            volatility = variance ** 0.5
            
            # Normalize volatility as percentage
            if mean > 0:
                volatility = (volatility / mean) * 100
    
    # Return analysis result
    return {
        'symbol': symbol,
        'price': mid_price,
        'bid': bid,
        'ask': ask,
        'spread': spread,
        'spread_pct': spread_pct,
        'trend': trend,
        'volatility': volatility,
        'confidence': confidence,
        'timestamp': timestamp
    }
