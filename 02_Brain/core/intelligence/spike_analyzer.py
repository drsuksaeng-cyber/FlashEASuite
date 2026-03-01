#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Spike Analyzer (Real-Time Detection)
Location: 02_Brain/core/intelligence/spike_analyzer.py

Detects spikes in real-time tick data using 7 factors.

Author: Dr. Suksaeng Kukanok
Date: 2026-01-30
"""

import numpy as np
from typing import Dict, Optional
from collections import deque
import logging

logger = logging.getLogger(__name__)


class SpikeAnalyzer:
    """
    Real-time spike detection using 7-factor analysis.
    
    Designed for low-latency analysis of incoming tick data.
    """
    
    def __init__(self, buffer_size: int = 1000):
        """
        Initialize spike analyzer.
        
        Args:
            buffer_size: Size of price history buffer
        """
        self.buffer_size = buffer_size
        
        # Price buffers per symbol
        self.price_buffers = {}  # symbol -> deque of prices
        self.volume_buffers = {}  # symbol -> deque of volumes
        self.time_buffers = {}  # symbol -> deque of timestamps
        
        # Latest calculations per symbol
        self.latest_atr = {}
        self.latest_adx = {}
        
    def _ensure_buffers(self, symbol: str):
        """Ensure buffers exist for symbol."""
        if symbol not in self.price_buffers:
            self.price_buffers[symbol] = deque(maxlen=self.buffer_size)
            self.volume_buffers[symbol] = deque(maxlen=self.buffer_size)
            self.time_buffers[symbol] = deque(maxlen=self.buffer_size)
    
    def update_tick(self, symbol: str, price: float, volume: int, timestamp: int):
        """
        Update buffers with new tick.
        
        Args:
            symbol: Symbol name
            price: Tick price
            volume: Tick volume
            timestamp: Tick timestamp (milliseconds)
        """
        self._ensure_buffers(symbol)
        
        self.price_buffers[symbol].append(price)
        self.volume_buffers[symbol].append(volume)
        self.time_buffers[symbol].append(timestamp)
    
    def calculate_roc(self, symbol: str, period: int = 10) -> float:
        """
        Calculate Rate of Change.
        
        Args:
            symbol: Symbol name
            period: ROC period
        
        Returns:
            ROC percentage
        """
        try:
            prices = list(self.price_buffers[symbol])
            
            if len(prices) < period + 1:
                return 0.0
            
            current = prices[-1]
            old = prices[-period-1]
            
            if old == 0:
                return 0.0
            
            roc = ((current - old) / old) * 100.0
            
            return roc
            
        except Exception as e:
            logger.error(f"Error calculating ROC for {symbol}: {e}")
            return 0.0
    
    def calculate_atr(self, symbol: str, period: int = 14) -> float:
        """
        Calculate ATR from price buffer.
        
        Args:
            symbol: Symbol name
            period: ATR period
        
        Returns:
            ATR value
        """
        try:
            prices = list(self.price_buffers[symbol])
            
            if len(prices) < period + 1:
                return 0.0
            
            # Simplified ATR using price ranges
            ranges = []
            for i in range(1, min(period + 1, len(prices))):
                range_val = abs(prices[-i] - prices[-i-1])
                ranges.append(range_val)
            
            atr = np.mean(ranges) if ranges else 0.0
            
            # Cache for later use
            self.latest_atr[symbol] = atr
            
            return atr
            
        except Exception as e:
            logger.error(f"Error calculating ATR for {symbol}: {e}")
            return 0.0
    
    def detect_volume_spike(self, symbol: str, multiplier: float = 1.5, period: int = 20) -> bool:
        """
        Detect if current volume is a spike.
        
        Args:
            symbol: Symbol name
            multiplier: Volume spike multiplier
            period: Period to calculate average
        
        Returns:
            True if volume spike detected
        """
        try:
            volumes = list(self.volume_buffers[symbol])
            
            if len(volumes) < period + 1:
                return False
            
            current_vol = volumes[-1]
            avg_vol = np.mean(volumes[-period-1:-1])
            
            if avg_vol == 0:
                return False
            
            is_spike = current_vol >= (avg_vol * multiplier)
            
            return is_spike
            
        except Exception as e:
            logger.error(f"Error detecting volume spike for {symbol}: {e}")
            return False
    
    def calculate_tick_density(self, symbol: str, seconds: int = 10) -> float:
        """
        Calculate tick density (ticks per time period).
        
        Args:
            symbol: Symbol name
            seconds: Time window in seconds
        
        Returns:
            Density ratio
        """
        try:
            times = list(self.time_buffers[symbol])
            
            if len(times) < 2:
                return 0.0
            
            current_time = times[-1]
            cutoff_time = current_time - (seconds * 1000)  # Convert to ms
            
            # Count ticks in window
            ticks_in_window = sum(1 for t in times if t >= cutoff_time)
            
            # Calculate average ticks per window
            if len(times) < 100:
                avg_ticks = len(times) / 10  # Rough estimate
            else:
                avg_ticks = len(times) / ((times[-1] - times[0]) / (seconds * 1000))
            
            if avg_ticks == 0:
                return 0.0
            
            density = ticks_in_window / avg_ticks
            
            return density
            
        except Exception as e:
            logger.error(f"Error calculating density for {symbol}: {e}")
            return 0.0
    
    def calculate_zscore(self, symbol: str, current_change: float, period: int = 100) -> float:
        """
        Calculate Z-Score for price change.
        
        Args:
            symbol: Symbol name
            current_change: Current price change
            period: Period for mean/std calculation
        
        Returns:
            Z-Score value
        """
        try:
            prices = list(self.price_buffers[symbol])
            
            if len(prices) < period + 1:
                return 0.0
            
            # Calculate price changes
            changes = []
            for i in range(1, min(period + 1, len(prices))):
                change = prices[-i] - prices[-i-1]
                changes.append(change)
            
            mean = np.mean(changes)
            std_dev = np.std(changes)
            
            if std_dev == 0:
                return 0.0
            
            zscore = (current_change - mean) / std_dev
            
            return zscore
            
        except Exception as e:
            logger.error(f"Error calculating Z-Score for {symbol}: {e}")
            return 0.0
    
    def analyze_spike_condition(self, tick_data: Dict) -> Dict:
        """
        Comprehensive spike analysis for a tick.
        
        Args:
            tick_data: Dictionary with tick information
                      {
                          'symbol': str,
                          'bid': float,
                          'ask': float,
                          'volume': int,
                          'timestamp': int,
                          'spread': float (optional)
                      }
        
        Returns:
            Analysis result:
            {
                'detected': bool,
                'score': float (0-100),
                'direction': str ('BUY'/'SELL'/'NEUTRAL'),
                'confidence': float (0-1),
                'factors': {
                    'roc': float,
                    'atr': float,
                    'volume_spike': bool,
                    'density': float,
                    'zscore': float
                }
            }
        """
        try:
            symbol = tick_data['symbol']
            price = (tick_data['bid'] + tick_data['ask']) / 2
            volume = tick_data.get('volume', 0)
            timestamp = tick_data['timestamp']
            
            # Update buffers
            self.update_tick(symbol, price, volume, timestamp)
            
            # Check if we have enough data
            if len(self.price_buffers[symbol]) < 20:
                return {
                    'detected': False,
                    'score': 0.0,
                    'direction': 'NEUTRAL',
                    'confidence': 0.0,
                    'factors': {}
                }
            
            # Calculate factors
            roc = self.calculate_roc(symbol, period=10)
            atr = self.calculate_atr(symbol, period=14)
            volume_spike = self.detect_volume_spike(symbol, multiplier=1.5)
            density = self.calculate_tick_density(symbol, seconds=10)
            
            # Current price move
            prices = list(self.price_buffers[symbol])
            price_move = abs(prices[-1] - prices[-11]) if len(prices) > 11 else 0
            zscore = self.calculate_zscore(symbol, price_move, period=100)
            
            # Scoring
            score = 0.0
            
            # Factor 1: ATR-based spike (40 points)
            if atr > 0:
                spike_ratio = price_move / atr
                if spike_ratio >= 2.0:
                    score += 40
                elif spike_ratio >= 1.5:
                    score += 30
                elif spike_ratio >= 1.0:
                    score += 20
            
            # Factor 2: ROC momentum (30 points)
            if abs(roc) >= 0.6:
                score += 30
            elif abs(roc) >= 0.5:
                score += 25
            elif abs(roc) >= 0.4:
                score += 15
            
            # Factor 3: Volume spike (10 points)
            if volume_spike:
                score += 10
            
            # Factor 4: Tick density (20 points)
            if density >= 3.5:
                score += 20
            elif density >= 3.0:
                score += 15
            elif density >= 2.5:
                score += 10
            
            # Bonus: Z-Score (optional +10)
            if abs(zscore) >= 2.0:
                score += 10
            
            # Determine direction
            if roc > 0.1:
                direction = 'BUY'
            elif roc < -0.1:
                direction = 'SELL'
            else:
                direction = 'NEUTRAL'
            
            # Detection threshold
            detected = score >= 70
            
            # Confidence
            confidence = min(score / 100.0, 1.0)
            
            return {
                'detected': detected,
                'score': round(score, 2),
                'direction': direction,
                'confidence': round(confidence, 2),
                'factors': {
                    'roc': round(roc, 4),
                    'atr': round(atr, 6),
                    'price_move': round(price_move, 6),
                    'volume_spike': volume_spike,
                    'density': round(density, 2),
                    'zscore': round(zscore, 2)
                }
            }
            
        except Exception as e:
            logger.error(f"Error analyzing spike condition: {e}")
            return {
                'detected': False,
                'score': 0.0,
                'direction': 'NEUTRAL',
                'confidence': 0.0,
                'factors': {}
            }


def analyze_spike_condition(tick_data: Dict) -> Dict:
    """
    Convenience function for spike analysis.
    
    Args:
        tick_data: Tick data dictionary
    
    Returns:
        Analysis result
    """
    # Use global analyzer instance (stateful)
    global _spike_analyzer
    
    if '_spike_analyzer' not in globals():
        _spike_analyzer = SpikeAnalyzer()
    
    return _spike_analyzer.analyze_spike_condition(tick_data)


if __name__ == "__main__":
    # Example usage
    print("Spike Analyzer - Example")
    print("=" * 60)
    
    analyzer = SpikeAnalyzer()
    
    # Simulate ticks
    for i in range(100):
        tick = {
            'symbol': 'GBPJPY',
            'bid': 195.50 + (i * 0.01),
            'ask': 195.52 + (i * 0.01),
            'volume': 100 + (i * 2),
            'timestamp': 1738220400000 + (i * 1000)
        }
        
        result = analyzer.analyze_spike_condition(tick)
        
        if result['detected']:
            print(f"\n🚨 SPIKE DETECTED at tick {i}!")
            print(f"Score: {result['score']}")
            print(f"Direction: {result['direction']}")
            print(f"Factors: {result['factors']}")
