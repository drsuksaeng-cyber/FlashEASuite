#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Policy Generator (Updated with Spike Strategy)
Location: 02_Brain/core/strategy/policy.py

Generates trading policies for Grid and Spike strategies.

Author: Dr. Suksaeng Kukanok
Date: 2026-01-30 (Updated for Spike)
"""

import msgpack
import uuid
import time
from typing import Dict, Optional
import logging

logger = logging.getLogger(__name__)


class PolicyPublisher:
    """
    Publishes trading policies to MQL5 Trader via ZMQ.
    
    Supports multiple strategies:
    - Grid: Range-bound grid trading
    - Spike: High-frequency spike hunting
    """
    
    def __init__(self, zmq_socket):
        """
        Initialize policy publisher.
        
        Args:
            zmq_socket: ZMQ PUB socket for broadcasting policies
        """
        self.socket = zmq_socket
        self.sequence_counter = {}  # Per symbol sequence
        
    def generate_grid_policy(self, market_signal: Dict, risk_params: Dict) -> Optional[list]:
        """
        Generate Grid strategy policy.
        
        Args:
            market_signal: Market analysis results
            risk_params: Risk management parameters
        
        Returns:
            Grid policy ARRAY or None (MessagePack array format for MQL5)
            
        Format matches MQL5 Serialization.mqh (11 elements):
            [0]  type           (int)    = 2 (POLICY)
            [1]  timestamp_ms   (int64)  = milliseconds
            [2]  symbol         (string) = "XAUUSD.tp"
            [3]  strategy       (string) = "Grid" or "Spike"
            [4]  entry_price    (double)
            [5]  lot_size       (double)
            [6]  max_orders     (int)
            [7]  take_profit    (double)
            [8]  stop_loss      (double)
            [9]  confidence     (double) 0.0-1.0
            [10] risk_multiplier (double)
        """
        try:
            symbol = market_signal['symbol']
            
            # Grid-specific logic
            if not market_signal.get('is_ranging', False):
                logger.debug(f"Market not ranging for {symbol}, skip Grid policy")
                return None
            
            # Increment sequence
            if symbol not in self.sequence_counter:
                self.sequence_counter[symbol] = 0
            self.sequence_counter[symbol] += 1
            
            # Get current market prices
            current_price = market_signal.get('current_price', 0.0)
            bid = market_signal.get('bid', current_price)
            ask = market_signal.get('ask', current_price)
            entry_price = (bid + ask) / 2.0 if bid > 0 and ask > 0 else current_price
            
            # Calculate TP/SL based on grid spacing
            grid_spacing_points = market_signal.get('grid_spacing', 50)
            point_size = market_signal.get('point_size', 0.0001)  # Default for forex
            
            # For grid: TP = entry + spacing, SL = entry - spacing
            tp = entry_price + (grid_spacing_points * point_size)
            sl = entry_price - (grid_spacing_points * point_size)
            
            # Lot size
            lot_size = market_signal.get('lot_size', 0.01)
            
            # Risk
            risk_multiplier = risk_params.get('risk_multiplier', 1.0)
            confidence = market_signal.get('confidence', 0.5)
            
            # Max orders for grid
            max_orders = market_signal.get('grid_levels', 5)
            
            # Current timestamp (MILLISECONDS for MQL5)
            timestamp = int(time.time() * 1000)
            
            # 🔥 CRITICAL: Create ARRAY format matching MQL5 Serialization.mqh line 227-238
            policy = [
                2,                   # [0] type = 2 (POLICY)
                timestamp,           # [1] timestamp_ms (int64)
                symbol,              # [2] symbol (string)
                "Grid",              # [3] strategy (string)
                entry_price,         # [4] entry_price (double)
                lot_size,            # [5] lot_size (double)
                max_orders,          # [6] max_orders (int)
                tp,                  # [7] take_profit (double)
                sl,                  # [8] stop_loss (double)
                confidence,          # [9] confidence (double)
                risk_multiplier      # [10] risk_multiplier (double)
            ]
            
            logger.info(f"✅ Generated Grid policy for {symbol} (seq: {self.sequence_counter[symbol]}) - Entry: {entry_price:.5f}, TP: {tp:.5f}, SL: {sl:.5f}, Lots: {lot_size}")
            return policy
            
        except Exception as e:
            logger.error(f"Error generating Grid policy: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def generate_spike_policy(self, market_signal: Dict, risk_params: Dict) -> Optional[list]:
        """
        Generate Spike strategy policy (NEW).
        
        Args:
            market_signal: Market analysis with spike detection
            risk_params: Risk management parameters
        
        Returns:
            Spike policy ARRAY or None (MessagePack array format for MQL5)
            
        Format matches MQL5 Serialization.mqh (11 elements):
            [0]  type           (int)    = 2 (POLICY)
            [1]  timestamp_ms   (int64)  = milliseconds
            [2]  symbol         (string) = "XAUUSD.tp"
            [3]  strategy       (string) = "Grid" or "Spike"
            [4]  entry_price    (double)
            [5]  lot_size       (double)
            [6]  max_orders     (int)
            [7]  take_profit    (double)
            [8]  stop_loss      (double)
            [9]  confidence     (double) 0.0-1.0
            [10] risk_multiplier (double)
        """
        try:
            symbol = market_signal['symbol']
            spike_signal = market_signal.get('spike', {})
            
            # Check if spike detected
            if not spike_signal.get('detected', False):
                logger.debug(f"No spike detected for {symbol}")
                return None
            
            # Increment sequence
            if symbol not in self.sequence_counter:
                self.sequence_counter[symbol] = 0
            self.sequence_counter[symbol] += 1
            
            # Get spike direction
            direction = spike_signal.get('direction', 'NEUTRAL')
            if direction not in ['BUY', 'SELL']:
                logger.warning(f"Invalid spike direction: {direction}")
                return None
            
            # Get current market prices
            current_price = market_signal.get('current_price', 0.0)
            bid = market_signal.get('bid', current_price)
            ask = market_signal.get('ask', current_price)
            entry_price = ask if direction == 'BUY' else bid  # BUY at ask, SELL at bid
            
            # Calculate TP/SL based on ATR
            factors = spike_signal.get('factors', {})
            atr = factors.get('atr', 0.001)  # Default ATR
            atr_tp_mult = market_signal.get('atr_tp_mult', 0.8)
            atr_sl_mult = market_signal.get('atr_sl_mult', 0.4)
            
            if direction == 'BUY':
                tp = entry_price + (atr * atr_tp_mult)
                sl = entry_price - (atr * atr_sl_mult)
            else:  # SELL
                tp = entry_price - (atr * atr_tp_mult)
                sl = entry_price + (atr * atr_sl_mult)
            
            # Lot size
            lot_size = market_signal.get('lot_size', 0.01)
            
            # Risk
            risk_multiplier = risk_params.get('risk_multiplier', 1.0)
            confidence = spike_signal.get('confidence', 0.0)
            
            # Current timestamp (MILLISECONDS for MQL5)
            timestamp = int(time.time() * 1000)
            
            # 🔥 CRITICAL: Create ARRAY format matching MQL5 Serialization.mqh line 227-238
            policy = [
                2,                   # [0] type = 2 (POLICY)
                timestamp,           # [1] timestamp_ms (int64)
                symbol,              # [2] symbol (string)
                "Spike",             # [3] strategy (string)
                entry_price,         # [4] entry_price (double)
                lot_size,            # [5] lot_size (double)
                1,                   # [6] max_orders = 1 for spike (single order)
                tp,                  # [7] take_profit (double)
                sl,                  # [8] stop_loss (double)
                confidence,          # [9] confidence (double)
                risk_multiplier      # [10] risk_multiplier (double)
            ]
            
            logger.info(f"🚨 Generated Spike policy for {symbol} - {direction} (score: {spike_signal.get('score', 0):.1f}) - Entry: {entry_price:.5f}, TP: {tp:.5f}, SL: {sl:.5f}")
            return policy
            
        except Exception as e:
            logger.error(f"Error generating Spike policy: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def generate_policy(self, market_signal: Dict, risk_params: Dict) -> Optional[list]:
        """
        Main policy generation router.
        
        Routes to appropriate strategy based on market signal.
        
        Args:
            market_signal: Market analysis results
            risk_params: Risk management parameters
        
        Returns:
            Policy ARRAY (list) or None - MessagePack array format for MQL5
        """
        recommended_strategy = market_signal.get('recommended_strategy', 'Grid')
        
        if recommended_strategy == 'Spike':
            return self.generate_spike_policy(market_signal, risk_params)
        elif recommended_strategy == 'Grid':
            return self.generate_grid_policy(market_signal, risk_params)
        else:
            logger.warning(f"Unknown strategy: {recommended_strategy}")
            return None
    
    def publish_policy(self, policy: list) -> bool:
        """
        Serialize and publish policy via ZMQ.
        
        Args:
            policy: Policy ARRAY (list format, not dict)
        
        Returns:
            True if published successfully
        """
        try:
            # Serialize with MessagePack (array format)
            packed = msgpack.packb(policy)
            
            # Send via ZMQ
            self.socket.send(packed)
            
            # Extract symbol and strategy for logging
            symbol = policy[0] if len(policy) > 0 else "UNKNOWN"
            strategy = policy[1] if len(policy) > 1 else "UNKNOWN"
            
            logger.debug(f"📤 Published {strategy} policy for {symbol}")
            return True
            
        except Exception as e:
            logger.error(f"Error publishing policy: {e}")
            return False


def select_best_strategy(grid_signal: Dict, spike_signal: Dict) -> str:
    """
    Select best strategy based on market conditions.
    
    Args:
        grid_signal: Grid strategy signal
        spike_signal: Spike strategy signal
    
    Returns:
        Strategy name ('Grid' or 'Spike')
    """
    # Spike takes priority if detected with high confidence
    if spike_signal.get('detected', False):
        spike_confidence = spike_signal.get('confidence', 0.0)
        if spike_confidence >= 0.7:
            return 'Spike'
    
    # Grid if market is ranging
    if grid_signal.get('is_ranging', False):
        grid_confidence = grid_signal.get('confidence', 0.0)
        if grid_confidence >= 0.6:
            return 'Grid'
    
    # Default to Grid (safer)
    return 'Grid'


# ============================================================================
# Standalone Functions (for imports and testing)
# ============================================================================

def generate_spike_policy(market_signal: Dict, risk_params: Dict) -> Optional[list]:
    """
    Standalone function to generate Spike policy.
    
    Args:
        market_signal: Market signal with spike data
        risk_params: Risk parameters
        
    Returns:
        Spike policy ARRAY (list) or None
    """
    publisher = PolicyPublisher(None)
    return publisher.generate_spike_policy(market_signal, risk_params)


def generate_grid_policy(market_signal: Dict, risk_params: Dict) -> Optional[list]:
    """
    Standalone function to generate Grid policy.
    
    Args:
        market_signal: Market signal with grid data
        risk_params: Risk parameters
        
    Returns:
        Grid policy ARRAY (list) or None
    """
    publisher = PolicyPublisher(None)
    return publisher.generate_grid_policy(market_signal, risk_params)


def generate_policy(market_signal: Dict, risk_params: Dict, zmq_socket=None) -> Optional[list]:
    """
    Convenience function for policy generation.
    
    Args:
        market_signal: Market analysis
        risk_params: Risk parameters
        zmq_socket: ZMQ socket (optional)
    
    Returns:
        Policy ARRAY (list) or None
    """
    if zmq_socket:
        publisher = PolicyPublisher(zmq_socket)
        return publisher.generate_policy(market_signal, risk_params)
    else:
        # Return policy without publishing
        publisher = PolicyPublisher(None)
        return publisher.generate_policy(market_signal, risk_params)


if __name__ == "__main__":
    # Example usage
    print("Policy Generator - Example")
    print("=" * 60)
    
    # Example Grid signal
    grid_signal = {
        'symbol': 'EURUSD',
        'is_ranging': True,
        'confidence': 0.75,
        'grid_spacing': 50,
        'grid_levels': 5,
        'lot_size': 0.01
    }
    
    # Example Spike signal
    spike_signal = {
        'symbol': 'GBPJPY',
        'detected': True,
        'score': 85.0,
        'direction': 'BUY',
        'confidence': 0.85,
        'factors': {
            'roc': 0.65,
            'atr': 0.015,
            'volume_spike': True,
            'density': 3.8
        }
    }
    
    risk_params = {'risk_multiplier': 1.0}
    
    # Test Grid
    market_signal_grid = {
        'symbol': 'EURUSD',
        'recommended_strategy': 'Grid',
        **grid_signal
    }
    
    policy_grid = generate_policy(market_signal_grid, risk_params)
    print("\nGrid Policy:")
    print(policy_grid)
    
    # Test Spike
    market_signal_spike = {
        'symbol': 'GBPJPY',
        'recommended_strategy': 'Spike',
        'spike': spike_signal
    }
    
    policy_spike = generate_policy(market_signal_spike, risk_params)
    print("\nSpike Policy:")
    print(policy_spike)
